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
    }
  ]

  # Client API

  def start_link(opts) do
    # Check if already started globally (in a multi-node cluster)
    case GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__}) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
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
    Logger.info("[MnesiaInitializer] Starting Mnesia initialization on node: #{node()}")

    # Initialize Mnesia in a separate process to not block supervision tree
    Task.start(fn -> initialize_mnesia() end)

    {:ok, %{initialized: false}}
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

  defp join_existing_cluster(other_nodes) do
    # IMPORTANT: Do NOT delete local schema yet!
    # First, check if any of the cluster nodes actually have Mnesia running.
    # If we delete our schema and then can't connect, we lose all data.

    # First try: Start Mnesia with our existing schema and try to connect
    # This preserves data if the cluster isn't ready yet
    case :mnesia.start() do
      :ok ->
        Logger.info("[MnesiaInitializer] Mnesia started with existing schema")

      {:error, reason} ->
        Logger.warning("[MnesiaInitializer] Could not start Mnesia with existing schema: #{inspect(reason)}")
        # Try without schema - but we'll be careful about creating new tables
        :ok
    end

    # Try to connect to cluster nodes
    case :mnesia.change_config(:extra_db_nodes, other_nodes) do
      {:ok, connected_nodes} when connected_nodes != [] ->
        Logger.info("[MnesiaInitializer] Connected to Mnesia cluster: #{inspect(connected_nodes)}")

        # Successfully connected - now we can safely update our schema
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

        # Wait for all tables to be ready
        wait_for_tables()

        Logger.info("[MnesiaInitializer] Mnesia initialization complete (joined cluster)")

      {:ok, []} ->
        # Cluster nodes exist but their Mnesia isn't running yet
        # DO NOT create fresh tables - this would wipe existing data!
        Logger.warning("[MnesiaInitializer] No Mnesia on cluster nodes yet - using local data and waiting")

        # If Mnesia isn't running, try starting with existing schema
        if :mnesia.system_info(:is_running) != :yes do
          :mnesia.start()
        end

        # Try to load tables from disk if they exist
        load_tables_from_disk_or_wait(other_nodes)

      {:error, reason} ->
        # Connection error - use local data, don't wipe anything
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
          Logger.info("[MnesiaInitializer] Table #{table_name} exists but schema differs, will use existing")
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

      {:error, reason} ->
        Logger.error("[MnesiaInitializer] Error waiting for tables: #{inspect(reason)}")
    end
  end

  # Public accessor for table definitions
  def tables, do: @tables

  def table_names, do: Enum.map(@tables, & &1.name)
end
