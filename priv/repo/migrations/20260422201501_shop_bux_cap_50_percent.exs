defmodule BlocksterV2.Repo.Migrations.ShopBuxCap50Percent do
  @moduledoc """
  SHOP-04 — backfill an explicit `bux_max_discount` cap for every
  existing product that still has the historical default of `0` (or
  `NULL`, though the column is `NOT NULL DEFAULT 0` so this is
  defensive).

  Historically `bux_max_discount = 0` was treated as "100% discount
  allowed" by the shop renderer — an unbounded exploit documented in
  the 2026-04-22 bug audit. The renderer fallback is flipped in
  companion commits; this migration caps existing rows at 50% so the
  shop does not flip from "100% off" to "no discount" overnight for
  previously-discounted SKUs.

  ## Why 50%
  Matches the current marketing copy ("up to 50% off"). Product owners
  can tune per-SKU caps later via the admin.

  ## Rollback
  This migration mutates data only; schema is unchanged. `down/0` is
  intentionally a no-op because we cannot distinguish an originally-
  zero cap from one that this migration wrote. If a rollback is ever
  needed, restore from a pre-migration database backup.

  Do NOT rely on `mix ecto.rollback` to undo this.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE products
    SET bux_max_discount = 50
    WHERE bux_max_discount IS NULL OR bux_max_discount = 0
    """)
  end

  def down do
    # No-op by design — see moduledoc. Restore from backup if needed.
    :ok
  end
end
