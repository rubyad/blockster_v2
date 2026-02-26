defmodule BlocksterV2.HubLogoCache do
  @moduledoc """
  ETS-based cache for hub token logos.
  Maps token names to their logo URLs for efficient lookups without DB queries.
  """
  use GenServer

  @table_name :hub_logo_cache

  # Client API

  def start_link(_opts) do
    # Local registration - each node needs its own ETS table for fast local lookups
    # The GenServer runs on every node and creates a local ETS table
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Get logo URL for a token name. Returns nil if not found.
  """
  def get_logo(token_name) when is_binary(token_name) do
    case :ets.lookup(@table_name, token_name) do
      [{^token_name, logo_url}] -> logo_url
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc """
  Get all cached logos as a map of token_name => logo_url.
  """
  def get_all_logos do
    :ets.tab2list(@table_name)
    |> Enum.into(%{})
  rescue
    ArgumentError -> %{}
  end

  @doc """
  Refresh the cache from the database.
  Call this when hubs are created/updated.
  """
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc """
  Update a single hub's logo in the cache.
  """
  def update_hub(token_name, logo_url) when is_binary(token_name) do
    GenServer.cast(__MODULE__, {:update, token_name, logo_url})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table owned by this process
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

    # Load initial data after a short delay to ensure Repo is ready
    Process.send_after(self(), :load_initial, 2_000)

    {:ok, %{}}
  end

  @impl true
  def handle_info(:load_initial, state) do
    try do
      load_from_database()
    rescue
      _ -> Process.send_after(self(), :load_initial, 2_000)
    end
    {:noreply, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    load_from_database()
    {:noreply, state}
  end

  @impl true
  def handle_cast({:update, token_name, logo_url}, state) do
    if token_name && token_name != "" do
      :ets.insert(@table_name, {token_name, logo_url})
    end
    {:noreply, state}
  end

  defp load_from_database do
    import Ecto.Query

    # Query only active hubs with tokens and logo URLs
    hubs =
      BlocksterV2.Blog.Hub
      |> where([h], not is_nil(h.token) and h.token != "")
      |> select([h], {h.token, h.logo_url})
      |> BlocksterV2.Repo.all()

    # Clear and repopulate the table
    :ets.delete_all_objects(@table_name)

    Enum.each(hubs, fn {token, logo_url} ->
      :ets.insert(@table_name, {token, logo_url})
    end)

    # Always include BUX with the blockster icon
    :ets.insert(@table_name, {"BUX", "https://ik.imagekit.io/blockster/blockster-icon.png"})

    # Include ROGUE native token
    :ets.insert(@table_name, {"ROGUE", "https://ik.imagekit.io/blockster/rogue-white-in-indigo-logo.png"})
  end
end
