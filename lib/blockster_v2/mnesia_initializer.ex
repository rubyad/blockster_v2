defmodule BlocksterV2.MnesiaInitializer do
  use GenServer
  require Logger

  @moduledoc """
  Initializes Mnesia tables on server startup.
  Handles both single-node (local dev) and multi-node (Fly.io production) setups.

  For local development:
    - Uses disc_copies for persistence across restarts
    - Node name configured via --sname flag

  For production (Fly.io with 2 nodes):
    - Discovers other nodes via libcluster
    - Syncs schema across nodes
    - Uses disc_copies on all nodes for redundancy
  """

  # Table definitions - single source of truth
  @tables [
    %{
      name: :user_bux_points,
      type: :ordered_set,
      attributes: [
        :user_id,
        :user_smart_wallet,
        :bux_balance,
        :extra_field1,
        :extra_field2,
        :extra_field3,
        :extra_field4,
        :created_at,
        :updated_at
      ],
      index: [:bux_balance, :updated_at]
    },
    %{
      name: :post_bux_points,
      type: :ordered_set,
      attributes: [
        :post_id,
        :reward,
        :read_time,
        :bux_balance,
        :bux_deposited,
        :extra_field1,
        :extra_field2,
        :extra_field3,
        :extra_field4,
        :created_at,
        :updated_at
      ],
      index: [:bux_balance, :updated_at]
    },
    %{
      name: :user_post_time,
      type: :set,
      attributes: [
        :key,         # {user_id, post_id} tuple as primary key
        :user_id,
        :post_id,
        :seconds,
        :updated_at
      ],
      index: [:user_id, :post_id]
    },
    %{
      name: :user_post_engagement,
      type: :set,
      attributes: [
        :key,                    # {user_id, post_id} tuple as primary key
        :user_id,
        :post_id,
        :time_spent,             # Total seconds spent on page
        :min_read_time,          # Calculated minimum read time for article
        :scroll_depth,           # 0-100 percentage of article scrolled
        :reached_end,            # Boolean - did they scroll to end of article body
        :scroll_events,          # Number of scroll events
        :avg_scroll_speed,       # Average scroll speed (pixels/second)
        :max_scroll_speed,       # Maximum scroll speed detected
        :scroll_reversals,       # Number of times scrolled back up
        :focus_changes,          # Number of tab visibility changes
        :engagement_score,       # 1-10 quality score
        :is_read,                # Boolean - article considered read
        :created_at,
        :updated_at
      ],
      index: [:user_id, :post_id, :engagement_score, :is_read]
    },
    %{
      name: :user_multipliers,
      type: :set,
      attributes: [
        :user_id,                # Primary key
        :smart_wallet,           # User's smart wallet address
        :x_multiplier,           # X (Twitter) multiplier
        :linkedin_multiplier,    # LinkedIn multiplier
        :personal_multiplier,    # Personal website/portfolio multiplier
        :rogue_multiplier,       # Rogue-specific multiplier
        :overall_multiplier,     # Computed overall multiplier
        :extra_field1,           # Reserved for future use
        :extra_field2,           # Reserved for future use
        :extra_field3,           # Reserved for future use
        :extra_field4,           # Reserved for future use
        :created_at,
        :updated_at
      ],
      index: [:smart_wallet, :overall_multiplier]
    },
    %{
      name: :user_post_rewards,
      type: :set,
      attributes: [
        :key,                    # {user_id, post_id} tuple as primary key
        :user_id,
        :post_id,
        :read_bux,               # BUX earned for reading the article
        :read_paid,              # Boolean - has read reward been paid out
        :read_tx_id,             # Transaction ID of read reward payout
        :x_share_bux,            # BUX earned for sharing on X (Twitter)
        :x_share_paid,           # Boolean - has X share reward been paid out
        :x_share_tx_id,          # Transaction ID of X share payout
        :linkedin_share_bux,     # BUX earned for sharing on LinkedIn
        :linkedin_share_paid,    # Boolean - has LinkedIn share reward been paid out
        :linkedin_share_tx_id,   # Transaction ID of LinkedIn share payout
        :total_bux,              # Total BUX earned for this post
        :total_paid_bux,         # Total BUX that has been paid out
        :created_at,
        :updated_at
      ],
      index: [:user_id, :post_id, :total_bux, :read_paid, :x_share_paid, :linkedin_share_paid]
    },
    %{
      name: :share_rewards,
      type: :set,
      attributes: [
        :key,                    # {user_id, campaign_id} tuple as primary key
        :id,                     # PostgreSQL id (for reference/sync)
        :user_id,
        :campaign_id,
        :x_connection_id,        # Optional X connection reference
        :retweet_id,             # X retweet/post ID
        :status,                 # pending | verified | rewarded | failed
        :bux_rewarded,           # Decimal amount of BUX rewarded
        :verified_at,            # Unix timestamp when verified
        :rewarded_at,            # Unix timestamp when rewarded
        :failure_reason,         # Reason for failure (if status is failed)
        :tx_hash,                # Blockchain transaction hash
        :created_at,             # Unix timestamp
        :updated_at              # Unix timestamp
      ],
      index: [:user_id, :campaign_id, :status, :rewarded_at]
    },
    %{
      name: :user_bux_balances,
      type: :set,
      attributes: [
        :user_id,                   # Primary key
        :user_smart_wallet,         # User's smart wallet address
        :updated_at,                # Last update timestamp
        :aggregate_bux_balance,     # Total of all token balances combined
        :bux_balance,               # BUX token balance
        :moonbux_balance,           # moonBUX token balance
        :neobux_balance,            # neoBUX token balance
        :roguebux_balance,          # rogueBUX token balance
        :flarebux_balance,          # flareBUX token balance
        :nftbux_balance,            # nftBUX token balance
        :nolchabux_balance,         # nolchaBUX token balance
        :solbux_balance,            # solBUX token balance
        :spacebux_balance,          # spaceBUX token balance
        :tronbux_balance,           # tronBUX token balance
        :tranbux_balance            # tranBUX token balance
      ],
      index: [:user_smart_wallet, :aggregate_bux_balance]
    },
    %{
      name: :user_rogue_balances,
      type: :set,
      attributes: [
        :user_id,                   # Primary key
        :user_smart_wallet,         # User's smart wallet address
        :updated_at,                # Last update timestamp
        :rogue_balance_rogue_chain, # ROGUE balance on Rogue Chain (native token)
        :rogue_balance_arbitrum     # ROGUE balance on Arbitrum One (ERC-20 token)
      ],
      index: [:user_smart_wallet]
    },
    %{
      name: :hub_bux_points,
      type: :ordered_set,
      attributes: [
        :hub_id,                    # Primary key (PostgreSQL hub id)
        :total_bux_rewarded,        # Total BUX rewarded through this hub
        :extra_field1,              # Reserved for future use
        :extra_field2,              # Reserved for future use
        :extra_field3,              # Reserved for future use
        :extra_field4,              # Reserved for future use
        :created_at,
        :updated_at
      ],
      index: [:total_bux_rewarded, :updated_at]
    },
    # X/Twitter OAuth and sharing tables
    %{
      name: :x_oauth_states,
      type: :set,
      attributes: [
        :state,                     # Primary key - random OAuth state string
        :user_id,                   # User initiating the OAuth flow
        :code_verifier,             # PKCE code verifier
        :redirect_path,             # Where to redirect after OAuth completes
        :expires_at,                # Unix timestamp when state expires (15 min TTL)
        :inserted_at                # Unix timestamp when created
      ],
      index: [:user_id, :expires_at]
    },
    %{
      name: :x_connections,
      type: :set,
      attributes: [
        :user_id,                   # Primary key - one X account per user
        :x_user_id,                 # X's user ID (for account locking)
        :x_username,                # X username (handle)
        :x_name,                    # X display name
        :x_profile_image_url,       # Profile image URL
        :access_token_encrypted,    # Encrypted OAuth access token
        :refresh_token_encrypted,   # Encrypted OAuth refresh token
        :token_expires_at,          # Unix timestamp when token expires
        :scopes,                    # List of granted scopes
        :connected_at,              # Unix timestamp when first connected
        :x_score,                   # Account quality score (1-100)
        :followers_count,           # Number of followers
        :following_count,           # Number of accounts following
        :tweet_count,               # Total tweets
        :listed_count,              # Times listed
        :avg_engagement_rate,       # Average engagement rate
        :original_tweets_analyzed,  # Number of tweets analyzed for score
        :account_created_at,        # When X account was created
        :score_calculated_at,       # When score was last calculated
        :updated_at                 # Last update timestamp
      ],
      index: [:x_user_id, :x_username]
    },
    %{
      name: :share_campaigns,
      type: :set,
      attributes: [
        :post_id,                   # Primary key - one campaign per post
        :tweet_id,                  # X tweet ID for this campaign
        :tweet_url,                 # Full URL to the tweet
        :tweet_text,                # Text of the tweet
        :bux_reward,                # BUX reward amount for sharing
        :is_active,                 # Boolean - is campaign active
        :starts_at,                 # Unix timestamp - campaign start (nil = immediate)
        :ends_at,                   # Unix timestamp - campaign end (nil = no end)
        :max_participants,          # Max number of participants (nil = unlimited)
        :total_shares,              # Running count of shares
        :inserted_at,               # Unix timestamp when created
        :updated_at                 # Last update timestamp
      ],
      index: [:tweet_id, :is_active]
    },
    # BUX Booster gambling game tables
    %{
      name: :bux_booster_games,
      type: :ordered_set,
      attributes: [
        :game_id,                   # Primary key - unique game identifier (UUID or timestamp-based)
        :user_id,                   # User who played
        :token_type,                # Token used: "BUX", "moonBUX", "neoBUX", "rogueBUX", "flareBUX", "ROGUE"
        :bet_amount,                # Amount wagered
        :difficulty,                # Number of correct predictions needed (1-5)
        :multiplier,                # Payout multiplier (2, 4, 8, 16, 32)
        :predictions,               # List of user predictions [:heads, :tails, ...]
        :results,                   # List of actual results [:heads, :tails, ...]
        :won,                       # Boolean - did user win
        :payout,                    # Amount won (0 if lost)
        :created_at,                # Unix timestamp when game was played
        # Provably fair fields:
        :server_seed,               # Hex string, revealed after game
        :server_seed_hash,          # SHA256 hash, shown before bet (commitment)
        :nonce                      # Integer, game counter for this user
      ],
      index: [:user_id, :token_type, :won, :created_at]
    },
    %{
      name: :bux_booster_user_stats,
      type: :set,
      attributes: [
        :key,                       # Primary key - {user_id, token_type} tuple
        :user_id,                   # User ID
        :token_type,                # Token type for these stats
        :total_games,               # Total games played
        :total_wins,                # Total games won
        :total_losses,              # Total games lost
        :total_wagered,             # Total amount wagered
        :total_won,                 # Total amount won
        :total_lost,                # Total amount lost (wagered - won when lost)
        :biggest_win,               # Largest single win
        :biggest_loss,              # Largest single loss
        :current_streak,            # Current win/loss streak (positive = wins, negative = losses)
        :best_streak,               # Best winning streak
        :worst_streak,              # Worst losing streak
        :updated_at                 # Last update timestamp
      ],
      index: [:user_id, :total_games, :total_won]
    },
    # Token prices from CoinGecko (cached for USD display)
    %{
      name: :token_prices,
      type: :set,
      attributes: [
        :token_id,                  # PRIMARY KEY - CoinGecko token ID (e.g., "bitcoin", "ethereum", "rogue")
        :symbol,                    # Token symbol (e.g., "BTC", "ETH", "ROGUE")
        :usd_price,                 # Current USD price (float)
        :usd_24h_change,            # 24h price change percentage (float)
        :last_updated               # Unix timestamp of last update (integer)
      ],
      index: [:symbol]
    },
    # BUX Booster on-chain games (smart contract version)
    %{
      name: :bux_booster_onchain_games,
      type: :ordered_set,
      attributes: [
        :game_id,                   # PRIMARY KEY - 32-char hex string generated via :crypto.strong_rand_bytes(16)
        :user_id,                   # User who played
        :wallet_address,            # Player's wallet address (smart wallet)
        :server_seed,               # Hex string (64 chars), revealed after settlement
        :commitment_hash,           # 0x-prefixed SHA256 hash shown before bet (on-chain commitment)
        :nonce,                     # Player's nonce for this game (integer)
        :status,                    # :pending | :committed | :placed | :settled | :expired
        :bet_id,                    # On-chain bet ID (0x-prefixed bytes32, set after placeBet tx)
        :token,                     # Token name used (e.g., "BUX", "moonBUX")
        :token_address,             # Token contract address
        :bet_amount,                # Amount wagered (integer tokens)
        :difficulty,                # Game difficulty (-4 to 5)
        :predictions,               # List of predictions [:heads, :tails, ...]
        :results,                   # List of results (calculated after bet placed)
        :won,                       # Boolean - did player win
        :payout,                    # Amount won (0 if lost)
        :commitment_tx,             # TX hash for submitCommitment
        :bet_tx,                    # TX hash for placeBet
        :settlement_tx,             # TX hash for settleBet
        :created_at,                # Unix timestamp when game started
        :settled_at                 # Unix timestamp when settled (nil until settled)
      ],
      index: [:user_id, :wallet_address, :status, :created_at]
    }
  ]

  # Client API

  def start_link(opts) do
    # Use GlobalSingleton to avoid killing existing process during name conflicts
    # This prevents crashes during rolling deploys when Mnesia tables are being copied
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} ->
        # Notify the process that it's the globally registered instance
        send(pid, :registered)
        {:ok, pid}

      {:already_registered, _pid} ->
        # Another node already started the global GenServer
        # We still need to initialize Mnesia on this node
        Logger.info("[MnesiaInitializer] Global GenServer already running on another node, initializing Mnesia locally")
        Task.start(fn -> initialize_mnesia_for_joining_node() end)
        :ignore
    end
  end

  defp initialize_mnesia_for_joining_node do
    # This runs on a node joining an existing cluster
    initialize_with_persistence()
  end

  @doc """
  Get the Mnesia directory path.
  Uses the path configured in :mnesia, :dir (set in runtime.exs).
  In production: /data/mnesia/blockster (static path that persists across deploys)
  In development: priv/mnesia/{node_name} (separate per node for multi-node testing)
  """
  def mnesia_dir do
    case Application.get_env(:mnesia, :dir) do
      nil ->
        # Fallback: use priv/mnesia/{node_name} if not configured
        node_name = node() |> Atom.to_string() |> String.split("@") |> List.first()
        Path.join([Application.app_dir(:blockster_v2), "priv", "mnesia", node_name])

      dir ->
        to_string(dir)
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Don't start work here - wait for :registered message from start_link
    # This prevents duplicate Mnesia initialization when GlobalSingleton loses the registration race
    {:ok, %{initialized: false, registered: false}}
  end

  @impl true
  def handle_info(:registered, %{registered: false} = state) do
    Logger.info("[MnesiaInitializer] Starting Mnesia initialization on node: #{node()}")

    # Initialize Mnesia in a separate process to not block supervision tree
    Task.start(fn -> initialize_mnesia() end)

    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state) do
    # Already registered, ignore duplicate
    {:noreply, state}
  end

  defp initialize_mnesia do
    # Check if we're running in distributed mode
    if node() == :nonode@nohost do
      Logger.warning("[MnesiaInitializer] Running without distributed Erlang. Mnesia will use ram_copies only.")
      Logger.warning("[MnesiaInitializer] For persistent storage, start with: elixir --sname blockster -S mix phx.server")
      initialize_ram_only()
    else
      initialize_with_persistence()
    end
  end

  defp initialize_ram_only do
    # Start Mnesia without schema (ram only)
    :mnesia.start()
    create_ram_tables()
    Logger.info("[MnesiaInitializer] Mnesia initialized with RAM-only tables")
  end

  defp create_ram_tables do
    Enum.each(@tables, fn table_def ->
      create_table(table_def, :ram_copies)
    end)
  end

  defp initialize_with_persistence do
    # Ensure Mnesia directory exists
    dir = mnesia_dir()
    File.mkdir_p!(dir)
    Application.put_env(:mnesia, :dir, String.to_charlist(dir))

    Logger.info("[MnesiaInitializer] Mnesia directory: #{dir}")

    # Stop Mnesia if running (for clean restart)
    :mnesia.stop()

    # Wait for cluster discovery before deciding if we're the primary node
    # libcluster may not have connected nodes yet
    other_nodes = wait_for_cluster_discovery()

    if other_nodes != [] do
      # Other nodes exist - try to join the cluster
      Logger.info("[MnesiaInitializer] Found cluster nodes: #{inspect(other_nodes)}")
      join_existing_cluster(other_nodes)
    else
      # No other nodes after waiting - we're the first node, create schema and tables
      Logger.info("[MnesiaInitializer] No other nodes found after waiting, initializing as primary node")
      initialize_as_primary_node()
    end
  end

  # Wait for libcluster to discover other nodes
  # Retries up to 5 times with 1 second between attempts
  defp wait_for_cluster_discovery(attempts \\ 5) do
    case Node.list() do
      [] when attempts > 0 ->
        Logger.info("[MnesiaInitializer] No nodes found yet, waiting for cluster discovery (#{attempts} attempts remaining)")
        Process.sleep(1000)
        wait_for_cluster_discovery(attempts - 1)

      nodes ->
        nodes
    end
  end

  defp initialize_as_primary_node do
    # First, check if we have existing Mnesia data on disk that belongs to a different node name
    # This happens on Fly.io deploys where node names include deployment IDs that change each deploy
    case check_for_node_name_mismatch() do
      {:mismatch, old_node} ->
        Logger.info("[MnesiaInitializer] Detected node name change: #{old_node} -> #{node()}")
        migrate_from_old_node(old_node)

      :ok ->
        # No mismatch, proceed normally
        case :mnesia.create_schema([node()]) do
          :ok ->
            Logger.info("[MnesiaInitializer] Created new Mnesia schema")

          {:error, {_, {:already_exists, _}}} ->
            Logger.info("[MnesiaInitializer] Using existing Mnesia schema")

          {:error, reason} ->
            Logger.warning("[MnesiaInitializer] Schema creation issue: #{inspect(reason)}")
        end

        start_mnesia_and_create_tables()
    end
  end

  # Check if Mnesia data on disk belongs to a different node name
  # This detects the Fly.io node name change issue
  defp check_for_node_name_mismatch do
    dir = mnesia_dir()
    schema_file = Path.join(dir, "schema.DAT")

    if File.exists?(schema_file) do
      # Read the schema file to find what node it was created for
      # The schema.DAT file is a DETS file with records like {:schema, table_name, properties}
      # We need to find the node that owns the schema copy
      case :dets.open_file(:schema_check, [{:file, String.to_charlist(schema_file)}, {:repair, false}]) do
        {:ok, ref} ->
          result = find_schema_owner(ref)
          :dets.close(ref)
          result

        {:error, _reason} ->
          # Can't read schema file, assume no mismatch
          :ok
      end
    else
      :ok
    end
  end

  defp find_schema_owner(dets_ref) do
    # Look for the schema table entry which has disc_copies info
    case :dets.lookup(dets_ref, :schema) do
      [{:schema, :schema, props}] ->
        disc_copies = Keyword.get(props, :disc_copies, [])
        current_node = node()

        cond do
          current_node in disc_copies ->
            # Current node is in the schema, no mismatch
            :ok

          disc_copies == [] ->
            # No disc copies registered, no mismatch
            :ok

          true ->
            # Schema has disc_copies on a different node - this is the mismatch!
            old_node = hd(disc_copies)
            Logger.info("[MnesiaInitializer] Schema file shows disc_copies on #{old_node}, but we are #{current_node}")
            {:mismatch, old_node}
        end

      _ ->
        :ok
    end
  end

  # Migrate Mnesia data from an old node name to the current node
  # This handles the Fly.io deploy node name change issue
  defp migrate_from_old_node(old_node) do
    Logger.info("[MnesiaInitializer] Starting migration from #{old_node} to #{node()}")

    dir = mnesia_dir()

    # Step 1: Extract all data from the old .DCD files BEFORE touching the schema
    # .DCD files are DETS files that we can read directly
    table_data = extract_data_from_dcd_files(dir)
    Logger.info("[MnesiaInitializer] Extracted data from #{map_size(table_data)} tables")

    # Step 2: Stop Mnesia and clean up old schema
    :mnesia.stop()

    # Delete all files in the Mnesia directory - we're starting fresh with correct node
    cleanup_mnesia_directory(dir)

    # Step 3: Create new schema with current node
    case :mnesia.create_schema([node()]) do
      :ok ->
        Logger.info("[MnesiaInitializer] Created new schema for #{node()}")

      {:error, reason} ->
        Logger.error("[MnesiaInitializer] Failed to create schema: #{inspect(reason)}")
    end

    # Step 4: Start Mnesia
    :mnesia.start()

    # Step 5: Create tables
    create_tables()

    # Step 6: Wait for tables to be ready
    wait_for_tables()

    # Step 7: Restore the extracted data
    restore_table_data(table_data)

    Logger.info("[MnesiaInitializer] Migration complete")
  end

  # Extract data from .DCD files before migration
  # .DCD files are DETS files containing the table records
  defp extract_data_from_dcd_files(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".DCD"))
        |> Enum.reduce(%{}, fn file, acc ->
          table_name = file |> String.replace(".DCD", "") |> String.to_atom()
          file_path = Path.join(dir, file)

          case extract_dcd_records(table_name, file_path) do
            {:ok, records} when records != [] ->
              Logger.info("[MnesiaInitializer] Extracted #{length(records)} records from #{table_name}")
              Map.put(acc, table_name, records)

            {:ok, []} ->
              Logger.info("[MnesiaInitializer] Table #{table_name} was empty")
              acc

            {:error, reason} ->
              Logger.warning("[MnesiaInitializer] Could not extract #{table_name}: #{inspect(reason)}")
              acc
          end
        end)

      {:error, _} ->
        %{}
    end
  end

  # Extract records from a .DCD file (DETS format)
  defp extract_dcd_records(table_name, file_path) do
    # Generate a unique reference name to avoid conflicts
    ref_name = :"dcd_extract_#{table_name}_#{System.unique_integer([:positive])}"

    case :dets.open_file(ref_name, [{:file, String.to_charlist(file_path)}, {:repair, false}]) do
      {:ok, ref} ->
        # Read all records from the DETS file
        records = :dets.foldl(fn record, acc -> [record | acc] end, [], ref)
        :dets.close(ref)
        {:ok, records}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Clean up the Mnesia directory to start fresh
  defp cleanup_mnesia_directory(dir) do
    Logger.info("[MnesiaInitializer] Cleaning up Mnesia directory: #{dir}")

    case File.ls(dir) do
      {:ok, files} ->
        Enum.each(files, fn file ->
          path = Path.join(dir, file)
          File.rm(path)
        end)

      {:error, _} ->
        :ok
    end
  end

  # Restore extracted data to the new tables
  defp restore_table_data(table_data) when table_data == %{} do
    Logger.info("[MnesiaInitializer] No data to restore")
    :ok
  end

  defp restore_table_data(table_data) do
    Logger.info("[MnesiaInitializer] Restoring data to #{map_size(table_data)} tables")

    Enum.each(table_data, fn {table_name, records} ->
      restored_count = Enum.reduce(records, 0, fn record, count ->
        case :mnesia.transaction(fn -> :mnesia.write(table_name, record, :write) end) do
          {:atomic, :ok} ->
            count + 1

          {:aborted, reason} ->
            Logger.warning("[MnesiaInitializer] Failed to restore record to #{table_name}: #{inspect(reason)}")
            count
        end
      end)

      Logger.info("[MnesiaInitializer] Restored #{restored_count}/#{length(records)} records to #{table_name}")
    end)
  end

  defp join_existing_cluster(other_nodes) do
    # Check if the cluster actually has Mnesia running with data we should copy from
    # Try connecting to check cluster state before deciding what to do
    cluster_has_data = check_if_cluster_has_mnesia_data(other_nodes)

    if cluster_has_data do
      # Cluster has running Mnesia with tables - we should join it properly
      # This means deleting our local schema and copying from cluster
      Logger.info("[MnesiaInitializer] Cluster has Mnesia data - joining as secondary node")
      join_as_secondary_node(other_nodes)
    else
      # Cluster nodes exist but don't have Mnesia data yet
      # We may have local data that should be preserved
      Logger.info("[MnesiaInitializer] Cluster doesn't have Mnesia data yet - using local data")
      use_local_data_and_retry_cluster(other_nodes)
    end
  end

  # Check if any cluster node has Mnesia running with our tables AND actual data
  defp check_if_cluster_has_mnesia_data(other_nodes) do
    # Try to query a cluster node to see if it has our tables WITH DATA
    # We must verify there's actual data before wiping our local copy
    Enum.any?(other_nodes, fn node ->
      try do
        # RPC call to check if node has Mnesia running with tables
        case :rpc.call(node, :mnesia, :system_info, [:is_running], 5000) do
          :yes ->
            # Mnesia is running, check if it has our tables
            case :rpc.call(node, :mnesia, :system_info, [:local_tables], 5000) do
              tables when is_list(tables) ->
                # Check if it has more than just schema
                has_data_tables = Enum.any?(tables, fn t -> t != :schema end)
                if has_data_tables do
                  Logger.info("[MnesiaInitializer] Node #{node} has Mnesia with tables: #{inspect(tables)}")
                  # CRITICAL: Also verify at least one table has actual records
                  # This prevents data loss when cluster node has empty tables
                  has_actual_data = check_cluster_has_actual_data(node, tables)
                  if has_actual_data do
                    Logger.info("[MnesiaInitializer] Node #{node} confirmed to have actual data")
                    true
                  else
                    Logger.warning("[MnesiaInitializer] Node #{node} has tables but they appear empty - treating as no data")
                    false
                  end
                else
                  false
                end
              _ -> false
            end
          _ -> false
        end
      catch
        :exit, _ -> false
      end
    end)
  end

  # Check if cluster node has actual data in tables (not just empty tables)
  defp check_cluster_has_actual_data(node, tables) do
    # Check the tables we care about for actual records
    data_tables = tables -- [:schema]

    Enum.any?(data_tables, fn table ->
      try do
        case :rpc.call(node, :mnesia, :table_info, [table, :size], 5000) do
          size when is_integer(size) and size > 0 ->
            Logger.info("[MnesiaInitializer] Table #{table} on #{node} has #{size} records")
            true
          _ ->
            false
        end
      catch
        :exit, _ -> false
      end
    end)
  end

  # Join as a secondary node - safely sync with cluster WITHOUT deleting local data first
  defp join_as_secondary_node(other_nodes) do
    Logger.info("[MnesiaInitializer] Joining cluster as secondary node - will sync tables from cluster")

    # IMPORTANT: Check if we have local data BEFORE doing anything destructive
    dir = mnesia_dir()
    has_local_data = has_local_mnesia_data?(dir)

    if has_local_data do
      Logger.info("[MnesiaInitializer] Local Mnesia data exists - attempting safe sync without deletion")
      safe_join_preserving_local_data(other_nodes)
    else
      Logger.info("[MnesiaInitializer] No local Mnesia data - safe to join cluster fresh")
      join_cluster_fresh(other_nodes)
    end
  end

  # Check if we have local Mnesia data files
  defp has_local_mnesia_data?(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        # Check for .DCD files (data) or schema.DAT
        Enum.any?(files, fn f ->
          String.ends_with?(f, ".DCD") or String.ends_with?(f, ".DAT")
        end)
      {:error, _} ->
        false
    end
  end

  # Join cluster while preserving our local data - try to add copies
  defp safe_join_preserving_local_data(other_nodes) do
    # Start Mnesia with existing schema
    case :mnesia.start() do
      :ok ->
        Logger.info("[MnesiaInitializer] Mnesia started with existing local data")
      {:error, reason} ->
        Logger.warning("[MnesiaInitializer] Error starting Mnesia: #{inspect(reason)}")
    end

    # Try to connect to cluster
    case :mnesia.change_config(:extra_db_nodes, other_nodes) do
      {:ok, connected_nodes} when connected_nodes != [] ->
        Logger.info("[MnesiaInitializer] Connected to cluster: #{inspect(connected_nodes)}")

        # Add schema disc_copies to this node
        case :mnesia.change_table_copy_type(:schema, node(), :disc_copies) do
          {:atomic, :ok} ->
            Logger.info("[MnesiaInitializer] Schema stored as disc_copies")
          {:aborted, {:already_exists, :schema, _, :disc_copies}} ->
            Logger.info("[MnesiaInitializer] Schema already disc_copies")
          {:aborted, reason} ->
            Logger.warning("[MnesiaInitializer] Schema issue: #{inspect(reason)}")
        end

        # Copy tables from cluster (this adds copies, doesn't wipe local)
        copy_tables_from_cluster()
        wait_for_tables()

        Logger.info("[MnesiaInitializer] Successfully joined cluster and synced tables")

      {:ok, []} ->
        Logger.warning("[MnesiaInitializer] No cluster nodes available - using local data")
        # We have local data, so just use it
        wait_for_tables()

      {:error, reason} ->
        Logger.warning("[MnesiaInitializer] Cluster connection error: #{inspect(reason)} - using local data")
        wait_for_tables()
    end
  end

  # Join cluster fresh when we have no local data
  defp join_cluster_fresh(other_nodes) do
    # Stop Mnesia if running
    :mnesia.stop()

    # No local data, safe to start fresh
    :mnesia.start()

    # Connect to cluster
    case :mnesia.change_config(:extra_db_nodes, other_nodes) do
      {:ok, connected_nodes} when connected_nodes != [] ->
        Logger.info("[MnesiaInitializer] Connected to cluster: #{inspect(connected_nodes)}")

        # Add schema disc_copies to this node
        case :mnesia.change_table_copy_type(:schema, node(), :disc_copies) do
          {:atomic, :ok} ->
            Logger.info("[MnesiaInitializer] Schema stored as disc_copies")
          {:aborted, {:already_exists, :schema, _, :disc_copies}} ->
            Logger.info("[MnesiaInitializer] Schema already disc_copies")
          {:aborted, reason} ->
            Logger.warning("[MnesiaInitializer] Schema issue: #{inspect(reason)}")
        end

        # Copy all tables from cluster
        copy_tables_from_cluster()
        wait_for_tables()

        Logger.info("[MnesiaInitializer] Successfully joined cluster and copied tables")

      {:ok, []} ->
        Logger.warning("[MnesiaInitializer] No cluster nodes available - creating fresh schema")
        :mnesia.stop()
        :mnesia.create_schema([node()])
        :mnesia.start()
        create_tables()
        wait_for_tables()

      {:error, reason} ->
        Logger.warning("[MnesiaInitializer] Connection error: #{inspect(reason)} - creating fresh schema")
        :mnesia.stop()
        :mnesia.create_schema([node()])
        :mnesia.start()
        create_tables()
        wait_for_tables()
    end
  end

  # Use local data and try to connect to cluster in background
  defp use_local_data_and_retry_cluster(other_nodes) do
    # Start Mnesia with our existing schema
    case :mnesia.start() do
      :ok ->
        Logger.info("[MnesiaInitializer] Mnesia started with existing schema")
      {:error, reason} ->
        Logger.warning("[MnesiaInitializer] Could not start Mnesia: #{inspect(reason)}")
        :ok
    end

    # Try to connect to cluster nodes (they may not have Mnesia ready yet)
    case :mnesia.change_config(:extra_db_nodes, other_nodes) do
      {:ok, connected_nodes} when connected_nodes != [] ->
        Logger.info("[MnesiaInitializer] Connected to Mnesia cluster: #{inspect(connected_nodes)}")

        # Add schema copy to this node
        case :mnesia.change_table_copy_type(:schema, node(), :disc_copies) do
          {:atomic, :ok} ->
            Logger.info("[MnesiaInitializer] Schema stored as disc_copies on this node")
          {:aborted, {:already_exists, :schema, _, :disc_copies}} ->
            Logger.info("[MnesiaInitializer] Schema already disc_copies on this node")
          {:aborted, reason} ->
            Logger.warning("[MnesiaInitializer] Could not change schema to disc_copies: #{inspect(reason)}")
        end

        # Copy tables from cluster
        copy_tables_from_cluster()
        wait_for_tables()

        Logger.info("[MnesiaInitializer] Mnesia initialization complete (joined cluster)")

      {:ok, []} ->
        # Cluster nodes exist but their Mnesia isn't running yet
        Logger.warning("[MnesiaInitializer] No Mnesia on cluster nodes yet - using local data and waiting")

        if :mnesia.system_info(:is_running) != :yes do
          :mnesia.start()
        end

        load_tables_from_disk_or_wait(other_nodes)

      {:error, reason} ->
        Logger.warning("[MnesiaInitializer] Failed to join cluster: #{inspect(reason)} - using local data")

        if :mnesia.system_info(:is_running) != :yes do
          :mnesia.start()
        end

        load_tables_from_disk_or_wait(other_nodes)
    end
  end

  # Load tables from local disk if available, otherwise wait for cluster
  # NEVER creates fresh tables if we expected to join a cluster
  defp load_tables_from_disk_or_wait(cluster_nodes, attempts \\ 5) do
    # Check if we have local tables on disk
    local_tables = :mnesia.system_info(:local_tables) -- [:schema]

    if local_tables != [] do
      Logger.info("[MnesiaInitializer] Found local tables on disk: #{inspect(local_tables)}")
      # Wait for local tables to load
      case :mnesia.wait_for_tables(local_tables, 10_000) do
        :ok ->
          Logger.info("[MnesiaInitializer] Local tables loaded successfully")
          # Try to reconnect to cluster in background for replication
          spawn(fn -> retry_cluster_connection(cluster_nodes) end)
        {:timeout, still_waiting} ->
          Logger.warning("[MnesiaInitializer] Timeout waiting for tables: #{inspect(still_waiting)}")
          # Force load tables that timed out (single node scenario)
          Logger.info("[MnesiaInitializer] Force loading timed out tables...")
          for table <- still_waiting do
            case :mnesia.force_load_table(table) do
              :yes -> Logger.info("[MnesiaInitializer] Force loaded #{table}")
              other -> Logger.warning("[MnesiaInitializer] Force load #{table} returned: #{inspect(other)}")
            end
          end
          # Try to reconnect to cluster in background for replication
          spawn(fn -> retry_cluster_connection(cluster_nodes) end)
        {:error, reason} ->
          Logger.warning("[MnesiaInitializer] Error loading tables: #{inspect(reason)}")
      end
    else
      # No local tables - either first run or data was lost
      if attempts > 0 do
        Logger.info("[MnesiaInitializer] No local tables, waiting for cluster (#{attempts} attempts remaining)")
        Process.sleep(2000)

        # Try to reconnect
        case :mnesia.change_config(:extra_db_nodes, cluster_nodes) do
          {:ok, connected} when connected != [] ->
            Logger.info("[MnesiaInitializer] Connected to cluster on retry")
            copy_tables_from_cluster()
            wait_for_tables()
          _ ->
            load_tables_from_disk_or_wait(cluster_nodes, attempts - 1)
        end
      else
        # After all retries, we have no choice but to create fresh tables
        # This should only happen on a brand new deployment
        Logger.warning("[MnesiaInitializer] No local data and cannot reach cluster - creating fresh tables (this should only happen on first deploy)")
        create_tables()
        wait_for_tables()
      end
    end
  end

  # Background task to reconnect to cluster for replication
  defp retry_cluster_connection(cluster_nodes, attempts \\ 10) do
    if attempts > 0 do
      Process.sleep(5000)
      case :mnesia.change_config(:extra_db_nodes, cluster_nodes) do
        {:ok, connected} when connected != [] ->
          Logger.info("[MnesiaInitializer] Background: Connected to cluster #{inspect(connected)}")
          # Tables should auto-replicate now
        _ ->
          retry_cluster_connection(cluster_nodes, attempts - 1)
      end
    end
  end

  defp start_mnesia_and_create_tables do
    # Start Mnesia
    case :mnesia.start() do
      :ok ->
        Logger.info("[MnesiaInitializer] Mnesia started successfully")

      {:error, reason} ->
        Logger.error("[MnesiaInitializer] Failed to start Mnesia: #{inspect(reason)}")
        raise "Failed to start Mnesia: #{inspect(reason)}"
    end

    # Wait for schema
    :mnesia.wait_for_tables([:schema], 5000)

    # Create tables
    create_tables()

    # Wait for all tables to be ready
    wait_for_tables()

    Logger.info("[MnesiaInitializer] Mnesia initialization complete")
  end

  defp copy_tables_from_cluster do
    # First, check if the cluster has any healthy tables we can copy from
    # If not, we need to recreate everything from scratch
    cluster_health = check_cluster_health()

    case cluster_health do
      :healthy ->
        Logger.info("[MnesiaInitializer] Cluster is healthy, copying tables")
        copy_tables_normally()

      :degraded ->
        # Cluster exists but tables appear broken
        # IMPORTANT: Do NOT delete tables during rolling deploys - this causes data loss!
        # Instead, try to add copies to this node. If that fails, the table may still
        # be accessible from disk on restart.
        Logger.warning("[MnesiaInitializer] Cluster tables appear degraded, attempting safe recovery")
        safe_recover_tables()

      :empty ->
        Logger.info("[MnesiaInitializer] No tables in cluster, creating fresh")
        create_tables()
    end
  end

  defp check_cluster_health do
    # Check the first table to determine cluster health
    # If tables have active copies, cluster is healthy
    # If tables exist in schema but have no copies, cluster is degraded
    # If tables don't exist, cluster is empty (new setup)
    sample_table = hd(@tables).name

    case get_table_status(sample_table) do
      {:has_copies, copies} when copies != [] ->
        # Check if any copy is on a reachable node
        reachable_copies = Enum.filter(copies, fn n ->
          n == node() or n in Node.list()
        end)

        if reachable_copies != [] do
          :healthy
        else
          # Copies exist but nodes aren't reachable - this shouldn't happen
          # after change_config connected us, but handle it
          Logger.warning("[MnesiaInitializer] Table copies exist but on unreachable nodes: #{inspect(copies)}")
          :degraded
        end

      :exists_no_copies ->
        :degraded

      :not_exists ->
        :empty
    end
  end

  defp copy_tables_normally do
    Enum.each(@tables, fn table_def = %{name: table_name} ->
      case get_table_status(table_name) do
        {:has_copies, _copies} ->
          Logger.info("[MnesiaInitializer] Copying table #{table_name} from cluster")
          add_table_copy_to_node(table_name, table_def)

        :exists_no_copies ->
          # Shouldn't happen if cluster is healthy, but handle it
          Logger.warning("[MnesiaInitializer] Table #{table_name} has no copies despite healthy cluster")
          add_table_copy_to_node(table_name, table_def)

        :not_exists ->
          Logger.info("[MnesiaInitializer] Table #{table_name} not found, creating it")
          create_table(table_def, :disc_copies)
      end
    end)
  end

  defp safe_recover_tables do
    # Tables appear degraded but we must NOT delete them - they may have data on disk.
    # Instead, try to add copies to this node, and if that fails, log a warning
    # and hope the table data can be recovered from disk on restart.
    Logger.info("[MnesiaInitializer] Attempting safe table recovery (no deletions)")

    Enum.each(@tables, fn table_def = %{name: table_name} ->
      case get_table_status(table_name) do
        {:has_copies, _} ->
          # Table has copies - try to add copy to this node
          safe_add_table_copy(table_name, table_def)

        :exists_no_copies ->
          # Table exists in schema but has no copies.
          # This could be a timing issue during rolling deploy.
          # DO NOT DELETE - try to add a copy, the data may be on disk.
          Logger.warning("[MnesiaInitializer] Table #{table_name} has no copies but exists in schema - attempting safe add")
          safe_add_table_copy(table_name, table_def)

        :not_exists ->
          # Table genuinely doesn't exist - safe to create
          create_table(table_def, :disc_copies)
      end
    end)
  end

  # Safe version that never deletes tables - but will create if no other option
  defp safe_add_table_copy(table_name, table_def) do
    case :mnesia.add_table_copy(table_name, node(), :disc_copies) do
      {:atomic, :ok} ->
        Logger.info("[MnesiaInitializer] Successfully added #{table_name} disc_copies to this node")

      {:aborted, {:already_exists, _, _}} ->
        Logger.info("[MnesiaInitializer] Table #{table_name} already has disc_copies on this node")

      {:aborted, {:system_limit, _, {_node, :none_active}}} ->
        # No active copies anywhere - we need to create a fresh table
        # This happens when previous deploy wiped data and there's nothing to copy
        Logger.warning("[MnesiaInitializer] Table #{table_name} has no active copies - creating fresh table")
        create_table(table_def, :disc_copies)

      {:aborted, {:no_exists, _}} ->
        # Table doesn't exist in schema - create it fresh
        Logger.info("[MnesiaInitializer] Table #{table_name} doesn't exist, creating fresh")
        create_table(table_def, :disc_copies)

      {:aborted, reason} ->
        # Try to create the table if we can't add copy for other reasons
        Logger.warning("[MnesiaInitializer] Could not add #{table_name} copy: #{inspect(reason)} - attempting to create fresh")
        create_table(table_def, :disc_copies)
    end
  end

  # DEPRECATED - kept for reference but should not be called
  # This function was deleting tables that had data during rolling deploys
  defp cleanup_and_recreate_tables do
    Logger.error("[MnesiaInitializer] cleanup_and_recreate_tables called - this should not happen!")
    Logger.error("[MnesiaInitializer] Using safe_recover_tables instead to prevent data loss")
    safe_recover_tables()
  end

  defp delete_orphaned_table(table_name) do
    # When a table exists in schema but has no active copies, it's a "zombie" table
    # This can happen during rolling deploys when one node dies before the other starts
    # The table exists in the global schema but has no disc_copies/ram_copies anywhere
    #
    # delete_table fails with {:no_exists, _} in this state because there are no
    # copies to delete, even though the schema entry exists.
    #
    # The fix is to use the internal schema functions to forcefully remove the table
    # from the schema on all nodes.

    Logger.info("[MnesiaInitializer] Force-deleting orphaned table #{table_name} from schema")

    # First try the normal delete_table
    case :mnesia.delete_table(table_name) do
      {:atomic, :ok} ->
        Logger.info("[MnesiaInitializer] Successfully deleted table #{table_name}")
        :ok

      _ ->
        # delete_table didn't work - force remove from schema
        # We do this by deleting the schema record for this table directly
        force_delete_table_from_schema(table_name)
    end
  end

  defp force_delete_table_from_schema(table_name) do
    # Delete the schema entry for this table directly
    # This is a low-level operation that removes the table definition from schema
    Logger.info("[MnesiaInitializer] Force removing #{table_name} from schema")

    # Write a transaction that removes the schema record for this table
    result = :mnesia.transaction(fn ->
      # Delete the {schema, table_name, _} record from the schema table
      case :mnesia.read(:schema, table_name) do
        [_record] ->
          :mnesia.delete({:schema, table_name})
          :ok
        [] ->
          :already_gone
      end
    end)

    case result do
      {:atomic, :ok} ->
        Logger.info("[MnesiaInitializer] Removed #{table_name} from schema")
        :ok

      {:atomic, :already_gone} ->
        Logger.info("[MnesiaInitializer] Table #{table_name} already gone from schema")
        :ok

      {:aborted, reason} ->
        Logger.warning("[MnesiaInitializer] Could not remove #{table_name} from schema: #{inspect(reason)}")
        # As a last resort, try clearing from local node schema cache
        clear_local_schema_cache(table_name)
    end
  end

  defp clear_local_schema_cache(table_name) do
    # Try to clear any local cached references to this table
    # This shouldn't normally be needed, but handles edge cases
    Logger.info("[MnesiaInitializer] Clearing local schema cache for #{table_name}")

    # Delete any local schema references
    all_nodes = [node() | Node.list()]

    Enum.each(all_nodes, fn n ->
      case :mnesia.del_table_copy(table_name, n) do
        {:atomic, :ok} ->
          Logger.info("[MnesiaInitializer] Removed #{table_name} copy from #{n}")

        {:aborted, _reason} ->
          # Ignore errors - we're trying to clean up
          :ok
      end
    end)

    :ok
  end

  defp get_table_status(table_name) do
    # Check if table exists and its copy status
    case :mnesia.table_info(table_name, :all) do
      info when is_list(info) ->
        disc_copies = Keyword.get(info, :disc_copies, [])
        ram_copies = Keyword.get(info, :ram_copies, [])
        disc_only = Keyword.get(info, :disc_only_copies, [])
        all_copies = disc_copies ++ ram_copies ++ disc_only

        if all_copies == [] do
          :exists_no_copies
        else
          {:has_copies, all_copies}
        end

      _ ->
        :not_exists
    end
  catch
    :exit, _ -> :not_exists
  end

  defp add_table_copy_to_node(table_name, _table_def) do
    case :mnesia.add_table_copy(table_name, node(), :disc_copies) do
      {:atomic, :ok} ->
        Logger.info("[MnesiaInitializer] Successfully added #{table_name} disc_copies to this node")

      {:aborted, {:already_exists, _, _}} ->
        Logger.info("[MnesiaInitializer] Table #{table_name} already has disc_copies on this node")

      {:aborted, {:system_limit, _, {_node, :none_active}}} ->
        # Source table has no active replicas
        # IMPORTANT: Do NOT delete - data may be recoverable from disk
        Logger.warning("[MnesiaInitializer] Table #{table_name} has no active copies - data may be recoverable on restart")

      {:aborted, reason} ->
        # Log warning but do NOT delete tables - this causes data loss during rolling deploys
        Logger.warning("[MnesiaInitializer] Could not add #{table_name} copy: #{inspect(reason)} - will retry on restart")
    end
  end

  defp table_exists_in_cluster?(table_name) do
    # Check if table exists anywhere in the cluster
    case :mnesia.table_info(table_name, :where_to_read) do
      :nowhere -> false
      _ -> true
    end
  catch
    :exit, _ -> false
  end

  # Force create a table without checking if it exists
  # Used after deleting orphaned tables from schema
  defp force_create_table(%{name: table_name, type: type, attributes: attributes, index: index}) do
    Logger.info("[MnesiaInitializer] Force creating table #{table_name}")

    result = :mnesia.create_table(
      table_name,
      [type: type, attributes: attributes, index: index, disc_copies: [node()]]
    )

    case result do
      {:atomic, :ok} ->
        Logger.info("[MnesiaInitializer] Successfully created table #{table_name}")
        :ok

      {:aborted, {:already_exists, ^table_name}} ->
        # Table somehow still exists - try to add disc_copies
        Logger.warning("[MnesiaInitializer] Table #{table_name} still exists after deletion, trying to add disc_copies")
        case :mnesia.add_table_copy(table_name, node(), :disc_copies) do
          {:atomic, :ok} ->
            Logger.info("[MnesiaInitializer] Added disc_copies to existing #{table_name}")
          {:aborted, {:already_exists, _, _}} ->
            Logger.info("[MnesiaInitializer] disc_copies already exist for #{table_name}")
          {:aborted, reason} ->
            Logger.error("[MnesiaInitializer] Failed to add disc_copies for #{table_name}: #{inspect(reason)}")
        end

      {:aborted, reason} ->
        Logger.error("[MnesiaInitializer] Failed to force create table #{table_name}: #{inspect(reason)}")
    end
  end

  defp create_tables do
    Enum.each(@tables, fn table_def ->
      create_table(table_def, :disc_copies)
    end)
  end

  defp create_table(%{name: table_name, type: type, attributes: attributes, index: index}, copy_type) do
    # Check if table already exists by trying to get its attributes
    case table_exists?(table_name) do
      true ->
        # Table exists, check if schema matches
        existing_attrs = :mnesia.table_info(table_name, :attributes)

        if existing_attrs == attributes do
          Logger.info("[MnesiaInitializer] Table #{table_name} already exists with correct schema")
        else
          Logger.warning("[MnesiaInitializer] Table #{table_name} exists with different schema")
          Logger.info("[MnesiaInitializer] Existing: #{inspect(existing_attrs)}")
          Logger.info("[MnesiaInitializer] Expected: #{inspect(attributes)}")

          # Attempt to migrate the table schema
          migrate_table_schema(table_name, existing_attrs, attributes)
        end

        if copy_type == :disc_copies, do: ensure_disc_copies(table_name)

      false ->
        # Table doesn't exist, create it
        Logger.info("[MnesiaInitializer] Creating table #{table_name}")

        copies_opt =
          case copy_type do
            :disc_copies -> [disc_copies: [node()]]
            :ram_copies -> [ram_copies: [node()]]
          end

        result =
          :mnesia.create_table(
            table_name,
            [type: type, attributes: attributes, index: index] ++ copies_opt
          )

        case result do
          {:atomic, :ok} ->
            Logger.info("[MnesiaInitializer] Table #{table_name} created successfully")

          {:aborted, {:already_exists, ^table_name}} ->
            Logger.info("[MnesiaInitializer] Table #{table_name} already exists")
            if copy_type == :disc_copies, do: ensure_disc_copies(table_name)

          {:aborted, reason} ->
            Logger.error("[MnesiaInitializer] Failed to create table #{table_name}: #{inspect(reason)}")
        end
    end
  end

  defp table_exists?(table_name) do
    :mnesia.table_info(table_name, :type)
    true
  catch
    :exit, _ -> false
  end

  # Schema migration for tables that have changed structure
  # This handles adding new fields to existing tables while preserving data
  defp migrate_table_schema(table_name, existing_attrs, new_attrs) do
    # First check if the table has active copies - transform_table won't work without them
    case get_table_status(table_name) do
      {:has_copies, copies} ->
        # Check if any copy is reachable
        reachable = Enum.any?(copies, fn n -> n == node() or n in Node.list() end)

        if reachable do
          do_migrate_table_schema(table_name, existing_attrs, new_attrs)
        else
          # No reachable copies - try to force load from disk first
          Logger.warning("[MnesiaInitializer] Table #{table_name} has no reachable copies, attempting force load")
          force_load_and_migrate(table_name, existing_attrs, new_attrs)
        end

      :exists_no_copies ->
        # Table exists in schema but has no copies - zombie table
        # Try to force load from disk, or recreate if that fails
        Logger.warning("[MnesiaInitializer] Table #{table_name} is a zombie (no copies), attempting recovery")
        recover_zombie_table_and_migrate(table_name, existing_attrs, new_attrs)

      :not_exists ->
        # Should not happen since we checked table_exists? before calling this
        Logger.error("[MnesiaInitializer] Table #{table_name} doesn't exist despite earlier check")
    end
  end

  # Attempt to force load a table and then migrate it
  defp force_load_and_migrate(table_name, existing_attrs, new_attrs) do
    case :mnesia.force_load_table(table_name) do
      :yes ->
        Logger.info("[MnesiaInitializer] Force loaded #{table_name}, now migrating")
        do_migrate_table_schema(table_name, existing_attrs, new_attrs)

      other ->
        Logger.warning("[MnesiaInitializer] Force load #{table_name} returned: #{inspect(other)}")
        Logger.warning("[MnesiaInitializer] Table #{table_name} migration deferred until table is available")
    end
  end

  # Recover a zombie table (exists in schema but no copies) and migrate it
  defp recover_zombie_table_and_migrate(table_name, existing_attrs, new_attrs) do
    # First try to force load - this may work if there's data on disk
    case :mnesia.force_load_table(table_name) do
      :yes ->
        Logger.info("[MnesiaInitializer] Force loaded zombie table #{table_name}, now migrating")
        do_migrate_table_schema(table_name, existing_attrs, new_attrs)

      _ ->
        # Force load didn't work - table truly has no data
        # We need to delete it from schema and recreate with new schema
        Logger.warning("[MnesiaInitializer] Cannot recover #{table_name}, will delete and recreate with new schema")
        delete_and_recreate_table(table_name, new_attrs)
    end
  end

  # Delete a zombie table from schema and recreate with new schema
  defp delete_and_recreate_table(table_name, _new_attrs) do
    # Find the table definition from @tables
    table_def = Enum.find(@tables, fn t -> t.name == table_name end)

    if table_def == nil do
      Logger.error("[MnesiaInitializer] Cannot find table definition for #{table_name}")
    else
      # Try to delete the table from schema
      Logger.info("[MnesiaInitializer] Deleting zombie table #{table_name} from schema")

      case :mnesia.delete_table(table_name) do
        {:atomic, :ok} ->
          Logger.info("[MnesiaInitializer] Deleted #{table_name}, recreating with new schema")
          create_fresh_table(table_def)

        {:aborted, {:no_exists, _}} ->
          # Already gone, create fresh
          Logger.info("[MnesiaInitializer] Table #{table_name} already gone, creating fresh")
          create_fresh_table(table_def)

        {:aborted, reason} ->
          Logger.warning("[MnesiaInitializer] Could not delete #{table_name}: #{inspect(reason)}")
          # Try force removing from schema
          force_delete_table_from_schema(table_name)
          create_fresh_table(table_def)
      end
    end
  end

  # Remove disc_copies from nodes that are not active/reachable
  # This is needed when trying to transform a table and some nodes with copies are offline
  defp remove_inactive_node_copies(table_name, inactive_nodes) do
    Enum.each(inactive_nodes, fn node ->
      Logger.info("[MnesiaInitializer] Removing #{table_name} copy from inactive node #{node}")

      # First try to forcefully remove the node from the cluster schema
      # This is needed when the node is completely dead
      remove_dead_node_from_schema(node)

      case :mnesia.del_table_copy(table_name, node) do
        {:atomic, :ok} ->
          Logger.info("[MnesiaInitializer] Removed #{table_name} copy from #{node}")

        {:aborted, {:no_exists, _, _}} ->
          Logger.info("[MnesiaInitializer] #{table_name} copy already gone from #{node}")

        {:aborted, reason} ->
          Logger.warning("[MnesiaInitializer] Could not remove #{table_name} from #{node}: #{inspect(reason)}")
      end
    end)
  end

  # Forcefully remove a dead node from the Mnesia schema
  # This is a last resort when a node will never come back
  defp remove_dead_node_from_schema(dead_node) do
    Logger.info("[MnesiaInitializer] Attempting to remove dead node #{dead_node} from schema")

    # Check if this node is in the connected nodes - if so, don't remove it
    if dead_node in Node.list() do
      Logger.info("[MnesiaInitializer] Node #{dead_node} is still connected, not removing")
    else
      # The node is truly dead - try to remove it from all tables
      # Use mnesia:del_table_copy for schema table to remove the node entirely
      case :mnesia.del_table_copy(:schema, dead_node) do
        {:atomic, :ok} ->
          Logger.info("[MnesiaInitializer] Removed dead node #{dead_node} from schema")

        {:aborted, {:no_exists, :schema, ^dead_node}} ->
          Logger.info("[MnesiaInitializer] Node #{dead_node} already removed from schema")

        {:aborted, reason} ->
          Logger.warning("[MnesiaInitializer] Could not remove #{dead_node} from schema: #{inspect(reason)}")
          # Last resort: try to directly manipulate the schema table
          force_remove_node_from_all_tables(dead_node)
      end
    end
  end

  # Force remove a node from all tables by modifying table definitions
  defp force_remove_node_from_all_tables(dead_node) do
    Logger.info("[MnesiaInitializer] Force removing #{dead_node} from all table definitions")

    # Get all tables except schema
    all_tables = :mnesia.system_info(:tables) -- [:schema]

    Enum.each(all_tables, fn table_name ->
      try do
        disc_copies = :mnesia.table_info(table_name, :disc_copies)

        if dead_node in disc_copies do
          Logger.info("[MnesiaInitializer] Table #{table_name} has copy on dead node #{dead_node}")
          # We can't use del_table_copy because Mnesia won't allow it
          # The only option is to delete and recreate the table
        end
      catch
        :exit, _ -> :ok
      end
    end)
  end

  # Ensure a table is loaded before performing operations on it
  defp ensure_table_loaded(table_name) do
    # First try waiting for the table
    case :mnesia.wait_for_tables([table_name], 5000) do
      :ok ->
        Logger.info("[MnesiaInitializer] Table #{table_name} is ready")
        :ok

      {:timeout, _} ->
        # Table didn't become ready in time - try force loading
        Logger.warning("[MnesiaInitializer] Table #{table_name} timed out, attempting force load")
        case :mnesia.force_load_table(table_name) do
          :yes ->
            Logger.info("[MnesiaInitializer] Force loaded #{table_name}")
            :ok

          other ->
            Logger.warning("[MnesiaInitializer] Force load #{table_name} returned: #{inspect(other)}")
            {:error, other}
        end

      {:error, reason} ->
        Logger.warning("[MnesiaInitializer] Error waiting for #{table_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Create a table fresh with current schema definition
  defp create_fresh_table(%{name: table_name, type: type, attributes: attributes, index: index}) do
    Logger.info("[MnesiaInitializer] Creating fresh table #{table_name} with #{length(attributes)} attributes")

    result = :mnesia.create_table(
      table_name,
      [type: type, attributes: attributes, index: index, disc_copies: [node()]]
    )

    case result do
      {:atomic, :ok} ->
        Logger.info("[MnesiaInitializer] Successfully created fresh #{table_name}")

      {:aborted, {:already_exists, ^table_name}} ->
        Logger.warning("[MnesiaInitializer] Table #{table_name} still exists after deletion attempt")

      {:aborted, reason} ->
        Logger.error("[MnesiaInitializer] Failed to create #{table_name}: #{inspect(reason)}")
    end
  end

  # Actually perform the table schema migration
  defp do_migrate_table_schema(table_name, existing_attrs, new_attrs) do
    # First ensure the table is loaded/active before attempting transform
    ensure_table_loaded(table_name)

    # Check if this is a supported migration (adding fields at the end)
    existing_count = length(existing_attrs)
    new_count = length(new_attrs)

    # Verify the existing attributes are a prefix of the new attributes
    existing_prefix_matches = Enum.take(new_attrs, existing_count) == existing_attrs

    cond do
      existing_prefix_matches and new_count > existing_count ->
        # Safe migration: new fields added at the end
        added_fields = Enum.drop(new_attrs, existing_count)
        Logger.info("[MnesiaInitializer] Migrating #{table_name}: adding fields #{inspect(added_fields)}")

        transform_fn = build_transform_function(table_name, existing_count, new_count)

        case :mnesia.transform_table(table_name, transform_fn, new_attrs) do
          {:atomic, :ok} ->
            Logger.info("[MnesiaInitializer] Successfully migrated #{table_name} from #{existing_count} to #{new_count} fields")

          {:aborted, {:no_exists, _}} ->
            # Table doesn't exist despite our checks - try to recreate it
            Logger.warning("[MnesiaInitializer] Table #{table_name} disappeared during migration, recreating")
            delete_and_recreate_table(table_name, new_attrs)

          {:aborted, {:not_active, _msg, ^table_name, inactive_nodes}} ->
            # Some nodes that have copies are not active - remove them and retry
            Logger.warning("[MnesiaInitializer] Inactive nodes for #{table_name}: #{inspect(inactive_nodes)}")
            remove_inactive_node_copies(table_name, inactive_nodes)
            # Retry the transform after removing inactive copies
            Logger.info("[MnesiaInitializer] Retrying migration after removing inactive node copies")
            case :mnesia.transform_table(table_name, transform_fn, new_attrs) do
              {:atomic, :ok} ->
                Logger.info("[MnesiaInitializer] Successfully migrated #{table_name} on retry")
              {:aborted, retry_reason} ->
                Logger.error("[MnesiaInitializer] Retry failed for #{table_name}: #{inspect(retry_reason)}")
                Logger.warning("[MnesiaInitializer] Falling back to recreate table")
                delete_and_recreate_table(table_name, new_attrs)
            end

          {:aborted, reason} ->
            Logger.error("[MnesiaInitializer] Failed to migrate #{table_name}: #{inspect(reason)}")
            Logger.warning("[MnesiaInitializer] Table #{table_name} will use old schema until manual fix")
        end

      existing_prefix_matches and new_count < existing_count ->
        # Removing fields - more dangerous, just log warning
        Logger.warning("[MnesiaInitializer] Table #{table_name} has more fields than expected (#{existing_count} vs #{new_count})")
        Logger.warning("[MnesiaInitializer] Manual migration may be required")

      true ->
        # Incompatible schema change
        Logger.error("[MnesiaInitializer] Table #{table_name} has incompatible schema change")
        Logger.error("[MnesiaInitializer] Existing: #{inspect(existing_attrs)}")
        Logger.error("[MnesiaInitializer] Expected: #{inspect(new_attrs)}")
        Logger.warning("[MnesiaInitializer] Table will continue with old schema - manual migration required")
    end
  end

  # Build a transform function that adds nil values for new fields
  defp build_transform_function(table_name, old_field_count, new_field_count) do
    fields_to_add = new_field_count - old_field_count

    # Get table-specific default values if any
    defaults = get_migration_defaults(table_name, fields_to_add)

    fn old_record ->
      old_list = Tuple.to_list(old_record)
      new_list = old_list ++ defaults
      List.to_tuple(new_list)
    end
  end

  # Define default values for new fields when migrating specific tables
  # This allows for table-specific migration logic
  defp get_migration_defaults(:bux_booster_games, 3) do
    # Adding: server_seed, server_seed_hash, nonce - all nil for old games
    [nil, nil, nil]
  end

  defp get_migration_defaults(_table_name, field_count) do
    # Default: add nil for each new field
    List.duplicate(nil, field_count)
  end

  defp ensure_disc_copies(table_name) do
    # Ensure this node has disc_copies of the table
    copies = :mnesia.table_info(table_name, :disc_copies)

    if node() in copies do
      :ok
    else
      case :mnesia.add_table_copy(table_name, node(), :disc_copies) do
        {:atomic, :ok} ->
          Logger.info("[MnesiaInitializer] Added disc_copies for #{table_name} on #{node()}")

        {:aborted, {:already_exists, _, _}} ->
          :ok

        {:aborted, reason} ->
          Logger.warning("[MnesiaInitializer] Could not add disc_copies for #{table_name}: #{inspect(reason)}")
      end
    end
  end

  defp wait_for_tables do
    table_names = Enum.map(@tables, & &1.name)

    case :mnesia.wait_for_tables(table_names, 30_000) do
      :ok ->
        Logger.info("[MnesiaInitializer] All tables ready: #{inspect(table_names)}")

      {:timeout, remaining} ->
        Logger.warning("[MnesiaInitializer] Timeout waiting for tables: #{inspect(remaining)}")
        # Force load tables that timed out (single node scenario)
        Logger.info("[MnesiaInitializer] Force loading timed out tables...")
        for table <- remaining do
          case :mnesia.force_load_table(table) do
            :yes -> Logger.info("[MnesiaInitializer] Force loaded #{table}")
            other -> Logger.warning("[MnesiaInitializer] Force load #{table} returned: #{inspect(other)}")
          end
        end

      {:error, reason} ->
        Logger.error("[MnesiaInitializer] Error waiting for tables: #{inspect(reason)}")
    end
  end

  # Public accessor for table definitions
  def tables, do: @tables

  def table_names, do: Enum.map(@tables, & &1.name)
end
