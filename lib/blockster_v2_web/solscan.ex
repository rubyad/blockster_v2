defmodule BlocksterV2Web.Solscan do
  @moduledoc """
  Solscan URL helpers that branch on `WEB3AUTH_CHAIN_ID` for
  mainnet vs devnet cluster.

  Use these instead of hardcoding `?cluster=devnet` anywhere — there's no
  build-time guarantee Solscan links match the configured RPC.

  Convention (Web3Auth ws-embed chain IDs, NOT the public docs `0x1/0x2/0x3`):
    * `0x65` → Solana mainnet (no `?cluster=...`)
    * `0x67` → Solana devnet (`?cluster=devnet`) — default fallback
  """

  @doc "Solscan tx URL for the given signature. `nil`/empty returns `\"#\"`."
  def tx_url(nil), do: "#"
  def tx_url(""), do: "#"
  def tx_url(sig) when is_binary(sig), do: "https://solscan.io/tx/#{sig}#{cluster_query()}"

  @doc "Solscan account URL for the given pubkey/wallet address."
  def account_url(nil), do: "#"
  def account_url(""), do: "#"
  def account_url(addr) when is_binary(addr),
    do: "https://solscan.io/account/#{addr}#{cluster_query()}"

  @doc "Solscan token URL for the given mint pubkey."
  def token_url(nil), do: "#"
  def token_url(""), do: "#"
  def token_url(mint) when is_binary(mint),
    do: "https://solscan.io/token/#{mint}#{cluster_query()}"

  @doc "Solscan home URL pinned to the current cluster."
  def home_url, do: "https://solscan.io/#{cluster_query()}"

  @doc """
  Returns true on mainnet (WEB3AUTH_CHAIN_ID=0x65), false otherwise.
  Useful for narrative copy that should change post-launch.
  """
  def mainnet?, do: System.get_env("WEB3AUTH_CHAIN_ID") == "0x65"

  defp cluster_query do
    case System.get_env("WEB3AUTH_CHAIN_ID") do
      "0x65" -> ""
      _ -> "?cluster=devnet"
    end
  end
end
