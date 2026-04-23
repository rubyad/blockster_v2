defmodule BlocksterV2.Orders.BuxBurnWatcherTest do
  @moduledoc """
  Regression coverage for SHOP-14's stuck-`:bux_pending` watcher. Exercises
  `run_once/1` directly with a pinned `now` — no scheduler involvement so the
  test is synchronous and deterministic.

  Covers the selector (what counts as stuck) + the PubSub surface. Does NOT
  mutate order state (watcher is surface-only).
  """
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Orders.{BuxBurnWatcher, Order}
  alias BlocksterV2.Repo

  defp create_user do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560_013
      })

    %{user | username: "stuck_bux_#{unique}"}
  end

  defp insert_order(user, attrs) do
    defaults = %{
      order_number: "ORD-#{System.unique_integer([:positive])}",
      user_id: user.id,
      subtotal: Decimal.new("100.00"),
      bux_tokens_burned: 1_000,
      bux_discount_amount: Decimal.new("10.00"),
      total_paid: Decimal.new("90.00"),
      rogue_usd_rate_locked: Decimal.new("0.10")
    }

    {:ok, order} =
      %Order{}
      |> Order.create_changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    # Direct update for status + bux_burn fields without reinserting.
    order
    |> Ecto.Changeset.change(Map.drop(attrs, Map.keys(defaults)))
    |> Repo.update!()
  end

  describe "run_once/1" do
    test "selects orders in :bux_pending with burn_started_at past the 15-min cutoff" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      stuck_since = DateTime.add(now, -20, :minute)

      stuck =
        insert_order(user, %{
          status: "bux_pending",
          bux_burn_started_at: stuck_since,
          bux_burn_tx_hash: nil
        })

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, BuxBurnWatcher.topic())

      assert [hit] = BuxBurnWatcher.run_once(now)
      assert hit.id == stuck.id

      assert_receive {:stuck_bux_order, order_id}, 500
      assert order_id == stuck.id

      # Status is untouched — watcher only surfaces.
      assert Repo.get!(Order, stuck.id).status == "bux_pending"
    end

    test "does NOT flag orders inside the 15-min window" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      fresh = DateTime.add(now, -5, :minute)

      insert_order(user, %{
        status: "bux_pending",
        bux_burn_started_at: fresh,
        bux_burn_tx_hash: nil
      })

      assert BuxBurnWatcher.run_once(now) == []
    end

    test "does NOT flag orders where burn already landed (bux_burn_tx_hash set)" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      stuck_since = DateTime.add(now, -20, :minute)

      insert_order(user, %{
        status: "bux_pending",
        bux_burn_started_at: stuck_since,
        bux_burn_tx_hash: "5abcd" <> String.duplicate("x", 83)
      })

      assert BuxBurnWatcher.run_once(now) == []
    end

    test "does NOT flag non-bux_pending statuses even if timestamp is old" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      stuck_since = DateTime.add(now, -20, :minute)

      for status <- ["pending", "bux_paid", "paid", "expired", "cancelled"] do
        insert_order(user, %{
          status: status,
          bux_burn_started_at: stuck_since,
          bux_burn_tx_hash: nil
        })
      end

      assert BuxBurnWatcher.run_once(now) == []
    end

    test "does NOT flag orders with nil burn_started_at (never initiated)" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # :bux_pending is theoretically unreachable without a timestamp under
      # the new code path, but pin the guard so regressions surface.
      insert_order(user, %{
        status: "bux_pending",
        bux_burn_started_at: nil,
        bux_burn_tx_hash: nil
      })

      assert BuxBurnWatcher.run_once(now) == []
    end
  end
end
