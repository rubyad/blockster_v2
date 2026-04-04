defmodule BlocksterV2Web.PageControllerTest do
  use BlocksterV2Web.ConnCase

  test "GET /profile redirects unauthenticated users to homepage", %{conn: conn} do
    conn = get(conn, ~p"/profile")
    assert redirected_to(conn) =~ "/"
  end

  test "GET /login redirects to homepage", %{conn: conn} do
    conn = get(conn, "/login")
    assert redirected_to(conn) == "/"
  end
end
