defmodule BlocksterV2Web.ContentAutomationLive.EditArticleTest do
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
        email: "admin_edit_#{unique}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true,
        is_author: true
      })
      |> Repo.insert()

    %{admin: admin}
  end

  defp create_queue_entry_for(admin, attrs \\ %{}) do
    defaults = %{
      status: "pending",
      content_type: "news",
      author_id: admin.id,
      article_data: %{
        "title" => "Test Article for Editing",
        "excerpt" => "This article is ready for editorial review.",
        "content" => build_valid_tiptap_content(),
        "category" => "bitcoin",
        "tags" => ["bitcoin", "test"],
        "featured_image" => "https://example.com/image.jpg",
        "promotional_tweet" => "Check out our latest article!",
        "author_username" => "TestAuthor"
      }
    }

    insert_queue_entry(Map.merge(defaults, attrs))
  end

  describe "mount" do
    setup [:create_admin]

    test "renders edit article page with entry data", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Edit Article"
      assert html =~ "Test Article for Editing"
      assert html =~ "This article is ready for editorial review."
    end

    test "shows word count and author", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "words"
      assert html =~ "TestAuthor"
    end

    test "shows content type badge", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin, %{content_type: "opinion"})

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Opinion"
    end

    test "shows status", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "pending"
    end

    test "shows action buttons", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Save Draft"
      assert html =~ "Publish Now"
      assert html =~ "Preview"
      assert html =~ "Back to Queue"
    end

    test "redirects when article not found", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} =
        live(conn, ~p"/admin/content/queue/#{Ecto.UUID.generate()}/edit")
        |> follow_redirect(conn)

      assert html =~ "Article not found"
    end
  end

  describe "access control" do
    test "redirects non-admin user", %{conn: conn} do
      {:ok, user} =
        %User{}
        |> Ecto.Changeset.change(%{
          email: "nonadmin_edit@test.com",
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          is_admin: false
        })
        |> Repo.insert()

      conn = log_in_user(conn, user)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/content/queue/#{Ecto.UUID.generate()}/edit")
    end
  end

  describe "field editing" do
    setup [:create_admin]

    test "shows title input field", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert has_element?(view, "input[phx-value-field='title']")
    end

    test "shows excerpt textarea", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert has_element?(view, "textarea[phx-value-field='excerpt']")
    end

    test "shows category dropdown", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Category"
      assert html =~ ~s(phx-change="select_category")
    end

    test "shows tags section", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Tags"
      assert html =~ "bitcoin"
      assert html =~ "test"
    end

    test "shows featured image section", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Featured Image"
      assert html =~ "Change Image"
    end
  end

  describe "promotional tweet" do
    setup [:create_admin]

    test "shows promo tweet section", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Promo Tweet"
      assert html =~ "Check out our latest article!"
      assert html =~ "Post Tweet"
    end

    test "shows character count", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "/280"
    end

    test "shows auto-post toggle", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Auto-post tweet on publish"
    end
  end

  describe "revision section" do
    setup [:create_admin]

    test "shows revision request form", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Request AI Revision"
      assert html =~ "Request Revision"
    end

    test "shows error for empty revision instruction", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      html = render_submit(view, "request_revision", %{"instruction" => ""})
      assert html =~ "Enter a revision instruction"
    end
  end

  describe "editorial memory section" do
    setup [:create_admin]

    test "shows memory form", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Editorial Memory"
      assert html =~ "Save to Memory"
    end

    test "shows memory categories in dropdown", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Global"
      assert html =~ "Tone"
      assert html =~ "Terminology"
      assert html =~ "Topics"
      assert html =~ "Formatting"
    end

    test "shows error for empty memory instruction", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      html = render_submit(view, "add_memory", %{"instruction" => "", "category" => "global"})
      assert html =~ "Enter a memory instruction"
    end
  end

  describe "offer content type" do
    setup [:create_admin]

    test "shows offer details section for offer content type", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin, %{content_type: "offer"})

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Offer Details"
      assert html =~ "CTA URL"
      assert html =~ "CTA Button Text"
      assert html =~ "Offer Type"
      assert html =~ "Expiration Date"
    end

    test "does not show offer details for news content type", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin, %{content_type: "news"})

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      refute html =~ "Offer Details"
      refute html =~ "CTA URL"
    end

    test "shows offer type options", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin, %{content_type: "offer"})

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Yield Opportunity"
      assert html =~ "Exchange Promotion"
      assert html =~ "Token Launch"
      assert html =~ "Airdrop"
      assert html =~ "Listing"
    end
  end

  describe "schedule section" do
    setup [:create_admin]

    test "shows schedule publish section", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert html =~ "Schedule Publish"
      assert html =~ "Eastern"
    end
  end

  describe "navigation" do
    setup [:create_admin]

    test "has back to queue link", %{conn: conn, admin: admin} do
      entry = create_queue_entry_for(admin)

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/queue/#{entry.id}/edit")

      assert has_element?(view, "a[href='/admin/content/queue']")
    end
  end
end
