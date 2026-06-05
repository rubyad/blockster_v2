defmodule BlocksterV2.Workers.AIManagerReviewWorker do
  @moduledoc """
  Oban worker for AI Manager autonomous reviews (daily / weekly).

  DORMANT (2026-06-05): the cron entries were removed from config.exs — each
  scheduled run was a Claude Opus call (~420/year). The module is kept so a
  review can still be run on demand:

      Oban.insert(BlocksterV2.Workers.AIManagerReviewWorker.new(%{"type" => "daily"}))

  Re-adding the crontab entries reintroduces recurring Anthropic spend —
  get explicit sign-off first. The dormancy contract test guards this.
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
