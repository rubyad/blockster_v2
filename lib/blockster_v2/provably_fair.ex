defmodule BlocksterV2.ProvablyFair do
  @moduledoc """
  Provably fair random number generation using commit-reveal pattern.

  The client seed is derived DETERMINISTICALLY from bet details, making
  verification fully transparent - anyone can recompute all seeds.

  ## How It Works

  1. Server generates random seed and commits to it (hash) BEFORE player places bet
  2. Player makes their bet choices (predictions, amount, token, etc.)
  3. Client seed is derived from player's bet details only (no server-controlled values)
  4. Combined seed = SHA256(server_seed:client_seed:nonce)
  5. Results are derived from combined seed bytes
  6. After game, server reveals seed - player can verify commitment matches
  """

  @doc """
  Generate a new server seed (32 bytes hex = 64 characters).
  """
  def generate_server_seed do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  @doc """
  Generate commitment (hash) from server seed.
  This is shown to the player BEFORE they place their bet.
  """
  def generate_commitment(server_seed) do
    :crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower)
  end

  @doc """
  Verify a commitment matches a server seed.
  """
  def verify_commitment(server_seed, commitment) do
    generate_commitment(server_seed) == String.downcase(commitment)
  end

  @doc """
  Generate client seed DETERMINISTICALLY from bet details.

  This is the key improvement over random client seeds:
  - Fully verifiable by anyone
  - No trust required in client's RNG
  - All inputs are visible in the game record
  - No server-controlled values (like timestamp)

  Formula: SHA256(user_id:bet_amount:token:difficulty:predictions)
  """
  def generate_client_seed(user_id, bet_amount, token, difficulty, predictions) do
    predictions_str =
      predictions
      |> Enum.map(&Atom.to_string/1)
      |> Enum.join(",")

    input = "#{user_id}:#{bet_amount}:#{token}:#{difficulty}:#{predictions_str}"
    :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)
  end

  @doc """
  Generate combined seed from server_seed + client_seed + nonce.
  """
  def generate_combined_seed(server_seed, client_seed, nonce) do
    input = "#{server_seed}:#{client_seed}:#{nonce}"
    :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)
  end

  @doc """
  Generate coin flip results from combined seed.
  Each byte < 128 = heads, >= 128 = tails (exactly 50/50).
  """
  def generate_results(combined_seed, num_flips) do
    combined_seed
    |> Base.decode16!(case: :lower)
    |> :binary.bin_to_list()
    |> Enum.take(num_flips)
    |> Enum.map(fn byte ->
      if byte < 128, do: :heads, else: :tails
    end)
  end

  @doc """
  Get the raw bytes from combined seed (for verification display).
  """
  def get_result_bytes(combined_seed, num_flips) do
    combined_seed
    |> Base.decode16!(case: :lower)
    |> :binary.bin_to_list()
    |> Enum.take(num_flips)
  end

  @doc """
  Full verification: given all bet details, verify the results are correct.
  Returns {:ok, results, client_seed, combined_seed} if valid, {:error, reason} if not.

  This allows complete third-party verification with only the game record data.
  No timestamp needed - all inputs are player-controlled values from the game record.
  """
  def verify_game(server_seed, server_seed_hash, user_id, bet_amount, token,
                  difficulty, predictions, nonce) do
    # Step 1: Verify server commitment
    if not verify_commitment(server_seed, server_seed_hash) do
      {:error, :invalid_commitment}
    else
      # Step 2: Derive client seed from bet details (all from game record)
      client_seed = generate_client_seed(user_id, bet_amount, token, difficulty, predictions)

      # Step 3: Generate combined seed and results
      combined_seed = generate_combined_seed(server_seed, client_seed, nonce)
      results = generate_results(combined_seed, length(predictions))

      {:ok, results, client_seed, combined_seed}
    end
  end

  @doc """
  Build the client seed input string (for display in verification modal).
  """
  def build_client_seed_input(user_id, bet_amount, token, difficulty, predictions) do
    predictions_str =
      predictions
      |> Enum.map(&Atom.to_string/1)
      |> Enum.join(",")

    "#{user_id}:#{bet_amount}:#{token}:#{difficulty}:#{predictions_str}"
  end
end
