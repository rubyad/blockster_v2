defmodule BlocksterV2Web.Plugs.V2RedirectPlug do
  @moduledoc """
  Redirects legacy domains (v2.blockster.com, blockster-v2.fly.dev) to blockster.com.
  Also redirects www.blockster.com to blockster.com for canonical URL.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.host in ["v2.blockster.com", "blockster-v2.fly.dev", "www.blockster.com"] do
      conn
      |> redirect(external: "https://blockster.com#{conn.request_path}")
      |> halt()
    else
      conn
    end
  end
end
