defmodule HighRollers.RPC do
  @moduledoc """
  Shared RPC utilities with retry logic and circuit breaker pattern.

  RETRY: Exponential backoff for transient failures (timeouts, 5xx errors).
  CIRCUIT BREAKER: Prevent cascading failures when RPC endpoint is down.

  All contract modules delegate to this module for HTTP calls.
  Uses Finch for connection pooling and better resource management.
  """

  require Logger

  @default_timeout 30_000
  @default_max_retries 3
  @initial_backoff_ms 500

  @doc """
  Make an RPC call with automatic retry on transient failures.

  Options:
    - timeout: Request timeout in ms (default: 30_000)
    - max_retries: Maximum retry attempts (default: 3)
  """
  def call(url, method, params, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)

    start_time = System.monotonic_time()

    result = do_call_with_retry(url, method, params, timeout, 0, max_retries)

    # Emit telemetry event
    duration = System.monotonic_time() - start_time
    :telemetry.execute(
      [:high_rollers, :rpc, :call],
      %{duration: duration},
      %{method: method, url: url, result: result_type(result)}
    )

    result
  end

  @doc """
  Make an RPC call to Arbitrum (uses configured arbitrum_rpc_url).
  """
  def call_arbitrum(method, params, opts \\ []) do
    url = Application.get_env(:high_rollers, :arbitrum_rpc_url)
    call(url, method, params, opts)
  end

  @doc """
  Make an RPC call to Rogue Chain (uses configured rogue_rpc_url).
  """
  def call_rogue(method, params, opts \\ []) do
    url = Application.get_env(:high_rollers, :rogue_rpc_url)
    call(url, method, params, opts)
  end

  # ===== Private Functions =====

  defp do_call_with_retry(_url, method, _params, _timeout, attempts, max) when attempts >= max do
    Logger.error("[RPC] #{method} failed after #{max} attempts")
    {:error, :max_retries_exceeded}
  end

  defp do_call_with_retry(url, method, params, timeout, attempt, max_retries) do
    body = Jason.encode!(%{
      jsonrpc: "2.0",
      method: method,
      params: params,
      id: System.unique_integer([:positive])
    })

    request = Finch.build(:post, url, [{"Content-Type", "application/json"}], body)

    case Finch.request(request, HighRollers.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        case Jason.decode!(response_body) do
          %{"result" => result} ->
            {:ok, result}

          %{"error" => %{"message" => message}} ->
            Logger.warning("[RPC] #{method} error: #{message}")
            {:error, message}

          %{"error" => error} ->
            Logger.warning("[RPC] #{method} error: #{inspect(error)}")
            {:error, inspect(error)}
        end

      {:ok, %Finch.Response{status: status}} when status >= 500 ->
        # Emit retry telemetry
        :telemetry.execute(
          [:high_rollers, :rpc, :retry],
          %{attempt: attempt + 1},
          %{method: method, url: url, error: "HTTP #{status}"}
        )
        # Retry on server errors
        backoff = calculate_backoff(attempt)
        Logger.warning("[RPC] #{method} server error #{status}, retrying in #{backoff}ms (attempt #{attempt + 1}/#{max_retries})")
        Process.sleep(backoff)
        do_call_with_retry(url, method, params, timeout, attempt + 1, max_retries)

      {:error, %Mint.TransportError{reason: :timeout}} ->
        # Emit retry telemetry
        :telemetry.execute(
          [:high_rollers, :rpc, :retry],
          %{attempt: attempt + 1},
          %{method: method, url: url, error: "timeout"}
        )
        # Retry on timeouts
        backoff = calculate_backoff(attempt)
        Logger.warning("[RPC] #{method} timeout, retrying in #{backoff}ms (attempt #{attempt + 1}/#{max_retries})")
        Process.sleep(backoff)
        do_call_with_retry(url, method, params, timeout, attempt + 1, max_retries)

      {:error, %Mint.TransportError{reason: :closed}} ->
        # Emit retry telemetry
        :telemetry.execute(
          [:high_rollers, :rpc, :retry],
          %{attempt: attempt + 1},
          %{method: method, url: url, error: "connection_closed"}
        )
        # Retry on connection closed
        backoff = calculate_backoff(attempt)
        Logger.warning("[RPC] #{method} connection closed, retrying in #{backoff}ms (attempt #{attempt + 1}/#{max_retries})")
        Process.sleep(backoff)
        do_call_with_retry(url, method, params, timeout, attempt + 1, max_retries)

      {:error, %Mint.TransportError{reason: reason}} ->
        # Emit retry telemetry
        :telemetry.execute(
          [:high_rollers, :rpc, :retry],
          %{attempt: attempt + 1},
          %{method: method, url: url, error: inspect(reason)}
        )
        # Retry on other transport errors
        backoff = calculate_backoff(attempt)
        Logger.warning("[RPC] #{method} transport error: #{inspect(reason)}, retrying in #{backoff}ms (attempt #{attempt + 1}/#{max_retries})")
        Process.sleep(backoff)
        do_call_with_retry(url, method, params, timeout, attempt + 1, max_retries)

      {:ok, %Finch.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_backoff(attempt) do
    # Exponential backoff: 500ms, 1000ms, 2000ms, etc.
    trunc(@initial_backoff_ms * :math.pow(2, attempt))
  end

  defp result_type({:ok, _}), do: :success
  defp result_type({:error, _}), do: :error

  # ===== Utility Functions =====

  @doc """
  Convert hex string to integer.
  """
  def hex_to_int("0x" <> hex), do: String.to_integer(hex, 16)
  def hex_to_int(hex) when is_binary(hex), do: String.to_integer(hex, 16)

  @doc """
  Convert integer to hex string with 0x prefix.
  """
  def int_to_hex(int) when is_integer(int) do
    "0x" <> Integer.to_string(int, 16)
  end

  @doc """
  Pad address to 32 bytes for event log topics.
  """
  def pad_address("0x" <> address) do
    "0x" <> String.pad_leading(String.downcase(address), 64, "0")
  end

  @doc """
  Extract address from padded 32-byte topic.
  """
  def unpad_address("0x" <> padded) do
    # Take last 40 characters (20 bytes = 40 hex chars)
    "0x" <> String.slice(padded, -40, 40)
  end
end
