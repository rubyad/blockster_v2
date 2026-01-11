defmodule HighRollers.DataMigration do
  @moduledoc """
  Migrate data from Node.js SQLite to Elixir Mnesia (Optimized Schema).
  Run once during deployment transition.

  ## Key Difference from Old Schema
  This migration JOINs multiple SQLite tables into the unified hr_nfts table:
  - nfts (core data)
  - sales (original_buyer, block_number)
  - nft_earnings (revenue share data)
  - time_reward_nfts (time reward fields for tokens 2340-2700)

  ## Usage

      # Copy SQLite database from Node.js app to accessible path
      # Then run from IEx:
      HighRollers.DataMigration.run("/path/to/high_rollers.db")

  ## What Gets Migrated

  - 2,342 NFTs with ALL data unified into single hr_nfts records:
    - Core: token_id, owner, hostess_index, hostess_name
    - Sales: original_buyer, mint_block_number, mint_tx_hash, mint_price
    - Earnings: total_earned, pending_amount, last_24h_earned, apy_basis_points
    - Time Rewards: time_start_time, time_last_claim, time_total_claimed (tokens 2340-2700)
  - Affiliate earnings (direct copy)
  - Reward events (direct copy)
  - Reward withdrawals (direct copy)
  - Pending mints (direct copy)

  ## CRITICAL: Set last_processed_block

  After migration, you MUST set the last_processed_block for both pollers
  to a block BEFORE any existing events, otherwise they'll skip historical data.
  """

  require Logger

  @doc """
  Run the full migration from SQLite to Mnesia.

  ## Parameters
    - db_path: Path to the SQLite database file (high_rollers.db)

  ## Returns
    A map with counts of migrated records per table.
  """
  def run(db_path) do
    Logger.info("[DataMigration] Starting migration from #{db_path}")

    {:ok, db} = Exqlite.Sqlite3.open(db_path)

    # Migrate unified NFT data first (JOINs 4 SQLite tables)
    nft_count = migrate_unified_nfts(db)

    # Migrate remaining tables
    results = %{
      nfts: nft_count,
      affiliate_earnings: migrate_affiliate_earnings(db),
      reward_events: migrate_reward_events(db),
      reward_withdrawals: migrate_reward_withdrawals(db),
      pending_mints: migrate_pending_mints(db)
    }

    Exqlite.Sqlite3.close(db)

    Logger.info("[DataMigration] Migration complete!")
    Logger.info("[DataMigration] Results: #{inspect(results)}")

    # CRITICAL REMINDER
    Logger.warning("""
    [DataMigration] CRITICAL: You must now set last_processed_block for pollers!

    Run in IEx:
      # For ArbitrumEventPoller - set to block before first NFTMinted event
      :mnesia.dirty_write({:hr_poller_state, :arbitrum, 123456789})

      # For RogueRewardPoller - set to block before first RewardReceived event
      :mnesia.dirty_write({:hr_poller_state, :rogue, 1234567})
    """)

    results
  end

  @doc """
  Run migration with dry-run option to preview what would be migrated.
  """
  def dry_run(db_path) do
    Logger.info("[DataMigration] DRY RUN - previewing migration from #{db_path}")

    {:ok, db} = Exqlite.Sqlite3.open(db_path)

    counts = %{
      nfts: count_unified_nfts(db),
      affiliate_earnings: count_table(db, "affiliate_earnings"),
      reward_events: count_table(db, "reward_events"),
      reward_withdrawals: count_table(db, "reward_withdrawals"),
      pending_mints: count_table(db, "pending_mints")
    }

    Exqlite.Sqlite3.close(db)

    Logger.info("[DataMigration] DRY RUN Results: #{inspect(counts)}")
    counts
  end

  # ===== UNIFIED NFT MIGRATION =====
  # JOINs: nfts + sales + nft_earnings + time_reward_nfts → hr_nfts

  defp migrate_unified_nfts(db) do
    # Query that JOINs all 4 tables
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db, """
      SELECT
        n.token_id,
        n.owner,
        n.hostess_index,
        n.hostess_name,
        n.mint_price,
        n.affiliate,
        n.affiliate2,
        n.created_at as mint_timestamp,
        -- From sales table (LEFT JOIN - may be null for some NFTs)
        s.buyer as original_buyer,
        s.tx_hash as mint_tx_hash,
        s.block_number as mint_block_number,
        -- From nft_earnings table (LEFT JOIN - may be null)
        e.total_earned,
        e.pending_amount,
        e.last_24h_earned,
        e.apy_basis_points,
        -- From time_reward_nfts table (LEFT JOIN - only for tokens 2340-2700)
        t.start_time as time_start_time,
        t.last_claim_time as time_last_claim,
        t.total_claimed as time_total_claimed
      FROM nfts n
      LEFT JOIN sales s ON s.token_id = n.token_id
      LEFT JOIN nft_earnings e ON e.token_id = n.token_id
      LEFT JOIN time_reward_nfts t ON t.token_id = n.token_id
      ORDER BY n.token_id
    """)

    now = System.system_time(:second)

    count = migrate_rows(db, stmt, fn row ->
      [token_id, owner, hostess_index, hostess_name, mint_price, affiliate, affiliate2, mint_timestamp,
       original_buyer, mint_tx_hash, mint_block_number,
       total_earned, pending_amount, last_24h_earned, apy_basis_points,
       time_start_time, time_last_claim, time_total_claimed] = row

      # Build unified hr_nfts record (matches table definition order)
      record = {:hr_nfts,
        # Core Identity
        token_id,
        downcase(owner),
        downcase(original_buyer || owner),  # original_buyer defaults to owner if null
        hostess_index,
        hostess_name,

        # Mint Data
        mint_tx_hash,
        mint_block_number,
        mint_price,
        downcase(affiliate),
        downcase(affiliate2),

        # Revenue Share Earnings (defaults to "0" if null)
        total_earned || "0",
        pending_amount || "0",
        last_24h_earned || "0",
        apy_basis_points || 0,

        # Time Rewards (nil for regular NFTs, populated for tokens 2340-2700)
        time_start_time,
        time_last_claim,
        # Convert total_claimed to string format if present
        convert_time_total_claimed(time_total_claimed),

        # Timestamps
        mint_timestamp || now,  # created_at
        now                     # updated_at
      }

      :mnesia.dirty_write(record)
    end)

    Logger.info("[DataMigration] Migrated #{count} unified NFT records")
    count
  end

  defp count_unified_nfts(db) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db, "SELECT COUNT(*) FROM nfts")
    {:row, [count]} = Exqlite.Sqlite3.step(db, stmt)
    count
  end

  # ===== DIRECT COPY MIGRATIONS =====

  defp migrate_affiliate_earnings(db) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db, """
      SELECT token_id, tier, affiliate, earnings, tx_hash, timestamp
      FROM affiliate_earnings
    """)

    count = migrate_rows(db, stmt, fn [token_id, tier, affiliate, earnings, tx_hash, timestamp] ->
      # hr_affiliate_earnings is a bag type table
      record = {:hr_affiliate_earnings,
        token_id,
        tier,
        downcase(affiliate),
        earnings || "0",
        tx_hash,
        timestamp
      }
      :mnesia.dirty_write(record)
    end)

    Logger.info("[DataMigration] Migrated #{count} affiliate earnings records")
    count
  end

  defp migrate_reward_events(db) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db, """
      SELECT commitment_hash, amount, timestamp, block_number, tx_hash
      FROM reward_events
    """)

    count = migrate_rows(db, stmt, fn [commitment_hash, amount, timestamp, block_number, tx_hash] ->
      # Natural key: commitment_hash (unique bet ID from blockchain event)
      record = {:hr_reward_events, commitment_hash, amount, timestamp, block_number, tx_hash}
      :mnesia.dirty_write(record)
    end)

    Logger.info("[DataMigration] Migrated #{count} reward events")
    count
  end

  defp migrate_reward_withdrawals(db) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db, """
      SELECT user_address, amount, token_ids, timestamp, tx_hash
      FROM reward_withdrawals
    """)

    count = migrate_rows(db, stmt, fn [user, amount, token_ids_json, timestamp, tx_hash] ->
      token_ids = Jason.decode!(token_ids_json || "[]")
      # Natural key: tx_hash (unique transaction hash)
      record = {:hr_reward_withdrawals, tx_hash, downcase(user), amount, token_ids, timestamp}
      :mnesia.dirty_write(record)
    end)

    Logger.info("[DataMigration] Migrated #{count} reward withdrawals")
    count
  end

  defp migrate_pending_mints(db) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db, """
      SELECT request_id, sender, token_id, price, tx_hash, created_at
      FROM pending_mints
    """)

    count = migrate_rows(db, stmt, fn [request_id, sender, token_id, price, tx_hash, created_at] ->
      record = {:hr_pending_mints, request_id, downcase(sender), token_id, price, tx_hash, created_at}
      :mnesia.dirty_write(record)
    end)

    Logger.info("[DataMigration] Migrated #{count} pending mints")
    count
  end

  # ===== Helpers =====

  defp migrate_rows(db, stmt, insert_fn) do
    do_migrate_rows(db, stmt, insert_fn, 0)
  end

  defp do_migrate_rows(db, stmt, insert_fn, count) do
    case Exqlite.Sqlite3.step(db, stmt) do
      {:row, row} ->
        insert_fn.(row)
        do_migrate_rows(db, stmt, insert_fn, count + 1)
      :done ->
        count
    end
  end

  defp count_table(db, table_name) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db, "SELECT COUNT(*) FROM #{table_name}")
    case Exqlite.Sqlite3.step(db, stmt) do
      {:row, [count]} -> count
      :done -> 0
    end
  end

  defp downcase(nil), do: ""
  defp downcase(str) when is_binary(str), do: String.downcase(str)
  defp downcase(other), do: to_string(other)

  # Convert time_total_claimed from SQLite (may be REAL/float) to Wei string
  defp convert_time_total_claimed(nil), do: nil
  defp convert_time_total_claimed(value) when is_float(value) do
    # SQLite stores as REAL, convert to Wei string (multiply by 1e18)
    value
    |> Kernel.*(1_000_000_000_000_000_000)
    |> trunc()
    |> Integer.to_string()
  end
  defp convert_time_total_claimed(value) when is_integer(value) do
    # Already an integer (wei), convert to string
    Integer.to_string(value)
  end
  defp convert_time_total_claimed(value) when is_binary(value), do: value

  # ===== Verification Helpers =====

  @doc """
  Verify migration by comparing counts between SQLite and Mnesia.
  """
  def verify(db_path) do
    Logger.info("[DataMigration] Verifying migration...")

    {:ok, db} = Exqlite.Sqlite3.open(db_path)

    sqlite_counts = %{
      nfts: count_table(db, "nfts"),
      affiliate_earnings: count_table(db, "affiliate_earnings"),
      reward_events: count_table(db, "reward_events"),
      reward_withdrawals: count_table(db, "reward_withdrawals"),
      pending_mints: count_table(db, "pending_mints")
    }

    Exqlite.Sqlite3.close(db)

    mnesia_counts = %{
      nfts: :mnesia.table_info(:hr_nfts, :size),
      affiliate_earnings: :mnesia.table_info(:hr_affiliate_earnings, :size),
      reward_events: :mnesia.table_info(:hr_reward_events, :size),
      reward_withdrawals: :mnesia.table_info(:hr_reward_withdrawals, :size),
      pending_mints: :mnesia.table_info(:hr_pending_mints, :size)
    }

    results = %{
      sqlite: sqlite_counts,
      mnesia: mnesia_counts,
      match: sqlite_counts == mnesia_counts
    }

    if results.match do
      Logger.info("[DataMigration] ✅ Verification PASSED - all counts match")
    else
      Logger.warning("[DataMigration] ⚠️ Verification FAILED - counts don't match")
      Logger.warning("[DataMigration] SQLite: #{inspect(sqlite_counts)}")
      Logger.warning("[DataMigration] Mnesia: #{inspect(mnesia_counts)}")
    end

    results
  end

  @doc """
  Set the poller block numbers after migration.
  This should be called with block numbers BEFORE any existing events.

  ## Example
      HighRollers.DataMigration.set_poller_blocks(
        arbitrum: 289_000_000,  # Block before first NFTMinted
        rogue: 1_000_000        # Block before first RewardReceived
      )
  """
  def set_poller_blocks(opts) do
    arbitrum_block = Keyword.get(opts, :arbitrum)
    rogue_block = Keyword.get(opts, :rogue)

    if arbitrum_block do
      :mnesia.dirty_write({:hr_poller_state, :arbitrum, arbitrum_block})
      Logger.info("[DataMigration] Set Arbitrum poller to block #{arbitrum_block}")
    end

    if rogue_block do
      :mnesia.dirty_write({:hr_poller_state, :rogue, rogue_block})
      Logger.info("[DataMigration] Set Rogue poller to block #{rogue_block}")
    end

    :ok
  end

  @doc """
  Get current poller block numbers.
  """
  def get_poller_blocks do
    arbitrum = case :mnesia.dirty_read(:hr_poller_state, :arbitrum) do
      [{:hr_poller_state, :arbitrum, block}] -> block
      [] -> nil
    end

    rogue = case :mnesia.dirty_read(:hr_poller_state, :rogue) do
      [{:hr_poller_state, :rogue, block}] -> block
      [] -> nil
    end

    %{arbitrum: arbitrum, rogue: rogue}
  end
end
