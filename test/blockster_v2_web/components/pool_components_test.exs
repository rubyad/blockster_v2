defmodule BlocksterV2Web.PoolComponentsTest do
  use ExUnit.Case, async: true

  alias BlocksterV2Web.PoolComponents

  describe "format_tvl/1" do
    test "formats millions" do
      assert PoolComponents.format_tvl(1_500_000) == "1.50M"
      assert PoolComponents.format_tvl(2_000_000.0) == "2.00M"
    end

    test "formats thousands" do
      assert PoolComponents.format_tvl(1_500) == "1.50k"
      assert PoolComponents.format_tvl(50_000.0) == "50.00k"
    end

    test "formats small numbers" do
      assert PoolComponents.format_tvl(123.45) == "123.45"
      assert PoolComponents.format_tvl(0.5) == "0.50"
    end

    test "formats zero and nil" do
      assert PoolComponents.format_tvl(0) == "0.00"
      assert PoolComponents.format_tvl(nil) == "0.00"
    end
  end

  describe "format_price/1" do
    test "formats to 6 decimal places" do
      assert PoolComponents.format_price(1.000400) == "1.000400"
      assert PoolComponents.format_price(0.999123) == "0.999123"
    end

    test "default for zero/nil" do
      assert PoolComponents.format_price(0) == "1.000000"
      assert PoolComponents.format_price(nil) == "1.000000"
    end
  end

  describe "format_number/1" do
    test "formats millions" do
      assert PoolComponents.format_number(5_000_000) == "5.00M"
    end

    test "formats thousands" do
      assert PoolComponents.format_number(2_500) == "2.50k"
    end

    test "formats small numbers" do
      assert PoolComponents.format_number(42.0) == "42.00"
    end

    test "formats zero/nil" do
      assert PoolComponents.format_number(0) == "0"
      assert PoolComponents.format_number(nil) == "0"
    end
  end

  describe "format_profit_value/1" do
    test "positive profit has + prefix" do
      assert PoolComponents.format_profit_value(1.5) == "+1.5000"
    end

    test "negative profit keeps - prefix" do
      assert PoolComponents.format_profit_value(-0.5) == "-0.5000"
    end

    test "zero returns zero string" do
      assert PoolComponents.format_profit_value(0) == "0.0000"
      assert PoolComponents.format_profit_value(nil) == "0.0000"
    end
  end

  describe "profit_color/1" do
    test "positive is green" do
      assert PoolComponents.profit_color(1.0) == "text-emerald-500"
    end

    test "negative is red" do
      assert PoolComponents.profit_color(-1.0) == "text-red-500"
    end

    test "zero is gray" do
      assert PoolComponents.profit_color(0) == "text-gray-500"
    end
  end

  describe "format_integer/1" do
    test "formats millions" do
      assert PoolComponents.format_integer(5_000_000) == "5.0M"
    end

    test "formats thousands" do
      assert PoolComponents.format_integer(2_500) == "2.5k"
    end

    test "formats small numbers" do
      assert PoolComponents.format_integer(42) == "42"
    end

    test "formats zero/nil" do
      assert PoolComponents.format_integer(0) == "0"
      assert PoolComponents.format_integer(nil) == "0"
    end
  end

  describe "format_win_rate/2" do
    test "calculates win rate percentage" do
      assert PoolComponents.format_win_rate(100, 45) == "45.0%"
    end

    test "handles zero bets" do
      assert PoolComponents.format_win_rate(0, 0) == "0.0%"
    end

    test "handles nil" do
      assert PoolComponents.format_win_rate(nil, nil) == "0.0%"
    end
  end

  describe "get_vault_stat/3" do
    test "returns nested value" do
      stats = %{"sol" => %{"totalBalance" => 100.0, "lpPrice" => 1.0004}}
      assert PoolComponents.get_vault_stat(stats, "sol", "totalBalance") == 100.0
      assert PoolComponents.get_vault_stat(stats, "sol", "lpPrice") == 1.0004
    end

    test "returns 0 for nil stats" do
      assert PoolComponents.get_vault_stat(nil, "sol", "totalBalance") == 0
    end

    test "returns 0 for missing vault" do
      stats = %{"sol" => %{"totalBalance" => 100.0}}
      assert PoolComponents.get_vault_stat(stats, "bux", "totalBalance") == 0
    end

    test "returns 0 for missing key" do
      stats = %{"sol" => %{"totalBalance" => 100.0}}
      assert PoolComponents.get_vault_stat(stats, "sol", "missing") == 0
    end
  end
end
