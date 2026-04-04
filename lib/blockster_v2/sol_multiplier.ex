defmodule BlocksterV2.SolMultiplier do
  @moduledoc """
  Calculates SOL balance multiplier for BUX earning rewards.

  Users must hold SOL in their connected Solana wallet to earn BUX.
  The more SOL held, the higher the multiplier.

  ## Multiplier Tiers

  | SOL Balance    | Multiplier | Notes                  |
  |----------------|-----------|------------------------|
  | 0 - 0.0099     | 0.0x      | Cannot earn BUX at all |
  | 0.01 - 0.04    | 1.0x      | Bare minimum to earn   |
  | 0.05 - 0.09    | 1.5x      |                        |
  | 0.1 - 0.24     | 2.0x      |                        |
  | 0.25 - 0.49    | 2.5x      |                        |
  | 0.5 - 0.99     | 3.0x      |                        |
  | 1.0 - 2.49     | 3.5x      | Decent earnings        |
  | 2.5 - 4.99     | 4.0x      |                        |
  | 5.0 - 9.99     | 4.5x      |                        |
  | 10.0+          | 5.0x      | Maximum                |

  ## Balance Source

  SOL balance is read from the `user_solana_balances` Mnesia table,
  which is synced from on-chain via the Solana settler service.
  """

  require Logger

  # SOL tiers: {threshold, multiplier}
  # Ordered from highest to lowest for efficient lookup
  @sol_tiers [
    {10.0, 5.0},
    {5.0, 4.5},
    {2.5, 4.0},
    {1.0, 3.5},
    {0.5, 3.0},
    {0.25, 2.5},
    {0.1, 2.0},
    {0.05, 1.5},
    {0.01, 1.0},
    {0.0, 0.0}
  ]

  @max_multiplier 5.0
  @min_multiplier 0.0

  @doc """
  Calculate SOL multiplier for a user based on their Solana wallet balance.

  Returns a map with:
  - `multiplier`: The multiplier value (0.0 - 5.0)
  - `balance`: The user's SOL balance
  - `next_tier`: Info about the next tier (nil if maxed)
  """
  def calculate(user_id) when is_integer(user_id) do
    balance = get_sol_balance(user_id)
    calculate_from_balance(balance)
  end

  def calculate(_), do: default_result()

  @doc """
  Calculate SOL multiplier from a given balance (for testing or preview).
  Does not read from Mnesia.
  """
  def calculate_from_balance(balance) when is_number(balance) and balance >= 0 do
    multiplier = get_tier_multiplier(balance)
    next_tier = get_next_tier_info(balance)

    %{
      multiplier: multiplier,
      balance: balance,
      next_tier: next_tier
    }
  end

  def calculate_from_balance(_), do: default_result()

  @doc """
  Get just the multiplier value for a user.
  Returns a float between 0.0 and 5.0.
  """
  def get_multiplier(user_id) when is_integer(user_id) do
    balance = get_sol_balance(user_id)
    get_tier_multiplier(balance)
  end

  def get_multiplier(_), do: @min_multiplier

  @doc """
  Get the SOL tiers for display in UI.
  """
  def get_tiers do
    @sol_tiers
    |> Enum.map(fn {threshold, multiplier} ->
      %{threshold: threshold, multiplier: multiplier}
    end)
  end

  @doc """
  Get the maximum possible multiplier.
  """
  def max_multiplier, do: @max_multiplier

  @doc """
  Get the minimum possible multiplier.
  """
  def min_multiplier, do: @min_multiplier

  # Private Functions

  # Read SOL balance from user_solana_balances Mnesia table
  # Table structure: {:user_solana_balances, user_id, wallet_address, updated_at, sol_balance, bux_balance}
  defp get_sol_balance(user_id) do
    case :mnesia.dirty_read({:user_solana_balances, user_id}) do
      [] -> 0.0
      [record] -> elem(record, 4) || 0.0
    end
  rescue
    _ -> 0.0
  catch
    :exit, _ -> 0.0
  end

  # Find the multiplier for a given SOL balance
  defp get_tier_multiplier(balance) when is_number(balance) and balance >= 0 do
    Enum.find_value(@sol_tiers, @min_multiplier, fn {threshold, multiplier} ->
      if balance >= threshold, do: multiplier
    end)
  end

  defp get_tier_multiplier(_), do: @min_multiplier

  # Get info about the next tier the user can reach
  defp get_next_tier_info(balance) do
    next_tier =
      @sol_tiers
      |> Enum.reverse()
      |> Enum.find(fn {threshold, _multiplier} ->
        threshold > balance
      end)

    case next_tier do
      nil ->
        # User is at max tier
        nil

      {threshold, multiplier} ->
        %{
          threshold: threshold,
          multiplier: multiplier,
          sol_needed: Float.round(threshold - balance, 4)
        }
    end
  end

  defp default_result do
    %{
      multiplier: @min_multiplier,
      balance: 0.0,
      next_tier: %{
        threshold: 0.01,
        multiplier: 1.0,
        sol_needed: 0.01
      }
    }
  end
end
