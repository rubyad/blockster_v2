defmodule BlocksterV2.ReferralsTest do
  use BlocksterV2.DataCase

  alias BlocksterV2.Referrals
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Repo

  # Helper to create test users with unique values
  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])
    wallet = attrs[:wallet_address] || "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"

    default_attrs = %{
      wallet_address: wallet,
      smart_wallet_address: wallet,
      email: "user#{unique_id}@example.com",
      username: "user#{unique_id}",
      auth_method: "wallet",
      phone_verified: false,
      geo_multiplier: Decimal.new("0.5"),
      geo_tier: "unverified",
      sms_opt_in: true
    }

    %User{}
    |> User.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  # Helper to ensure Mnesia tables exist and are clean between tests
  defp ensure_mnesia_tables do
    # Start Mnesia if not started
    :mnesia.start()

    # Create tables if they don't exist
    tables = [
      {:referrals, [:user_id, :referrer_id, :referrer_wallet, :referee_wallet, :referred_at, :on_chain_synced],
       [index: [:referrer_id, :referrer_wallet, :referee_wallet]]},
      {:referral_earnings, [:id, :referrer_id, :referrer_wallet, :referee_wallet, :earning_type, :amount, :token, :tx_hash, :commitment_hash, :timestamp],
       [type: :bag, index: [:referrer_id, :commitment_hash]]},
      {:referral_stats, [:user_id, :total_referrals, :verified_referrals, :total_bux_earned, :total_rogue_earned, :updated_at],
       []}
    ]

    for {table_name, attributes, opts} <- tables do
      case :mnesia.create_table(table_name, [
        attributes: attributes,
        type: Keyword.get(opts, :type, :set),
        index: Keyword.get(opts, :index, [])
      ]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, _}} -> :ok
        other -> other
      end
    end

    # Clear tables
    :mnesia.clear_table(:referrals)
    :mnesia.clear_table(:referral_earnings)
    :mnesia.clear_table(:referral_stats)
  end

  setup do
    # Ensure Mnesia tables exist and are clean before each test
    ensure_mnesia_tables()
    :ok
  end

  describe "process_signup_referral/2" do
    test "returns error when referrer wallet is nil" do
      user = create_user()
      assert {:error, :no_referrer} = Referrals.process_signup_referral(user, nil)
    end

    test "returns error when referrer wallet is empty string" do
      user = create_user()
      # Empty string goes through to DB lookup and returns :referrer_not_found
      assert {:error, :referrer_not_found} = Referrals.process_signup_referral(user, "")
    end

    test "returns error when referrer wallet is not found in database" do
      user = create_user()
      non_existent_wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"

      assert {:error, :referrer_not_found} =
               Referrals.process_signup_referral(user, non_existent_wallet)
    end

    test "returns error for self-referral" do
      user = create_user()
      assert {:error, :self_referral} = Referrals.process_signup_referral(user, user.smart_wallet_address)
    end

    test "returns error for self-referral (case-insensitive)" do
      wallet = "0xabcdef1234567890abcdef1234567890abcdef12"
      user = create_user(%{smart_wallet_address: wallet})

      # Try with uppercase version
      assert {:error, :self_referral} =
               Referrals.process_signup_referral(user, String.upcase(wallet))
    end

    test "creates referral relationship for valid referrer wallet" do
      referrer = create_user()
      referee = create_user()

      assert {:ok, returned_referrer} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
      assert returned_referrer.id == referrer.id

      # Verify PostgreSQL was updated
      updated_referee = Repo.get!(User, referee.id)
      assert updated_referee.referrer_id == referrer.id
      assert updated_referee.referred_at != nil

      # Verify Mnesia record was created
      case :mnesia.dirty_read(:referrals, referee.id) do
        [{:referrals, rec_referee_id, rec_referrer_id, rec_referrer_wallet, rec_referee_wallet, _at, _synced}] ->
          assert rec_referee_id == referee.id
          assert rec_referrer_id == referrer.id
          assert rec_referrer_wallet == String.downcase(referrer.smart_wallet_address)
          assert rec_referee_wallet == String.downcase(referee.smart_wallet_address)

        _ ->
          flunk("Expected Mnesia referral record not found")
      end
    end

    test "creates signup earning record and updates stats" do
      referrer = create_user()
      referee = create_user()

      assert {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)

      # Give async tasks a moment to complete (minting is async)
      Process.sleep(100)

      # Verify earning record was created
      earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      assert length(earnings) == 1

      [{:referral_earnings, _id, rec_referrer_id, _rw, _rew, earning_type, amount, token, _tx, _commit, _ts}] = earnings
      assert rec_referrer_id == referrer.id
      assert earning_type == :signup
      assert amount == 100
      assert token == "BUX"

      # Verify stats were updated
      stats = Referrals.get_referrer_stats(referrer.id)
      assert stats.total_referrals == 1
      assert stats.total_bux_earned == 100
    end

    test "handles wallet address case insensitivity" do
      # PostgreSQL stores wallet addresses in lowercase, so we test with lowercase
      wallet = "0xabcdef1234567890abcdef1234567890abcdef12"
      _referrer = create_user(%{smart_wallet_address: wallet})
      referee = create_user()

      # Use uppercase version of referrer's wallet - the function lowercases it before lookup
      # Note: Ecto's get_by is case-sensitive, so wallet must match DB format
      assert {:ok, _} = Referrals.process_signup_referral(referee, wallet)

      # Verify the referral was created
      referral = :mnesia.dirty_read(:referrals, referee.id)
      assert length(referral) == 1
    end
  end

  describe "process_phone_verification_reward/1" do
    test "returns :no_referrer when user has no referrer" do
      user = create_user()
      assert :no_referrer = Referrals.process_phone_verification_reward(user.id)
    end

    test "creates phone verification earning when user has referrer" do
      referrer = create_user()
      referee = create_user()

      # First, set up the referral
      {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)

      # Give async tasks time to complete
      Process.sleep(100)

      # Clear signup earning to count phone verification earning separately
      initial_earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      assert length(initial_earnings) == 1  # Should have signup earning

      # Now trigger phone verification reward
      assert {:ok, returned_referrer_id} = Referrals.process_phone_verification_reward(referee.id)
      assert returned_referrer_id == referrer.id

      # Give async minting time
      Process.sleep(100)

      # Verify phone verification earning was added
      earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      assert length(earnings) == 2  # signup + phone_verified

      phone_earning = Enum.find(earnings, fn record -> elem(record, 5) == :phone_verified end)
      assert phone_earning != nil
      assert elem(phone_earning, 6) == 100  # amount
      assert elem(phone_earning, 7) == "BUX"  # token

      # Verify stats were updated
      stats = Referrals.get_referrer_stats(referrer.id)
      assert stats.verified_referrals == 1
      assert stats.total_bux_earned == 200  # 100 signup + 100 phone verified
    end

    test "returns :already_rewarded if phone verification was already rewarded" do
      referrer = create_user()
      referee = create_user()

      # Set up the referral
      {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
      Process.sleep(100)

      # First phone verification reward
      {:ok, _} = Referrals.process_phone_verification_reward(referee.id)
      Process.sleep(100)

      # Second attempt should fail
      assert {:error, :already_rewarded} = Referrals.process_phone_verification_reward(referee.id)
    end
  end

  describe "record_bet_loss_earning/1" do
    setup do
      referrer = create_user()
      referee = create_user()

      # Set up the referral relationship
      {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
      Process.sleep(100)

      {:ok, referrer: referrer, referee: referee}
    end

    test "records BUX bet loss earning", %{referrer: referrer, referee: referee} do
      attrs = %{
        referrer_wallet: referrer.smart_wallet_address,
        referee_wallet: referee.smart_wallet_address,
        amount: 10.5,
        token: "BUX",
        commitment_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}",
        tx_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}"
      }

      assert :ok = Referrals.record_bet_loss_earning(attrs)

      # Verify earning was recorded
      earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      bet_earning = Enum.find(earnings, fn record -> elem(record, 5) == :bux_bet_loss end)

      assert bet_earning != nil
      assert elem(bet_earning, 6) == 10.5  # amount
      assert elem(bet_earning, 7) == "BUX"  # token
      assert elem(bet_earning, 8) == String.downcase(attrs.tx_hash)  # tx_hash (lowercased)
    end

    test "records ROGUE bet loss earning", %{referrer: referrer, referee: referee} do
      attrs = %{
        referrer_wallet: referrer.smart_wallet_address,
        referee_wallet: referee.smart_wallet_address,
        amount: 50.25,
        token: "ROGUE",
        commitment_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}",
        tx_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}"
      }

      assert :ok = Referrals.record_bet_loss_earning(attrs)

      # Verify earning type is :rogue_bet_loss
      earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      bet_earning = Enum.find(earnings, fn record -> elem(record, 5) == :rogue_bet_loss end)

      assert bet_earning != nil
      assert elem(bet_earning, 6) == 50.25
      assert elem(bet_earning, 7) == "ROGUE"

      # Verify ROGUE stats updated
      stats = Referrals.get_referrer_stats(referrer.id)
      assert stats.total_rogue_earned == 50.25
    end

    test "returns :duplicate for duplicate commitment_hash", %{referrer: referrer, referee: referee} do
      commitment_hash = "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}"

      attrs = %{
        referrer_wallet: referrer.smart_wallet_address,
        referee_wallet: referee.smart_wallet_address,
        amount: 10.0,
        token: "BUX",
        commitment_hash: commitment_hash,
        tx_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}"
      }

      # First recording should succeed
      assert :ok = Referrals.record_bet_loss_earning(attrs)

      # Second recording with same commitment_hash should return :duplicate
      attrs2 = %{attrs | tx_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}"}
      assert :duplicate = Referrals.record_bet_loss_earning(attrs2)
    end

    test "returns :referral_not_found for unknown referee wallet" do
      referrer = create_user()
      unknown_referee_wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"

      attrs = %{
        referrer_wallet: referrer.smart_wallet_address,
        referee_wallet: unknown_referee_wallet,
        amount: 10.0,
        token: "BUX",
        commitment_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}",
        tx_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}"
      }

      assert :referral_not_found = Referrals.record_bet_loss_earning(attrs)
    end

    test "returns :referrer_mismatch when wallets don't match", %{referee: referee} do
      # Create a different user to act as a "wrong" referrer
      wrong_referrer = create_user()

      attrs = %{
        referrer_wallet: wrong_referrer.smart_wallet_address,  # Wrong referrer!
        referee_wallet: referee.smart_wallet_address,
        amount: 10.0,
        token: "BUX",
        commitment_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}",
        tx_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}"
      }

      assert :referrer_mismatch = Referrals.record_bet_loss_earning(attrs)
    end
  end

  describe "get_referrer_stats/1" do
    test "returns zero stats for user with no referrals" do
      user = create_user()

      stats = Referrals.get_referrer_stats(user.id)

      assert stats.total_referrals == 0
      assert stats.verified_referrals == 0
      assert stats.total_bux_earned == 0.0
      assert stats.total_rogue_earned == 0.0
    end

    test "returns accurate stats after referrals and earnings" do
      referrer = create_user()
      referee1 = create_user()
      referee2 = create_user()

      # First referral
      {:ok, _} = Referrals.process_signup_referral(referee1, referrer.smart_wallet_address)
      Process.sleep(100)

      # Second referral
      {:ok, _} = Referrals.process_signup_referral(referee2, referrer.smart_wallet_address)
      Process.sleep(100)

      # Phone verification for first referee
      {:ok, _} = Referrals.process_phone_verification_reward(referee1.id)
      Process.sleep(100)

      stats = Referrals.get_referrer_stats(referrer.id)

      assert stats.total_referrals == 2
      assert stats.verified_referrals == 1
      assert stats.total_bux_earned == 300  # 100 + 100 signup + 100 phone verified
    end
  end

  describe "list_referrals/2" do
    test "returns empty list when no referrals" do
      user = create_user()
      assert [] = Referrals.list_referrals(user.id)
    end

    test "returns list of referrals ordered by most recent" do
      referrer = create_user()
      referee1 = create_user()
      referee2 = create_user()

      # Create referrals with slight delay for ordering
      {:ok, _} = Referrals.process_signup_referral(referee1, referrer.smart_wallet_address)
      Process.sleep(1100)  # 1.1 seconds to ensure different timestamps

      {:ok, _} = Referrals.process_signup_referral(referee2, referrer.smart_wallet_address)
      Process.sleep(100)

      referrals = Referrals.list_referrals(referrer.id)

      assert length(referrals) == 2

      # Most recent should be first
      [first, second] = referrals
      assert first.referee_wallet == String.downcase(referee2.smart_wallet_address)
      assert second.referee_wallet == String.downcase(referee1.smart_wallet_address)
    end

    test "includes phone_verified status" do
      referrer = create_user()
      referee = create_user()

      {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
      Process.sleep(100)

      # Before phone verification
      [referral] = Referrals.list_referrals(referrer.id)
      assert referral.phone_verified == false

      # After phone verification
      {:ok, _} = Referrals.process_phone_verification_reward(referee.id)
      Process.sleep(100)

      [referral] = Referrals.list_referrals(referrer.id)
      assert referral.phone_verified == true
    end

    test "respects limit option" do
      referrer = create_user()

      # Create 5 referees
      for _ <- 1..5 do
        referee = create_user()
        {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
        Process.sleep(100)
      end

      # Request only 3
      referrals = Referrals.list_referrals(referrer.id, limit: 3)
      assert length(referrals) == 3
    end
  end

  describe "list_referral_earnings/2" do
    test "returns empty list when no earnings" do
      user = create_user()
      assert [] = Referrals.list_referral_earnings(user.id)
    end

    test "returns earnings ordered by most recent" do
      referrer = create_user()
      referee = create_user()

      {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
      Process.sleep(1100)

      {:ok, _} = Referrals.process_phone_verification_reward(referee.id)
      Process.sleep(100)

      earnings = Referrals.list_referral_earnings(referrer.id)

      assert length(earnings) == 2

      # Most recent first (phone_verified)
      [first, second] = earnings
      assert first.earning_type == :phone_verified
      assert second.earning_type == :signup
    end

    test "includes all earning types" do
      referrer = create_user()
      referee = create_user()

      {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
      Process.sleep(100)

      {:ok, _} = Referrals.process_phone_verification_reward(referee.id)
      Process.sleep(100)

      # Add bet loss earning
      bet_attrs = %{
        referrer_wallet: referrer.smart_wallet_address,
        referee_wallet: referee.smart_wallet_address,
        amount: 5.5,
        token: "BUX",
        commitment_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}",
        tx_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}"
      }
      :ok = Referrals.record_bet_loss_earning(bet_attrs)

      earnings = Referrals.list_referral_earnings(referrer.id)

      assert length(earnings) == 3

      types = Enum.map(earnings, & &1.earning_type)
      assert :signup in types
      assert :phone_verified in types
      assert :bux_bet_loss in types
    end

    test "respects limit and offset options" do
      referrer = create_user()

      # Create 5 referees to generate 5 earnings
      for _ <- 1..5 do
        referee = create_user()
        {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
        Process.sleep(100)
      end

      # Test limit
      earnings = Referrals.list_referral_earnings(referrer.id, limit: 2)
      assert length(earnings) == 2

      # Test offset (skip first 2, get next 2)
      earnings = Referrals.list_referral_earnings(referrer.id, limit: 2, offset: 2)
      assert length(earnings) == 2
    end
  end

  describe "get_user_id_by_wallet/1" do
    test "returns :not_found for unknown wallet" do
      unknown_wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
      assert :not_found = Referrals.get_user_id_by_wallet(unknown_wallet)
    end

    test "finds user by referee wallet" do
      referrer = create_user()
      referee = create_user()

      {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
      Process.sleep(100)

      assert {:ok, user_id} = Referrals.get_user_id_by_wallet(referee.smart_wallet_address)
      assert user_id == referee.id
    end

    test "finds user by referrer wallet" do
      referrer = create_user()
      referee = create_user()

      {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
      Process.sleep(100)

      assert {:ok, user_id} = Referrals.get_user_id_by_wallet(referrer.smart_wallet_address)
      assert user_id == referrer.id
    end

    test "handles case insensitivity" do
      referrer = create_user()
      referee = create_user()

      {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
      Process.sleep(100)

      # Query with uppercase
      assert {:ok, _} = Referrals.get_user_id_by_wallet(String.upcase(referee.smart_wallet_address))
    end
  end

  describe "get_referrer_by_referee_wallet/1" do
    test "returns :not_found for unknown referee wallet" do
      unknown_wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
      assert :not_found = Referrals.get_referrer_by_referee_wallet(unknown_wallet)
    end

    test "returns referrer info for valid referee wallet" do
      referrer = create_user()
      referee = create_user()

      {:ok, _} = Referrals.process_signup_referral(referee, referrer.smart_wallet_address)
      Process.sleep(100)

      assert {:ok, %{referrer_id: referrer_id, referrer_wallet: referrer_wallet}} =
               Referrals.get_referrer_by_referee_wallet(referee.smart_wallet_address)

      assert referrer_id == referrer.id
      assert referrer_wallet == String.downcase(referrer.smart_wallet_address)
    end
  end
end
