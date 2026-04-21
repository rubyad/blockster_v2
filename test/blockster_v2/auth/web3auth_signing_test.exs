defmodule BlocksterV2.Auth.Web3AuthSigningTest do
  use ExUnit.Case, async: false

  alias BlocksterV2.Auth.Web3AuthSigning

  setup do
    # Use a tmp path so the test doesn't touch priv/
    tmp = Path.join(System.tmp_dir!(), "web3auth_test_#{:rand.uniform(1_000_000)}.json")
    prev = System.get_env("WEB3AUTH_JWT_SIGNING_KEY_PATH")
    System.put_env("WEB3AUTH_JWT_SIGNING_KEY_PATH", tmp)

    # The agent may already be started by the application supervisor; stop it
    # so our test env var takes effect for this run.
    case Process.whereis(Web3AuthSigning) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end

    {:ok, _pid} = Web3AuthSigning.start_link([])

    on_exit(fn ->
      case Process.whereis(Web3AuthSigning) do
        nil -> :ok
        pid -> Agent.stop(pid)
      end

      if prev do
        System.put_env("WEB3AUTH_JWT_SIGNING_KEY_PATH", prev)
      else
        System.delete_env("WEB3AUTH_JWT_SIGNING_KEY_PATH")
      end

      File.rm(tmp)
    end)

    %{tmp: tmp}
  end

  test "generates and persists a signing key, produces a verifiable JWT + JWKS" do
    claims = %{"sub" => "123456", "telegram_username" => "alice"}
    jwt = Web3AuthSigning.sign_id_token(claims)

    assert is_binary(jwt)
    assert String.split(jwt, ".") |> length() == 3

    %{"keys" => [jwk]} = Atomize.atomize(Web3AuthSigning.jwks())
    assert jwk["kty"] == "RSA"
    assert jwk["alg"] == "RS256"
    assert jwk["use"] == "sig"
    assert jwk["kid"] == Web3AuthSigning.kid()

    # Verify the JWT with the public JWK we just published.
    public_jwk = JOSE.JWK.from_map(Map.drop(jwk, ["kid", "alg", "use"]))
    {verified?, payload_jwt, _jws} = JOSE.JWT.verify(public_jwk, jwt)
    assert verified?
    payload = payload_jwt.fields
    assert payload["sub"] == "123456"
    assert payload["telegram_username"] == "alice"
    assert payload["iss"] == "blockster"
    assert payload["aud"] == "blockster-web3auth"
    assert payload["exp"] > payload["iat"]
  end

  test "persists key across agent restarts (same kid)" do
    kid1 = Web3AuthSigning.kid()
    Agent.stop(Web3AuthSigning)
    {:ok, _pid} = Web3AuthSigning.start_link([])
    kid2 = Web3AuthSigning.kid()
    assert kid1 == kid2
  end
end

defmodule Atomize do
  # Helper to normalize struct/map input for assertion readability.
  def atomize(m) when is_map(m) do
    m
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), atomize(v)}
      {k, v} -> {k, atomize(v)}
    end)
    |> Map.new()
  end

  def atomize(l) when is_list(l), do: Enum.map(l, &atomize/1)
  def atomize(v), do: v
end
