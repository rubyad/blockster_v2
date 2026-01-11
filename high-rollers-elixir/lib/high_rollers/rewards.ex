defmodule HighRollers.Rewards do
  @moduledoc """
  Mnesia operations for reward events, withdrawals, and stats.

  NOTE: NFT earnings updates go through NFTStore GenServer (since earnings
  fields are now part of the unified hr_nfts table).
  """

  @events_table :hr_reward_events
  @withdrawals_table :hr_reward_withdrawals
  @stats_table :hr_stats

  # ===== REWARD EVENTS =====

  @doc "Insert a reward event (from RewardReceived blockchain event)"
  def insert_event(attrs) do
    # Use commitment_hash as natural key (unique bet ID from blockchain event)
    record = {@events_table,
      attrs.commitment_hash,
      attrs.amount,
      attrs.timestamp,
      attrs.block_number,
      attrs.tx_hash
    }

    :mnesia.dirty_write(record)
    :ok
  end

  @doc "Get total rewards since a given timestamp"
  def get_rewards_since(timestamp) do
    # Sum all amounts where timestamp > given timestamp
    :mnesia.dirty_select(@events_table, [
      {{@events_table, :_, :"$1", :"$2", :_, :_},
       [{:>, :"$2", timestamp}],
       [:"$1"]}
    ])
    |> Enum.reduce(0, fn amount_str, acc ->
      acc + String.to_integer(amount_str)
    end)
  end

  @doc "Get reward events with pagination"
  def get_events(limit \\ 50, offset \\ 0) do
    :mnesia.dirty_match_object({@events_table, :_, :_, :_, :_, :_})
    |> Enum.sort_by(fn record -> elem(record, 3) end, :desc)  # Sort by timestamp
    |> Enum.drop(offset)
    |> Enum.take(limit)
    |> Enum.map(&event_to_map/1)
  end

  @doc "Reset pending amount for an NFT after withdrawal"
  def reset_nft_pending(token_id) do
    HighRollers.NFTStore.update_earnings(token_id, %{pending_amount: "0"})
  end

  # ===== WITHDRAWALS =====

  @doc "Record a withdrawal (from RewardClaimed blockchain event)"
  def record_withdrawal(attrs) do
    # Use tx_hash as natural key (unique transaction hash)
    record = {@withdrawals_table,
      attrs.tx_hash,
      String.downcase(attrs.user_address),
      attrs.amount,
      attrs.token_ids,
      System.system_time(:second)
    }

    :mnesia.dirty_write(record)
    :ok
  end

  @doc "Get withdrawals for a user"
  def get_withdrawals_by_user(user_address, limit \\ 50) do
    address = String.downcase(user_address)
    :mnesia.dirty_index_read(@withdrawals_table, address, :user_address)
    |> Enum.sort_by(fn record -> elem(record, 5) end, :desc)  # Sort by timestamp
    |> Enum.take(limit)
    |> Enum.map(&withdrawal_to_map/1)
  end

  # ===== GLOBAL STATS =====
  # Uses hr_stats table with compound key :global

  @doc "Get global revenue stats"
  def get_global_stats do
    case :mnesia.dirty_read({@stats_table, :global}) do
      [{@stats_table, :global, data, _updated_at}] -> data
      [] -> nil
    end
  end

  @doc "Update global revenue stats"
  def update_global_stats(attrs) do
    record = {@stats_table,
      :global,
      %{
        total_rewards_received: attrs.total_rewards_received,
        total_rewards_distributed: attrs.total_rewards_distributed,
        rewards_last_24h: attrs.rewards_last_24h,
        overall_apy_basis_points: attrs.overall_apy_basis_points,
        total_nfts: attrs.total_nfts,
        total_multiplier_points: attrs.total_multiplier_points
      },
      System.system_time(:second)
    }

    :mnesia.dirty_write(record)
    :ok
  end

  # ===== HOSTESS STATS =====
  # Uses hr_stats table with compound key {:hostess, 0-7}

  @doc "Update stats for a specific hostess type"
  def update_hostess_stats(hostess_index, attrs) do
    record = {@stats_table,
      {:hostess, hostess_index},
      %{
        nft_count: attrs.nft_count,
        total_points: attrs.total_points,
        share_basis_points: attrs.share_basis_points,
        last_24h_per_nft: attrs.last_24h_per_nft,
        apy_basis_points: attrs.apy_basis_points,
        time_24h_per_nft: attrs.time_24h_per_nft,
        time_apy_basis_points: attrs.time_apy_basis_points,
        special_nft_count: attrs.special_nft_count
      },
      System.system_time(:second)
    }

    :mnesia.dirty_write(record)
    :ok
  end

  @doc "Get stats for all hostess types"
  def get_all_hostess_stats do
    Enum.map(0..7, fn index ->
      case :mnesia.dirty_read({@stats_table, {:hostess, index}}) do
        [{@stats_table, {:hostess, ^index}, data, _updated_at}] ->
          Map.put(data, :hostess_index, index)
        [] ->
          %{hostess_index: index}
      end
    end)
  end

  # ===== TIME REWARD STATS =====
  # Uses hr_stats table with compound key :time_rewards

  @doc "Get time reward global stats"
  def get_time_reward_stats do
    case :mnesia.dirty_read({@stats_table, :time_rewards}) do
      [{@stats_table, :time_rewards, data, _updated_at}] -> data
      [] -> nil
    end
  end

  @doc "Update time reward global stats"
  def update_time_reward_stats(attrs) do
    record = {@stats_table,
      :time_rewards,
      %{
        pool_deposited: attrs.pool_deposited,
        pool_remaining: attrs.pool_remaining,
        pool_claimed: attrs.pool_claimed,
        nfts_started: attrs.nfts_started
      },
      System.system_time(:second)
    }

    :mnesia.dirty_write(record)
    :ok
  end

  # ===== HELPERS =====

  defp event_to_map({@events_table, commitment_hash, amount, timestamp, block_number, tx_hash}) do
    %{
      commitment_hash: commitment_hash,
      amount: amount,
      timestamp: timestamp,
      block_number: block_number,
      tx_hash: tx_hash
    }
  end

  defp withdrawal_to_map({@withdrawals_table, tx_hash, user_address, amount, token_ids, timestamp}) do
    %{
      tx_hash: tx_hash,
      user_address: user_address,
      amount: amount,
      token_ids: token_ids,
      timestamp: timestamp
    }
  end
end
