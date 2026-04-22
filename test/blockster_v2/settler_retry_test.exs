defmodule BlocksterV2.SettlerRetryTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.SettlerRetry

  setup do
    :mnesia.start()

    case :mnesia.create_table(:settler_dead_letters,
           attributes: [
             :id,
             :operation_type,
             :operation_id,
             :reason,
             :attempt_count,
             :first_failed_at,
             :last_failed_at,
             :payload
           ],
           ram_copies: [node()],
           type: :set,
           index: [:operation_type, :last_failed_at]
         ) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, :settler_dead_letters}} ->
        :mnesia.clear_table(:settler_dead_letters)
    end

    :ok
  end

  describe "classify/1" do
    test ":manual_review is terminal" do
      assert SettlerRetry.classify(:manual_review) == :terminal
      assert SettlerRetry.classify({:error, :manual_review}) == :terminal
    end

    test "InvalidServerSeed / 0x178a are terminal" do
      assert SettlerRetry.classify("Program failed: InvalidServerSeed") == :terminal
      assert SettlerRetry.classify("custom program error: 0x178a") == :terminal
    end

    test "commitment_mismatch structured tuple is terminal" do
      assert SettlerRetry.classify({:commitment_mismatch, "abc", "def"}) == :terminal
    end

    test "AccountNotInitialized / AccountNotFound / InstructionError are terminal" do
      assert SettlerRetry.classify("AccountNotInitialized") == :terminal
      assert SettlerRetry.classify("AccountNotFound: player state") == :terminal
      assert SettlerRetry.classify("InstructionError: Custom(0)") == :terminal
    end

    test "TransportError / timeout / BlockhashNotFound are transient" do
      assert SettlerRetry.classify("TransportError") == :transient
      assert SettlerRetry.classify("Request timeout after 60s") == :transient
      assert SettlerRetry.classify("BlockhashNotFound") == :transient
      assert SettlerRetry.classify("ECONNREFUSED") == :transient
    end

    test "unknown strings default to :retry" do
      assert SettlerRetry.classify("something weird happened") == :retry
      assert SettlerRetry.classify(%{unexpected: "shape"}) == :retry
    end
  end

  describe "backoff_delay/1" do
    test "follows the audit's [10, 30, 90, 270, 810, 900] schedule" do
      assert SettlerRetry.backoff_delay(0) == 10
      assert SettlerRetry.backoff_delay(1) == 30
      assert SettlerRetry.backoff_delay(2) == 90
      assert SettlerRetry.backoff_delay(3) == 270
      assert SettlerRetry.backoff_delay(4) == 810
      assert SettlerRetry.backoff_delay(5) == 900
    end

    test "caps at 900s past the schedule end" do
      assert SettlerRetry.backoff_delay(10) == 900
      assert SettlerRetry.backoff_delay(100) == 900
    end

    test "full schedule is exposed for callers" do
      assert SettlerRetry.backoff_schedule() == [10, 30, 90, 270, 810, 900]
    end
  end

  describe "maybe_upgrade_to_terminal/1" do
    test "upgrades to :terminal at or past the attempt cap" do
      cap = SettlerRetry.terminal_attempt_cap()
      assert SettlerRetry.maybe_upgrade_to_terminal(cap) == :terminal
      assert SettlerRetry.maybe_upgrade_to_terminal(cap + 10) == :terminal
    end

    test "stays :retry below the cap" do
      assert SettlerRetry.maybe_upgrade_to_terminal(0) == :retry
      assert SettlerRetry.maybe_upgrade_to_terminal(1) == :retry
      assert SettlerRetry.maybe_upgrade_to_terminal(2) == :retry
    end
  end

  describe "park_dead_letter/3 + list_dead_letters/0" do
    test "writes a row that list_dead_letters/0 can read back" do
      SettlerRetry.park_dead_letter(:coin_flip, "game_aaa", %{
        reason: "InvalidServerSeed",
        attempt_count: 3,
        user_id: 42
      })

      rows = SettlerRetry.list_dead_letters()
      assert length(rows) == 1
      row = hd(rows)
      assert row.operation_type == :coin_flip
      assert row.operation_id == "game_aaa"
      assert row.attempt_count == 3
      assert row.payload[:user_id] == 42
      assert is_integer(row.first_failed_at)
      assert is_integer(row.last_failed_at)
    end

    test "count_by_type groups rows by operation_type" do
      SettlerRetry.park_dead_letter(:coin_flip, "game_1", %{})
      SettlerRetry.park_dead_letter(:coin_flip, "game_2", %{})
      SettlerRetry.park_dead_letter(:bux_mint, "mint_1", %{})

      counts = SettlerRetry.count_by_type()
      assert counts[:coin_flip] == 2
      assert counts[:bux_mint] == 1
    end

    test "resolve/2 removes the row" do
      SettlerRetry.park_dead_letter(:coin_flip, "to_resolve", %{reason: "x"})
      assert length(SettlerRetry.list_dead_letters()) >= 1

      SettlerRetry.resolve(:coin_flip, "to_resolve")
      assert Enum.all?(SettlerRetry.list_dead_letters(), fn r -> r.operation_id != "to_resolve" end)
    end
  end
end
