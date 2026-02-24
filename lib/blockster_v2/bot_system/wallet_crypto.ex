defmodule BlocksterV2.BotSystem.WalletCrypto do
  @moduledoc """
  Generates real Ethereum keypairs (private key + derived address)
  using secp256k1 and keccak256.
  """

  @doc """
  Generates a new Ethereum keypair.
  Returns `{address, private_key}` where both are 0x-prefixed hex strings.

  The address is derived from the private key using:
  1. secp256k1 elliptic curve to get the public key
  2. keccak256 hash of the uncompressed public key (minus 0x04 prefix)
  3. Last 20 bytes of the hash = Ethereum address
  """
  def generate_keypair do
    # Generate a random 32-byte private key
    private_key_bytes = :crypto.strong_rand_bytes(32)

    # Derive the public key using secp256k1
    {public_key_bytes, _} = :crypto.generate_key(:ecdh, :secp256k1, private_key_bytes)

    # public_key_bytes is 65 bytes: 0x04 prefix + 32 bytes X + 32 bytes Y
    # We need to hash the 64 bytes (without the 0x04 prefix)
    <<4, public_key_64::binary-size(64)>> = public_key_bytes

    # Keccak256 hash of the public key
    hash = ExKeccak.hash_256(public_key_64)

    # Ethereum address = last 20 bytes of the hash
    <<_first_12::binary-size(12), address_bytes::binary-size(20)>> = hash

    address = "0x" <> Base.encode16(address_bytes, case: :lower)
    private_key = "0x" <> Base.encode16(private_key_bytes, case: :lower)

    {address, private_key}
  end

  @doc """
  Derives an Ethereum address from a hex-encoded private key.
  Private key should be 0x-prefixed or raw 64-char hex.
  """
  def address_from_private_key(private_key_hex) do
    private_key_bytes =
      private_key_hex
      |> String.replace_leading("0x", "")
      |> Base.decode16!(case: :mixed)

    {public_key_bytes, _} = :crypto.generate_key(:ecdh, :secp256k1, private_key_bytes)
    <<4, public_key_64::binary-size(64)>> = public_key_bytes
    hash = ExKeccak.hash_256(public_key_64)
    <<_first_12::binary-size(12), address_bytes::binary-size(20)>> = hash

    "0x" <> Base.encode16(address_bytes, case: :lower)
  end
end
