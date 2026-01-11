defmodule HighRollers.Contracts.NFTRewarderBehaviour do
  @moduledoc """
  Behaviour for NFTRewarder contract interactions.
  Enables mocking in tests via Mox.
  """

  @callback get_block_number() :: {:ok, integer()} | {:error, term()}
  @callback get_reward_received_events(integer(), integer()) :: {:ok, list(map())} | {:error, term()}
  @callback get_reward_claimed_events(integer(), integer()) :: {:ok, list(map())} | {:error, term()}
  @callback get_batch_nft_earnings(list(integer())) :: {:ok, list(map())} | {:error, term()}
  @callback get_global_totals() :: {:ok, map()} | {:error, term()}
  @callback get_time_reward_info(integer()) :: {:ok, map()} | {:error, term()}
  @callback get_nonce(String.t()) :: {:ok, integer()} | {:error, term()}
  @callback wait_for_receipt(String.t(), integer()) :: {:ok, map()} | {:error, term()}
  @callback get_owners_batch(list(integer())) :: {:ok, list(String.t())} | {:error, term()}
  @callback get_nft_owner(integer()) :: {:ok, String.t()} | {:error, term()}
  @callback send_raw_transaction(String.t()) :: {:ok, String.t()} | {:error, term()}
end
