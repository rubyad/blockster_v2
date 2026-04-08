defmodule BlocksterV2.Accounts.EmailVerificationTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Accounts.EmailVerification
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Repo

  setup_all do
    # Create Mnesia tables needed by UnifiedMultiplier (called from verify_code)
    tables = [
      {:unified_multipliers_v2, :set,
        [:user_id, :x_score, :x_multiplier, :phone_multiplier, :sol_multiplier,
         :email_multiplier, :overall_multiplier, :last_updated, :created_at],
        [:overall_multiplier]},
      {:user_solana_balances, :set,
        [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance],
        []},
      {:x_connections, :set,
        [:user_id, :x_user_id, :x_username, :x_name, :x_profile_image_url,
         :access_token_encrypted, :refresh_token_encrypted, :token_expires_at,
         :scopes, :connected_at, :x_score, :followers_count, :following_count,
         :tweet_count, :listed_count, :avg_engagement_rate, :original_tweets_analyzed,
         :account_created_at, :score_calculated_at, :updated_at],
        [:x_user_id, :x_username]}
    ]

    for {name, type, attributes, index} <- tables do
      case :mnesia.create_table(name, [
        type: type,
        attributes: attributes,
        index: index,
        ram_copies: [node()]
      ]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^name}} -> :ok
      end
    end

    :ok
  end

  setup do
    # Create a test user with Solana wallet auth
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        wallet_address: "TestSolanaWallet123456789abcdef",
        username: "testuser_ev",
        auth_method: "wallet"
      })
      |> Repo.insert()

    # Create a legacy EVM user for migration testing
    {:ok, legacy_user} =
      %User{}
      |> User.changeset(%{
        wallet_address: "0xLegacyEvmWallet123456789",
        smart_wallet_address: "0xLegacySmartWallet123",
        username: "legacy_user",
        email: "legacy@example.com",
        auth_method: "email"
      })
      |> Repo.insert()

    %{user: user, legacy_user: legacy_user}
  end

  describe "send_verification_code/2" do
    test "stores code and timestamp on pending_email", %{user: user} do
      assert {:ok, updated} = EmailVerification.send_verification_code(user, "test@example.com")
      assert updated.pending_email == "test@example.com"
      # email is NOT promoted until verify_code succeeds
      assert updated.email != "test@example.com"
      assert updated.email_verification_code != nil
      assert String.length(updated.email_verification_code) == 6
      assert updated.email_verification_sent_at != nil
    end

    test "normalizes email to lowercase", %{user: user} do
      assert {:ok, updated} = EmailVerification.send_verification_code(user, "  Test@EXAMPLE.com  ")
      assert updated.pending_email == "test@example.com"
    end

    test "generates 6-digit numeric code", %{user: user} do
      assert {:ok, updated} = EmailVerification.send_verification_code(user, "test@example.com")
      assert Regex.match?(~r/^\d{6}$/, updated.email_verification_code)
    end
  end

  describe "verify_code/2" do
    test "verifies correct code and promotes pending_email -> email", %{user: user} do
      {:ok, user_with_code} = EmailVerification.send_verification_code(user, "test@example.com")
      code = user_with_code.email_verification_code

      assert {:ok, verified_user, info} = EmailVerification.verify_code(user_with_code, code)
      assert info[:merged] == false
      assert verified_user.email == "test@example.com"
      assert verified_user.email_verified == true
      assert verified_user.pending_email == nil
      assert verified_user.email_verification_code == nil
      assert verified_user.email_verification_sent_at == nil
    end

    test "rejects wrong code", %{user: user} do
      {:ok, user_with_code} = EmailVerification.send_verification_code(user, "test@example.com")

      assert {:error, :invalid_code} = EmailVerification.verify_code(user_with_code, "000000")
    end

    test "rejects when no code was sent", %{user: user} do
      assert {:error, :no_code_sent} = EmailVerification.verify_code(user, "123456")
    end

    test "rejects expired code", %{user: user} do
      {:ok, user_with_code} = EmailVerification.send_verification_code(user, "test@example.com")

      # Manually set sent_at to 11 minutes ago
      expired_time =
        DateTime.utc_now()
        |> DateTime.add(-11 * 60, :second)
        |> DateTime.truncate(:second)

      {:ok, expired_user} =
        user_with_code
        |> User.changeset(%{email_verification_sent_at: expired_time})
        |> Repo.update()

      assert {:error, :code_expired} = EmailVerification.verify_code(expired_user, expired_user.email_verification_code)
    end
  end

  describe "find_legacy_account/1" do
    test "finds legacy EVM user by email", %{legacy_user: legacy_user} do
      result = EmailVerification.find_legacy_account("legacy@example.com")
      assert result != nil
      assert result.id == legacy_user.id
    end

    test "returns nil for unknown email" do
      assert nil == EmailVerification.find_legacy_account("nonexistent@example.com")
    end

    test "case insensitive email matching", %{legacy_user: legacy_user} do
      result = EmailVerification.find_legacy_account("LEGACY@EXAMPLE.COM")
      assert result != nil
      assert result.id == legacy_user.id
    end

    test "does not find wallet-auth users", %{user: user} do
      # Add email to wallet user
      {:ok, _} =
        user
        |> User.changeset(%{email: "wallet_user@example.com"})
        |> Repo.update()

      # Should not find because auth_method is "wallet" not "email"
      assert nil == EmailVerification.find_legacy_account("wallet_user@example.com")
    end
  end

  describe "merge dispatch in verify_code/2" do
    test "no merge when no legacy account matches", %{user: user} do
      {:ok, user_with_code} = EmailVerification.send_verification_code(user, "fresh@example.com")
      code = user_with_code.email_verification_code

      assert {:ok, _verified_user, info} = EmailVerification.verify_code(user_with_code, code)
      assert info[:merged] == false
    end

    test "ignores legacy match when same user_id", %{user: user} do
      # If the email already lives on this user, we should NOT try to merge.
      {:ok, user_with_email} =
        user
        |> User.changeset(%{email: "owned@example.com"})
        |> Repo.update()

      {:ok, user_with_code} = EmailVerification.send_verification_code(user_with_email, "owned@example.com")
      code = user_with_code.email_verification_code

      assert {:ok, _verified_user, info} = EmailVerification.verify_code(user_with_code, code)
      assert info[:merged] == false
    end

    test "skips deactivated legacy users", %{user: user, legacy_user: legacy_user} do
      # Deactivation in real flow also NULLs the email (frees the unique slot).
      # Simulate that here so we can verify the new user picks up the email
      # without colliding.
      {:ok, _} =
        legacy_user
        |> User.changeset(%{
          is_active: false,
          legacy_email: legacy_user.email,
          email: nil
        })
        |> Repo.update()

      {:ok, user_with_code} =
        EmailVerification.send_verification_code(user, "legacy@example.com")

      code = user_with_code.email_verification_code

      assert {:ok, _verified_user, info} = EmailVerification.verify_code(user_with_code, code)
      assert info[:merged] == false
    end

    test "does NOT merge against an active Solana wallet user that shares the email",
         %{user: user} do
      # Active wallet user that already verified an email — must NOT be merged.
      {:ok, _other_wallet_user} =
        %User{}
        |> User.changeset(%{
          wallet_address: "OtherSolWallet#{System.unique_integer([:positive])}",
          username: "other_w#{System.unique_integer([:positive])}",
          auth_method: "wallet",
          email: "shared@example.com",
          email_verified: true
        })
        |> Repo.insert()

      {:ok, user_with_code} =
        EmailVerification.send_verification_code(user, "shared@example.com")

      code = user_with_code.email_verification_code

      # `find_legacy_user_for_email` filters auth_method = "email", so the
      # wallet user is not matched. The promote step then hits the unique
      # constraint on `users.email` and we surface :email_taken.
      assert {:error, :email_taken} =
               EmailVerification.verify_code(user_with_code, code)
    end

    test "returns :email_taken when promote hits the unique constraint on email", %{user: user} do
      {:ok, _other} =
        %User{}
        |> User.changeset(%{
          wallet_address: "TakenSolWallet#{System.unique_integer([:positive])}",
          username: "taken#{System.unique_integer([:positive])}",
          auth_method: "wallet",
          email: "taken@example.com"
        })
        |> Repo.insert()

      {:ok, user_with_code} =
        EmailVerification.send_verification_code(user, "taken@example.com")

      code = user_with_code.email_verification_code

      assert {:error, :email_taken} =
               EmailVerification.verify_code(user_with_code, code)
    end

    test "user can change their already-verified email to a fresh address", %{user: user} do
      # Step 1: verify the original email
      {:ok, with_orig} = EmailVerification.send_verification_code(user, "first@example.com")
      orig_code = with_orig.email_verification_code
      assert {:ok, after_first, _} = EmailVerification.verify_code(with_orig, orig_code)
      assert after_first.email == "first@example.com"
      assert after_first.email_verified == true

      # Step 2: change to a new email
      {:ok, with_new} = EmailVerification.send_verification_code(after_first, "second@example.com")
      new_code = with_new.email_verification_code

      assert with_new.pending_email == "second@example.com"
      # Old email is still on the user until verify_code promotes it
      assert with_new.email == "first@example.com"

      assert {:ok, after_second, _} = EmailVerification.verify_code(with_new, new_code)
      assert after_second.email == "second@example.com"
      assert after_second.email_verified == true
      assert after_second.pending_email == nil
    end
  end

  describe "can_resend?/1" do
    test "returns true when no code has been sent", %{user: user} do
      assert EmailVerification.can_resend?(user) == true
    end

    test "returns false immediately after sending", %{user: user} do
      {:ok, sent_user} = EmailVerification.send_verification_code(user, "test@example.com")
      assert EmailVerification.can_resend?(sent_user) == false
    end

    test "returns true after 60 seconds", %{user: user} do
      old_time =
        DateTime.utc_now()
        |> DateTime.add(-61, :second)
        |> DateTime.truncate(:second)

      {:ok, old_user} =
        user
        |> User.changeset(%{email_verification_sent_at: old_time})
        |> Repo.update()

      assert EmailVerification.can_resend?(old_user) == true
    end
  end

  describe "resend_cooldown/1" do
    test "returns 0 when no code has been sent", %{user: user} do
      assert EmailVerification.resend_cooldown(user) == 0
    end

    test "returns positive seconds when recently sent", %{user: user} do
      {:ok, sent_user} = EmailVerification.send_verification_code(user, "test@example.com")
      cooldown = EmailVerification.resend_cooldown(sent_user)
      assert cooldown > 0
      assert cooldown <= 60
    end
  end
end
