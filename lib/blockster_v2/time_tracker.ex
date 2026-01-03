defmodule BlocksterV2.TimeTracker do
  use GenServer

  @moduledoc """
  Tracks time spent by users on posts.

  Uses a global GenServer to serialize writes and Mnesia for distributed
  persistent storage. Data survives GenServer restarts and node failures.

  All Mnesia operations are dirty (no transactions) for better performance
  since the global GenServer ensures serialized writes.
  """

  # Client API

  def start_link(default) do
    # Use GlobalSingleton to avoid killing existing process during name conflicts
    # This prevents crashes during rolling deploys when Mnesia tables are being copied
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, default) do
      {:ok, pid} ->
        {:ok, pid}

      {:already_registered, _pid} ->
        # Another node already has the global TimeTracker running
        # Return :ignore so supervisor doesn't fail
        :ignore
    end
  end

  @doc """
  Updates the time spent by a user on a specific post.
  """
  def update_time(user_id, post_id, seconds) when is_integer(seconds) and seconds > 0 do
    GenServer.cast({:global, __MODULE__}, {:update_time, user_id, post_id, seconds})
  end

  def update_time(_user_id, _post_id, _seconds), do: :ok

  @doc """
  Gets the time spent by a user on a specific post.
  Reads directly from Mnesia for consistency across nodes.
  """
  def get_time(user_id, post_id) do
    key = {user_id, post_id}

    case :mnesia.dirty_read({:user_post_time, key}) do
      [] -> 0
      [{:user_post_time, ^key, ^user_id, ^post_id, seconds, _updated_at}] -> seconds
    end
  rescue
    _ -> 0
  end

  @doc """
  Gets all time data for a user.
  Returns a map of %{post_id => seconds}.
  """
  def get_user_times(user_id) do
    case :mnesia.dirty_index_read(:user_post_time, user_id, :user_id) do
      records when is_list(records) ->
        Enum.reduce(records, %{}, fn {:user_post_time, _key, ^user_id, post_id, seconds, _updated_at}, acc ->
          Map.put(acc, post_id, seconds)
        end)

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  @doc """
  Gets all tracked time data.
  Returns a map of %{user_id => %{post_id => seconds}}.
  """
  def get_all do
    case :mnesia.dirty_match_object({:user_post_time, :_, :_, :_, :_, :_}) do
      records when is_list(records) ->
        Enum.reduce(records, %{}, fn {:user_post_time, _key, user_id, post_id, seconds, _updated_at}, acc ->
          acc
          |> Map.put_new(user_id, %{})
          |> put_in([user_id, post_id], seconds)
        end)

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  # Server Callbacks

  @impl true
  def init(_default) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:update_time, user_id, post_id, seconds}, state) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    # Read-modify-write using dirty operations (safe since GenServer serializes writes)
    existing_seconds =
      case :mnesia.dirty_read({:user_post_time, key}) do
        [] -> 0
        [{:user_post_time, ^key, ^user_id, ^post_id, s, _updated_at}] -> s
      end

    :mnesia.dirty_write({:user_post_time, key, user_id, post_id, existing_seconds + seconds, now})

    {:noreply, state}
  end
end
