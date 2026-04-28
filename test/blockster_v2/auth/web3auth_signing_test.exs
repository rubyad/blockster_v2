defmodule BlocksterV2.Auth.Web3AuthSigningTest do
  use ExUnit.Case, async: false

  alias BlocksterV2.Auth.Web3AuthSigning

  # Each test uses its OWN locally-named agent (test_<unique>) and tmp file
  # so we never touch the supervised `Web3AuthSigning` agent in
  # `application.ex`. Stopping/restarting the supervised one races with the
  # supervisor's automatic restart and cascaded into the rest of the suite —
  # the application supervisor would eventually exhaust its restart budget,
  # taking the Repo + PubSub down with it. Keep this test fully isolated.

  setup do
    tmp = Path.join(System.tmp_dir!(), "web3auth_test_#{:rand.uniform(1_000_000)}.json")
    name = :"web3auth_signing_test_#{System.unique_integer([:positive])}"

    prev = System.get_env("WEB3AUTH_JWT_SIGNING_KEY_PATH")
    System.put_env("WEB3AUTH_JWT_SIGNING_KEY_PATH", tmp)

    {:ok, pid} = Web3AuthSigning.start_link(name: name)

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          Agent.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end

      if prev do
        System.put_env("WEB3AUTH_JWT_SIGNING_KEY_PATH", prev)
      else
        System.delete_env("WEB3AUTH_JWT_SIGNING_KEY_PATH")
      end

      File.rm(tmp)
    end)

    %{tmp: tmp, name: name}
  end

  test "generates and persists a signing key, produces a verifiable JWT + JWKS", %{name: name} do
    claims = %{"sub" => "123456", "telegram_username" => "alice"}
    jwt = Web3AuthSigning.sign_id_token(claims, name)

    assert is_binary(jwt)
    assert String.split(jwt, ".") |> length() == 3

    %{"keys" => [jwk]} = Atomize.atomize(Web3AuthSigning.jwks(name))
    assert jwk["kty"] == "RSA"
    assert jwk["alg"] == "RS256"
    assert jwk["use"] == "sig"
    assert jwk["kid"] == Web3AuthSigning.kid(name)

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

  test "persists key across agent restarts (same kid)", %{name: name} do
    kid1 = Web3AuthSigning.kid(name)

    # Stop the locally-named agent and start a fresh one — the env var still
    # points at the same tmp path so the restart loads the same persisted key.
    pid = Process.whereis(name)
    Agent.stop(pid)
    {:ok, _new_pid} = Web3AuthSigning.start_link(name: name)

    kid2 = Web3AuthSigning.kid(name)
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
