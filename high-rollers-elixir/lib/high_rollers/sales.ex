defmodule HighRollers.Sales do
  @moduledoc """
  Mnesia operations for mint/sales data and affiliate earnings.

  NOTE: Sale data is stored as mint fields in hr_nfts (via NFTStore).
  This module handles affiliate earnings and provides convenience queries.
  """

  @affiliate_earnings_table :hr_affiliate_earnings

  @doc "Get paginated sales (minted NFTs) for display, sorted by token_id descending"
  def get_sales(limit \\ 50, offset \\ 0) do
    HighRollers.NFTStore.get_all()
    |> Enum.filter(fn nft -> nft.mint_price != nil and nft.mint_price != "" end)
    |> Enum.sort_by(fn nft -> nft.token_id end, :desc)
    |> Enum.drop(offset)
    |> Enum.take(limit)
    |> Enum.map(fn nft ->
      %{
        token_id: nft.token_id,
        buyer: nft.original_buyer,
        hostess_index: nft.hostess_index,
        hostess_name: nft.hostess_name,
        price: nft.mint_price,
        price_eth: format_eth(nft.mint_price),
        tx_hash: nft.mint_tx_hash,
        timestamp: nft.created_at
      }
    end)
  end

  defp format_eth(nil), do: "0"
  defp format_eth(wei_string) when is_binary(wei_string) do
    wei = String.to_integer(wei_string)
    :erlang.float_to_binary(wei / 1.0e18, decimals: 3)
  end
  defp format_eth(_), do: "0"

  @doc "Record mint data in hr_nfts table (delegates to NFTStore)"
  def insert(attrs) do
    # Mint data is stored in hr_nfts - use NFTStore.upsert/1
    # This function exists for clarity and to match the original API
    HighRollers.NFTStore.upsert(attrs)
  end

  @doc "Insert affiliate earning record (bag table - allows multiple per token)"
  def insert_affiliate_earning(attrs) do
    record = {@affiliate_earnings_table,
      attrs.token_id,
      attrs.tier,
      String.downcase(attrs.affiliate),
      attrs.earnings,
      attrs.tx_hash,
      System.system_time(:second)
    }

    :mnesia.dirty_write(record)
    :ok
  end

  @doc "Get affiliate stats (total earnings, count, withdrawable balance) for an address"
  def get_affiliate_stats(address) do
    address = String.downcase(address)

    # Get all earnings for this affiliate using index
    earnings = :mnesia.dirty_index_read(@affiliate_earnings_table, address, :affiliate)

    tier1 = Enum.filter(earnings, fn record -> elem(record, 2) == 1 end)
    tier2 = Enum.filter(earnings, fn record -> elem(record, 2) == 2 end)

    # Get withdrawable balance from user record
    user = HighRollers.Users.get(address)
    withdrawable = if user, do: user.affiliate_balance, else: "0"

    %{
      tier1_count: length(tier1),
      tier1_total: sum_earnings(tier1),
      tier2_count: length(tier2),
      tier2_total: sum_earnings(tier2),
      total_earned: sum_earnings(tier1) + sum_earnings(tier2),
      withdrawable_balance: withdrawable
    }
  end

  @doc """
  Get recent affiliate earnings.

  - Pass nil for address to get ALL affiliate earnings (global view)
  - Pass an address to get earnings for that specific affiliate
  - Supports pagination with limit and offset
  """
  def get_affiliate_earnings(address, limit \\ 50, offset \\ 0)

  def get_affiliate_earnings(nil, limit, offset) do
    # Get ALL affiliate earnings (for global Recent Affiliate Earnings table)
    :mnesia.dirty_match_object({@affiliate_earnings_table, :_, :_, :_, :_, :_, :_})
    |> Enum.sort_by(fn record -> elem(record, 1) end, :desc)  # Sort by token_id descending
    |> Enum.drop(offset)
    |> Enum.take(limit)
    |> Enum.map(&earning_to_map/1)
  end

  def get_affiliate_earnings(address, limit, offset) do
    address = String.downcase(address)

    :mnesia.dirty_index_read(@affiliate_earnings_table, address, :affiliate)
    |> Enum.sort_by(fn record -> elem(record, 1) end, :desc)  # Sort by token_id descending
    |> Enum.drop(offset)
    |> Enum.take(limit)
    |> Enum.map(&earning_to_map/1)
  end

  @doc "Get all affiliate earnings for a token"
  def get_earnings_by_token(token_id) do
    :mnesia.dirty_read(@affiliate_earnings_table, token_id)
    |> Enum.map(&earning_to_map/1)
  end

  defp sum_earnings(records) do
    Enum.reduce(records, 0, fn record, acc ->
      acc + String.to_integer(elem(record, 4))  # earnings field
    end)
  end

  defp earning_to_map({@affiliate_earnings_table, token_id, tier, affiliate, earnings, tx_hash, timestamp}) do
    # Look up the NFT to get hostess_index and buyer for display
    nft = HighRollers.NFTStore.get(token_id)
    hostess_index = if nft, do: nft.hostess_index, else: 0
    buyer = if nft, do: nft.original_buyer, else: nil

    %{
      token_id: token_id,
      tier: tier,
      affiliate: affiliate,
      earnings: earnings,
      earnings_eth: format_eth(earnings),
      tx_hash: tx_hash,
      timestamp: timestamp,
      hostess_index: hostess_index,
      buyer: buyer
    }
  end
end
