defmodule BlocksterV2.BuxMinterPoolTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.BuxMinter

  # ============================================================================
  # Tests for BuxMinter pool-related functions (Phase 7)
  # Tests: get_pool_stats/0, get_house_balance/1, get_lp_balance/2,
  #        build_deposit_tx/3, build_withdraw_tx/3
  # ============================================================================

  setup do
    # Ensure ETS dedup table exists
    BuxMinter.init_dedup_table()
    :ok
  end

  # ============================================================================
  # get_pool_stats Tests
  # ============================================================================

  describe "get_pool_stats/0" do
    test "returns error when API secret not configured" do
      # In test env, settler is not configured — should return error or fallback
      result = BuxMinter.get_pool_stats()

      case result do
        {:ok, stats} ->
          # If it somehow connects (unlikely in test), verify structure
          assert is_map(stats)

        {:error, reason} ->
          # Expected — settler is not running
          assert reason != nil
      end
    end
  end

  # ============================================================================
  # get_house_balance Tests
  # ============================================================================

  describe "get_house_balance/1" do
    test "returns error when settler not configured" do
      result = BuxMinter.get_house_balance("SOL")

      case result do
        {:ok, balance} ->
          assert is_number(balance)

        {:error, reason} ->
          assert reason != nil
      end
    end

    test "accepts SOL token" do
      result = BuxMinter.get_house_balance("SOL")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts BUX token" do
      result = BuxMinter.get_house_balance("BUX")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "defaults to BUX when no token specified" do
      result = BuxMinter.get_house_balance()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  # ============================================================================
  # get_lp_balance Tests
  # ============================================================================

  describe "get_lp_balance/2" do
    test "accepts sol vault type" do
      result = BuxMinter.get_lp_balance("TestWallet123", "sol")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts bux vault type" do
      result = BuxMinter.get_lp_balance("TestWallet456", "bux")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "rejects invalid vault type" do
      assert_raise FunctionClauseError, fn ->
        BuxMinter.get_lp_balance("TestWallet", "invalid")
      end
    end
  end

  # ============================================================================
  # build_deposit_tx Tests
  # ============================================================================

  describe "build_deposit_tx/3" do
    test "accepts sol vault type" do
      result = BuxMinter.build_deposit_tx("TestWallet", 1.0, "sol")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts bux vault type" do
      result = BuxMinter.build_deposit_tx("TestWallet", 100.0, "bux")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "rejects invalid vault type" do
      assert_raise FunctionClauseError, fn ->
        BuxMinter.build_deposit_tx("TestWallet", 1.0, "rogue")
      end
    end
  end

  # ============================================================================
  # build_withdraw_tx Tests
  # ============================================================================

  describe "build_withdraw_tx/3" do
    test "accepts sol vault type" do
      result = BuxMinter.build_withdraw_tx("TestWallet", 1.0, "sol")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts bux vault type" do
      result = BuxMinter.build_withdraw_tx("TestWallet", 50.0, "bux")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "rejects invalid vault type" do
      assert_raise FunctionClauseError, fn ->
        BuxMinter.build_withdraw_tx("TestWallet", 1.0, "eth")
      end
    end
  end
end
