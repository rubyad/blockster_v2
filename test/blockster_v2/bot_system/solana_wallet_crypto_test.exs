defmodule BlocksterV2.BotSystem.SolanaWalletCryptoTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.BotSystem.SolanaWalletCrypto

  describe "generate_keypair/0" do
    test "returns a base58 pubkey that decodes to 32 bytes" do
      {pubkey, _secret} = SolanaWalletCrypto.generate_keypair()

      assert is_binary(pubkey)
      refute String.starts_with?(pubkey, "0x")
      assert byte_size(Base58.decode(pubkey)) == 32
    end

    test "returns a base58 secret key that decodes to 64 bytes (Solana format)" do
      {_pubkey, secret} = SolanaWalletCrypto.generate_keypair()

      assert is_binary(secret)
      refute String.starts_with?(secret, "0x")
      assert byte_size(Base58.decode(secret)) == 64
    end

    test "secret key contains the public key in its trailing 32 bytes" do
      # Standard Solana secret key layout: seed(32) || pubkey(32). Verify by
      # decoding both and confirming the second half matches the pubkey bytes.
      {pubkey, secret} = SolanaWalletCrypto.generate_keypair()

      pubkey_bytes = Base58.decode(pubkey)
      secret_bytes = Base58.decode(secret)
      <<_seed::binary-size(32), trailing_pubkey::binary-size(32)>> = secret_bytes

      assert trailing_pubkey == pubkey_bytes
    end

    test "generates unique keypairs across many invocations" do
      pubkeys = for _ <- 1..200, do: elem(SolanaWalletCrypto.generate_keypair(), 0)
      assert length(Enum.uniq(pubkeys)) == 200
    end
  end

  describe "solana_address?/1" do
    test "returns true for a freshly generated Solana pubkey" do
      {pubkey, _} = SolanaWalletCrypto.generate_keypair()
      assert SolanaWalletCrypto.solana_address?(pubkey)
    end

    test "returns false for nil" do
      refute SolanaWalletCrypto.solana_address?(nil)
    end

    test "returns false for an EVM 0x address" do
      refute SolanaWalletCrypto.solana_address?("0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0")
      refute SolanaWalletCrypto.solana_address?("0xdeadbeef")
    end

    test "returns false for malformed base58 strings" do
      refute SolanaWalletCrypto.solana_address?("not a real wallet")
      refute SolanaWalletCrypto.solana_address?("")
    end

    test "returns false for base58 that decodes to the wrong byte length" do
      # 16 bytes instead of 32 — valid base58 but wrong size for an ed25519 pubkey.
      short = Base58.encode(:crypto.strong_rand_bytes(16))
      refute SolanaWalletCrypto.solana_address?(short)
    end

    test "returns false for non-string inputs" do
      refute SolanaWalletCrypto.solana_address?(123)
      refute SolanaWalletCrypto.solana_address?(%{})
    end
  end
end
