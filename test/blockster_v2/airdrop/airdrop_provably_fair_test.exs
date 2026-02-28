defmodule BlocksterV2.Airdrop.ProvablyFairTest do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Airdrop
  alias BlocksterV2.ProvablyFair

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
      block_hash = "0x" <> String.duplicate("ab", 32)
      total_entries = 1000

      combined1 = Airdrop.keccak256_combined(server_seed, block_hash)
      combined2 = Airdrop.keccak256_combined(server_seed, block_hash)

      assert combined1 == combined2

      # Derive positions
      positions1 = for i <- 0..32, do: Airdrop.derive_position(combined1, i, total_entries)
      positions2 = for i <- 0..32, do: Airdrop.derive_position(combined2, i, total_entries)

      assert positions1 == positions2
    end

    test "different server seeds produce different winners" do
      seed1 = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      seed2 = "f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5"
      block_hash = "0x" <> String.duplicate("ab", 32)
      total_entries = 1000

      combined1 = Airdrop.keccak256_combined(seed1, block_hash)
      combined2 = Airdrop.keccak256_combined(seed2, block_hash)

      positions1 = for i <- 0..32, do: Airdrop.derive_position(combined1, i, total_entries)
      positions2 = for i <- 0..32, do: Airdrop.derive_position(combined2, i, total_entries)

      refute positions1 == positions2
    end

    test "different block hashes produce different winners" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      hash1 = "0x" <> String.duplicate("ab", 32)
      hash2 = "0x" <> String.duplicate("cd", 32)
      total_entries = 1000

      combined1 = Airdrop.keccak256_combined(server_seed, hash1)
      combined2 = Airdrop.keccak256_combined(server_seed, hash2)

      positions1 = for i <- 0..32, do: Airdrop.derive_position(combined1, i, total_entries)
      positions2 = for i <- 0..32, do: Airdrop.derive_position(combined2, i, total_entries)

      refute positions1 == positions2
    end

    test "positions are within valid range" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      block_hash = "0x" <> String.duplicate("ab", 32)
      total_entries = 500

      combined = Airdrop.keccak256_combined(server_seed, block_hash)

      for i <- 0..32 do
        pos = Airdrop.derive_position(combined, i, total_entries)
        assert pos >= 1, "Position #{pos} should be >= 1"
        assert pos <= total_entries, "Position #{pos} should be <= #{total_entries}"
      end
    end

    test "produces 33 positions" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      block_hash = "0x" <> String.duplicate("ab", 32)
      total_entries = 10000

      combined = Airdrop.keccak256_combined(server_seed, block_hash)
      positions = for i <- 0..32, do: Airdrop.derive_position(combined, i, total_entries)

      assert length(positions) == 33
    end
  end

  # ============================================================================
  # keccak256 Combined Seed
  # ============================================================================

  describe "keccak256_combined/2" do
    test "produces 32-byte binary" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      block_hash = "0x" <> String.duplicate("ab", 32)

      result = Airdrop.keccak256_combined(server_seed, block_hash)
      assert byte_size(result) == 32
    end

    test "handles 0x prefix in block hash" do
      server_seed = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      hash_with_prefix = "0x" <> String.duplicate("ab", 32)
      hash_without_prefix = String.duplicate("ab", 32)

      # Both should produce the same result since decode_hex strips 0x
      result1 = Airdrop.keccak256_combined(server_seed, hash_with_prefix)
      result2 = Airdrop.keccak256_combined(server_seed, hash_without_prefix)

      assert result1 == result2
    end
  end

  # ============================================================================
  # Full Round Verification
  # ============================================================================

  describe "full round provably fair verification" do
    test "commitment published before draw matches revealed seed" do
      # 1. Create round — commitment is published
      {:ok, round} = Airdrop.create_round(~U[2026-04-01 00:00:00Z])
      commitment_before = Airdrop.get_commitment_hash(round.round_id)
      assert commitment_before != nil

      # 2. Add entries
      user = create_user()
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round.round_id)

      # 3. Close round
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))

      # 4. Draw winners
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      # 5. Verify: SHA256(revealed_seed) == commitment published before
      {:ok, data} = Airdrop.get_verification_data(round.round_id)
      assert data.commitment_hash == commitment_before

      computed_commitment = ProvablyFair.generate_commitment(data.server_seed)
      assert computed_commitment == commitment_before
    end

    test "winners can be independently re-derived from verification data" do
      {:ok, round} = Airdrop.create_round(~U[2026-04-01 00:00:00Z])
      user = create_user()
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round.round_id)
      block_hash = "0x" <> String.duplicate("ab", 32)
      {:ok, _} = Airdrop.close_round(round.round_id, block_hash)
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      # Get verification data
      {:ok, data} = Airdrop.get_verification_data(round.round_id)

      # Re-derive winners independently
      combined = Airdrop.keccak256_combined(data.server_seed, data.block_hash_at_close)

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
