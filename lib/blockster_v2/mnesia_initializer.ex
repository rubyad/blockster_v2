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
  Get the Mnesia directory path
  """
  def mnesia_dir do
    case Application.get_env(:mnesia, :dir) do
      nil ->
        # Default to priv/mnesia/{node_name}
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

    # Check for cluster BEFORE creating schema
    # This is critical - if we create a schema first, we can't join an existing cluster
    other_nodes = Node.list()

    if other_nodes != [] do
      # Other nodes exist - try to join the cluster
      Logger.info("[MnesiaInitializer] Found cluster nodes: #{inspect(other_nodes)}")
      join_existing_cluster(other_nodes)
    else
      # No other nodes - we're the first node, create schema and tables
      Logger.info("[MnesiaInitializer] No other nodes found, initializing as primary node")
      initialize_as_primary_node()
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
    # Delete any existing local schema - we'll get it from the cluster
    Logger.info("[MnesiaInitializer] Deleting local schema to join cluster")
    :mnesia.delete_schema([node()])

    # Start Mnesia without a schema (will get it from cluster)
    case :mnesia.start() do
      :ok ->
        Logger.info("[MnesiaInitializer] Mnesia started (without local schema)")

      {:error, reason} ->
        Logger.error("[MnesiaInitializer] Failed to start Mnesia: #{inspect(reason)}")
        raise "Failed to start Mnesia: #{inspect(reason)}"
    end

    # Connect to the cluster - this will sync the schema
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

        # Wait for all tables to be ready
        wait_for_tables()

        Logger.info("[MnesiaInitializer] Mnesia initialization complete (joined cluster)")

      {:ok, []} ->
        Logger.warning("[MnesiaInitializer] No Mnesia nodes in cluster, falling back to primary init")
        :mnesia.stop()
        initialize_as_primary_node()

      {:error, reason} ->
        Logger.warning("[MnesiaInitializer] Failed to join cluster: #{inspect(reason)}, falling back to primary init")
        :mnesia.stop()
        initialize_as_primary_node()
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
    # For each table, try to add a copy to this node from the cluster
    Enum.each(@tables, fn %{name: table_name} ->
      case table_exists_in_cluster?(table_name) do
        true ->
          Logger.info("[MnesiaInitializer] Copying table #{table_name} from cluster")
          case :mnesia.add_table_copy(table_name, node(), :disc_copies) do
            {:atomic, :ok} ->
              Logger.info("[MnesiaInitializer] Successfully copied #{table_name} to this node")

            {:aborted, {:already_exists, _, _}} ->
              Logger.info("[MnesiaInitializer] Table #{table_name} already exists on this node")

            {:aborted, reason} ->
              Logger.warning("[MnesiaInitializer] Could not copy #{table_name}: #{inspect(reason)}")
          end

        false ->
          Logger.warning("[MnesiaInitializer] Table #{table_name} not found in cluster, will be created when primary node starts")
      end
    end)
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
