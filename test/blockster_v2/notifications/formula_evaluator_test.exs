defmodule BlocksterV2.Notifications.FormulaEvaluatorTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.Notifications.FormulaEvaluator

  # ============ Basic Arithmetic ============

  describe "basic arithmetic" do
    test "evaluates a plain number" do
      assert {:ok, 100.0} = FormulaEvaluator.evaluate("100")
    end

    test "evaluates addition" do
      assert {:ok, 5.0} = FormulaEvaluator.evaluate("2 + 3")
    end

    test "evaluates subtraction" do
      assert {:ok, 6.0} = FormulaEvaluator.evaluate("10 - 4")
    end

    test "evaluates multiplication" do
      assert {:ok, 21.0} = FormulaEvaluator.evaluate("3 * 7")
    end

    test "evaluates division" do
      assert {:ok, 5.0} = FormulaEvaluator.evaluate("20 / 4")
    end

    test "respects operator precedence (multiply before add)" do
      assert {:ok, 14.0} = FormulaEvaluator.evaluate("2 + 3 * 4")
    end

    test "parentheses override precedence" do
      assert {:ok, 20.0} = FormulaEvaluator.evaluate("(2 + 3) * 4")
    end

    test "handles float division" do
      {:ok, result} = FormulaEvaluator.evaluate("10 / 3")
      assert_in_delta result, 3.333, 0.01
    end

    test "handles decimal numbers" do
      assert {:ok, 50.0} = FormulaEvaluator.evaluate("0.5 * 100")
    end

    test "handles negative via unary minus" do
      assert {:ok, -10.0} = FormulaEvaluator.evaluate("-10")
    end

    test "handles negative in expression" do
      assert {:ok, -7.0} = FormulaEvaluator.evaluate("3 + -10")
    end
  end

  # ============ Variable Substitution ============

  describe "variable substitution" do
    test "simple variable multiplication" do
      assert {:ok, 50.0} = FormulaEvaluator.evaluate("total_bets * 10", %{"total_bets" => 5})
    end

    test "two variables in division" do
      assert {:ok, 50.0} = FormulaEvaluator.evaluate(
        "bux_total_wagered / total_bets",
        %{"bux_total_wagered" => 1000, "total_bets" => 20}
      )
    end

    test "negative variable for cashback calculation" do
      assert {:ok, 50.0} = FormulaEvaluator.evaluate(
        "bux_net_pnl * -0.1",
        %{"bux_net_pnl" => -500}
      )
    end

    test "balance variable" do
      assert {:ok, 20.0} = FormulaEvaluator.evaluate(
        "rogue_balance * 0.0001",
        %{"rogue_balance" => 200000}
      )
    end

    test "missing variable returns error" do
      assert :error = FormulaEvaluator.evaluate("missing_var * 10", %{})
    end

    test "variable with zero value works" do
      assert {:ok, 0.0} = FormulaEvaluator.evaluate("total_bets * 10", %{"total_bets" => 0})
    end
  end

  # ============ Functions ============

  describe "functions" do
    test "random returns value in range" do
      {:ok, result} = FormulaEvaluator.evaluate("random(100, 500)")
      assert result >= 100 and result <= 500
    end

    test "random produces varying results" do
      results = for _ <- 1..20, do: elem(FormulaEvaluator.evaluate("random(1, 100)"), 1)
      # Not all the same (statistical — extremely unlikely for 20 trials in 1..100)
      refute Enum.count(Enum.uniq(results)) == 1
    end

    test "random with min == max returns that value" do
      assert {:ok, 10.0} = FormulaEvaluator.evaluate("random(10, 10)")
    end

    test "max returns larger value" do
      assert {:ok, 7.0} = FormulaEvaluator.evaluate("max(3, 7)")
    end

    test "min returns smaller value" do
      assert {:ok, 3.0} = FormulaEvaluator.evaluate("min(3, 7)")
    end

    test "max with variable" do
      assert {:ok, 10.0} = FormulaEvaluator.evaluate("max(total_bets, 10)", %{"total_bets" => 5})
    end

    test "min with variable" do
      assert {:ok, 5.0} = FormulaEvaluator.evaluate("min(total_bets, 10)", %{"total_bets" => 5})
    end

    test "nested function calls" do
      {:ok, result} = FormulaEvaluator.evaluate("max(random(1, 5), 3)")
      assert result >= 3 and result <= 5
    end
  end

  # ============ Complex Expressions ============

  describe "complex expressions" do
    test "average loss per bet" do
      {:ok, result} = FormulaEvaluator.evaluate(
        "(bux_total_wagered - bux_total_winnings) / total_bets",
        %{"bux_total_wagered" => 1000, "bux_total_winnings" => 500, "total_bets" => 10}
      )
      assert result == 50.0
    end

    test "base random plus balance bonus" do
      {:ok, result} = FormulaEvaluator.evaluate(
        "random(100, 500) + rogue_balance * 0.00001",
        %{"rogue_balance" => 1_000_000}
      )
      # random gives 100-500, balance bonus gives 10, so total 110-510
      assert result >= 110 and result <= 510
    end

    test "randomized scaling" do
      {:ok, result} = FormulaEvaluator.evaluate(
        "random(1, 3) * total_bets",
        %{"total_bets" => 10}
      )
      assert result >= 10 and result <= 30
    end

    test "dynamic interval formula" do
      {:ok, result} = FormulaEvaluator.evaluate(
        "max(3, 20 - bux_win_rate / 5)",
        %{"bux_win_rate" => 50.0}
      )
      # 20 - 50/5 = 20 - 10 = 10, max(3, 10) = 10
      assert result == 10.0
    end

    test "multi-balance formula" do
      {:ok, result} = FormulaEvaluator.evaluate(
        "bux_balance * 0.001 + rogue_balance * 0.0001",
        %{"bux_balance" => 10000.0, "rogue_balance" => 100000.0}
      )
      # 10000 * 0.001 + 100000 * 0.0001 = 10 + 10 = 20
      assert result == 20.0
    end
  end

  # ============ Safety / Edge Cases ============

  describe "safety and edge cases" do
    test "division by zero returns error" do
      assert :error = FormulaEvaluator.evaluate("100 / 0")
    end

    test "division by zero via variable returns error" do
      assert :error = FormulaEvaluator.evaluate("100 / total_bets", %{"total_bets" => 0})
    end

    test "empty string returns error" do
      assert :error = FormulaEvaluator.evaluate("")
    end

    test "nil returns error" do
      assert :error = FormulaEvaluator.evaluate(nil)
    end

    test "invalid chars rejected" do
      assert :error = FormulaEvaluator.evaluate("system('rm -rf /')")
    end

    test "code injection rejected" do
      assert :error = FormulaEvaluator.evaluate("Code.eval_string(\"IO.puts\")")
    end

    test "deeply nested parentheses work" do
      assert {:ok, 3.0} = FormulaEvaluator.evaluate("((((1 + 2))))")
    end

    test "very large result still returns" do
      {:ok, result} = FormulaEvaluator.evaluate("999999 * 999999")
      assert result > 0
    end

    test "whitespace variations handled" do
      assert {:ok, 5.0} = FormulaEvaluator.evaluate("  2  +  3  ")
    end

    test "numeric input passes through" do
      assert {:ok, 42.0} = FormulaEvaluator.evaluate(42)
    end
  end
end
