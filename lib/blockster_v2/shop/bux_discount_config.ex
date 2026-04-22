defmodule BlocksterV2.Shop.BuxDiscountConfig do
  @moduledoc """
  Feature-flag helpers for the SHOP-04 BUX discount cap enforcement.

  Historically the shop treated `bux_max_discount = 0` (the schema
  default) as "100% discount allowed" — an unbounded exploit where any
  un-migrated product let the user redeem BUX for the full list value.
  The 2026-04-22 audit logged this as SHOP-04.

  The fix flips the fallback direction: `0` / `nil` ⇒ BUX discount
  disabled (0%). To let local testers still exercise the legacy 100%
  behaviour without touching prod, the flip is gated on the
  `SHOP_BUX_CAP_ENFORCED` env var.

  Defaults:
    * prod / test — enforced (fallback = 0%, exploit blocked)
    * dev         — not enforced (fallback = 100%, legacy behaviour)

  Set `SHOP_BUX_CAP_ENFORCED=true` to opt into the hardened path in dev.
  Set `SHOP_BUX_CAP_ENFORCED=false` in prod only if you need to
  emergency-rollback to the legacy fallback (do not do this).
  """

  @doc """
  Returns true when the SHOP-04 cap-enforcement is active.

  Callers use this to pick between the hardened (`0 → 0%`) and legacy
  (`0 → 100%`) fallback for `bux_max_discount`.
  """
  def cap_enforced? do
    default =
      case Application.get_env(:blockster_v2, :env, :prod) do
        :dev -> "false"
        _ -> "true"
      end

    String.trim(System.get_env("SHOP_BUX_CAP_ENFORCED", default)) == "true"
  end
end
