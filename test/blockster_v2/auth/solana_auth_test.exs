defmodule BlocksterV2.Auth.SolanaAuthTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.Auth.SolanaAuth
  alias BlocksterV2.Auth.NonceStore

  setup do
    # Ensure NonceStore is running (started by application supervisor)
    # If not, start it for tests
    case GenServer.whereis(NonceStore) do
      nil ->
        {:ok, _} = NonceStore.start_link([])
      _pid ->
        :ok
    end

    :ok
  end

  describe "generate_challenge/1" do
    test "returns a SIWS message with wallet address" do
      wallet = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
      {:ok, challenge} = SolanaAuth.generate_challenge(wallet)

      assert challenge.message =~ "blockster.com wants you to sign in with your Solana account:"
      assert challenge.message =~ wallet
      assert challenge.message =~ "Sign in to Blockster"
      assert challenge.message =~ "Nonce: #{challenge.nonce}"
      assert challenge.message =~ "Version: 1"
      assert challenge.message =~ "URI: https://blockster.com"
      assert String.length(challenge.nonce) > 10
    end

    test "generates unique nonces" do
      wallet = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
      {:ok, c1} = SolanaAuth.generate_challenge(wallet)
      {:ok, c2} = SolanaAuth.generate_challenge(wallet)

      assert c1.nonce != c2.nonce
    end
  end

  describe "verify_signature/3" do
    test "rejects invalid nonce" do
      wallet = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"

      # Generate challenge but use a modified message with wrong nonce
      {:ok, _challenge} = SolanaAuth.generate_challenge(wallet)

      fake_message = """
      blockster.com wants you to sign in with your Solana account:
      #{wallet}

      Sign in to Blockster

      URI: https://blockster.com
      Version: 1
      Nonce: invalid_nonce_12345
      Issued At: 2026-04-02T00:00:00Z\
      """

      result = SolanaAuth.verify_signature(wallet, fake_message, "fakesig")
      assert {:error, :not_found} = result
    end

    test "rejects wallet mismatch" do
      wallet1 = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
      wallet2 = "9xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"

      {:ok, challenge} = SolanaAuth.generate_challenge(wallet1)

      # Try to verify with different wallet
      result = SolanaAuth.verify_signature(wallet2, challenge.message, "fakesig")
      assert {:error, :wallet_mismatch} = result
    end

    test "nonce is single-use" do
      wallet = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
      {:ok, challenge} = SolanaAuth.generate_challenge(wallet)

      # First attempt consumes nonce (will fail on sig verification but nonce is taken)
      _result = SolanaAuth.verify_signature(wallet, challenge.message, "fakesig")

      # Second attempt should fail with :not_found since nonce was consumed
      result = SolanaAuth.verify_signature(wallet, challenge.message, "fakesig")
      assert {:error, :not_found} = result
    end
  end

  describe "NonceStore" do
    test "put and take" do
      nonce = "test_nonce_#{:rand.uniform(1_000_000)}"
      wallet = "TestWalletAddress"

      :ok = NonceStore.put(nonce, wallet)
      assert {:ok, ^wallet} = NonceStore.take(nonce)
    end

    test "take removes nonce" do
      nonce = "test_nonce_#{:rand.uniform(1_000_000)}"
      :ok = NonceStore.put(nonce, "wallet")
      {:ok, _} = NonceStore.take(nonce)
      assert {:error, :not_found} = NonceStore.take(nonce)
    end

    test "unknown nonce returns not_found" do
      assert {:error, :not_found} = NonceStore.take("nonexistent_nonce")
    end
  end
end
