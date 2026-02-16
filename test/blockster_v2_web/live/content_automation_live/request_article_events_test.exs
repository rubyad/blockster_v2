defmodule BlocksterV2Web.ContentAutomationLive.RequestArticleEventsTest do
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  import BlocksterV2.ContentAutomation.Factory

  setup do
    ensure_mnesia_tables()
    :mnesia.clear_table(:upcoming_events)
    :ok
  end

  defp create_admin(_) do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "admin_evt_#{unique}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true,
        is_author: true
      })
      |> Repo.insert()

    %{admin: admin}
  end

  defp switch_to_event_preview(view) do
    render_change(view, "validate", %{"form" => %{
      "template" => "event_preview",
      "topic" => "",
      "instructions" => "",
      "category" => "events",
      "content_type" => "news"
    }})
  end

  defp switch_to_weekly_roundup(view) do
    render_change(view, "validate", %{"form" => %{
      "template" => "weekly_roundup",
      "topic" => "",
      "instructions" => "",
      "category" => "events",
      "content_type" => "news"
    }})

    # Weekly roundup triggers async fetch_events — wait for it
    render_async(view)
  end

  describe "event_preview template" do
    setup [:create_admin]

    test "shows event date, location, and URL fields", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_event_preview(view)

      assert html =~ "Event Date(s)"
      assert html =~ "Location"
      assert html =~ "Event URL"
    end

    test "topic label shows 'Event Name'", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_event_preview(view)

      assert html =~ "Event Name"
    end

    test "submit button says Generate Event Preview", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_event_preview(view)

      assert html =~ "Generate Event Preview"
    end

    test "shows template description", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_event_preview(view)

      assert html =~ "standalone preview article"
      assert html =~ "Events / News"
    end

    test "hides category/content type selectors", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_event_preview(view)

      # Hidden inputs for auto-set values
      assert html =~ ~s(value="events")
      assert html =~ ~s(value="news")
    end

    test "hides angle field", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_event_preview(view)

      refute html =~ "Angle / Perspective"
    end

    test "instructions label shows 'Additional Context'", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_event_preview(view)

      assert html =~ "Additional Context"
    end
  end

  describe "weekly_roundup template" do
    setup [:create_admin]

    test "submit button says Generate Weekly Roundup", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_weekly_roundup(view)

      assert html =~ "Generate Weekly Roundup"
    end

    test "hides topic field for weekly roundup", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_weekly_roundup(view)

      # Weekly roundup auto-generates topic, field should be hidden
      refute html =~ ~s(name="form[topic]" type="text")
    end

    test "instructions label shows 'Event Data'", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_weekly_roundup(view)

      assert html =~ "Event Data"
    end

    test "validates event data is required", %{conn: conn, admin: admin} do
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

    test "shows template description", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_weekly_roundup(view)

      assert html =~ "weekly roundup"
      assert html =~ "auto-populated"
    end
  end
end
