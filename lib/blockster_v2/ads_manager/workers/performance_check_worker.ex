defmodule BlocksterV2.AdsManager.Workers.PerformanceCheckWorker do
  @moduledoc """
  Hourly worker that pulls performance data from ad platforms
  and updates campaign metrics. Detects anomalies.
  """

  use Oban.Worker, queue: :ads_analytics, max_attempts: 3

  alias BlocksterV2.AdsManager.{CampaignManager, PlatformClient, SafetyGuards, DecisionLogger}
  alias BlocksterV2.AdsManager.Schemas.PerformanceSnapshot
  alias BlocksterV2.Repo

  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    unless BlocksterV2.AdsManager.enabled?() do
      Logger.debug("[PerformanceCheckWorker] Ads manager disabled, skipping")
      :ok
    else
      Logger.info("[PerformanceCheckWorker] Starting hourly performance check")

      campaigns = CampaignManager.active_campaigns()

      Enum.each(campaigns, fn campaign ->
        if campaign.platform_campaign_id do
          pull_campaign_metrics(campaign)
        end
      end)

      check_for_anomalies(campaigns)

      :ok
    end
  rescue
    e ->
      Logger.error("[PerformanceCheckWorker] Error: #{inspect(e)}")
      :ok
  end

  defp pull_campaign_metrics(campaign) do
    case PlatformClient.get_campaign_analytics(campaign.platform_campaign_id) do
      {:ok, metrics} ->
        # Save snapshot
        %PerformanceSnapshot{}
        |> PerformanceSnapshot.changeset(%{
          campaign_id: campaign.id,
          platform: campaign.platform,
          snapshot_at: DateTime.utc_now() |> DateTime.truncate(:second),
          impressions: metrics["impressions"] || 0,
          clicks: metrics["clicks"] || 0,
          conversions: metrics["conversions"] || 0,
          spend: metrics["spend"] || 0,
          platform_metrics: metrics["extra"] || %{}
        })
        |> Repo.insert()

        # Update campaign spend total
        if metrics["spend"] do
          CampaignManager.update_campaign(campaign, %{
            spend_total: Decimal.new("#{metrics["spend"]}")
          })
        end

      {:error, reason} ->
        Logger.warning("[PerformanceCheckWorker] Failed to pull metrics for campaign #{campaign.id}: #{inspect(reason)}")
    end
  rescue
    e -> Logger.error("[PerformanceCheckWorker] Metrics error for campaign #{campaign.id}: #{inspect(e)}")
  end

  defp check_for_anomalies(campaigns) do
    daily_spend = SafetyGuards.total_spend_today()
    daily_limit = BlocksterV2.AdsManager.Config.daily_budget_limit()

    # Check if we're at 80% of daily budget
    if Decimal.compare(daily_spend, Decimal.mult(Decimal.new("#{daily_limit}"), Decimal.new("0.8"))) != :lt do
      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "ads_manager", {:budget_alert, %{
        type: "daily_80_pct",
        spend: daily_spend,
        limit: daily_limit
      }})
    end

    # Check for zero-conversion campaigns with significant spend
    Enum.each(campaigns, fn campaign ->
      spend = campaign.spend_total || Decimal.new(0)

      if Decimal.compare(spend, Decimal.new("50")) != :lt do
        # Check if any conversions in last 24h snapshots
        recent_conversions =
          BlocksterV2.AdsManager.Schemas.PerformanceSnapshot
          |> Ecto.Query.where([s], s.campaign_id == ^campaign.id)
          |> Ecto.Query.where([s], s.snapshot_at >= ^(DateTime.utc_now() |> DateTime.add(-86400, :second)))
          |> Repo.aggregate(:sum, :conversions)

        if (recent_conversions || 0) == 0 do
          Logger.warning("[PerformanceCheckWorker] Campaign #{campaign.id} has $#{spend} spend with 0 conversions")

          DecisionLogger.log_decision(%{
            decision_type: "anomaly_detected",
            input_context: %{campaign_id: campaign.id, spend: spend, conversions: 0},
            reasoning: "Campaign has significant spend ($#{spend}) but zero conversions in 24h",
            action_taken: %{action: "alert", recommendation: "consider_pausing"},
            outcome: "success",
            campaign_id: campaign.id,
            platform: campaign.platform
          })
        end
      end
    end)
  rescue
    e -> Logger.error("[PerformanceCheckWorker] Anomaly check error: #{inspect(e)}")
  end
end
