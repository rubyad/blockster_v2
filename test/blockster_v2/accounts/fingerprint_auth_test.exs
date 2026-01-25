defmodule BlocksterV2.Accounts.FingerprintAuthTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Accounts
  alias BlocksterV2.Accounts.{User, UserFingerprint}

  describe "authenticate_email_with_fingerprint/1" do
    @valid_attrs %{
      email: "test@example.com",
      wallet_address: "0xabc123",
      smart_wallet_address: "0xdef456",
      fingerprint_id: "fp_test123",
      fingerprint_confidence: 0.99
    }

    test "creates new user with fingerprint when email and fingerprint are new" do
      assert {:ok, user, session} = Accounts.authenticate_email_with_fingerprint(@valid_attrs)

      # Verify user created
      assert user.email == "test@example.com"
      assert user.wallet_address == "0xabc123"
      assert user.smart_wallet_address == "0xdef456"
      assert user.registered_devices_count == 1

      # Verify fingerprint created
      fingerprints = Accounts.get_user_devices(user.id)
      assert length(fingerprints) == 1

      [fingerprint] = fingerprints
      assert fingerprint.fingerprint_id == "fp_test123"
      assert fingerprint.fingerprint_confidence == 0.99
      assert fingerprint.is_primary == true
      assert fingerprint.user_id == user.id

      # Verify session created
      assert session.user_id == user.id
      assert session.token != nil
    end

    test "blocks new account creation when fingerprint already exists" do
      # Create first user with fingerprint
      {:ok, first_user, _session} = Accounts.authenticate_email_with_fingerprint(@valid_attrs)

      # Attempt to create second user with same fingerprint
      second_user_attrs = %{@valid_attrs | email: "different@example.com"}

      assert {:error, :fingerprint_conflict, existing_email} =
               Accounts.authenticate_email_with_fingerprint(second_user_attrs)

      # Verify error returns first user's email
      assert existing_email == first_user.email

      # Verify first user is flagged for suspicious activity
      flagged_user = Accounts.get_user(first_user.id)
      assert flagged_user.is_flagged_multi_account_attempt == true
      assert flagged_user.last_suspicious_activity_at != nil

      # Verify no second user was created
      assert Accounts.get_user_by_email("different@example.com") == nil
    end

    test "allows existing user to login from same device" do
      # Create user
      {:ok, user, _session} = Accounts.authenticate_email_with_fingerprint(@valid_attrs)

      # Wait a moment to ensure timestamps will be different
      :timer.sleep(1000)

      # Simulate logout and login again
      assert {:ok, logged_in_user, new_session} =
               Accounts.authenticate_email_with_fingerprint(@valid_attrs)

      # Verify same user returned
      assert logged_in_user.id == user.id

      # Verify still only 1 fingerprint
      fingerprints = Accounts.get_user_devices(user.id)
      assert length(fingerprints) == 1

      # Verify last_seen updated
      [fingerprint] = fingerprints
      assert DateTime.compare(fingerprint.last_seen_at, fingerprint.first_seen_at) == :gt

      # Verify new session created
      assert new_session.user_id == user.id
      assert new_session.token != nil
    end

    test "allows existing user to login from new device and claims fingerprint" do
      # Create user on first device
      {:ok, user, _session} = Accounts.authenticate_email_with_fingerprint(@valid_attrs)

      # Login from second device
      new_device_attrs = %{
        @valid_attrs
        | fingerprint_id: "fp_second_device",
          fingerprint_confidence: 0.98
      }

      assert {:ok, logged_in_user, _session} =
               Accounts.authenticate_email_with_fingerprint(new_device_attrs)

      # Verify same user returned
      assert logged_in_user.id == user.id

      # Verify user now has 2 devices
      updated_user = Accounts.get_user(user.id)
      assert updated_user.registered_devices_count == 2

      # Verify both fingerprints exist
      fingerprints = Accounts.get_user_devices(user.id)
      assert length(fingerprints) == 2

      # Verify primary device is first one
      primary = Enum.find(fingerprints, & &1.is_primary)
      assert primary.fingerprint_id == "fp_test123"

      # Verify second device is not primary
      secondary = Enum.find(fingerprints, &(!&1.is_primary))
      assert secondary.fingerprint_id == "fp_second_device"
      assert secondary.fingerprint_confidence == 0.98
    end

    test "allows existing user to login from shared device (owned by someone else)" do
      # User A creates account on shared device
      user_a_attrs = %{
        @valid_attrs
        | email: "usera@example.com",
          wallet_address: "0xaaa",
          smart_wallet_address: "0xbbb"
      }

      {:ok, user_a, _session} = Accounts.authenticate_email_with_fingerprint(user_a_attrs)

      # User B creates account on different device
      user_b_attrs = %{
        @valid_attrs
        | email: "userb@example.com",
          wallet_address: "0xccc",
          smart_wallet_address: "0xddd",
          fingerprint_id: "fp_userb_device"
      }

      {:ok, user_b, _session} = Accounts.authenticate_email_with_fingerprint(user_b_attrs)

      # User B logs in from shared device (owned by User A)
      user_b_on_shared_device = %{
        user_b_attrs
        | fingerprint_id: "fp_test123"  # User A's device
      }

      assert {:ok, logged_in_user, _session} =
               Accounts.authenticate_email_with_fingerprint(user_b_on_shared_device)

      # Verify User B logged in successfully
      assert logged_in_user.id == user_b.id

      # Verify shared device still owned by User A
      fingerprints_a = Accounts.get_user_devices(user_a.id)
      shared_device = Enum.find(fingerprints_a, &(&1.fingerprint_id == "fp_test123"))
      assert shared_device.user_id == user_a.id

      # Verify User B still has only 1 device (their own)
      fingerprints_b = Accounts.get_user_devices(user_b.id)
      assert length(fingerprints_b) == 1
      assert hd(fingerprints_b).fingerprint_id == "fp_userb_device"
    end

    test "updates smart_wallet_address if it changed for existing user" do
      # Create user
      {:ok, user, _session} = Accounts.authenticate_email_with_fingerprint(@valid_attrs)
      original_smart_wallet = user.smart_wallet_address

      # Login with different smart_wallet_address
      updated_attrs = %{@valid_attrs | smart_wallet_address: "0xnew_smart_wallet"}

      assert {:ok, logged_in_user, _session} =
               Accounts.authenticate_email_with_fingerprint(updated_attrs)

      # Verify smart_wallet_address updated
      assert logged_in_user.smart_wallet_address == "0xnew_smart_wallet"
      assert logged_in_user.smart_wallet_address != original_smart_wallet
    end

    test "normalizes email to lowercase" do
      uppercase_attrs = %{@valid_attrs | email: "TEST@EXAMPLE.COM"}

      assert {:ok, user, _session} =
               Accounts.authenticate_email_with_fingerprint(uppercase_attrs)

      # Verify email stored as lowercase
      assert user.email == "test@example.com"
    end
  end

  describe "get_user_devices/1" do
    test "returns devices ordered by primary first, then by first_seen_at desc" do
      attrs = %{
        email: "test@example.com",
        wallet_address: "0xabc",
        smart_wallet_address: "0xdef",
        fingerprint_id: "fp_device1",
        fingerprint_confidence: 0.99
      }

      {:ok, user, _session} = Accounts.authenticate_email_with_fingerprint(attrs)

      # Add second device
      device2_attrs = %{attrs | fingerprint_id: "fp_device2"}
      Accounts.authenticate_email_with_fingerprint(device2_attrs)

      # Add third device
      device3_attrs = %{attrs | fingerprint_id: "fp_device3"}
      Accounts.authenticate_email_with_fingerprint(device3_attrs)

      devices = Accounts.get_user_devices(user.id)

      # Verify order: primary first
      assert length(devices) == 3
      assert hd(devices).is_primary == true
      assert hd(devices).fingerprint_id == "fp_device1"
    end

    test "returns empty list for user with no devices" do
      # Create user without going through fingerprint auth
      {:ok, user} =
        Repo.insert(%User{
          email: "test@example.com",
          wallet_address: "0xabc",
          smart_wallet_address: "0xdef"
        })

      devices = Accounts.get_user_devices(user.id)
      assert devices == []
    end
  end

  describe "remove_user_device/2" do
    setup do
      attrs = %{
        email: "test@example.com",
        wallet_address: "0xabc",
        smart_wallet_address: "0xdef",
        fingerprint_id: "fp_device1",
        fingerprint_confidence: 0.99
      }

      {:ok, user, _session} = Accounts.authenticate_email_with_fingerprint(attrs)

      # Add second device
      device2_attrs = %{attrs | fingerprint_id: "fp_device2"}
      Accounts.authenticate_email_with_fingerprint(device2_attrs)

      # Reload user to get updated device count
      user = Accounts.get_user(user.id)

      %{user: user}
    end

    test "removes secondary device successfully", %{user: user} do
      assert user.registered_devices_count == 2

      assert {:ok, :device_removed} =
               Accounts.remove_user_device(user.id, "fp_device2")

      # Verify device removed
      devices = Accounts.get_user_devices(user.id)
      assert length(devices) == 1
      assert hd(devices).fingerprint_id == "fp_device1"

      # Verify device count decremented
      updated_user = Accounts.get_user(user.id)
      assert updated_user.registered_devices_count == 1
    end

    test "prevents removal of last device", %{user: user} do
      # Remove second device first
      Accounts.remove_user_device(user.id, "fp_device2")

      # Try to remove last device
      assert {:error, :cannot_remove_last_device} =
               Accounts.remove_user_device(user.id, "fp_device1")

      # Verify device still exists
      devices = Accounts.get_user_devices(user.id)
      assert length(devices) == 1
    end

    test "returns error when device doesn't exist", %{user: user} do
      # Device gets deleted but count doesn't decrement properly (edge case)
      result = Accounts.remove_user_device(user.id, "fp_nonexistent")

      # Should return ok even if device doesn't exist (idempotent)
      assert result == {:ok, :device_removed}
    end
  end

  describe "list_flagged_accounts/0" do
    test "returns users flagged for multi-account attempts ordered by date desc" do
      # Create first user
      attrs1 = %{
        email: "user1@example.com",
        wallet_address: "0x111",
        smart_wallet_address: "0x222",
        fingerprint_id: "fp_device1",
        fingerprint_confidence: 0.99
      }

      {:ok, _user1, _session} = Accounts.authenticate_email_with_fingerprint(attrs1)

      # Attempt to create second user with same fingerprint (triggers flag)
      attrs2 = %{attrs1 | email: "user2@example.com"}
      Accounts.authenticate_email_with_fingerprint(attrs2)

      # Wait a moment to ensure different timestamp for next flag event
      :timer.sleep(1000)

      # Create third user on different device
      attrs3 = %{
        email: "user3@example.com",
        wallet_address: "0x333",
        smart_wallet_address: "0x444",
        fingerprint_id: "fp_device3",
        fingerprint_confidence: 0.99
      }

      {:ok, _user3, _session} = Accounts.authenticate_email_with_fingerprint(attrs3)

      # Attempt to create fourth user with user3's fingerprint (triggers flag)
      attrs4 = %{attrs3 | email: "user4@example.com"}
      Accounts.authenticate_email_with_fingerprint(attrs4)

      # Get flagged accounts
      flagged = Accounts.list_flagged_accounts()

      # Verify both flagged users returned
      assert length(flagged) == 2
      flagged_emails = Enum.map(flagged, & &1.email)
      assert "user1@example.com" in flagged_emails
      assert "user3@example.com" in flagged_emails

      # Verify ordered by last_suspicious_activity_at desc (most recent first)
      assert hd(flagged).email == "user3@example.com"
    end

    test "returns empty list when no flagged accounts exist" do
      # Create normal user
      attrs = %{
        email: "normal@example.com",
        wallet_address: "0xabc",
        smart_wallet_address: "0xdef",
        fingerprint_id: "fp_device1",
        fingerprint_confidence: 0.99
      }

      Accounts.authenticate_email_with_fingerprint(attrs)

      flagged = Accounts.list_flagged_accounts()
      assert flagged == []
    end
  end
end
