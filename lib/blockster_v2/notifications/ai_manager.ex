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

  ## Your Capabilities
  - Adjust referral rewards (BUX amounts for signups, phone verification)
  - Modify trigger thresholds (BUX milestones, reading streaks, cart abandonment timing)
  - Enable/disable notification triggers
  - Create and send email campaigns with custom copy
  - Analyze system performance and user engagement
  - Add custom event→notification rules with your own crafted copy
  - View user profiles and referral stats
  - Look up all existing notification templates and craft new messages

  ## Platform Context
  Users earn BUX tokens by reading articles, sharing on X, and referrals. They can play BUX Booster (coin flip game with BUX or ROGUE tokens) and shop with BUX/ROGUE. ROGUE is the native gas token of Rogue Chain.

  ## Notification Triggers & Their Current Copy
  The TriggerEngine fires these automatically based on user events:

  1. **BUX Milestone** (events: bux_earned when balance crosses 1K/5K/10K/25K/50K/100K)
     - Title: "You hit {N} BUX!"
     - Body: "Your BUX balance just hit {N}! Current balance: {bal}"

  2. **Reading Streak** (event: article_read_complete, streaks of 3/7/14/30 days)
     - Title: "{N}-day reading streak!"
     - Body: "You've read articles {N} days in a row. Keep it up!"

  3. **Hub Recommendation** (event: article_read_complete, 3+ reads in same category)
     - Title: "Hubs you might like"
     - Body: "Based on your reading: {hub names}"

  4. **Dormancy Warning** (event: daily_login after 5-14 days away)
     - Title: "Welcome back! {N} days is too long"
     - Body: "You missed {N} days of content. Here's what's new."

  5. **Referral Opportunity** (events: article_share or bux_earned, users with referrals or shares)
     - Title: "Share Blockster, earn BUX"
     - Body: "Share your referral link — earn 500 BUX for each friend who joins."

  ## Email Templates
  - **Daily Digest**: Personalized by engagement tier (new/casual/active/power/whale/dormant/churned)
  - **Welcome Series**: Day 0 "Welcome!", Day 3 "You're earning BUX by reading", Day 5 "Discover your hubs", Day 7 "Invite friends, earn together"
  - **Re-engagement**: "You have unread articles" → "Your BUX are waiting" → "We miss you!" → "Special welcome back offer"
  - **Referral Prompt**: Personalized by whether user has converted referrals, earned BUX, or made purchases
  - **Weekly Reward Summary**: "Great week!" for earners, "Start earning" for inactive

  ## Enriched Game Event Metadata
  When a `game_played` event fires, the metadata is automatically enriched with cumulative player stats:

  **Counts:**
  - `total_bets` — combined BUX + ROGUE total bets
  - `bux_total_bets`, `rogue_total_bets` — per-token bet counts
  - `bux_wins`, `bux_losses` — BUX game outcomes
  - `rogue_wins`, `rogue_losses` — ROGUE game outcomes

  **Amounts (human-readable, not wei):**
  - `bux_total_wagered`, `rogue_total_wagered` — total amount bet per token
  - `bux_total_winnings`, `rogue_total_winnings` — total payouts received
  - `bux_total_losses`, `rogue_total_losses` — total amount lost
  - `bux_net_pnl`, `rogue_net_pnl` — net profit/loss (negative = losing)

  **Rates & Timing:**
  - `bux_win_rate`, `rogue_win_rate` — win percentage (0-100)
  - `first_bet_at`, `last_bet_at` — unix millisecond timestamps

  ## Betting Stats Tool
  Use `get_betting_stats` to query platform-wide or per-player betting data at any time:
  - `scope: "global"` — house profit, volume, payouts, player count, house balances
  - `scope: "player"` — full per-user stats with amounts, win rates, P&L
  - `scope: "top_players"` — leaderboard sorted by bets, wagered, or P&L

  Custom rules support comparison operators in conditions:
  - Exact match: `{"token": "BUX"}` — metadata["token"] == "BUX"
  - `{"$gte": 50}` — greater than or equal
  - `{"$lte": 10}` — less than or equal
  - `{"$gt": 100}` — greater than
  - `{"$lt": 5}` — less than

  Example rules:
  - "Notify users who place 50+ bets": event_type="game_played", conditions={"total_bets": {"$gte": 50}}
  - "Notify on 3+ BUX losses": event_type="game_played", conditions={"token": "BUX", "bux_losses": {"$gte": 3}}
  - "Notify big BUX wagerers (>10K BUX wagered)": event_type="game_played", conditions={"bux_total_wagered": {"$gte": 10000}}
  - "Notify losing ROGUE players (negative P&L)": event_type="game_played", conditions={"rogue_net_pnl": {"$lt": 0}}

  ## ROGUE Deposit/Withdrawal Events
  When a ROGUE transfer is confirmed (deposit or withdrawal via member page), events fire with:
  - `rogue_deposited`: metadata has `amount` (this deposit), `net_deposits` (cumulative deposits minus withdrawals), `tx_hash`
  - `rogue_withdrawn`: metadata has `amount` (this withdrawal), `net_deposits` (cumulative deposits minus withdrawals), `tx_hash`

  Use `net_deposits` (not `amount`) for reward rules to prevent gaming via withdraw+redeposit:
  - "Reward 5000 BUX for 100K+ net ROGUE deposited": event_type="rogue_deposited", conditions={"net_deposits": {"$gte": 100000}}, bux_bonus=5000
  - "Reward at 500K net deposits": event_type="rogue_deposited", conditions={"net_deposits": {"$gte": 500000}}, bux_bonus=25000

  `net_deposits` = sum(all confirmed deposits) - sum(all confirmed withdrawals). A user who deposits 100K, withdraws it, and redeposits has net_deposits=100K (not 200K). The dedup system ensures each threshold fires only once per user.

  ## Telegram Events
  - `telegram_connected`: fires when user links their Telegram account via the bot
  - `telegram_group_joined`: fires when a connected user joins the Blockster Telegram group

  **IMPORTANT Telegram URLs** — use these exact URLs, NEVER guess or make up Telegram links:
  - Blockster Telegram Group: https://t.me/+7bIzOyrYBEc3OTdh
  - Blockster V2 Bot: https://t.me/BlocksterV2Bot
  - t.me/blockster is NOT ours — never use it

  ## Other Trackable Events
  - `signup`: fires once on account creation, metadata has `method` ("email" or "wallet")
  - `profile_updated`: fires on username change, metadata has `field` ("username")
  - `phone_verified`: fires when user completes phone verification
  - `x_connected`: fires on first X account connection, metadata has `x_user_id`
  - `wallet_connected`: fires when external wallet connected, metadata has `provider`, `address`

  Rules with numeric thresholds are automatically deduplicated — each user only receives the notification once per rule.

  ## Campaign Safety
  CRITICAL: Campaigns are ALWAYS created as drafts. You cannot send campaigns directly. An admin must review the campaign content, audience, and subject line before manually approving it for sending. Always set send_now to false.

  ## Campaign Targeting
  Available audiences: all, hub_followers, active_users, dormant_users, phone_verified, not_phone_verified, x_connected, not_x_connected, has_external_wallet, no_external_wallet, wallet_provider, multiplier, custom, bux_gamers, rogue_gamers, bux_balance, rogue_holders.
  For custom targeting, provide `user_ids` or `user_emails` in the create_campaign tool.
  For bux_balance and rogue_holders audiences, use `balance_operator` ("above" or "below") and `balance_threshold` (number) to filter by balance amount.
  For wallet_provider audience, use `wallet_provider` to specify the provider (metamask, phantom, coinbase, walletconnect).
  For multiplier audience, use `balance_operator` ("above" or "below") and `balance_threshold` (number) to filter by overall multiplier value.

  ## Conversion Funnel Stages
  nil → earner (reads articles) → bux_player (plays games) → rogue_curious (whale gambler) → rogue_buyer (made purchase)

  ## SMS Templates
  - Flash sale, BUX milestone, order shipped, account security, exclusive drop, special offer

  ## Site URLs for CTAs
  CRITICAL: NEVER invent URLs. Only use these exact paths. The production domain is https://blockster.com.
  All action_url values MUST use relative paths (starting with /) — the system prepends the domain automatically.

  | Page | Path |
  |------|------|
  | Home / Articles | `/` |
  | Single Article | `/:slug` (e.g. `/bitcoin-etf-update`) |
  | Hub | `/hubs/:slug` |
  | Shop | `/shop` |
  | Product | `/shop/:slug` |
  | BUX Booster Game | `/play` |
  | Member Profile | `/members/:id` |
  | Notifications | `/notifications` |
  | Notification Settings | `/notifications/settings` |
  | Referrals | `/referrals` |
  | Onboarding | `/onboarding` |

  There is NO `/wallet` page. BUX balances are shown on the member profile (`/members/:id`) and in the navbar.
  The production domain is `https://blockster.com`.

  **External links** (use full URLs for these):
  | Resource | URL |
  |----------|-----|
  | Telegram Group | `https://t.me/+7bIzOyrYBEc3OTdh` |
  | Telegram Bot | `https://t.me/BlocksterV2Bot` |

  NEVER guess or fabricate URLs. If you're unsure about a URL, omit the action_url entirely rather than making one up.

  ## Guidelines
  - Be decisive but conservative — don't make changes >20% without confirmation
  - Always explain what you're doing and why
  - When analyzing data, be specific with numbers
  - When asked about notifications for specific scenarios, CRAFT appropriate messages using your knowledge of the templates above
  - Use the get_notification_templates tool to see exact current copy for any trigger type
  - You CAN and SHOULD suggest/create contextual notification copy — that's a core part of your job
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
            "description" => "Map of config keys to new values. Keys: referrer_signup_bux, referee_signup_bux, phone_verify_bux, bux_milestones, reading_streak_days, bux_balance_gaming_nudge, articles_before_nudge, games_before_rogue_nudge, default_max_emails_per_day, trigger_*_enabled, etc."
          }
        },
        "required" => ["changes"]
      }
    },
    %{
      "name" => "create_campaign",
      "description" => "Create a notification campaign as a DRAFT for admin review. Campaigns are NEVER sent automatically — an admin must review and approve sending from the campaign admin page. For custom targeting, provide user_ids or user_emails.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "Campaign name"},
          "subject" => %{"type" => "string", "description" => "Email subject line"},
          "body" => %{"type" => "string", "description" => "Email body (plain text or HTML). HTML tags will render properly in the email."},
          "campaign_type" => %{"type" => "string", "description" => "Campaign type", "enum" => ["email_blast", "push_notification", "sms_blast", "multi_channel"]},
          "target_audience" => %{"type" => "string", "description" => "Target audience", "enum" => ["all", "hub_followers", "active_users", "dormant_users", "phone_verified", "not_phone_verified", "x_connected", "not_x_connected", "has_external_wallet", "no_external_wallet", "wallet_provider", "multiplier", "custom", "bux_gamers", "rogue_gamers", "bux_balance", "rogue_holders"]},
          "user_ids" => %{"type" => "array", "items" => %{"type" => "integer"}, "description" => "List of user IDs for custom targeting. Sets target_audience to 'custom' automatically."},
          "user_emails" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "List of user emails for custom targeting. Resolved to IDs. Sets target_audience to 'custom'."},
          "action_url" => %{"type" => "string", "description" => "CTA link URL (optional)"},
          "action_label" => %{"type" => "string", "description" => "CTA button text (optional)"},
          "balance_operator" => %{"type" => "string", "description" => "For bux_balance, rogue_holders, or multiplier audience: 'above' or 'below'", "enum" => ["above", "below"]},
          "balance_threshold" => %{"type" => "number", "description" => "For bux_balance, rogue_holders, or multiplier audience: threshold amount"},
          "wallet_provider" => %{"type" => "string", "description" => "For wallet_provider audience: the wallet provider to filter by", "enum" => ["metamask", "phantom", "coinbase", "walletconnect"]},
          "send_now" => %{"type" => "boolean", "description" => "ALWAYS set to false. Campaigns must be reviewed by admin before sending."}
        },
        "required" => ["name", "subject", "body"]
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
      "name" => "lookup_user",
      "description" => "Look up a user by email, wallet address, smart wallet address, username/slug, or user ID. Returns comprehensive data: account info, token balances (BUX/ROGUE), notification profile, notification preferences, referral stats, and recent events.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "user_id" => %{"type" => "integer", "description" => "User ID (if known)"},
          "email" => %{"type" => "string", "description" => "User email address"},
          "wallet_address" => %{"type" => "string", "description" => "EOA wallet address (0x...)"},
          "smart_wallet_address" => %{"type" => "string", "description" => "ERC-4337 smart wallet address (0x...)"},
          "username" => %{"type" => "string", "description" => "Username or slug"}
        },
        "required" => []
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
            "enum" => ["bux_milestone", "reading_streak", "hub_recommendation", "dormancy", "referral_opportunity"]
          },
          "enabled" => %{"type" => "boolean", "description" => "Enable or disable the trigger"},
          "threshold" => %{"description" => "New threshold value (type depends on trigger)"}
        },
        "required" => ["trigger_name"]
      }
    },
    %{
      "name" => "add_custom_rule",
      "description" => """
      Add a custom event→notification rule. Evaluated by EventProcessor when matching events occur.
      Rules with numeric thresholds are automatically deduplicated — each user only receives the notification once.

      **Channel options:**
      - "in_app" (default) — in-app notification only
      - "email" — send email only
      - "telegram" — send Telegram DM only (user must have connected their Telegram)
      - "both" — in-app notification AND email
      - "all" — in-app + email + Telegram DM

      **BUX/ROGUE bonuses:**
      - Set bux_bonus to auto-mint BUX to the user's wallet when the rule fires
      - Set rogue_bonus to auto-send ROGUE to the user's wallet when the rule fires

      For game_played events, metadata is enriched with cumulative stats:
      Counts: total_bets, bux_total_bets, rogue_total_bets, bux_wins, bux_losses, rogue_wins, rogue_losses
      Amounts: bux_total_wagered, bux_total_winnings, bux_total_losses, bux_net_pnl, rogue_total_wagered, rogue_total_winnings, rogue_total_losses, rogue_net_pnl
      Rates: bux_win_rate, rogue_win_rate (0-100%)
      Timing: first_bet_at, last_bet_at (unix ms)

      Conditions support comparison operators:
      - Exact match: {"token": "BUX"}
      - Greater/equal: {"total_bets": {"$gte": 50}}
      - Less/equal: {"bux_losses": {"$lte": 3}}
      - Greater than: {"bux_total_wagered": {"$gt": 10000}}
      - Less than: {"rogue_net_pnl": {"$lt": 0}}

      For rogue_deposited/rogue_withdrawn events, metadata includes:
      - amount: this transfer's amount
      - net_deposits: cumulative deposits minus withdrawals (use this for rewards to prevent gaming)
      - tx_hash: on-chain transaction hash

      Other event types with metadata: signup (method), profile_updated (field), phone_verified, x_connected (x_user_id), wallet_connected (provider, address).

      Examples:
      - Email on 1000+ BUX profit: channel="email", conditions={"bux_net_pnl": {"$gte": 1000}}
      - Console losers with 200 BUX bonus: channel="both", conditions={"bux_net_pnl": {"$lt": -1000}}, bux_bonus=200
      - Reward 50+ games with ROGUE: channel="both", conditions={"total_bets": {"$gte": 50}}, rogue_bonus=0.5
      - Reward 100K+ net ROGUE deposited with 5000 BUX: event_type="rogue_deposited", conditions={"net_deposits": {"$gte": 100000}}, bux_bonus=5000
      """,
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "event_type" => %{"type" => "string", "description" => "Event type to match (e.g., 'article_read_complete', 'game_played')"},
          "conditions" => %{"type" => "object", "description" => "Conditions to match on event metadata. Supports exact match or comparison operators ($gte, $lte, $gt, $lt)."},
          "title" => %{"type" => "string", "description" => "Notification title"},
          "body" => %{"type" => "string", "description" => "Notification body"},
          "notification_type" => %{"type" => "string", "description" => "Notification type (default: special_offer)"},
          "channel" => %{"type" => "string", "description" => "Delivery channel: 'in_app' (default), 'email', 'telegram' (DM), 'both' (in_app+email), or 'all' (in_app+email+telegram)", "enum" => ["in_app", "email", "telegram", "both", "all"]},
          "subject" => %{"type" => "string", "description" => "Email subject line (defaults to title if not provided)"},
          "action_url" => %{"type" => "string", "description" => "CTA link URL for notifications and emails"},
          "action_label" => %{"type" => "string", "description" => "CTA button text"},
          "bux_bonus" => %{"type" => "integer", "description" => "BUX to auto-mint to the user's wallet when rule fires"},
          "rogue_bonus" => %{"type" => "number", "description" => "ROGUE to auto-send to the user's wallet when rule fires (e.g. 0.5)"}
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
    },
    %{
      "name" => "get_notification_templates",
      "description" => "Get all notification copy/templates for a specific trigger type or all triggers. Shows the exact title and body text used for each notification type, email subjects, CTA text, and SMS messages.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "trigger_type" => %{
            "type" => "string",
            "description" => "Specific trigger to get templates for, or 'all' for everything",
            "enum" => ["bux_milestone", "reading_streak", "hub_recommendation", "dormancy", "referral", "welcome_series", "re_engagement", "daily_digest", "reward_summary", "sms", "conversion_funnel", "all"]
          }
        },
        "required" => []
      }
    },
    %{
      "name" => "get_betting_stats",
      "description" => "Get BUX Booster betting statistics. Can fetch global platform stats (house profit, volume, player count) or individual player stats by user_id or wallet address. All token amounts are in human-readable format (not wei).",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "scope" => %{
            "type" => "string",
            "description" => "What stats to fetch",
            "enum" => ["global", "player", "top_players"]
          },
          "user_id" => %{"type" => "integer", "description" => "User ID (for player scope)"},
          "wallet_address" => %{"type" => "string", "description" => "Wallet address (for player scope)"},
          "sort_by" => %{
            "type" => "string",
            "description" => "Sort field for top_players (default: total_bets)",
            "enum" => ["total_bets", "bux_wagered", "bux_pnl", "rogue_wagered", "rogue_pnl"]
          },
          "limit" => %{"type" => "integer", "description" => "Number of top players to return (default: 10, max: 50)"}
        },
        "required" => ["scope"]
      }
    },
    %{
      "name" => "craft_notification",
      "description" => "Craft and send a contextual notification to a user based on their situation. Use this when you want to send a personalized message (e.g., consolation after losses, congratulations on wins, encouragement to try something new). You write the title and body copy.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "user_id" => %{"type" => "integer", "description" => "User ID to notify"},
          "title" => %{"type" => "string", "description" => "Notification title — make it personal and contextual"},
          "body" => %{"type" => "string", "description" => "Notification body — empathetic, helpful, not salesy"},
          "notification_type" => %{
            "type" => "string",
            "description" => "Type of notification",
            "enum" => ["content_recommendation", "special_offer", "bux_milestone", "referral_prompt", "welcome", "welcome_back", "re_engagement", "daily_bonus", "game_settlement"]
          },
          "category" => %{
            "type" => "string",
            "description" => "Notification category",
            "enum" => ["content", "offers", "social", "rewards", "system"]
          }
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
    case api_call_with_retry(messages, api_key) do
      {:ok, %{status: 200, body: %{"content" => content, "stop_reason" => stop_reason}}} ->
        if stop_reason == "tool_use" do
          {tool_use_blocks, _text_blocks} = partition_content(content)

          # Execute each tool once, build both the API response and our accumulator
          executed =
            Enum.map(tool_use_blocks, fn block ->
              result = execute_tool(block["name"], block["input"], admin_user_id)
              {block, result}
            end)

          tool_results =
            Enum.map(executed, fn {block, result} ->
              %{
                "type" => "tool_result",
                "tool_use_id" => block["id"],
                "content" => Jason.encode!(result)
              }
            end)

          new_tool_results_acc =
            tool_results_acc ++
              Enum.map(executed, fn {block, result} ->
                %{tool: block["name"], input: block["input"], result: result}
              end)

          new_messages =
            messages ++
              [%{"role" => "assistant", "content" => content}] ++
              [%{"role" => "user", "content" => tool_results}]

          run_conversation(new_messages, api_key, admin_user_id, new_tool_results_acc, round + 1)
        else
          text = extract_text(content)
          {:ok, text, tool_results_acc}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("[AIManager] API returned #{status}: #{inspect(body)}")
        {:error, "Claude API returned #{status}"}

      {:error, reason} ->
        Logger.error("[AIManager] Request failed after retries: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp api_call_with_retry(messages, api_key, attempt \\ 1) do
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
      {:ok, %{status: 429}} when attempt <= 3 ->
        Process.sleep(attempt * 3_000)
        api_call_with_retry(messages, api_key, attempt + 1)

      {:ok, %{status: 529}} when attempt <= 3 ->
        Process.sleep(attempt * 5_000)
        api_call_with_retry(messages, api_key, attempt + 1)

      {:error, %Req.TransportError{}} when attempt <= 3 ->
        Logger.warning("[AIManager] Transport error on attempt #{attempt}, retrying...")
        Process.sleep(attempt * 2_000)
        api_call_with_retry(messages, api_key, attempt + 1)

      result ->
        result
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
        |> Map.merge(Map.take(config, ["bux_milestones", "reading_streak_days",
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
    # Resolve user targeting
    {target_audience, target_criteria} = resolve_campaign_targeting(input)

    # SAFETY: Always create as draft — admin must review and send manually
    attrs = %{
      name: input["name"],
      type: input["campaign_type"] || "email_blast",
      subject: input["subject"],
      body: input["body"],
      plain_text_body: input["body"],
      target_audience: target_audience,
      target_criteria: target_criteria,
      action_url: input["action_url"],
      action_label: input["action_label"],
      status: "draft"
    }

    case BlocksterV2.Notifications.create_campaign(attrs) do
      {:ok, campaign} ->
        %{status: "ok", campaign_id: campaign.id, name: campaign.name, message: "Campaign created as draft. An admin must review and send it from /admin/notifications/campaigns/#{campaign.id}"}

      {:error, changeset} ->
        %{status: "error", errors: inspect(changeset.errors)}
    end
  end

  defp execute_tool("get_system_stats", input, _admin) do
    period = input["period"] || "24h"
    gather_system_stats(period)
  end

  defp execute_tool("lookup_user", input, _admin) do
    user = resolve_user(input)

    if user do
      build_user_report(user)
    else
      %{status: "not_found", message: "No user found matching the provided criteria"}
    end
  end

  # Keep backwards compat for old tool name
  defp execute_tool("get_user_profile", %{"user_id" => user_id}, admin) do
    execute_tool("lookup_user", %{"user_id" => user_id}, admin)
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

  # HARD GATE: AI cannot create/modify/delete custom rules autonomously.
  # These tools only propose changes — the admin must use the Rules Admin page to apply them.
  defp execute_tool("add_custom_rule", input, _admin) do
    rule =
      %{
        "event_type" => input["event_type"],
        "conditions" => input["conditions"],
        "action" => "notification",
        "title" => input["title"],
        "body" => input["body"],
        "notification_type" => input["notification_type"] || "special_offer",
        "channel" => input["channel"] || "in_app",
        "subject" => input["subject"],
        "action_url" => input["action_url"],
        "action_label" => input["action_label"],
        "bux_bonus" => input["bux_bonus"],
        "rogue_bonus" => input["rogue_bonus"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    %{
      status: "requires_admin_action",
      message: "Custom rules cannot be created automatically. The rule has been drafted below for the admin to review. To apply it, go to /admin/notifications/rules and create it manually.",
      proposed_rule: rule
    }
  end

  defp execute_tool("remove_custom_rule", %{"rule_index" => index}, _admin) do
    rules = SystemConfig.get("custom_rules", [])

    if index >= 0 and index < length(rules) do
      %{
        status: "requires_admin_action",
        message: "Custom rules cannot be deleted automatically. To remove this rule, go to /admin/notifications/rules and delete it manually.",
        rule_to_remove: Enum.at(rules, index),
        rule_index: index
      }
    else
      %{status: "error", message: "Invalid rule index. Current rules: #{length(rules)}"}
    end
  end

  defp execute_tool("list_campaigns", input, _admin) do
    limit = input["limit"] || 10

    campaigns =
      BlocksterV2.Notifications.list_campaigns(limit: limit)
      |> Enum.map(fn c ->
        %{id: c.id, name: c.name, status: c.status, audience: c.target_audience, inserted_at: c.inserted_at}
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

  defp execute_tool("get_notification_templates", input, _admin) do
    trigger_type = input["trigger_type"] || "all"
    get_templates(trigger_type)
  end

  defp execute_tool("get_betting_stats", %{"scope" => "global"}, _admin) do
    alias BlocksterV2.BuxBoosterStats

    bux_stats = try_get({:ok, %{}}, fn -> BuxBoosterStats.get_bux_global_stats() end)
    rogue_stats = try_get({:ok, %{}}, fn -> BuxBoosterStats.get_rogue_global_stats() end)
    house = try_get({:ok, %{bux: 0, rogue: 0}}, fn -> BuxBoosterStats.get_house_balances() end)
    player_count = try_get(0, fn -> BuxBoosterStats.get_player_count() end)
    total_users = try_get(0, fn -> BuxBoosterStats.get_total_user_count() end)

    %{
      bux: format_global_stats(bux_stats, "BUX"),
      rogue: format_global_stats(rogue_stats, "ROGUE"),
      house_balances: %{
        bux: wei_to_float(house[:bux] || house.bux),
        rogue: wei_to_float(house[:rogue] || house.rogue)
      },
      player_count: player_count,
      total_users_with_accounts: total_users
    }
  end

  defp execute_tool("get_betting_stats", %{"scope" => "player"} = input, _admin) do
    alias BlocksterV2.BuxBoosterStats

    result =
      cond do
        input["user_id"] -> BuxBoosterStats.get_user_stats(input["user_id"])
        input["wallet_address"] -> BuxBoosterStats.get_user_stats_by_wallet(input["wallet_address"])
        true -> {:error, :missing_identifier}
      end

    case result do
      {:ok, stats} -> format_player_stats(stats)
      {:error, :not_found} -> %{status: "not_found", message: "No betting stats found for this user"}
      {:error, _} -> %{status: "error", message: "Provide user_id or wallet_address"}
    end
  end

  defp execute_tool("get_betting_stats", %{"scope" => "top_players"} = input, _admin) do
    alias BlocksterV2.BuxBoosterStats

    sort_by = String.to_existing_atom(input["sort_by"] || "total_bets")
    limit = min(input["limit"] || 10, 50)

    case BuxBoosterStats.get_all_player_stats(page: 1, per_page: limit, sort_by: sort_by, sort_order: :desc) do
      {:ok, %{players: players, total_count: total}} ->
        %{
          top_players: Enum.map(players, &format_player_stats/1),
          total_players: total,
          sorted_by: sort_by
        }

      _ ->
        %{status: "error", message: "Failed to fetch player stats"}
    end
  rescue
    _ -> %{status: "error", message: "Invalid sort_by field"}
  end

  defp execute_tool("craft_notification", input, _admin) do
    type = input["notification_type"] || "special_offer"
    category = input["category"] || notification_category_for(type)

    case BlocksterV2.Notifications.create_notification(input["user_id"], %{
      type: type,
      category: category,
      title: input["title"],
      body: input["body"]
    }) do
      {:ok, notif} ->
        %{status: "ok", notification_id: notif.id, title: notif.title, body: notif.body, type: type}

      {:error, changeset} ->
        %{status: "error", errors: inspect(changeset.errors)}
    end
  end

  defp execute_tool(name, _input, _admin) do
    %{status: "error", message: "Unknown tool: #{name}"}
  end

  # ============ User Lookup ============

  defp resolve_user(input) do
    alias BlocksterV2.Accounts

    cond do
      input["user_id"] ->
        BlocksterV2.Repo.get(Accounts.User, input["user_id"])

      input["email"] ->
        Accounts.get_user_by_email(input["email"])

      input["smart_wallet_address"] ->
        Accounts.get_user_by_smart_wallet_address(input["smart_wallet_address"])

      input["wallet_address"] ->
        Accounts.get_user_by_wallet(input["wallet_address"])

      input["username"] ->
        Accounts.get_user_by_slug(input["username"])

      true ->
        nil
    end
  end

  defp build_user_report(user) do
    prefs = BlocksterV2.Notifications.get_preferences(user.id)

    # Token balances from Mnesia
    balances =
      try do
        BlocksterV2.EngagementTracker.get_user_token_balances(user.id)
      rescue
        _ -> %{"BUX" => 0.0, "ROGUE" => 0.0}
      catch
        :exit, _ -> %{"BUX" => 0.0, "ROGUE" => 0.0}
      end

    # Betting stats from Mnesia
    betting_stats =
      try do
        case BlocksterV2.BuxBoosterStats.get_user_stats(user.id) do
          {:ok, stats} -> format_player_stats(stats)
          _ -> nil
        end
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end

    # Referral stats from Mnesia
    referral_stats =
      try do
        BlocksterV2.Referrals.get_referrer_stats(user.id)
      rescue
        _ -> %{total_referrals: 0, verified_referrals: 0, total_bux_earned: 0.0, total_rogue_earned: 0.0}
      catch
        :exit, _ -> %{total_referrals: 0, verified_referrals: 0, total_bux_earned: 0.0, total_rogue_earned: 0.0}
      end

    # Recent events
    recent_events =
      try do
        BlocksterV2.UserEvents.get_events(user.id, limit: 20)
        |> Enum.map(fn e ->
          %{type: e.event_type, category: e.event_category, metadata: e.metadata, at: e.inserted_at}
        end)
      rescue
        _ -> []
      end

    # Recent notifications
    recent_notifications =
      try do
        import Ecto.Query
        from(n in BlocksterV2.Notifications.Notification,
          where: n.user_id == ^user.id,
          order_by: [desc: n.inserted_at],
          limit: 10,
          select: %{type: n.type, title: n.title, read: n.read, at: n.inserted_at}
        )
        |> BlocksterV2.Repo.all()
      rescue
        _ -> []
      end

    %{
      account: %{
        id: user.id,
        email: user.email,
        username: user.username,
        slug: user.slug,
        wallet_address: user.wallet_address,
        smart_wallet_address: user.smart_wallet_address,
        auth_method: user.auth_method,
        is_admin: user.is_admin,
        is_author: user.is_author,
        phone_verified: user.phone_verified,
        geo_tier: user.geo_tier,
        level: user.level,
        experience_points: user.experience_points,
        created_at: user.inserted_at
      },
      balances: balances,
      betting_stats: betting_stats,
      referral_stats: referral_stats,
      notification_preferences: prefs && Map.from_struct(prefs) |> Map.drop([:__meta__, :user]),
      recent_events: recent_events,
      recent_notifications: recent_notifications
    }
  end

  defp notification_category_for("content_recommendation"), do: "content"
  defp notification_category_for("special_offer"), do: "offers"
  defp notification_category_for("bux_milestone"), do: "rewards"
  defp notification_category_for("referral_prompt"), do: "social"
  defp notification_category_for("game_settlement"), do: "rewards"
  defp notification_category_for("daily_bonus"), do: "rewards"
  defp notification_category_for(_), do: "system"

  # ============ Template Data ============

  defp get_templates("all") do
    %{
      triggers: %{
        bux_milestone: get_templates("bux_milestone"),
        reading_streak: get_templates("reading_streak"),
        hub_recommendation: get_templates("hub_recommendation"),
        dormancy: get_templates("dormancy"),
        referral: get_templates("referral")
      },
      emails: %{
        welcome_series: get_templates("welcome_series"),
        re_engagement: get_templates("re_engagement"),
        daily_digest: get_templates("daily_digest"),
        reward_summary: get_templates("reward_summary")
      },
      sms: get_templates("sms"),
      conversion_funnel: get_templates("conversion_funnel")
    }
  end

  defp get_templates("bux_milestone") do
    %{
      milestones: [1_000, 5_000, 10_000, 25_000, 50_000, 100_000],
      in_app: %{title: "You hit {milestone} BUX!", body: "Your BUX balance just hit {milestone}! Current balance: {bal}"},
      note: "Only fires once per milestone per user"
    }
  end

  defp get_templates("reading_streak") do
    %{
      streak_days: [3, 7, 14, 30],
      in_app: %{title: "{N}-day reading streak!", body: "You've read articles {N} days in a row. Keep it up!"},
      note: "Only fires once per streak milestone per user"
    }
  end

  defp get_templates("hub_recommendation") do
    %{
      trigger: "3+ article reads in same category within 7 days",
      in_app: %{title: "Hubs you might like", body: "Based on your reading: {hub names}"},
      note: "Only suggests hubs the user hasn't followed yet"
    }
  end

  defp get_templates("dormancy") do
    %{
      trigger: "daily_login after 5-14 days of inactivity",
      in_app: %{title: "Welcome back! {N} days is too long", body: "You missed {N} days of content. Here's what's new."}
    }
  end

  defp get_templates("referral") do
    %{
      trigger: "article_share or bux_earned for high-propensity users (>0.6)",
      in_app: %{title: "Share Blockster, earn BUX", body: "Share your referral link — earn 500 BUX for each friend who joins."},
      email_subjects_by_profile: [
        %{condition: "Has converted referrals", subject: "Your referrals are working — keep going!"},
        %{condition: "Earned >1000 BUX this month", subject: "You earned BUX this month — share the love"},
        %{condition: "Has made purchases", subject: "Give your friends a head start, get 500 BUX for yourself"},
        %{condition: "Default", subject: "Invite friends to Blockster, earn 500 BUX each"}
      ],
      cta: "Share with friends",
      note: "Max 1 referral prompt per user per week"
    }
  end

  defp get_templates("welcome_series") do
    %{
      schedule: [
        %{day: 0, subject: "Welcome to Blockster!", cta: "Get started"},
        %{day: 3, subject: "You're earning BUX by reading", cta: "Get started"},
        %{day: 5, subject: "Discover your hubs", cta: "Get started"},
        %{day: 7, subject: "Invite friends, earn together", cta: "Get started"}
      ]
    }
  end

  defp get_templates("re_engagement") do
    %{
      email_subjects_by_days_inactive: [
        %{days: "1-3", subject: "You have unread articles from your hubs"},
        %{days: "4-7", subject: "Your BUX are waiting — claim your rewards"},
        %{days: "8-14", subject: "We miss you! Here's what's new"},
        %{days: "15+", subject: "Special welcome back offer — just for you"}
      ],
      cta_by_tier: [
        %{tier: "churned", cta: "Come back to Blockster"},
        %{tier: "default", cta: "See what you missed"}
      ],
      note: "Copy must be honest — no fake '2x BUX' or 'special reward' promises"
    }
  end

  defp get_templates("daily_digest") do
    %{
      subjects_by_tier: [
        %{tier: "new", subject: "Your daily Blockster briefing is ready"},
        %{tier: "casual", subject: "{N} articles picked for you today"},
        %{tier: "active", subject: "Today's top stories from your hubs"},
        %{tier: "power", subject: "{N} hubs have new content for you"},
        %{tier: "whale", subject: "Exclusive: your personalized daily brief"},
        %{tier: "dormant", subject: "We've been saving stories for you"},
        %{tier: "churned", subject: "Here's what you've been missing"}
      ],
      cta_by_tier: [
        %{tier: "new", cta: "Start reading"},
        %{tier: "default", cta: "Read today's articles"}
      ]
    }
  end

  defp get_templates("reward_summary") do
    %{
      subjects: [
        %{condition: "Earned >500 BUX this week", subject: "Great week! Your BUX report is ready"},
        %{condition: "Earned >0 BUX", subject: "Your weekly BUX report"},
        %{condition: "Earned 0 BUX", subject: "Your BUX balance is waiting — start earning"}
      ],
      cta: "View your stats"
    }
  end

  defp get_templates("sms") do
    %{
      templates: [
        %{type: "flash_sale", message: "Flash sale on Blockster! {item} is {pct}% off for the next {hours}h. Shop now: {url}"},
        %{type: "bux_milestone", message: "You just hit {milestone} BUX on Blockster! Keep earning: {url}"},
        %{type: "order_shipped", message: "Your Blockster order #{"{order_id}"} has shipped! Track it: {url}"},
        %{type: "account_security", message: "Blockster security alert: {message}. If this wasn't you, secure your account: {url}"},
        %{type: "exclusive_drop", message: "Exclusive drop on Blockster: {item}. Limited quantities. Shop now: {url}"},
        %{type: "special_offer", message: "{message} Check it out: {url}"}
      ]
    }
  end

  defp get_templates("conversion_funnel") do
    %{
      stages: [
        %{stage: "earner", description: "Reads articles, earns BUX", nudge: "Gaming nudge when BUX balance > threshold"},
        %{stage: "bux_player", description: "Plays BUX Booster games", nudge: "ROGUE game nudge after N games"},
        %{stage: "rogue_curious", description: "Whale gambler tier", nudge: "Shop/purchase offers"},
        %{stage: "rogue_buyer", description: "Has made a purchase", nudge: "Loyalty and retention offers"}
      ],
      gaming_scenarios: [
        %{scenario: "Loss streak (3+ consecutive losses)", suggested_copy: "Empathetic — acknowledge the streak, suggest taking a break or trying a different bet size, never promise wins"},
        %{scenario: "Win streak", suggested_copy: "Celebratory — congratulate, suggest trying higher stakes or ROGUE games"},
        %{scenario: "Big win (>5x multiplier)", suggested_copy: "Excitement — highlight the achievement, suggest sharing or shopping with winnings"},
        %{scenario: "First game ever", suggested_copy: "Educational — explain how BUX Booster works, encourage exploration"},
        %{scenario: "Switched from BUX to ROGUE", suggested_copy: "Welcome to ROGUE gaming — explain real-value aspect"}
      ],
      note: "Use the craft_notification tool to send personalized messages for these scenarios. You write the copy — be empathetic, honest, and helpful."
    }
  end

  # ============ Campaign Targeting ============

  defp resolve_campaign_targeting(input) do
    cond do
      # Direct user IDs provided
      is_list(input["user_ids"]) && input["user_ids"] != [] ->
        {"custom", %{"user_ids" => input["user_ids"]}}

      # User emails provided — resolve to IDs
      is_list(input["user_emails"]) && input["user_emails"] != [] ->
        import Ecto.Query
        user_ids =
          from(u in BlocksterV2.Accounts.User,
            where: u.email in ^input["user_emails"],
            select: u.id
          )
          |> BlocksterV2.Repo.all()

        {"custom", %{"user_ids" => user_ids}}

      true ->
        criteria =
          %{}
          |> maybe_put("operator", input["balance_operator"])
          |> maybe_put("threshold", input["balance_threshold"])
          |> maybe_put("provider", input["wallet_provider"])

        {input["target_audience"] || "all", criteria}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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

  # ============ Betting Stats Helpers ============

  defp try_get(default, fun) do
    case fun.() do
      {:ok, result} -> result
      result when is_integer(result) -> result
      _ -> default
    end
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end

  defp wei_to_float(nil), do: 0.0
  defp wei_to_float(wei) when is_integer(wei), do: Float.round(wei / 1_000_000_000_000_000_000, 2)
  defp wei_to_float(_), do: 0.0

  defp format_global_stats(stats, token) when is_map(stats) do
    %{
      token: token,
      total_bets: stats[:total_bets] || 0,
      total_wins: stats[:total_wins] || 0,
      total_losses: stats[:total_losses] || 0,
      volume_wagered: wei_to_float(stats[:total_volume_wagered]),
      total_payouts: wei_to_float(stats[:total_payouts]),
      house_profit: wei_to_float(stats[:total_house_profit]),
      largest_bet: wei_to_float(stats[:largest_bet]),
      largest_win: wei_to_float(stats[:largest_win])
    }
  end

  defp format_global_stats(_, token), do: %{token: token, error: "unavailable"}

  defp format_player_stats(stats) when is_map(stats) do
    %{
      user_id: stats.user_id,
      wallet: stats.wallet,
      bux: %{
        total_bets: stats.bux.total_bets,
        wins: stats.bux.wins,
        losses: stats.bux.losses,
        win_rate: if(stats.bux.total_bets > 0, do: Float.round(stats.bux.wins / stats.bux.total_bets * 100, 1), else: 0.0),
        total_wagered: wei_to_float(stats.bux.total_wagered),
        total_winnings: wei_to_float(stats.bux.total_winnings),
        total_losses: wei_to_float(stats.bux.total_losses),
        net_pnl: wei_to_float(stats.bux.net_pnl)
      },
      rogue: %{
        total_bets: stats.rogue.total_bets,
        wins: stats.rogue.wins,
        losses: stats.rogue.losses,
        win_rate: if(stats.rogue.total_bets > 0, do: Float.round(stats.rogue.wins / stats.rogue.total_bets * 100, 1), else: 0.0),
        total_wagered: wei_to_float(stats.rogue.total_wagered),
        total_winnings: wei_to_float(stats.rogue.total_winnings),
        total_losses: wei_to_float(stats.rogue.total_losses),
        net_pnl: wei_to_float(stats.rogue.net_pnl)
      },
      combined: %{
        total_bets: stats.combined.total_bets,
        total_wins: stats.combined.total_wins,
        total_losses: stats.combined.total_losses
      },
      first_bet_at: stats.first_bet_at,
      last_bet_at: stats.last_bet_at
    }
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
