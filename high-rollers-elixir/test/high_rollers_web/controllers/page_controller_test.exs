defmodule HighRollersWeb.PageControllerTest do
  use HighRollersWeb.ConnCase

  test "GET / redirects to LiveView mint page", %{conn: conn} do
    conn = get(conn, ~p"/")
    # The root route serves MintLive via LiveView, which returns a 200
    assert html_response(conn, 200) =~ "High Rollers"
  end
end
