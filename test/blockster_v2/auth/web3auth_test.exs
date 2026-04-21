defmodule BlocksterV2.Auth.Web3AuthTest do
  use ExUnit.Case, async: false

  alias BlocksterV2.Auth.Web3Auth

  @expected_issuer "https://api-auth.web3auth.io"
  @test_audience "BFBFYsroKJuuISi3qWf4SWt5UiE-test-client-id"

  setup do
    # Seed a deterministic ES256 key for this test and flush the JWKS cache
    # so the verifier picks it up from our ETS insertion instead of hitting
    # the network.
    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, public_map} = JOSE.JWK.to_public(jwk) |> JOSE.JWK.to_map()
    kid = "test-kid-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    public_map = Map.merge(public_map, %{"kid" => kid, "alg" => "ES256", "use" => "sig"})

    # Ensure the cache table exists, then seed our test key into it.
    if :ets.whereis(:web3auth_jwks_cache) == :undefined do
      :ets.new(:web3auth_jwks_cache, [:named_table, :public, :set])
    end

    :ets.delete_all_objects(:web3auth_jwks_cache)
    :ets.insert(
      :web3auth_jwks_cache,
      {kid, public_map, :erlang.system_time(:second) + 3600}
    )

    {_, pem} = JOSE.JWK.to_pem(jwk)
    signer = Joken.Signer.create("ES256", %{"pem" => to_string(pem)}, %{"kid" => kid})

    {:ok, signer: signer, kid: kid, public_map: public_map}
  end

  defp sign_token(signer, claims) do
    defaults = %{
      "iss" => @expected_issuer,
      "aud" => @test_audience,
      "iat" => System.system_time(:second),
      "exp" => System.system_time(:second) + 300,
      "nonce" => Base.encode16(:crypto.strong_rand_bytes(4)),
      "verifier" => "web3auth",
      "verifierId" => "user@example.com",
      "userId" => "user@example.com",
      "email" => "user@example.com",
      "name" => "Alice",
      "authConnection" => "email_passwordless",
      "aggregateVerifier" => "web3auth-auth0-email-passwordless-sapphire-devnet",
      "wallets" => [
        %{
          "type" => "web3auth_app_key",
          "curve" => "ed25519",
          "public_key" => test_ed25519_pubkey_hex()
        },
        %{
          "type" => "web3auth_threshold_key",
          "curve" => "ed25519",
          "public_key" => "aaaaaa"
        }
      ]
    }

    Joken.generate_and_sign!(%{}, Map.merge(defaults, claims), signer)
  end

  defp test_ed25519_pubkey_hex do
    # Stable 32-byte test pubkey — just for claim-matching in tests.
    "d70fb3caa755a02b0a08feda8d8da5df3c762e9693fceffd6ea97d7070314f46"
  end

  defp test_ed25519_pubkey_b58 do
    "d70fb3caa755a02b0a08feda8d8da5df3c762e9693fceffd6ea97d7070314f46"
    |> Base.decode16!(case: :lower)
    |> Base58.encode()
  end

  describe "verify_id_token/2" do
    test "accepts a well-formed token signed by a cached JWK", ctx do
      token = sign_token(ctx.signer, %{})
      assert {:ok, claims} = Web3Auth.verify_id_token(token, expected_audience: @test_audience)
      assert claims.email == "user@example.com"
      assert claims.verifier == "web3auth"
      assert claims.solana_pubkey == test_ed25519_pubkey_b58()
    end

    test "matches expected_wallet_pubkey against the token's ed25519 wallet", ctx do
      token = sign_token(ctx.signer, %{})

      assert {:ok, _} =
               Web3Auth.verify_id_token(token,
                 expected_audience: @test_audience,
                 expected_wallet_pubkey: test_ed25519_pubkey_b58()
               )
    end

    test "rejects when expected_wallet_pubkey does not match", ctx do
      token = sign_token(ctx.signer, %{})
      assert {:error, {:wallet_mismatch, _}} =
               Web3Auth.verify_id_token(token,
                 expected_audience: @test_audience,
                 expected_wallet_pubkey: "bogus-pubkey-base58"
               )
    end

    test "rejects expired tokens", ctx do
      now = System.system_time(:second)
      token = sign_token(ctx.signer, %{"iat" => now - 3600, "exp" => now - 1800})
      assert {:error, :expired} = Web3Auth.verify_id_token(token, expected_audience: @test_audience)
    end

    test "rejects audience mismatch", ctx do
      token = sign_token(ctx.signer, %{"aud" => "some-other-client"})
      assert {:error, {:audience_mismatch, _}} =
               Web3Auth.verify_id_token(token, expected_audience: @test_audience)
    end

    test "rejects issuer mismatch", ctx do
      token = sign_token(ctx.signer, %{"iss" => "https://evil.example.com"})
      assert {:error, {:issuer_mismatch, _}} =
               Web3Auth.verify_id_token(token, expected_audience: @test_audience)
    end

    test "rejects tampered signatures", ctx do
      token = sign_token(ctx.signer, %{})
      [header, payload, _sig] = String.split(token, ".")
      # Replace the signature with random-ish bytes of matching length
      tampered = header <> "." <> payload <> "." <> Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false)
      assert {:error, {:signature_invalid, _}} =
               Web3Auth.verify_id_token(tampered, expected_audience: @test_audience)
    end

    test "rejects malformed tokens" do
      assert {:error, :malformed_token} =
               Web3Auth.verify_id_token("not-a-jwt", expected_audience: @test_audience)
    end
  end

  describe "claim normalization" do
    test "extracts Telegram fields when verifier is our custom JWT", ctx do
      token =
        sign_token(ctx.signer, %{
          "verifier" => "blockster-telegram",
          "authConnection" => "custom",
          "aggregateVerifier" => "custom-blockster-telegram",
          "userId" => "12345",
          "verifierId" => "12345",
          "telegram_user_id" => "12345",
          "telegram_username" => "alice_tg"
        })

      assert {:ok, claims} = Web3Auth.verify_id_token(token, expected_audience: @test_audience)
      assert claims.telegram_user_id == "12345"
      assert claims.telegram_username == "alice_tg"
      assert claims.verifier == "blockster-telegram"
    end

    test "extracts X user_id from twitter|<id> subject", ctx do
      token =
        sign_token(ctx.signer, %{
          "userId" => "twitter|987654321",
          "verifierId" => "twitter|987654321",
          "authConnection" => "twitter",
          "aggregateVerifier" => "web3auth-auth0-twitter-sapphire-devnet",
          "email" => nil
        })

      assert {:ok, claims} = Web3Auth.verify_id_token(token, expected_audience: @test_audience)
      assert claims.x_user_id == "987654321"
    end
  end
end
