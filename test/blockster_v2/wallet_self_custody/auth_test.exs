defmodule BlocksterV2.WalletSelfCustody.AuthTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.WalletSelfCustody.Auth

  describe "web3auth_user?/1" do
    test "true for every web3auth_* auth_method" do
      for method <- ~w(web3auth_email web3auth_google web3auth_apple web3auth_x web3auth_twitter web3auth_telegram) do
        assert Auth.web3auth_user?(%{auth_method: method}),
               "expected #{method} to be recognized"
      end
    end

    test "true for unknown web3auth_* variants (forward-compatible)" do
      assert Auth.web3auth_user?(%{auth_method: "web3auth_farcaster"})
    end

    test "false for wallet users" do
      refute Auth.web3auth_user?(%{auth_method: "wallet"})
    end

    test "false for nil / missing auth_method" do
      refute Auth.web3auth_user?(nil)
      refute Auth.web3auth_user?(%{})
      refute Auth.web3auth_user?(%{auth_method: nil})
    end
  end

  describe "feature_enabled?/0" do
    test "honors the WALLET_SELF_CUSTODY_ENABLED env var" do
      System.put_env("WALLET_SELF_CUSTODY_ENABLED", "true")
      assert Auth.feature_enabled?()

      System.put_env("WALLET_SELF_CUSTODY_ENABLED", "false")
      refute Auth.feature_enabled?()
    after
      System.delete_env("WALLET_SELF_CUSTODY_ENABLED")
    end
  end
end
