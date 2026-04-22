defmodule BlocksterV2Web.AuthControllerEmailOtpTest do
  use BlocksterV2Web.ConnCase, async: false

  alias BlocksterV2.Auth.EmailOtpStore

  setup do
    # Clear the ETS table between tests. The GenServer runs app-wide.
    try do
      :ets.delete_all_objects(:web3auth_email_otps)
    catch
      :error, :badarg -> :ok
    end

    :ok
  end

  describe "POST /api/auth/web3auth/email_otp/send" do
    test "issues an OTP for a valid email", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/web3auth/email_otp/send", %{"email" => "adam@blockster.com"})
      assert %{"success" => true, "ttl" => ttl} = json_response(conn, 200)
      assert is_integer(ttl) and ttl > 0
    end

    test "rejects malformed email", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/web3auth/email_otp/send", %{"email" => "not-an-email"})
      assert json_response(conn, 400) == %{"success" => false, "error" => "Invalid email"}
    end

    test "rejects missing email param", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/web3auth/email_otp/send", %{})
      assert json_response(conn, 400) == %{"success" => false, "error" => "Missing email"}
    end

    test "returns 429 on second send within 60s", %{conn: conn} do
      post(conn, ~p"/api/auth/web3auth/email_otp/send", %{"email" => "rl@example.com"})

      conn2 = post(conn, ~p"/api/auth/web3auth/email_otp/send", %{"email" => "rl@example.com"})
      body = json_response(conn2, 429)
      assert body["success"] == false
      assert body["retry_after"] > 0
    end
  end

  describe "POST /api/auth/web3auth/email_otp/verify" do
    test "returns a JWT on valid code", %{conn: conn} do
      email = "verify@example.com"
      EmailOtpStore.send_otp(email)
      key = EmailOtpStore.normalize(email)
      [{^key, code, _, _, _, _}] = :ets.lookup(:web3auth_email_otps, key)

      conn = post(conn, ~p"/api/auth/web3auth/email_otp/verify", %{"email" => email, "code" => code})

      assert %{"success" => true, "id_token" => jwt, "email" => ^key} = json_response(conn, 200)
      assert is_binary(jwt)

      # JWT should verify against our own signing keys.
      claims = decode_jwt_claims(jwt)
      assert claims["sub"] == key
      assert claims["email"] == key
      assert claims["email_verified"] == true
      assert claims["iss"] == "blockster"
      assert claims["aud"] == "blockster-web3auth"
    end

    test "rejects an incorrect code", %{conn: conn} do
      email = "bad@example.com"
      EmailOtpStore.send_otp(email)

      conn = post(conn, ~p"/api/auth/web3auth/email_otp/verify", %{"email" => email, "code" => "000000"})
      assert %{"success" => false, "error" => "Invalid code"} = json_response(conn, 401)
    end

    test "rejects when no OTP has been issued", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/web3auth/email_otp/verify", %{"email" => "never@example.com", "code" => "123456"})
      assert json_response(conn, 401)["success"] == false
    end

    test "rejects missing params", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/web3auth/email_otp/verify", %{})
      assert json_response(conn, 400) == %{"success" => false, "error" => "Missing email or code"}
    end

    test "valid code is single-use", %{conn: conn} do
      email = "single@example.com"
      EmailOtpStore.send_otp(email)
      key = EmailOtpStore.normalize(email)
      [{^key, code, _, _, _, _}] = :ets.lookup(:web3auth_email_otps, key)

      # First verify succeeds
      conn1 = post(conn, ~p"/api/auth/web3auth/email_otp/verify", %{"email" => email, "code" => code})
      assert json_response(conn1, 200)["success"] == true

      # Second verify with the same code fails (OTP consumed)
      conn2 = post(conn, ~p"/api/auth/web3auth/email_otp/verify", %{"email" => email, "code" => code})
      assert json_response(conn2, 401)["success"] == false
    end
  end

  # Decode a JWT compact-serialized payload without verifying the signature.
  # We trust the issuer path here; this is just to read the claims.
  defp decode_jwt_claims(jwt) do
    [_header, payload_b64, _sig] = String.split(jwt, ".")
    payload_b64 = payload_b64 |> String.replace("-", "+") |> String.replace("_", "/")

    payload_b64 =
      case rem(byte_size(payload_b64), 4) do
        0 -> payload_b64
        n -> payload_b64 <> String.duplicate("=", 4 - n)
      end

    payload_b64
    |> Base.decode64!()
    |> Jason.decode!()
  end
end
