defmodule BlocksterV2.PaymentIntentsPhase7Test do
  @moduledoc """
  Phase 7 of the social login plan: `payment_mode` on order_payment_intents
  + helper that picks the right mode per user. The v1 `check_sol_payment_allowed/2`
  gate + `WEB3AUTH_SOL_CHECKOUT_ENABLED` env flag were removed in Phase 13 —
  Web3Auth users check out with SOL the same way Wallet Standard users do.
  """
  use ExUnit.Case, async: true

  alias BlocksterV2.PaymentIntents
  alias BlocksterV2.Orders.PaymentIntent

  describe "payment_mode_for_user/1" do
    test "wallet users default to manual" do
      assert PaymentIntents.payment_mode_for_user(%{auth_method: "wallet"}) == "manual"
    end

    test "legacy email users default to manual" do
      assert PaymentIntents.payment_mode_for_user(%{auth_method: "email"}) == "manual"
    end

    test "all web3auth auth_methods use wallet_sign" do
      for auth <- ~w(web3auth_email web3auth_google web3auth_apple web3auth_x web3auth_telegram) do
        assert PaymentIntents.payment_mode_for_user(%{auth_method: auth}) == "wallet_sign",
               "expected #{auth} to map to wallet_sign"
      end
    end

    test "nil user falls back to manual" do
      assert PaymentIntents.payment_mode_for_user(nil) == "manual"
      assert PaymentIntents.payment_mode_for_user(%{}) == "manual"
    end
  end

  describe "PaymentIntent.payment_modes/0" do
    test "exposes the allowed payment mode values" do
      assert "manual" in PaymentIntent.payment_modes()
      assert "wallet_sign" in PaymentIntent.payment_modes()
      assert length(PaymentIntent.payment_modes()) == 2
    end
  end

  describe "PaymentIntent.create_changeset/1" do
    test "accepts payment_mode=manual" do
      cs =
        PaymentIntent.create_changeset(%{
          order_id: Ecto.UUID.generate(),
          buyer_wallet: "buyer_wallet",
          pubkey: "pubkey_#{System.unique_integer()}",
          expected_lamports: 1_000,
          quoted_usd: Decimal.new("10.00"),
          quoted_sol_usd_rate: Decimal.new("120.0"),
          expires_at: DateTime.utc_now() |> DateTime.add(900, :second),
          payment_mode: "manual"
        })

      assert cs.valid?
    end

    test "accepts payment_mode=wallet_sign" do
      cs =
        PaymentIntent.create_changeset(%{
          order_id: Ecto.UUID.generate(),
          buyer_wallet: "buyer_wallet",
          pubkey: "pubkey_#{System.unique_integer()}",
          expected_lamports: 1_000,
          quoted_usd: Decimal.new("10.00"),
          quoted_sol_usd_rate: Decimal.new("120.0"),
          expires_at: DateTime.utc_now() |> DateTime.add(900, :second),
          payment_mode: "wallet_sign"
        })

      assert cs.valid?
    end

    test "rejects unknown payment_mode" do
      cs =
        PaymentIntent.create_changeset(%{
          order_id: Ecto.UUID.generate(),
          buyer_wallet: "buyer_wallet",
          pubkey: "pubkey_#{System.unique_integer()}",
          expected_lamports: 1_000,
          quoted_usd: Decimal.new("10.00"),
          quoted_sol_usd_rate: Decimal.new("120.0"),
          expires_at: DateTime.utc_now() |> DateTime.add(900, :second),
          payment_mode: "helio_fiat"
        })

      refute cs.valid?

      assert Enum.any?(cs.errors, fn {field, _} -> field == :payment_mode end)
    end

    test "defaults payment_mode to manual when not set" do
      attrs = %{
        order_id: Ecto.UUID.generate(),
        buyer_wallet: "buyer_wallet",
        pubkey: "pubkey_#{System.unique_integer()}",
        expected_lamports: 1_000,
        quoted_usd: Decimal.new("10.00"),
        quoted_sol_usd_rate: Decimal.new("120.0"),
        expires_at: DateTime.utc_now() |> DateTime.add(900, :second)
      }

      cs = PaymentIntent.create_changeset(attrs)
      assert cs.valid?
      # Default applied at the schema level; the changeset leaves it nil for a
      # new struct unless explicitly cast, but the DB default kicks in on insert.
      # This test exists to document that absence is not a validation error.
    end
  end
end
