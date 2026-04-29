defmodule BlocksterV2.Auth.PendingTelegramJwtStore do
  @moduledoc """
  Mnesia-backed store for the Telegram redirect-mode Custom JWT.

  Why a separate store and not just `put_session(:pending_telegram_jwt, jwt)`:
  Phoenix's default CookieStore caps the encoded session at ~4KB. The Custom
  JWT we sign for Telegram (`AuthController.telegram_callback/2` →
  `BlocksterV2.Auth.Web3AuthSigning.sign_id_token/1`) is ~1.5KB. Add the
  user's existing session keys (wallet_address, user_token, OTP store hints,
  Phoenix CSRF, the LV session token) and a single-shot stash easily overflows.
  When the cookie overflows, the new key gets silently dropped by Plug.Session,
  and the next request reads `nil` for `:pending_telegram_jwt` — which the JS
  hook surfaces as "No pending Telegram login" while the user stares at a
  modal that won't dismiss. Confirmed reproducible on mobile post-2026-04-29
  redirect-mode rollout.

  Fix: stash the JWT in Mnesia keyed by a short random token, put only the
  token in the cookie. `:web3auth_pending_telegram_jwts` is `:set` typed,
  one entry per pending login, with a 2-minute TTL.

  Cluster: Mnesia replicates this table across both prod machines (mirroring
  `:web3auth_email_otps` — same operational reasoning called out in
  `Auth.EmailOtpStore`'s moduledoc: ETS-only would have caused random 401s
  in the 2-machine production cluster when callback and pending_jwt land on
  different machines).

  Mnesia record shape (table name is the first tuple element):
    {:web3auth_pending_telegram_jwts, token, jwt, expires_at_ms}
  """

  require Logger

  @table :web3auth_pending_telegram_jwts
  @ttl_ms :timer.minutes(2)
  @token_bytes 24

  @doc """
  Stash a JWT and return a short opaque token to put in the session cookie.
  Returns `{:ok, token}` or `{:error, reason}` if Mnesia is unavailable.
  """
  def stash(jwt) when is_binary(jwt) and jwt != "" do
    token = generate_token()
    now = System.system_time(:millisecond)
    record = {@table, token, jwt, now + @ttl_ms}
    :mnesia.dirty_write(record)
    {:ok, token}
  rescue
    e ->
      Logger.error("[PendingTelegramJwtStore] stash crashed: #{inspect(e)}")
      {:error, :store_unavailable}
  catch
    :exit, reason ->
      Logger.error("[PendingTelegramJwtStore] stash exited: #{inspect(reason)}")
      {:error, :store_unavailable}
  end

  @doc """
  One-shot read: returns `{:ok, jwt}` and deletes the entry, or
  `{:error, :not_found}` / `{:error, :expired}` / `{:error, :store_unavailable}`.
  """
  def take(token) when is_binary(token) and token != "" do
    now = System.system_time(:millisecond)

    case :mnesia.dirty_read({@table, token}) do
      [{@table, ^token, jwt, expires_at}] when expires_at > now ->
        :mnesia.dirty_delete({@table, token})
        {:ok, jwt}

      [{@table, ^token, _jwt, _expired_at}] ->
        :mnesia.dirty_delete({@table, token})
        {:error, :expired}

      [] ->
        {:error, :not_found}
    end
  rescue
    e ->
      Logger.error("[PendingTelegramJwtStore] take crashed: #{inspect(e)}")
      {:error, :store_unavailable}
  catch
    :exit, reason ->
      Logger.error("[PendingTelegramJwtStore] take exited: #{inspect(reason)}")
      {:error, :store_unavailable}
  end

  defp generate_token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
