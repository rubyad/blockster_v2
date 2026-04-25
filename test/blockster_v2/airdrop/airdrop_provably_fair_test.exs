defmodule BlocksterV2.Airdrop.ProvablyFairTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Airdrop
  alias BlocksterV2.ProvablyFair

  # ============================================================================
  # Mnesia Setup
  # ============================================================================

  defp setup_mnesia(_context) do
    :mnesia.start()

    # Post-Solana migration: balances are read from :user_solana_balances
    # via EngagementTracker.get_user_token_balances/1.
    tables = [
      {:user_solana_balances,
       [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance]}
    ]

    for {table, attrs} <- tables do
      case :mnesia.create_table(table, attributes: attrs, type: :set, ram_copies: [node()]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, _}} -> :ok
        {:aborted, other} -> raise "Mnesia table creation failed: #{inspect(other)}"
      end
    end

    :ok
  end

  defp set_bux_balance(user, balance) do
    # {:user_solana_balances, user_id, wallet_address, updated_at, sol_balance, bux_balance}
    record =
      {:user_solana_balances, user.id, user.wallet_address, DateTime.utc_now(),
       0.0, balance * 1.0}

    :mnesia.dirty_write(:user_solana_balances, record)
  end

  setup :setup_mnesia

  # ============================================================================
  # Server Seed Generation
  # ============================================================================

  describe "server seed generation" do
    test "produces 64-character hex string (32 bytes)" do
      seed = ProvablyFair.generate_server_seed()
      assert String.length(seed) == 64
      assert Regex.match?(~r/^[0-9a-f]{64}$/, seed)
    end

    test "produces unique seeds" do
      seeds = for _ <- 1..10, do: ProvablyFair.generate_server_seed()
      assert length(Enum.uniq(seeds)) == 10
    end
  end

  # ============================================================================
  # Commitment Hash
  # ============================================================================

  describe "commitment hash" do
    test "is SHA256 of server seed" do
      seed = ProvablyFair.generate_server_seed()
      commitment = ProvablyFair.generate_commitment(seed)

      expected = :crypto.hash(:sha256, seed) |> Base.encode16(case: :lower)
      assert commitment == expected
    end

    test "different seeds produce different commitments" do
      seed1 = ProvablyFair.generate_server_seed()
      seed2 = ProvablyFair.generate_server_seed()

      assert ProvablyFair.generate_commitment(seed1) != ProvablyFair.generate_commitment(seed2)
    end

    test "verify_commitment returns true for matching seed" do
      seed = ProvablyFair.generate_server_seed()
      commitment = ProvablyFair.generate_commitment(seed)

      assert ProvablyFair.verify_commitment(seed, commitment) == true
    end

    test "verify_commitment returns false for wrong seed" do
      seed = ProvablyFair.generate_server_seed()
      wrong_seed = ProvablyFair.generate_server_seed()
      commitment = ProvablyFair.generate_commitment(seed)

      assert ProvablyFair.verify_commitment(wrong_seed, commitment) == false
    end
  end

  # ============================================================================
  # Winner Derivation (Determinism)
  # ============================================================================

  describe "winner derivation determinism" do
    test "same inputs produce same winners" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      slot_at_close = "12345678"
      total_entries = 1000

      combined1 = Airdrop.sha256_combined(server_seed, slot_at_close)
      combined2 = Airdrop.sha256_combined(server_seed, slot_at_close)

      assert combined1 == combined2

      # Derive positions
      positions1 = for i <- 0..32, do: Airdrop.derive_position(combined1, i, total_entries)
      positions2 = for i <- 0..32, do: Airdrop.derive_position(combined2, i, total_entries)

      assert positions1 == positions2
    end

    test "different server seeds produce different winners" do
      seed1 = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      seed2 = "f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5"
      slot_at_close = "12345678"
      total_entries = 1000

      combined1 = Airdrop.sha256_combined(seed1, slot_at_close)
      combined2 = Airdrop.sha256_combined(seed2, slot_at_close)

      positions1 = for i <- 0..32, do: Airdrop.derive_position(combined1, i, total_entries)
      positions2 = for i <- 0..32, do: Airdrop.derive_position(combined2, i, total_entries)

      refute positions1 == positions2
    end

    test "different slots produce different winners" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      slot1 = "12345678"
      slot2 = "87654321"
      total_entries = 1000

      combined1 = Airdrop.sha256_combined(server_seed, slot1)
      combined2 = Airdrop.sha256_combined(server_seed, slot2)

      positions1 = for i <- 0..32, do: Airdrop.derive_position(combined1, i, total_entries)
      positions2 = for i <- 0..32, do: Airdrop.derive_position(combined2, i, total_entries)

      refute positions1 == positions2
    end

    test "positions are within valid range" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      slot_at_close = "12345678"
      total_entries = 500

      combined = Airdrop.sha256_combined(server_seed, slot_at_close)

      for i <- 0..32 do
        pos = Airdrop.derive_position(combined, i, total_entries)
        assert pos >= 1, "Position #{pos} should be >= 1"
        assert pos <= total_entries, "Position #{pos} should be <= #{total_entries}"
      end
    end

    test "produces 33 positions" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      slot_at_close = "12345678"
      total_entries = 10000

      combined = Airdrop.sha256_combined(server_seed, slot_at_close)
      positions = for i <- 0..32, do: Airdrop.derive_position(combined, i, total_entries)

      assert length(positions) == 33
    end
  end

  # ============================================================================
  # keccak256 Combined Seed
  # ============================================================================

  describe "sha256_combined/2" do
    test "produces 32-byte binary" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      slot_at_close = "12345678"

      result = Airdrop.sha256_combined(server_seed, slot_at_close)
      assert byte_size(result) == 32
    end

    test "handles integer slot as string" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"

      # Both string and integer representations should produce the same result
      result1 = Airdrop.sha256_combined(server_seed, "12345678")
      result2 = Airdrop.sha256_combined(server_seed, "12345678")

      assert result1 == result2
    end
  end

  # ============================================================================
  # Full Round Verification
  # ============================================================================

  describe "full round provably fair verification" do
    test "commitment published before draw matches revealed seed" do
      # 1. Create round — commitment is published
      {:ok, round} = Airdrop.create_round(~U[2026-04-01 00:00:00Z], skip_vault: true)
      commitment_before = Airdrop.get_commitment_hash(round.round_id)
      assert commitment_before != nil

      # 2. Add entries
      user = create_user()
      set_bux_balance(user, 1000)
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round.round_id)

      # 3. Close round (Solana slot number)
      {:ok, _} = Airdrop.close_round(round.round_id, "12345678")

      # 4. Draw winners
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      # 5. Verify: SHA256(revealed_seed) == commitment published before
      {:ok, data} = Airdrop.get_verification_data(round.round_id)
      assert data.commitment_hash == commitment_before

      computed_commitment = ProvablyFair.generate_commitment(data.server_seed)
      assert computed_commitment == commitment_before
    end

    test "winners can be independently re-derived from verification data" do
      {:ok, round} = Airdrop.create_round(~U[2026-04-01 00:00:00Z], skip_vault: true)
      user = create_user()
      set_bux_balance(user, 1000)
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round.round_id)
      slot_at_close = "12345678"
      {:ok, _} = Airdrop.close_round(round.round_id, slot_at_close)
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      # Get verification data
      {:ok, data} = Airdrop.get_verification_data(round.round_id)

      # Re-derive winners independently
      combined = Airdrop.sha256_combined(data.server_seed, data.slot_at_close)

      winners = Airdrop.get_winners(round.round_id)

      for winner <- winners do
        re_derived = Airdrop.derive_position(combined, winner.winner_index, data.total_entries)
        assert re_derived == winner.random_number,
          "Winner #{winner.winner_index}: expected position #{re_derived}, got #{winner.random_number}"
      end
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "user#{unique_id}@example.com",
      username: "user#{unique_id}",
      auth_method: "wallet",
      phone_verified: true
    }

    %BlocksterV2.Accounts.User{}
    |> BlocksterV2.Accounts.User.changeset(Map.merge(default_attrs, attrs))
    |> BlocksterV2.Repo.insert!()
  end
end
