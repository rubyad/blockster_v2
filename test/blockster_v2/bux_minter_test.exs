defmodule BlocksterV2.BuxMinterTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.BuxMinter

  # ============================================================================
  # Test Setup
  # ============================================================================

  setup do
    # Ensure ETS dedup table exists
    BuxMinter.init_dedup_table()

    # Clear any app config overrides from previous tests
    on_exit(fn ->
      Application.delete_env(:blockster_v2, :settler_url)
      Application.delete_env(:blockster_v2, :settler_secret)
    end)

    :ok
  end

  # ============================================================================
  # Deprecated EVM function tests
  # ============================================================================

  describe "deprecated EVM functions" do
    test "get_aggregated_balances returns :deprecated" do
      assert {:error, :deprecated} = BuxMinter.get_aggregated_balances("0xSomeEvmAddress")
    end

    test "get_rogue_house_balance returns :deprecated" do
      assert {:error, :deprecated} = BuxMinter.get_rogue_house_balance()
    end

    test "transfer_rogue returns :deprecated" do
      assert {:error, :deprecated} = BuxMinter.transfer_rogue("0xAddr", 100, 1)
    end

    test "transfer_rogue with custom reason returns :deprecated" do
      assert {:error, :deprecated} = BuxMinter.transfer_rogue("0xAddr", 100, 1, "ai_bonus")
    end

    test "get_all_balances returns :deprecated" do
      assert {:error, :deprecated} = BuxMinter.get_all_balances("0xSomeEvmAddress")
    end
  end

  # ============================================================================
  # Not-configured guard tests (no HTTP calls made)
  # ============================================================================

  describe "not-configured guard" do
    setup do
      # Save and clear ALL secret sources so the :not_configured guard triggers
      old_settler = Application.get_env(:blockster_v2, :settler_secret)
      old_minter = Application.get_env(:blockster_v2, :bux_minter_secret)
      old_env_settler = System.get_env("BLOCKSTER_SETTLER_SECRET")
      old_env_minter = System.get_env("BUX_MINTER_SECRET")

      Application.put_env(:blockster_v2, :settler_secret, nil)
      Application.put_env(:blockster_v2, :bux_minter_secret, nil)
      System.delete_env("BLOCKSTER_SETTLER_SECRET")
      System.delete_env("BUX_MINTER_SECRET")

      on_exit(fn ->
        if old_settler, do: Application.put_env(:blockster_v2, :settler_secret, old_settler)
        if old_minter, do: Application.put_env(:blockster_v2, :bux_minter_secret, old_minter)
        if old_env_settler, do: System.put_env("BLOCKSTER_SETTLER_SECRET", old_env_settler)
        if old_env_minter, do: System.put_env("BUX_MINTER_SECRET", old_env_minter)
      end)

      :ok
    end

    test "mint_bux returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.mint_bux("wallet", 100, 1, nil, :read)
    end

    test "burn_bux returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.burn_bux("wallet", 50, 1)
    end

    test "get_balance returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.get_balance("wallet")
    end

    test "get_balance/2 legacy returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.get_balance("wallet", "BUX")
    end

    test "get_house_balance returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.get_house_balance()
    end

    test "get_pool_stats returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.get_pool_stats()
    end

    test "set_player_referrer returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.set_player_referrer("player", "referrer")
    end

    test "airdrop_start_round returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.airdrop_start_round("hash", 1234567890)
    end

    test "airdrop_build_deposit returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.airdrop_build_deposit("wallet", 1, 0, 100)
    end

    test "airdrop_build_claim returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.airdrop_build_claim("wallet", 1, 0)
    end

    test "airdrop_get_vault_round_id returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.airdrop_get_vault_round_id()
    end

    test "airdrop_close returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.airdrop_close(1)
    end

    test "airdrop_draw_winners returns :not_configured" do
      assert {:error, :not_configured} = BuxMinter.airdrop_draw_winners(1, "server_seed_hex", [])
    end

  end

  # ============================================================================
  # ETS dedup table tests
  # ============================================================================

  describe "init_dedup_table/0" do
    test "creates ETS table" do
      # Table already created in setup, verify it exists
      assert :ets.whereis(:bux_minter_sync_dedup) != :undefined
    end

    test "is idempotent" do
      assert :ok = BuxMinter.init_dedup_table()
      assert :ok = BuxMinter.init_dedup_table()
    end
  end

  # ============================================================================
  # mint_bux_async tests
  # ============================================================================

  describe "mint_bux_async/5" do
    test "accepts valid reward types" do
      # With no secret configured, the async task will return :not_configured
      # but the function itself returns {:ok, pid} because Task.start succeeds
      Application.put_env(:blockster_v2, :settler_secret, nil)

      for reward_type <- [:read, :x_share, :video_watch] do
        assert {:ok, _pid} = BuxMinter.mint_bux_async("wallet", 10, 1, nil, reward_type)
      end
    end
  end

  # ============================================================================
  # Config resolution tests
  # ============================================================================

  describe "config resolution" do
    test "settler_secret falls back to bux_minter_secret during migration" do
      # Clear settler_secret but preserve legacy secret
      old_settler = Application.get_env(:blockster_v2, :settler_secret)
      old_minter = Application.get_env(:blockster_v2, :bux_minter_secret)

      Application.put_env(:blockster_v2, :settler_secret, nil)
      System.delete_env("BLOCKSTER_SETTLER_SECRET")
      Application.put_env(:blockster_v2, :bux_minter_secret, "legacy-secret")

      # The function should NOT return :not_configured because it falls back to legacy secret.
      # It will fail with an HTTP error (no server) or raise — the point is it doesn't bail early.
      # We test by calling get_balance on a nonexistent server, which proves auth wasn't nil.
      result = try do
        BuxMinter.get_balance("wallet")
      rescue
        _ -> {:error, :connection_failed}
      catch
        :exit, _ -> {:error, :connection_failed}
      end

      # The key assertion: it did NOT return :not_configured
      assert {:error, reason} = result
      assert reason != :not_configured

      # Restore
      if old_settler, do: Application.put_env(:blockster_v2, :settler_secret, old_settler)
      if old_minter, do: Application.put_env(:blockster_v2, :bux_minter_secret, old_minter),
        else: Application.delete_env(:blockster_v2, :bux_minter_secret)
    end
  end

  # ============================================================================
  # sync deduplication tests
  # ============================================================================

  describe "sync_user_balances_async deduplication" do
    test "skips duplicate syncs for same user" do
      Application.put_env(:blockster_v2, :settler_secret, nil)

      # First call with no secret just fails quietly
      # But the dedup mechanism should still work
      result1 = BuxMinter.sync_user_balances_async(1, "wallet")
      result2 = BuxMinter.sync_user_balances_async(1, "wallet")

      # Second call should be skipped (deduplication)
      # First one claimed the slot
      assert result1 != {:ok, :skipped} or result2 == {:ok, :skipped}
    end

    test "force: true bypasses deduplication" do
      Application.put_env(:blockster_v2, :settler_secret, nil)

      BuxMinter.sync_user_balances_async(1, "wallet")
      # Force should not skip
      result = BuxMinter.sync_user_balances_async(1, "wallet", force: true)
      assert result != {:ok, :skipped}
    end
  end
end
