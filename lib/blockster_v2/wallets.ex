defmodule BlocksterV2.Wallets do
  @moduledoc """
  Context for managing connected hardware wallets and wallet transfers.

  Handles:
  - Hardware wallet connection/disconnection (Postgres)
  - Token balance storage and retrieval (Mnesia)
  - Wallet transfer tracking (Postgres)
  """

  import Ecto.Query, warn: false
  require Logger
  alias BlocksterV2.Repo
  alias BlocksterV2.ConnectedWallet
  alias BlocksterV2.WalletTransfer

  ## Connected Wallets

  @doc """
  Gets the connected wallet for a user.
  Returns nil if no wallet is connected.
  """
  def get_connected_wallet(user_id) do
    Repo.get_by(ConnectedWallet, user_id: user_id)
  end

  @doc """
  Connects a wallet to a user account.
  Only one wallet can be connected at a time (enforced by unique constraint).
  """
  def connect_wallet(attrs) do
    result =
      %ConnectedWallet{}
      |> ConnectedWallet.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, wallet} ->
        BlocksterV2.UserEvents.track(wallet.user_id, "wallet_connected", %{
          provider: wallet.provider,
          address: wallet.wallet_address
        })
        {:ok, wallet}

      error ->
        error
    end
  end

  @doc """
  Updates a connected wallet.
  """
  def update_connected_wallet(%ConnectedWallet{} = wallet, attrs) do
    wallet
    |> ConnectedWallet.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Disconnects a wallet from a user account.
  """
  def disconnect_wallet(user_id) do
    case get_connected_wallet(user_id) do
      nil -> {:error, :not_found}
      wallet -> Repo.delete(wallet)
    end
  end

  @doc """
  Checks if a user has a connected wallet.
  """
  def has_connected_wallet?(user_id) do
    Repo.exists?(from w in ConnectedWallet, where: w.user_id == ^user_id)
  end

  @doc """
  Updates the last balance sync timestamp for a wallet.
  """
  def mark_balance_synced(user_id) do
    case get_connected_wallet(user_id) do
      nil -> {:error, :not_found}
      wallet ->
        update_connected_wallet(wallet, %{last_balance_sync_at: DateTime.utc_now()})
    end
  end

  ## Wallet Transfers

  @doc """
  Creates a new wallet transfer record.
  """
  def create_transfer(attrs) do
    %WalletTransfer{}
    |> WalletTransfer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a wallet transfer.
  """
  def update_transfer(%WalletTransfer{} = transfer, attrs) do
    transfer
    |> WalletTransfer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a transfer by transaction hash.
  """
  def get_transfer_by_tx_hash(tx_hash) do
    Repo.get_by(WalletTransfer, tx_hash: tx_hash)
  end

  @doc """
  Lists all transfers for a user, ordered by most recent first.
  """
  def list_user_transfers(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(t in WalletTransfer,
      where: t.user_id == ^user_id,
      order_by: [desc: t.inserted_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Marks a transfer as confirmed.
  """
  def confirm_transfer(tx_hash, block_number) do
    case get_transfer_by_tx_hash(tx_hash) do
      nil -> {:error, :not_found}
      transfer ->
        result = update_transfer(transfer, %{
          status: "confirmed",
          block_number: block_number,
          confirmed_at: DateTime.utc_now()
        })

        case result do
          {:ok, confirmed} ->
            if confirmed.token_symbol == "ROGUE" do
              net = net_rogue_deposits(confirmed.user_id)

              case confirmed.direction do
                "to_blockster" ->
                  BlocksterV2.UserEvents.track(confirmed.user_id, "rogue_deposited", %{
                    amount: to_string(confirmed.amount),
                    net_deposits: net,
                    tx_hash: confirmed.tx_hash
                  })

                "from_blockster" ->
                  BlocksterV2.UserEvents.track(confirmed.user_id, "rogue_withdrawn", %{
                    amount: to_string(confirmed.amount),
                    net_deposits: net,
                    tx_hash: confirmed.tx_hash
                  })

                _ -> :ok
              end
            end
            {:ok, confirmed}

          error ->
            error
        end
    end
  end

  @doc """
  Calculates net ROGUE deposits for a user (total deposited - total withdrawn).
  Only counts confirmed transfers. Returns a float.
  """
  def net_rogue_deposits(user_id) do
    result =
      from(t in WalletTransfer,
        where: t.user_id == ^user_id,
        where: t.token_symbol == "ROGUE",
        where: t.status == "confirmed",
        select: %{
          deposited: coalesce(sum(fragment("CASE WHEN direction = 'to_blockster' THEN amount ELSE 0 END")), 0),
          withdrawn: coalesce(sum(fragment("CASE WHEN direction = 'from_blockster' THEN amount ELSE 0 END")), 0)
        }
      )
      |> Repo.one()

    case result do
      %{deposited: d, withdrawn: w} -> Decimal.to_float(Decimal.sub(d, w))
      _ -> 0.0
    end
  end

  @doc """
  Marks a transfer as failed.
  """
  def fail_transfer(tx_hash, error_message) do
    case get_transfer_by_tx_hash(tx_hash) do
      nil -> {:error, :not_found}
      transfer ->
        update_transfer(transfer, %{
          status: "failed",
          error_message: error_message
        })
    end
  end

  ## Hardware Wallet Balances (Mnesia)

  @doc """
  Store or update hardware wallet balances in Mnesia.

  ## Parameters
  - user_id: User ID
  - wallet_address: Connected wallet address
  - balances: List of balance maps with keys: symbol, chain_id, balance, address, decimals

  ## Returns
  - {:ok, count} on success
  - {:error, reason} on failure
  """
  def store_balances(user_id, wallet_address, balances) when is_list(balances) do
    now = System.system_time(:second)

    results =
      Enum.map(balances, fn balance_map ->
        key = {user_id, balance_map.symbol, balance_map.chain_id}

        record = {
          :hardware_wallet_balances,
          key,
          user_id,
          wallet_address,
          balance_map.symbol,
          balance_map.chain_id,
          balance_map.balance,
          balance_map[:address],
          balance_map.decimals,
          now,
          now
        }

        :mnesia.dirty_write(record)
      end)

    # Check if all writes succeeded
    if Enum.all?(results, &(&1 == :ok)) do
      {:ok, length(balances)}
    else
      {:error, "Failed to store some balances"}
    end
  end

  @doc """
  Get all balances for a user's connected wallet.

  Returns a map grouped by symbol with combined balances across chains.
  """
  def get_user_balances(user_id) do
    :mnesia.dirty_index_read(:hardware_wallet_balances, user_id, :user_id)
    |> Enum.map(&parse_balance_record/1)
    |> group_by_symbol()
  end

  @doc """
  Get detailed balance breakdown by chain for a specific token.
  """
  def get_token_balances(user_id, symbol) do
    :mnesia.dirty_index_read(:hardware_wallet_balances, user_id, :user_id)
    |> Enum.filter(fn record ->
      elem(record, 4) == symbol
    end)
    |> Enum.map(&parse_balance_record/1)
    |> Enum.sort_by(& &1.chain_id)
  end

  @doc """
  Get the most recent balance fetch timestamp for a user.
  """
  def get_last_fetch_time(user_id) do
    case :mnesia.dirty_index_read(:hardware_wallet_balances, user_id, :user_id) do
      [] ->
        nil

      records ->
        records
        |> Enum.map(fn record -> elem(record, 9) end)
        |> Enum.max()
        |> DateTime.from_unix!()
    end
  end

  @doc """
  Clear all balances for a user (called when wallet is disconnected).
  """
  def clear_balances(user_id) do
    records = :mnesia.dirty_index_read(:hardware_wallet_balances, user_id, :user_id)

    Enum.each(records, fn record ->
      key = elem(record, 1)
      :mnesia.dirty_delete({:hardware_wallet_balances, key})
    end)

    {:ok, length(records)}
  end

  # Private functions for balance operations

  defp parse_balance_record(record) do
    %{
      user_id: elem(record, 2),
      wallet_address: elem(record, 3),
      symbol: elem(record, 4),
      chain_id: elem(record, 5),
      balance: elem(record, 6),
      token_address: elem(record, 7),
      decimals: elem(record, 8),
      last_fetched_at: elem(record, 9),
      updated_at: elem(record, 10)
    }
  end

  defp group_by_symbol(balances) do
    balances
    |> Enum.group_by(& &1.symbol)
    |> Enum.map(fn {symbol, token_balances} ->
      total_balance = Enum.reduce(token_balances, 0.0, &(&1.balance + &2))

      chain_breakdown =
        Enum.map(token_balances, fn b ->
          %{
            chain_id: b.chain_id,
            balance: b.balance,
            chain_name: chain_name(b.chain_id)
          }
        end)

      {symbol,
       %{
         total: total_balance,
         chains: chain_breakdown,
         last_updated: Enum.max_by(token_balances, & &1.last_fetched_at).last_fetched_at
       }}
    end)
    |> Map.new()
  end

  defp chain_name(1), do: "Ethereum"
  defp chain_name(42161), do: "Arbitrum"
  defp chain_name(560013), do: "Rogue Chain"
  defp chain_name(_), do: "Unknown"
end
