defmodule BlocksterV2.BotSystem.SolanaWalletCrypto do
  @moduledoc """
  Generates Solana ed25519 keypairs for bot users.

  Replaces the legacy EVM `WalletCrypto` module. Each keypair consists of:
    * a 32-byte ed25519 public key (the Solana wallet address), base58-encoded
    * a 64-byte secret key in the standard Solana format
      (`seed(32) || pubkey(32)`), base58-encoded so it can be loaded directly
      by `@solana/web3.js`'s `Keypair.fromSecretKey()` if ever needed.
  """

  @doc """
  Generates a new Solana keypair.

  Returns `{base58_pubkey, base58_secret_key}` — both plain base58 strings,
  no `0x` prefix. The pubkey is what gets stored in `users.wallet_address`,
  the secret key is what gets stored in `users.bot_private_key`.
  """
  @spec generate_keypair() :: {String.t(), String.t()}
  def generate_keypair do
    {pubkey, seed} = :crypto.generate_key(:eddsa, :ed25519)
    secret_key = seed <> pubkey

    {Base58.encode(pubkey), Base58.encode(secret_key)}
  end

  @doc """
  Returns `true` if the given string decodes as a 32-byte base58 value
  (i.e. looks like a Solana ed25519 pubkey). Returns `false` for `nil`,
  `0x`-prefixed EVM addresses, malformed base58, or any other length.
  """
  @spec solana_address?(any()) :: boolean()
  def solana_address?(nil), do: false
  def solana_address?("0x" <> _), do: false

  def solana_address?(address) when is_binary(address) do
    try do
      decoded = Base58.decode(address)
      byte_size(decoded) == 32
    rescue
      _ -> false
    end
  end

  def solana_address?(_), do: false
end
