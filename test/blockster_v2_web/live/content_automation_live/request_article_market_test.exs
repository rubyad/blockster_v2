defmodule BlocksterV2Web.ContentAutomationLive.RequestArticleMarketTest do
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  import BlocksterV2.ContentAutomation.Factory

  setup do
    ensure_mnesia_tables()
    populate_altcoin_cache()
    :ok
  end

  defp create_admin(_) do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "admin_mkt_#{unique}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true,
        is_author: true
      })
      |> Repo.insert()

    %{admin: admin}
  end

  defp switch_to_market_movers(view) do
    render_change(view, "validate", %{"form" => %{
      "template" => "market_movers",
      "topic" => "",
      "instructions" => "",
      "category" => "altcoins",
      "content_type" => "news"
    }})

    # Market movers triggers async fetch — wait for it
    render_async(view)
  end

  defp switch_to_narrative(view, sector \\ "ai") do
    render_change(view, "validate", %{"form" => %{
      "template" => "narrative_analysis",
      "topic" => "",
      "instructions" => "",
      "category" => "altcoins",
      "content_type" => "opinion",
      "sector" => sector
    }})

    # Narrative triggers async fetch — wait for it
    render_async(view)
  end

  describe "market_movers template" do
    setup [:create_admin]

    test "submit button says Generate Market Analysis", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_market_movers(view)

      assert html =~ "Generate Market Analysis"
    end

    test "hides topic field", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_market_movers(view)

      # Topic is auto-generated for market movers
      refute html =~ ~s(name="form[topic]" type="text")
    end

    test "shows market data description", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_market_movers(view)

      assert html =~ "data-driven analysis"
      assert html =~ "CoinGecko"
    end

    test "instructions label shows 'Market Data'", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_market_movers(view)

      assert html =~ "Market Data"
    end

    test "auto-populates instructions with market data", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_market_movers(view)

      # Instructions should be populated with formatted market data
      assert html =~ "MARKET DATA" or html =~ "GAINERS" or html =~ "BTC" or html =~ "SOL"
    end

    test "validates market data is required", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_submit(view, "generate", %{"form" => %{
        "template" => "market_movers",
        "topic" => "market_movers",
        "instructions" => "",
        "category" => "altcoins",
        "content_type" => "news"
      }})

      assert html =~ "Market data is required"
    end

    test "hides angle field", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_market_movers(view)

      refute html =~ "Angle / Perspective"
    end

    test "auto-sets category to altcoins", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_market_movers(view)

      assert html =~ ~s(value="altcoins")
    end
  end

  describe "narrative_analysis template" do
    setup [:create_admin]

    test "submit button says Generate Narrative Report", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_narrative(view)

      assert html =~ "Generate Narrative Report"
    end

    test "shows sector dropdown", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_narrative(view)

      assert html =~ "Sector"
      assert html =~ "AI / Artificial Intelligence"
      assert html =~ "DeFi"
      assert html =~ "Layer 1"
      assert html =~ "Layer 2"
      assert html =~ "Gaming"
      assert html =~ "Real World Assets"
      assert html =~ "Meme Coins"
      assert html =~ "DePIN"
    end

    test "shows narrative description", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_narrative(view)

      assert html =~ "sector rotation"
    end

    test "instructions label shows 'Sector Data'", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_narrative(view)

      assert html =~ "Sector Data"
    end

    test "validates sector data is required", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_submit(view, "generate", %{"form" => %{
        "template" => "narrative_analysis",
        "topic" => "AI Sector Rally",
        "instructions" => "",
        "category" => "altcoins",
        "content_type" => "opinion",
        "sector" => "ai"
      }})

      assert html =~ "Sector data is required"
    end

    test "auto-sets content_type to opinion", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_narrative(view)

      assert html =~ ~s(value="opinion")
    end
  end
end
