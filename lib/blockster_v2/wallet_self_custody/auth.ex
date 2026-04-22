defmodule BlocksterV2.WalletSelfCustody.Auth do
  @moduledoc """
  Authorization helpers for the /wallet self-custody panel.

  The panel is only shown to Web3Auth social-login users (they have no
  other way to withdraw SOL or take custody of their keys). External-
  wallet users (Phantom, Solflare, Backpack) already have self-custody
  through their wallet extension and are redirected away.
  """

  @web3auth_methods ~w(
    web3auth_email
    web3auth_google
    web3auth_apple
    web3auth_x
    web3auth_twitter
    web3auth_telegram
  )

  @doc """
  Returns true when the user's auth_method starts with "web3auth_" —
  i.e. they signed in via Web3Auth and have an MPC-derived wallet they
  might want to export.
  """
  def web3auth_user?(nil), do: false
  def web3auth_user?(%{auth_method: method}) when method in @web3auth_methods, do: true
  def web3auth_user?(%{auth_method: "web3auth_" <> _}), do: true
  def web3auth_user?(_), do: false

  @doc """
  Feature-flag check. Controlled by WALLET_SELF_CUSTODY_ENABLED env var.
  Default: true in dev, off in prod until the real launch.
  """
  def feature_enabled? do
    default =
      case Application.get_env(:blockster_v2, :env, :prod) do
        :prod -> "false"
        _ -> "true"
      end

    String.trim(System.get_env("WALLET_SELF_CUSTODY_ENABLED", default)) == "true"
  end
end
