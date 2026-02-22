defmodule BlocksterV2.Workers.EventCleanupWorker do
  @moduledoc """
  Daily Oban worker that deletes user_events older than 90 days.
  Runs in batches to avoid long-running transactions.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  require Logger

  @batch_size 5_000
  @retention_days 90

  @impl Oban.Worker
  def perform(_job) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-@retention_days, :day)
    delete_in_batches(cutoff, 0)
  end

  defp delete_in_batches(cutoff, total_deleted) do
    # Select a batch of IDs to delete
    ids =
      from(e in "user_events",
        where: e.inserted_at < ^cutoff,
        select: e.id,
        limit: @batch_size
      )
      |> BlocksterV2.Repo.all()

    if ids == [] do
      if total_deleted > 0 do
        Logger.info("[EventCleanup] Deleted #{total_deleted} events older than #{@retention_days} days")
      end

      :ok
    else
      {deleted, _} =
        from(e in "user_events", where: e.id in ^ids)
        |> BlocksterV2.Repo.delete_all()

      delete_in_batches(cutoff, total_deleted + deleted)
    end
  end
end
