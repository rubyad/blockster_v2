defmodule BlocksterV2.SignupBonus do
  @moduledoc """
  Grants every new user a one-time 1,000 BUX starter bonus on first auth.

  ## Idempotency

  The grant is gated on `users.signup_bonus_granted_at`. Once stamped, the
  user can never re-trigger — even if the auth controller's new-user branch
  fires twice (replay, race, retry).

  ## Triggers

  Called from each new-user branch in `BlocksterV2Web.AuthController`:

    * `/api/auth/wallet/verify`        (legacy EVM wallet)
    * `/api/auth/email/verify`         (legacy email + fingerprint)
    * `/api/auth/session`              (Solana SIWS / Wallet Standard)
    * `/api/auth/web3auth/session`     (Web3Auth SFA — email OTP & social)

  ## Mint pipeline

  Calls `BlocksterV2.BuxMinter.mint_bux/5` with `reward_type: :signup`. The
  settler service mints 1,000 SPL BUX to the user's wallet on Solana. We
  fire it through `AsyncTask.run/1` so session creation never waits on the
  RPC round-trip. The timestamp stamp commits FIRST and is not rolled back
  on mint failure — a missed mint is recoverable by a human ops retry, but
  a stamp rollback opens the door to double-mints if the failure response
  is a false negative (settler succeeded, network ate the response).
  Failed mints are logged loudly with `[SignupBonus]`.

  ## Sybil considerations

  Already protected by `Accounts.authenticate_email_with_fingerprint/1` —
  fingerprint conflict blocks new account creation outright. The bonus is
  per-user, so multi-wallet farming on the same device is blocked at signup.
  """

  alias BlocksterV2.{Accounts.User, AsyncTask, BuxMinter, Repo}
  alias Ecto.Changeset
  require Logger

  @amount 1_000

  @doc """
  Grants the starter bonus to a freshly-created user.

  Returns:
    * `:ok` — async mint dispatched
    * `:already_granted` — user already has `signup_bonus_granted_at` set
    * `{:error, reason}` — wallet missing or other guard failed

  Always non-blocking. The mint itself runs inside `AsyncTask.run/1`.
  """
  def grant_to_new_user(%User{signup_bonus_granted_at: %DateTime{}}), do: :already_granted

  def grant_to_new_user(%User{wallet_address: w}) when w in [nil, ""], do: {:error, :no_wallet}

  def grant_to_new_user(%User{is_bot: true}), do: {:error, :bot_user}

  def grant_to_new_user(%User{} = user) do
    # Stamp synchronously BEFORE dispatching the async mint. This wins the
    # race against a duplicate auth callback firing for the same user — only
    # one of them flips NULL → now and proceeds; the other sees the stamp
    # and short-circuits via the first clause.
    case stamp_granted(user) do
      {:ok, stamped_user} ->
        AsyncTask.run(fn -> mint(stamped_user) end)
        :ok

      {:error, _reason} = err ->
        err
    end
  end

  def grant_to_new_user(_), do: {:error, :invalid_user}

  defp stamp_granted(%User{} = user) do
    user
    |> Changeset.change(signup_bonus_granted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  defp mint(%User{id: id, wallet_address: wallet} = _user) do
    case BuxMinter.mint_bux(wallet, @amount, id, nil, :signup) do
      {:ok, response} ->
        Logger.info(
          "[SignupBonus] Granted #{@amount} BUX to user_id=#{id} wallet=#{wallet} sig=#{response["signature"]}"
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "[SignupBonus] Mint FAILED for user_id=#{id} wallet=#{wallet}: #{inspect(reason)} — stamp left in place; manually retry via SettlerClient if needed"
        )

        {:error, reason}
    end
  end
end
