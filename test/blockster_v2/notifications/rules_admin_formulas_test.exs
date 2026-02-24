defmodule BlocksterV2.Notifications.RulesAdminFormulasTest do
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Notifications.SystemConfig

  setup do
    Repo.delete_all("system_config")
    SystemConfig.invalidate_cache()
    :ok
  end

  defp create_admin(_) do
    unique = System.unique_integer([:positive])
    wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"

    {:ok, admin} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "rules_admin_#{unique}@test.com",
        wallet_address: wallet,
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true
      })
      |> Repo.insert()

    %{admin: admin}
  end

  # ============ Form Rendering ============

  describe "form rendering" do
    setup [:create_admin]

    test "shows formula input fields when adding new rule", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      # Click add rule
      html = view |> element("button", "+ New Rule") |> render_click()

      assert html =~ "BUX Bonus Formula"
      assert html =~ "ROGUE Bonus Formula"
      assert html =~ "bux_bonus_formula"
      assert html =~ "rogue_bonus_formula"
    end

    test "shows recurring rule fields when adding new rule", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      html = view |> element("button", "+ New Rule") |> render_click()

      assert html =~ "Recurring Rule"
      assert html =~ "Every N"
      assert html =~ "Every N Formula"
      assert html =~ "Count Field"
    end

    test "count_field dropdown has expected options", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      html = view |> element("button", "+ New Rule") |> render_click()

      assert html =~ "total_bets (combined)"
      assert html =~ "bux_total_bets"
      assert html =~ "rogue_total_bets"
      assert html =~ "net_deposits (ROGUE)"
    end

    test "formula syntax helper text is visible", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      html = view |> element("button", "+ New Rule") |> render_click()

      assert html =~ "random(min, max)"
      assert html =~ "Formulas take precedence over static bonuses"
    end
  end

  # ============ Form Validation ============

  describe "form validation" do
    setup [:create_admin]

    test "accepts valid formula string", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      view |> element("button", "+ New Rule") |> render_click()

      html =
        view
        |> form("form", %{
          "event_type" => "game_played",
          "title" => "Formula Test",
          "body" => "Test body",
          "bux_bonus_formula" => "total_bets * 10"
        })
        |> render_submit()

      # Should succeed (no error for bux_bonus_formula)
      refute html =~ "invalid formula syntax"
      assert html =~ "Formula Test"
    end

    test "rejects invalid formula string", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      view |> element("button", "+ New Rule") |> render_click()

      html =
        view
        |> form("form", %{
          "event_type" => "game_played",
          "title" => "Bad Formula",
          "body" => "Test body",
          "bux_bonus_formula" => "this is not valid !!!"
        })
        |> render_submit()

      assert html =~ "invalid formula syntax"
    end

    test "every_n requires positive integer for recurring rules", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      view |> element("button", "+ New Rule") |> render_click()

      html =
        view
        |> form("form", %{
          "event_type" => "game_played",
          "title" => "Recurring Bad",
          "body" => "Test body",
          "recurring" => "true",
          "every_n" => "-5"
        })
        |> render_submit()

      assert html =~ "must be a positive integer" or html =~ "require every_n"
    end

    test "recurring true requires every_n or every_n_formula", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      view |> element("button", "+ New Rule") |> render_click()

      html =
        view
        |> form("form", %{
          "event_type" => "game_played",
          "title" => "Recurring No Interval",
          "body" => "Test body",
          "recurring" => "true",
          "every_n" => "",
          "every_n_formula" => ""
        })
        |> render_submit()

      assert html =~ "require every_n"
    end
  end

  # ============ Save Rule with Formulas ============

  describe "save rule with formulas" do
    setup [:create_admin]

    test "saving rule with bux_bonus_formula persists to SystemConfig", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      view |> element("button", "+ New Rule") |> render_click()

      view
      |> form("form", %{
        "event_type" => "game_played",
        "title" => "Formula Rule",
        "body" => "Test body",
        "bux_bonus_formula" => "total_bets * 10",
        "recurring" => "false"
      })
      |> render_submit()

      rules = SystemConfig.get("custom_rules", [])
      assert length(rules) == 1
      rule = hd(rules)
      assert rule["bux_bonus_formula"] == "total_bets * 10"
      assert rule["title"] == "Formula Rule"
    end

    test "saving recurring rule persists recurring fields", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      view |> element("button", "+ New Rule") |> render_click()

      view
      |> form("form", %{
        "event_type" => "game_played",
        "title" => "Recurring Rule",
        "body" => "Every 10 games!",
        "recurring" => "true",
        "every_n" => "10",
        "count_field" => "total_bets",
        "bux_bonus" => "500"
      })
      |> render_submit()

      rules = SystemConfig.get("custom_rules", [])
      assert length(rules) == 1
      rule = hd(rules)
      assert rule["recurring"] == true
      assert rule["every_n"] == 10
      assert rule["bux_bonus"] == 500
    end

    test "editing existing rule loads formula/recurring fields", %{conn: conn, admin: admin} do
      # Pre-populate a rule with formula fields
      SystemConfig.put("custom_rules", [
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Existing Formula",
          "body" => "Test",
          "bux_bonus_formula" => "random(100, 500)",
          "recurring" => true,
          "every_n" => 10,
          "count_field" => "total_bets"
        }
      ], "test")

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      html = view |> element("button[phx-click=edit_rule]") |> render_click()

      assert html =~ "random(100, 500)"
      assert html =~ "value=\"10\""
    end
  end

  # ============ Backwards Compatibility ============

  describe "backwards compatibility" do
    setup [:create_admin]

    test "rules without formulas still save and display", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/notifications/rules")

      view |> element("button", "+ New Rule") |> render_click()

      view
      |> form("form", %{
        "event_type" => "signup",
        "title" => "Welcome!",
        "body" => "Thanks for joining",
        "bux_bonus" => "500",
        "recurring" => "false"
      })
      |> render_submit()

      rules = SystemConfig.get("custom_rules", [])
      assert length(rules) == 1
      rule = hd(rules)
      assert rule["bux_bonus"] == 500
      refute Map.has_key?(rule, "bux_bonus_formula")
      refute Map.has_key?(rule, "recurring")
    end

    test "existing static bonus rules display correctly in table", %{conn: conn, admin: admin} do
      SystemConfig.put("custom_rules", [
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Static Bonus",
          "body" => "Test",
          "bux_bonus" => 1000
        }
      ], "test")

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/notifications/rules")

      assert html =~ "Static Bonus"
      assert html =~ "1000 BUX"
    end
  end
end
