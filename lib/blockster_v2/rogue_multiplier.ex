defmodule BlocksterV2.RogueMultiplier do
  @moduledoc """
  Calculates ROGUE multiplier based on Blockster smart wallet balance.

  **IMPORTANT**: Only ROGUE held in the user's **Blockster smart wallet** counts toward
  this multiplier. ROGUE in external wallets (MetaMask, Ledger, etc.) does NOT count.

  ## Multiplier Tiers

  | ROGUE Balance (Smart Wallet) | Boost  | Total Multiplier |
  |------------------------------|--------|------------------|
  | 0 - 99,999                   | +0.0x  | 1.0x             |
  | 100,000 - 199,999            | +0.4x  | 1.4x             |
  | 200,000 - 299,999            | +0.8x  | 1.8x             |
  | 300,000 - 399,999            | +1.2x  | 2.2x             |
  | 400,000 - 499,999            | +1.6x  | 2.6x             |
  | 500,000 - 599,999            | +2.0x  | 3.0x             |
  | 600,000 - 699,999            | +2.4x  | 3.4x             |
  | 700,000 - 799,999            | +2.8x  | 3.8x             |
  | 800,000 - 899,999            | +3.2x  | 4.2x             |
  | 900,000 - 999,999            | +3.6x  | 4.6x             |
  | 1,000,000+                   | +4.0x  | 5.0x (maximum)   |

  ## Cap

  Only the first 1M ROGUE counts toward the multiplier. Holding 5M ROGUE gives
  the same 5.0x multiplier as holding 1M ROGUE.

  ## Why Smart Wallet Only?

  - Encourages users to deposit ROGUE into Blockster ecosystem
  - Smart wallet balance is always accurate (stored in Mnesia)
  - Simplifies calculation (single source of truth)
  - Users don't need an external wallet to benefit from ROGUE holdings
  """

  require Logger

  # ROGUE tiers: {threshold, boost}
  # Ordered from highest to lowest for efficient lookup
  @rogue_tiers [
    {1_000_000, 4.0},
    {900_000, 3.6},
    {800_000, 3.2},
    {700_000, 2.8},
    {600_000, 2.4},
    {500_000, 2.0},
    {400_000, 1.6},
    {300_000, 1.2},
    {200_000, 0.8},
    {100_000, 0.4},
    {0, 0.0}
  ]

  # Maximum ROGUE that counts toward multiplier
  @max_rogue_for_multiplier 1_000_000

  # Minimum multiplier (no ROGUE)
  @base_multiplier 1.0

  # Maximum multiplier (1M+ ROGUE)
  @max_multiplier 5.0

  @doc """
  Calculate ROGUE multiplier for a user based on their smart wallet balance.

  Returns a map with:
  - `total_multiplier`: The final multiplier (1.0 - 5.0)
  - `boost`: The boost amount (0.0 - 4.0)
  - `balance`: The actual ROGUE balance in smart wallet
  - `capped_balance`: The balance used for calculation (capped at 1M)
  - `next_tier`: Info about the next tier (nil if maxed)

  ## Examples

      iex> BlocksterV2.RogueMultiplier.calculate_rogue_multiplier(123)
      %{
        total_multiplier: 3.0,
        boost: 2.0,
        balance: 500000.0,
        capped_balance: 500000.0,
        next_tier: %{threshold: 600000, boost: 2.4, rogue_needed: 100000}
      }
  """
  def calculate_rogue_multiplier(user_id) when is_integer(user_id) do
    # Get ROGUE balance from smart wallet (Mnesia user_rogue_balances table)
    balance = get_smart_wallet_rogue_balance(user_id)

    # Cap at 1M ROGUE for multiplier calculation
    capped_balance = min(balance, @max_rogue_for_multiplier)

    # Get boost from tier
    boost = get_rogue_boost(capped_balance)

    # Calculate total multiplier
    total_multiplier = @base_multiplier + boost

    # Get next tier info for UI progress display
    next_tier = get_next_tier_info(capped_balance)

    %{
      total_multiplier: total_multiplier,
      boost: boost,
      balance: balance,
      capped_balance: capped_balance,
      next_tier: next_tier
    }
  end

  def calculate_rogue_multiplier(_), do: default_result()

  @doc """
  Get just the multiplier value for a user.
  Returns a float between 1.0 and 5.0.

  ## Examples

      iex> BlocksterV2.RogueMultiplier.get_multiplier(123)
      3.0
  """
  def get_multiplier(user_id) when is_integer(user_id) do
    balance = get_smart_wallet_rogue_balance(user_id)
    capped_balance = min(balance, @max_rogue_for_multiplier)
    boost = get_rogue_boost(capped_balance)
    @base_multiplier + boost
  end

  def get_multiplier(_), do: @base_multiplier

  @doc """
  Calculate multiplier from a given balance (for testing or preview).
  Does not read from Mnesia.

  ## Examples

      iex> BlocksterV2.RogueMultiplier.calculate_from_balance(500_000)
      %{total_multiplier: 3.0, boost: 2.0, ...}
  """
  def calculate_from_balance(balance) when is_number(balance) and balance >= 0 do
    capped_balance = min(balance, @max_rogue_for_multiplier)
    boost = get_rogue_boost(capped_balance)
    total_multiplier = @base_multiplier + boost
    next_tier = get_next_tier_info(capped_balance)

    %{
      total_multiplier: total_multiplier,
      boost: boost,
      balance: balance,
      capped_balance: capped_balance,
      next_tier: next_tier
    }
  end

  def calculate_from_balance(_), do: default_result()

  @doc """
  Get the ROGUE tiers for display in UI.

  Returns a list of maps with threshold, boost, and multiplier info.
  """
  def get_tiers do
    @rogue_tiers
    |> Enum.map(fn {threshold, boost} ->
      %{
        threshold: threshold,
        boost: boost,
        multiplier: @base_multiplier + boost
      }
    end)
  end

  @doc """
  Get the maximum possible multiplier.
  """
  def max_multiplier, do: @max_multiplier

  @doc """
  Get the base/minimum multiplier.
  """
  def base_multiplier, do: @base_multiplier

  # Private Functions

  # Read ROGUE balance from Mnesia user_rogue_balances table
  # Table structure: {:user_rogue_balances, user_id, user_smart_wallet, updated_at, rogue_balance_rogue_chain, rogue_balance_arbitrum}
  # Mnesia records include table name at index 0, so:
  #   Index 0: :user_rogue_balances (table name)
  #   Index 1: user_id
  #   Index 2: user_smart_wallet
  #   Index 3: updated_at
  #   Index 4: rogue_balance_rogue_chain  <-- this is what we need
  #   Index 5: rogue_balance_arbitrum
  defp get_smart_wallet_rogue_balance(user_id) do
    case :mnesia.dirty_read({:user_rogue_balances, user_id}) do
      [] ->
        0.0

      [record] ->
        # rogue_balance_rogue_chain is at index 4
        elem(record, 4) || 0.0
    end
  rescue
    _ -> 0.0
  end

  # Find the boost for a given balance by finding the first matching tier
  defp get_rogue_boost(balance) do
    Enum.find_value(@rogue_tiers, 0.0, fn {threshold, boost} ->
      if balance >= threshold, do: boost
    end)
  end

  # Get info about the next tier the user can reach
  defp get_next_tier_info(capped_balance) do
    # Find the first tier that's higher than current balance
    # Tiers are ordered highest to lowest, so we need to reverse and find first > balance
    next_tier =
      @rogue_tiers
      |> Enum.reverse()
      |> Enum.find(fn {threshold, _boost} ->
        threshold > capped_balance
      end)

    case next_tier do
      nil ->
        # User is at max tier
        nil

      {threshold, boost} ->
        %{
          threshold: threshold,
          boost: boost,
          multiplier: @base_multiplier + boost,
          rogue_needed: threshold - capped_balance
        }
    end
  end

  defp default_result do
    %{
      total_multiplier: @base_multiplier,
      boost: 0.0,
      balance: 0.0,
      capped_balance: 0.0,
      next_tier: %{
        threshold: 100_000,
        boost: 0.4,
        multiplier: 1.4,
        rogue_needed: 100_000
      }
    }
  end
end
