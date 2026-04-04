defmodule BlocksterV2Web.PoolIndexLiveTest do
  use BlocksterV2Web.LiveCase, async: false

  # ============================================================================
  # Page Render Tests
  # ============================================================================

  describe "page render" do
    test "renders pool index page with both pool cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "Liquidity Pools"
      assert html =~ "SOL Pool"
      assert html =~ "BUX Pool"
      assert html =~ "Enter Pool"
    end

    test "renders how it works section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "How it works"
      assert html =~ "Deposit"
      assert html =~ "Earn"
      assert html =~ "Withdraw"
    end

    test "renders back to play link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "Back to Play"
      assert html =~ ~s(href="/play")
    end

    test "renders enter pool links to vault pages", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ ~s(href="/pool/sol")
      assert html =~ ~s(href="/pool/bux")
    end

    test "renders loading skeleton state on initial mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      # Pool stats haven't loaded yet, so skeleton cells are shown
      assert html =~ "animate-pulse"
    end

    test "renders live indicator dots", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "Live"
      assert html =~ "animate-ping"
    end
  end

  # ============================================================================
  # Navigation Tests
  # ============================================================================

  describe "navigation" do
    test "enter pool navigates to SOL vault page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pool")

      # Find the SOL Enter Pool link
      assert view
             |> element("a[href=\"/pool/sol\"]")
             |> has_element?()
    end

    test "enter pool navigates to BUX vault page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pool")

      assert view
             |> element("a[href=\"/pool/bux\"]")
             |> has_element?()
    end
  end
end
