defmodule BlocksterV2.Auth.EmailOtpStore do
  @moduledoc """
  Mnesia-backed OTP store for the Web3Auth email sign-in flow.

  Replaces Web3Auth's default `EMAIL_PASSWORDLESS` connector (which opens a
  popup window with its own captcha + email + code UI that hides behind the
  main browser tab — confusing UX for users). Instead we issue our own OTP,
  render the code entry INSIDE the sign-in modal, and hand Web3Auth a signed
  JWT via the CUSTOM JWT connector once verified. Same MPC wallet derivation,
  zero popup ceremony.

  Rate limits:
    * One OTP per email per 60s (resend cooldown)
    * Code expires 10 minutes after issue
    * 5 incorrect attempts per email → lock for 10 min (replay guard)

  State is replicated across the Erlang cluster via Mnesia (ram_copies +
  disc_copies on each node). Required so /send and /verify can land on
  different machines without losing the OTP — a single-node ETS implementation
  caused random 401s in the 2-machine production cluster (validation gate
  caught this before launch). The table is created by `MnesiaInitializer`
  on app boot.

  All Mnesia ops are dirty (per CLAUDE.md) — single-row reads/writes keyed
  on email don't need transactions; concurrent verify attempts on the same
  email accept the inherent race (worst case = an extra attempt counted).
  """

  use GenServer
  require Logger

  alias BlocksterV2.Mailer

  @table :web3auth_email_otps
  @code_length 6
  @ttl_ms :timer.minutes(10)
  @resend_cooldown_ms :timer.seconds(60)
  @max_attempts 5
  @cleanup_interval_ms :timer.minutes(1)

  # Mnesia record shape (table name is the first tuple element):
  #   {:web3auth_email_otps, email_key, code, created_at_ms, expires_at_ms,
  #    attempt_count, locked_until_ms}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc """
  Send an OTP to `email`. Returns `{:ok, expires_in_seconds}` or
  `{:error, {:rate_limited, seconds_remaining}}`. Email delivery is async
  so the caller gets the sooner "we'll send it" acknowledgement.
  """
  def send_otp(email) when is_binary(email) do
    key = normalize(email)
    now = System.system_time(:millisecond)

    case :mnesia.dirty_read({@table, key}) do
      [{@table, ^key, _code, created_at, _exp, _attempts, _lock}]
      when now - created_at < @resend_cooldown_ms ->
        {:error, {:rate_limited, div(@resend_cooldown_ms - (now - created_at), 1000)}}

      _ ->
        code = generate_code()
        expires_at = now + @ttl_ms
        :mnesia.dirty_write({@table, key, code, now, expires_at, 0, 0})
        Task.start(fn -> deliver_email(email, code) end)
        {:ok, div(@ttl_ms, 1000)}
    end
  end

  @doc """
  Verify `code` against the stored OTP for `email`. On success, returns
  `{:ok, normalized_email}` and consumes the OTP. On failure, increments
  the attempt counter and returns one of:
    * `{:error, :not_found}` — no OTP was issued or it already expired
    * `{:error, :invalid_code}` — wrong code, ttl still valid
    * `{:error, :expired}`
    * `{:error, {:locked, seconds_remaining}}` — too many wrong attempts

  Valid codes are single-use — a second `verify_otp` call with the same
  (email, code) returns `:not_found`.
  """
  def verify_otp(email, code) when is_binary(email) and is_binary(code) do
    key = normalize(email)
    code = String.trim(code)
    now = System.system_time(:millisecond)

    case :mnesia.dirty_read({@table, key}) do
      [] ->
        {:error, :not_found}

      [{@table, ^key, _code, _created, _exp, _attempts, locked_until}]
      when locked_until > now ->
        {:error, {:locked, div(locked_until - now, 1000)}}

      [{@table, ^key, _stored_code, _created, expires_at, _attempts, _lock}]
      when expires_at < now ->
        :mnesia.dirty_delete({@table, key})
        {:error, :expired}

      [{@table, ^key, stored_code, created, expires_at, attempts, lock}] ->
        if Plug.Crypto.secure_compare(stored_code, code) do
          :mnesia.dirty_delete({@table, key})
          {:ok, key}
        else
          new_attempts = attempts + 1

          if new_attempts >= @max_attempts do
            new_lock = now + @ttl_ms

            :mnesia.dirty_write(
              {@table, key, stored_code, created, expires_at, new_attempts, new_lock}
            )

            {:error, {:locked, div(@ttl_ms, 1000)}}
          else
            :mnesia.dirty_write(
              {@table, key, stored_code, created, expires_at, new_attempts, lock}
            )

            {:error, :invalid_code}
          end
        end
    end
  end

  @doc "Normalize an email for use as a Mnesia key. Trim + lowercase."
  def normalize(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end

  # ── GenServer ───────────────────────────────────────────────

  @impl true
  def init(_) do
    # Mnesia table is created by `BlocksterV2.MnesiaInitializer` (app boot
    # order: EmailOtpStore starts first as a base child, MnesiaInitializer
    # follows in genserver_children). The cleanup tick is scheduled here;
    # the first tick fires after @cleanup_interval_ms (1 min), well after
    # MnesiaInitializer has registered the table.
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.system_time(:millisecond)

    expired_keys =
      try do
        :mnesia.dirty_match_object({@table, :_, :_, :_, :_, :_, :_})
        |> Enum.filter(fn {@table, _key, _code, _created, expires_at, _attempts, locked_until} ->
          expires_at < now and locked_until < now
        end)
        |> Enum.map(fn {@table, key, _, _, _, _, _} -> key end)
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end

    Enum.each(expired_keys, fn key ->
      _ = :mnesia.dirty_delete({@table, key})
    end)

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_interval_ms)

  # ── Helpers ─────────────────────────────────────────────────

  defp generate_code do
    :rand.uniform(999_999)
    |> Integer.to_string()
    |> String.pad_leading(@code_length, "0")
  end

  defp deliver_email(to_email, code) do
    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(to_email)
      |> Swoosh.Email.from({"Blockster", "noreply@blockster.com"})
      |> Swoosh.Email.subject("Your Blockster sign-in code: #{code}")
      |> Swoosh.Email.html_body(html_body(code))
      |> Swoosh.Email.text_body(text_body(code))

    case Mailer.deliver(email) do
      {:ok, _} -> Logger.info("[EmailOtpStore] sent code to #{to_email}")
      {:error, reason} -> Logger.error("[EmailOtpStore] send failed for #{to_email}: #{inspect(reason)}")
    end
  end

  defp html_body(code) do
    """
    <!doctype html><html><body style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;background:#F5F6FB;padding:24px;">
    <div style="max-width:480px;margin:0 auto;background:#fff;border-radius:16px;border:1px solid #e5e7eb;padding:28px;">
      <div style="font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;color:#6b7280;margin-bottom:8px;">Blockster sign-in</div>
      <h2 style="margin:0 0 8px;font-size:22px;letter-spacing:-0.02em;color:#141414;">Your verification code</h2>
      <p style="margin:0 0 20px;font-size:13px;color:#6b7280;">Enter this 6-digit code in the Blockster sign-in window. It expires in 10 minutes.</p>
      <div style="font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:36px;font-weight:700;color:#141414;letter-spacing:0.22em;padding:16px 20px;background:#fafaf9;border:1px solid #e5e7eb;border-radius:12px;text-align:center;">#{code}</div>
      <p style="margin:20px 0 0;font-size:11px;color:#9ca3af;">If you didn't try to sign in, you can ignore this message.</p>
    </div>
    </body></html>
    """
  end

  defp text_body(code) do
    """
    Your Blockster sign-in code: #{code}

    Enter this 6-digit code in the Blockster sign-in window. It expires in 10 minutes.
    If you didn't try to sign in, you can ignore this message.
    """
  end
end
