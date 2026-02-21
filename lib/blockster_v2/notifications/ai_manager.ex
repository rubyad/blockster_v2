defmodule BlocksterV2.Notifications.AIManager do
  @moduledoc """
  AI Manager — Opus 4.6-powered autonomous controller of the notification system.
  Processes admin messages via tool_use, runs daily/weekly autonomous reviews.

  The AI Manager reads and writes SystemConfig to control all notification parameters.
  """

  require Logger

  alias BlocksterV2.Notifications.{SystemConfig, Notifications}
  alias BlocksterV2.ContentAutomation.Config

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"
  @model "claude-opus-4-6"
  @max_tool_rounds 5

  @system_prompt """
  You are Blockster's AI Manager. You autonomously control the notification and engagement system for a web3 content platform.

  You can:
  - Adjust referral rewards (BUX amounts for signups, phone verification)
  - Modify trigger thresholds (BUX milestones, reading streaks, cart abandonment timing)
  - Enable/disable notification triggers
  - Create and send email campaigns
  - Analyze system performance and user engagement
  - Add custom event→notification rules
  - View user profiles and referral stats

  Be decisive but conservative:
  - Don't make changes >20% without confirmation
  - Always explain what you're doing and why
  - When analyzing data, be specific with numbers
  - If asked to do something you can't, explain what alternatives exist

  The platform earns BUX tokens by reading articles, sharing on X, and referrals. Users can play BUX Booster (coin flip game) and shop with BUX/ROGUE tokens.
  """

  @tools [
    %{
      "name" => "get_system_config",
      "description" => "Read the current system configuration. Returns all configurable values: referral amounts, trigger thresholds, rate limits, conversion funnel settings, enabled/disabled triggers.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "section" => %{
            "type" => "string",
            "description" => "Optional section filter: 'referral', 'triggers', 'funnel', 'rate_limits', 'all'",
            "enum" => ["referral", "triggers", "funnel", "rate_limits", "all"]
          }
        },
        "required" => []
      }
    },
    %{
      "name" => "update_system_config",
      "description" => "Update one or more system configuration values. Changes take effect immediately (ETS cache invalidated).",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "changes" => %{
            "type" => "object",
            "description" => "Map of config keys to new values. Keys: referrer_signup_bux, referee_signup_bux, phone_verify_bux, bux_milestones, reading_streak_days, cart_abandon_hours, bux_balance_gaming_nudge, articles_before_nudge, games_before_rogue_nudge, default_max_emails_per_day, trigger_*_enabled, etc."
          }
        },
        "required" => ["changes"]
      }
    },
    %{
      "name" => "create_campaign",
      "description" => "Create a notification campaign (email blast). Optionally send immediately.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "Campaign name"},
          "subject" => %{"type" => "string", "description" => "Email subject line"},
          "body" => %{"type" => "string", "description" => "Email body (plain text)"},
          "audience" => %{"type" => "string", "description" => "Target audience: 'all', 'active', 'dormant', 'gamers', 'shoppers'", "enum" => ["all", "active", "dormant", "gamers", "shoppers"]},
          "send_now" => %{"type" => "boolean", "description" => "Send immediately if true, save as draft if false"}
        },
        "required" => ["name", "subject", "body", "audience"]
      }
    },
    %{
      "name" => "get_system_stats",
      "description" => "Get aggregate system metrics: notifications sent (24h/7d/30d), active users, conversion funnel distribution, email engagement rates.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "period" => %{"type" => "string", "description" => "Time period: '24h', '7d', '30d'", "enum" => ["24h", "7d", "30d"]}
        },
        "required" => []
      }
    },
    %{
      "name" => "get_user_profile",
      "description" => "Look up a specific user's notification profile, preferences, conversion stage, and engagement tier.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "user_id" => %{"type" => "integer", "description" => "User ID to look up"}
        },
        "required" => ["user_id"]
      }
    },
    %{
      "name" => "adjust_referral_rewards",
      "description" => "Change referrer and/or referee BUX reward amounts. Updates SystemConfig and logs the change.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "referrer_signup_bux" => %{"type" => "integer", "description" => "BUX rewarded to referrer on friend signup"},
          "referee_signup_bux" => %{"type" => "integer", "description" => "BUX rewarded to new user (referee) on signup"},
          "phone_verify_bux" => %{"type" => "integer", "description" => "BUX rewarded to referrer when friend verifies phone"}
        },
        "required" => []
      }
    },
    %{
      "name" => "modify_trigger",
      "description" => "Enable/disable a notification trigger or change its threshold.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "trigger_name" => %{
            "type" => "string",
            "description" => "Trigger to modify",
            "enum" => ["cart_abandonment", "bux_milestone", "reading_streak", "hub_recommendation", "price_drop", "purchase_thank_you", "dormancy", "referral_opportunity"]
          },
          "enabled" => %{"type" => "boolean", "description" => "Enable or disable the trigger"},
          "threshold" => %{"description" => "New threshold value (type depends on trigger)"}
        },
        "required" => ["trigger_name"]
      }
    },
    %{
      "name" => "add_custom_rule",
      "description" => "Add a custom event→notification rule. Evaluated by EventProcessor when matching events occur.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "event_type" => %{"type" => "string", "description" => "Event type to match (e.g., 'article_read_complete', 'game_played')"},
          "conditions" => %{"type" => "object", "description" => "Optional conditions to match on event metadata"},
          "title" => %{"type" => "string", "description" => "Notification title"},
          "body" => %{"type" => "string", "description" => "Notification body"},
          "notification_type" => %{"type" => "string", "description" => "Notification type (default: special_offer)"}
        },
        "required" => ["event_type", "title", "body"]
      }
    },
    %{
      "name" => "remove_custom_rule",
      "description" => "Remove a custom event rule by index.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "rule_index" => %{"type" => "integer", "description" => "Index of the rule to remove (0-based)"}
        },
        "required" => ["rule_index"]
      }
    },
    %{
      "name" => "list_campaigns",
      "description" => "List recent notification campaigns with stats.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "limit" => %{"type" => "integer", "description" => "Number of campaigns to return (default: 10)"}
        },
        "required" => []
      }
    },
    %{
      "name" => "analyze_performance",
      "description" => "Generate an analysis of recent notification and campaign performance.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      }
    },
    %{
      "name" => "get_referral_stats",
      "description" => "Get system-wide referral metrics: total referrals, conversion rates, reward amounts distributed.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      }
    },
    %{
      "name" => "send_test_notification",
      "description" => "Send a test notification to a specific user (in-app only).",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "user_id" => %{"type" => "integer", "description" => "User ID to notify"},
          "title" => %{"type" => "string", "description" => "Notification title"},
          "body" => %{"type" => "string", "description" => "Notification body"}
        },
        "required" => ["user_id", "title", "body"]
      }
    }
  ]

  # ============ Public API ============

  @doc """
  Process an admin message through the AI Manager.
  Returns {:ok, response_text, tool_results} or {:error, reason}.
  """
  def process_message(admin_message, conversation_history \\ [], admin_user_id \\ nil) do
    api_key = Config.anthropic_api_key()

    unless api_key do
      {:error, "ANTHROPIC_API_KEY not configured"}
    else
      messages = build_messages(conversation_history, admin_message)
      run_conversation(messages, api_key, admin_user_id, [], 0)
    end
  end

  @doc """
  Run autonomous daily review. Called by AIManagerReviewWorker.
  """
  def autonomous_daily_review do
    stats = gather_system_stats("24h")

    prompt = """
    Review these 24-hour notification system metrics and flag any anomalies.
    Make conservative adjustments if needed (e.g., tighten rate limits if volume is high).
    Generate a brief report.

    Metrics:
    #{Jason.encode!(stats, pretty: true)}

    Current config:
    #{Jason.encode!(SystemConfig.get_all(), pretty: true)}
    """

    case process_message(prompt) do
      {:ok, response, tool_results} ->
        log_review("daily", prompt, response, tool_results)
        {:ok, response}

      {:error, reason} ->
        Logger.error("[AIManager] Daily review failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run autonomous weekly optimization. Called by AIManagerReviewWorker.
  """
  def autonomous_weekly_optimization do
    stats = gather_system_stats("7d")

    prompt = """
    Analyze this week's notification system performance. Consider:
    1. Are referral rewards producing good conversion rates?
    2. Are any triggers firing too much or too little?
    3. Are re-engagement emails bringing users back?
    4. Suggest specific optimizations with reasoning.

    Metrics:
    #{Jason.encode!(stats, pretty: true)}

    Current config:
    #{Jason.encode!(SystemConfig.get_all(), pretty: true)}
    """

    case process_message(prompt) do
      {:ok, response, tool_results} ->
        log_review("weekly", prompt, response, tool_results)
        {:ok, response}

      {:error, reason} ->
        Logger.error("[AIManager] Weekly review failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============ Conversation Loop ============

  defp run_conversation(messages, api_key, admin_user_id, tool_results_acc, round)
       when round >= @max_tool_rounds do
    # Exceeded max rounds, return accumulated results
    {:ok, "I've completed the maximum number of operations for this request.", tool_results_acc}
  end

  defp run_conversation(messages, api_key, admin_user_id, tool_results_acc, round) do
    body = %{
      "model" => @model,
      "max_tokens" => 4096,
      "temperature" => 0.3,
      "system" => @system_prompt,
      "tools" => @tools,
      "messages" => messages
    }

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]

    case Req.post(@api_url,
      json: body,
      headers: headers,
      receive_timeout: 120_000,
      connect_options: [timeout: 15_000]
    ) do
      {:ok, %{status: 200, body: %{"content" => content, "stop_reason" => stop_reason}}} ->
        if stop_reason == "tool_use" do
          # Execute tool calls and continue conversation
          {tool_use_blocks, text_blocks} = partition_content(content)

          tool_results =
            Enum.map(tool_use_blocks, fn block ->
              result = execute_tool(block["name"], block["input"], admin_user_id)
              %{
                "type" => "tool_result",
                "tool_use_id" => block["id"],
                "content" => Jason.encode!(result)
              }
            end)

          new_tool_results_acc =
            tool_results_acc ++
              Enum.map(tool_use_blocks, fn block ->
                %{tool: block["name"], input: block["input"], result: execute_tool(block["name"], block["input"], admin_user_id)}
              end)

          # Append assistant content + tool results, continue
          new_messages =
            messages ++
              [%{"role" => "assistant", "content" => content}] ++
              [%{"role" => "user", "content" => tool_results}]

          run_conversation(new_messages, api_key, admin_user_id, new_tool_results_acc, round + 1)
        else
          # Final response — extract text
          text = extract_text(content)
          {:ok, text, tool_results_acc}
        end

      {:ok, %{status: 429}} ->
        Process.sleep(5_000)
        run_conversation(messages, api_key, admin_user_id, tool_results_acc, round)

      {:ok, %{status: status, body: body}} ->
        Logger.error("[AIManager] API returned #{status}: #{inspect(body)}")
        {:error, "Claude API returned #{status}"}

      {:error, reason} ->
        Logger.error("[AIManager] Request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  # ============ Tool Execution ============

  defp execute_tool("get_system_config", %{"section" => section}, _admin) do
    config = SystemConfig.get_all()

    case section do
      "referral" ->
        Map.take(config, ["referrer_signup_bux", "referee_signup_bux", "phone_verify_bux"])

      "triggers" ->
        config
        |> Enum.filter(fn {k, _} -> String.starts_with?(k, "trigger_") end)
        |> Map.new()
        |> Map.merge(Map.take(config, ["bux_milestones", "reading_streak_days", "cart_abandon_hours",
          "dormancy_min_days", "dormancy_max_days", "referral_propensity_threshold"]))

      "funnel" ->
        Map.take(config, ["bux_balance_gaming_nudge", "articles_before_nudge",
          "games_before_rogue_nudge", "loss_streak_rogue_offer", "win_streak_celebration", "big_win_multiplier"])

      "rate_limits" ->
        Map.take(config, ["default_max_emails_per_day", "global_max_per_hour"])

      _ ->
        config
    end
  end

  defp execute_tool("get_system_config", _input, _admin) do
    SystemConfig.get_all()
  end

  defp execute_tool("update_system_config", %{"changes" => changes}, admin) do
    updated_by = if admin, do: "ai_manager:#{admin}", else: "ai_manager"
    SystemConfig.put_many(changes, updated_by)
    %{status: "ok", updated_keys: Map.keys(changes)}
  end

  defp execute_tool("create_campaign", input, _admin) do
    attrs = %{
      name: input["name"],
      description: input["body"],
      audience_type: input["audience"] || "all",
      channels: ["email"],
      status: if(input["send_now"], do: "sent", else: "draft")
    }

    case BlocksterV2.Notifications.create_campaign(attrs) do
      {:ok, campaign} ->
        if input["send_now"] do
          BlocksterV2.Workers.PromoEmailWorker.enqueue_campaign(campaign.id)
        end

        %{status: "ok", campaign_id: campaign.id, name: campaign.name, sent: !!input["send_now"]}

      {:error, changeset} ->
        %{status: "error", errors: inspect(changeset.errors)}
    end
  end

  defp execute_tool("get_system_stats", input, _admin) do
    period = input["period"] || "24h"
    gather_system_stats(period)
  end

  defp execute_tool("get_user_profile", %{"user_id" => user_id}, _admin) do
    profile = BlocksterV2.UserEvents.get_profile(user_id)
    prefs = BlocksterV2.Notifications.get_preferences(user_id)
    user = BlocksterV2.Repo.get(BlocksterV2.Accounts.User, user_id)

    %{
      user: user && %{id: user.id, email: user.email, username: user.username},
      profile: profile && Map.from_struct(profile) |> Map.drop([:__meta__]),
      preferences: prefs && Map.from_struct(prefs) |> Map.drop([:__meta__])
    }
  end

  defp execute_tool("adjust_referral_rewards", input, admin) do
    changes =
      input
      |> Map.take(["referrer_signup_bux", "referee_signup_bux", "phone_verify_bux"])
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(changes) > 0 do
      old_values = Enum.map(changes, fn {k, _} -> {k, SystemConfig.get(k)} end) |> Map.new()
      updated_by = if admin, do: "ai_manager:#{admin}", else: "ai_manager"
      SystemConfig.put_many(changes, updated_by)
      %{status: "ok", old_values: old_values, new_values: changes}
    else
      %{status: "no_changes", message: "No valid reward fields provided"}
    end
  end

  defp execute_tool("modify_trigger", input, admin) do
    trigger = input["trigger_name"]
    config_key = "trigger_#{trigger}_enabled"

    changes = %{}
    changes = if Map.has_key?(input, "enabled"), do: Map.put(changes, config_key, input["enabled"]), else: changes

    changes =
      if Map.has_key?(input, "threshold") do
        threshold_key =
          case trigger do
            "cart_abandonment" -> "cart_abandon_hours"
            "bux_milestone" -> "bux_milestones"
            "reading_streak" -> "reading_streak_days"
            "dormancy" -> "dormancy_min_days"
            "referral_opportunity" -> "referral_propensity_threshold"
            _ -> nil
          end

        if threshold_key, do: Map.put(changes, threshold_key, input["threshold"]), else: changes
      else
        changes
      end

    if map_size(changes) > 0 do
      updated_by = if admin, do: "ai_manager:#{admin}", else: "ai_manager"
      SystemConfig.put_many(changes, updated_by)
      %{status: "ok", trigger: trigger, changes: changes}
    else
      %{status: "no_changes"}
    end
  end

  defp execute_tool("add_custom_rule", input, _admin) do
    rule = %{
      "event_type" => input["event_type"],
      "conditions" => input["conditions"],
      "action" => "notification",
      "title" => input["title"],
      "body" => input["body"],
      "notification_type" => input["notification_type"] || "special_offer"
    }

    rules = SystemConfig.get("custom_rules", [])
    SystemConfig.put("custom_rules", rules ++ [rule], "ai_manager")
    %{status: "ok", total_rules: length(rules) + 1, rule: rule}
  end

  defp execute_tool("remove_custom_rule", %{"rule_index" => index}, _admin) do
    rules = SystemConfig.get("custom_rules", [])

    if index >= 0 and index < length(rules) do
      removed = Enum.at(rules, index)
      new_rules = List.delete_at(rules, index)
      SystemConfig.put("custom_rules", new_rules, "ai_manager")
      %{status: "ok", removed_rule: removed, remaining_rules: length(new_rules)}
    else
      %{status: "error", message: "Invalid rule index. Current rules: #{length(rules)}"}
    end
  end

  defp execute_tool("list_campaigns", input, _admin) do
    limit = input["limit"] || 10

    campaigns =
      BlocksterV2.Notifications.list_campaigns(limit: limit)
      |> Enum.map(fn c ->
        %{id: c.id, name: c.name, status: c.status, audience: c.audience_type, inserted_at: c.inserted_at}
      end)

    %{campaigns: campaigns, total: length(campaigns)}
  end

  defp execute_tool("analyze_performance", _input, _admin) do
    stats_24h = gather_system_stats("24h")
    stats_7d = gather_system_stats("7d")

    %{
      last_24h: stats_24h,
      last_7d: stats_7d,
      analysis_note: "Raw metrics provided. Generate analysis from these numbers."
    }
  end

  defp execute_tool("get_referral_stats", _input, _admin) do
    # Aggregate from Mnesia
    all_stats =
      try do
        :mnesia.dirty_match_object({:referral_stats, :_, :_, :_, :_, :_, :_})
        |> Enum.reduce(
          %{total_referrers: 0, total_referrals: 0, total_verified: 0, total_bux: 0.0, total_rogue: 0.0},
          fn {:referral_stats, _, refs, verified, bux, rogue, _}, acc ->
            %{
              total_referrers: acc.total_referrers + 1,
              total_referrals: acc.total_referrals + refs,
              total_verified: acc.total_verified + verified,
              total_bux: acc.total_bux + (bux || 0),
              total_rogue: acc.total_rogue + (rogue || 0)
            }
          end
        )
      rescue
        _ -> %{total_referrers: 0, total_referrals: 0, total_verified: 0, total_bux: 0.0, total_rogue: 0.0}
      catch
        :exit, _ -> %{total_referrers: 0, total_referrals: 0, total_verified: 0, total_bux: 0.0, total_rogue: 0.0}
      end

    config = SystemConfig.get_all()

    Map.merge(all_stats, %{
      current_referrer_reward: config["referrer_signup_bux"],
      current_referee_reward: config["referee_signup_bux"],
      current_phone_reward: config["phone_verify_bux"]
    })
  end

  defp execute_tool("send_test_notification", input, _admin) do
    case BlocksterV2.Notifications.create_notification(input["user_id"], %{
      type: "special_offer",
      category: "admin",
      title: input["title"],
      body: input["body"]
    }) do
      {:ok, notif} -> %{status: "ok", notification_id: notif.id}
      {:error, _} -> %{status: "error", message: "Failed to create notification"}
    end
  end

  defp execute_tool(name, _input, _admin) do
    %{status: "error", message: "Unknown tool: #{name}"}
  end

  # ============ Helpers ============

  defp build_messages(history, new_message) do
    history_messages =
      Enum.flat_map(history, fn
        %{role: role, content: content} -> [%{"role" => to_string(role), "content" => content}]
        _ -> []
      end)

    history_messages ++ [%{"role" => "user", "content" => new_message}]
  end

  defp partition_content(content) when is_list(content) do
    tool_use = Enum.filter(content, &(&1["type"] == "tool_use"))
    text = Enum.filter(content, &(&1["type"] == "text"))
    {tool_use, text}
  end

  defp extract_text(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(& &1["text"])
    |> Enum.join("\n")
  end

  defp extract_text(_), do: ""

  defp gather_system_stats(period) do
    import Ecto.Query

    days =
      case period do
        "24h" -> 1
        "7d" -> 7
        "30d" -> 30
        _ -> 7
      end

    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    # Notifications sent
    notifications_sent =
      from(n in BlocksterV2.Notifications.Notification,
        where: n.inserted_at >= ^since,
        select: count(n.id)
      )
      |> BlocksterV2.Repo.one() || 0

    # Emails sent
    emails_sent =
      from(e in BlocksterV2.Notifications.EmailLog,
        where: e.sent_at >= ^since,
        select: count(e.id)
      )
      |> BlocksterV2.Repo.one() || 0

    # Email opens
    emails_opened =
      from(e in BlocksterV2.Notifications.EmailLog,
        where: e.sent_at >= ^since and not is_nil(e.opened_at),
        select: count(e.id)
      )
      |> BlocksterV2.Repo.one() || 0

    # Active users (users with events)
    active_users =
      from(e in BlocksterV2.Notifications.UserEvent,
        where: e.inserted_at >= ^since,
        select: count(e.user_id, :distinct)
      )
      |> BlocksterV2.Repo.one() || 0

    # Event summary
    event_counts =
      from(e in BlocksterV2.Notifications.UserEvent,
        where: e.inserted_at >= ^since,
        group_by: e.event_type,
        select: {e.event_type, count(e.id)}
      )
      |> BlocksterV2.Repo.all()
      |> Map.new()

    open_rate = if emails_sent > 0, do: Float.round(emails_opened / emails_sent * 100, 1), else: 0.0

    %{
      period: period,
      notifications_sent: notifications_sent,
      emails_sent: emails_sent,
      emails_opened: emails_opened,
      email_open_rate: open_rate,
      active_users: active_users,
      event_counts: event_counts
    }
  rescue
    e ->
      Logger.warning("[AIManager] Stats query error: #{inspect(e)}")
      %{period: period, error: "Failed to gather stats"}
  end

  defp log_review(type, input, output, tool_results) do
    import Ecto.Query
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    changes_made =
      tool_results
      |> Enum.filter(fn r -> r[:result] && r[:result][:status] == "ok" end)
      |> Enum.map(fn r -> %{tool: r[:tool], input: r[:input]} end)

    BlocksterV2.Repo.insert_all("ai_manager_logs", [
      %{
        review_type: type,
        input_summary: String.slice(input, 0..500),
        output_summary: String.slice(output, 0..500),
        changes_made: changes_made,
        inserted_at: now
      }
    ])
  rescue
    e -> Logger.warning("[AIManager] Failed to log review: #{inspect(e)}")
  end
end
