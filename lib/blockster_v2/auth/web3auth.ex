defmodule BlocksterV2.Auth.Web3Auth do
  @moduledoc """
  Verifies Web3Auth-issued ID tokens (ES256 JWTs signed by their JWKS at
  `https://api-auth.web3auth.io/jwks`).

  Returns a normalized map of claims Phase 3 uses to create or look up users.

  Cache model: the JWKS is fetched on demand + cached in ETS (keyed by `kid`)
  with a 1h refresh window. A `kid` miss triggers a single refresh; repeated
  misses do NOT spam the JWKS endpoint.

  Not to be confused with `BlocksterV2.Auth.Web3AuthSigning`, which is our
  own JWT issuer for the Telegram path (we sign → Web3Auth's dashboard
  verifier consumes). That flow is orthogonal.
  """
  require Logger

  alias BlocksterV2.Auth.Web3Auth.JwksCache

  @jwks_url "https://api-auth.web3auth.io/jwks"
  @expected_issuer "https://api-auth.web3auth.io"
  @clock_skew_seconds 60

  @doc """
  Verify a Web3Auth-issued ID token.

  `opts`:
    * `:expected_wallet_pubkey` — if provided, the token's `wallets` array
      must include a matching `public_key` (ed25519 curve). Use this when
      the client ALSO sent us the claimed wallet pubkey — we verify it
      against the JWT claim so the client can't spoof a different wallet.
    * `:expected_audience` — defaults to the `WEB3AUTH_CLIENT_ID` env var.
      Override for tests.
    * `:now` — unix timestamp for clock comparisons (default: current).

  Returns `{:ok, normalized_claims}` or `{:error, reason}`.
  """
  def verify_id_token(token, opts \\ []) when is_binary(token) do
    with {:ok, jws} <- peek_header(token),
         {:ok, kid} <- fetch_kid(jws),
         {:ok, jwk} <- JwksCache.get(kid, @jwks_url),
         {:ok, claims} <- verify_and_check(token, jwk, opts),
         :ok <- check_audience(claims, opts),
         :ok <- check_issuer(claims),
         :ok <- check_expiration(claims, opts),
         :ok <- check_wallets(claims, opts) do
      {:ok, normalize(claims)}
    end
  end

  # ---------------------------------------------------------
  # Header + key lookup
  # ---------------------------------------------------------

  defp peek_header(token) do
    try do
      case Joken.peek_header(token) do
        {:ok, header} -> {:ok, header}
        header when is_map(header) -> {:ok, header}
        _ -> {:error, :malformed_token}
      end
    rescue
      _ -> {:error, :malformed_token}
    end
  end

  defp fetch_kid(%{"kid" => kid}) when is_binary(kid), do: {:ok, kid}
  defp fetch_kid(_), do: {:error, :missing_kid}

  # ---------------------------------------------------------
  # Signature verification
  # ---------------------------------------------------------

  # Web3Auth rotates keys + uses ES256 today. Detect the algorithm from the
  # JWK rather than hardcoding — keeps us tolerant if they switch to RS256.
  defp verify_and_check(token, jwk_map, _opts) do
    alg = jwk_map["alg"] || infer_alg(jwk_map)

    signer =
      case alg do
        "ES256" -> Joken.Signer.create("ES256", %{"pem" => jwk_to_pem(jwk_map)})
        "RS256" -> Joken.Signer.create("RS256", %{"pem" => jwk_to_pem(jwk_map)})
        other -> {:error, {:unsupported_alg, other}}
      end

    case signer do
      {:error, reason} ->
        {:error, reason}

      %Joken.Signer{} = signer ->
        case Joken.verify(token, signer) do
          {:ok, claims} -> {:ok, claims}
          {:error, reason} -> {:error, {:signature_invalid, reason}}
        end
    end
  end

  defp infer_alg(%{"kty" => "EC"}), do: "ES256"
  defp infer_alg(%{"kty" => "RSA"}), do: "RS256"
  defp infer_alg(_), do: "ES256"

  defp jwk_to_pem(jwk_map) do
    {_type, pem} = JOSE.JWK.from_map(jwk_map) |> JOSE.JWK.to_pem()
    pem
  end

  # ---------------------------------------------------------
  # Claim checks
  # ---------------------------------------------------------

  defp check_audience(%{"aud" => aud}, opts) do
    expected =
      (opts[:expected_audience] || System.get_env("WEB3AUTH_CLIENT_ID") || "")
      |> to_string()
      |> String.trim()
      |> String.trim("\"")
      |> String.trim("'")
      |> String.trim()

    # Clean aud too — Web3Auth occasionally wraps string claims in extra
    # whitespace that survives the JWT parse.
    aud_clean =
      case aud do
        s when is_binary(s) -> String.trim(s)
        list when is_list(list) -> Enum.map(list, fn x -> if is_binary(x), do: String.trim(x), else: x end)
        other -> other
      end

    cond do
      expected == "" ->
        Logger.warning("[Web3Auth] WEB3AUTH_CLIENT_ID not configured — accepting any aud")
        :ok

      aud_clean == expected or (is_list(aud_clean) and expected in aud_clean) ->
        :ok

      true ->
        Logger.warning(
          "[Web3Auth] audience mismatch — got=#{inspect(aud_clean)} expected=#{inspect(expected)}"
        )

        {:error, {:audience_mismatch, %{got: aud_clean, expected: expected}}}
    end
  end

  defp check_audience(_, _), do: {:error, :missing_audience}

  defp check_issuer(%{"iss" => iss}) when iss == @expected_issuer, do: :ok
  defp check_issuer(claims), do: {:error, {:issuer_mismatch, Map.get(claims, "iss")}}

  defp check_expiration(%{"exp" => exp}, opts) when is_integer(exp) do
    now = opts[:now] || System.system_time(:second)
    if now > exp + @clock_skew_seconds, do: {:error, :expired}, else: :ok
  end

  defp check_expiration(_, _), do: {:error, :missing_exp}

  defp check_wallets(claims, opts) do
    case opts[:expected_wallet_pubkey] do
      nil ->
        :ok

      expected when is_binary(expected) ->
        wallets = claims["wallets"] || []

        case find_solana_wallet(wallets) do
          nil ->
            {:error, :no_solana_wallet_in_token}

          %{"public_key" => hex_pubkey} ->
            if solana_pubkey_from_hex(hex_pubkey) == expected do
              :ok
            else
              {:error, {:wallet_mismatch, %{expected: expected, got: hex_pubkey}}}
            end
        end
    end
  end

  # Web3Auth's idToken `wallets` array carries one entry per curve
  # (ed25519 for Solana, secp256k1 for EVM). We only care about ed25519.
  defp find_solana_wallet(wallets) do
    Enum.find(wallets, fn w ->
      curve = Map.get(w, "curve")
      type = Map.get(w, "type")
      curve == "ed25519" and type == "web3auth_app_key"
    end)
  end

  # Convert a 32-byte hex-encoded ed25519 public key to Solana's base58 form.
  defp solana_pubkey_from_hex(hex) when is_binary(hex) do
    case Base.decode16(String.downcase(hex), case: :lower) do
      {:ok, bytes} when byte_size(bytes) == 32 -> Base58.encode(bytes)
      _ -> nil
    end
  end

  defp solana_pubkey_from_hex(_), do: nil

  # ---------------------------------------------------------
  # Normalization
  # ---------------------------------------------------------

  defp normalize(claims) do
    solana_pubkey =
      case find_solana_wallet(claims["wallets"] || []) do
        %{"public_key" => hex} -> solana_pubkey_from_hex(hex)
        _ -> nil
      end

    %{
      solana_pubkey: solana_pubkey,
      email: Map.get(claims, "email"),
      name: Map.get(claims, "name"),
      profile_image: Map.get(claims, "profileImage"),
      verifier: Map.get(claims, "verifier"),
      aggregate_verifier: Map.get(claims, "aggregateVerifier"),
      auth_connection: Map.get(claims, "authConnection"),
      verifier_id: Map.get(claims, "verifierId"),
      user_id: Map.get(claims, "userId"),
      # Present when the identity path is Telegram (our custom JWT)
      telegram_user_id: Map.get(claims, "telegram_user_id"),
      telegram_username: Map.get(claims, "telegram_username"),
      # Present when the identity path is X/Twitter
      x_handle: Map.get(claims, "name") |> twitter_handle_from_name(),
      x_user_id: twitter_id_from_userid(Map.get(claims, "userId")),
      raw: claims
    }
  end

  # Web3Auth's Twitter login sets userId to "twitter|<numeric_id>" — extract.
  defp twitter_id_from_userid("twitter|" <> id), do: id
  defp twitter_id_from_userid(_), do: nil

  # `name` for Twitter logins is the display name, NOT the @handle. The handle
  # isn't reliably present in the default claims, so we leave this as nil for
  # now — callers that need it should fetch via X API. Placeholder preserved
  # to keep the shape stable when that flow lands.
  defp twitter_handle_from_name(_), do: nil

  # ---------------------------------------------------------
  # JWKS cache (ETS, lazy, 1h TTL)
  # ---------------------------------------------------------

  defmodule JwksCache do
    @moduledoc false
    @table :web3auth_jwks_cache
    @ttl_seconds 3600

    def get(kid, url) do
      ensure_table()
      now = :erlang.system_time(:second)

      case :ets.lookup(@table, kid) do
        [{^kid, jwk, expires_at}] ->
          if expires_at > now do
            {:ok, jwk}
          else
            refresh_and_get(kid, url)
          end

        _ ->
          refresh_and_get(kid, url)
      end
    end

    defp refresh_and_get(kid, url) do
      case refresh(url) do
        {:ok, keys} ->
          store(keys)

          case :ets.lookup(@table, kid) do
            [{^kid, jwk, _}] -> {:ok, jwk}
            [] -> {:error, {:unknown_kid, kid}}
          end

        {:error, reason} ->
          {:error, {:jwks_fetch_failed, reason}}
      end
    end

    defp ensure_table do
      if :ets.whereis(@table) == :undefined do
        :ets.new(@table, [:named_table, :public, :set, {:read_concurrency, true}])
      end
    end

    defp refresh(url) do
      case Req.get(url, receive_timeout: 10_000, retry: :safe_transient, max_retries: 2) do
        {:ok, %{status: 200, body: %{"keys" => keys}}} when is_list(keys) -> {:ok, keys}
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, reason}
      end
    end

    defp store(keys) do
      expires_at = :erlang.system_time(:second) + @ttl_seconds

      Enum.each(keys, fn key ->
        case Map.get(key, "kid") do
          nil -> :ok
          kid -> :ets.insert(@table, {kid, key, expires_at})
        end
      end)
    end
  end
end
