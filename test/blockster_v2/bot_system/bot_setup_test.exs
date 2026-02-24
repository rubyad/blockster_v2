defmodule BlocksterV2.BotSystem.BotSetupTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.BotSystem.BotSetup
  alias BlocksterV2.Accounts.User

  setup do
    # Ensure unified_multipliers Mnesia table exists for tests
    case :mnesia.create_table(:unified_multipliers, [
      type: :set,
      attributes: [:user_id, :x_score, :x_multiplier, :phone_multiplier,
                   :rogue_multiplier, :wallet_multiplier, :overall_multiplier,
                   :last_updated, :created_at],
      index: [:overall_multiplier],
      ram_copies: [node()]
    ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :unified_multipliers}} -> :ok
    end

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
    test "creates a user with correct attributes" do
      {:ok, user} = BotSetup.create_bot(1)

      assert user.email == "bot_0001@blockster.bot"
      assert user.is_bot == true
      assert user.auth_method == "email"
      assert String.starts_with?(user.wallet_address, "0x")
      assert String.length(user.wallet_address) == 42
      assert String.starts_with?(user.smart_wallet_address, "0x")
      assert String.length(user.smart_wallet_address) == 42
      assert user.wallet_address != user.smart_wallet_address
      assert is_binary(user.username)
    end

    test "wallet and smart_wallet are different" do
      {:ok, user} = BotSetup.create_bot(5)
      assert user.wallet_address != user.smart_wallet_address
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

      case :mnesia.dirty_read({:unified_multipliers, user.id}) do
        [record] ->
          # Check all fields are set
          assert elem(record, 0) == :unified_multipliers
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
        case :mnesia.dirty_read({:unified_multipliers, id}) do
          [record] -> elem(record, 7)
          [] -> 0.0
        end
      end)

      # All should be positive
      assert Enum.all?(multipliers, fn m -> m > 0 end)

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
end
