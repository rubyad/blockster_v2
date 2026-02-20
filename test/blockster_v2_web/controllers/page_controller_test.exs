defmodule BlocksterV2Web.PageControllerTest do
  use BlocksterV2Web.ConnCase

  test "GET /profile redirects unauthenticated users to login", %{conn: conn} do
    conn = get(conn, ~p"/profile")
    assert redirected_to(conn) =~ "/login"
  end
end
