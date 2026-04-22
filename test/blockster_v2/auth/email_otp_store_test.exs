defmodule BlocksterV2.Auth.EmailOtpStoreTest do
  use ExUnit.Case, async: false

  alias BlocksterV2.Auth.EmailOtpStore

  setup do
    # Clear the ETS table between tests. The GenServer runs app-wide so
    # we can't start a fresh one per test.
    try do
      :ets.delete_all_objects(:web3auth_email_otps)
    catch
      :error, :badarg -> :ok
    end

    :ok
  end

  describe "send_otp/1" do
    test "returns {:ok, ttl} on first send" do
      email = "test-#{System.unique_integer([:positive])}@example.com"
      assert {:ok, ttl} = EmailOtpStore.send_otp(email)
      assert is_integer(ttl) and ttl > 0
    end

    test "rate-limits a second send within 60s" do
      email = "ratelimit-#{System.unique_integer([:positive])}@example.com"
      assert {:ok, _} = EmailOtpStore.send_otp(email)
      assert {:error, {:rate_limited, seconds}} = EmailOtpStore.send_otp(email)
      assert seconds > 0 and seconds <= 60
    end

    test "normalizes email (trim + lowercase)" do
      upper = "  Alice@Example.COM  "
      lower = "alice@example.com"

      assert {:ok, _} = EmailOtpStore.send_otp(upper)
      # A second send for the canonicalized form should hit the rate limit.
      assert {:error, {:rate_limited, _}} = EmailOtpStore.send_otp(lower)
    end
  end

  describe "verify_otp/2" do
    test "rejects when no OTP has been sent" do
      email = "never-sent-#{System.unique_integer([:positive])}@example.com"
      assert {:error, :not_found} = EmailOtpStore.verify_otp(email, "123456")
    end

    test "accepts the correct code and consumes it" do
      email = "verify-#{System.unique_integer([:positive])}@example.com"
      EmailOtpStore.send_otp(email)

      key = EmailOtpStore.normalize(email)
      [{^key, code, _, _, _, _}] = :ets.lookup(:web3auth_email_otps, key)

      assert {:ok, ^key} = EmailOtpStore.verify_otp(email, code)
      # Single-use: second call returns not_found
      assert {:error, :not_found} = EmailOtpStore.verify_otp(email, code)
    end

    test "rejects a wrong code and increments the attempt counter" do
      email = "wrong-#{System.unique_integer([:positive])}@example.com"
      EmailOtpStore.send_otp(email)

      assert {:error, :invalid_code} = EmailOtpStore.verify_otp(email, "000000")

      key = EmailOtpStore.normalize(email)
      [{^key, _code, _, _, attempts, _lock}] = :ets.lookup(:web3auth_email_otps, key)
      assert attempts == 1
    end

    test "locks after 5 wrong attempts" do
      email = "lock-#{System.unique_integer([:positive])}@example.com"
      EmailOtpStore.send_otp(email)

      for _ <- 1..4 do
        assert {:error, :invalid_code} = EmailOtpStore.verify_otp(email, "000000")
      end

      # 5th wrong attempt flips the lock
      assert {:error, {:locked, seconds}} = EmailOtpStore.verify_otp(email, "000000")
      assert seconds > 0

      # Even the correct code is rejected while locked
      key = EmailOtpStore.normalize(email)
      [{^key, real_code, _, _, _, _}] = :ets.lookup(:web3auth_email_otps, key)
      assert {:error, {:locked, _}} = EmailOtpStore.verify_otp(email, real_code)
    end

    test "same code from different-case emails still works" do
      email = "caseinsensitive-#{System.unique_integer([:positive])}@example.com"
      EmailOtpStore.send_otp(String.upcase(email))

      key = EmailOtpStore.normalize(email)
      [{^key, code, _, _, _, _}] = :ets.lookup(:web3auth_email_otps, key)

      assert {:ok, _} = EmailOtpStore.verify_otp(email, code)
    end
  end

  describe "normalize/1" do
    test "trim + lowercase" do
      assert EmailOtpStore.normalize("  ADAM@Blockster.com  ") == "adam@blockster.com"
    end
  end
end
