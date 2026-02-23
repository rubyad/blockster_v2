defmodule BlocksterV2Web.TelegramWebhookControllerTest do
  use BlocksterV2Web.ConnCase, async: false

  alias BlocksterV2.{Repo, Accounts, Accounts.User, UserEvents}
  alias BlocksterV2.Notifications.UserEvent
  import Ecto.Query

  setup do
    # Allow async tasks (UserEvents.track, send_telegram_message, etc.) to use the sandbox
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  # ============ Test Helpers ============

  defp create_user(attrs \\ %{}) do
    {:ok, user} =
      Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    if map_size(attrs) > 0 do
      {:ok, user} = Accounts.update_user(user, attrs)
      user
    else
      user
    end
  end

  defp create_connected_user(tg_user_id \\ nil) do
    tg_id = tg_user_id || "#{System.unique_integer([:positive])}"

    create_user(%{
      telegram_user_id: tg_id,
      telegram_username: "testuser_#{tg_id}",
      telegram_connected_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp create_user_with_connect_token do
    user = create_user()
    token = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    {:ok, user} = Accounts.update_user(user, %{telegram_connect_token: token})
    {user, token}
  end

  defp events_for_user(user_id, event_type) do
    Repo.all(
      from e in UserEvent,
        where: e.user_id == ^user_id and e.event_type == ^event_type,
        order_by: [desc: e.inserted_at]
    )
  end

  defp wait_for_async(timeout \\ 500) do
    Process.sleep(timeout)
  end

  # ============ /start Deep Link (Account Connection) ============

  describe "handle /start deep link" do
    test "successfully connects Telegram account", %{conn: conn} do
      {user, token} = create_user_with_connect_token()

      conn =
        post(conn, "/api/webhooks/telegram", %{
          "message" => %{
            "text" => "/start #{token}",
            "from" => %{
              "id" => 123456,
              "username" => "testuser",
              "first_name" => "Test"
            }
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}

      # Verify user was updated
      updated_user = Repo.get!(User, user.id)
      assert updated_user.telegram_user_id == "123456"
      assert updated_user.telegram_username == "testuser"
      assert updated_user.telegram_connect_token == nil
      assert updated_user.telegram_connected_at != nil
    end

    test "fires telegram_connected event on successful link", %{conn: conn} do
      {user, token} = create_user_with_connect_token()

      post(conn, "/api/webhooks/telegram", %{
        "message" => %{
          "text" => "/start #{token}",
          "from" => %{"id" => 789, "username" => "eventuser", "first_name" => "E"}
        }
      })

      wait_for_async()

      events = events_for_user(user.id, "telegram_connected")
      assert length(events) >= 1

      event = List.first(events)
      assert event.event_category == "social"
    end

    test "rejects invalid token", %{conn: conn} do
      conn =
        post(conn, "/api/webhooks/telegram", %{
          "message" => %{
            "text" => "/start invalid_token_xyz",
            "from" => %{"id" => 111, "username" => "baduser", "first_name" => "Bad"}
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "rejects already-connected user", %{conn: conn} do
      user = create_connected_user("555")

      # Give this user a connect token too
      token = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      {:ok, _} = Accounts.update_user(user, %{telegram_connect_token: token})

      conn =
        post(conn, "/api/webhooks/telegram", %{
          "message" => %{
            "text" => "/start #{token}",
            "from" => %{"id" => 555, "username" => "alreadyconnected", "first_name" => "Already"}
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "rejects Telegram account linked to another user", %{conn: conn} do
      # First user already has this TG account
      _existing = create_connected_user("999888")

      # Second user tries to link the same TG account
      {_user2, token} = create_user_with_connect_token()

      conn =
        post(conn, "/api/webhooks/telegram", %{
          "message" => %{
            "text" => "/start #{token}",
            "from" => %{"id" => 999888, "username" => "duplicate", "first_name" => "Dup"}
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "handles trimmed token with whitespace", %{conn: conn} do
      {user, token} = create_user_with_connect_token()

      conn =
        post(conn, "/api/webhooks/telegram", %{
          "message" => %{
            "text" => "/start #{token}  ",
            "from" => %{"id" => 42, "username" => "trim", "first_name" => "Trim"}
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}

      updated = Repo.get!(User, user.id)
      assert updated.telegram_user_id == "42"
    end

    test "handles missing username in from", %{conn: conn} do
      {user, token} = create_user_with_connect_token()

      conn =
        post(conn, "/api/webhooks/telegram", %{
          "message" => %{
            "text" => "/start #{token}",
            "from" => %{"id" => 77, "first_name" => "NoUsername"}
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}

      updated = Repo.get!(User, user.id)
      assert updated.telegram_user_id == "77"
      assert updated.telegram_username == nil
    end

    test "handles missing first_name in from", %{conn: conn} do
      {user, token} = create_user_with_connect_token()

      conn =
        post(conn, "/api/webhooks/telegram", %{
          "message" => %{
            "text" => "/start #{token}",
            "from" => %{"id" => 88, "username" => "nofirst"}
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}

      updated = Repo.get!(User, user.id)
      assert updated.telegram_user_id == "88"
    end
  end

  # ============ chat_member Webhook (Group Join Detection) ============

  describe "handle chat_member update" do
    setup do
      # Set up the V2 channel ID config for these tests
      original = Application.get_env(:blockster_v2, :telegram_v2_channel_id)
      Application.put_env(:blockster_v2, :telegram_v2_channel_id, "-1001234567890")
      on_exit(fn -> Application.put_env(:blockster_v2, :telegram_v2_channel_id, original) end)
      :ok
    end

    test "tracks group join when connected user joins the configured group", %{conn: conn} do
      user = create_connected_user("100200")

      conn =
        post(conn, "/api/webhooks/telegram", %{
          "chat_member" => %{
            "chat" => %{"id" => -1_001_234_567_890},
            "new_chat_member" => %{
              "status" => "member",
              "user" => %{"id" => 100_200}
            }
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}

      # Verify user's telegram_group_joined_at was set
      updated = Repo.get!(User, user.id)
      assert updated.telegram_group_joined_at != nil
    end

    test "fires telegram_group_joined event", %{conn: conn} do
      user = create_connected_user("200300")

      post(conn, "/api/webhooks/telegram", %{
        "chat_member" => %{
          "chat" => %{"id" => -1_001_234_567_890},
          "new_chat_member" => %{
            "status" => "member",
            "user" => %{"id" => 200_300}
          }
        }
      })

      wait_for_async()

      events = events_for_user(user.id, "telegram_group_joined")
      assert length(events) >= 1

      event = List.first(events)
      assert event.event_category == "social"
      # "source" is extracted to the source column by UserEvents.track
      assert event.source == "webhook"
    end

    test "handles administrator status as group join", %{conn: conn} do
      user = create_connected_user("300400")

      conn =
        post(conn, "/api/webhooks/telegram", %{
          "chat_member" => %{
            "chat" => %{"id" => -1_001_234_567_890},
            "new_chat_member" => %{
              "status" => "administrator",
              "user" => %{"id" => 300_400}
            }
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}

      updated = Repo.get!(User, user.id)
      assert updated.telegram_group_joined_at != nil
    end

    test "handles creator status as group join", %{conn: conn} do
      user = create_connected_user("400500")

      conn =
        post(conn, "/api/webhooks/telegram", %{
          "chat_member" => %{
            "chat" => %{"id" => -1_001_234_567_890},
            "new_chat_member" => %{
              "status" => "creator",
              "user" => %{"id" => 400_500}
            }
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}

      updated = Repo.get!(User, user.id)
      assert updated.telegram_group_joined_at != nil
    end

    test "ignores left/kicked/banned status", %{conn: conn} do
      user = create_connected_user("500600")

      for status <- ["left", "kicked", "banned"] do
        post(conn, "/api/webhooks/telegram", %{
          "chat_member" => %{
            "chat" => %{"id" => -1_001_234_567_890},
            "new_chat_member" => %{
              "status" => status,
              "user" => %{"id" => 500_600}
            }
          }
        })
      end

      updated = Repo.get!(User, user.id)
      assert updated.telegram_group_joined_at == nil
    end

    test "ignores events from a different chat/group", %{conn: conn} do
      user = create_connected_user("600700")

      conn =
        post(conn, "/api/webhooks/telegram", %{
          "chat_member" => %{
            "chat" => %{"id" => -9_999_999_999},
            "new_chat_member" => %{
              "status" => "member",
              "user" => %{"id" => 600_700}
            }
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}

      updated = Repo.get!(User, user.id)
      assert updated.telegram_group_joined_at == nil
    end

    test "ignores unlinked Telegram user (no Blockster account)", %{conn: conn} do
      conn =
        post(conn, "/api/webhooks/telegram", %{
          "chat_member" => %{
            "chat" => %{"id" => -1_001_234_567_890},
            "new_chat_member" => %{
              "status" => "member",
              "user" => %{"id" => 999_999_999}
            }
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "idempotent — does not double-track group join", %{conn: conn} do
      user = create_connected_user("700800")

      # First join
      post(conn, "/api/webhooks/telegram", %{
        "chat_member" => %{
          "chat" => %{"id" => -1_001_234_567_890},
          "new_chat_member" => %{
            "status" => "member",
            "user" => %{"id" => 700_800}
          }
        }
      })

      updated = Repo.get!(User, user.id)
      first_joined_at = updated.telegram_group_joined_at
      assert first_joined_at != nil

      # Wait a second for different timestamp
      Process.sleep(1100)

      # Second join (e.g. left and rejoined)
      post(conn, "/api/webhooks/telegram", %{
        "chat_member" => %{
          "chat" => %{"id" => -1_001_234_567_890},
          "new_chat_member" => %{
            "status" => "member",
            "user" => %{"id" => 700_800}
          }
        }
      })

      updated2 = Repo.get!(User, user.id)
      # Timestamp should not have changed
      assert updated2.telegram_group_joined_at == first_joined_at
    end

    test "does not fire duplicate events on re-join", %{conn: conn} do
      user = create_connected_user("800900")

      # First join
      post(conn, "/api/webhooks/telegram", %{
        "chat_member" => %{
          "chat" => %{"id" => -1_001_234_567_890},
          "new_chat_member" => %{
            "status" => "member",
            "user" => %{"id" => 800_900}
          }
        }
      })

      wait_for_async()

      events_after_first = events_for_user(user.id, "telegram_group_joined")
      count_first = length(events_after_first)

      # Second join
      post(conn, "/api/webhooks/telegram", %{
        "chat_member" => %{
          "chat" => %{"id" => -1_001_234_567_890},
          "new_chat_member" => %{
            "status" => "member",
            "user" => %{"id" => 800_900}
          }
        }
      })

      wait_for_async()

      events_after_second = events_for_user(user.id, "telegram_group_joined")
      # Should not have increased
      assert length(events_after_second) == count_first
    end
  end

  # ============ Catch-all Handler ============

  describe "catch-all handler" do
    test "returns ok for unknown update types", %{conn: conn} do
      conn = post(conn, "/api/webhooks/telegram", %{"unknown_field" => "whatever"})
      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "returns ok for empty params", %{conn: conn} do
      conn = post(conn, "/api/webhooks/telegram", %{})
      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "returns ok for message without /start", %{conn: conn} do
      conn =
        post(conn, "/api/webhooks/telegram", %{
          "message" => %{
            "text" => "Hello bot!",
            "from" => %{"id" => 123, "username" => "someone"}
          }
        })

      assert json_response(conn, 200) == %{"ok" => true}
    end
  end
end
