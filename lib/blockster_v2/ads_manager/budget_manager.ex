defmodule BlocksterV2.AdsManager.BudgetManager do
  @moduledoc """
  Budget allocation, tracking, pacing, and limit enforcement.
  Manages daily/weekly/monthly budgets per platform and globally.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.AdsManager.Schemas.{Budget, BudgetAdjustment}
  alias BlocksterV2.AdsManager.Config

  require Logger

  @platforms ~w(x meta tiktok telegram)

  # Default platform allocation percentages
  @default_allocations %{
    "x" => 0.35,
    "meta" => 0.35,
    "tiktok" => 0.20,
    "telegram" => 0.10
  }

  @doc """
  Create or reset daily budgets for all platforms.
  Called by DailyBudgetResetWorker at midnight UTC.
  """
  def reset_daily_budgets do
    today = Date.utc_today()
    daily_total = Config.daily_budget_limit()

    Enum.each(@platforms, fn platform ->
      allocation = Map.get(@default_allocations, platform, 0.25)
      amount = Decimal.mult(Decimal.new("#{daily_total}"), Decimal.new("#{allocation}"))

      case get_budget(platform, "daily", today) do
        nil ->
          create_budget(%{
            platform: platform,
            period_type: "daily",
            period_start: today,
            period_end: today,
            allocated_amount: amount
          })

        existing ->
          # Don't reset if already has spend — just update allocation if needed
          if Decimal.compare(existing.spent_amount, Decimal.new(0)) == :eq do
            update_budget(existing, %{allocated_amount: amount})
          else
            {:ok, existing}
          end
      end
    end)

    # Create global daily budget
    global_amount = Decimal.new("#{daily_total}")
    case get_budget(nil, "daily", today) do
      nil ->
        create_budget(%{
          platform: nil,
          period_type: "daily",
          period_start: today,
          period_end: today,
          allocated_amount: global_amount
        })
      _ -> :ok
    end

    Logger.info("[BudgetManager] Daily budgets reset for #{today}")
    :ok
  end

  @doc """
  Record spend for a campaign/platform.
  """
  def record_spend(platform, amount) do
    today = Date.utc_today()

    case get_budget(platform, "daily", today) do
      nil ->
        Logger.warning("[BudgetManager] No daily budget found for #{platform} on #{today}")
        {:error, :no_budget}

      budget ->
        new_spent = Decimal.add(budget.spent_amount, Decimal.new("#{amount}"))
        status = if Decimal.compare(new_spent, budget.allocated_amount) != :lt, do: "exhausted", else: "active"
        update_budget(budget, %{spent_amount: new_spent, status: status})
    end
  end

  @doc """
  Get remaining budget for a platform today.
  """
  def remaining_today(platform) do
    today = Date.utc_today()

    case get_budget(platform, "daily", today) do
      nil -> Decimal.new(0)
      budget -> Budget.remaining_amount(budget)
    end
  end

  @doc """
  Get all daily budgets for today with their status.
  """
  def today_budgets do
    today = Date.utc_today()

    Budget
    |> where([b], b.period_type == "daily" and b.period_start == ^today)
    |> Repo.all()
  end

  @doc """
  Get spend summary for a date range.
  """
  def spend_summary(from_date, to_date) do
    Budget
    |> where([b], b.period_type == "daily")
    |> where([b], b.period_start >= ^from_date and b.period_end <= ^to_date)
    |> group_by([b], b.platform)
    |> select([b], %{
      platform: b.platform,
      total_allocated: sum(b.allocated_amount),
      total_spent: sum(b.spent_amount)
    })
    |> Repo.all()
  end

  @doc """
  Log a budget adjustment (for audit trail).
  """
  def log_adjustment(attrs) do
    %BudgetAdjustment{}
    |> BudgetAdjustment.changeset(attrs)
    |> Repo.insert()
  end

  # ============ Private ============

  defp get_budget(platform, period_type, date) do
    query =
      Budget
      |> where([b], b.period_type == ^period_type and b.period_start == ^date)

    query =
      if platform do
        where(query, [b], b.platform == ^platform)
      else
        where(query, [b], is_nil(b.platform))
      end

    Repo.one(query)
  end

  defp create_budget(attrs) do
    %Budget{}
    |> Budget.changeset(attrs)
    |> Repo.insert()
  end

  defp update_budget(budget, attrs) do
    budget
    |> Budget.changeset(attrs)
    |> Repo.update()
  end
end
