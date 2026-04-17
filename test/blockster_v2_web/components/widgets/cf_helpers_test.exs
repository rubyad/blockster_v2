defmodule BlocksterV2Web.Widgets.CfHelpersTest do
  use ExUnit.Case, async: true

  alias BlocksterV2Web.Widgets.CfHelpers

  test "truncate_wallet/1 truncates long wallets" do
    assert CfHelpers.truncate_wallet("7k2abc9fX") == "7k2...9fX"
    assert CfHelpers.truncate_wallet("ABCDEFGHIJKL") == "ABC...JKL"
  end

  test "truncate_wallet/1 handles nil and short strings" do
    assert CfHelpers.truncate_wallet(nil) == "..."
    assert CfHelpers.truncate_wallet("abc") == "abc"
  end

  test "chip_side/1 returns :heads or :tails" do
    assert CfHelpers.chip_side(:h) == :heads
    assert CfHelpers.chip_side("h") == :heads
    assert CfHelpers.chip_side(0) == :heads
    assert CfHelpers.chip_side(:t) == :tails
    assert CfHelpers.chip_side("t") == :tails
    assert CfHelpers.chip_side(1) == :tails
  end

  test "chip_emoji/1 returns rocket or poop" do
    assert CfHelpers.chip_emoji(:heads) == "\u{1F680}"
    assert CfHelpers.chip_emoji(:tails) == "\u{1F4A9}"
  end

  test "matched?/3 checks prediction vs result at index" do
    assert CfHelpers.matched?([:h, :t, :h], [:h, :t, :h], 0)
    assert CfHelpers.matched?([:h, :t, :h], [:h, :t, :h], 1)
    refute CfHelpers.matched?([:h, :t, :h], [:t, :t, :h], 0)
  end

  test "matched?/3 returns false for out-of-bounds" do
    refute CfHelpers.matched?([:h], [:h], 5)
  end

  test "mode_label/1 returns human-readable mode" do
    assert CfHelpers.mode_label(:win_all) == "Win All"
    assert CfHelpers.mode_label(:win_one) == "Win One"
  end

  test "format_sol/1 formats amounts" do
    assert CfHelpers.format_sol(0.5) == "0.50"
    assert CfHelpers.format_sol(1.0) == "1.00"
    assert CfHelpers.format_sol(0.1) == "0.10"
  end

  test "format_net_sol/1 adds +/- prefix" do
    assert CfHelpers.format_net_sol(0.98) == "+0.98"
    assert CfHelpers.format_net_sol(-0.5) == "-0.50"
  end

  test "sol_to_usd/2 converts correctly" do
    assert CfHelpers.sol_to_usd(1.0, 236.0) == 236.0
    assert CfHelpers.sol_to_usd(0.5, 236.0) == 118.0
    assert CfHelpers.sol_to_usd(1.0, nil) == nil
  end

  test "format_usd/1 formats dollar amounts" do
    assert CfHelpers.format_usd(118.0) == "$118.00"
    assert CfHelpers.format_usd(nil) == ""
  end

  test "format_net_usd/1 adds +/- prefix" do
    assert CfHelpers.format_net_usd(231.28) == "+$231.28"
    assert CfHelpers.format_net_usd(-5.0) == "-$5.00"
    assert CfHelpers.format_net_usd(nil) == ""
  end

  test "demo_configs/0 returns 9 entries" do
    assert length(CfHelpers.demo_configs()) == 9
  end

  test "demo_durations/0 returns 9 durations" do
    assert length(CfHelpers.demo_durations()) == 9
  end

  test "format_cf_game/1 formats a game map" do
    game = %{
      type: "win",
      difficulty: 2,
      predictions: [:h, :h],
      results: [:h, :h],
      bet_amount: 0.5,
      payout: 1.98,
      wallet: "7k2abcdefghij9fX",
      created_at: ~U[2026-04-15 02:14:00Z]
    }

    formatted = CfHelpers.format_cf_game(game)

    assert formatted.won == true
    assert formatted.mode == :win_all
    assert formatted.flip_count == 2
    assert formatted.multiplier == 3.96
    assert formatted.net == 1.48
    assert formatted.wallet_short == "7k2...9fX"
    assert formatted.predictions == [:h, :h]
    assert formatted.results == [:h, :h]
  end
end
