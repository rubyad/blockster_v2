defmodule BlocksterV2.Encryption do
  @moduledoc """
  Handles encryption and decryption of sensitive data using AES-256-GCM.
  Uses the application's secret_key_base to derive the encryption key.
  """

  @aad "AES256GCM"

  @doc """
  Encrypts the given plaintext using AES-256-GCM.
  Returns the encrypted binary (IV + ciphertext + tag).
  """
  def encrypt(plaintext) when is_binary(plaintext) do
    key = get_key()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)

    iv <> tag <> ciphertext
  end

  def encrypt(nil), do: nil

  @doc """
  Decrypts the given encrypted binary.
  Returns the plaintext or nil if decryption fails.
  """
  def decrypt(encrypted) when is_binary(encrypted) and byte_size(encrypted) > 28 do
    key = get_key()
    <<iv::binary-12, tag::binary-16, ciphertext::binary>> = encrypted

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> plaintext
      :error -> nil
    end
  end

  def decrypt(_), do: nil

  defp get_key do
    secret_key_base =
      Application.get_env(:blockster_v2, BlocksterV2Web.Endpoint)[:secret_key_base]

    :crypto.hash(:sha256, secret_key_base)
  end
end
