defmodule BlocksterV2.BotSystem.BotSetupTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.BotSystem.{BotSetup, SolanaWalletCrypto}
  alias BlocksterV2.Accounts.User

  setup do
    # Ensure unified_multipliers_v2 Mnesia table exists for tests
    case :mnesia.create_table(:unified_multipliers_v2, [
      type: :set,
      attributes: [:user_id, :x_score, :x_multiplier, :phone_multiplier,
                   :sol_multiplier, :email_multiplier, :overall_multiplier,
                   :last_updated, :created_at],
      index: [:overall_multiplier],
      ram_copies: [node()]
    ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :unified_multipliers_v2}} -> :ok
    end

    # user_solana_balances is needed for rotate_to_solana_keypairs tests
    # (rotation drops cached balance rows for orphaned EVM wallets).
    case :mnesia.create_table(:user_solana_balances, [
      type: :set,
      attributes: [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance],
      ram_copies: [node()]
    ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :user_solana_balances}} -> :ok
    end

    :mnesia.clear_table(:unified_multipliers_v2)
    :mnesia.clear_table(:user_solana_balances)

    :ok
  end

  describe "bot_email/1" do
    test "formats email with zero-padded index" do
      assert BotSetup.bot_email(1) == "bot_0001@blockster.bot"
      assert BotSetup.bot_email(42) == "bot_0042@blockster.bot"
      assert BotSetup.bot_email(999) == "bot_0999@blockster.bot"
      assert BotSetup.bot_email(1000) == "bot_1000@blockster.bot"
    end
  end

  describe "generate_eth_address/0" do
    test "generates valid hex address" do
      address = BotSetup.generate_eth_address()

      assert String.starts_with?(address, "0x")
      assert String.length(address) == 42
      # All hex chars after 0x
      assert String.match?(address, ~r/^0x[0-9a-f]{40}$/)
    end

    test "generates unique addresses" do
      addresses = for _ <- 1..1000, do: BotSetup.generate_eth_address()
      assert length(Enum.uniq(addresses)) == 1000
    end
  end

  describe "generate_username/1" do
    test "generates a username with prefix_suffix_number format" do
      username = BotSetup.generate_username(1)

      assert is_binary(username)
      parts = String.split(username, "_")
      assert length(parts) == 3
    end

    test "generates unique usernames for different indices" do
      usernames = for i <- 1..100, do: BotSetup.generate_username(i)
      # Due to randomness, most should be unique
      unique_count = length(Enum.uniq(usernames))
      assert unique_count >= 90
    end
  end

  describe "create_bot/1" do
    test "creates a user with a Solana wallet and ed25519 secret key" do
      {:ok, user} = BotSetup.create_bot(1)

      assert user.email == "bot_0001@blockster.bot"
      assert user.is_bot == true
      assert user.auth_method == "email"

      # wallet_address must be a valid Solana base58 pubkey (32 bytes)
      refute String.starts_with?(user.wallet_address, "0x")
      assert SolanaWalletCrypto.solana_address?(user.wallet_address)

      # bot_private_key must be a base58-encoded 64-byte Solana secret key
      refute String.starts_with?(user.bot_private_key, "0x")
      assert byte_size(Base58.decode(user.bot_private_key)) == 64

      # smart_wallet_address remains a 0x placeholder for legacy schema compat
      # but is no longer used by the bot system.
      assert String.starts_with?(user.smart_wallet_address, "0x")
      assert user.wallet_address != user.smart_wallet_address
      assert is_binary(user.username)
    end

    test "different bots get unique Solana wallets" do
      {:ok, a} = BotSetup.create_bot(5)
      {:ok, b} = BotSetup.create_bot(6)
      assert a.wallet_address != b.wallet_address
      assert a.bot_private_key != b.bot_private_key
    end
  end

  describe "create_all_bots/1" do
    test "creates specified number of bots" do
      {:ok, created} = BotSetup.create_all_bots(5)
      assert created == 5

      count = Repo.one(from u in User, where: u.is_bot == true, select: count(u.id))
      assert count == 5
    end

    test "is idempotent — calling twice doesn't duplicate" do
      {:ok, 5} = BotSetup.create_all_bots(5)
      {:ok, 0} = BotSetup.create_all_bots(5)

      count = Repo.one(from u in User, where: u.is_bot == true, select: count(u.id))
      assert count == 5
    end

    test "creates remaining bots if some already exist" do
      {:ok, 3} = BotSetup.create_all_bots(3)
      {:ok, 2} = BotSetup.create_all_bots(5)

      count = Repo.one(from u in User, where: u.is_bot == true, select: count(u.id))
      assert count == 5
    end
  end

  describe "seed_multiplier/3" do
    test "writes valid record to Mnesia" do
      {:ok, user} = BotSetup.create_bot(1)
      assert :ok = BotSetup.seed_multiplier(user.id, 1, 100)

      case :mnesia.dirty_read({:unified_multipliers_v2, user.id}) do
        [record] ->
          # Check all fields are set
          assert elem(record, 0) == :unified_multipliers_v2
          assert elem(record, 1) == user.id
          assert is_float(elem(record, 7))  # overall_multiplier
          assert elem(record, 7) > 0
        [] ->
          flunk("Mnesia record not found for user #{user.id}")
      end
    end

    test "multiplier distribution creates varied tiers" do
      # Create 100 bots and check multiplier diversity
      {:ok, _} = BotSetup.create_all_bots(100)
      bot_ids = BotSetup.get_all_bot_ids()

      multipliers = Enum.map(bot_ids, fn id ->
        case :mnesia.dirty_read({:unified_multipliers_v2, id}) do
          [record] -> elem(record, 7)
          [] -> 0.0
        end
      end)

      # All should be non-negative (casual bots may have 0.0 SOL multiplier → 0.0 overall)
      assert Enum.all?(multipliers, fn m -> m >= 0 end)

      # Should have some variation
      min_mult = Enum.min(multipliers)
      max_mult = Enum.max(multipliers)
      assert max_mult > min_mult * 2, "Expected meaningful multiplier variation"

      # Casual tier (low multipliers) should exist
      low_mults = Enum.count(multipliers, fn m -> m < 2.0 end)
      assert low_mults > 0, "Expected some low multipliers (casual tier)"

      # Higher tier multipliers should exist
      high_mults = Enum.count(multipliers, fn m -> m > 5.0 end)
      assert high_mults > 0, "Expected some high multipliers"
    end
  end

  describe "get_all_bot_ids/0" do
    test "returns bot IDs in order" do
      {:ok, _} = BotSetup.create_all_bots(5)
      ids = BotSetup.get_all_bot_ids()

      assert length(ids) == 5
      assert ids == Enum.sort(ids)
    end

    test "returns empty list when no bots exist" do
      assert BotSetup.get_all_bot_ids() == []
    end
  end

  describe "bot_count/0" do
    test "returns correct count" do
      assert BotSetup.bot_count() == 0
      {:ok, _} = BotSetup.create_all_bots(3)
      assert BotSetup.bot_count() == 3
    end
  end

  describe "rotate_to_solana_keypairs/0" do
    test "rotates EVM bots onto Solana keypairs and clears stale balance cache" do
      # Create three "legacy EVM" bots by inserting users directly with 0x wallets,
      # bypassing create_bot/1 which would already produce Solana wallets.
      evm_bots =
        for i <- 1..3 do
          random_hex = :crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)
          random_smart = :crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)

          {:ok, user} =
            User.email_registration_changeset(%{
              email: "legacy_#{i}@blockster.bot",
              wallet_address: "0x" <> random_hex,
              smart_wallet_address: "0x" <> random_smart,
              username: "legacy_bot_#{i}"
            })
            |> Ecto.Changeset.put_change(:is_bot, true)
            |> Ecto.Changeset.put_change(:bot_private_key, "0xdeadbeef")
            |> Repo.insert()

          # Seed a stale solana balance row so we can verify it gets cleared.
          :mnesia.dirty_write(
            {:user_solana_balances, user.id, "0x" <> random_hex,
             System.system_time(:second), 1.23, 456.0}
          )

          user
        end

      # Sanity: cached rows exist before rotation
      Enum.each(evm_bots, fn bot ->
        assert [_] = :mnesia.dirty_read({:user_solana_balances, bot.id})
      end)

      assert {:ok, 3} = BotSetup.rotate_to_solana_keypairs()

      # Each bot now has a valid Solana wallet + 64-byte base58 secret key,
      # and its stale balance row has been deleted.
      Enum.each(evm_bots, fn bot ->
        reloaded = Repo.get!(User, bot.id)
        refute String.starts_with?(reloaded.wallet_address, "0x")
        assert SolanaWalletCrypto.solana_address?(reloaded.wallet_address)
        assert byte_size(Base58.decode(reloaded.bot_private_key)) == 64

        assert [] = :mnesia.dirty_read({:user_solana_balances, bot.id})
      end)
    end

    test "is idempotent — bots already on Solana wallets are skipped" do
      # First call: create three bots via create_bot/1 (already Solana).
      for i <- 1..3, do: {:ok, _} = BotSetup.create_bot(i)

      # First rotation should be a no-op.
      assert {:ok, 0} = BotSetup.rotate_to_solana_keypairs()

      # Snapshot wallets before second rotation.
      before =
        Repo.all(from u in User, where: u.is_bot == true, select: {u.id, u.wallet_address})
        |> Map.new()

      # Second rotation is also a no-op, wallets unchanged.
      assert {:ok, 0} = BotSetup.rotate_to_solana_keypairs()

      after_rot =
        Repo.all(from u in User, where: u.is_bot == true, select: {u.id, u.wallet_address})
        |> Map.new()

      assert before == after_rot
    end

    test "only rotates bots whose wallet is not a valid Solana address" do
      # One legacy EVM bot
      {:ok, evm} =
        User.email_registration_changeset(%{
          email: "legacy_mixed@blockster.bot",
          wallet_address: "0x" <> (:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)),
          smart_wallet_address: "0x" <> (:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)),
          username: "legacy_mixed_bot"
        })
        |> Ecto.Changeset.put_change(:is_bot, true)
        |> Ecto.Changeset.put_change(:bot_private_key, "0xdeadbeef")
        |> Repo.insert()

      # One already-Solana bot
      {:ok, sol} = BotSetup.create_bot(99)
      sol_wallet_before = sol.wallet_address

      assert {:ok, 1} = BotSetup.rotate_to_solana_keypairs()

      reloaded_evm = Repo.get!(User, evm.id)
      reloaded_sol = Repo.get!(User, sol.id)

      assert SolanaWalletCrypto.solana_address?(reloaded_evm.wallet_address)
      refute String.starts_with?(reloaded_evm.wallet_address, "0x")

      # The Solana bot is untouched.
      assert reloaded_sol.wallet_address == sol_wallet_before
    end
  end
end
