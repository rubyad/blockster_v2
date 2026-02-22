defmodule BlocksterV2.AdsManager.Workers.DailyBudgetResetWorker do
  @moduledoc """
  Runs at midnight UTC to reset daily budget allocations
  and close out the previous day's budgets.
  """

  use Oban.Worker, queue: :ads_management, max_attempts: 3

  alias BlocksterV2.AdsManager.BudgetManager

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    unless BlocksterV2.AdsManager.enabled?() do
      Logger.debug("[DailyBudgetResetWorker] Ads manager disabled, skipping")
      :ok
    else
      Logger.info("[DailyBudgetResetWorker] Resetting daily budgets")
      BudgetManager.reset_daily_budgets()
      :ok
    end
  rescue
    e ->
      Logger.error("[DailyBudgetResetWorker] Error: #{inspect(e)}")
      :ok
  end
end
