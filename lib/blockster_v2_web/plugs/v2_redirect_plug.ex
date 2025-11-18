defmodule BlocksterV2Web.Plugs.V2RedirectPlug do
  @moduledoc """
  Redirects root path to /waitlist when accessed from v2.blockster.com
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.request_path == "/" and conn.host == "v2.blockster.com" do
      conn
      |> redirect(to: "/waitlist")
      |> halt()
    else
      conn
    end
  end
end
