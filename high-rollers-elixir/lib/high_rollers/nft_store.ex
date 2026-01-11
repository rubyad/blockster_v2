defmodule HighRollers.NFTStore do
  @moduledoc """
  Centralized access to the hr_nfts Mnesia table.

  Provides both read and write operations for NFT records.
  All writes are serialized through this GenServer.

  Writers:
  - ArbitrumEventPoller (on NFTMinted and Transfer events)
  - EarningsSyncer (on earnings sync)
  """
  use GenServer
  require Logger

  @table :hr_nfts

  # ===== Client API =====

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Insert or update an NFT record (serialized)"
  def upsert(attrs) do
    GenServer.call(__MODULE__, {:upsert, attrs})
  end

  @doc "Update NFT owner (serialized)"
  def update_owner(token_id, new_owner) do
    GenServer.call(__MODULE__, {:update_owner, token_id, new_owner})
  end

  @doc "Update NFT earnings (serialized)"
  def update_earnings(token_id, attrs) do
    GenServer.call(__MODULE__, {:update_earnings, token_id, attrs})
  end

  @doc "Get NFT by token_id (read - no serialization needed)"
  def get(token_id) do
    case :mnesia.dirty_read({@table, token_id}) do
      [record] -> record_to_map(record)
      [] -> nil
    end
  end

  @doc "Get all NFTs owned by address (read - no serialization needed)"
  def get_by_owner(owner) do
    owner_lower = String.downcase(owner)
    :mnesia.dirty_index_read(@table, owner_lower, :owner)
    |> Enum.map(&record_to_map/1)
  end

  @doc "Get all NFTs (read - no serialization needed)"
  def get_all do
    # Use dirty_select for efficiency - returns all records without needing exact tuple size
    :mnesia.dirty_select(@table, [{{@table, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}, [], [:'$_']}])
    |> Enum.map(&record_to_map/1)
  end

  @doc "Count NFTs (read - no serialization needed)"
  def count, do: :mnesia.table_info(@table, :size)

  @doc "Count NFTs by hostess index"
  def count_by_hostess(hostess_index) do
    :mnesia.dirty_index_read(@table, hostess_index, :hostess_index) |> length()
  end

  @doc "Get total multiplier points for all NFTs"
  def get_total_multiplier_points do
    get_all()
    |> Enum.reduce(0, fn nft, acc ->
      acc + HighRollers.Hostess.multiplier(nft.hostess_index)
    end)
  end

  @doc "Count special NFTs (2340-2700) by hostess type"
  def count_special_by_hostess(hostess_index) do
    :mnesia.dirty_index_read(@table, hostess_index, :hostess_index)
    |> Enum.filter(fn record -> elem(record, 1) >= 2340 and elem(record, 1) <= 2700 end)  # Position 1 = token_id
    |> length()
  end

  @doc """
  Get all special NFTs (token_ids 2340-2700) by owner.
  Pass nil to get ALL special NFTs regardless of owner.
  """
  def get_special_nfts_by_owner(owner) do
    records = if owner do
      owner_lower = String.downcase(owner)
      :mnesia.dirty_index_read(@table, owner_lower, :owner)
    else
      # Get all NFTs - use dirty_select for efficiency
      :mnesia.dirty_select(@table, [{{@table, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}, [], [:'$_']}])
    end

    records
    |> Enum.filter(fn record ->
      token_id = elem(record, 1)  # Position 1 = token_id
      token_id >= 2340 and token_id <= 2700
    end)
    |> Enum.map(&record_to_map/1)
  end

  @doc "Update time reward fields for a special NFT (serialized)"
  def update_time_reward(token_id, attrs) do
    GenServer.call(__MODULE__, {:update_time_reward, token_id, attrs})
  end

  @doc "Record a time reward claim (serialized)"
  def record_time_claim(token_id, claimed_amount) do
    GenServer.call(__MODULE__, {:record_time_claim, token_id, claimed_amount})
  end

  @doc "Get counts for all hostess types (0-7) as a map"
  def get_counts_by_hostess do
    Enum.reduce(0..7, %{}, fn index, acc ->
      Map.put(acc, index, count_by_hostess(index))
    end)
  end

  @doc "Get recent sales (minted NFTs sorted by created_at)"
  def get_recent_sales(limit \\ 10) do
    get_all()
    |> Enum.filter(fn nft -> nft.mint_tx_hash != nil end)
    |> Enum.sort_by(fn nft -> nft.created_at end, :desc)
    |> Enum.take(limit)
  end

  # ===== Pending Mints (separate table: hr_pending_mints) =====

  @pending_table :hr_pending_mints

  @doc "Insert a pending mint record (VRF waiting)"
  def insert_pending_mint(attrs) do
    record = {@pending_table,
      attrs.request_id,
      attrs.sender,
      attrs.token_id,
      attrs.price,
      attrs.tx_hash,
      System.system_time(:second)
    }
    :mnesia.dirty_write(record)
    :ok
  end

  @doc "Delete a pending mint record (VRF completed)"
  def delete_pending_mint(request_id) do
    :mnesia.dirty_delete({@pending_table, request_id})
    :ok
  end

  @doc "Get pending mint by request_id"
  def get_pending_mint(request_id) do
    case :mnesia.dirty_read({@pending_table, request_id}) do
      [{@pending_table, req_id, sender, token_id, price, tx_hash, created_at}] ->
        %{
          request_id: req_id,
          sender: sender,
          token_id: token_id,
          price: price,
          tx_hash: tx_hash,
          created_at: created_at
        }
      [] -> nil
    end
  end

  # ===== Server Callbacks =====

  @impl true
  def init(_opts) do
    Logger.info("[NFTStore] Started - serializing writes to hr_nfts")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:upsert, attrs}, _from, state) do
    now = System.system_time(:second)
    existing = get(attrs.token_id)
    created_at = if existing, do: existing.created_at, else: now

    # Unified hr_nfts schema (20 fields) - preserves existing values if not provided
    record = {@table,
      # Core Identity (positions 1-5)
      attrs.token_id,
      String.downcase(attrs.owner),
      String.downcase(attrs[:original_buyer] || attrs.owner),
      attrs.hostess_index,
      attrs.hostess_name,
      # Mint Data (positions 6-10)
      attrs[:mint_tx_hash],
      attrs[:mint_block_number],
      attrs[:mint_price],
      attrs[:affiliate] && String.downcase(attrs[:affiliate]),
      attrs[:affiliate2] && String.downcase(attrs[:affiliate2]),
      # Revenue Share Earnings (positions 11-14) - preserve existing or default to "0"
      (existing && existing.total_earned) || attrs[:total_earned] || "0",
      (existing && existing.pending_amount) || attrs[:pending_amount] || "0",
      (existing && existing.last_24h_earned) || attrs[:last_24h_earned] || "0",
      (existing && existing.apy_basis_points) || attrs[:apy_basis_points] || 0,
      # Time Rewards (positions 15-17) - nil for regular NFTs
      (existing && existing.time_start_time) || attrs[:time_start_time],
      (existing && existing.time_last_claim) || attrs[:time_last_claim],
      (existing && existing.time_total_claimed) || attrs[:time_total_claimed],
      # Timestamps (positions 18-19)
      created_at,
      now
    }

    :mnesia.dirty_write(record)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:update_owner, token_id, new_owner}, _from, state) do
    result =
      case :mnesia.dirty_read({@table, token_id}) do
        [record] ->
          # Position 2 = owner, Position 19 = updated_at (0-indexed in 20-field record)
          updated = put_elem(record, 2, String.downcase(new_owner))
          updated = put_elem(updated, 19, System.system_time(:second))
          :mnesia.dirty_write(updated)
          :ok

        [] ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_earnings, token_id, attrs}, _from, state) do
    # hr_nfts unified schema (20 fields):
    # Positions: 11=total_earned, 12=pending_amount, 13=last_24h_earned, 14=apy_basis_points, 19=updated_at
    result =
      case :mnesia.dirty_read({@table, token_id}) do
        [record] ->
          now = System.system_time(:second)
          updated = record
          |> then(fn r -> if attrs[:total_earned], do: put_elem(r, 11, attrs[:total_earned]), else: r end)
          |> then(fn r -> if attrs[:pending_amount], do: put_elem(r, 12, attrs[:pending_amount]), else: r end)
          |> then(fn r -> if attrs[:last_24h_earned], do: put_elem(r, 13, attrs[:last_24h_earned]), else: r end)
          |> then(fn r -> if attrs[:apy_basis_points], do: put_elem(r, 14, attrs[:apy_basis_points]), else: r end)
          |> put_elem(19, now)  # Position 19 = updated_at
          :mnesia.dirty_write(updated)
          :ok

        [] ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_time_reward, token_id, attrs}, _from, state) do
    # hr_nfts unified schema (20 fields):
    # Positions: 15=time_start_time, 16=time_last_claim, 17=time_total_claimed, 19=updated_at
    result =
      case :mnesia.dirty_read({@table, token_id}) do
        [record] ->
          now = System.system_time(:second)
          updated = record
          |> then(fn r -> if attrs[:time_start_time], do: put_elem(r, 15, attrs[:time_start_time]), else: r end)
          |> then(fn r -> if attrs[:time_last_claim], do: put_elem(r, 16, attrs[:time_last_claim]), else: r end)
          |> then(fn r -> if attrs[:time_total_claimed], do: put_elem(r, 17, attrs[:time_total_claimed]), else: r end)
          |> put_elem(19, now)  # Position 19 = updated_at
          :mnesia.dirty_write(updated)
          :ok

        [] ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:record_time_claim, token_id, claimed_amount}, _from, state) do
    # hr_nfts unified schema (20 fields):
    # Positions: 16=time_last_claim, 17=time_total_claimed, 19=updated_at
    result =
      case :mnesia.dirty_read({@table, token_id}) do
        [record] ->
          now = System.system_time(:second)
          current_total = elem(record, 17) || "0"  # Position 17 = time_total_claimed
          current_total_int = String.to_integer(current_total)
          new_total = Integer.to_string(current_total_int + claimed_amount)

          updated = record
          |> put_elem(16, now)        # Position 16 = time_last_claim
          |> put_elem(17, new_total)  # Position 17 = time_total_claimed
          |> put_elem(19, now)        # Position 19 = updated_at

          :mnesia.dirty_write(updated)
          Logger.info("[NFTStore] Recorded time claim for token #{token_id}: #{claimed_amount} wei")
          :ok

        [] ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  # ===== Helpers =====

  # Record layout matches unified hr_nfts schema (20 fields total):
  # {table, token_id, owner, original_buyer, hostess_index, hostess_name,
  #  mint_tx_hash, mint_block_number, mint_price, affiliate, affiliate2,
  #  total_earned, pending_amount, last_24h_earned, apy_basis_points,
  #  time_start_time, time_last_claim, time_total_claimed, created_at, updated_at}
  defp record_to_map({@table, token_id, owner, original_buyer, hostess_index, hostess_name,
                      mint_tx_hash, mint_block_number, mint_price, affiliate, affiliate2,
                      total_earned, pending_amount, last_24h_earned, apy_basis_points,
                      time_start_time, time_last_claim, time_total_claimed,
                      created_at, updated_at}) do
    %{
      token_id: token_id,
      owner: owner,
      original_buyer: original_buyer,
      hostess_index: hostess_index,
      hostess_name: hostess_name,
      mint_tx_hash: mint_tx_hash,
      mint_block_number: mint_block_number,
      mint_price: mint_price,
      affiliate: affiliate,
      affiliate2: affiliate2,
      total_earned: total_earned,
      pending_amount: pending_amount,
      last_24h_earned: last_24h_earned,
      apy_basis_points: apy_basis_points,
      time_start_time: time_start_time,
      time_last_claim: time_last_claim,
      time_total_claimed: time_total_claimed,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end
