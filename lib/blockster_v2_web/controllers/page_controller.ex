defmodule BlocksterV2Web.PageController do
  use BlocksterV2Web, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
