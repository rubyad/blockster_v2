defmodule HighRollers.TimeRewards do
  @moduledoc """
  Pure calculation functions for time-based rewards.

  Special NFTs (2340-2700) earn time-based rewards for 180 days after minting.
  Each hostess type has a different rate per second.

  NO STATE - all functions are pure and take data as arguments.
  """

  @special_nft_start 2340
  @special_nft_end 2700
  @duration_seconds 180 * 24 * 60 * 60  # 180 days

  # Rates per second in wei (from NFTRewarder contract)
  @time_reward_rates %{
    0 => 2_125_029_000_000_000_000,  # Penelope (100x)
    1 => 1_912_007_000_000_000_000,  # Mia (90x)
    2 => 1_700_492_000_000_000_000,  # Cleo (80x)
    3 => 1_487_470_000_000_000_000,  # Sophia (70x)
    4 => 1_274_962_000_000_000_000,  # Luna (60x)
    5 => 1_062_454_000_000_000_000,  # Aurora (50x)
    6 => 849_946_000_000_000_000,    # Scarlett (40x)
    7 => 637_438_000_000_000_000     # Vivienne (30x)
  }

  @doc "Check if token ID is a special NFT with time rewards"
  def special_nft?(token_id), do: token_id >= @special_nft_start and token_id <= @special_nft_end

  @doc """
  Get time reward info for an NFT by token_id.
  Fetches data from unified hr_nfts table (via NFTStore) and calculates pending rewards.
  Returns zero_reward() for non-special NFTs.
  """
  def get_nft_time_info(token_id) do
    if special_nft?(token_id) do
      # All NFT data including time rewards is in unified hr_nfts table
      case HighRollers.NFTStore.get(token_id) do
        nil -> zero_reward()
        nft ->
          calculate_pending(%{
            start_time: nft.time_start_time,
            last_claim_time: nft.time_last_claim,
            hostess_index: nft.hostess_index,
            total_claimed: nft.time_total_claimed
          })
      end
    else
      zero_reward()
    end
  end

  @doc "Get rate per second in wei for a hostess type"
  def rate_per_second_wei(hostess_index), do: Map.get(@time_reward_rates, hostess_index, 0)

  @doc "Get rate per second in ROGUE (float)"
  def rate_per_second(hostess_index), do: rate_per_second_wei(hostess_index) / 1.0e18

  @doc "Calculate pending time reward for an NFT"
  def calculate_pending(%{start_time: nil}), do: zero_reward()
  def calculate_pending(%{start_time: 0}), do: zero_reward()

  def calculate_pending(%{
    start_time: start_time,
    last_claim_time: last_claim_time,
    hostess_index: hostess_index,
    total_claimed: total_claimed
  }) do
    now = System.system_time(:second)
    end_time = start_time + @duration_seconds
    current_time = min(now, end_time)
    time_remaining = max(0, end_time - now)
    claim_time = last_claim_time || start_time

    # Time elapsed since last claim
    time_elapsed = max(0, current_time - claim_time)

    rate_wei = rate_per_second_wei(hostess_index)
    pending_wei = div(rate_wei * time_elapsed, round(1.0e18))

    # Total for 180 days
    total_for_180_days_wei = div(rate_wei * @duration_seconds, round(1.0e18))

    # Total earned since start (use same calculation method as pending for consistency)
    total_time_since_start = max(0, current_time - start_time)
    total_earned = div(rate_wei * total_time_since_start, round(1.0e18))

    # 24h earnings (overlap calculation)
    one_day_ago = now - 86400
    window_start = max(start_time, one_day_ago)
    window_end = min(end_time, now)
    last_24h = if window_end > window_start do
      rate_per_second(hostess_index) * (window_end - window_start)
    else
      0
    end

    percent_complete = min(100.0, (now - start_time) / @duration_seconds * 100)

    %{
      pending: pending_wei,
      pending_wei: Integer.to_string(pending_wei),
      rate_per_second: rate_per_second(hostess_index),
      time_remaining: time_remaining,
      total_for_180_days: total_for_180_days_wei,
      last_24h: last_24h,
      total_earned: total_earned,
      total_claimed: total_claimed || 0,
      start_time: start_time,
      last_claim_time: claim_time,  # For JS hook - when last claim happened (or start_time if never claimed)
      end_time: end_time,
      is_special: true,
      has_started: true,
      percent_complete: Float.round(percent_complete * 1.0, 2)
    }
  end

  @doc "Calculate hostess time stats for APY display"
  def calculate_hostess_time_stats(hostess_index, nft_value_in_rogue_wei) do
    rate_wei = rate_per_second_wei(hostess_index)

    # 24h earnings = rate * 86400
    time_24h_wei = div(rate_wei * 86400, round(1.0e18))

    # APY: (total_for_180_days × 365/180) / nft_value × 10000
    total_180_days_wei = div(rate_wei * @duration_seconds, round(1.0e18))
    annualized = div(total_180_days_wei * 365, 180)

    time_apy =
      if nft_value_in_rogue_wei > 0 do
        div(annualized * 10000 * round(1.0e18), nft_value_in_rogue_wei)
      else
        0
      end

    {time_24h_wei, time_apy}
  end

  @doc "Calculate global 24h time rewards across all special NFTs"
  def calculate_global_24h(time_reward_nfts) do
    now = System.system_time(:second)
    one_day_ago = now - 86400

    Enum.reduce(time_reward_nfts, {0, List.duplicate(0, 8)}, fn nft, {global, hostess_list} ->
      if nft.start_time && nft.start_time > 0 do
        end_time = nft.start_time + @duration_seconds
        rate = rate_per_second(nft.hostess_index)

        window_start = max(nft.start_time, one_day_ago)
        window_end = min(end_time, now)

        nft_24h = if window_end > window_start do
          rate * (window_end - window_start)
        else
          0
        end

        new_hostess = List.update_at(hostess_list, nft.hostess_index, &(&1 + nft_24h))
        {global + nft_24h, new_hostess}
      else
        {global, hostess_list}
      end
    end)
  end

  @doc """
  Record a time reward claim for a special NFT.
  Updates last_claim_time to now and adds claimed amount to total.
  Called after successful claimTimeRewards blockchain transaction.
  """
  def record_claim(token_id) do
    case get_nft_time_info(token_id) do
      %{pending: pending} when pending > 0 ->
        # Record claim in NFTStore - updates last_claim to now
        HighRollers.NFTStore.record_time_claim(token_id, pending)
      _ ->
        :ok
    end
  end

  defp zero_reward do
    %{
      pending: 0,
      pending_wei: "0",
      rate_per_second: 0,
      time_remaining: 0,
      total_for_180_days: 0,
      last_24h: 0,
      total_earned: 0,
      total_claimed: 0,
      start_time: 0,
      end_time: 0,
      is_special: false,
      has_started: false,
      percent_complete: 0
    }
  end
end
