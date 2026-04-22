defmodule BlocksterV2Web.FormatHelpersTest do
  @moduledoc """
  Property-style parity test for every `:erlang.float_to_binary` call
  site hardened in PR 1b. The goal: every `format_*` helper must accept
  integer AND float inputs and produce an identical string for the
  integer-valued pair (e.g. `1000` ≡ `1000.0`, `5` ≡ `5.0`).

  The 2026-04-22 bug audit caught a wallet crash where `format_bux/1`
  guarded with `is_float` and blew up when PubSub delivered an integer
  balance. This test pins the contract across the full helper set so
  the same class of bug cannot re-surface silently.
  """

  use ExUnit.Case, async: true

  # A representative set of integer values. For each, the test asserts
  # that `helper.(int)` == `helper.(int * 1.0)` — this is the "property"
  # we care about, since the bug class is "integer input produces
  # different output than the float equivalent".
  @integer_samples [0, 1, 5, 10, 100, 1_000, 10_000, 500_000, 1_000_000]

  # Non-numeric inputs that must not raise. Every helper should return
  # some stable fallback (usually "0" or "—") for these.
  @non_numeric_samples [nil, "garbage", :atom, %{}, []]

  describe "pool_detail_live format helpers" do
    # The helpers are defp's; invoke via the public-facing render path
    # by asserting behaviour via a wrapper module-level private test is
    # impractical without a render test. The parity invariant we test
    # here is on the PUBLIC format helpers exposed by modules we can
    # call directly.
    #
    # This block asserts parity for `BlocksterV2.Shop.Pricing.format_sol/1`
    # and `format_usd/1` — both public + coerced in commit 674e581.
    test "Shop.Pricing.format_sol accepts integer and float with parity" do
      for n <- @integer_samples do
        assert BlocksterV2.Shop.Pricing.format_sol(n) ==
                 BlocksterV2.Shop.Pricing.format_sol(n * 1.0),
               "expected parity at n=#{n}"
      end
    end

    test "Shop.Pricing.format_sol tolerates non-numeric input" do
      for v <- @non_numeric_samples do
        assert BlocksterV2.Shop.Pricing.format_sol(v) == "0.00"
      end
    end

    test "Shop.Pricing.format_usd accepts integer and float with parity" do
      for n <- @integer_samples do
        assert BlocksterV2.Shop.Pricing.format_usd(n) ==
                 BlocksterV2.Shop.Pricing.format_usd(n * 1.0),
               "expected parity at n=#{n}"
      end
    end

    test "Shop.Pricing.format_usd tolerates non-numeric input" do
      for v <- @non_numeric_samples do
        assert BlocksterV2.Shop.Pricing.format_usd(v) == "$0.00"
      end
    end
  end

  describe "pool_components format helpers" do
    test "format_change_pct accepts integer and float with parity" do
      for n <- [-100, -5, 0, 5, 50, 100, 1_000] do
        assert BlocksterV2Web.PoolComponents.format_change_pct(n) ==
                 BlocksterV2Web.PoolComponents.format_change_pct(n * 1.0),
               "expected parity at n=#{n}"
      end
    end

    test "format_number accepts integer and float with parity" do
      for n <- @integer_samples do
        assert BlocksterV2Web.PoolComponents.format_number(n) ==
                 BlocksterV2Web.PoolComponents.format_number(n * 1.0),
               "expected parity at n=#{n}"
      end
    end

    test "format_integer accepts integer and float with parity" do
      for n <- @integer_samples do
        assert BlocksterV2Web.PoolComponents.format_integer(n) ==
                 BlocksterV2Web.PoolComponents.format_integer(n * 1.0),
               "expected parity at n=#{n}"
      end
    end

    test "format_house_edge accepts integer and float with parity" do
      for n <- [0, 1, 2, 5, 10] do
        assert BlocksterV2Web.PoolComponents.format_house_edge(n) ==
                 BlocksterV2Web.PoolComponents.format_house_edge(n * 1.0),
               "expected parity at n=#{n}"
      end
    end

    test "format_win_rate accepts integer bet/win counts" do
      # total_bets: 10, total_wins: 5 (both integer) must match floats
      assert BlocksterV2Web.PoolComponents.format_win_rate(10, 5) ==
               BlocksterV2Web.PoolComponents.format_win_rate(10.0, 5.0)

      assert BlocksterV2Web.PoolComponents.format_win_rate(100, 33) ==
               BlocksterV2Web.PoolComponents.format_win_rate(100.0, 33.0)
    end

    test "format_profit_value returns stable output for integer/float parity" do
      for n <- [-10, -5, -1, 1, 5, 10, 100] do
        assert BlocksterV2Web.PoolComponents.format_profit_value(n) ==
                 BlocksterV2Web.PoolComponents.format_profit_value(n * 1.0),
               "expected parity at n=#{n}"
      end
    end
  end

  describe "member_live format helpers" do
    test "format_referral_number accepts integer and float with parity" do
      for n <- @integer_samples do
        assert BlocksterV2Web.MemberLive.Show.format_referral_number(n) ==
                 BlocksterV2Web.MemberLive.Show.format_referral_number(n * 1.0),
               "expected parity at n=#{n}"
      end
    end

    test "format_multiplier accepts integer and float with parity" do
      for n <- [1, 2, 3, 5, 10, 25, 50, 100, 200] do
        assert BlocksterV2Web.MemberLive.Show.format_multiplier(n) ==
                 BlocksterV2Web.MemberLive.Show.format_multiplier(n * 1.0),
               "expected parity at n=#{n}"
      end
    end

    test "format_multiplier tolerates non-numeric input" do
      for v <- @non_numeric_samples do
        assert BlocksterV2Web.MemberLive.Show.format_multiplier(v) == "0"
      end
    end
  end
end
