defmodule BlocksterV2Web.AuthControllerFingerprintTest do
  use BlocksterV2Web.ConnCase, async: false

  alias BlocksterV2.Accounts

  setup do
    # Create user_betting_stats Mnesia table (needed by Accounts.create_user_betting_stats/2 on signup)
    case :mnesia.create_table(:user_betting_stats, [
           attributes: [
             :user_id, :wallet_address,
             :bux_total_bets, :bux_wins, :bux_losses, :bux_total_wagered,
             :bux_total_winnings, :bux_total_losses, :bux_net_pnl,
             :rogue_total_bets, :rogue_wins, :rogue_losses, :rogue_total_wagered,
             :rogue_total_winnings, :rogue_total_losses, :rogue_net_pnl,
             :first_bet_at, :last_bet_at, :updated_at, :onchain_stats_cache
           ],
           ram_copies: [node()],
           type: :set,
           index: [:bux_total_wagered, :rogue_total_wagered]
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :user_betting_stats}} -> :mnesia.clear_table(:user_betting_stats)
    end

    :ok
  end

  describe "POST /api/auth/email/verify with fingerprint" do
    @valid_params %{
      "email" => "test@example.com",
      "wallet_address" => "0xabc123",
      "smart_wallet_address" => "0xdef456",
      "fingerprint_id" => "fp_test123",
      "fingerprint_confidence" => 0.99,
      "fingerprint_request_id" => "req_abc123"
    }

    test "creates new user and returns success with fingerprint data", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/email/verify", @valid_params)

      assert %{
               "success" => true,
               "user" => user,
               "token" => token
             } = json_response(conn, 200)

      # Verify user data
      assert user["email"] == "test@example.com"
      assert user["wallet_address"] == "0xabc123"
      assert user["smart_wallet_address"] == "0xdef456"
      assert user["registered_devices_count"] == 1

      # Verify token returned
      assert token != nil

      # Verify session cookie set
      assert get_session(conn, :user_token) == token

      # Verify fingerprint saved in database
      db_user = Accounts.get_user_by_email("test@example.com")
      devices = Accounts.get_user_devices(db_user.id)
      assert length(devices) == 1
      assert hd(devices).fingerprint_id == "fp_test123"
    end

    test "returns 403 when fingerprint already registered to different user", %{conn: conn} do
      # Create first user
      post(conn, ~p"/api/auth/email/verify", @valid_params)

      # Attempt to create second user with same fingerprint
      second_user_params = %{@valid_params | "email" => "different@example.com"}

      conn = post(conn, ~p"/api/auth/email/verify", second_user_params)

      assert %{
               "success" => false,
               "error_type" => "fingerprint_conflict",
               "message" => message,
               "existing_email" => masked_email
             } = json_response(conn, 403)

      # Verify error message
      assert message == "This device is already registered to another account"

      # Verify email is masked
      assert masked_email == "te***@example.com"

      # Verify second user was not created
      assert Accounts.get_user_by_email("different@example.com") == nil

      # Verify first user was flagged
      first_user = Accounts.get_user_by_email("test@example.com")
      assert first_user.is_flagged_multi_account_attempt == true
    end

    test "allows existing user to login from same device", %{conn: conn} do
      # Create user
      conn1 = post(conn, ~p"/api/auth/email/verify", @valid_params)
      %{"user" => original_user} = json_response(conn1, 200)

      # Login again with same email and fingerprint
      conn2 = post(conn, ~p"/api/auth/email/verify", @valid_params)

      assert %{
               "success" => true,
               "user" => user,
               "token" => _token
             } = json_response(conn2, 200)

      # Verify same user
      assert user["id"] == original_user["id"]
      assert user["email"] == "test@example.com"

      # Verify still only 1 device
      assert user["registered_devices_count"] == 1
    end

    test "allows existing user to login from new device", %{conn: conn} do
      # Create user on first device
      conn1 = post(conn, ~p"/api/auth/email/verify", @valid_params)
      %{"user" => original_user} = json_response(conn1, 200)

      # Login from second device
      new_device_params = %{@valid_params | "fingerprint_id" => "fp_second_device"}

      conn2 = post(conn, ~p"/api/auth/email/verify", new_device_params)

      assert %{
               "success" => true,
               "user" => user,
               "token" => _token
             } = json_response(conn2, 200)

      # Verify same user
      assert user["id"] == original_user["id"]

      # Verify now has 2 devices (reload from DB for updated count)
      db_user = Accounts.get_user(user["id"])
      assert db_user.registered_devices_count == 2
    end

    test "returns 422 when required fingerprint fields are missing", %{conn: conn} do
      # Missing fingerprint_id
      invalid_params = Map.delete(@valid_params, "fingerprint_id")

      conn = post(conn, ~p"/api/auth/email/verify", invalid_params)

      assert %{"success" => false, "errors" => _errors} = json_response(conn, 422)
    end

    test "normalizes email to lowercase", %{conn: conn} do
      uppercase_params = %{@valid_params | "email" => "TEST@EXAMPLE.COM"}

      conn = post(conn, ~p"/api/auth/email/verify", uppercase_params)

      assert %{
               "success" => true,
               "user" => user
             } = json_response(conn, 200)

      # Verify email stored as lowercase
      assert user["email"] == "test@example.com"
    end

    test "masks email correctly in fingerprint conflict error", %{conn: conn} do
      # Create user with various email formats
      test_cases = [
        {"ab@example.com", "ab***@example.com"},
        {"a@example.com", "a***@example.com"},
        {"alice@example.com", "al***@example.com"},
        {"verylongemail@example.com", "ve***@example.com"}
      ]

      for {email, expected_masked} <- test_cases do
        # Create first user (with unique wallet addresses to avoid constraint violations)
        params1 = %{
          @valid_params
          | "email" => email,
            "fingerprint_id" => "fp_#{email}",
            "wallet_address" => "0x#{Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)}",
            "smart_wallet_address" => "0x#{Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)}"
        }
        post(conn, ~p"/api/auth/email/verify", params1)

        # Attempt second user with same fingerprint but different wallet addresses
        params2 = %{
          params1
          | "email" => "different_#{email}",
            "wallet_address" => "0x#{Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)}",
            "smart_wallet_address" => "0x#{Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)}"
        }
        conn2 = post(conn, ~p"/api/auth/email/verify", params2)

        assert %{"existing_email" => masked_email} = json_response(conn2, 403)
        assert masked_email == expected_masked
      end
    end
  end
end
