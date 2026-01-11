defmodule HighRollersWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limiting plug using Hammer library.

  Default: 100 requests per minute
  Sensitive operations (withdrawals): 10 requests per minute

  Rate limits are keyed by wallet address (from X-Wallet-Address header)
  or IP address if no wallet header is present.

  ## Usage in router.ex

      pipeline :api do
        plug :accepts, ["json"]
        plug HighRollersWeb.Plugs.RateLimit, limit: 100, window_ms: 60_000
      end

      pipeline :api_sensitive do
        plug :accepts, ["json"]
        plug HighRollersWeb.Plugs.RateLimit, limit: 10, window_ms: 60_000
      end
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @default_limit 100  # requests
  @default_window_ms 60_000  # 1 minute

  def init(opts), do: opts

  def call(conn, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    window = Keyword.get(opts, :window_ms, @default_window_ms)
    key = rate_limit_key(conn)

    case Hammer.check_rate(key, window, limit) do
      {:allow, _count} ->
        conn

      {:deny, retry_after} ->
        retry_seconds = div(retry_after, 1000)
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_seconds))
        |> put_status(429)
        |> json(%{error: "Rate limit exceeded", retry_after_seconds: retry_seconds})
        |> halt()
    end
  end

  defp rate_limit_key(conn) do
    # Use wallet address if available, otherwise IP
    case get_req_header(conn, "x-wallet-address") do
      [address] when is_binary(address) and address != "" ->
        "wallet:#{String.downcase(address)}"

      _ ->
        "ip:#{format_ip(conn.remote_ip)}"
    end
  end

  defp format_ip(ip) when is_tuple(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
  end
  defp format_ip(ip), do: to_string(ip)
end
