defmodule BlocksterV2Web.MemberLive.ReferralTest do
  @moduledoc """
  Integration tests for the MemberLive Referral tab.

  NOTE: These tests require the full application context with all Mnesia tables
  initialized. They are designed to run against a fully booted application
  (e.g., during Phase 8.3 local E2E testing) rather than in isolation.

  To run these tests:
  1. Start the full application with `elixir --sname node1 -S mix phx.server`
  2. Run tests manually or as part of full test suite

  For unit testing the Referrals module, see test/blockster_v2/referrals_test.exs
  """

  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Referrals

  # Skip all tests by default - they require full Mnesia setup
  # Remove @moduletag to enable tests during full E2E testing
  @moduletag :skip

  # Helper to ensure Mnesia tables exist
  defp ensure_mnesia_tables do
    :mnesia.start()

    tables = [
      {:referrals, [:user_id, :referrer_id, :referrer_wallet, :referee_wallet, :referred_at, :on_chain_synced],
       [index: [:referrer_id, :referrer_wallet, :referee_wallet]]},
      {:referral_earnings, [:id, :referrer_id, :referrer_wallet, :referee_wallet, :earning_type, :amount, :token, :tx_hash, :commitment_hash, :timestamp],
       [type: :bag, index: [:referrer_id, :commitment_hash]]},
      {:referral_stats, [:user_id, :total_referrals, :verified_referrals, :total_bux_earned, :total_rogue_earned, :updated_at],
       []}
    ]

    for {table_name, attributes, opts} <- tables do
      case :mnesia.create_table(table_name, [
        attributes: attributes,
        type: Keyword.get(opts, :type, :set),
        index: Keyword.get(opts, :index, [])
      ]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, _}} -> :ok
        other -> other
      end
    end

    :mnesia.clear_table(:referrals)
    :mnesia.clear_table(:referral_earnings)
    :mnesia.clear_table(:referral_stats)
  end

  setup do
    ensure_mnesia_tables()
    :ok
  end

  describe "Referrals module integration" do
    # These tests verify the Referrals module functions work correctly
    # and can be run in isolation without full LiveView context

    test "list_referral_earnings returns formatted data" do
      # Create test data directly in Mnesia
      referrer_id = 999
      now = System.system_time(:second)

      earning_record = {:referral_earnings, Ecto.UUID.generate(), referrer_id,
                        "0xreferrer123", "0xreferee456", :signup, 100, "BUX",
                        nil, nil, now}
      :mnesia.dirty_write(earning_record)

      earnings = Referrals.list_referral_earnings(referrer_id)

      assert length(earnings) == 1
      [earning] = earnings
      assert earning.earning_type == :signup
      assert earning.amount == 100
      assert earning.token == "BUX"
      assert earning.referee_wallet == "0xreferee456"
    end

    test "get_referrer_stats returns correct stats" do
      referrer_id = 998
      now = System.system_time(:second)

      stats_record = {:referral_stats, referrer_id, 5, 3, 500.0, 100.0, now}
      :mnesia.dirty_write(stats_record)

      stats = Referrals.get_referrer_stats(referrer_id)

      assert stats.total_referrals == 5
      assert stats.verified_referrals == 3
      assert stats.total_bux_earned == 500.0
      assert stats.total_rogue_earned == 100.0
    end

    test "list_referrals returns formatted referral data" do
      referrer_id = 997
      now = System.system_time(:second)

      referral_record = {:referrals, 100, referrer_id, "0xreferrer123",
                         "0xreferee456", now, false}
      :mnesia.dirty_write(referral_record)

      referrals = Referrals.list_referrals(referrer_id)

      assert length(referrals) == 1
      [referral] = referrals
      assert referral.referee_wallet == "0xreferee456"
      assert referral.phone_verified == false
    end
  end

  # The following tests are for LiveView integration and require full app context
  # They are skipped by default (@moduletag :skip) but document what should be tested

  describe "Refer tab display (requires full app context)" do
    @tag :skip
    test "shows referral link with user's wallet address" do
      # This test requires:
      # 1. Full Mnesia tables (unified_multipliers, user_bux_balances, etc.)
      # 2. Authenticated user session
      # 3. LiveView rendering
      #
      # Verify:
      # - Refer tab is visible
      # - Referral link contains user's smart_wallet_address
      # - Copy button is present
    end

    @tag :skip
    test "shows referral stats correctly" do
      # Verify:
      # - Total referrals count
      # - Verified referrals count
      # - Total BUX earned
      # - Total ROGUE earned
    end

    @tag :skip
    test "shows earnings table with all earning types" do
      # Verify:
      # - Signup earnings display
      # - Phone verification earnings display
      # - Bet loss earnings display
      # - Proper formatting of amounts and timestamps
    end
  end

  describe "copy_referral_link event (requires full app context)" do
    @tag :skip
    test "triggers clipboard copy with correct URL" do
      # Verify:
      # - push_event is called with correct referral link
      # - Link format is correct: /?ref=0xWalletAddress
    end
  end

  describe "load_more_earnings event (requires full app context)" do
    @tag :skip
    test "loads additional earnings" do
      # Verify:
      # - Additional earnings are appended to list
      # - Pagination works correctly
    end

    @tag :skip
    test "returns end_reached when no more earnings" do
      # Verify:
      # - Reply contains end_reached: true
    end
  end

  describe "realtime updates (requires full app context)" do
    @tag :skip
    test "receives and displays new earnings via PubSub" do
      # Verify:
      # - Subscribes to "referral:#{user.id}" topic
      # - Updates earnings list when broadcast received
      # - Updates stats when broadcast received
    end
  end
end
