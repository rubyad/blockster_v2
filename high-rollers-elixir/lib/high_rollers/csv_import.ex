defmodule HighRollers.CSVImport do
  @moduledoc """
  Import NFT and affiliate data from production CSV files.

  ## Usage

      # Import both NFTs and affiliate payouts
      HighRollers.CSVImport.run(
        "/path/to/high_rollers_nfts_production.csv",
        "/path/to/high_rollers_affiliate_payouts_production.csv"
      )

      # Import only NFTs
      HighRollers.CSVImport.import_nfts("/path/to/high_rollers_nfts_production.csv")

      # Import only affiliate payouts
      HighRollers.CSVImport.import_affiliate_payouts("/path/to/high_rollers_affiliate_payouts_production.csv")

  ## CSV Field Mappings

  ### high_rollers_nfts_production.csv → hr_nfts table
  - id → token_id
  - price → mint_price
  - name → hostess_name
  - girl_type → hostess_index
  - buyer → original_buyer
  - affiliate_1 → affiliate
  - affiliate_2 → affiliate2
  - minted_at → created_at (converted from microseconds to seconds)
  - current_owner → owner

  ### high_rollers_affiliate_payouts_production.csv → hr_affiliate_earnings table
  - token_id → token_id
  - tier → tier
  - affiliate → affiliate
  - payout → earnings
  - paid_at → timestamp (converted from microseconds to seconds)
  """

  require Logger

  @nfts_table :hr_nfts
  @affiliate_earnings_table :hr_affiliate_earnings

  @doc """
  Run full import from both CSV files.
  """
  def run(nfts_csv_path, affiliate_csv_path) do
    Logger.info("[CSVImport] Starting import...")

    nft_count = import_nfts(nfts_csv_path)
    affiliate_count = import_affiliate_payouts(affiliate_csv_path)

    Logger.info("[CSVImport] Import complete!")
    Logger.info("[CSVImport] Imported #{nft_count} NFTs and #{affiliate_count} affiliate payouts")

    %{nfts: nft_count, affiliate_payouts: affiliate_count}
  end

  @doc """
  Import NFTs from CSV file into hr_nfts Mnesia table.
  """
  def import_nfts(csv_path) do
    Logger.info("[CSVImport] Importing NFTs from #{csv_path}")

    now = System.system_time(:second)

    csv_path
    |> File.stream!()
    |> Stream.drop(1)  # Skip header
    |> Stream.map(&parse_nft_row/1)
    |> Stream.filter(&(&1 != nil))
    |> Enum.reduce(0, fn nft, count ->
      # Get existing record to preserve earnings data
      existing = HighRollers.NFTStore.get(nft.token_id)

      record = {@nfts_table,
        # Core Identity (positions 1-5)
        nft.token_id,
        downcase(nft.owner),
        downcase(nft.original_buyer),
        nft.hostess_index,
        nft.hostess_name,
        # Mint Data (positions 6-10)
        nil,  # mint_tx_hash - not in CSV
        nil,  # mint_block_number - not in CSV
        nft.mint_price,
        downcase(nft.affiliate),
        downcase(nft.affiliate2),
        # Revenue Share Earnings (positions 11-14) - preserve existing or default
        (existing && existing.total_earned) || "0",
        (existing && existing.pending_amount) || "0",
        (existing && existing.last_24h_earned) || "0",
        (existing && existing.apy_basis_points) || 0,
        # Time Rewards (positions 15-17) - preserve existing
        (existing && existing.time_start_time),
        (existing && existing.time_last_claim),
        (existing && existing.time_total_claimed),
        # Timestamps (positions 18-19)
        nft.created_at,
        now
      }

      :mnesia.dirty_write(record)
      count + 1
    end)
  end

  @doc """
  Import affiliate payouts from CSV file into hr_affiliate_earnings Mnesia table.
  """
  def import_affiliate_payouts(csv_path) do
    Logger.info("[CSVImport] Importing affiliate payouts from #{csv_path}")

    csv_path
    |> File.stream!()
    |> Stream.drop(1)  # Skip header
    |> Stream.map(&parse_affiliate_row/1)
    |> Stream.filter(&(&1 != nil))
    |> Enum.reduce(0, fn payout, count ->
      record = {@affiliate_earnings_table,
        payout.token_id,
        payout.tier,
        downcase(payout.affiliate),
        payout.earnings,
        "",  # tx_hash - not in CSV
        payout.timestamp
      }

      :mnesia.dirty_write(record)
      count + 1
    end)
  end

  # ===== CSV Parsing =====

  defp parse_nft_row(line) do
    # CSV columns:
    # id,price,name,girl_type,image_url,token_url,multiplier,rarity,buyer,affiliate_1,affiliate_2,
    # affiliate_1_payout,affiliate_2_payout,contract_address,contract_address_token_id,minted_at,
    # usdt_earnings,arb_earnings,usdt_earnings_usd,arb_earnings_usd,all_earnings_usd,current_owner,
    # rogue_earnings,rogue_earnings_usd,usdt_earnings_balance,arb_earnings_balance,rogue_earnings_balance,
    # usdt_earnings_balance_usd,arb_earnings_balance_usd,rogue_earnings_balance_usd,all_earnings_balance_usd

    case parse_csv_line(line) do
      [id, price, name, girl_type, _image_url, _token_url, _multiplier, _rarity, buyer,
       affiliate_1, affiliate_2, _aff1_payout, _aff2_payout, _contract, _contract_token_id,
       minted_at, _usdt_e, _arb_e, _usdt_e_usd, _arb_e_usd, _all_e_usd, current_owner | _rest] ->

        %{
          token_id: parse_int(id),
          mint_price: String.trim(price),
          hostess_name: String.trim(name),
          hostess_index: parse_int(girl_type),
          original_buyer: String.trim(buyer),
          affiliate: String.trim(affiliate_1),
          affiliate2: String.trim(affiliate_2),
          created_at: parse_timestamp(minted_at),
          owner: String.trim(current_owner)
        }

      _ ->
        Logger.warning("[CSVImport] Failed to parse NFT row: #{String.slice(line, 0, 100)}")
        nil
    end
  rescue
    e ->
      Logger.warning("[CSVImport] Error parsing NFT row: #{inspect(e)}")
      nil
  end

  defp parse_affiliate_row(line) do
    # CSV columns:
    # id,token_id,price,hostess_name,image_uri,commission_rate,payout,buyer,affiliate,contract_address,tier,paid_at

    case parse_csv_line(line) do
      [_id, token_id, _price, _hostess_name, _image_uri, _commission_rate, payout,
       _buyer, affiliate, _contract_address, tier, paid_at | _rest] ->

        %{
          token_id: parse_int(token_id),
          tier: parse_int(tier),
          affiliate: String.trim(affiliate),
          earnings: String.trim(payout),
          timestamp: parse_timestamp(paid_at)
        }

      _ ->
        Logger.warning("[CSVImport] Failed to parse affiliate row: #{String.slice(line, 0, 100)}")
        nil
    end
  rescue
    e ->
      Logger.warning("[CSVImport] Error parsing affiliate row: #{inspect(e)}")
      nil
  end

  # Simple CSV parser - handles basic comma separation
  defp parse_csv_line(line) do
    line
    |> String.trim()
    |> String.split(",")
  end

  defp parse_int(str) when is_binary(str) do
    str
    |> String.trim()
    |> String.to_integer()
  end
  defp parse_int(num) when is_integer(num), do: num
  defp parse_int(_), do: 0

  defp parse_timestamp(str) when is_binary(str) do
    # Timestamps in CSV are in microseconds, convert to seconds
    microseconds = parse_int(str)
    div(microseconds, 1_000_000)
  end
  defp parse_timestamp(_), do: System.system_time(:second)

  defp downcase(nil), do: nil
  defp downcase(""), do: nil
  defp downcase(str) when is_binary(str), do: String.downcase(String.trim(str))

  # ===== Verification =====

  @doc """
  Verify import by checking counts and sample data.
  """
  def verify do
    nft_count = :mnesia.table_info(@nfts_table, :size)
    affiliate_count = :mnesia.table_info(@affiliate_earnings_table, :size)

    # Sample some NFTs
    sample_nfts = HighRollers.NFTStore.get_all()
    |> Enum.take(3)
    |> Enum.map(fn nft ->
      %{
        token_id: nft.token_id,
        owner: nft.owner,
        original_buyer: nft.original_buyer,
        hostess_name: nft.hostess_name,
        mint_price: nft.mint_price,
        affiliate: nft.affiliate,
        created_at: nft.created_at
      }
    end)

    %{
      nft_count: nft_count,
      affiliate_payout_count: affiliate_count,
      sample_nfts: sample_nfts
    }
  end
end
