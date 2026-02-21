defmodule BlocksterV2.Workers.ProfileRecalcWorker do
  @moduledoc """
  Recalculates user profiles every 6 hours via Oban cron.
  Processes users in batches, prioritizing those with the most new events.
  Also triggered on-demand after high-value events.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias BlocksterV2.UserEvents
  alias BlocksterV2.Notifications.ProfileEngine

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    # Single user recalculation (on-demand)
    recalculate_single(user_id)
  end

  def perform(%Oban.Job{args: _args}) do
    # Batch recalculation (cron job)
    recalculate_batch()
  end

  @doc "Enqueue an on-demand profile recalculation for a specific user."
  def enqueue(user_id) do
    %{user_id: user_id}
    |> __MODULE__.new(unique: [period: 300, keys: [:user_id]])
    |> Oban.insert()
  end

  defp recalculate_batch do
    # Get users needing update (those with new events since last calc)
    user_ids = UserEvents.users_needing_profile_update(1)

    # Also include users that have events but no profile yet
    new_user_ids = UserEvents.users_without_profiles()

    all_user_ids = Enum.uniq(user_ids ++ new_user_ids)

    Logger.info("ProfileRecalcWorker: recalculating #{length(all_user_ids)} profiles")

    all_user_ids
    |> Enum.chunk_every(100)
    |> Enum.each(fn batch ->
      Enum.each(batch, &recalculate_single/1)
    end)

    :ok
  end

  defp recalculate_single(user_id) do
    profile_data = ProfileEngine.recalculate_profile(user_id)
    UserEvents.upsert_profile(user_id, profile_data)
    :ok
  rescue
    e ->
      Logger.warning("ProfileRecalcWorker: failed for user #{user_id}: #{inspect(e)}")
      :ok
  end
end
