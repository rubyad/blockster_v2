defmodule BlocksterV2Web.MemberLive.AuthMethodLabelsTest do
  @moduledoc """
  Phase 8 — Settings "Connected accounts" auth method display helpers.
  Verifies the primary + secondary labels map correctly per auth_method.
  """
  use ExUnit.Case, async: true

  alias BlocksterV2Web.MemberLive.Show

  describe "auth_method_primary_label/1" do
    test "wallet" do
      assert Show.auth_method_primary_label("wallet") == "Solana wallet"
    end

    test "legacy email" do
      assert Show.auth_method_primary_label("email") == "Legacy email"
    end

    test "web3auth variants" do
      assert Show.auth_method_primary_label("web3auth_email") == "Email (Web3Auth)"
      assert Show.auth_method_primary_label("web3auth_x") == "X (Web3Auth)"
      assert Show.auth_method_primary_label("web3auth_telegram") == "Telegram (Web3Auth)"
    end

    test "unknown falls back to em dash" do
      assert Show.auth_method_primary_label("mystery") == "—"
      assert Show.auth_method_primary_label(nil) == "—"
    end
  end

  describe "auth_method_secondary_label/1" do
    test "wallet → Wallet Standard" do
      assert Show.auth_method_secondary_label("wallet") == "Wallet Standard"
    end

    test "web3auth variants → MPC embedded wallet" do
      assert Show.auth_method_secondary_label("web3auth_email") == "MPC embedded wallet"
      assert Show.auth_method_secondary_label("web3auth_x") == "MPC embedded wallet"
      assert Show.auth_method_secondary_label("web3auth_telegram") == "MPC embedded wallet"
    end

    test "unknown returns empty" do
      assert Show.auth_method_secondary_label("mystery") == ""
    end
  end
end
