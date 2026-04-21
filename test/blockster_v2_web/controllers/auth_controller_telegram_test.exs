defmodule BlocksterV2Web.AuthControllerTelegramTest do
  use BlocksterV2Web.ConnCase, async: false

  @bot_token "fake_bot_token_for_tests:abc123"

  setup do
    prev_token = System.get_env("BLOCKSTER_V2_BOT_TOKEN")
    System.put_env("BLOCKSTER_V2_BOT_TOKEN", @bot_token)

    on_exit(fn ->
      if prev_token do
        System.put_env("BLOCKSTER_V2_BOT_TOKEN", prev_token)
      else
        System.delete_env("BLOCKSTER_V2_BOT_TOKEN")
      end
    end)

    :ok
  end

  # Telegram widget signs with SHA256(bot_token) as the HMAC secret. The client
  # assembles a newline-joined sorted key=value string (excluding "hash") and
  # the server must reproduce it identically.
  defp telegram_payload(fields, bot_token) do
    data_check_string =
      fields
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.sort()
      |> Enum.join("\n")

    secret = :crypto.hash(:sha256, bot_token)
    hash = :crypto.mac(:hmac, :sha256, secret, data_check_string) |> Base.encode16(case: :lower)
    Map.put(Map.new(fields), "hash", hash)
  end

  describe "POST /api/auth/telegram/verify" do
    test "returns an id_token when the widget payload is valid", %{conn: conn} do
      payload =
        telegram_payload(
          [
            {"id", 123456789},
            {"first_name", "Alice"},
            {"username", "alice_tg"},
            {"auth_date", System.system_time(:second)}
          ],
          @bot_token
        )

      conn = post(conn, ~p"/api/auth/telegram/verify", payload)
      assert %{"success" => true, "id_token" => jwt} = json_response(conn, 200)
      assert is_binary(jwt)
      assert String.split(jwt, ".") |> length() == 3
    end

    test "rejects a tampered payload", %{conn: conn} do
      payload =
        telegram_payload(
          [
            {"id", 123456789},
            {"first_name", "Alice"},
            {"auth_date", System.system_time(:second)}
          ],
          @bot_token
        )

      tampered = Map.put(payload, "id", 999999)
      conn = post(conn, ~p"/api/auth/telegram/verify", tampered)
      assert %{"success" => false} = json_response(conn, 401)
    end

    test "rejects stale auth_date (older than 24 hours)", %{conn: conn} do
      stale = System.system_time(:second) - 90_000

      payload =
        telegram_payload(
          [{"id", 123}, {"first_name", "Alice"}, {"auth_date", stale}],
          @bot_token
        )

      conn = post(conn, ~p"/api/auth/telegram/verify", payload)
      assert %{"success" => false} = json_response(conn, 401)
    end
  end

  describe "GET /.well-known/jwks.json" do
    test "returns a public JWKS with our signing key", %{conn: conn} do
      conn = get(conn, ~p"/.well-known/jwks.json")
      assert %{"keys" => [jwk]} = json_response(conn, 200)
      assert jwk["kty"] == "RSA"
      assert jwk["alg"] == "RS256"
      assert jwk["use"] == "sig"
      refute Map.has_key?(jwk, "d")
    end
  end
end
