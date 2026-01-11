defmodule HighRollers.Fixtures do
  @moduledoc """
  Test data fixtures for High Rollers tests.

  Provides factory functions for creating test entities.
  """

  @doc """
  Generate a random wallet address.
  """
  def random_address do
    "0x" <> (:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower))
  end

  @doc """
  Generate a random transaction hash.
  """
  def random_tx_hash do
    "0x" <> (:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower))
  end

  @doc """
  Generate a random commitment hash (for reward events).
  """
  def random_commitment_hash do
    "0x" <> (:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower))
  end

  @doc """
  Build NFT attributes with defaults.
  """
  def nft_attrs(overrides \\ %{}) do
    now = System.system_time(:second)

    defaults = %{
      token_id: :rand.uniform(2700),
      owner: random_address(),
      original_buyer: nil,  # Will be set to owner if nil
      hostess_index: :rand.uniform(8) - 1,  # 0-7
      hostess_name: nil,  # Will be derived from hostess_index
      mint_tx_hash: random_tx_hash(),
      mint_block_number: :rand.uniform(100_000_000),
      mint_price: "320000000000000000",  # 0.32 ETH
      affiliate: nil,
      affiliate2: nil,
      total_earned: "0",
      pending_amount: "0",
      last_24h_earned: "0",
      apy_basis_points: 0,
      time_start_time: nil,
      time_last_claim: nil,
      time_total_claimed: nil,
      created_at: now,
      updated_at: now
    }

    attrs = Map.merge(defaults, overrides)

    # Set derived fields
    attrs = if attrs.original_buyer == nil do
      Map.put(attrs, :original_buyer, attrs.owner)
    else
      attrs
    end

    attrs = if attrs.hostess_name == nil do
      Map.put(attrs, :hostess_name, HighRollers.Hostess.name(attrs.hostess_index))
    else
      attrs
    end

    attrs
  end

  @doc """
  Build special NFT (time rewards) attributes.
  """
  def special_nft_attrs(overrides \\ %{}) do
    now = System.system_time(:second)
    token_id = 2340 + :rand.uniform(360)  # 2340-2700

    base = nft_attrs(Map.merge(%{
      token_id: token_id,
      time_start_time: now - 86400,  # Started 1 day ago
      time_last_claim: now - 3600,   # Last claim 1 hour ago
      time_total_claimed: "1000000000000000000"  # 1 ROGUE claimed
    }, overrides))

    base
  end

  @doc """
  Build reward event attributes.
  """
  def reward_event_attrs(overrides \\ %{}) do
    now = System.system_time(:second)

    defaults = %{
      commitment_hash: random_commitment_hash(),
      amount: "#{:rand.uniform(1000)}000000000000000000",  # 1-1000 ROGUE
      timestamp: now - :rand.uniform(86400),  # Within last 24h
      block_number: :rand.uniform(1_000_000),
      tx_hash: random_tx_hash()
    }

    Map.merge(defaults, overrides)
  end

  @doc """
  Build withdrawal attributes.
  """
  def withdrawal_attrs(overrides \\ %{}) do
    defaults = %{
      tx_hash: random_tx_hash(),
      user_address: random_address(),
      amount: "#{:rand.uniform(1000)}000000000000000000",
      token_ids: [1, 2, 3]
    }

    Map.merge(defaults, overrides)
  end

  @doc """
  Build affiliate earning attributes.
  """
  def affiliate_earning_attrs(overrides \\ %{}) do
    defaults = %{
      token_id: :rand.uniform(2700),
      tier: Enum.random([1, 2]),
      affiliate: random_address(),
      earnings: "16000000000000000",  # 0.016 ETH (5% of 0.32)
      tx_hash: random_tx_hash()
    }

    Map.merge(defaults, overrides)
  end

  @doc """
  Build user attributes.
  """
  def user_attrs(overrides \\ %{}) do
    now = System.system_time(:second)

    defaults = %{
      wallet_address: random_address(),
      affiliate: nil,
      affiliate2: nil,
      affiliate_balance: "0",
      total_affiliate_earned: "0",
      linked_at: nil,
      linked_on_chain: false,
      created_at: now,
      updated_at: now
    }

    Map.merge(defaults, overrides)
  end

  @doc """
  Build global stats attributes.
  """
  def global_stats_attrs(overrides \\ %{}) do
    defaults = %{
      total_rewards_received: "10000000000000000000000",  # 10K ROGUE
      total_rewards_distributed: "9000000000000000000000",  # 9K ROGUE
      rewards_last_24h: "500000000000000000000",  # 500 ROGUE
      overall_apy_basis_points: 1500,  # 15%
      total_nfts: 2342,
      total_multiplier_points: 109390
    }

    Map.merge(defaults, overrides)
  end

  @doc """
  Build hostess stats attributes.
  """
  def hostess_stats_attrs(hostess_index, overrides \\ %{}) do
    multipliers = [100, 90, 80, 70, 60, 50, 40, 30]
    multiplier = Enum.at(multipliers, hostess_index, 30)

    defaults = %{
      nft_count: 100,
      total_points: 100 * multiplier,
      share_basis_points: 1000,  # 10%
      last_24h_per_nft: "50000000000000000000",  # 50 ROGUE
      apy_basis_points: 1500,  # 15%
      time_24h_per_nft: "0",
      time_apy_basis_points: 0,
      special_nft_count: 0
    }

    Map.merge(defaults, overrides)
  end
end
