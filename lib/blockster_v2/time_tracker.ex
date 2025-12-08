defmodule BlocksterV2.TimeTracker do
  use GenServer

  @moduledoc """
  Tracks time spent by users on posts.
  State structure: %{user_id => %{post_id => seconds}}
  """

  # Client API

  def start_link(default) do
    GenServer.start_link(__MODULE__, default, name: {:global, __MODULE__})
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
  """
  def get_time(user_id, post_id) do
    GenServer.call({:global, __MODULE__}, {:get_time, user_id, post_id})
  end

  @doc """
  Gets all time data for a user.
  """
  def get_user_times(user_id) do
    GenServer.call({:global, __MODULE__}, {:get_user_times, user_id})
  end

  @doc """
  Gets all tracked time data.
  """
  def get_all() do
    GenServer.call({:global, __MODULE__}, :get_all)
  end

  # Server Callbacks

  @impl true
  def init(_default) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_time, user_id, post_id}, _from, state) do
    time = get_in(state, [user_id, post_id]) || 0
    {:reply, time, state}
  end

  @impl true
  def handle_call({:get_user_times, user_id}, _from, state) do
    user_times = Map.get(state, user_id, %{})
    {:reply, user_times, state}
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:update_time, user_id, post_id, seconds}, state) do
    new_state =
      state
      |> Map.put_new(user_id, %{})
      |> update_in([user_id, post_id], fn
        nil -> seconds
        existing -> existing + seconds
      end)

    {:noreply, new_state}
  end
end
