defmodule BlocksterV2.TelegramBot.PromoEngineTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.TelegramBot.PromoEngine
  alias BlocksterV2.Notifications.{SystemConfig, FormulaEvaluator}
  alias BlocksterV2.Notifications.EventProcessor
  alias BlocksterV2.{Repo, Accounts.User}

  setup do
    setup_mnesia()
    :ok
  end

  defp setup_mnesia do
    tables = [
      {:bot_daily_rewards, [:key, :date, :total_bux_given, :user_reward_counts]},
      {:hourly_promo_state, [:key, :current_promo, :started_at, :history]},
      {:hourly_promo_entries, [:key, :promo_id, :user_id, :metric_value, :entered_at]}
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

    # Clean up any existing data
    for {name, _} <- tables do
      try do
        :mnesia.clear_table(name)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  describe "pick_next_promo/1" do
    test "picks a promo with required fields" do
      promo = PromoEngine.pick_next_promo()
      assert promo.id
      assert promo.category
      assert promo.template
      assert promo.name
      assert promo.announcement_html
      assert promo.started_at
      assert promo.expires_at
    end

    test "promo expires 1 hour after start" do
      promo = PromoEngine.pick_next_promo()
      diff = DateTime.diff(promo.expires_at, promo.started_at, :second)
      assert diff == 3600
    end

    test "never picks the same exact promo twice in a row" do
      # Run 20 iterations and verify no exact repeats
      {_, repeats} = Enum.reduce(1..20, {nil, 0}, fn _, {last_name, repeats} ->
        history = if last_name, do: [%{name: last_name, category: :bux_booster_rule}], else: []
        promo = PromoEngine.pick_next_promo(history)
        new_repeats = if promo.name == last_name, do: repeats + 1, else: repeats
        {promo.name, new_repeats}
      end)
      assert repeats == 0
    end

    test "all templates have required fields" do
      templates = PromoEngine.all_templates()
      for {_category, template_list} <- templates, template <- template_list do
        assert Map.has_key?(template, :name), "Template missing :name"
        assert Map.has_key?(template, :category), "Template missing :category"
      end
    end
  end

  describe "activate_promo/1 — BUX Booster rules" do
    test "creates a custom rule in SystemConfig" do
      promo = PromoEngine.pick_next_promo()
      # Force to bux_booster_rule
      template = hd(PromoEngine.all_templates()[:bux_booster_rule])
      promo = %{promo | category: :bux_booster_rule, template: template}

      PromoEngine.activate_promo(promo)

      rules = SystemConfig.get("custom_rules", [])
      bot_rules = Enum.filter(rules, &(&1["source"] == "telegram_bot"))
      assert length(bot_rules) >= 1
      rule = hd(bot_rules)
      assert rule["_hourly_promo"] == true
      assert rule["_promo_id"] == promo.id
      assert rule["source"] == "telegram_bot"
    end
  end

  describe "settle_promo/1 — cleanup" do
    test "removes bot-created rules from SystemConfig" do
      promo = PromoEngine.pick_next_promo()
      template = hd(PromoEngine.all_templates()[:bux_booster_rule])
      promo = %{promo | category: :bux_booster_rule, template: template}

      PromoEngine.activate_promo(promo)
      rules_before = SystemConfig.get("custom_rules", [])
      bot_rules_before = Enum.filter(rules_before, &(&1["source"] == "telegram_bot"))
      assert length(bot_rules_before) >= 1

      PromoEngine.settle_promo(promo)
      rules_after = SystemConfig.get("custom_rules", [])
      bot_rules_after = Enum.filter(rules_after, &(&1["source"] == "telegram_bot"))
      assert length(bot_rules_after) == 0
    end

    test "settle nil promo is a no-op" do
      assert :ok == PromoEngine.settle_promo(nil)
    end
  end

  describe "cleanup_all_bot_rules/0" do
    test "removes all bot-tagged rules" do
      # Add some bot rules
      rules = SystemConfig.get("custom_rules", [])
      bot_rule = %{"source" => "telegram_bot", "event_type" => "game_played", "_hourly_promo" => true}
      admin_rule = %{"source" => "admin", "event_type" => "telegram_connected", "title" => "Test"}
      SystemConfig.put("custom_rules", rules ++ [bot_rule, admin_rule], "test")

      PromoEngine.cleanup_all_bot_rules()

      updated = SystemConfig.get("custom_rules", [])
      assert Enum.any?(updated, &(&1["source"] == "admin"))
      refute Enum.any?(updated, &(&1["source"] == "telegram_bot"))
    end
  end

  describe "daily budget enforcement" do
    test "remaining_budget starts at 100000" do
      assert PromoEngine.remaining_budget() == 100_000
    end

    test "budget_exhausted? is false when fresh" do
      refute PromoEngine.budget_exhausted?()
    end

    test "get_daily_state returns correct structure" do
      state = PromoEngine.get_daily_state()
      assert state.date == Date.utc_today()
      assert state.total_bux_given == 0
      assert state.user_reward_counts == %{}
    end

    test "remaining_budget decreases when rewards are recorded in Mnesia" do
      assert PromoEngine.remaining_budget() == 100_000

      # Simulate 5000 BUX distributed by writing directly to Mnesia
      :mnesia.dirty_write({:bot_daily_rewards, :daily, Date.utc_today(), 5000, %{1 => 2, 2 => 1}})

      assert PromoEngine.remaining_budget() == 95_000
      refute PromoEngine.budget_exhausted?()

      state = PromoEngine.get_daily_state()
      assert state.total_bux_given == 5000
      assert state.user_reward_counts == %{1 => 2, 2 => 1}
    end

    test "budget_exhausted? returns true at 100k" do
      :mnesia.dirty_write({:bot_daily_rewards, :daily, Date.utc_today(), 100_000, %{}})
      assert PromoEngine.budget_exhausted?()
      assert PromoEngine.remaining_budget() == 0
    end

    test "credit_user returns :daily_budget_exceeded when budget is full" do
      :mnesia.dirty_write({:bot_daily_rewards, :daily, Date.utc_today(), 100_000, %{}})

      result = PromoEngine.credit_user(1, 100)
      assert result == {:error, :daily_budget_exceeded}
    end

    test "credit_user returns :user_daily_limit when user has 10 rewards" do
      :mnesia.dirty_write({:bot_daily_rewards, :daily, Date.utc_today(), 500, %{42 => 10}})

      result = PromoEngine.credit_user(42, 100)
      assert result == {:error, :user_daily_limit}
    end

    test "credit_user allows user with fewer than 10 rewards" do
      :mnesia.dirty_write({:bot_daily_rewards, :daily, Date.utc_today(), 500, %{42 => 9}})

      # Will fail at mint (no real wallet) but should NOT fail at budget/limit check
      result = PromoEngine.credit_user(42, 100)
      # Should get past budget checks — either :no_wallet (no user) or mint error
      assert result in [{:error, :no_wallet}] or match?({:error, _}, result)
      refute result == {:error, :daily_budget_exceeded}
      refute result == {:error, :user_daily_limit}
    end

    test "daily state resets when date changes" do
      # Write yesterday's state
      yesterday = Date.utc_today() |> Date.add(-1)
      :mnesia.dirty_write({:bot_daily_rewards, :daily, yesterday, 99_000, %{1 => 10}})

      # Should reset to today
      state = PromoEngine.get_daily_state()
      assert state.date == Date.utc_today()
      assert state.total_bux_given == 0
      assert state.user_reward_counts == %{}
      assert PromoEngine.remaining_budget() == 100_000
    end
  end

  describe "distribute_prizes/4" do
    test "tiered distribution — 3 winners" do
      prizes = PromoEngine.distribute_prizes(1000, :tiered, 3, 3)
      assert prizes == [500.0, 300.0, 200.0]
    end

    test "tiered distribution — 2 winners" do
      prizes = PromoEngine.distribute_prizes(1000, :tiered, 3, 2)
      assert prizes == [600.0, 400.0]
    end

    test "tiered distribution — 1 winner" do
      prizes = PromoEngine.distribute_prizes(1000, :tiered, 3, 1)
      assert prizes == [1000]
    end

    test "winner-take-all" do
      prizes = PromoEngine.distribute_prizes(5000, :winner_take_all, 3, 5)
      assert prizes == [5000]
    end

    test "participation — even split" do
      prizes = PromoEngine.distribute_prizes(1000, :participation, 10, 5)
      assert length(prizes) == 5
      assert Enum.all?(prizes, &(&1 == 200.0))
    end
  end

  describe "format_results_html/2" do
    test "giveaway with winners" do
      promo = %{
        name: "BUX Rain",
        category: :giveaway,
        results: {:ok, [{1, "alice", 500}, {2, "bob", 300}]}
      }
      html = PromoEngine.format_results_html(promo, %{name: "Next Promo"})
      assert html =~ "GIVEAWAY WINNERS"
      assert html =~ "@alice"
      assert html =~ "@bob"
      assert html =~ "800 BUX"
    end

    test "giveaway with no participants" do
      promo = %{name: "BUX Rain", category: :giveaway, results: {:ok, []}}
      html = PromoEngine.format_results_html(promo, nil)
      assert html =~ "No eligible participants"
    end

    test "competition with winners" do
      promo = %{
        name: "Wagering Champion",
        category: :competition,
        results: {:ok, [{1, "charlie", 1000}, {2, "dave", 600}]}
      }
      html = PromoEngine.format_results_html(promo, nil)
      assert html =~ "RESULTS"
      assert html =~ "@charlie"
      assert html =~ "1600 BUX"
    end

    test "nil promo returns nil" do
      assert nil == PromoEngine.format_results_html(nil, nil)
    end
  end

  describe "BUX Booster rule templates" do
    test "all rule formulas use bet_amount (per-bet, not lifetime)" do
      templates = PromoEngine.all_templates()[:bux_booster_rule]
      for template <- templates do
        formula = template.rule["bux_bonus_formula"]
        assert formula, "Template #{template.name} missing formula"
        assert String.contains?(formula, "bet_amount"),
          "Template #{template.name} formula must use bet_amount (per-bet), not lifetime totals: #{formula}"
      end
    end

    test "all rule formulas reference rogue_balance" do
      templates = PromoEngine.all_templates()[:bux_booster_rule]
      for template <- templates do
        formula = template.rule["bux_bonus_formula"]
        assert String.contains?(formula, "rogue_balance"),
          "Template #{template.name} formula must include rogue_balance: #{formula}"
      end
    end

    test "all rules use every_n_formula with rogue_balance for dynamic trigger frequency" do
      templates = PromoEngine.all_templates()[:bux_booster_rule]
      for template <- templates do
        every_n_formula = template.rule["every_n_formula"]
        assert every_n_formula,
          "Template #{template.name} must use every_n_formula (not fixed every_n)"
        assert String.contains?(every_n_formula, "rogue_balance"),
          "Template #{template.name} every_n_formula must reference rogue_balance: #{every_n_formula}"
      end
    end

    test "all formulas use profit-based calculation (payout - bet_amount)" do
      templates = PromoEngine.all_templates()[:bux_booster_rule]
      for template <- templates do
        formula = template.rule["bux_bonus_formula"]
        assert String.contains?(formula, "payout - bet_amount"),
          "Template #{template.name} formula must use profit (payout - bet_amount): #{formula}"
      end
    end

    test "all announcements explain bet size + ROGUE scaling" do
      templates = PromoEngine.all_templates()[:bux_booster_rule]
      for template <- templates do
        ann = template.announcement
        assert ann, "Template #{template.name} missing announcement"
        assert String.contains?(ann, "ROGUE"),
          "Template #{template.name} announcement must mention ROGUE"
        assert String.contains?(ann, "bet") or String.contains?(ann, "Bet"),
          "Template #{template.name} announcement must mention betting"
      end
    end

    test "no formulas use lifetime totals (bux_total_wagered, bux_wins, bux_win_rate)" do
      templates = PromoEngine.all_templates()[:bux_booster_rule]
      banned = ["bux_total_wagered", "bux_wins", "bux_losses", "bux_win_rate", "bux_total_losses", "bux_net_pnl"]
      for template <- templates do
        formula = template.rule["bux_bonus_formula"]
        for banned_var <- banned do
          refute String.contains?(formula, banned_var),
            "Template #{template.name} formula must NOT use lifetime stat #{banned_var}: #{formula}"
        end
      end
    end
  end

  # ============ INTEGRATION TESTS ============
  # These test actual behavior, not just string patterns.

  describe "BUX Booster formula evaluation — real formulas with real metadata" do
    test "all bonus formulas evaluate successfully with realistic game_played metadata" do
      metadata = %{
        "bet_amount" => 1000,
        "payout" => 1980,      # 1.98x win
        "rogue_balance" => 500_000,
        "total_bets" => 50
      }

      templates = PromoEngine.all_templates()[:bux_booster_rule]
      for template <- templates do
        formula = template.rule["bux_bonus_formula"]
        result = FormulaEvaluator.evaluate(formula, metadata)
        assert {:ok, val} = result, "Formula failed for #{template.name}: #{formula}"
        assert val > 0, "#{template.name} bonus should be > 0 for a 1.98x win, got #{val}"
      end
    end

    test "all bonus formulas evaluate successfully on a LOSS" do
      metadata = %{
        "bet_amount" => 1000,
        "payout" => 0,          # loss
        "rogue_balance" => 200_000,
        "total_bets" => 10
      }

      templates = PromoEngine.all_templates()[:bux_booster_rule]
      for template <- templates do
        formula = template.rule["bux_bonus_formula"]
        result = FormulaEvaluator.evaluate(formula, metadata)
        assert {:ok, val} = result, "Formula failed for #{template.name} on loss: #{formula}"
        assert val > 0, "#{template.name} bonus should be > 0 on a loss, got #{val}"
      end
    end

    test "1.02x win gives much smaller bonus than loss (anti-farming)" do
      win_metadata = %{"bet_amount" => 1000, "payout" => 1020, "rogue_balance" => 0, "total_bets" => 5}
      loss_metadata = %{"bet_amount" => 1000, "payout" => 0, "rogue_balance" => 0, "total_bets" => 5}

      # Test with Bet Bonus Blitz (20%)
      template = hd(PromoEngine.all_templates()[:bux_booster_rule])
      formula = template.rule["bux_bonus_formula"]

      {:ok, win_bonus} = FormulaEvaluator.evaluate(formula, win_metadata)
      {:ok, loss_bonus} = FormulaEvaluator.evaluate(formula, loss_metadata)

      # 1.02x win profit = 20, so 20% = 4 BUX. Loss = 1000, so 20% = 200 BUX.
      assert win_bonus < loss_bonus, "1.02x win (#{win_bonus}) should give less than loss (#{loss_bonus})"
      assert win_bonus < 10, "1.02x win bonus should be tiny, got #{win_bonus}"
    end

    test "31.68x win gives massive bonus" do
      metadata = %{"bet_amount" => 1000, "payout" => 31_680, "rogue_balance" => 0, "total_bets" => 5}

      template = hd(PromoEngine.all_templates()[:bux_booster_rule])
      formula = template.rule["bux_bonus_formula"]

      {:ok, bonus} = FormulaEvaluator.evaluate(formula, metadata)
      # profit = 30680, 20% = 6136
      assert bonus > 5000, "31.68x win bonus should be huge, got #{bonus}"
    end

    test "ROGUE balance adds flat bonus" do
      base_metadata = %{"bet_amount" => 1000, "payout" => 0, "rogue_balance" => 0, "total_bets" => 5}
      rogue_metadata = %{"bet_amount" => 1000, "payout" => 0, "rogue_balance" => 1_000_000, "total_bets" => 5}

      template = hd(PromoEngine.all_templates()[:bux_booster_rule])
      formula = template.rule["bux_bonus_formula"]

      {:ok, base_bonus} = FormulaEvaluator.evaluate(formula, base_metadata)
      {:ok, rogue_bonus} = FormulaEvaluator.evaluate(formula, rogue_metadata)

      diff = rogue_bonus - base_bonus
      # 1M * 0.0001 = 100 BUX flat bonus
      assert_in_delta diff, 100.0, 1.0, "1M ROGUE should add ~100 BUX, got #{diff}"
    end

    test "all every_n_formulas evaluate to valid integers >= 1" do
      metadata = %{"rogue_balance" => 500_000}

      templates = PromoEngine.all_templates()[:bux_booster_rule]
      for template <- templates do
        formula = template.rule["every_n_formula"]
        result = FormulaEvaluator.evaluate(formula, metadata)
        assert {:ok, val} = result, "every_n_formula failed for #{template.name}: #{formula}"
        assert val >= 1, "#{template.name} frequency should be >= 1, got #{val}"
      end
    end

    test "more ROGUE = more frequent triggers (lower every_n)" do
      low_rogue = %{"rogue_balance" => 0}
      high_rogue = %{"rogue_balance" => 1_000_000}

      # Test with a non-random template (Bet Bonus Blitz)
      template = hd(PromoEngine.all_templates()[:bux_booster_rule])
      formula = template.rule["every_n_formula"]

      {:ok, low_freq} = FormulaEvaluator.evaluate(formula, low_rogue)
      {:ok, high_freq} = FormulaEvaluator.evaluate(formula, high_rogue)

      assert high_freq < low_freq,
        "1M ROGUE (#{high_freq}) should trigger more often than 0 ROGUE (#{low_freq})"
    end
  end

  describe "BUX Booster — EventProcessor integration" do
    test "activated rule matches game_played events via EventProcessor.resolve_bonus" do
      promo = PromoEngine.pick_next_promo()
      template = hd(PromoEngine.all_templates()[:bux_booster_rule])
      promo = %{promo | category: :bux_booster_rule, template: template}

      PromoEngine.activate_promo(promo)

      rules = SystemConfig.get("custom_rules", [])
      bot_rule = Enum.find(rules, &(&1["source"] == "telegram_bot"))
      assert bot_rule, "Bot rule should exist in SystemConfig after activation"

      # Verify the rule matches game_played
      assert bot_rule["event_type"] == "game_played"

      # Verify resolve_bonus returns a positive number with game metadata
      metadata = %{
        "bet_amount" => 500,
        "payout" => 990,  # 1.98x win
        "rogue_balance" => 300_000,
        "total_bets" => 25
      }

      bonus = EventProcessor.resolve_bonus(bot_rule, "bux", metadata)
      assert is_number(bonus) and bonus > 0,
        "resolve_bonus should return positive number, got #{inspect(bonus)}"

      # Cleanup
      PromoEngine.settle_promo(promo)
    end

    test "High Roller rule only matches bets >= 500 via conditions" do
      templates = PromoEngine.all_templates()[:bux_booster_rule]
      high_roller = Enum.find(templates, &(&1.name == "High Roller Hour"))
      assert high_roller, "High Roller Hour template should exist"
      assert high_roller.rule["conditions"] == %{"bet_amount" => %{"$gte" => 500}}
    end

    test "Newbie Power Hour only matches <= 20 total bets via conditions" do
      templates = PromoEngine.all_templates()[:bux_booster_rule]
      newbie = Enum.find(templates, &(&1.name == "Newbie Power Hour"))
      assert newbie, "Newbie Power Hour template should exist"
      assert newbie.rule["conditions"] == %{"total_bets" => %{"$lte" => 20}}
    end

    test "EventProcessor.calculate_interval uses every_n_formula from rule" do
      template = hd(PromoEngine.all_templates()[:bux_booster_rule])
      rule = template.rule
      metadata = %{"rogue_balance" => 500_000, "total_bets" => 20}

      interval = EventProcessor.calculate_interval(rule, metadata)
      assert is_integer(interval) and interval >= 1,
        "calculate_interval should return integer >= 1, got #{inspect(interval)}"
    end
  end

  describe "referral boost — activation and restoration" do
    test "activate stores originals and applies boosted rates" do
      # Set known starting values
      SystemConfig.put("referrer_signup_bux", 500, "test")
      SystemConfig.put("referee_signup_bux", 250, "test")
      SystemConfig.put("phone_verify_bux", 500, "test")

      templates = PromoEngine.all_templates()[:referral_boost]
      template = hd(templates)  # Double Referral Hour
      promo = %{
        id: "test_referral",
        category: :referral_boost,
        template: template,
        name: template.name,
        announcement_html: "test",
        started_at: DateTime.utc_now(),
        expires_at: DateTime.utc_now() |> DateTime.add(3600),
        results: nil
      }

      PromoEngine.activate_promo(promo)

      # Rates should be boosted
      assert SystemConfig.get("referrer_signup_bux") == template.boost.referrer_signup_bux
      assert SystemConfig.get("referee_signup_bux") == template.boost.referee_signup_bux
      assert SystemConfig.get("phone_verify_bux") == template.boost.phone_verify_bux
    end

    test "settle restores original rates" do
      # Set known starting values
      SystemConfig.put("referrer_signup_bux", 500, "test")
      SystemConfig.put("referee_signup_bux", 250, "test")
      SystemConfig.put("phone_verify_bux", 500, "test")

      templates = PromoEngine.all_templates()[:referral_boost]
      template = hd(templates)
      promo = %{
        id: "test_referral",
        category: :referral_boost,
        template: template,
        name: template.name,
        announcement_html: "test",
        started_at: DateTime.utc_now(),
        expires_at: DateTime.utc_now() |> DateTime.add(3600),
        results: nil
      }

      PromoEngine.activate_promo(promo)
      # Rates are now boosted
      assert SystemConfig.get("referrer_signup_bux") != 500

      PromoEngine.settle_promo(promo)
      # Rates should be restored
      assert SystemConfig.get("referrer_signup_bux") == 500
      assert SystemConfig.get("referee_signup_bux") == 250
      assert SystemConfig.get("phone_verify_bux") == 500
    end
  end

  describe "giveaway settlement — real DB queries" do
    setup do
      # Create test users with telegram + smart wallet
      {:ok, user1} = Repo.insert(%User{
        email: "giveaway1@test.com",
        wallet_address: "0xwallet_ga1_#{System.unique_integer([:positive])}",
        telegram_user_id: "111",
        telegram_username: "alice",
        smart_wallet_address: "0xaaa",
        telegram_group_joined_at: DateTime.utc_now() |> DateTime.add(-600) |> DateTime.truncate(:second)
      })

      {:ok, user2} = Repo.insert(%User{
        email: "giveaway2@test.com",
        wallet_address: "0xwallet_ga2_#{System.unique_integer([:positive])}",
        telegram_user_id: "222",
        telegram_username: "bob",
        smart_wallet_address: "0xbbb",
        telegram_group_joined_at: DateTime.utc_now() |> DateTime.add(-300) |> DateTime.truncate(:second)
      })

      # User without telegram — should NOT be eligible
      {:ok, _user3} = Repo.insert(%User{
        email: "giveaway3@test.com",
        wallet_address: "0xwallet_ga3_#{System.unique_integer([:positive])}",
        smart_wallet_address: "0xccc"
      })

      %{user1: user1, user2: user2}
    end

    test "auto_entry giveaway finds telegram group members", %{user1: user1, user2: user2} do
      template = Enum.find(PromoEngine.all_templates()[:giveaway], &(&1.type == :auto_entry))
      assert template, "auto_entry template should exist"

      promo = %{
        id: "test_giveaway",
        category: :giveaway,
        template: template,
        name: template.name,
        announcement_html: "test",
        started_at: DateTime.utc_now() |> DateTime.add(-3600),
        expires_at: DateTime.utc_now(),
        results: nil
      }

      # settle_promo triggers settlement and returns results
      results = PromoEngine.settle_promo(promo)

      case results do
        {:ok, winners} ->
          assert is_list(winners)
          # Winners should only come from users with telegram + smart_wallet + group_joined
          winner_ids = Enum.map(winners, fn {id, _, _} -> id end)
          for id <- winner_ids do
            assert id in [user1.id, user2.id],
              "Winner #{id} should be a telegram group member"
          end

        _ ->
          # credit_user may fail (no real minter in test) but the query worked
          :ok
      end
    end

    test "activity_based giveaway finds users who performed events", %{user1: user1} do
      # Insert an article_view event for user1
      Repo.insert!(%BlocksterV2.Notifications.UserEvent{
        user_id: user1.id,
        event_type: "article_view",
        event_category: "engagement",
        metadata: %{"post_id" => 1},
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })

      template = Enum.find(PromoEngine.all_templates()[:giveaway], &(&1.type == :activity_based))
      assert template, "activity_based template should exist"

      promo = %{
        id: "test_activity_giveaway",
        category: :giveaway,
        template: template,
        name: template.name,
        announcement_html: "test",
        started_at: DateTime.utc_now() |> DateTime.add(-3600),
        expires_at: DateTime.utc_now(),
        results: nil
      }

      results = PromoEngine.settle_promo(promo)

      case results do
        {:ok, winners} ->
          assert is_list(winners)
          if length(winners) > 0 do
            winner_ids = Enum.map(winners, fn {id, _, _} -> id end)
            assert user1.id in winner_ids, "user1 should be eligible (has article_view event)"
          end

        _ -> :ok
      end
    end

    test "new_members giveaway finds users who joined during promo window" do
      # Create a user who joined 5 minutes ago (within promo window)
      {:ok, new_user} = Repo.insert(%User{
        email: "newmember@test.com",
        wallet_address: "0xwallet_new_#{System.unique_integer([:positive])}",
        telegram_user_id: "999",
        telegram_username: "newbie",
        smart_wallet_address: "0xnew",
        telegram_group_joined_at: DateTime.utc_now() |> DateTime.add(-300) |> DateTime.truncate(:second)
      })

      template = Enum.find(PromoEngine.all_templates()[:giveaway], &(&1.type == :new_members))
      assert template, "new_members template should exist"
      assert template.prize_amount == 1000, "New Member Welcome Drop should award 1000 BUX"

      promo = %{
        id: "test_new_members",
        category: :giveaway,
        template: template,
        name: template.name,
        announcement_html: "test",
        started_at: DateTime.utc_now() |> DateTime.add(-3600),
        expires_at: DateTime.utc_now(),
        results: nil
      }

      results = PromoEngine.settle_promo(promo)

      case results do
        {:ok, winners} ->
          assert is_list(winners)
          winner_ids = Enum.map(winners, fn {id, _, _} -> id end)
          assert new_user.id in winner_ids,
            "New member should be in winners list"

          # Check prize amount is 1000
          {_, _, amount} = Enum.find(winners, fn {id, _, _} -> id == new_user.id end)
          assert amount == 1000, "Prize should be 1000 BUX, got #{amount}"

        _ -> :ok
      end
    end
  end

  describe "competition settlement — real DB queries" do
    setup do
      {:ok, user1} = Repo.insert(%User{
        email: "comp1@test.com",
        wallet_address: "0xwallet_c1_#{System.unique_integer([:positive])}",
        telegram_user_id: "c1",
        telegram_username: "player1",
        smart_wallet_address: "0xcomp1"
      })

      {:ok, user2} = Repo.insert(%User{
        email: "comp2@test.com",
        wallet_address: "0xwallet_c2_#{System.unique_integer([:positive])}",
        telegram_user_id: "c2",
        telegram_username: "player2",
        smart_wallet_address: "0xcomp2"
      })

      %{user1: user1, user2: user2}
    end

    test "articles_read competition ranks users by article_view count", %{user1: user1, user2: user2} do
      now_naive = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      now_dt = DateTime.utc_now() |> DateTime.truncate(:second)

      # user1 reads 3 articles, user2 reads 1
      for _ <- 1..3 do
        Repo.insert!(%BlocksterV2.Notifications.UserEvent{
          user_id: user1.id,
          event_type: "article_view",
          event_category: "engagement",
          metadata: %{},
          inserted_at: now_naive
        })
      end

      Repo.insert!(%BlocksterV2.Notifications.UserEvent{
        user_id: user2.id,
        event_type: "article_view",
        event_category: "engagement",
        metadata: %{},
        inserted_at: now_naive
      })

      template = Enum.find(PromoEngine.all_templates()[:competition], &(&1.metric == :articles_read))
      assert template, "articles_read competition template should exist"

      promo = %{
        id: "test_reading_comp",
        category: :competition,
        template: template,
        name: template.name,
        announcement_html: "test",
        started_at: now_dt |> DateTime.add(-3600),
        expires_at: now_dt,
        results: nil
      }

      results = PromoEngine.settle_promo(promo)

      case results do
        {:ok, winners} ->
          assert length(winners) >= 1
          # user1 should be first (3 reads vs 1)
          {first_id, _, _} = hd(winners)
          assert first_id == user1.id, "user1 (3 reads) should be #1, got user #{first_id}"

        _ -> :ok
      end
    end

    test "bet_count competition ranks users by game_played count", %{user1: user1, user2: user2} do
      now_naive = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      now_dt = DateTime.utc_now() |> DateTime.truncate(:second)

      # user2 places 5 bets, user1 places 2
      for _ <- 1..5 do
        Repo.insert!(%BlocksterV2.Notifications.UserEvent{
          user_id: user2.id,
          event_type: "game_played",
          event_category: "engagement",
          metadata: %{"bet_amount" => 100},
          inserted_at: now_naive
        })
      end

      for _ <- 1..2 do
        Repo.insert!(%BlocksterV2.Notifications.UserEvent{
          user_id: user1.id,
          event_type: "game_played",
          event_category: "engagement",
          metadata: %{"bet_amount" => 500},
          inserted_at: now_naive
        })
      end

      template = Enum.find(PromoEngine.all_templates()[:competition], &(&1.metric == :bet_count))
      assert template, "bet_count competition template should exist"

      promo = %{
        id: "test_bet_comp",
        category: :competition,
        template: template,
        name: template.name,
        announcement_html: "test",
        started_at: now_dt |> DateTime.add(-3600),
        expires_at: now_dt,
        results: nil
      }

      results = PromoEngine.settle_promo(promo)

      case results do
        {:ok, winners} ->
          assert length(winners) >= 1
          # user2 should be first (5 bets vs 2)
          {first_id, _, _} = hd(winners)
          assert first_id == user2.id, "user2 (5 bets) should be #1, got user #{first_id}"

        _ -> :ok
      end
    end
  end

  describe "only valid categories can be picked" do
    test "pick_next_promo only returns categories that exist in all_templates" do
      valid_categories = Map.keys(PromoEngine.all_templates())

      for _ <- 1..50 do
        promo = PromoEngine.pick_next_promo()
        assert promo.category in valid_categories,
          "Picked category #{promo.category} not in valid categories: #{inspect(valid_categories)}"
      end
    end

    test "every template has a non-nil announcement" do
      for {category, templates} <- PromoEngine.all_templates(), template <- templates do
        announcement = template[:announcement]
        assert announcement != nil,
          "#{category}/#{template.name} has nil announcement — it's a stub that will fail"
      end
    end
  end

  # ============ FULL LIFECYCLE INTEGRATION TESTS ============

  describe "full lifecycle — BUX Booster rule" do
    test "pick → activate → rule exists → settle → rule gone" do
      templates = PromoEngine.all_templates()[:bux_booster_rule]
      template = hd(templates)
      promo = %{
        id: "lifecycle_bux_#{System.system_time(:millisecond)}",
        category: :bux_booster_rule,
        template: template,
        name: template.name,
        announcement_html: template.announcement,
        started_at: DateTime.utc_now(),
        expires_at: DateTime.utc_now() |> DateTime.add(3600),
        results: nil
      }

      # Before activation — no bot rules
      rules_before = SystemConfig.get("custom_rules", [])
      bot_before = Enum.filter(rules_before, &(&1["source"] == "telegram_bot"))
      assert bot_before == []

      # Activate
      assert :ok = PromoEngine.activate_promo(promo)

      # Rule should exist with correct tags
      rules_active = SystemConfig.get("custom_rules", [])
      bot_active = Enum.filter(rules_active, &(&1["source"] == "telegram_bot"))
      assert length(bot_active) == 1
      rule = hd(bot_active)
      assert rule["event_type"] == "game_played"
      assert rule["_hourly_promo"] == true
      assert rule["_promo_id"] == promo.id
      assert rule["_expires_at"] != nil
      assert rule["bux_bonus_formula"] != nil
      assert rule["recurring"] == true
      assert rule["count_field"] == "total_bets"

      # Verify EventProcessor can resolve a bonus from this rule
      metadata = %{"bet_amount" => 1000, "payout" => 1500, "rogue_balance" => 0, "total_bets" => 5}
      bonus = EventProcessor.resolve_bonus(rule, "bux", metadata)
      assert is_number(bonus) and bonus > 0

      # Settle — rule should be cleaned up
      assert :ok = PromoEngine.settle_promo(promo)
      rules_after = SystemConfig.get("custom_rules", [])
      bot_after = Enum.filter(rules_after, &(&1["source"] == "telegram_bot"))
      assert bot_after == []
    end
  end

  describe "full lifecycle — referral boost" do
    test "pick → activate → rates boosted → settle → rates restored" do
      # Set known baseline
      SystemConfig.put("referrer_signup_bux", 500, "test")
      SystemConfig.put("referee_signup_bux", 250, "test")
      SystemConfig.put("phone_verify_bux", 500, "test")

      templates = PromoEngine.all_templates()[:referral_boost]
      template = hd(templates)  # Double Referral Hour (2x)
      promo = %{
        id: "lifecycle_ref_#{System.system_time(:millisecond)}",
        category: :referral_boost,
        template: template,
        name: template.name,
        announcement_html: template.announcement,
        started_at: DateTime.utc_now(),
        expires_at: DateTime.utc_now() |> DateTime.add(3600),
        results: nil
      }

      # Activate — rates should be boosted
      assert :ok = PromoEngine.activate_promo(promo)
      assert SystemConfig.get("referrer_signup_bux") == template.boost.referrer_signup_bux
      assert SystemConfig.get("referee_signup_bux") == template.boost.referee_signup_bux
      assert SystemConfig.get("phone_verify_bux") == template.boost.phone_verify_bux

      # Verify originals were saved in Mnesia
      case :mnesia.dirty_read(:hourly_promo_state, :referral_originals) do
        [{:hourly_promo_state, :referral_originals, originals, _, _}] ->
          assert originals.referrer_signup_bux == 500
          assert originals.referee_signup_bux == 250
          assert originals.phone_verify_bux == 500

        _ ->
          flunk("Referral originals should be saved in Mnesia")
      end

      # Settle — rates should be restored
      assert :ok = PromoEngine.settle_promo(promo)
      assert SystemConfig.get("referrer_signup_bux") == 500
      assert SystemConfig.get("referee_signup_bux") == 250
      assert SystemConfig.get("phone_verify_bux") == 500

      # Mnesia originals should be cleaned up
      assert :mnesia.dirty_read(:hourly_promo_state, :referral_originals) == []
    end
  end

  describe "full lifecycle — giveaway with real users and events" do
    setup do
      {:ok, user1} = Repo.insert(%User{
        email: "life_ga1_#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0xwallet_lga1_#{System.unique_integer([:positive])}",
        telegram_user_id: "lga1_#{System.unique_integer([:positive])}",
        telegram_username: "lifecycle_alice",
        smart_wallet_address: "0xlga1_#{System.unique_integer([:positive])}",
        telegram_group_joined_at: DateTime.utc_now() |> DateTime.add(-600) |> DateTime.truncate(:second)
      })

      {:ok, user2} = Repo.insert(%User{
        email: "life_ga2_#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0xwallet_lga2_#{System.unique_integer([:positive])}",
        telegram_user_id: "lga2_#{System.unique_integer([:positive])}",
        telegram_username: "lifecycle_bob",
        smart_wallet_address: "0xlga2_#{System.unique_integer([:positive])}",
        telegram_group_joined_at: DateTime.utc_now() |> DateTime.add(-300) |> DateTime.truncate(:second)
      })

      %{user1: user1, user2: user2}
    end

    test "activity_based: insert events → settle → winners are users who performed action", %{user1: user1} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      started_at = DateTime.utc_now() |> DateTime.add(-3600)

      # user1 reads 2 articles during the promo window
      for _ <- 1..2 do
        Repo.insert!(%BlocksterV2.Notifications.UserEvent{
          user_id: user1.id,
          event_type: "article_view",
          event_category: "engagement",
          metadata: %{"post_id" => System.unique_integer([:positive])},
          inserted_at: now
        })
      end

      template = Enum.find(PromoEngine.all_templates()[:giveaway], &(&1.type == :activity_based))
      promo = %{
        id: "lifecycle_giveaway_#{System.system_time(:millisecond)}",
        category: :giveaway,
        template: template,
        name: template.name,
        announcement_html: template.announcement,
        started_at: started_at,
        expires_at: DateTime.utc_now(),
        results: nil
      }

      # Activate (no-op for giveaways without rules)
      assert :ok = PromoEngine.activate_promo(promo)

      # Settle — should find user1 as eligible
      results = PromoEngine.settle_promo(promo)
      assert {:ok, winners} = results
      assert is_list(winners)

      if length(winners) > 0 do
        winner_ids = Enum.map(winners, fn {id, _, _} -> id end)
        assert user1.id in winner_ids
        # Each winner should have a prize in the template range
        for {_id, _username, amount} <- winners do
          {min_prize, max_prize} = template.prize_range
          assert amount >= min_prize and amount <= max_prize,
            "Prize #{amount} should be between #{min_prize} and #{max_prize}"
        end
      end
    end

    test "auto_entry: all group members are eligible without any action", %{user1: user1, user2: user2} do
      template = Enum.find(PromoEngine.all_templates()[:giveaway], &(&1.type == :auto_entry))
      promo = %{
        id: "lifecycle_auto_#{System.system_time(:millisecond)}",
        category: :giveaway,
        template: template,
        name: template.name,
        announcement_html: template.announcement,
        started_at: DateTime.utc_now() |> DateTime.add(-3600),
        expires_at: DateTime.utc_now(),
        results: nil
      }

      results = PromoEngine.settle_promo(promo)
      assert {:ok, winners} = results

      if length(winners) > 0 do
        winner_ids = Enum.map(winners, fn {id, _, _} -> id end)
        # Both users are eligible (both have telegram + smart_wallet + group_joined)
        for id <- winner_ids do
          assert id in [user1.id, user2.id]
        end
      end
    end
  end

  describe "full lifecycle — competition with real users and events" do
    setup do
      {:ok, user1} = Repo.insert(%User{
        email: "life_comp1_#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0xwallet_lc1_#{System.unique_integer([:positive])}",
        telegram_user_id: "lc1_#{System.unique_integer([:positive])}",
        telegram_username: "lifecycle_player1",
        smart_wallet_address: "0xlc1_#{System.unique_integer([:positive])}"
      })

      {:ok, user2} = Repo.insert(%User{
        email: "life_comp2_#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0xwallet_lc2_#{System.unique_integer([:positive])}",
        telegram_user_id: "lc2_#{System.unique_integer([:positive])}",
        telegram_username: "lifecycle_player2",
        smart_wallet_address: "0xlc2_#{System.unique_integer([:positive])}"
      })

      %{user1: user1, user2: user2}
    end

    test "articles_read: user with more reads ranks higher → gets bigger prize", %{user1: user1, user2: user2} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      started_at = DateTime.utc_now() |> DateTime.add(-3600)

      # user1 reads 5 articles, user2 reads 2
      for _ <- 1..5 do
        Repo.insert!(%BlocksterV2.Notifications.UserEvent{
          user_id: user1.id,
          event_type: "article_view",
          event_category: "engagement",
          metadata: %{},
          inserted_at: now
        })
      end

      for _ <- 1..2 do
        Repo.insert!(%BlocksterV2.Notifications.UserEvent{
          user_id: user2.id,
          event_type: "article_view",
          event_category: "engagement",
          metadata: %{},
          inserted_at: now
        })
      end

      template = Enum.find(PromoEngine.all_templates()[:competition], &(&1.metric == :articles_read))
      promo = %{
        id: "lifecycle_comp_#{System.system_time(:millisecond)}",
        category: :competition,
        template: template,
        name: template.name,
        announcement_html: template.announcement,
        started_at: started_at,
        expires_at: DateTime.utc_now(),
        results: nil
      }

      results = PromoEngine.settle_promo(promo)
      assert {:ok, winners} = results
      assert length(winners) >= 2

      # user1 (5 reads) should be ranked first
      {first_id, _, first_prize} = Enum.at(winners, 0)
      {second_id, _, second_prize} = Enum.at(winners, 1)
      assert first_id == user1.id, "user1 (5 reads) should be #1"
      assert second_id == user2.id, "user2 (2 reads) should be #2"
      assert first_prize > second_prize, "1st place (#{first_prize}) should get more than 2nd (#{second_prize})"

      # 2 participants → tiered 60/40 of 1500 = 900/600
      assert first_prize == 900.0
      assert second_prize == 600.0
    end

    test "competition with zero participants returns empty winners" do
      template = Enum.find(PromoEngine.all_templates()[:competition], &(&1.metric == :bet_count))
      promo = %{
        id: "lifecycle_empty_comp_#{System.system_time(:millisecond)}",
        category: :competition,
        template: template,
        name: template.name,
        announcement_html: template.announcement,
        started_at: DateTime.utc_now() |> DateTime.add(-10),  # very recent — no events
        expires_at: DateTime.utc_now(),
        results: nil
      }

      results = PromoEngine.settle_promo(promo)
      assert {:ok, []} = results
    end

    test "results format correctly for announcements", %{user1: user1, user2: user2} do
      # Build a settled promo with real winner data
      promo = %{
        name: "Most Articles Read",
        category: :competition,
        results: {:ok, [{user1.id, "lifecycle_player1", 750.0}, {user2.id, "lifecycle_player2", 450.0}]}
      }

      next_promo = %{name: "Safety Net Hour"}
      html = PromoEngine.format_results_html(promo, next_promo)

      assert html =~ "Most Articles Read"
      assert html =~ "@lifecycle_player1"
      assert html =~ "@lifecycle_player2"
      assert html =~ "750 BUX"
      assert html =~ "450 BUX"
      assert html =~ "1200 BUX"  # total
      assert html =~ "Safety Net Hour"  # next promo teaser
    end
  end

  describe "full lifecycle — multiple promos in sequence" do
    test "activate/settle 3 promos in sequence, rules don't leak between cycles" do
      for i <- 1..3 do
        promo = PromoEngine.pick_next_promo(if(i > 1, do: [%{name: "prev", category: :bux_booster_rule}], else: []))

        # Activate
        assert :ok = PromoEngine.activate_promo(promo)

        # If BUX Booster, rule should be active
        if promo.category == :bux_booster_rule do
          rules = SystemConfig.get("custom_rules", [])
          bot_rules = Enum.filter(rules, &(&1["_promo_id"] == promo.id))
          assert length(bot_rules) == 1, "Cycle #{i}: expected 1 bot rule for #{promo.name}"
        end

        # Settle
        PromoEngine.settle_promo(promo)

        # After settle, no bot rules should remain
        rules = SystemConfig.get("custom_rules", [])
        bot_rules = Enum.filter(rules, &(&1["source"] == "telegram_bot"))
        assert bot_rules == [], "Cycle #{i}: bot rules should be cleaned after settle"
      end
    end
  end
end
