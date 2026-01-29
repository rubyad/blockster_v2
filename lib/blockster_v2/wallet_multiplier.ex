defmodule BlocksterV2.WalletMultiplier do
  @moduledoc """
  Calculates hardware wallet multiplier based on token holdings.

  Multiplier Rules:
  - Base wallet connection: +0.1x
  - ROGUE on Rogue Chain: +0.4x to +4.0x (tiered)
  - ROGUE on Arbitrum: 50% of Rogue Chain multiplier (max +2.0x)
  - ETH (mainnet + Arbitrum): +0.1x to +1.5x (combined, no L2 discount)
  - Other tokens (USD value): +0.01x to +1.0x (capped)

  See docs/hardware_wallet_integration.md for complete details.
  """

  require Logger
  alias BlocksterV2.{Wallets, PriceTracker}

  # Token contract addresses
  @rogue_on_arbitrum "0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd"
  @usdc_mainnet "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
  @usdc_arbitrum "0xaf88d065e77c8cc2239327c5edb3a432268e5831"
  @usdt_mainnet "0xdac17f958d2ee523a2206206994597c13d831ec7"
  @usdt_arbitrum "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9"
  @arb_mainnet "0xb50721bcf8d664c30412cfbc6cf7a15145935f0d"
  @arb_arbitrum "0x912ce59144191c1204e64559fe8253a0e49e6548"

  # Multiplier tiers for ROGUE
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

  # Multiplier tiers for ETH (combined mainnet + Arbitrum)
  @eth_tiers [
    {10.0, 1.5},
    {5.0, 1.1},
    {2.5, 0.9},
    {1.0, 0.7},
    {0.5, 0.5},
    {0.1, 0.3},
    {0.01, 0.1},
    {0.0, 0.0}
  ]

  @doc """
  Calculate hardware wallet multiplier for a user.

  Returns a map with breakdown:
  %{
    total_multiplier: 2.5,
    connection_boost: 0.1,
    rogue_multiplier: 1.2,
    eth_multiplier: 0.5,
    other_tokens_multiplier: 0.7,
    breakdown: %{
      rogue_chain: 250_000,
      rogue_arbitrum: 50_000,
      weighted_rogue: 275_000,
      eth_mainnet: 0.5,
      eth_arbitrum: 0.3,
      combined_eth: 0.8,
      other_tokens_usd: 7_500
    }
  }
  """
  def calculate_hardware_wallet_multiplier(user_id) do
    case Wallets.get_connected_wallet(user_id) do
      nil ->
        # No wallet connected - return base multiplier
        %{
          total_multiplier: 0.0,
          connection_boost: 0.0,
          rogue_multiplier: 0.0,
          eth_multiplier: 0.0,
          other_tokens_multiplier: 0.0,
          breakdown: %{}
        }

      wallet ->
        calculate_from_wallet_balances(wallet)
    end
  end

  @doc """
  Calculate multiplier from wallet balances stored in Mnesia.
  """
  defp calculate_from_wallet_balances(wallet) do
    # Get balances from Mnesia
    balances = Wallets.get_wallet_balances(wallet.user_id)

    # Base connection boost
    connection_boost = 0.1

    # Calculate ROGUE multiplier
    rogue_chain = get_balance(balances, "ROGUE", "rogue")
    rogue_arbitrum = get_balance(balances, "ROGUE", "arbitrum")
    weighted_rogue = rogue_chain + (rogue_arbitrum * 0.5)
    rogue_multiplier = calculate_rogue_tier_multiplier(weighted_rogue)

    # Calculate ETH multiplier (combined mainnet + Arbitrum)
    eth_mainnet = get_balance(balances, "ETH", "ethereum")
    eth_arbitrum = get_balance(balances, "ETH", "arbitrum")
    combined_eth = eth_mainnet + eth_arbitrum
    eth_multiplier = calculate_eth_tier_multiplier(combined_eth)

    # Calculate other tokens multiplier (USD value based)
    other_tokens_usd = calculate_other_tokens_usd_value(balances)
    other_tokens_multiplier = calculate_other_tokens_multiplier(other_tokens_usd)

    # Total multiplier
    total_multiplier =
      connection_boost + rogue_multiplier + eth_multiplier + other_tokens_multiplier

    %{
      total_multiplier: total_multiplier,
      connection_boost: connection_boost,
      rogue_multiplier: rogue_multiplier,
      eth_multiplier: eth_multiplier,
      other_tokens_multiplier: other_tokens_multiplier,
      breakdown: %{
        rogue_chain: rogue_chain,
        rogue_arbitrum: rogue_arbitrum,
        weighted_rogue: weighted_rogue,
        eth_mainnet: eth_mainnet,
        eth_arbitrum: eth_arbitrum,
        combined_eth: combined_eth,
        other_tokens_usd: other_tokens_usd
      }
    }
  end

  @doc """
  Calculate ROGUE tier multiplier based on weighted total.
  """
  defp calculate_rogue_tier_multiplier(weighted_rogue) do
    Enum.find_value(@rogue_tiers, 0.0, fn {threshold, multiplier} ->
      if weighted_rogue >= threshold, do: multiplier
    end)
  end

  @doc """
  Calculate ETH tier multiplier based on combined balance.
  """
  defp calculate_eth_tier_multiplier(combined_eth) do
    Enum.find_value(@eth_tiers, 0.0, fn {threshold, multiplier} ->
      if combined_eth >= threshold, do: multiplier
    end)
  end

  @doc """
  Calculate other tokens multiplier based on combined USD value.
  Formula: min(combined_usd_value / 10000, 1.0)
  """
  defp calculate_other_tokens_multiplier(combined_usd_value) do
    min(combined_usd_value / 10_000, 1.0)
  end

  @doc """
  Calculate combined USD value of all tracked tokens (excluding ETH and ROGUE).
  """
  defp calculate_other_tokens_usd_value(balances) do
    tokens = [
      {"USDC", "ethereum", @usdc_mainnet},
      {"USDC", "arbitrum", @usdc_arbitrum},
      {"USDT", "ethereum", @usdt_mainnet},
      {"USDT", "arbitrum", @usdt_arbitrum},
      {"ARB", "ethereum", @arb_mainnet},
      {"ARB", "arbitrum", @arb_arbitrum}
    ]

    Enum.reduce(tokens, 0.0, fn {symbol, chain, _contract}, acc ->
      balance = get_balance(balances, symbol, chain)
      price = get_token_price(symbol)
      acc + balance * price
    end)
  end

  @doc """
  Get balance for a specific token and chain from cached balances.
  """
  defp get_balance(balances, symbol, chain) do
    case Enum.find(balances, fn b -> b.symbol == symbol && b.chain == chain end) do
      nil -> 0.0
      balance -> balance.amount
    end
  end

  @doc """
  Get token price from PriceTracker (returns 0.0 if not available).
  """
  defp get_token_price(symbol) do
    case PriceTracker.get_price(symbol) do
      {:ok, price_data} -> price_data.usd_price
      {:error, _} -> 0.0
    end
  end

  @doc """
  Update hardware wallet multiplier for a user in Mnesia.

  Table schema (user_multipliers):
  Index 0: :user_multipliers (table name)
  Index 1: :user_id
  Index 2: :smart_wallet
  Index 3: :x_multiplier
  Index 4: :linkedin_multiplier
  Index 5: :personal_multiplier
  Index 6: :rogue_multiplier
  Index 7: :overall_multiplier
  Index 8: :extra_field1 (hardware_wallet_multiplier)
  Index 9-11: :extra_field2-4
  Index 12: :created_at
  Index 13: :updated_at
  """
  def update_user_multiplier(user_id) do
    multiplier_data = calculate_hardware_wallet_multiplier(user_id)

    # Update user_multipliers table in Mnesia
    case :mnesia.dirty_read({:user_multipliers, user_id}) do
      [] ->
        # Create new record with all fields initialized
        now = System.system_time(:second)

        record = {
          :user_multipliers,
          user_id,
          # smart_wallet (index 2)
          nil,
          # x_multiplier (index 3)
          1.0,
          # linkedin_multiplier (index 4)
          1.0,
          # personal_multiplier (index 5)
          1.0,
          # rogue_multiplier (index 6)
          1.0,
          # overall_multiplier (index 7) - sum of all multipliers
          1.0 + multiplier_data.total_multiplier,
          # extra_field1 (index 8) - hardware_wallet_multiplier
          multiplier_data.total_multiplier,
          # extra_field2 (index 9)
          nil,
          # extra_field3 (index 10)
          nil,
          # extra_field4 (index 11)
          nil,
          # created_at (index 12)
          now,
          # updated_at (index 13)
          now
        }

        :mnesia.dirty_write(record)

      [record] ->
        # Update existing record
        # Calculate new overall multiplier (sum of all individual multipliers)
        x_multiplier = elem(record, 3) || 1.0
        linkedin_multiplier = elem(record, 4) || 1.0
        personal_multiplier = elem(record, 5) || 1.0
        rogue_multiplier = elem(record, 6) || 1.0

        base_multiplier =
          x_multiplier + linkedin_multiplier + personal_multiplier + rogue_multiplier - 3.0

        new_overall = base_multiplier + multiplier_data.total_multiplier

        updated_record =
          record
          |> put_elem(7, new_overall)
          |> put_elem(8, multiplier_data.total_multiplier)
          |> put_elem(13, System.system_time(:second))

        :mnesia.dirty_write(updated_record)
    end

    Logger.info(
      "[WalletMultiplier] Updated multiplier for user #{user_id}: #{multiplier_data.total_multiplier}"
    )

    {:ok, multiplier_data}
  end

  @doc """
  Get hardware wallet multiplier for a user.
  """
  def get_user_multiplier(user_id) do
    case :mnesia.dirty_read({:user_multipliers, user_id}) do
      [] -> 0.0
      [record] -> elem(record, 8) || 0.0
    end
  end

  @doc """
  Get combined multiplier (overall) for a user.
  """
  def get_combined_multiplier(user_id) do
    case :mnesia.dirty_read({:user_multipliers, user_id}) do
      [] -> 1.0
      [record] -> elem(record, 7) || 1.0
    end
  end
end
