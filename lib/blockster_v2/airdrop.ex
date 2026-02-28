defmodule BlocksterV2.Airdrop do
  @moduledoc """
  Context module for the BUX airdrop system.

  Manages rounds, entries (BUX redemptions), winner selection, and prize claims.
  Uses provably fair commit-reveal pattern adapted from BUX Booster.
  """

  require Logger
  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.Airdrop.{Round, Entry, Winner}
  alias BlocksterV2.ProvablyFair

  @num_winners 33

  # Prize structure in USD cents: 1st=$0.65, 2nd=$0.40, 3rd=$0.35, 4th-33rd=$0.12
  # Total: $5.00 (test pool). Scale back up for production.
  @prize_structure %{
    0 => 65,
    1 => 40,
    2 => 35
  }
  @default_prize_usd 12

  # USDT has 6 decimals, so $250 = 250_000_000 micro-USDT
  @usdt_decimals 1_000_000

  # ============================================================================
  # Round Management
  # ============================================================================

  @doc """
  Creates a new airdrop round with provably fair commitment.

  Generates a server seed, computes SHA256 commitment hash, and stores
  the round. The server seed is hidden until the draw.
  """
  def create_round(end_time, opts \\ []) do
    server_seed = ProvablyFair.generate_server_seed()
    commitment_hash = ProvablyFair.generate_commitment(server_seed)

    next_round_id = get_next_round_id()

    # Start on-chain round on AirdropVault (publishes commitment for provable fairness)
    end_time_unix = DateTime.to_unix(end_time)
    start_round_tx =
      case BlocksterV2.BuxMinter.airdrop_start_round(commitment_hash, end_time_unix) do
        {:ok, response} ->
          Logger.info("[Airdrop] On-chain round started: #{inspect(response)}")
          response["transactionHash"]

        {:error, reason} ->
          Logger.warning("[Airdrop] On-chain startRound failed (#{inspect(reason)}), proceeding with DB-only round")
          nil
      end

    attrs = %{
      round_id: next_round_id,
      status: "open",
      end_time: end_time,
      server_seed: server_seed,
      commitment_hash: commitment_hash,
      start_round_tx: start_round_tx,
      vault_address: Keyword.get(opts, :vault_address),
      prize_pool_address: Keyword.get(opts, :prize_pool_address)
    }

    case %Round{}
         |> Round.changeset(attrs)
         |> Repo.insert() do
      {:ok, round} = result ->
        BlocksterV2.Airdrop.Settler.notify_round_created(round.round_id, round.end_time)
        result

      error ->
        error
    end
  end

  @doc """
  Returns the most recent active round (open, closed, or drawn), or nil if none.
  """
  def get_current_round do
    Round
    |> where([r], r.status in ["open", "closed", "drawn"])
    |> order_by([r], desc: r.round_id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets a round by its round_id.
  """
  def get_round(round_id) do
    Repo.get_by(Round, round_id: round_id)
  end

  @doc """
  Returns drawn rounds ordered by most recent.
  """
  def get_past_rounds do
    Round
    |> where([r], r.status == "drawn")
    |> order_by([r], desc: r.round_id)
    |> Repo.all()
  end

  @doc """
  Closes the airdrop round — stops deposits, records block hash.
  """
  def close_round(round_id, block_hash_at_close, opts \\ []) do
    case get_round(round_id) do
      nil ->
        {:error, :round_not_found}

      %Round{status: "open"} = round ->
        round
        |> Round.close_changeset(%{
          status: "closed",
          block_hash_at_close: block_hash_at_close,
          close_tx: Keyword.get(opts, :close_tx)
        })
        |> Repo.update()

      %Round{status: status} ->
        {:error, {:invalid_status, status}}
    end
  end

  @doc """
  Draws winners for a closed round using provably fair algorithm.

  The winner selection mirrors the on-chain algorithm:
  1. combinedSeed = keccak256(serverSeed | blockHashAtClose)
  2. For each winner i: position = hash(combinedSeed, i) mod totalEntries + 1
  3. Find the deposit that contains that position
  """
  def draw_winners(round_id, opts \\ []) do
    case get_round(round_id) do
      nil ->
        {:error, :round_not_found}

      %Round{status: "closed"} = round ->
        entries = list_entries(round_id)

        if entries == [] do
          {:error, :no_entries}
        else
          total_entries = round.total_entries

          winners = derive_winners(
            round.server_seed,
            round.block_hash_at_close,
            total_entries,
            entries
          )

          Repo.transaction(fn ->
            # Insert all winner records
            Enum.each(winners, fn winner_attrs ->
              %Winner{}
              |> Winner.changeset(Map.put(winner_attrs, :round_id, round_id))
              |> Repo.insert!()
            end)

            # Update round status
            {:ok, updated_round} =
              round
              |> Round.draw_changeset(%{
                status: "drawn",
                draw_tx: Keyword.get(opts, :draw_tx),
                total_entries: total_entries
              })
              |> Repo.update()

            updated_round
          end)
        end

      %Round{status: status} ->
        {:error, {:invalid_status, status}}
    end
  end

  # ============================================================================
  # Entry Management (BUX Redemptions)
  # ============================================================================

  @doc """
  Redeems BUX into the airdrop vault, creating a position block.

  Requires the user to be phone verified. Each BUX = 1 entry position.
  Returns {:ok, entry} with start_position and end_position.
  """
  def redeem_bux(user, amount, round_id, opts \\ []) do
    with :ok <- validate_phone_verified(user),
         %Round{status: "open"} <- get_round(round_id) || {:error, :round_not_found},
         :ok <- validate_amount(amount) do
      create_entry(user, amount, round_id, opts)
    else
      {:error, _} = error -> error
      %Round{status: status} -> {:error, {:round_not_open, status}}
      nil -> {:error, :round_not_found}
    end
  end

  @doc """
  Gets all entries for a user in a round.
  """
  def get_user_entries(user_id, round_id) do
    Entry
    |> where([e], e.user_id == ^user_id and e.round_id == ^round_id)
    |> order_by([e], asc: e.start_position)
    |> Repo.all()
  end

  @doc """
  Gets total entries (BUX deposited) for a round.
  """
  def get_total_entries(round_id) do
    case get_round(round_id) do
      nil -> 0
      round -> round.total_entries
    end
  end

  @doc """
  Gets unique participant count for a round.
  """
  def get_participant_count(round_id) do
    Entry
    |> where([e], e.round_id == ^round_id)
    |> select([e], count(e.user_id, :distinct))
    |> Repo.one() || 0
  end

  # ============================================================================
  # Winner Management
  # ============================================================================

  @doc """
  Gets all winners for a round, ordered by winner_index.
  """
  def get_winners(round_id) do
    Winner
    |> where([w], w.round_id == ^round_id)
    |> order_by([w], asc: w.winner_index)
    |> Repo.all()
  end

  @doc """
  Gets a specific winner by round and index.
  """
  def get_winner(round_id, winner_index) do
    Repo.get_by(Winner, round_id: round_id, winner_index: winner_index)
  end

  @doc """
  Checks if a user won in a given round.
  """
  def is_winner?(user_id, round_id) do
    Winner
    |> where([w], w.user_id == ^user_id and w.round_id == ^round_id)
    |> Repo.exists?()
  end

  @doc """
  Claims a prize for a winner. Records the claim transaction and wallet.

  Validates:
  - The winner exists and belongs to this user
  - Not already claimed
  - User has a connected external wallet
  """
  def claim_prize(user_id, round_id, winner_index, claim_tx, claim_wallet) do
    case get_winner(round_id, winner_index) do
      nil ->
        {:error, :winner_not_found}

      %Winner{user_id: uid} when uid != user_id ->
        {:error, :not_your_prize}

      %Winner{claimed: true} ->
        {:error, :already_claimed}

      %Winner{} = winner ->
        winner
        |> Winner.claim_changeset(%{
          claimed: true,
          claim_tx: claim_tx,
          claim_wallet: claim_wallet
        })
        |> Repo.update()
    end
  end

  # ============================================================================
  # Provably Fair Verification
  # ============================================================================

  @doc """
  Returns the commitment hash for a round (public, shown before draw).
  """
  def get_commitment_hash(round_id) do
    case get_round(round_id) do
      nil -> nil
      round -> round.commitment_hash
    end
  end

  @doc """
  Returns verification data after a round is drawn.
  Only reveals server_seed after the draw.
  """
  def get_verification_data(round_id) do
    case get_round(round_id) do
      %Round{status: "drawn"} = round ->
        {:ok, %{
          server_seed: round.server_seed,
          commitment_hash: round.commitment_hash,
          block_hash_at_close: round.block_hash_at_close,
          total_entries: round.total_entries,
          round_id: round.round_id
        }}

      %Round{} ->
        {:error, :not_yet_drawn}

      nil ->
        {:error, :round_not_found}
    end
  end

  @doc """
  Verifies that SHA256(server_seed) == commitment_hash for a drawn round.
  """
  def verify_fairness(round_id) do
    case get_verification_data(round_id) do
      {:ok, data} ->
        ProvablyFair.verify_commitment(data.server_seed, data.commitment_hash)

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Prize Helpers
  # ============================================================================

  @doc """
  Returns the prize amount in USD cents for a given winner index (0-32).
  """
  def prize_usd_for_index(index) when index >= 0 and index <= 32 do
    Map.get(@prize_structure, index, @default_prize_usd)
  end

  @doc """
  Returns the total prize pool in USD cents.
  """
  def total_prize_pool_usd do
    Enum.reduce(0..(@num_winners - 1), 0, fn i, acc -> acc + prize_usd_for_index(i) end)
  end

  @doc """
  Returns the prize structure summary for display: %{first: cents, second: cents, third: cents, rest: cents, rest_count: n, total: cents}
  """
  def prize_summary do
    %{
      first: prize_usd_for_index(0),
      second: prize_usd_for_index(1),
      third: prize_usd_for_index(2),
      rest: @default_prize_usd,
      rest_count: @num_winners - 3,
      total: total_prize_pool_usd()
    }
  end

  @doc """
  Returns the prize amount in USDT micro-units (6 decimals) for a given winner index.
  """
  def prize_usdt_for_index(index) when index >= 0 and index <= 32 do
    usd_cents = prize_usd_for_index(index)
    # Convert cents to USDT: $250.00 = 25000 cents = 250_000_000 micro-USDT
    div(usd_cents * @usdt_decimals, 100)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_next_round_id do
    case Repo.one(from r in Round, select: max(r.round_id)) do
      nil -> 1
      max_id -> max_id + 1
    end
  end

  defp validate_phone_verified(%{phone_verified: true}), do: :ok
  defp validate_phone_verified(_user), do: {:error, :phone_not_verified}

  defp validate_amount(amount) when is_integer(amount) and amount > 0, do: :ok
  defp validate_amount(_), do: {:error, :invalid_amount}

  defp create_entry(user, amount, round_id, opts) do
    wallet_address = user.smart_wallet_address || user.wallet_address

    # Deduct BUX from Mnesia balance BEFORE creating the entry
    case BlocksterV2.EngagementTracker.deduct_user_token_balance(
           user.id, wallet_address, "BUX", amount
         ) do
      {:ok, _new_balance} ->
        Repo.transaction(fn ->
          # Lock the round row for atomic position assignment
          round =
            Round
            |> where([r], r.round_id == ^round_id)
            |> lock("FOR UPDATE")
            |> Repo.one!()

          start_position = round.total_entries + 1
          end_position = round.total_entries + amount

          entry_attrs = %{
            user_id: user.id,
            round_id: round_id,
            wallet_address: wallet_address,
            external_wallet: Keyword.get(opts, :external_wallet),
            amount: amount,
            start_position: start_position,
            end_position: end_position,
            deposit_tx: Keyword.get(opts, :deposit_tx)
          }

          entry =
            %Entry{}
            |> Entry.changeset(entry_attrs)
            |> Repo.insert!()

          # Update total entries on the round
          round
          |> Ecto.Changeset.change(total_entries: end_position)
          |> Repo.update!()

          entry
        end)

      {:error, reason} ->
        Logger.error("[Airdrop] Failed to deduct BUX for user #{user.id}: #{inspect(reason)}")
        {:error, :insufficient_balance}
    end
  end

  defp derive_winners(server_seed, block_hash_at_close, total_entries, entries) do
    # Mirror the on-chain algorithm:
    # combinedSeed = keccak256(serverSeed | blockHashAtClose)
    combined_seed = keccak256_combined(server_seed, block_hash_at_close)

    for i <- 0..(@num_winners - 1) do
      # position = hash(combinedSeed, i) mod totalEntries + 1
      random_number = derive_position(combined_seed, i, total_entries)

      # Find the deposit containing this position
      entry = find_entry_for_position(entries, random_number)

      prize_usd = prize_usd_for_index(i)
      prize_usdt = prize_usdt_for_index(i)

      %{
        winner_index: i,
        random_number: random_number,
        wallet_address: entry.wallet_address,
        external_wallet: entry.external_wallet,
        user_id: entry.user_id,
        deposit_start: entry.start_position,
        deposit_end: entry.end_position,
        deposit_amount: entry.amount,
        prize_usd: prize_usd,
        prize_usdt: prize_usdt
      }
    end
  end

  @doc false
  def keccak256_combined(server_seed, block_hash) do
    # Convert hex strings to binary, concatenate, then keccak256
    seed_bytes = decode_hex(server_seed)
    block_bytes = decode_hex(block_hash)

    ExKeccak.hash_256(seed_bytes <> block_bytes)
  end

  @doc false
  def derive_position(combined_seed, index, total_entries) do
    # keccak256(combinedSeed ++ index_as_uint256)
    index_bytes = <<index::unsigned-big-integer-size(256)>>
    hash = ExKeccak.hash_256(combined_seed <> index_bytes)

    # Convert to integer, mod totalEntries + 1
    <<value::unsigned-big-integer-size(256)>> = hash
    rem(value, total_entries) + 1
  end

  defp find_entry_for_position(entries, position) do
    # Binary search through sorted entries
    Enum.find(entries, fn entry ->
      position >= entry.start_position and position <= entry.end_position
    end)
  end

  defp decode_hex("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp decode_hex(hex), do: Base.decode16!(hex, case: :mixed)

  defp list_entries(round_id) do
    Entry
    |> where([e], e.round_id == ^round_id)
    |> order_by([e], asc: e.start_position)
    |> Repo.all()
  end
end
