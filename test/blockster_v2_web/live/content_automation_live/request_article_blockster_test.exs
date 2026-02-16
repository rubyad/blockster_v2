defmodule BlocksterV2Web.ContentAutomationLive.RequestArticleBlocksterTest do
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
        email: "admin_botw_#{unique}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true,
        is_author: true
      })
      |> Repo.insert()

    %{admin: admin}
  end

  defp switch_to_blockster(view) do
    render_change(view, "validate", %{"form" => %{
      "template" => "blockster_of_week",
      "topic" => "",
      "instructions" => "",
      "category" => "blockster_of_week",
      "content_type" => "opinion"
    }})
  end

  describe "blockster_of_week template fields" do
    setup [:create_admin]

    test "shows X handle field with @ prefix", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_blockster(view)

      assert html =~ "X/Twitter Handle"
      assert html =~ "@"
      assert html =~ "VitalikButerin"
    end

    test "shows role/title field", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_blockster(view)

      assert html =~ "Role / Title"
      assert html =~ "Co-founder of Ethereum"
    end

    test "shows research brief as optional", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_blockster(view)

      assert html =~ "Research Brief"
      assert html =~ "optional"
      assert html =~ "X posts are the primary source"
    end

    test "hides category and content type selectors", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_blockster(view)

      # Category/content type dropdowns should not be visible
      refute html =~ "Opinion / Editorial"
      refute html =~ "News (Factual)"

      # Hidden inputs should carry the values
      assert html =~ ~s(value="blockster_of_week")
    end

    test "hides angle field", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_blockster(view)

      refute html =~ "Angle / Perspective"
    end

    test "topic field shows 'Person's Name' label", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_blockster(view)

      assert html =~ "Person"
      assert html =~ "Name"
    end

    test "submit button says Generate Profile", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      html = switch_to_blockster(view)

      assert html =~ "Generate Profile"
    end

    test "validates x_handle is required", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      switch_to_blockster(view)

      html = render_submit(view, "generate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "Vitalik Buterin",
        "x_handle" => "",
        "role" => "",
        "instructions" => "",
        "category" => "blockster_of_week",
        "content_type" => "opinion"
      }})

      assert html =~ "X/Twitter handle is required"
    end

    test "validates person name is required", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/content/request")

      switch_to_blockster(view)

      html = render_submit(view, "generate", %{"form" => %{
        "template" => "blockster_of_week",
        "topic" => "",
        "x_handle" => "vitalik",
        "role" => "",
        "instructions" => "",
        "category" => "blockster_of_week",
        "content_type" => "opinion"
      }})

      assert html =~ "is required"
    end
  end
end
