defmodule BlocksterV2.Orders do
  @moduledoc """
  The Orders context for managing orders, order items, and affiliate payouts.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.{Repo, Cart, Referrals}
  alias BlocksterV2.Orders.{Order, OrderItem, AffiliatePayout}
  alias BlocksterV2.Accounts.User
  require Logger

  @max_orders_per_hour 20

  def get_order(id) do
    Order
    |> Repo.get(id)
    |> Repo.preload([:order_items, :affiliate_payouts, :user, :referrer])
  end

  def get_order_by_number(num) do
    Order
    |> Repo.get_by(order_number: num)
    |> Repo.preload([:order_items, :user])
  end

  @doc "Finds the most recent pending/unpaid order for a user (created within the last hour)."
  def get_recent_pending_order(user_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -1, :hour)

    from(o in Order,
      where: o.user_id == ^user_id,
      where: o.status == "pending",
      where: o.inserted_at >= ^cutoff,
      order_by: [desc: o.inserted_at],
      limit: 1,
      preload: [:order_items, :affiliate_payouts, :user, :referrer]
    )
    |> Repo.one()
  end

  def list_orders_for_user(uid) do
    from(o in Order,
      where: o.user_id == ^uid,
      order_by: [desc: o.inserted_at],
      preload: [:order_items]
    )
    |> Repo.all()
  end

  def list_orders_admin(opts \\ %{}) do
    status_filter = Map.get(opts, :status)
    limit = Map.get(opts, :limit, 50)

    query =
      from(o in Order,
        order_by: [desc: o.inserted_at],
        limit: ^limit,
        preload: [:order_items, :affiliate_payouts, :user, :referrer]
      )

    query =
      if status_filter && status_filter != "" && status_filter != "all" do
        from(o in query, where: o.status == ^status_filter)
      else
        query
      end

    Repo.all(query)
  end

  @doc "Counts orders created by user in the last `minutes` minutes (default 60)."
  def recent_order_count(user_id, minutes \\ 60) do
    cutoff = DateTime.add(DateTime.utc_now(), -minutes, :minute)

    from(o in Order,
      where: o.user_id == ^user_id,
      where: o.inserted_at >= ^cutoff
    )
    |> Repo.aggregate(:count)
  end

  @doc "Checks if user can place a new order (max #{@max_orders_per_hour} per hour)."
  def check_rate_limit(user_id) do
    if recent_order_count(user_id) >= @max_orders_per_hour do
      {:error, :rate_limited}
    else
      :ok
    end
  end

  def create_order_from_cart(cart, %User{} = user) do
    cart = Cart.preload_items(cart)
    totals = Cart.calculate_totals(cart, user.id)

    Repo.transaction(fn ->
      {:ok, order} =
        %Order{}
        |> Order.create_changeset(%{
          order_number: generate_order_number(),
          user_id: user.id,
          referrer_id: user.referrer_id,
          subtotal: totals.subtotal,
          bux_discount_amount: totals.total_bux_discount,
          bux_tokens_burned: totals.total_bux_tokens,
          total_paid: totals.subtotal,
          rogue_usd_rate_locked: get_current_rogue_rate()
        })
        |> Repo.insert()

      Enum.each(cart.cart_items, fn item ->
        img = List.first(item.product.images)

        %OrderItem{}
        |> OrderItem.changeset(%{
          order_id: order.id,
          product_id: item.product.id,
          product_title: item.product.title,
          product_image: img && img.src,
          variant_id: item.variant && item.variant.id,
          variant_title: item.variant && item.variant.title,
          quantity: item.quantity,
          unit_price:
            if(item.variant,
              do: item.variant.price,
              else: List.first(item.product.variants).price
            ),
          subtotal: Cart.item_subtotal(item),
          bux_tokens_redeemed: item.bux_tokens_to_redeem,
          bux_discount_amount: Cart.item_bux_discount(item)
        })
        |> Repo.insert!()
      end)

      get_order(order.id)
    end)
  end

  def update_order(%Order{} = order, attrs) do
    result = order |> Order.status_changeset(attrs) |> Repo.update()

    case result do
      {:ok, updated_order} ->
        if Map.has_key?(attrs, :status) || Map.has_key?(attrs, "status") do
          notify_order_status_change(updated_order)
        end

        {:ok, updated_order}

      error ->
        error
    end
  end

  def complete_bux_payment(%Order{} = order, tx_hash) do
    order
    |> Order.bux_payment_changeset(%{bux_burn_tx_hash: tx_hash, status: "bux_paid"})
    |> Repo.update()
  end

  def complete_rogue_payment(%Order{} = order, tx_hash) do
    order
    |> Order.rogue_payment_changeset(%{rogue_payment_tx_hash: tx_hash, status: "rogue_paid"})
    |> Repo.update()
  end

  def update_order_shipping(%Order{} = order, attrs) do
    order |> Order.shipping_changeset(attrs) |> Repo.update()
  end

  def complete_helio_payment(%Order{} = order, %{helio_transaction_id: _} = attrs) do
    {:ok, order} =
      order
      |> Order.helio_payment_changeset(Map.put(attrs, :status, "paid"))
      |> Repo.update()

    process_paid_order(order)
    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "order:#{order.id}", {:order_updated, order})
    {:ok, order}
  end

  def process_paid_order(%Order{} = order) do
    order = get_order(order.id)

    # Clear the user's cart so they start fresh
    Cart.clear_cart(order.user_id)
    Cart.broadcast_cart_update(order.user_id)

    # Notify user of confirmed order
    notify_order_status_change(order)

    Task.start(fn ->
      BlocksterV2.Orders.Fulfillment.notify(order)
    end)

    if order.referrer_id, do: create_affiliate_payouts(order)

    # Track purchase completion for notification triggers
    BlocksterV2.UserEvents.track(order.user_id, "purchase_complete", %{
      target_type: "order",
      target_id: order.id,
      total: to_string(order.total_amount)
    })

    :ok
  end

  def create_affiliate_payouts(%Order{} = order) do
    rate = order.affiliate_commission_rate || Decimal.new("0.05")
    referrer = Repo.get(User, order.referrer_id)

    unless referrer do
      Logger.warning("[Orders] Referrer #{order.referrer_id} not found")
      throw(:skip)
    end

    # Get buyer's wallet for Mnesia referral_earnings recording
    buyer = order.user || Repo.get(User, order.user_id)
    buyer_wallet = buyer && buyer.smart_wallet_address

    if order.bux_tokens_burned > 0 do
      comm =
        Decimal.new(order.bux_tokens_burned)
        |> Decimal.mult(rate)
        |> Decimal.round(0)
        |> Decimal.to_integer()

      {:ok, p} = insert_payout(order, referrer, "BUX", order.bux_tokens_burned, rate, comm)

      if referrer.smart_wallet_address do
        BlocksterV2.BuxMinter.mint_bux(
          referrer.smart_wallet_address,
          comm,
          referrer.id,
          nil,
          :shop_affiliate
        )

        p |> Ecto.Changeset.change(%{status: "paid", paid_at: DateTime.utc_now() |> DateTime.truncate(:second)}) |> Repo.update()
      end

      record_affiliate_earning(referrer, buyer_wallet, comm, "BUX")
    end

    if Decimal.gt?(order.rogue_tokens_sent, 0) do
      rogue_comm = Decimal.mult(order.rogue_tokens_sent, rate)

      insert_payout(
        order,
        referrer,
        "ROGUE",
        order.rogue_tokens_sent,
        rate,
        rogue_comm
      )

      record_affiliate_earning(referrer, buyer_wallet, rogue_comm, "ROGUE")
    end

    if Decimal.gt?(order.helio_payment_amount, 0) do
      comm = Decimal.mult(order.helio_payment_amount, rate)
      is_card = order.helio_payment_currency == "CARD"
      currency = order.helio_payment_currency || "USDC"

      insert_payout(
        order,
        referrer,
        currency,
        order.helio_payment_amount,
        rate,
        comm,
        %{
          status: if(is_card, do: "held", else: "pending"),
          held_until: if(is_card, do: DateTime.add(DateTime.utc_now(), 30, :day) |> DateTime.truncate(:second)),
          commission_usd_value: comm
        }
      )

      record_affiliate_earning(referrer, buyer_wallet, comm, currency)
    end
  catch
    :skip -> :ok
  end

  def execute_affiliate_payout(%AffiliatePayout{} = p) do
    p = Repo.preload(p, [:referrer, :order])

    result =
      case p.currency do
        "BUX" ->
          BlocksterV2.BuxMinter.mint_bux(
            p.referrer.smart_wallet_address,
            Decimal.to_integer(Decimal.round(p.commission_amount, 0)),
            p.referrer.id,
            nil,
            :shop_affiliate
          )

        "ROGUE" ->
          treasury = Application.get_env(:blockster_v2, :shop_treasury_address)

          wei =
            p.commission_amount
            |> Decimal.mult(Decimal.new("1000000000000000000"))
            |> Decimal.round(0)
            |> Decimal.to_string()

          BlocksterV2.BuxMinter.transfer_rogue(treasury, p.referrer.smart_wallet_address, wei)

        c when c in ["USDC", "SOL", "ETH", "BTC", "CARD"] ->
          {:ok, :usdc_payout_queued}
      end

    case result do
      {:ok, %{"txHash" => h}} ->
        p
        |> Ecto.Changeset.change(%{status: "paid", paid_at: DateTime.utc_now() |> DateTime.truncate(:second), tx_hash: h})
        |> Repo.update()

      {:ok, _} ->
        p
        |> Ecto.Changeset.change(%{status: "paid", paid_at: DateTime.utc_now() |> DateTime.truncate(:second)})
        |> Repo.update()

      {:error, r} ->
        {:error, r}
    end
  end

  def generate_order_number do
    date = Date.utc_today() |> Calendar.strftime("%Y%m%d")

    suffix =
      System.unique_integer([:positive, :monotonic])
      |> rem(1_679_616)
      |> Integer.to_string(36)
      |> String.upcase()
      |> String.pad_leading(4, "0")

    "BLK-#{date}-#{suffix}"
  end

  defp record_affiliate_earning(referrer, buyer_wallet, amount, token) do
    if referrer.smart_wallet_address do
      Referrals.record_shop_purchase_earning(%{
        referrer_id: referrer.id,
        referrer_wallet: referrer.smart_wallet_address,
        referee_wallet: buyer_wallet,
        amount: amount,
        token: token
      })
    end
  end

  defp insert_payout(order, referrer, currency, basis, rate, comm, extra \\ %{}) do
    %AffiliatePayout{}
    |> AffiliatePayout.changeset(
      Map.merge(
        %{
          order_id: order.id,
          referrer_id: referrer.id,
          currency: currency,
          basis_amount: basis,
          commission_rate: rate,
          commission_amount: comm
        },
        extra
      )
    )
    |> Repo.insert()
  end

  defp get_current_rogue_rate do
    case :mnesia.dirty_read(:token_prices, "rogue") do
      [{:token_prices, "rogue", price, _}] when is_number(price) ->
        Decimal.from_float(price)

      _ ->
        Decimal.new(Application.get_env(:blockster_v2, :rogue_usd_price, "0.00006"))
    end
  rescue
    _ -> Decimal.new(Application.get_env(:blockster_v2, :rogue_usd_price, "0.00006"))
  catch
    :exit, _ -> Decimal.new(Application.get_env(:blockster_v2, :rogue_usd_price, "0.00006"))
  end

  @doc """
  Sends an in-app notification to the user when their order status changes.
  """
  def notify_order_status_change(%Order{} = order) do
    {title, body} = order_notification_copy(order.status)

    BlocksterV2.Notifications.create_notification(order.user_id, %{
      type: "order_#{order.status}",
      category: "system",
      title: title,
      body: body,
      action_url: "/shop",
      action_label: "View Order",
      metadata: %{"order_id" => order.id, "order_number" => order.order_number}
    })

    # Trigger SMS for shipped orders
    if order.status == "shipped" do
      BlocksterV2.Workers.SmsNotificationWorker.enqueue(
        order.user_id,
        :order_shipped,
        %{order_ref: order.order_number || "##{order.id}", url: "blockster-v2.fly.dev/shop"}
      )
    end
  end

  defp order_notification_copy("paid"), do: {"Order Confirmed", "Your order has been confirmed and is being processed."}
  defp order_notification_copy("shipped"), do: {"Order Shipped", "Your order is on its way!"}
  defp order_notification_copy("delivered"), do: {"Order Delivered", "Your order has been delivered."}
  defp order_notification_copy("cancelled"), do: {"Order Cancelled", "Your order has been cancelled."}
  defp order_notification_copy(status), do: {"Order Update", "Your order status has been updated to #{status}."}
end
