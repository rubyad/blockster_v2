defmodule HighRollers.Contracts.NFTContractBehaviour do
  @moduledoc """
  Behaviour for NFT contract interactions.
  Enables mocking in tests via Mox.
  """

  @callback get_block_number() :: {:ok, integer()} | {:error, term()}
  @callback get_nft_requested_events(integer(), integer()) :: {:ok, list(map())} | {:error, term()}
  @callback get_nft_minted_events(integer(), integer()) :: {:ok, list(map())} | {:error, term()}
  @callback get_transfer_events(integer(), integer()) :: {:ok, list(map())} | {:error, term()}
  @callback get_total_supply() :: {:ok, integer()} | {:error, term()}
  @callback get_owner_of(integer()) :: {:ok, String.t()} | {:error, term()}
  @callback get_hostess_index(integer()) :: {:ok, integer()} | {:error, term()}
  @callback get_nonce(String.t()) :: {:ok, integer()} | {:error, term()}
end
