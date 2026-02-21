defmodule BlocksterV2.Notifications.ConversionFunnelEngine do
  @moduledoc """
  Drives users through the 5-stage BUX→ROGUE conversion funnel via strategic notifications.

  Stages:
  1. Earner → BUX Player (BUX balance triggers)
  2. BUX Player → ROGUE Discovery (after 5+ BUX games)
  3. ROGUE Curious → ROGUE Buyer (after showing ROGUE interest)
  4. ROGUE Buyer → ROGUE Regular (retention)
  5. Regular → VIP (reward loyalty)
  """

  import Ecto.Query
  alias BlocksterV2.{Repo, Notifications, UserEvents}
  alias BlocksterV2.Notifications.{RogueOfferEngine, Notification, UserProfile}

  require Logger

  @doc """
  Evaluate funnel triggers for a user event.
  Called from TriggerEngine or can be called directly.
  Returns list of fired notification types.
  """
  def evaluate_funnel_triggers(user_id, event_type, metadata \\ %{}) do
    profile = UserEvents.get_profile(user_id)
    stage = if profile, do: profile.conversion_stage || "earner", else: "earner"

    triggers =
      case stage do
        "earner" -> earner_triggers(user_id, event_type, metadata, profile)
        "bux_player" -> bux_player_triggers(user_id, event_type, metadata, profile)
        "rogue_curious" -> rogue_curious_triggers(user_id, event_type, metadata, profile)
        "rogue_buyer" -> rogue_buyer_triggers(user_id, event_type, metadata, profile)
        "rogue_regular" -> rogue_regular_triggers(user_id, event_type, metadata, profile)
        _ -> []
      end

    # Also check VIP upgrades regardless of stage
    vip_triggers = check_vip_upgrade(user_id, event_type, profile)

    all_fired = triggers ++ vip_triggers

    Enum.each(all_fired, fn {type, data} ->
      fire_funnel_notification(user_id, type, data)
    end)

    Enum.map(all_fired, fn {type, _} -> type end)
  end

  # ============ Stage 1: Earner → BUX Player ============

  defp earner_triggers(user_id, event_type, metadata, profile) do
    results = []

    # BUX balance hits 500 → suggest BUX Booster
    results =
      if event_type == "bux_earned" do
        new_balance = get_balance(metadata)

        if new_balance && Decimal.compare(new_balance, Decimal.new(500)) != :lt &&
             !already_notified_today?(user_id, "bux_booster_invite") do
          [{
            "special_offer",
            %{
              offer_type: "bux_booster_invite",
              message: "You have #{Decimal.to_integer(new_balance)} BUX — try your luck on BUX Booster!",
              bux_balance: Decimal.to_string(new_balance),
              cta: "Play BUX Booster"
            }
          } | results]
        else
          results
        end
      else
        results
      end

    # After 5th article read → nudge toward gaming
    results =
      if event_type == "article_read_complete" && profile do
        total = profile.total_articles_read || 0

        if total == 5 && !already_notified_today?(user_id, "reader_gaming_nudge") do
          [{
            "special_offer",
            %{
              offer_type: "reader_gaming_nudge",
              message: "Readers love BUX Booster — double your earnings with a flip!",
              cta: "Try BUX Booster"
            }
          } | results]
        else
          results
        end
      else
        results
      end

    results
  end

  # ============ Stage 2: BUX Player → ROGUE Discovery ============

  defp bux_player_triggers(user_id, event_type, _metadata, profile) do
    results = []

    # After 5th BUX game → suggest ROGUE
    results =
      if event_type == "game_played" && profile do
        bux_games = profile.total_bets_placed || 0

        if bux_games == 5 && !already_notified_today?(user_id, "rogue_discovery") do
          [{
            "special_offer",
            %{
              offer_type: "rogue_discovery",
              message: "Level up: play with ROGUE for bigger payouts",
              cta: "Discover ROGUE"
            }
          } | results]
        else
          results
        end
      else
        results
      end

    # After loss streak of 3+ → free ROGUE offer
    results =
      if event_type == "game_played" && profile do
        losses = profile.loss_streak || 0

        if losses >= 3 && !already_notified_today?(user_id, "rogue_loss_streak_offer") do
          [{
            "special_offer",
            %{
              offer_type: "rogue_loss_streak_offer",
              message: "Try ROGUE games — different odds, fresh start. Here's 0.5 ROGUE free",
              amount: 0.5,
              cta: "Try ROGUE Free"
            }
          } | results]
        else
          results
        end
      else
        results
      end

    results
  end

  # ============ Stage 3: ROGUE Curious → ROGUE Buyer ============

  defp rogue_curious_triggers(user_id, event_type, _metadata, profile) do
    results = []

    # After free ROGUE game → how to get more
    results =
      if event_type == "game_played" && profile && (profile.total_rogue_games || 0) == 1 do
        if !already_notified_today?(user_id, "rogue_purchase_nudge") do
          [{
            "special_offer",
            %{
              offer_type: "rogue_purchase_nudge",
              message: "Want more ROGUE? Here's how to get it",
              cta: "Buy ROGUE"
            }
          } | results]
        else
          results
        end
      else
        results
      end

    results
  end

  # ============ Stage 4: ROGUE Buyer → ROGUE Regular (Retention) ============

  defp rogue_buyer_triggers(user_id, event_type, metadata, profile) do
    results = []

    # Win streak celebration
    results =
      if event_type == "game_played" && profile do
        wins = profile.win_streak || 0

        if wins >= 3 && !already_notified_today?(user_id, "win_streak_celebration") do
          [{
            "special_offer",
            %{
              offer_type: "win_streak_celebration",
              message: "You're on fire! #{wins} wins in a row — keep it going?",
              streak: wins,
              cta: "Play Again"
            }
          } | results]
        else
          results
        end
      else
        results
      end

    # Big win celebration (>10x detected via metadata)
    results =
      if event_type == "game_played" do
        multiplier = metadata["multiplier"] || metadata[:multiplier]

        if multiplier && to_number(multiplier) >= 10 do
          amount = metadata["win_amount"] || metadata[:win_amount] || "big"

          if !already_notified_today?(user_id, "big_win_celebration") do
            [{
              "special_offer",
              %{
                offer_type: "big_win_celebration",
                message: "MASSIVE WIN! You just won #{amount} ROGUE!",
                multiplier: multiplier,
                cta: "Share Your Win"
              }
            } | results]
          else
            results
          end
        else
          results
        end
      else
        results
      end

    results
  end

  # ============ Stage 5: ROGUE Regular → VIP ============

  defp rogue_regular_triggers(_user_id, _event_type, _metadata, _profile) do
    # VIP triggers handled by check_vip_upgrade/3
    []
  end

  # ============ VIP Tier Checks ============

  defp check_vip_upgrade(user_id, event_type, profile) do
    if event_type == "game_played" && profile do
      current_vip = profile.vip_tier || "none"
      new_vip = RogueOfferEngine.classify_vip_tier(profile)

      if vip_rank(new_vip) > vip_rank(current_vip) do
        # Update the profile
        UserEvents.upsert_profile(user_id, %{
          vip_tier: new_vip,
          vip_unlocked_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        [{
          "bux_milestone",
          %{
            type: "vip_upgrade",
            tier: new_vip,
            message: vip_upgrade_message(new_vip)
          }
        }]
      else
        []
      end
    else
      []
    end
  end

  defp vip_rank("none"), do: 0
  defp vip_rank("bronze"), do: 1
  defp vip_rank("silver"), do: 2
  defp vip_rank("gold"), do: 3
  defp vip_rank("diamond"), do: 4
  defp vip_rank(_), do: 0

  defp vip_upgrade_message("bronze"), do: "You unlocked Bronze! 5% cashback on losses this week"
  defp vip_upgrade_message("silver"), do: "Silver unlocked! Free ROGUE airdrop every Monday"
  defp vip_upgrade_message("gold"), do: "Gold status! Exclusive high-stakes games + priority support"
  defp vip_upgrade_message("diamond"), do: "Diamond VIP! Personal offers, early access, 1-on-1 support"
  defp vip_upgrade_message(_), do: "Congratulations on your new VIP tier!"

  # ============ Notification Helpers ============

  defp fire_funnel_notification(user_id, type, data) do
    attrs = %{
      type: type,
      category: "offers",
      title: data[:message] || data["message"] || "Special offer",
      body: data[:cta] || data["cta"] || "",
      metadata: data
    }

    case Notifications.create_notification(user_id, attrs) do
      {:ok, _} ->
        Logger.info("ConversionFunnel fired #{type} (#{data[:offer_type]}) for user #{user_id}")
        :ok

      {:error, reason} ->
        Logger.warning("ConversionFunnel failed for user #{user_id}: #{inspect(reason)}")
        :error
    end
  end

  defp already_notified_today?(user_id, offer_type) do
    today_start =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.to_date()
      |> NaiveDateTime.new!(~T[00:00:00])

    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.inserted_at >= ^today_start,
      where: fragment("?->>'offer_type' = ?", n.metadata, ^offer_type)
    )
    |> Repo.exists?()
  end

  defp get_balance(metadata) do
    val = metadata["new_balance"] || metadata[:new_balance]

    case val do
      nil -> nil
      %Decimal{} = d -> d
      v when is_number(v) -> Decimal.new(v)
      v when is_binary(v) ->
        case Decimal.parse(v) do
          {d, _} -> d
          :error -> nil
        end
      _ -> nil
    end
  end

  defp to_number(v) when is_number(v), do: v
  defp to_number(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0
    end
  end
  defp to_number(_), do: 0
end
