defmodule HighRollersWeb.PageController do
  use HighRollersWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
