defmodule BlocksterV2Web.ContentAutomationLive.DashboardTest do
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.ContentAutomation.Settings
  import BlocksterV2.ContentAutomation.Factory

  setup do
    ensure_mnesia_tables()
    Settings.init_cache()
    :ok
  end

  defp create_admin(_) do
    unique = System.unique_integer([:positive])
    wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"

    {:ok, admin} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "admin_dash_#{unique}@test.com",
        wallet_address: wallet,
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true,
        is_author: true
      })
      |> Repo.insert()

    %{admin: admin}
  end

  defp create_non_admin(_) do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "user_dash_#{unique}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: false
      })
      |> Repo.insert()

    %{user: user}
  end

  describe "mount" do
    setup [:create_admin]

    test "renders dashboard page for admin user", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content")

      assert html =~ "Content Automation"
      assert html =~ "Pipeline overview and controls"
    end

    test "shows stat cards", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content")

      assert html =~ "Pending Review"
      assert html =~ "Published Today"
      assert html =~ "Rejected Today"
      assert html =~ "Feeds Active"
    end

    test "shows queue size control", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content")

      assert html =~ "Target Queue Size"
      assert html =~ "Articles to keep pending in the queue"
    end

    test "shows action buttons", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content")

      assert html =~ "Request Article"
      assert html =~ "Force Analyze"
      assert html =~ "Market Analysis"
      assert html =~ "Pause Pipeline"
    end

    test "shows empty queue message when no articles pending", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content")

      assert html =~ "No articles pending review"
    end
  end

  describe "access control" do
    setup [:create_non_admin]

    test "redirects non-admin user to home", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/content")
    end

    test "redirects unauthenticated user to home", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/content")
    end
  end

  describe "toggle_pause event" do
    setup [:create_admin]

    test "toggles pipeline paused state", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, html} = live(conn, ~p"/admin/content")

      # Initially not paused
      assert html =~ "Pause Pipeline"
      refute html =~ "Pipeline is paused"

      # Click pause
      html = render_click(view, "toggle_pause")
      assert html =~ "Resume Pipeline"
      assert html =~ "Pipeline is paused"

      # Click resume
      html = render_click(view, "toggle_pause")
      assert html =~ "Pause Pipeline"
      refute html =~ "Pipeline is paused"
    end
  end

  describe "queue size controls" do
    setup [:create_admin]

    test "increase_queue_size increments target", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content")

      initial_size = Settings.get(:target_queue_size, 10)

      html = render_click(view, "increase_queue_size")
      assert html =~ "#{initial_size + 1}"
    end

    test "decrease_queue_size decrements target", %{conn: conn, admin: admin} do
      Settings.set(:target_queue_size, 15)

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content")

      html = render_click(view, "decrease_queue_size")
      assert html =~ "14"
    end

    test "queue size does not go below 1", %{conn: conn, admin: admin} do
      Settings.set(:target_queue_size, 1)

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content")

      render_click(view, "decrease_queue_size")
      # Should still be 1
      assert Settings.get(:target_queue_size, 10) == 1
    end

    test "queue size does not exceed 50", %{conn: conn, admin: admin} do
      Settings.set(:target_queue_size, 50)

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content")

      render_click(view, "increase_queue_size")
      assert Settings.get(:target_queue_size, 10) == 50
    end
  end

  describe "recent queue display" do
    setup [:create_admin]

    test "displays pending queue entries", %{conn: conn, admin: admin} do
      insert_queue_entry(%{
        status: "pending",
        content_type: "news",
        author_id: admin.id,
        article_data: %{
          "title" => "Test Queue Article",
          "excerpt" => "A queued article for testing.",
          "category" => "bitcoin",
          "tags" => ["test"]
        }
      })

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content")

      assert html =~ "Test Queue Article"
      assert html =~ "A queued article for testing."
      assert html =~ "Publish Now"
      assert html =~ "Reject"
    end

    test "shows Edit button for queue entries", %{conn: conn, admin: admin} do
      entry = insert_queue_entry(%{
        status: "pending",
        author_id: admin.id,
        article_data: %{
          "title" => "Editable Article",
          "excerpt" => "Test",
          "category" => "defi",
          "tags" => []
        }
      })

      conn = log_in_user(conn, admin)
      {:ok, view, html} = live(conn, ~p"/admin/content")

      assert html =~ "Edit"
      assert has_element?(view, "a[href='/admin/content/queue/#{entry.id}/edit']")
    end
  end

  describe "reject event" do
    setup [:create_admin]

    test "removes entry from recent queue on reject", %{conn: conn, admin: admin} do
      entry = insert_queue_entry(%{
        status: "pending",
        author_id: admin.id,
        article_data: %{
          "title" => "Article To Reject",
          "excerpt" => "Will be rejected",
          "category" => "bitcoin",
          "tags" => []
        }
      })

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content")

      # Entry should be in the queue
      assert has_element?(view, "#queue-#{entry.id}")

      html = render_click(view, "reject", %{"id" => entry.id})
      assert html =~ "Article rejected"

      # Entry should be removed from the recent queue section
      refute has_element?(view, "#queue-#{entry.id}")
    end
  end

  describe "navigation links" do
    setup [:create_admin]

    test "has link to queue page", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content")

      assert has_element?(view, "a[href='/admin/content/queue']")
    end

    test "has link to request article page", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content")

      assert has_element?(view, "a[href='/admin/content/request']")
    end

    test "has link to feeds management", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content")

      assert has_element?(view, "a[href='/admin/content/feeds']")
    end
  end
end
