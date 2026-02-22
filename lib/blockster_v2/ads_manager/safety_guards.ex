defmodule BlocksterV2.AdsManager.SafetyGuards do
  @moduledoc """
  Spending limits, anomaly detection, and kill switches for the AI Ads Manager.

  Safety levels:
  - L1: Per Campaign ($20/day, $200 lifetime) → auto-pause campaign
  - L2: Per Platform ($25/day, $750/month) → throttle new campaigns
  - L3: Global ($50/day, $1,500/month) → pause all, alert admin
  - L4: Per Decision (>50% budget increase) → require admin approval
  - Hard Ceiling: $3,000/month → cannot be overridden
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.AdsManager.{Config, DecisionLogger}
  alias BlocksterV2.AdsManager.Schemas.{Campaign, Budget}
  alias BlocksterV2.Notifications.SystemConfig

  require Logger

  @doc """
  Check if a proposed action is safe to execute.
  Returns :ok or {:error, reason}.
  """
  def check_safety(action, params \\ %{}) do
    with :ok <- check_enabled(),
         :ok <- check_hard_ceiling(),
         :ok <- check_global_daily_limit(),
         :ok <- check_action_specific(action, params) do
      :ok
    end
  end

  @doc """
  Check if a campaign budget is within limits.
  """
  def check_campaign_budget(daily_budget, lifetime_budget \\ nil) do
    l1_daily = SystemConfig.get("ads_l1_campaign_daily_limit", 20)
    l1_lifetime = SystemConfig.get("ads_l1_campaign_lifetime_limit", 200)

    cond do
      daily_budget && Decimal.compare(Decimal.new("#{daily_budget}"), Decimal.new("#{l1_daily}")) == :gt ->
        {:error, "Campaign daily budget $#{daily_budget} exceeds L1 limit of $#{l1_daily}"}

      lifetime_budget && Decimal.compare(Decimal.new("#{lifetime_budget}"), Decimal.new("#{l1_lifetime}")) == :gt ->
        {:error, "Campaign lifetime budget $#{lifetime_budget} exceeds L1 limit of $#{l1_lifetime}"}

      true ->
        :ok
    end
  end

  @doc """
  Check if a proposed budget increase requires admin approval.
  """
  def requires_approval?(action, params) do
    autonomy = Config.autonomy_level()
    threshold = Config.approval_threshold()

    cond do
      autonomy == "manual" -> true
      action == :create_campaign && (params[:budget_daily] || 0) > threshold -> true
      action == :increase_budget && (params[:increase_pct] || 0) > 50 -> true
      true -> false
    end
  end

  @doc """
  Emergency kill switch — pause all active campaigns.
  """
  def emergency_stop!(reason) do
    Logger.error("[SafetyGuards] EMERGENCY STOP: #{reason}")

    {count, _} =
      Campaign
      |> where([c], c.status == "active")
      |> Repo.update_all(set: [status: "paused", updated_at: DateTime.utc_now() |> DateTime.truncate(:second)])

    SystemConfig.put("ai_ads_enabled", false, "safety_guard")

    DecisionLogger.log_decision(%{
      decision_type: "anomaly_detected",
      input_context: %{reason: reason},
      reasoning: "Emergency stop triggered: #{reason}",
      action_taken: %{action: "emergency_stop", campaigns_paused: count},
      outcome: "success",
      budget_impact: Decimal.new(0)
    })

    {:ok, count}
  end

  @doc """
  Get current daily spend across all platforms.
  """
  def total_spend_today do
    today = Date.utc_today()

    Budget
    |> where([b], b.period_type == "daily" and b.period_start == ^today)
    |> Repo.aggregate(:sum, :spent_amount) || Decimal.new(0)
  end

  @doc """
  Get current monthly spend.
  """
  def total_spend_this_month do
    month_start = Date.utc_today() |> Date.beginning_of_month()
    month_end = Date.utc_today() |> Date.end_of_month()

    Budget
    |> where([b], b.period_type == "monthly" and b.period_start == ^month_start and b.period_end == ^month_end)
    |> Repo.aggregate(:sum, :spent_amount) || Decimal.new(0)
  end

  # ============ Private Checks ============

  defp check_enabled do
    if Config.ai_ads_enabled?() do
      :ok
    else
      {:error, "AI Ads Manager is disabled"}
    end
  end

  defp check_hard_ceiling do
    monthly_spend = total_spend_this_month()
    ceiling = Decimal.new("#{Config.hard_ceiling_monthly()}")

    if Decimal.compare(monthly_spend, ceiling) == :lt do
      :ok
    else
      emergency_stop!("Monthly hard ceiling of $#{Config.hard_ceiling_monthly()} reached")
      {:error, "Monthly hard ceiling reached"}
    end
  end

  defp check_global_daily_limit do
    daily_spend = total_spend_today()
    limit = Decimal.new("#{Config.daily_budget_limit()}")

    if Decimal.compare(daily_spend, limit) == :lt do
      :ok
    else
      {:error, "Global daily budget limit of $#{Config.daily_budget_limit()} reached"}
    end
  end

  defp check_action_specific(:create_campaign, params) do
    check_campaign_budget(params[:budget_daily], params[:budget_lifetime])
  end

  defp check_action_specific(_action, _params), do: :ok
end
