defmodule HighRollers.MnesiaInitializer do
  @moduledoc """
  Initializes Mnesia tables for the High Rollers NFT application.

  Tables:
  1. hr_nfts - Core NFT data (unified with earnings and time rewards)
  2. hr_reward_events - Append-only log of RewardReceived events
  3. hr_reward_withdrawals - User withdrawal history
  4. hr_users - Buyer-affiliate mapping
  5. hr_affiliate_earnings - Affiliate commission records (bag type)
  6. hr_pending_mints - VRF waiting records
  7. hr_admin_ops - Pending admin operations queue
  8. hr_stats - Global, per-hostess, and time reward stats
  9. hr_poller_state - Persisted block numbers for pollers

  Single-node setup - no clustering, no schema deletion.
  """
  use GenServer
  require Logger

  @tables [
    # ===== NFT DATA (UNIFIED) =====
    # Combines: NFT core data + earnings + time rewards + mint data
    %{
      name: :hr_nfts,
      type: :set,
      attributes: [
        # === Core Identity (positions 1-5) ===
        :token_id,           # Primary key (integer 1-2342+)
        :owner,              # Current wallet address (string, indexed)
        :original_buyer,     # First owner at mint time (string, indexed)
        :hostess_index,      # 0-7 (integer, indexed)
        :hostess_name,       # "Penelope Fatale", etc. (string)

        # === Mint Data (positions 6-10) ===
        :mint_tx_hash,       # Arbitrum tx hash (string)
        :mint_block_number,  # Arbitrum block number (integer)
        :mint_price,         # Wei string
        :affiliate,          # Tier 1 affiliate address (string)
        :affiliate2,         # Tier 2 affiliate address (string)

        # === Revenue Share Earnings (positions 11-14) ===
        :total_earned,       # Wei string (from contract, default "0")
        :pending_amount,     # Wei string (from contract, default "0")
        :last_24h_earned,    # Wei string (calculated, default "0")
        :apy_basis_points,   # Integer (calculated, default 0)

        # === Time Rewards (positions 15-17) ===
        :time_start_time,    # Unix timestamp when time rewards started (nil for regular NFTs)
        :time_last_claim,    # Unix timestamp of last claim (nil for regular NFTs)
        :time_total_claimed, # Total ROGUE claimed (Wei string, nil for regular NFTs)

        # === Timestamps (positions 18-19) ===
        :created_at,         # Unix timestamp (mint time)
        :updated_at          # Unix timestamp (last earnings sync)
      ],
      indices: [:owner, :original_buyer, :hostess_index]
    },

    # ===== REWARD EVENTS (Append-only log from RewardReceived events) =====
    %{
      name: :hr_reward_events,
      type: :set,
      attributes: [
        :commitment_hash,    # Primary key - unique bet ID from RewardReceived event (string)
        :amount,             # Wei string
        :timestamp,          # Block timestamp (integer)
        :block_number,       # Block number (integer)
        :tx_hash             # Transaction hash (string)
      ],
      indices: [:timestamp]
    },

    # ===== REWARD WITHDRAWALS (User claims) =====
    %{
      name: :hr_reward_withdrawals,
      type: :set,
      attributes: [
        :tx_hash,            # Primary key - unique transaction hash (string)
        :user_address,       # Wallet address (string, indexed)
        :amount,             # Wei string
        :token_ids,          # List of token IDs (list)
        :timestamp           # Unix timestamp
      ],
      indices: [:user_address]
    },

    # ===== USERS (Buyer-Affiliate Mapping) =====
    %{
      name: :hr_users,
      type: :set,
      attributes: [
        :wallet_address,     # Primary key - user's wallet (string, lowercase)
        :affiliate,          # Tier 1 affiliate address (string, indexed)
        :affiliate2,         # Tier 2 affiliate address (string)
        :affiliate_balance,  # Accumulated affiliate earnings in wei (string, default "0")
        :total_affiliate_earned, # Total affiliate earnings ever (string, default "0")
        :linked_at,          # Unix timestamp when affiliate was linked
        :linked_on_chain,    # Boolean - whether linkAffiliate() was called on contract
        :created_at,         # Unix timestamp
        :updated_at          # Unix timestamp
      ],
      indices: [:affiliate]
    },

    # ===== AFFILIATE EARNINGS =====
    # Bag type allows multiple earnings per token_id (one per tier)
    %{
      name: :hr_affiliate_earnings,
      type: :bag,
      attributes: [
        :token_id,           # Token this earning is for (integer) - bag key
        :tier,               # 1 or 2 (integer)
        :affiliate,          # Affiliate address (string, indexed)
        :earnings,           # Wei string
        :tx_hash,            # Transaction hash (string)
        :timestamp           # Unix timestamp when earning occurred
      ],
      indices: [:affiliate]
    },

    # ===== PENDING MINTS (VRF waiting) =====
    %{
      name: :hr_pending_mints,
      type: :set,
      attributes: [
        :request_id,         # Primary key (string)
        :sender,             # Wallet address (string)
        :token_id,           # Expected token ID (integer)
        :price,              # Wei string
        :tx_hash,            # Transaction hash (string)
        :created_at          # Unix timestamp
      ],
      indices: []
    },

    # ===== ADMIN OPERATIONS (UNIFIED) =====
    # Combines pending ops + dead letter queue
    %{
      name: :hr_admin_ops,
      type: :set,
      attributes: [
        :key,                # Primary key: {token_id, operation} tuple
        :args,               # Operation-specific args as map
        :status,             # :pending | :processing | :failed | :dead_letter (indexed)
        :attempts,           # Number of attempts so far (integer)
        :last_error,         # Last error message (string, nullable)
        :created_at,         # Unix timestamp
        :updated_at          # Unix timestamp
      ],
      indices: [:status]
    },

    # ===== STATS (UNIFIED) =====
    # Compound key for all stats types: :global | {:hostess, 0-7} | :time_rewards
    %{
      name: :hr_stats,
      type: :set,
      attributes: [
        :key,                # Compound key
        :data,               # Map with type-specific fields
        :updated_at          # Unix timestamp
      ],
      indices: []
    },

    # ===== POLLER STATE (Block number tracking for restart recovery) =====
    %{
      name: :hr_poller_state,
      type: :set,
      attributes: [
        :chain,              # Primary key: :arbitrum or :rogue (atom)
        :last_processed_block  # Block number (integer)
      ],
      indices: []
    },

    # ===== PRICE CACHE (Token prices from BlocksterV2 API) =====
    %{
      name: :hr_prices,
      type: :set,
      attributes: [
        :symbol,             # Primary key: "ROGUE", "ETH", etc. (string)
        :usd_price,          # Price in USD (float)
        :usd_24h_change,     # 24h change percentage (float, nullable)
        :updated_at          # Unix timestamp of last API fetch
      ],
      indices: []
    }
  ]

  @seed_dir "priv/mnesia_seed"

  def tables, do: @tables
  def table_names, do: Enum.map(@tables, & &1.name)

  # ===== GenServer API =====

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ===== GenServer Callbacks =====

  @impl true
  def init(_opts) do
    Logger.info("[MnesiaInitializer] Starting Mnesia initialization")
    initialize_mnesia()
    {:ok, %{initialized: true}}
  end

  # ===== Private Functions =====

  defp initialize_mnesia do
    # Ensure mnesia directory exists
    ensure_mnesia_dir()

    # Start Mnesia (if not already running)
    case :mnesia.system_info(:is_running) do
      :yes ->
        Logger.info("[MnesiaInitializer] Mnesia already running")

      :no ->
        # Create schema if it doesn't exist (safe operation)
        case :mnesia.create_schema([node()]) do
          :ok ->
            Logger.info("[MnesiaInitializer] Created schema on #{node()}")

          {:error, {_, {:already_exists, _}}} ->
            Logger.debug("[MnesiaInitializer] Schema already exists")

          {:error, reason} ->
            Logger.warning("[MnesiaInitializer] Schema creation returned: #{inspect(reason)}")
        end

        :ok = :mnesia.start()
        Logger.info("[MnesiaInitializer] Started Mnesia")
    end

    # Wait for any existing tables to be ready
    existing_tables = :mnesia.system_info(:tables) -- [:schema]
    if length(existing_tables) > 0 do
      :mnesia.wait_for_tables(existing_tables, 30_000)
    end

    # Create tables that don't exist and track which are new
    new_tables = Enum.filter(@tables, &create_table_if_new/1)

    # Seed new tables from priv/mnesia_seed/ files if they exist
    if length(new_tables) > 0 do
      seed_tables(new_tables)
    end

    Logger.info("[MnesiaInitializer] All tables ready")
  end

  defp ensure_mnesia_dir do
    case Application.get_env(:mnesia, :dir) do
      nil ->
        Logger.warning("[MnesiaInitializer] No Mnesia directory configured")

      dir when is_list(dir) ->
        path = List.to_string(dir)
        File.mkdir_p!(path)
        Logger.info("[MnesiaInitializer] Mnesia directory: #{path}")
    end
  end

  defp create_table_if_new(table_config) do
    name = table_config.name
    type = table_config.type
    attributes = table_config.attributes
    indices = table_config[:indices] || []

    table_opts = [
      attributes: attributes,
      type: type,
      disc_copies: [node()]
    ]

    # Add indices if specified
    table_opts =
      if Enum.empty?(indices) do
        table_opts
      else
        Keyword.put(table_opts, :index, indices)
      end

    case :mnesia.create_table(name, table_opts) do
      {:atomic, :ok} ->
        Logger.info("[MnesiaInitializer] Created table #{name}")
        true  # Table was created (new)

      {:aborted, {:already_exists, ^name}} ->
        Logger.debug("[MnesiaInitializer] Table #{name} already exists")
        false  # Table already existed

      {:aborted, reason} ->
        Logger.error("[MnesiaInitializer] Failed to create table #{name}: #{inspect(reason)}")
        false
    end
  end

  defp seed_tables(new_tables) do
    # Get seed directory path (works in both dev and release)
    seed_path = Application.app_dir(:high_rollers, @seed_dir)

    unless File.dir?(seed_path) do
      Logger.info("[MnesiaInitializer] No seed directory found at #{seed_path}, skipping seeding")
      :ok
    else
      Enum.each(new_tables, fn table_config ->
        seed_file = Path.join(seed_path, "#{table_config.name}.etf")
        seed_table(table_config.name, seed_file)
      end)
    end
  end

  defp seed_table(table_name, seed_file) do
    if File.exists?(seed_file) do
      Logger.info("[MnesiaInitializer] Seeding #{table_name} from #{seed_file}")

      case File.read(seed_file) do
        {:ok, binary} ->
          records = :erlang.binary_to_term(binary)
          count = length(records)

          # Write all records to the table
          Enum.each(records, fn record ->
            :mnesia.dirty_write(record)
          end)

          Logger.info("[MnesiaInitializer] Seeded #{count} records into #{table_name}")

        {:error, reason} ->
          Logger.error("[MnesiaInitializer] Failed to read seed file #{seed_file}: #{inspect(reason)}")
      end
    else
      Logger.debug("[MnesiaInitializer] No seed file for #{table_name}")
    end
  end
end
