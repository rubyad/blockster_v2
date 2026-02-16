defmodule BlocksterV2Web.ContentAutomationLive.EventsPageTest do
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.ContentAutomation.EventRoundup
  import BlocksterV2.ContentAutomation.Factory

  setup do
    ensure_mnesia_tables()

    # Clear events table between tests to avoid cross-contamination
    :mnesia.clear_table(:upcoming_events)

    on_exit(fn ->
      try do
        :mnesia.clear_table(:upcoming_events)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  defp create_admin(_) do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "admin_events_#{unique}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true
      })
      |> Repo.insert()

    %{admin: admin}
  end

  describe "mount" do
    setup [:create_admin]

    test "renders events page for admin", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/events")

      assert html =~ "Upcoming Events"
      assert html =~ "events tracked"
    end

    test "shows Add Event button", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/events")

      assert html =~ "Add Event"
    end

    test "shows Generate Weekly Roundup button", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/events")

      assert html =~ "Generate Weekly Roundup"
    end

    test "shows dashboard back link", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/events")

      assert has_element?(view, "a[href='/admin/content']")
    end

    test "shows empty state when no events", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/events")

      assert html =~ "No events tracked yet"
    end
  end

  describe "access control" do
    test "redirects non-admin user", %{conn: conn} do
      {:ok, user} =
        %User{}
        |> Ecto.Changeset.change(%{
          email: "nonadmin_events@test.com",
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          is_admin: false
        })
        |> Repo.insert()

      conn = log_in_user(conn, user)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/content/events")
    end
  end

  describe "toggle_form event" do
    setup [:create_admin]

    test "shows add event form when toggled", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, html} = live(conn, ~p"/admin/content/events")

      # Form should be hidden initially
      refute html =~ "Event Name"

      # Toggle form open
      html = render_click(view, "toggle_form")
      assert html =~ "Event Name"
      assert html =~ "Start Date"
      assert html =~ "End Date"
      assert html =~ "Tier"

      # Button should now say Cancel
      assert html =~ "Cancel"
    end

    test "hides form when toggled again", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/events")

      # Open
      render_click(view, "toggle_form")
      # Close
      html = render_click(view, "toggle_form")

      assert html =~ "Add Event"
      refute html =~ "Cancel"
    end
  end

  describe "add_event validation" do
    setup [:create_admin]

    test "shows error when event name is empty", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/events")

      # Open form
      render_click(view, "toggle_form")

      html = render_submit(view, "add_event", %{"event" => %{
        "name" => "",
        "event_type" => "conference",
        "start_date" => "2026-03-01",
        "end_date" => "",
        "location" => "Denver",
        "url" => "https://ethdenver.com",
        "description" => "Test event",
        "tier" => "major"
      }})

      assert html =~ "Event name is required"
    end

    test "shows error when start date is empty", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/events")

      render_click(view, "toggle_form")

      html = render_submit(view, "add_event", %{"event" => %{
        "name" => "ETH Denver",
        "event_type" => "conference",
        "start_date" => "",
        "end_date" => "",
        "location" => "Denver",
        "url" => "https://ethdenver.com",
        "description" => "",
        "tier" => "major"
      }})

      assert html =~ "Start date is required"
    end

    test "shows error when URL is empty", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/events")

      render_click(view, "toggle_form")

      html = render_submit(view, "add_event", %{"event" => %{
        "name" => "ETH Denver",
        "event_type" => "conference",
        "start_date" => "2026-03-01",
        "end_date" => "",
        "location" => "Denver",
        "url" => "",
        "description" => "",
        "tier" => "major"
      }})

      assert html =~ "Event URL is required"
    end
  end

  describe "add_event success" do
    setup [:create_admin]

    test "adds event and shows it in the list", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/events")

      # Open form
      render_click(view, "toggle_form")

      html = render_submit(view, "add_event", %{"event" => %{
        "name" => "ETH Denver 2026",
        "event_type" => "conference",
        "start_date" => "2026-03-01",
        "end_date" => "2026-03-05",
        "location" => "Denver, Colorado",
        "url" => "https://ethdenver.com",
        "description" => "Major Ethereum developer conference",
        "tier" => "major"
      }})

      assert html =~ "Event added: ETH Denver 2026"
      assert html =~ "ETH Denver 2026"
      assert html =~ "Conference"
      assert html =~ "Denver, Colorado"
      assert html =~ "Major"
    end

    test "hides form after successful add", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/events")

      render_click(view, "toggle_form")

      html = render_submit(view, "add_event", %{"event" => %{
        "name" => "Devcon 2026",
        "event_type" => "conference",
        "start_date" => "2026-05-01",
        "end_date" => "",
        "location" => "",
        "url" => "https://devcon.org",
        "description" => "",
        "tier" => "notable"
      }})

      # Form should be hidden after successful add
      assert html =~ "Devcon 2026"
      # "Cancel" button only shows when form is visible
      refute html =~ "Cancel"
    end
  end

  describe "delete_event" do
    setup [:create_admin]

    test "deletes event from the list", %{conn: conn, admin: admin} do
      # Add an event directly via EventRoundup
      {:ok, event_id} = EventRoundup.add_event(%{
        name: "Delete Me Event",
        event_type: "conference",
        start_date: "2026-04-01",
        url: "https://example.com",
        tier: "minor"
      })

      conn = log_in_user(conn, admin)
      {:ok, view, html} = live(conn, ~p"/admin/content/events")

      assert html =~ "Delete Me Event"

      html = render_click(view, "delete_event", %{"id" => event_id})

      assert html =~ "Event deleted"
      refute html =~ "Delete Me Event"
    end
  end

  describe "events table" do
    setup [:create_admin]

    test "shows table headers when events exist", %{conn: conn, admin: admin} do
      {:ok, _} = EventRoundup.add_event(%{
        name: "Test Conference",
        event_type: "conference",
        start_date: "2026-06-01",
        url: "https://test.com",
        tier: "notable"
      })

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/events")

      assert html =~ "Event"
      assert html =~ "Type"
      assert html =~ "Date(s)"
      assert html =~ "Tier"
      assert html =~ "Article"
      assert html =~ "Actions"
    end

    test "shows Generate Preview button for major events", %{conn: conn, admin: admin} do
      {:ok, _} = EventRoundup.add_event(%{
        name: "Major Conference",
        event_type: "conference",
        start_date: "2026-06-01",
        url: "https://major.com",
        tier: "major"
      })

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/events")

      assert html =~ "Generate Preview"
    end

    test "does not show Generate Preview for minor events", %{conn: conn, admin: admin} do
      {:ok, _} = EventRoundup.add_event(%{
        name: "Minor Meetup",
        event_type: "ecosystem",
        start_date: "2026-06-01",
        url: "https://minor.com",
        tier: "minor"
      })

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/events")

      assert html =~ "Minor Meetup"
      refute html =~ "Generate Preview"
    end

    test "shows event type labels correctly", %{conn: conn, admin: admin} do
      {:ok, _} = EventRoundup.add_event(%{
        name: "Upgrade Event",
        event_type: "upgrade",
        start_date: "2026-06-01",
        url: "https://upgrade.com",
        tier: "notable"
      })

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/events")

      assert html =~ "Upgrade"
    end
  end

  describe "form fields" do
    setup [:create_admin]

    test "shows all event type options in form", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/events")

      html = render_click(view, "toggle_form")

      assert html =~ "Conference"
      assert html =~ "Upgrade"
      assert html =~ "Token Unlock"
      assert html =~ "Regulatory"
      assert html =~ "Ecosystem"
    end

    test "shows all tier options in form", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/events")

      html = render_click(view, "toggle_form")

      assert html =~ "Major"
      assert html =~ "Notable"
      assert html =~ "Minor"
    end
  end
end
