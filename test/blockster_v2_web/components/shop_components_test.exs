defmodule BlocksterV2Web.ShopComponentsTest do
  @moduledoc """
  Regression coverage for the shared currency-display component introduced
  with PR 3b. Locks in the rendered format so we don't drift back into the
  "cart says $, checkout says SOL" inconsistency SHOP-06/09/11 flagged.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  alias BlocksterV2Web.ShopComponents

  describe "sol_usd_dual/1 (SHOP-06)" do
    test "renders SOL primary + USD secondary in 'N SOL ≈ $X.XX' shape" do
      html =
        render_component(&ShopComponents.sol_usd_dual/1,
          usd: Decimal.new("220.00"),
          rate: 88.0,
          size: :total
        )

      assert html =~ "2.5000 SOL"
      assert html =~ "≈ $220.00"
      # SOL renders first in DOM order (primary).
      assert sol_before_usd?(html)
    end

    test "accepts float USD input (not just Decimal)" do
      html =
        render_component(&ShopComponents.sol_usd_dual/1,
          usd: 10.0,
          rate: 100.0,
          size: :line
        )

      assert html =~ "0.1000 SOL"
      assert html =~ "≈ $10.00"
    end

    test "accepts integer USD input" do
      html =
        render_component(&ShopComponents.sol_usd_dual/1,
          usd: 500,
          rate: 100.0,
          size: :line
        )

      assert html =~ "5.0000 SOL"
      assert html =~ "≈ $500.00"
    end

    test "format adapts to small amounts (sub-dollar)" do
      # 0.01 USD / 100 SOL-rate = 0.0001 SOL. `Pricing.format_sol` uses 4
      # decimals once we're below 0.01, so small prices don't truncate to 0.
      html =
        render_component(&ShopComponents.sol_usd_dual/1,
          usd: 0.01,
          rate: 100.0,
          size: :line
        )

      assert html =~ "0.0001 SOL"
      assert html =~ "≈ $0.01"
    end

    test "zero-rate (rate feed offline) renders FREE instead of crashing" do
      # Audit SHOP-06 edge case: "PriceTracker returns nil (service offline) →
      # fall back …". Zero-rate reaches the same code path; a value of 0.0 SOL
      # would truncate to "0.0000 SOL" which reads as a bug. Render FREE.
      html =
        render_component(&ShopComponents.sol_usd_dual/1,
          usd: Decimal.new("50"),
          rate: 0.0
        )

      assert html =~ "FREE"
      refute html =~ "SOL"
    end

    test "nil usd renders FREE (defensive — schema should never emit nil)" do
      html =
        render_component(&ShopComponents.sol_usd_dual/1,
          usd: nil,
          rate: 100.0
        )

      assert html =~ "FREE"
      refute html =~ "SOL"
    end

    test "zero USD on a live rate renders FREE (promo / 100% BUX-discounted item)" do
      # Audit SHOP-06: "Zero-SOL free item → render 'FREE' not '0.0 SOL'".
      # This is the path that also back-stops SHOP-04 / SHOP-08 footguns — a
      # product computed to 0 USD never displays as "0.0000 SOL".
      html =
        render_component(&ShopComponents.sol_usd_dual/1,
          usd: Decimal.new("0"),
          rate: 100.0
        )

      assert html =~ "FREE"
      refute html =~ "SOL"
    end

    test "size :tiny renders smaller typography classes" do
      html =
        render_component(&ShopComponents.sol_usd_dual/1,
          usd: Decimal.new("10"),
          rate: 100.0,
          size: :tiny
        )

      assert html =~ "text-[12px]"
      refute html =~ "text-[22px]"
    end

    test "align left uses items-start" do
      html =
        render_component(&ShopComponents.sol_usd_dual/1,
          usd: Decimal.new("10"),
          rate: 100.0,
          align: "left"
        )

      assert html =~ "items-start"
      refute html =~ "items-end"
    end
  end

  # Verify the SOL line precedes the USD line in the rendered markup — catches
  # accidental primary/secondary swap in future edits.
  defp sol_before_usd?(html) do
    sol_idx = :binary.match(html, "SOL") |> elem(0)
    usd_idx = :binary.match(html, "$") |> elem(0)
    sol_idx < usd_idx
  end
end
