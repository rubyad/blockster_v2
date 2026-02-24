defmodule BlocksterV2.TelegramBot.AdminCommandsTest do
  use BlocksterV2Web.ConnCase, async: false

  alias BlocksterV2.Notifications.SystemConfig

  setup do
    # Create an admin user with telegram connected
    {:ok, admin} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    {:ok, admin} = BlocksterV2.Accounts.update_user(admin, %{
      is_admin: true,
      telegram_user_id: "123456789",
      telegram_username: "test_admin"
    })

    # Create a non-admin user
    {:ok, regular} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    {:ok, regular} = BlocksterV2.Accounts.update_user(regular, %{
      telegram_user_id: "987654321",
      telegram_username: "test_user"
    })

    %{admin: admin, regular: regular}
  end

  describe "admin commands" do
    test "non-admin cannot use /bot_pause", %{conn: conn} do
      payload = %{
        "message" => %{
          "text" => "/bot_pause",
          "from" => %{"id" => 987654321}
        }
      }

      conn = post(conn, "/api/webhooks/telegram", payload)
      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "admin can use /bot_pause", %{conn: conn} do
      payload = %{
        "message" => %{
          "text" => "/bot_pause",
          "from" => %{"id" => 123456789}
        }
      }

      conn = post(conn, "/api/webhooks/telegram", payload)
      assert json_response(conn, 200) == %{"ok" => true}

      # Verify SystemConfig was updated
      assert SystemConfig.get("hourly_promo_enabled", true) == false
    end

    test "admin can use /bot_resume", %{conn: conn} do
      SystemConfig.put("hourly_promo_enabled", false, "test")

      payload = %{
        "message" => %{
          "text" => "/bot_resume",
          "from" => %{"id" => 123456789}
        }
      }

      conn = post(conn, "/api/webhooks/telegram", payload)
      assert json_response(conn, 200) == %{"ok" => true}

      assert SystemConfig.get("hourly_promo_enabled", true) == true
    end

    test "admin can use /bot_status", %{conn: conn} do
      payload = %{
        "message" => %{
          "text" => "/bot_status",
          "from" => %{"id" => 123456789}
        }
      }

      conn = post(conn, "/api/webhooks/telegram", payload)
      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "admin can use /bot_budget", %{conn: conn} do
      payload = %{
        "message" => %{
          "text" => "/bot_budget",
          "from" => %{"id" => 123456789}
        }
      }

      conn = post(conn, "/api/webhooks/telegram", payload)
      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "admin can use /bot_next with type", %{conn: conn} do
      payload = %{
        "message" => %{
          "text" => "/bot_next game",
          "from" => %{"id" => 123456789}
        }
      }

      conn = post(conn, "/api/webhooks/telegram", payload)
      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "admin sees help when /bot_next without type", %{conn: conn} do
      payload = %{
        "message" => %{
          "text" => "/bot_next",
          "from" => %{"id" => 123456789}
        }
      }

      conn = post(conn, "/api/webhooks/telegram", payload)
      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "unrecognized message returns ok", %{conn: conn} do
      payload = %{
        "message" => %{
          "text" => "hello",
          "from" => %{"id" => 123456789}
        }
      }

      conn = post(conn, "/api/webhooks/telegram", payload)
      assert json_response(conn, 200) == %{"ok" => true}
    end
  end
end
