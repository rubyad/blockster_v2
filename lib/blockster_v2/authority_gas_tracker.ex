defmodule BlocksterV2.AuthorityGasTracker do
  @moduledoc """
  Tracks daily gas spend for the Solana mint authority wallet.
  Records mint operations, ATA creations, and their associated costs.

  All data is stored in the :authority_gas_tracker Mnesia table (ram_copies).
  Key is a Date struct (e.g. ~D[2026-04-03]).

  Costs:
    - Transaction fee: 5000 lamports per mint
    - ATA rent: 2,039,280 lamports when a new ATA is created
  """

  require Logger

  @table :authority_gas_tracker
  @tx_fee_lamports 5_000
  @ata_rent_lamports 2_039_280

  @doc """
  Records a mint operation for today.
  Increments mint_count and tx fees. If `ata_created` is true, also
  increments ata_creations and adds ATA rent cost.
  """
  def record_mint(ata_created \\ false) do
    today = Date.utc_today()
    record = get_or_init(today)

    {_table, _date, mint_count, ata_creations, total_tx_fees, total_ata_rent, balance} = record

    new_mint_count = mint_count + 1
    new_tx_fees = total_tx_fees + @tx_fee_lamports

    {new_ata_creations, new_ata_rent} =
      if ata_created do
        {ata_creations + 1, total_ata_rent + @ata_rent_lamports}
      else
        {ata_creations, total_ata_rent}
      end

    updated = {@table, today, new_mint_count, new_ata_creations, new_tx_fees, new_ata_rent, balance}
    :mnesia.dirty_write(updated)
    :ok
  rescue
    e ->
      Logger.warning("[AuthorityGasTracker] record_mint failed: #{inspect(e)}")
      :error
  end

  @doc """
  Updates the authority wallet balance (in lamports) for today's record.
  """
  def update_authority_balance(lamports) when is_integer(lamports) do
    today = Date.utc_today()
    record = get_or_init(today)

    {_table, _date, mint_count, ata_creations, total_tx_fees, total_ata_rent, _old_balance} = record
    updated = {@table, today, mint_count, ata_creations, total_tx_fees, total_ata_rent, lamports}
    :mnesia.dirty_write(updated)
    :ok
  rescue
    e ->
      Logger.warning("[AuthorityGasTracker] update_authority_balance failed: #{inspect(e)}")
      :error
  end

  @doc """
  Returns today's gas tracking record as a map, or nil if no record exists.
  """
  def get_today do
    today = Date.utc_today()

    case :mnesia.dirty_read({@table, today}) do
      [{@table, date, mint_count, ata_creations, total_tx_fees, total_ata_rent, balance}] ->
        %{
          date: date,
          mint_count: mint_count,
          ata_creations: ata_creations,
          total_tx_fees_lamports: total_tx_fees,
          total_ata_rent_lamports: total_ata_rent,
          authority_balance_lamports: balance
        }

      [] ->
        nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Returns the last `days` days of gas tracking records (most recent first).
  """
  def get_daily_stats(days \\ 7) do
    today = Date.utc_today()

    dates =
      for i <- 0..(days - 1) do
        Date.add(today, -i)
      end

    dates
    |> Enum.map(fn date ->
      case :mnesia.dirty_read({@table, date}) do
        [{@table, d, mc, ac, tf, ar, bal}] ->
          %{
            date: d,
            mint_count: mc,
            ata_creations: ac,
            total_tx_fees_lamports: tf,
            total_ata_rent_lamports: ar,
            authority_balance_lamports: bal
          }

        [] ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  rescue
    _ -> []
  end

  @doc """
  Fetches the authority wallet's SOL balance from the settler service.
  Returns `{:ok, lamports}` or `{:error, reason}`.
  """
  def get_authority_balance do
    authority_address =
      Application.get_env(:blockster_v2, :solana_authority_address) ||
        "6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1"

    case BlocksterV2.BuxMinter.get_balance(authority_address) do
      {:ok, %{sol: sol}} ->
        lamports = round(sol * 1_000_000_000)
        {:ok, lamports}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Transaction fee per mint in lamports."
  def tx_fee_lamports, do: @tx_fee_lamports

  @doc "ATA rent-exempt cost in lamports."
  def ata_rent_lamports, do: @ata_rent_lamports

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp get_or_init(date) do
    case :mnesia.dirty_read({@table, date}) do
      [record] ->
        record

      [] ->
        # Initialize a fresh record for this date
        record = {@table, date, 0, 0, 0, 0, 0}
        :mnesia.dirty_write(record)
        record
    end
  end
end
