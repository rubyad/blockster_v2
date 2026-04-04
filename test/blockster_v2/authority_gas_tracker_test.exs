defmodule BlocksterV2.AuthorityGasTrackerTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.AuthorityGasTracker

  @table :authority_gas_tracker

  setup do
    :mnesia.start()

    case :mnesia.create_table(@table, [
           attributes: [:date, :mint_count, :ata_creations, :total_tx_fees_lamports, :total_ata_rent_lamports, :authority_balance_lamports],
           ram_copies: [node()],
           type: :set
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, @table}} ->
        case :mnesia.add_table_copy(@table, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, @table, _}} -> :ok
        end
        :mnesia.clear_table(@table)
    end

    :ok
  end

  describe "record_mint/1" do
    test "increments mint count and adds tx fee" do
      assert :ok = AuthorityGasTracker.record_mint()

      stats = AuthorityGasTracker.get_today()
      assert stats.mint_count == 1
      assert stats.ata_creations == 0
      assert stats.total_tx_fees_lamports == 5_000
      assert stats.total_ata_rent_lamports == 0
    end

    test "increments multiple mints correctly" do
      AuthorityGasTracker.record_mint()
      AuthorityGasTracker.record_mint()
      AuthorityGasTracker.record_mint()

      stats = AuthorityGasTracker.get_today()
      assert stats.mint_count == 3
      assert stats.total_tx_fees_lamports == 15_000
    end

    test "tracks ATA creation when ata_created is true" do
      AuthorityGasTracker.record_mint(true)

      stats = AuthorityGasTracker.get_today()
      assert stats.mint_count == 1
      assert stats.ata_creations == 1
      assert stats.total_tx_fees_lamports == 5_000
      assert stats.total_ata_rent_lamports == 2_039_280
    end

    test "mixed mints with and without ATA creation" do
      AuthorityGasTracker.record_mint(false)
      AuthorityGasTracker.record_mint(true)
      AuthorityGasTracker.record_mint(false)
      AuthorityGasTracker.record_mint(true)

      stats = AuthorityGasTracker.get_today()
      assert stats.mint_count == 4
      assert stats.ata_creations == 2
      assert stats.total_tx_fees_lamports == 20_000
      assert stats.total_ata_rent_lamports == 2 * 2_039_280
    end
  end

  describe "update_authority_balance/1" do
    test "stores balance for today" do
      assert :ok = AuthorityGasTracker.update_authority_balance(5_000_000_000)

      stats = AuthorityGasTracker.get_today()
      assert stats.authority_balance_lamports == 5_000_000_000
    end

    test "preserves other fields when updating balance" do
      AuthorityGasTracker.record_mint(true)
      AuthorityGasTracker.update_authority_balance(3_000_000_000)

      stats = AuthorityGasTracker.get_today()
      assert stats.mint_count == 1
      assert stats.ata_creations == 1
      assert stats.total_tx_fees_lamports == 5_000
      assert stats.total_ata_rent_lamports == 2_039_280
      assert stats.authority_balance_lamports == 3_000_000_000
    end
  end

  describe "get_today/0" do
    test "returns nil when no data exists" do
      assert AuthorityGasTracker.get_today() == nil
    end

    test "returns today's record after recording a mint" do
      AuthorityGasTracker.record_mint()
      stats = AuthorityGasTracker.get_today()

      assert stats.date == Date.utc_today()
      assert stats.mint_count == 1
    end
  end

  describe "get_daily_stats/1" do
    test "returns empty list when no data" do
      assert AuthorityGasTracker.get_daily_stats(7) == []
    end

    test "returns today's stats" do
      AuthorityGasTracker.record_mint()

      stats = AuthorityGasTracker.get_daily_stats(7)
      assert length(stats) == 1
      assert hd(stats).date == Date.utc_today()
    end

    test "daily rollover - records for different dates do not interfere" do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      # Manually write a record for yesterday
      :mnesia.dirty_write({@table, yesterday, 10, 3, 50_000, 6_117_840, 2_000_000_000})

      # Record for today
      AuthorityGasTracker.record_mint(true)

      stats = AuthorityGasTracker.get_daily_stats(7)
      assert length(stats) == 2

      today_stats = Enum.find(stats, &(&1.date == today))
      yesterday_stats = Enum.find(stats, &(&1.date == yesterday))

      assert today_stats.mint_count == 1
      assert today_stats.ata_creations == 1

      assert yesterday_stats.mint_count == 10
      assert yesterday_stats.ata_creations == 3
      assert yesterday_stats.authority_balance_lamports == 2_000_000_000
    end

    test "only returns stats within the requested day range" do
      today = Date.utc_today()
      eight_days_ago = Date.add(today, -8)

      # Write record for 8 days ago (outside 7-day window)
      :mnesia.dirty_write({@table, eight_days_ago, 5, 1, 25_000, 2_039_280, 1_000_000_000})

      # Write record for today
      AuthorityGasTracker.record_mint()

      stats = AuthorityGasTracker.get_daily_stats(7)
      assert length(stats) == 1
      assert hd(stats).date == today
    end
  end

  describe "constants" do
    test "tx_fee_lamports is 5000" do
      assert AuthorityGasTracker.tx_fee_lamports() == 5_000
    end

    test "ata_rent_lamports is 2039280" do
      assert AuthorityGasTracker.ata_rent_lamports() == 2_039_280
    end
  end
end
