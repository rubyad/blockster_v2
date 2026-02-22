defmodule BlocksterV2.AdsManager do
  @moduledoc """
  Central AI Ads Manager GenServer. Receives PubSub events, coordinates
  campaign creation, budget management, and platform operations.

  Runs as a GlobalSingleton — one instance across the cluster.
  Feature-flagged behind AI_ADS_MANAGER_ENABLED env var.
  """

  use GenServer
  require Logger

  alias BlocksterV2.AdsManager.{
    Config,
    CampaignManager,
    BudgetManager,
    DecisionLogger,
    SafetyGuards,
    PlatformClient
  }

  @pubsub BlocksterV2.PubSub

  # ============ Client API ============

  def start_link(opts \\ []) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc """
  Check if the ads manager is enabled and running.
  """
  def enabled? do
    Config.enabled?() && Config.ai_ads_enabled?()
  end

  @doc """
  Submit an admin instruction to the AI agent.
  """
  def submit_instruction(instruction_text, admin_user_id) do
    if enabled?() do
      case :global.whereis_name(__MODULE__) do
        :undefined -> {:error, :not_running}
        pid -> GenServer.cast(pid, {:admin_instruction, instruction_text, admin_user_id})
      end
    else
      {:error, :disabled}
    end
  end

  # ============ GenServer Callbacks ============

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(@pubsub, "post:published")
    Phoenix.PubSub.subscribe(@pubsub, "ads_manager")

    Logger.info("[AdsManager] Started — listening on post:published + ads_manager")

    {:ok, %{
      last_check_at: nil,
      pending_approvals: [],
      active_campaign_ids: []
    }}
  end

  # ============ Event Handlers ============

  @impl true
  def handle_info({:post_published, post}, state) do
    Task.start(fn -> evaluate_post_for_promotion(post) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:create_ads_for_post, post, platforms}, state) do
    Task.start(fn -> create_ads_for_platforms(post, platforms) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:performance_update, data}, state) do
    Task.start(fn -> process_performance_update(data) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:budget_alert, alert}, state) do
    Task.start(fn -> handle_budget_alert(alert) end)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast({:admin_instruction, text, admin_user_id}, state) do
    Task.start(fn -> process_admin_instruction(text, admin_user_id) end)
    {:noreply, state}
  end

  # ============ Core Logic ============

  defp evaluate_post_for_promotion(post) do
    unless enabled?() do
      Logger.debug("[AdsManager] Disabled — skipping post #{post.id}")
      :skip
    else
      Logger.info("[AdsManager] Evaluating post #{post.id} (#{post.title}) for ad promotion")

      # Check if we already have campaigns for this post
      existing = CampaignManager.campaigns_for_content("post", post.id)

      if existing != [] do
        Logger.debug("[AdsManager] Post #{post.id} already has #{length(existing)} campaign(s)")

        DecisionLogger.log_decision(%{
          decision_type: "evaluate_post",
          input_context: %{post_id: post.id, title: post.title, existing_campaigns: length(existing)},
          reasoning: "Post already has active campaigns, skipping",
          action_taken: %{action: "skip"},
          outcome: "skipped"
        })
      else
        # Check safety before proceeding
        case SafetyGuards.check_safety(:create_campaign, %{budget_daily: 10}) do
          :ok ->
            create_post_campaign(post)

          {:error, reason} ->
            DecisionLogger.log_decision(%{
              decision_type: "evaluate_post",
              input_context: %{post_id: post.id, title: post.title},
              reasoning: "Safety check failed: #{reason}",
              action_taken: %{action: "blocked"},
              outcome: "failure",
              outcome_details: %{reason: reason}
            })
        end
      end
    end
  rescue
    e ->
      Logger.error("[AdsManager] Error evaluating post: #{inspect(e)}")
  end

  defp create_ads_for_platforms(post, platforms) do
    Logger.info("[AdsManager] Admin-triggered ad creation for post #{post.id} on platforms: #{inspect(platforms)}")

    Enum.each(platforms, fn platform ->
      # Check if campaign already exists for this post + platform
      existing =
        CampaignManager.campaigns_for_content("post", post.id)
        |> Enum.filter(&(&1.platform == platform))

      if existing == [] do
        create_post_campaign(post, platform)
      else
        Logger.debug("[AdsManager] Post #{post.id} already has a #{platform} campaign — skipping")
      end
    end)
  rescue
    e -> Logger.error("[AdsManager] Error creating ads for platforms: #{inspect(e)}")
  end

  defp create_post_campaign(post, platform \\ "x") do
    attrs = %{
      platform: platform,
      name: "Article: #{String.slice(post.title, 0, 200)}",
      objective: "traffic",
      content_type: "post",
      content_id: post.id,
      budget_daily: Decimal.new("10"),
      targeting_config: %{
        "interests" => ["blockchain", "cryptocurrency", "web3"],
        "locations" => ["US", "UK", "CA"]
      },
      status: "draft",
      created_by: "ai",
      ai_confidence_score: Decimal.new("0.75")
    }

    case CampaignManager.create_from_ai_decision(attrs) do
      {:ok, campaign} ->
        Logger.info("[AdsManager] Created draft campaign #{campaign.id} for post #{post.id}")

        # Request copy generation from Node.js service
        generate_copy_for_campaign(campaign, post)

        DecisionLogger.log_decision(%{
          decision_type: "create_campaign",
          input_context: %{post_id: post.id, title: post.title},
          reasoning: "Creating #{platform} campaign for traffic",
          action_taken: %{campaign_id: campaign.id, platform: platform, daily_budget: 10},
          outcome: if(campaign.status == "pending_approval", do: "pending_approval", else: "success"),
          campaign_id: campaign.id,
          platform: platform,
          budget_impact: Decimal.new("10")
        })

      {:error, reason} ->
        Logger.warning("[AdsManager] Failed to create campaign for post #{post.id}: #{inspect(reason)}")
    end
  end

  defp generate_copy_for_campaign(campaign, post) do
    case PlatformClient.generate_copy(%{
      content_type: "post",
      title: post.title,
      excerpt: post.excerpt || "",
      platform: campaign.platform,
      objective: campaign.objective
    }) do
      {:ok, %{"variants" => variants}} ->
        Enum.each(variants, fn variant ->
          CampaignManager.add_creative(campaign, %{
            platform: campaign.platform,
            type: "text",
            headline: variant["headline"],
            body: variant["body"],
            cta_text: variant["cta_text"],
            hashtags: variant["hashtags"] || [],
            source: "ai",
            status: "draft"
          })
        end)

      {:error, reason} ->
        Logger.warning("[AdsManager] Copy generation failed for campaign #{campaign.id}: #{inspect(reason)}")
    end
  rescue
    e -> Logger.error("[AdsManager] Copy generation error: #{inspect(e)}")
  end

  defp process_performance_update(data) do
    # Phase 1: Log performance data, no optimization yet
    Logger.debug("[AdsManager] Performance update: #{inspect(data)}")
  end

  defp handle_budget_alert(alert) do
    Logger.warning("[AdsManager] Budget alert: #{inspect(alert)}")

    case alert[:type] do
      "daily_80_pct" ->
        DecisionLogger.log_decision(%{
          decision_type: "anomaly_detected",
          input_context: alert,
          reasoning: "Daily budget at 80% — throttling new campaigns",
          action_taken: %{action: "throttle"},
          outcome: "success"
        })

      "daily_exceeded" ->
        SafetyGuards.emergency_stop!("Daily budget exceeded")

      _ ->
        :ok
    end
  end

  defp process_admin_instruction(text, admin_user_id) do
    alias BlocksterV2.AdsManager.Schemas.Instruction

    # Log the instruction
    {:ok, instruction} =
      %Instruction{}
      |> Instruction.changeset(%{
        admin_user_id: admin_user_id,
        instruction_text: text,
        status: "processing"
      })
      |> BlocksterV2.Repo.insert()

    # Phase 1: Simple keyword-based parsing. Phase 5 will use Claude for NLP.
    actions = parse_simple_instruction(text)

    instruction
    |> Instruction.changeset(%{
      parsed_intent: %{actions: actions},
      actions_taken: %{results: Enum.map(actions, &execute_instruction_action/1)},
      status: "completed",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> BlocksterV2.Repo.update()

    Logger.info("[AdsManager] Processed admin instruction: #{text}")
  rescue
    e -> Logger.error("[AdsManager] Admin instruction error: #{inspect(e)}")
  end

  defp parse_simple_instruction(text) do
    text = String.downcase(text)

    cond do
      String.contains?(text, "pause") && String.contains?(text, "all") ->
        [%{action: "pause_all"}]

      String.contains?(text, "pause") ->
        [%{action: "pause", detail: text}]

      String.contains?(text, "resume") ->
        [%{action: "resume", detail: text}]

      String.contains?(text, "status") || String.contains?(text, "report") ->
        [%{action: "status_report"}]

      true ->
        [%{action: "unknown", text: text}]
    end
  end

  defp execute_instruction_action(%{action: "pause_all"}) do
    campaigns = CampaignManager.active_campaigns()
    Enum.each(campaigns, &CampaignManager.pause_campaign(&1, "admin_instruction"))
    %{action: "pause_all", campaigns_paused: length(campaigns)}
  end

  defp execute_instruction_action(%{action: "status_report"}) do
    %{
      action: "status_report",
      active_campaigns: length(CampaignManager.active_campaigns()),
      today_spend: SafetyGuards.total_spend_today(),
      month_spend: SafetyGuards.total_spend_this_month()
    }
  end

  defp execute_instruction_action(action), do: %{action: "unhandled", detail: action}
end
