defmodule BlocksterV2Web.ContentAutomationLive.RequestArticleTest do
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  import BlocksterV2.ContentAutomation.Factory

  setup do
    ensure_mnesia_tables()
    :ok
  end

  defp create_admin(_) do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "admin_req_#{unique}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true,
        is_author: true
      })
      |> Repo.insert()

    %{admin: admin}
  end

  describe "mount" do
    setup [:create_admin]

    test "renders request article page for admin", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/request")

      assert html =~ "Request Article"
      assert html =~ "Generate an article on any topic"
    end

    test "defaults to custom template", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/request")

      # Custom template should be selected by default
      assert html =~ "Custom Article"
      # Should show topic field
      assert html =~ "Topic / Headline"
      # Should show content type and category selectors
      assert html =~ "Content Type"
      assert html =~ "Category"
    end

    test "shows generate button", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/request")

      assert html =~ "Generate Article"
    end

    test "shows dashboard back link", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      assert has_element?(view, "a[href='/admin/content']")
    end
  end

  describe "access control" do
    test "redirects non-admin user", %{conn: conn} do
      {:ok, user} =
        %User{}
        |> Ecto.Changeset.change(%{
          email: "nonadmin_req@test.com",
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          is_admin: false
        })
        |> Repo.insert()

      conn = log_in_user(conn, user)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/content/request")
    end
  end

  describe "template switching" do
    setup [:create_admin]

    test "switching to blockster_of_week shows X handle field", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_change(view, "validate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "opinion"
      }})

      assert html =~ "X/Twitter Handle"
      assert html =~ "Person&#39;s Name"
      assert html =~ "Role / Title"
      assert html =~ "Generate Profile"
    end

    test "switching to event_preview shows event fields", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_change(view, "validate", %{"form" => %{
        "template" => "event_preview",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "opinion"
      }})

      assert html =~ "Event Date(s)"
      assert html =~ "Location"
      assert html =~ "Event URL"
      assert html =~ "Event Name"
      assert html =~ "Generate Event Preview"
    end

    test "switching to narrative_analysis shows sector dropdown", %{conn: conn, admin: admin} do
      # Pre-populate altcoin cache so the async fetch completes
      populate_altcoin_cache()

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      # Template switch triggers async fetch_sector_data
      render_change(view, "validate", %{"form" => %{
        "template" => "narrative_analysis",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "opinion",
        "sector" => "ai"
      }})

      # Wait for async to complete so form re-renders
      html = render_async(view)

      assert html =~ "Sector"
      assert html =~ "AI / Artificial Intelligence"
      assert html =~ "DeFi"
      assert html =~ "Layer 1"
      assert html =~ "Meme Coins"
      assert html =~ "Generate Narrative Report"
    end

    test "switching to custom hides blockster fields", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      # Switch to blockster first
      render_change(view, "validate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "opinion"
      }})

      # Switch back to custom
      html = render_change(view, "validate", %{"form" => %{
        "template" => "custom",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "opinion"
      }})

      refute html =~ "X/Twitter Handle"
      refute html =~ "Role / Title"
      assert html =~ "Content Type"
      assert html =~ "Category"
      assert html =~ "Generate Article"
    end

    test "blockster template auto-sets category and content_type", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_change(view, "validate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "news"
      }})

      # Category and content_type selectors should be hidden for blockster
      refute html =~ ~r/<select[^>]*name="form\[category\]"/
      # Hidden fields should set them
      assert html =~ ~s(value="blockster_of_week")
      assert html =~ ~s(value="opinion")
    end

    test "event_preview auto-sets category to events and content_type to news", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_change(view, "validate", %{"form" => %{
        "template" => "event_preview",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "opinion"
      }})

      # Hidden inputs should set category and content_type
      assert html =~ ~s(value="events")
      assert html =~ ~s(value="news")
    end
  end

  describe "form validation errors" do
    setup [:create_admin]

    test "shows error when topic is empty for custom article", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_submit(view, "generate", %{"form" => %{
        "template" => "custom",
        "topic" => "",
        "instructions" => "Some instructions here",
        "category" => "bitcoin",
        "content_type" => "news"
      }})

      assert html =~ "is required"
    end

    test "shows error when instructions are empty for custom article", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_submit(view, "generate", %{"form" => %{
        "template" => "custom",
        "topic" => "Test Topic",
        "instructions" => "",
        "category" => "bitcoin",
        "content_type" => "news"
      }})

      assert html =~ "Instructions/details are required"
    end

    test "shows error when topic empty for blockster_of_week", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      # Switch to blockster template first
      render_change(view, "validate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "",
        "instructions" => "",
        "category" => "blockster_of_week",
        "content_type" => "opinion"
      }})

      html = render_submit(view, "generate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "",
        "x_handle" => "vitalik",
        "instructions" => "",
        "category" => "blockster_of_week",
        "content_type" => "opinion"
      }})

      assert html =~ "is required"
    end

    test "shows error when x_handle empty for blockster_of_week", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      # Switch to blockster template first
      render_change(view, "validate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "",
        "instructions" => "",
        "category" => "blockster_of_week",
        "content_type" => "opinion"
      }})

      html = render_submit(view, "generate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "Vitalik Buterin",
        "x_handle" => "",
        "instructions" => "",
        "category" => "blockster_of_week",
        "content_type" => "opinion"
      }})

      assert html =~ "X/Twitter handle is required"
    end

    test "shows error when instructions empty for weekly_roundup", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_submit(view, "generate", %{"form" => %{
        "template" => "weekly_roundup",
        "topic" => "weekly_roundup",
        "instructions" => "",
        "category" => "events",
        "content_type" => "news"
      }})

      assert html =~ "Event data is required"
    end

    test "shows error when instructions empty for market_movers", %{conn: conn, admin: admin} do
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

    test "shows error when instructions empty for narrative_analysis", %{conn: conn, admin: admin} do
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
  end

  describe "template descriptions" do
    setup [:create_admin]

    test "custom template has no extra description", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/request")

      # Default is custom - should not show special template descriptions
      refute html =~ "Profile a notable crypto figure"
      refute html =~ "Generate a standalone preview"
    end

    test "blockster template shows profile description", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_change(view, "validate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "opinion"
      }})

      assert html =~ "Profile a notable crypto figure"
      assert html =~ "magazine-style profile"
    end

    test "event_preview shows event description", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_change(view, "validate", %{"form" => %{
        "template" => "event_preview",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "opinion"
      }})

      assert html =~ "standalone preview article"
    end

    test "market_movers shows market description", %{conn: conn, admin: admin} do
      populate_altcoin_cache()

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      # Template switch triggers async fetch_market_data
      render_change(view, "validate", %{"form" => %{
        "template" => "market_movers",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "opinion"
      }})

      # Wait for async to complete so form re-renders
      html = render_async(view)

      assert html =~ "data-driven analysis"
      assert html =~ "Generate Market Analysis"
    end
  end

  describe "form fields" do
    setup [:create_admin]

    test "shows author persona dropdown", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/request")

      assert html =~ "Author Persona"
      assert html =~ "Auto-select by category"
    end

    test "shows angle field for custom template", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/request")

      assert html =~ "Angle / Perspective"
    end

    test "hides angle field for blockster template", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = render_change(view, "validate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "",
        "instructions" => "",
        "category" => "defi",
        "content_type" => "opinion"
      }})

      refute html =~ "Angle / Perspective"
    end

    test "shows content type options for custom template", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/request")

      assert html =~ "Opinion / Editorial"
      assert html =~ "News (Factual)"
      assert html =~ "Offer / Opportunity"
    end
  end
end
