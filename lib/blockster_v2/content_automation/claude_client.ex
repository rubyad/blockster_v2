defmodule BlocksterV2.ContentAutomation.ClaudeClient do
  @moduledoc """
  HTTP client for the Anthropic Claude API with structured output via tool_use.
  Handles retries on 429 (rate limit) with exponential backoff.

  Used by:
  - TopicEngine: Claude Haiku for topic clustering (low temp, fast)
  - ContentGenerator: Claude Opus for article generation (higher temp, creative)
  """

  require Logger

  alias BlocksterV2.ContentAutomation.Config

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"

  @doc """
  Call Claude with tool_use for structured output.
  Forces tool use so the response always matches the provided schema.

  Returns {:ok, tool_input_map} or {:error, reason}.

  ## Options
  - `:model` - Claude model ID (default: claude-opus-4-6)
  - `:temperature` - 0.0-1.0 (default: 0.7)
  - `:max_tokens` - max response tokens (default: 4096)
  """
  def call_with_tools(prompt, tools, opts \\ []) do
    model = Keyword.get(opts, :model, Config.content_model())
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    retry_count = Keyword.get(opts, :_retry_count, 0)

    api_key = Config.anthropic_api_key()

    unless api_key do
      {:error, "ANTHROPIC_API_KEY not configured"}
    else
      body = %{
        "model" => model,
        "max_tokens" => max_tokens,
        "temperature" => temperature,
        "tools" => tools,
        "tool_choice" => %{"type" => "any"},
        "messages" => [%{"role" => "user", "content" => prompt}]
      }

      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", @api_version},
        {"content-type", "application/json"}
      ]

      case Req.post(@api_url,
        json: body,
        headers: headers,
        receive_timeout: 90_000,
        connect_options: [timeout: 15_000]
      ) do
        {:ok, %{status: 200, body: %{"content" => content}}} ->
          extract_tool_result(content)

        {:ok, %{status: 429}} when retry_count < 2 ->
          backoff = :timer.seconds(5 * (retry_count + 1))
          Logger.warning("[ClaudeClient] Rate limited (429), retrying in #{div(backoff, 1000)}s (attempt #{retry_count + 1})")
          Process.sleep(backoff)
          call_with_tools(prompt, tools, Keyword.put(opts, :_retry_count, retry_count + 1))

        {:ok, %{status: 429}} ->
          Logger.error("[ClaudeClient] Rate limited (429) after #{retry_count} retries, giving up")
          {:error, :rate_limited}

        {:ok, %{status: 529}} when retry_count < 2 ->
          # API overloaded
          backoff = :timer.seconds(10 * (retry_count + 1))
          Logger.warning("[ClaudeClient] API overloaded (529), retrying in #{div(backoff, 1000)}s")
          Process.sleep(backoff)
          call_with_tools(prompt, tools, Keyword.put(opts, :_retry_count, retry_count + 1))

        {:ok, %{status: status, body: body}} ->
          Logger.error("[ClaudeClient] API returned #{status}: #{inspect(body)}")
          {:error, "Claude API returned #{status}"}

        {:error, %Req.TransportError{reason: reason}} when reason in [:closed, :timeout] and retry_count < 2 ->
          backoff = :timer.seconds(3 * (retry_count + 1))
          Logger.warning("[ClaudeClient] Transport error (#{reason}), retrying in #{div(backoff, 1000)}s (attempt #{retry_count + 1})")
          Process.sleep(backoff)
          call_with_tools(prompt, tools, Keyword.put(opts, :_retry_count, retry_count + 1))

        {:error, reason} ->
          Logger.error("[ClaudeClient] Request failed: #{inspect(reason)}")
          {:error, "Claude API request failed: #{inspect(reason)}"}
      end
    end
  end

  # Extract the tool_use input from Claude's response content blocks
  defp extract_tool_result(content) when is_list(content) do
    case Enum.find(content, &(&1["type"] == "tool_use")) do
      %{"input" => input} -> {:ok, input}
      nil -> {:error, "No tool_use block in response"}
    end
  end

  defp extract_tool_result(_), do: {:error, "Unexpected response format"}
end
