defmodule BlocksterV2.Workers.AIManagerReviewWorker do
  @moduledoc """
  Oban cron worker for AI Manager autonomous reviews.
  - Daily review: 6 AM UTC
  - Weekly optimization: Monday 7 AM UTC

  Configure in Oban crontab:
    {"0 6 * * *", BlocksterV2.Workers.AIManagerReviewWorker, args: %{"type" => "daily"}}
    {"0 7 * * 1", BlocksterV2.Workers.AIManagerReviewWorker, args: %{"type" => "weekly"}}
  """

  use Oban.Worker, queue: :email_marketing, max_attempts: 2

  require Logger

  alias BlocksterV2.Notifications.AIManager

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "daily"}}) do
    Logger.info("[AIManagerReview] Starting daily review")

    case AIManager.autonomous_daily_review() do
      {:ok, response} ->
        Logger.info("[AIManagerReview] Daily review complete: #{String.slice(response, 0..100)}")
        :ok

      {:error, reason} ->
        Logger.error("[AIManagerReview] Daily review failed: #{inspect(reason)}")
        :ok
    end
  end

  def perform(%Oban.Job{args: %{"type" => "weekly"}}) do
    Logger.info("[AIManagerReview] Starting weekly optimization")

    case AIManager.autonomous_weekly_optimization() do
      {:ok, response} ->
        Logger.info("[AIManagerReview] Weekly optimization complete: #{String.slice(response, 0..100)}")
        :ok

      {:error, reason} ->
        Logger.error("[AIManagerReview] Weekly optimization failed: #{inspect(reason)}")
        :ok
    end
  end

  def perform(_job), do: :ok
end
