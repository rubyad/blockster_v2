defmodule BlocksterV2.AdsManager.Workers.CampaignLaunchWorker do
  @moduledoc """
  Async worker for launching campaigns on ad platforms.
  Handles the actual API calls to create campaigns on X/Meta/TikTok.
  """

  use Oban.Worker, queue: :ads_management, max_attempts: 3

  alias BlocksterV2.AdsManager.CampaignManager

  require Logger

  @doc """
  Enqueue a campaign for launch.
  """
  def enqueue(campaign_id) do
    %{campaign_id: campaign_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_id" => campaign_id}}) do
    unless BlocksterV2.AdsManager.enabled?() do
      Logger.debug("[CampaignLaunchWorker] Ads manager disabled, skipping")
      :ok
    else
      campaign = CampaignManager.get_campaign!(campaign_id)

      case campaign.status do
        status when status in ["draft", "pending_approval"] ->
          Logger.info("[CampaignLaunchWorker] Launching campaign #{campaign_id} on #{campaign.platform}")

          case CampaignManager.launch_campaign(campaign) do
            {:ok, _updated} ->
              Logger.info("[CampaignLaunchWorker] Campaign #{campaign_id} launched successfully")
              :ok

            {:error, reason} ->
              Logger.error("[CampaignLaunchWorker] Campaign #{campaign_id} launch failed: #{inspect(reason)}")
              {:error, reason}
          end

        other ->
          Logger.debug("[CampaignLaunchWorker] Campaign #{campaign_id} in #{other} status, skipping launch")
          :ok
      end
    end
  rescue
    e ->
      Logger.error("[CampaignLaunchWorker] Error: #{inspect(e)}")
      :ok
  end
end
