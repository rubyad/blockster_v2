defmodule BlocksterV2.AdsManager.CampaignManager do
  @moduledoc """
  Campaign CRUD operations and state machine management.
  Handles campaign lifecycle from draft through completion.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.AdsManager.Schemas.{Campaign, Creative, PlatformAccount}
  alias BlocksterV2.AdsManager.{DecisionLogger, SafetyGuards, PlatformClient}

  require Logger

  # ============ CRUD ============

  def create_campaign(attrs) do
    %Campaign{}
    |> Campaign.changeset(attrs)
    |> Repo.insert()
  end

  def get_campaign(id), do: Repo.get(Campaign, id)
  def get_campaign!(id), do: Repo.get!(Campaign, id)

  def update_campaign(%Campaign{} = campaign, attrs) do
    campaign
    |> Campaign.changeset(attrs)
    |> Repo.update()
  end

  def update_status(%Campaign{} = campaign, new_status) do
    campaign
    |> Campaign.status_changeset(new_status)
    |> Repo.update()
  end

  def list_campaigns(opts \\ []) do
    status = Keyword.get(opts, :status)
    platform = Keyword.get(opts, :platform)
    content_type = Keyword.get(opts, :content_type)
    limit = Keyword.get(opts, :limit, 50)

    Campaign
    |> maybe_filter(:status, status)
    |> maybe_filter(:platform, platform)
    |> maybe_filter(:content_type, content_type)
    |> order_by([c], desc: c.inserted_at)
    |> limit(^limit)
    |> preload([:account, :creatives])
    |> Repo.all()
  end

  def active_campaigns do
    Campaign
    |> where([c], c.status in ["active", "pending_approval"])
    |> preload([:account, :creatives])
    |> Repo.all()
  end

  def campaigns_for_content(content_type, content_id) do
    Campaign
    |> where([c], c.content_type == ^content_type and c.content_id == ^content_id)
    |> where([c], c.status not in ["archived", "failed"])
    |> Repo.all()
  end

  # ============ Campaign Actions ============

  @doc """
  Create a campaign from an AI decision. Validates budget, checks safety,
  and optionally requires admin approval.
  """
  def create_from_ai_decision(decision) do
    with :ok <- SafetyGuards.check_safety(:create_campaign, decision),
         {:ok, campaign} <- create_campaign(Map.merge(decision, %{created_by: "ai", status: "draft"})) do

      if SafetyGuards.requires_approval?(:create_campaign, decision) do
        update_status(campaign, "pending_approval")
      else
        {:ok, campaign}
      end
    end
  end

  @doc """
  Create a campaign from admin input. Skips AI approval, goes directly to draft.
  """
  def create_from_admin(attrs, admin_user_id) do
    attrs = Map.merge(attrs, %{
      created_by: "admin",
      created_by_user_id: admin_user_id,
      admin_override: true
    })

    create_campaign(attrs)
  end

  @doc """
  Launch a campaign on the ad platform via Node.js service.
  """
  def launch_campaign(%Campaign{} = campaign) do
    with :ok <- SafetyGuards.check_safety(:create_campaign, %{budget_daily: campaign.budget_daily}),
         {:ok, platform_response} <- PlatformClient.create_campaign(build_platform_params(campaign)),
         {:ok, updated} <- update_campaign(campaign, %{
           platform_campaign_id: platform_response["campaign_id"],
           status: "active"
         }) do
      DecisionLogger.log_decision(%{
        decision_type: "create_campaign",
        input_context: %{campaign_id: campaign.id, platform: campaign.platform},
        reasoning: "Campaign launched on #{campaign.platform}",
        action_taken: %{platform_campaign_id: platform_response["campaign_id"]},
        outcome: "success",
        campaign_id: campaign.id,
        platform: campaign.platform,
        budget_impact: campaign.budget_daily
      })

      {:ok, updated}
    else
      {:error, reason} ->
        Logger.error("[CampaignManager] Failed to launch campaign #{campaign.id}: #{inspect(reason)}")
        update_status(campaign, "failed")
        {:error, reason}
    end
  end

  @doc """
  Pause a campaign.
  """
  def pause_campaign(%Campaign{} = campaign, reason \\ "manual") do
    if campaign.platform_campaign_id do
      PlatformClient.pause_campaign(campaign.platform_campaign_id)
    end

    update_status(campaign, "paused")
  end

  @doc """
  Resume a paused campaign.
  """
  def resume_campaign(%Campaign{} = campaign) do
    if campaign.platform_campaign_id do
      PlatformClient.resume_campaign(campaign.platform_campaign_id)
    end

    update_status(campaign, "active")
  end

  @doc """
  Approve a pending campaign (admin action).
  """
  def approve_campaign(%Campaign{status: "pending_approval"} = campaign) do
    update_status(campaign, "active")
  end

  def approve_campaign(_), do: {:error, "Campaign is not pending approval"}

  @doc """
  Reject a pending campaign (admin action).
  """
  def reject_campaign(%Campaign{status: "pending_approval"} = campaign) do
    update_status(campaign, "archived")
  end

  def reject_campaign(_), do: {:error, "Campaign is not pending approval"}

  # ============ Creative Management ============

  def add_creative(%Campaign{} = campaign, attrs) do
    attrs = Map.put(attrs, :campaign_id, campaign.id)

    %Creative{}
    |> Creative.changeset(attrs)
    |> Repo.insert()
  end

  def list_creatives(campaign_id) do
    Creative
    |> where([c], c.campaign_id == ^campaign_id)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  # ============ Platform Account Management ============

  def list_accounts(opts \\ []) do
    platform = Keyword.get(opts, :platform)

    PlatformAccount
    |> maybe_filter(:platform, platform)
    |> where([a], a.status == "active")
    |> order_by([a], asc: a.platform, asc: a.account_name)
    |> Repo.all()
  end

  def create_account(attrs) do
    %PlatformAccount{}
    |> PlatformAccount.changeset(attrs)
    |> Repo.insert()
  end

  def get_account(id), do: Repo.get(PlatformAccount, id)

  def update_account(%PlatformAccount{} = account, attrs) do
    account
    |> PlatformAccount.changeset(attrs)
    |> Repo.update()
  end

  # ============ Stats ============

  def campaign_count_by_status do
    Campaign
    |> group_by([c], c.status)
    |> select([c], {c.status, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  def total_spend do
    Campaign
    |> Repo.aggregate(:sum, :spend_total) || Decimal.new(0)
  end

  # ============ Helpers ============

  defp build_platform_params(%Campaign{} = campaign) do
    %{
      platform: campaign.platform,
      account_id: campaign.account_id,
      name: campaign.name,
      objective: campaign.objective,
      daily_budget: campaign.budget_daily,
      lifetime_budget: campaign.budget_lifetime,
      targeting: campaign.targeting_config,
      content_type: campaign.content_type,
      content_id: campaign.content_id
    }
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :status, value), do: where(query, [c], c.status == ^value)
  defp maybe_filter(query, :platform, value), do: where(query, [c], c.platform == ^value)
  defp maybe_filter(query, :content_type, value), do: where(query, [c], c.content_type == ^value)
end
