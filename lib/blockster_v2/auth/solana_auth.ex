defmodule BlocksterV2.Auth.SolanaAuth do
  @moduledoc """
  Ed25519 SIWS (Sign-In With Solana) authentication.
  Generates challenges and verifies Ed25519 signatures.
  """

  alias BlocksterV2.Auth.NonceStore

  @domain "blockster.com"
  @statement "Sign in to Blockster"

  def generate_challenge(wallet_address) do
    nonce = generate_nonce()
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    message = build_siws_message(wallet_address, nonce, timestamp)

    :ok = NonceStore.put(nonce, wallet_address)

    {:ok, %{message: message, nonce: nonce}}
  end

  def verify_signature(wallet_address, message, signature_b58) do
    with {:ok, nonce} <- extract_nonce(message),
         {:ok, stored_wallet} <- NonceStore.take(nonce),
         :ok <- verify_wallet_match(wallet_address, stored_wallet),
         {:ok, pubkey_bytes} <- decode_base58(wallet_address),
         {:ok, sig_bytes} <- decode_base58(signature_b58),
         :ok <- verify_ed25519(pubkey_bytes, message, sig_bytes) do
      {:ok, wallet_address}
    end
  end

  defp build_siws_message(wallet_address, nonce, timestamp) do
    """
    #{@domain} wants you to sign in with your Solana account:
    #{wallet_address}

    #{@statement}

    URI: https://#{@domain}
    Version: 1
    Nonce: #{nonce}
    Issued At: #{timestamp}\
    """
  end

  defp generate_nonce do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp extract_nonce(message) do
    case Regex.run(~r/Nonce: (.+)/, message) do
      [_, nonce] -> {:ok, nonce}
      _ -> {:error, :invalid_message}
    end
  end

  defp verify_wallet_match(wallet_address, stored_wallet) do
    if wallet_address == stored_wallet, do: :ok, else: {:error, :wallet_mismatch}
  end

  defp decode_base58(encoded) do
    try do
      {:ok, Base58.decode(encoded)}
    rescue
      _ -> {:error, :invalid_base58}
    end
  end

  defp verify_ed25519(pubkey_bytes, message, sig_bytes)
       when byte_size(pubkey_bytes) == 32 and byte_size(sig_bytes) == 64 do
    case :crypto.verify(:eddsa, :none, message, sig_bytes, [pubkey_bytes, :ed25519]) do
      true -> :ok
      false -> {:error, :invalid_signature}
    end
  end

  defp verify_ed25519(_, _, _), do: {:error, :invalid_signature}
end
