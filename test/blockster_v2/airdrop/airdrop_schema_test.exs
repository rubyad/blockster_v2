defmodule BlocksterV2.Airdrop.SchemaTest do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Airdrop.{Round, Entry, Winner}

  # ============================================================================
  # Round Changeset Tests
  # ============================================================================

  describe "Round changeset" do
    test "valid changeset with required fields" do
      attrs = %{
        round_id: 1,
        status: "open",
        end_time: ~U[2026-03-01 00:00:00Z],
        commitment_hash: "abc123def456"
      }

      changeset = Round.changeset(%Round{}, attrs)
      assert changeset.valid?
    end

    test "invalid without round_id" do
      attrs = %{status: "open", end_time: ~U[2026-03-01 00:00:00Z], commitment_hash: "abc"}
      changeset = Round.changeset(%Round{}, attrs)
      refute changeset.valid?
      assert %{round_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without status" do
      attrs = %{round_id: 1, end_time: ~U[2026-03-01 00:00:00Z], commitment_hash: "abc", status: nil}
      changeset = Round.changeset(%Round{}, attrs)
      refute changeset.valid?
      assert %{status: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without end_time" do
      attrs = %{round_id: 1, status: "open", commitment_hash: "abc"}
      changeset = Round.changeset(%Round{}, attrs)
      refute changeset.valid?
      assert %{end_time: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without commitment_hash" do
      attrs = %{round_id: 1, status: "open", end_time: ~U[2026-03-01 00:00:00Z]}
      changeset = Round.changeset(%Round{}, attrs)
      refute changeset.valid?
      assert %{commitment_hash: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid with bad status value" do
      attrs = %{
        round_id: 1,
        status: "invalid_status",
        end_time: ~U[2026-03-01 00:00:00Z],
        commitment_hash: "abc"
      }

      changeset = Round.changeset(%Round{}, attrs)
      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts valid status values" do
      base = %{round_id: 1, end_time: ~U[2026-03-01 00:00:00Z], commitment_hash: "abc"}

      for status <- ["pending", "open", "closed", "drawn"] do
        changeset = Round.changeset(%Round{}, Map.put(base, :status, status))
        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end

    test "accepts optional fields" do
      attrs = %{
        round_id: 1,
        status: "open",
        end_time: ~U[2026-03-01 00:00:00Z],
        commitment_hash: "abc",
        server_seed: "seed123",
        vault_address: "0x1234",
        prize_pool_address: "0x5678",
        start_round_tx: "0xtx1"
      }

      changeset = Round.changeset(%Round{}, attrs)
      assert changeset.valid?
    end

    test "close_changeset requires status and block_hash" do
      round = %Round{status: "open"}
      changeset = Round.close_changeset(round, %{status: "closed", block_hash_at_close: "0xhash"})
      assert changeset.valid?
    end

    test "close_changeset rejects missing block_hash" do
      round = %Round{status: "open"}
      changeset = Round.close_changeset(round, %{status: "closed"})
      refute changeset.valid?
      assert %{block_hash_at_close: ["can't be blank"]} = errors_on(changeset)
    end

    test "draw_changeset requires status" do
      round = %Round{status: "closed"}
      changeset = Round.draw_changeset(round, %{status: "drawn"})
      assert changeset.valid?
    end

    test "unique round_id constraint" do
      attrs = %{
        round_id: 1,
        status: "open",
        end_time: ~U[2026-03-01 00:00:00Z],
        commitment_hash: "abc"
      }

      assert {:ok, _} = %Round{} |> Round.changeset(attrs) |> Repo.insert()
      assert {:error, changeset} = %Round{} |> Round.changeset(attrs) |> Repo.insert()
      assert %{round_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  # ============================================================================
  # Entry Changeset Tests
  # ============================================================================

  describe "Entry changeset" do
    setup do
      user = create_user()
      %{user: user}
    end

    test "valid changeset with required fields", %{user: user} do
      attrs = %{
        user_id: user.id,
        round_id: 1,
        wallet_address: "0x1234567890abcdef",
        amount: 100,
        start_position: 1,
        end_position: 100
      }

      changeset = Entry.changeset(%Entry{}, attrs)
      assert changeset.valid?
    end

    test "invalid without user_id" do
      attrs = %{round_id: 1, wallet_address: "0x1234", amount: 100, start_position: 1, end_position: 100}
      changeset = Entry.changeset(%Entry{}, attrs)
      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without wallet_address", %{user: user} do
      attrs = %{user_id: user.id, round_id: 1, amount: 100, start_position: 1, end_position: 100}
      changeset = Entry.changeset(%Entry{}, attrs)
      refute changeset.valid?
      assert %{wallet_address: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates amount > 0", %{user: user} do
      base = %{user_id: user.id, round_id: 1, wallet_address: "0x1234", start_position: 1, end_position: 1}

      changeset = Entry.changeset(%Entry{}, Map.put(base, :amount, 0))
      refute changeset.valid?
      assert %{amount: ["must be greater than 0"]} = errors_on(changeset)

      changeset = Entry.changeset(%Entry{}, Map.put(base, :amount, -5))
      refute changeset.valid?

      changeset = Entry.changeset(%Entry{}, Map.put(base, :amount, 1))
      assert changeset.valid?
    end

    test "validates positions > 0", %{user: user} do
      base = %{user_id: user.id, round_id: 1, wallet_address: "0x1234", amount: 10}

      changeset = Entry.changeset(%Entry{}, Map.merge(base, %{start_position: 0, end_position: 10}))
      refute changeset.valid?

      changeset = Entry.changeset(%Entry{}, Map.merge(base, %{start_position: 1, end_position: 0}))
      refute changeset.valid?
    end

    test "accepts optional fields", %{user: user} do
      attrs = %{
        user_id: user.id,
        round_id: 1,
        wallet_address: "0x1234",
        amount: 50,
        start_position: 1,
        end_position: 50,
        external_wallet: "0xexternal",
        deposit_tx: "0xtxhash"
      }

      changeset = Entry.changeset(%Entry{}, attrs)
      assert changeset.valid?
    end
  end

  # ============================================================================
  # Winner Changeset Tests
  # ============================================================================

  describe "Winner changeset" do
    test "valid changeset with required fields" do
      attrs = %{
        round_id: 1,
        winner_index: 0,
        random_number: 42,
        wallet_address: "0x1234",
        deposit_start: 1,
        deposit_end: 100,
        deposit_amount: 100,
        prize_usd: 25_000,
        prize_usdt: 250_000_000
      }

      changeset = Winner.changeset(%Winner{}, attrs)
      assert changeset.valid?
    end

    test "validates winner_index 0-32" do
      base = %{
        round_id: 1, random_number: 42, wallet_address: "0x1234",
        deposit_start: 1, deposit_end: 100, deposit_amount: 100,
        prize_usd: 5_000, prize_usdt: 50_000_000
      }

      # Valid range
      for i <- [0, 1, 16, 32] do
        changeset = Winner.changeset(%Winner{}, Map.put(base, :winner_index, i))
        assert changeset.valid?, "Expected winner_index #{i} to be valid"
      end

      # Invalid
      changeset = Winner.changeset(%Winner{}, Map.put(base, :winner_index, -1))
      refute changeset.valid?

      changeset = Winner.changeset(%Winner{}, Map.put(base, :winner_index, 33))
      refute changeset.valid?
    end

    test "validates random_number > 0" do
      base = %{
        round_id: 1, winner_index: 0, wallet_address: "0x1234",
        deposit_start: 1, deposit_end: 100, deposit_amount: 100,
        prize_usd: 25_000, prize_usdt: 250_000_000
      }

      changeset = Winner.changeset(%Winner{}, Map.put(base, :random_number, 0))
      refute changeset.valid?

      changeset = Winner.changeset(%Winner{}, Map.put(base, :random_number, 1))
      assert changeset.valid?
    end

    test "validates prize amounts > 0" do
      base = %{
        round_id: 1, winner_index: 0, random_number: 42, wallet_address: "0x1234",
        deposit_start: 1, deposit_end: 100, deposit_amount: 100
      }

      changeset = Winner.changeset(%Winner{}, Map.merge(base, %{prize_usd: 0, prize_usdt: 50_000_000}))
      refute changeset.valid?

      changeset = Winner.changeset(%Winner{}, Map.merge(base, %{prize_usd: 5_000, prize_usdt: 0}))
      refute changeset.valid?
    end

    test "unique constraint on round_id + winner_index" do
      attrs = %{
        round_id: 1,
        winner_index: 0,
        random_number: 42,
        wallet_address: "0x1234",
        deposit_start: 1,
        deposit_end: 100,
        deposit_amount: 100,
        prize_usd: 25_000,
        prize_usdt: 250_000_000
      }

      assert {:ok, _} = %Winner{} |> Winner.changeset(attrs) |> Repo.insert()
      assert {:error, changeset} = %Winner{} |> Winner.changeset(attrs) |> Repo.insert()
      assert %{round_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "claim_changeset requires all claim fields" do
      winner = %Winner{}

      changeset = Winner.claim_changeset(winner, %{claimed: true, claim_tx: "0xtx", claim_wallet: "0xwallet"})
      assert changeset.valid?

      changeset = Winner.claim_changeset(winner, %{claimed: true})
      refute changeset.valid?
      assert %{claim_tx: ["can't be blank"], claim_wallet: ["can't be blank"]} = errors_on(changeset)
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "user#{unique_id}@example.com",
      username: "user#{unique_id}",
      auth_method: "wallet"
    }

    %BlocksterV2.Accounts.User{}
    |> BlocksterV2.Accounts.User.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end
end
