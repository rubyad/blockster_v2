defmodule BlocksterV2.Auth.Web3AuthSigning do
  @moduledoc """
  RSA keypair + JWT signing for Web3Auth's Custom JWT verifier path
  (used today for Telegram login; extensible to any bot-driven identity).

  On first call the module generates a 2048-bit RSA keypair and persists it
  to `priv/web3auth_keys/signing_key.json` (gitignored). Subsequent boots
  load the same key so JWKS stays stable across restarts. Production should
  set `WEB3AUTH_JWT_SIGNING_KEY_PATH` to point at a Fly.io secret-mounted
  file instead of the priv location.

  Exposes:
    * `sign_id_token/1` — returns a signed compact JWT string.
    * `jwks/0` — returns the public JWKS response body (map).
    * `kid/0` — key ID for JWT `kid` header.
  """

  use Agent
  require Logger

  @issuer "blockster"
  @audience "blockster-web3auth"
  @ttl_seconds 600

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(&load_or_generate/0, name: name)
  end

  def child_spec(arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, type: :worker}
  end

  defp load_or_generate do
    path = signing_key_path()

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{"pem" => pem, "kid" => kid}} -> %{pem: pem, kid: kid}
          _ -> generate_and_persist(path)
        end

      _ ->
        generate_and_persist(path)
    end
  end

  defp generate_and_persist(path) do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_, pem_bin} = JOSE.JWK.to_pem(jwk)
    pem = to_string(pem_bin)
    kid = :crypto.hash(:sha256, pem) |> Base.encode16(case: :lower) |> binary_part(0, 16)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{pem: pem, kid: kid}))
    Logger.info("[Web3AuthSigning] generated new signing key at #{path} (kid=#{kid})")
    %{pem: pem, kid: kid}
  end

  defp signing_key_path do
    System.get_env("WEB3AUTH_JWT_SIGNING_KEY_PATH") ||
      Path.join(:code.priv_dir(:blockster_v2), "web3auth_keys/signing_key.json")
  end

  def kid(server \\ __MODULE__), do: Agent.get(server, & &1.kid)

  def sign_id_token(claims, server \\ __MODULE__) when is_map(claims) do
    %{pem: pem, kid: kid} = Agent.get(server, & &1)
    now = System.system_time(:second)

    payload =
      claims
      |> Map.merge(%{
        "iss" => @issuer,
        "aud" => @audience,
        "iat" => now,
        "exp" => now + @ttl_seconds
      })

    jwk = JOSE.JWK.from_pem(pem)
    jws = %{"alg" => "RS256", "typ" => "JWT", "kid" => kid}
    {_, signed} = JOSE.JWT.sign(jwk, jws, payload) |> JOSE.JWS.compact()
    signed
  end

  def jwks(server \\ __MODULE__) do
    %{pem: pem, kid: kid} = Agent.get(server, & &1)
    jwk = JOSE.JWK.from_pem(pem)
    {_, public_map} = JOSE.JWK.to_public(jwk) |> JOSE.JWK.to_map()

    public_map
    |> Map.put("kid", kid)
    |> Map.put("use", "sig")
    |> Map.put("alg", "RS256")
    |> then(&%{keys: [&1]})
  end
end
