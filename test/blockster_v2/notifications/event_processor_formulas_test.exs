defmodule BlocksterV2.Notifications.EventProcessorFormulasTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Notifications
  alias BlocksterV2.Notifications.{SystemConfig, EventProcessor}

  # ============ Test Helpers ============

  defp create_user(_context \\ %{}) do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    %{user: user}
  end

  defp setup_mnesia(_context \\ %{}) do
    # Ensure Mnesia tables exist for balance lookups and game stats
    # Schemas must match real mnesia_initializer.ex definitions
    tables = [
      {:user_bux_balances, [
        :user_id, :user_smart_wallet, :updated_at, :aggregate_bux_balance,
        :bux_balance, :moonbux_balance, :neobux_balance, :roguebux_balance,
        :flarebux_balance, :nftbux_balance, :nolchabux_balance, :solbux_balance,
        :spacebux_balance, :tronbux_balance, :tranbux_balance
      ]},
      {:user_rogue_balances, [
        :user_id, :user_smart_wallet, :updated_at,
        :rogue_balance_rogue_chain, :rogue_balance_arbitrum
      ]},
      {:user_betting_stats, [
        :user_id, :wallet_address,
        :bux_total_bets, :bux_wins, :bux_losses, :bux_total_wagered,
        :bux_total_winnings, :bux_total_losses, :bux_net_pnl,
        :rogue_total_bets, :rogue_wins, :rogue_losses, :rogue_total_wagered,
        :rogue_total_winnings, :rogue_total_losses, :rogue_net_pnl,
        :first_bet_at, :last_bet_at, :updated_at, :onchain_stats_cache
      ]}
    ]

    for {name, attrs} <- tables do
      try do
        :mnesia.create_table(name, attributes: attrs, type: :set)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  defp set_bux_balance(user_id, amount) do
    # Matches: {:user_bux_balances, user_id, smart_wallet, updated_at, aggregate, bux_balance, ...rest zeros}
    # elem(record, 5) = bux_balance (what get_user_token_balances reads)
    record = {:user_bux_balances, user_id, nil, nil, amount, amount,
              0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}
    :mnesia.dirty_write(record)
  end

  defp set_rogue_balance(user_id, amount) do
    # Matches: {:user_rogue_balances, user_id, smart_wallet, updated_at, rogue_chain, arbitrum}
    # elem(record, 4) = rogue_balance_rogue_chain (what get_user_token_balances reads)
    record = {:user_rogue_balances, user_id, nil, nil, amount, 0.0}
    :mnesia.dirty_write(record)
  end

  defp clear_rules do
    BlocksterV2.Repo.delete_all("system_config")
    SystemConfig.invalidate_cache()
  end

  defp save_rules(rules) do
    SystemConfig.put("custom_rules", rules, "test")
  end

  setup do
    clear_rules()
    setup_mnesia()
    %{user: create_user().user}
  end

  # ============ Balance Enrichment ============

  describe "balance enrichment" do
    test "enrich_metadata for hub_followed includes balances", %{user: user} do
      set_bux_balance(user.id, 5000.0)
      set_rogue_balance(user.id, 100_000.0)

      save_rules([
        %{
          "event_type" => "hub_followed",
          "action" => "notification",
          "title" => "Balance Test",
          "body" => "You have BUX",
          "conditions" => %{"bux_balance" => %{"$gte" => 1000}}
        }
      ])

      EventProcessor.process_user_event(user.id, "hub_followed", %{"hub_slug" => "bitcoin"})

      notifications = Notifications.list_notifications(user.id)
      assert Enum.any?(notifications, fn n -> n.title == "Balance Test" end)
    end

    test "balances default to 0.0 when user has no Mnesia record", %{user: user} do
      # Don't set any balance — should default to 0.0
      save_rules([
        %{
          "event_type" => "daily_login",
          "action" => "notification",
          "title" => "Zero Balance Test",
          "body" => "No balance",
          "conditions" => %{"bux_balance" => %{"$gte" => 1}}
        }
      ])

      EventProcessor.process_user_event(user.id, "daily_login", %{})

      notifications = Notifications.list_notifications(user.id)
      # Should NOT fire because bux_balance defaults to 0.0
      refute Enum.any?(notifications, fn n -> n.title == "Zero Balance Test" end)
    end
  end

  # ============ resolve_bonus/3 ============

  describe "resolve_bonus/3" do
    test "static bux_bonus still works (backwards compatible)" do
      rule = %{"bux_bonus" => 500}
      assert EventProcessor.resolve_bonus(rule, "bux", %{}) == 500
    end

    test "formula bonus computes value from metadata" do
      rule = %{"bux_bonus_formula" => "total_bets * 10"}
      result = EventProcessor.resolve_bonus(rule, "bux", %{"total_bets" => 5})
      assert result == 50.0
    end

    test "random formula returns value in range" do
      rule = %{"bux_bonus_formula" => "random(100, 500)"}
      result = EventProcessor.resolve_bonus(rule, "bux", %{})
      assert is_number(result)
      assert result >= 100 and result <= 500
    end

    test "formula takes precedence over static bonus" do
      rule = %{"bux_bonus" => 999, "bux_bonus_formula" => "total_bets * 10"}
      result = EventProcessor.resolve_bonus(rule, "bux", %{"total_bets" => 5})
      assert result == 50.0
    end

    test "missing variable in formula returns nil" do
      rule = %{"bux_bonus_formula" => "missing_var * 10"}
      assert EventProcessor.resolve_bonus(rule, "bux", %{}) == nil
    end

    test "division by zero in formula returns nil" do
      rule = %{"bux_bonus_formula" => "100 / total_bets"}
      assert EventProcessor.resolve_bonus(rule, "bux", %{"total_bets" => 0}) == nil
    end

    test "result capped at max (100,000 BUX)" do
      rule = %{"bux_bonus_formula" => "total_bets * 100000"}
      result = EventProcessor.resolve_bonus(rule, "bux", %{"total_bets" => 5})
      # 5 * 100000 = 500000, but capped at 100000
      assert result == 100_000
    end

    test "negative formula result returns nil" do
      rule = %{"bux_bonus_formula" => "bux_net_pnl * 0.1"}
      # bux_net_pnl is negative, so result is negative
      assert EventProcessor.resolve_bonus(rule, "bux", %{"bux_net_pnl" => -500}) == nil
    end

    test "no bonus fields returns nil" do
      assert EventProcessor.resolve_bonus(%{}, "bux", %{}) == nil
    end
  end

  # ============ Recurring Rules ============

  describe "recurring rules" do
    test "fires on first event and sets next_trigger_at", %{user: user} do
      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Recurring Test",
          "body" => "Every 10 games!",
          "recurring" => true,
          "every_n" => 10,
          "count_field" => "total_bets",
          "bux_bonus" => 500
        }
      ])

      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 1})

      notifications = Notifications.list_notifications(user.id)
      recurring_notif = Enum.find(notifications, fn n -> n.title == "Recurring Test" end)
      assert recurring_notif != nil
      assert recurring_notif.metadata["next_trigger_at"] == 11
      assert recurring_notif.metadata["fired_at_count"] == 1
      assert recurring_notif.metadata["interval"] == 10
    end

    test "does not fire again below threshold", %{user: user} do
      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Recurring Skip Test",
          "body" => "Every 10 games!",
          "recurring" => true,
          "every_n" => 10,
          "count_field" => "total_bets"
        }
      ])

      # First fire at count=1
      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 1})

      # Second event at count=5 — should NOT fire again
      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 5})

      notifications = Notifications.list_notifications(user.id)
      recurring_count = Enum.count(notifications, fn n -> n.title == "Recurring Skip Test" end)
      assert recurring_count == 1
    end

    test "fires again at threshold and sets new next_trigger_at", %{user: user} do
      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Recurring Chain",
          "body" => "Every 10 games!",
          "recurring" => true,
          "every_n" => 10,
          "count_field" => "total_bets"
        }
      ])

      # First fire at count=1 (next_trigger_at=11)
      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 1})

      # Fire again at count=11 (next_trigger_at=21)
      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 11})

      notifications = Notifications.list_notifications(user.id)
      recurring_notifs = Enum.filter(notifications, fn n -> n.title == "Recurring Chain" end)
      assert length(recurring_notifs) == 2

      # Most recent notification should have next_trigger_at=21
      [latest | _] = Enum.sort_by(recurring_notifs, & &1.inserted_at, {:desc, NaiveDateTime})
      assert latest.metadata["next_trigger_at"] == 21
      assert latest.metadata["fired_at_count"] == 11
    end

    test "random interval formula creates varying intervals", %{user: user} do
      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Random Interval",
          "body" => "Random every!",
          "recurring" => true,
          "every_n_formula" => "random(5, 15)",
          "count_field" => "total_bets"
        }
      ])

      # First fire at count=1
      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 1})

      notifications = Notifications.list_notifications(user.id)
      notif = Enum.find(notifications, fn n -> n.title == "Random Interval" end)
      assert notif != nil
      assert notif.metadata["interval"] >= 5
      assert notif.metadata["interval"] <= 15
      assert notif.metadata["next_trigger_at"] == 1 + notif.metadata["interval"]
    end

    test "non-recurring rule still deduplicates (backwards compatible)", %{user: user} do
      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "One Shot",
          "body" => "Fire once!",
          "bux_bonus" => 100,
          "conditions" => %{"total_bets" => %{"$gte" => 5}}
        }
      ])

      # First fire
      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 10})

      # Second fire — should be deduplicated
      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 20})

      notifications = Notifications.list_notifications(user.id)
      count = Enum.count(notifications, fn n -> n.title == "One Shot" end)
      assert count == 1
    end

    test "recurring rule respects conditions", %{user: user} do
      set_bux_balance(user.id, 1000.0)

      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Whale Only",
          "body" => "Big bux!",
          "recurring" => true,
          "every_n" => 5,
          "count_field" => "total_bets",
          "conditions" => %{"bux_balance" => %{"$gte" => 50000}}
        }
      ])

      # User has only 1000 BUX — condition should fail
      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 1})

      notifications = Notifications.list_notifications(user.id)
      refute Enum.any?(notifications, fn n -> n.title == "Whale Only" end)
    end

    test "recurring rule with formula bonus gives different amounts", %{user: user} do
      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Scaling Reward",
          "body" => "Scales with bets!",
          "recurring" => true,
          "every_n" => 5,
          "count_field" => "total_bets",
          "bux_bonus_formula" => "total_bets * 5"
        }
      ])

      # Fire at count=10
      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 10})

      notifications = Notifications.list_notifications(user.id)
      notif = Enum.find(notifications, fn n -> n.title == "Scaling Reward" end)
      assert notif != nil
      # total_bets * 5 = 10 * 5 = 50
      assert notif.metadata["bux_bonus"] == 50.0
    end
  end

  # ============ calculate_interval/2 ============

  describe "calculate_interval/2" do
    test "static every_n" do
      rule = %{"every_n" => 10}
      assert EventProcessor.calculate_interval(rule, %{}) == 10
    end

    test "formula every_n" do
      rule = %{"every_n_formula" => "max(3, 20 - bux_win_rate / 5)"}
      metadata = %{"bux_win_rate" => 50.0}
      assert EventProcessor.calculate_interval(rule, metadata) == 10
    end

    test "random formula every_n" do
      rule = %{"every_n_formula" => "random(5, 15)"}
      result = EventProcessor.calculate_interval(rule, %{})
      assert result >= 5 and result <= 15
    end

    test "formula takes precedence over static" do
      rule = %{"every_n" => 100, "every_n_formula" => "5"}
      assert EventProcessor.calculate_interval(rule, %{}) == 5
    end

    test "defaults to 10 when nothing set" do
      assert EventProcessor.calculate_interval(%{}, %{}) == 10
    end

    test "minimum interval is 1" do
      rule = %{"every_n_formula" => "0.5"}
      assert EventProcessor.calculate_interval(rule, %{}) == 1
    end
  end

  # ============ Full Pipeline Integration ============

  describe "full pipeline integration" do
    test "formula bonus rule fires with computed amount", %{user: user} do
      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Scaled Bonus",
          "body" => "Congrats!",
          "bux_bonus_formula" => "total_bets * 2"
        }
      ])

      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 25})

      notifications = Notifications.list_notifications(user.id)
      notif = Enum.find(notifications, fn n -> n.title == "Scaled Bonus" end)
      assert notif != nil
      # total_bets * 2 = 25 * 2 = 50
      assert notif.metadata["bux_bonus"] == 50.0
    end

    test "balance-triggered rule fires when balance sufficient", %{user: user} do
      set_bux_balance(user.id, 60_000.0)

      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "High Roller",
          "body" => "You're a whale!",
          "conditions" => %{"bux_balance" => %{"$gte" => 50000}},
          "bux_bonus" => 1000
        }
      ])

      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 5})

      notifications = Notifications.list_notifications(user.id)
      assert Enum.any?(notifications, fn n -> n.title == "High Roller" end)
    end

    test "balance-triggered rule does NOT fire when balance insufficient", %{user: user} do
      set_bux_balance(user.id, 1_000.0)

      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Not a Whale",
          "body" => "You're a whale!",
          "conditions" => %{"bux_balance" => %{"$gte" => 50000}},
          "bux_bonus" => 1000
        }
      ])

      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 5})

      notifications = Notifications.list_notifications(user.id)
      refute Enum.any?(notifications, fn n -> n.title == "Not a Whale" end)
    end

    test "recurring rule with formula creates notification with next_trigger_at", %{user: user} do
      save_rules([
        %{
          "event_type" => "game_played",
          "action" => "notification",
          "title" => "Pipeline Recurring",
          "body" => "Recurring!",
          "recurring" => true,
          "every_n" => 10,
          "count_field" => "total_bets",
          "bux_bonus_formula" => "random(50, 100)"
        }
      ])

      EventProcessor.process_user_event(user.id, "game_played", %{"total_bets" => 37})

      notifications = Notifications.list_notifications(user.id)
      notif = Enum.find(notifications, fn n -> n.title == "Pipeline Recurring" end)
      assert notif != nil
      assert notif.metadata["next_trigger_at"] == 47
      assert notif.metadata["fired_at_count"] == 37
      assert notif.metadata["bux_bonus"] >= 50
      assert notif.metadata["bux_bonus"] <= 100
    end
  end
end
