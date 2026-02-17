defmodule BlocksterV2Web.CheckoutLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Orders
  alias BlocksterV2.Orders.Order
  alias BlocksterV2.Shop.BalanceManager

  require Logger

  @rogue_discount_rate Decimal.new("0.10")
  @rate_lock_ttl_seconds 600

  @impl true
  def mount(%{"order_id" => order_id}, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Please log in to continue checkout")
         |> redirect(to: ~p"/login?redirect=/checkout/#{order_id}")}

      user ->
        case Orders.get_order(order_id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Order not found")
             |> redirect(to: ~p"/cart")}

          %Order{user_id: uid} when uid != user.id ->
            {:ok,
             socket
             |> put_flash(:error, "Order not found")
             |> redirect(to: ~p"/cart")}

          %Order{status: "paid"} = order ->
            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :confirmation)
             |> assign(:page_title, "Order Confirmed")
             |> assign_payment_defaults()}

          %Order{status: s} when s not in ["pending", "bux_pending", "bux_paid", "rogue_pending", "rogue_paid", "helio_pending"] ->
            {:ok,
             socket
             |> put_flash(:error, "This order cannot be modified")
             |> redirect(to: ~p"/cart")}

          %Order{status: "helio_pending"} = order ->
            # Helio payment in progress — subscribe for webhook completion
            if connected?(socket), do: Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "order:#{order.id}")

            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :payment)
             |> assign(:page_title, "Checkout")
             |> assign_shipping_form(order)
             |> assign_rogue_defaults()
             |> assign_payment_defaults()
             |> assign(:bux_payment_status, if(order.bux_tokens_burned > 0, do: :completed, else: :pending))
             |> assign(:rogue_payment_status, if(Decimal.gt?(order.rogue_payment_amount || Decimal.new("0"), 0), do: :completed, else: :pending))
             |> assign(:helio_payment_status, :processing)}

          %Order{status: "rogue_paid"} = order ->
            # BUX + ROGUE already paid, resume at payment step
            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :payment)
             |> assign(:page_title, "Checkout")
             |> assign_shipping_form(order)
             |> assign_rogue_defaults()
             |> assign_payment_defaults()
             |> assign(:bux_payment_status, if(order.bux_tokens_burned > 0, do: :completed, else: :pending))
             |> assign(:rogue_payment_status, :completed)}

          %Order{status: "rogue_pending"} = order ->
            # ROGUE payment in progress, resume at payment step
            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :payment)
             |> assign(:page_title, "Checkout")
             |> assign_shipping_form(order)
             |> assign_rogue_defaults()
             |> assign_payment_defaults()
             |> assign(:bux_payment_status, if(order.bux_tokens_burned > 0, do: :completed, else: :pending))
             |> assign(:rogue_payment_status, :processing)}

          %Order{status: "bux_paid"} = order ->
            # BUX already paid, resume at payment step
            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :payment)
             |> assign(:page_title, "Checkout")
             |> assign_shipping_form(order)
             |> assign_rogue_defaults()
             |> assign_payment_defaults()
             |> assign(:bux_payment_status, :completed)}

          order ->
            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :shipping)
             |> assign(:page_title, "Checkout")
             |> assign_shipping_form(order)
             |> assign_rogue_defaults()
             |> assign_payment_defaults()}
        end
    end
  end

  @impl true
  def handle_event("validate_shipping", %{"shipping" => params}, socket) do
    changeset =
      socket.assigns.order
      |> Order.shipping_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :shipping_changeset, changeset)}
  end

  def handle_event("save_shipping", %{"shipping" => params}, socket) do
    case Orders.update_order_shipping(socket.assigns.order, params) do
      {:ok, order} ->
        order = Orders.get_order(order.id)

        {:noreply,
         socket
         |> assign_order(order)
         |> assign(:step, :review)
         |> lock_rogue_rate()}

      {:error, changeset} ->
        {:noreply, assign(socket, :shipping_changeset, changeset)}
    end
  end

  def handle_event("set_rogue_amount", %{"amount" => amount_str}, socket) do
    rogue_usd = parse_decimal(amount_str)
    {:noreply, recalculate_rogue(socket, rogue_usd)}
  end

  def handle_event("proceed_to_payment", _params, socket) do
    order = socket.assigns.order
    rogue_usd = socket.assigns.rogue_usd_amount
    rogue_discount_saved = socket.assigns.rogue_discount_saved
    rogue_tokens = socket.assigns.rogue_tokens
    helio = socket.assigns.helio_amount

    {:ok, order} =
      order
      |> Order.rogue_payment_changeset(%{
        rogue_payment_amount: rogue_usd,
        rogue_discount_amount: rogue_discount_saved,
        rogue_tokens_sent: rogue_tokens
      })
      |> BlocksterV2.Repo.update()

    if Decimal.gt?(helio, 0) do
      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{helio_payment_amount: helio})
        |> BlocksterV2.Repo.update()

      order = Orders.get_order(order.id)

      {:noreply,
       socket
       |> assign_order(order)
       |> assign(:step, :payment)
       |> assign_payment_defaults()}
    else
      order = Orders.get_order(order.id)

      {:noreply,
       socket
       |> assign_order(order)
       |> assign(:step, :payment)
       |> assign_payment_defaults()}
    end
  end

  def handle_event("go_to_step", %{"step" => step}, socket) do
    allowed_back =
      case socket.assigns.step do
        :review -> [:shipping]
        :payment -> [:review, :shipping]
        _ -> []
      end

    step_atom = String.to_existing_atom(step)

    if step_atom in allowed_back do
      socket =
        case step_atom do
          :shipping -> assign_shipping_form(socket, socket.assigns.order)
          _ -> socket
        end

      {:noreply, assign(socket, :step, step_atom)}
    else
      {:noreply, socket}
    end
  end

  # ── BUX Payment ─────────────────────────────────────────────────────────────

  def handle_event("initiate_bux_payment", _params, socket) do
    order = socket.assigns.order
    user = socket.assigns.current_user
    bux_amount = order.bux_tokens_burned

    if bux_amount <= 0 do
      # No BUX to burn, skip to next step
      {:noreply, advance_after_bux(socket)}
    else
      # Attempt optimistic BUX deduction via BalanceManager
      case BalanceManager.deduct_bux(user.id, bux_amount) do
        {:ok, _new_balance} ->
          # Update order status to bux_pending
          {:ok, order} = Orders.update_order(order, %{status: "bux_pending"})
          order = Orders.get_order(order.id)

          socket =
            socket
            |> assign_order(order)
            |> assign(:bux_payment_status, :processing)

          # Attempt on-chain burn via BuxMinter
          wallet = user.smart_wallet_address
          start_async(socket, :burn_bux, fn ->
            BlocksterV2.BuxMinter.burn_bux(wallet, bux_amount, user.id)
          end)

        {:error, :insufficient, current_balance} ->
          {:noreply,
           socket
           |> assign(:bux_payment_status, :failed)
           |> put_flash(
             :error,
             "Insufficient BUX balance. You have #{trunc(current_balance)} BUX but need #{bux_amount} BUX. Go back to cart to adjust."
           )}
      end
    end
  end

  def handle_event("bux_payment_complete", %{"tx_hash" => hash}, socket) do
    # Callback from JS hook with on-chain tx hash
    order = socket.assigns.order

    {:ok, order} = Orders.complete_bux_payment(order, hash)
    order = Orders.get_order(order.id)

    # Sync on-chain balance
    user = socket.assigns.current_user
    if user.smart_wallet_address do
      BlocksterV2.BuxMinter.sync_user_balances_async(user.id, user.smart_wallet_address, force: true)
    end

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:bux_payment_status, :completed)
     |> put_flash(:info, "BUX payment confirmed!")}
  end

  def handle_event("bux_payment_error", %{"error" => err}, socket) do
    # JS hook reported an error — credit back BUX
    order = socket.assigns.order
    user = socket.assigns.current_user

    if order.bux_tokens_burned > 0 do
      BalanceManager.credit_bux(user.id, order.bux_tokens_burned)
    end

    # Revert order status
    {:ok, order} = Orders.update_order(order, %{status: "pending"})
    order = Orders.get_order(order.id)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:bux_payment_status, :failed)
     |> put_flash(:error, "BUX payment failed: #{err}")}
  end

  def handle_event("advance_after_bux", _params, socket) do
    {:noreply, advance_after_bux(socket)}
  end

  # ── ROGUE Payment ──────────────────────────────────────────────────────────

  def handle_event("initiate_rogue_payment", _params, socket) do
    order = socket.assigns.order
    rogue_tokens = order.rogue_tokens_sent

    if is_nil(rogue_tokens) or Decimal.compare(rogue_tokens, 0) in [:eq, :lt] do
      {:noreply, advance_after_rogue(socket)}
    else
      # Update order status to rogue_pending
      {:ok, order} = Orders.update_order(order, %{status: "rogue_pending"})
      order = Orders.get_order(order.id)

      # Convert ROGUE tokens to wei (18 decimals) for the JS hook
      amount_wei =
        rogue_tokens
        |> Decimal.mult(Decimal.new("1000000000000000000"))
        |> Decimal.round(0)
        |> Decimal.to_string()

      socket =
        socket
        |> assign_order(order)
        |> assign(:rogue_payment_status, :processing)
        |> push_event("initiate_rogue_payment", %{
          amount_wei: amount_wei,
          order_id: order.id
        })

      {:noreply, socket}
    end
  end

  def handle_event("rogue_payment_complete", %{"tx_hash" => hash}, socket) do
    order = socket.assigns.order

    {:ok, order} = Orders.complete_rogue_payment(order, hash)
    order = Orders.get_order(order.id)

    # Sync on-chain balance
    user = socket.assigns.current_user
    if user.smart_wallet_address do
      BlocksterV2.BuxMinter.sync_user_balances_async(user.id, user.smart_wallet_address, force: true)
    end

    socket =
      socket
      |> assign_order(order)
      |> assign(:rogue_payment_status, :completed)
      |> put_flash(:info, "ROGUE payment confirmed!")

    # Check if BUX + ROGUE covers full price — auto-advance
    {:noreply, maybe_complete_after_rogue(socket)}
  end

  def handle_event("rogue_payment_error", %{"error" => err}, socket) do
    order = socket.assigns.order

    # Revert order status to bux_paid (or pending if no BUX)
    revert_status = if order.bux_tokens_burned > 0, do: "bux_paid", else: "pending"
    {:ok, order} = Orders.update_order(order, %{status: revert_status})
    order = Orders.get_order(order.id)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:rogue_payment_status, :failed)
     |> put_flash(:error, "ROGUE payment failed: #{err}")}
  end

  def handle_event("advance_after_rogue", _params, socket) do
    {:noreply, advance_after_rogue(socket)}
  end

  # ── Helio Payment ────────────────────────────────────────────────────────

  def handle_event("initiate_helio_payment", _params, socket) do
    order = socket.assigns.order

    # Subscribe for webhook-driven completion
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "order:#{order.id}")

    socket =
      socket
      |> assign(:helio_payment_status, :processing)

    # Create Helio charge via start_async
    start_async(socket, :create_helio_charge, fn ->
      BlocksterV2.Helio.create_charge(order)
    end)
  end

  def handle_event("helio_payment_success", %{"transaction_id" => txid}, socket) do
    # Client-side widget reports success — update status to helio_pending
    # The webhook will finalize the order as "paid"
    order = socket.assigns.order

    {:ok, order} =
      order
      |> Order.helio_payment_changeset(%{helio_transaction_id: txid, status: "helio_pending"})
      |> BlocksterV2.Repo.update()

    order = Orders.get_order(order.id)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:helio_payment_status, :confirming)
     |> put_flash(:info, "Payment submitted! Waiting for confirmation...")}
  end

  def handle_event("helio_payment_error", %{"error" => err}, socket) do
    {:noreply,
     socket
     |> assign(:helio_payment_status, :failed)
     |> put_flash(:error, "Payment failed: #{err}. You can retry.")}
  end

  def handle_event("helio_payment_cancelled", _params, socket) do
    {:noreply,
     socket
     |> assign(:helio_payment_status, :pending)
     |> put_flash(:info, "Payment cancelled. You can try again.")}
  end

  def handle_event("complete_order", _params, socket) do
    order = socket.assigns.order
    remaining = remaining_after_bux(order)

    cond do
      # Fully covered by BUX — skip all other payments
      Decimal.compare(remaining, 0) in [:eq, :lt] and order.bux_tokens_burned > 0 ->
        # BUX payment flow handles this
        {:noreply,
         socket
         |> put_flash(:info, "Click 'Burn BUX' to complete your payment.")
         |> assign(:bux_payment_status, :pending)}

      # No remaining amount (e.g. free item with full BUX coverage already completed)
      Decimal.compare(remaining, 0) in [:eq, :lt] ->
        {:ok, order} = Orders.update_order(order, %{status: "paid"})
        order = Orders.get_order(order.id)

        {:noreply,
         socket
         |> assign_order(order)
         |> assign(:step, :confirmation)}

      true ->
        # Remaining balance needs ROGUE/Helio — proceed to confirmation with info
        {:noreply,
         socket
         |> assign(:step, :confirmation)
         |> put_flash(:info, "Order placed! ROGUE/Helio payment processing will be available soon.")}
    end
  end

  # ── Async Handlers ──────────────────────────────────────────────────────────

  @impl true
  def handle_async(:burn_bux, {:ok, {:ok, response}}, socket) do
    # On-chain burn succeeded
    order = socket.assigns.order
    tx_hash = response["transactionHash"] || "burn-#{System.unique_integer([:positive])}"

    {:ok, order} = Orders.complete_bux_payment(order, tx_hash)
    order = Orders.get_order(order.id)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:bux_payment_status, :completed)
     |> put_flash(:info, "BUX payment confirmed!")}
  end

  def handle_async(:burn_bux, {:ok, {:error, reason}}, socket) do
    # On-chain burn failed, but Mnesia deduction succeeded.
    # Still mark as bux_paid — the Mnesia deduction is authoritative for the app.
    # Log the error for manual review.
    order = socket.assigns.order
    Logger.warning("[Checkout] On-chain BUX burn failed: #{inspect(reason)}, proceeding with Mnesia deduction for order #{order.id}")

    ref = "local-#{System.unique_integer([:positive])}"
    {:ok, order} = Orders.complete_bux_payment(order, ref)
    order = Orders.get_order(order.id)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:bux_payment_status, :completed)
     |> put_flash(:info, "BUX payment confirmed!")}
  end

  def handle_async(:burn_bux, {:exit, reason}, socket) do
    # Async task crashed — same approach, log and proceed
    order = socket.assigns.order
    Logger.error("[Checkout] BUX burn task crashed: #{inspect(reason)}, proceeding for order #{order.id}")

    ref = "local-#{System.unique_integer([:positive])}"
    {:ok, order} = Orders.complete_bux_payment(order, ref)
    order = Orders.get_order(order.id)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:bux_payment_status, :completed)
     |> put_flash(:info, "BUX payment confirmed!")}
  end

  def handle_async(:create_helio_charge, {:ok, {:ok, %{charge_id: cid, page_url: _url}}}, socket) do
    order = socket.assigns.order

    # Store charge_id on the order
    {:ok, order} =
      order
      |> Order.helio_payment_changeset(%{helio_charge_id: cid})
      |> BlocksterV2.Repo.update()

    order = Orders.get_order(order.id)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:helio_payment_status, :widget_ready)
     |> push_event("helio_charge_created", %{charge_id: cid})}
  end

  def handle_async(:create_helio_charge, {:ok, {:error, reason}}, socket) do
    Logger.warning("[Checkout] Helio charge creation failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:helio_payment_status, :failed)
     |> put_flash(:error, "Failed to create payment. Please try again.")}
  end

  def handle_async(:create_helio_charge, {:exit, reason}, socket) do
    Logger.error("[Checkout] Helio charge task crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:helio_payment_status, :failed)
     |> put_flash(:error, "Payment service error. Please try again.")}
  end

  # ── PubSub Handlers ────────────────────────────────────────────────────────

  @impl true
  def handle_info({:order_updated, updated_order}, socket) do
    # Webhook confirmed payment — order is now "paid"
    order = Orders.get_order(updated_order.id)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:helio_payment_status, :completed)
     |> assign(:step, :confirmation)
     |> put_flash(:info, "Payment confirmed! Your order has been placed.")}
  end

  # ── Private Helpers ──────────────────────────────────────────────────────────

  defp assign_order(socket, order) do
    assign(socket, :order, order)
  end

  defp assign_shipping_form(socket, order) do
    changeset = Order.shipping_changeset(order, %{})
    assign(socket, :shipping_changeset, changeset)
  end

  defp assign_payment_defaults(socket) do
    socket
    |> assign(:bux_payment_status, :pending)
    |> assign(:rogue_payment_status, :pending)
    |> assign(:helio_payment_status, :pending)
  end

  defp assign_rogue_defaults(socket) do
    socket
    |> assign(:rogue_usd_amount, Decimal.new("0"))
    |> assign(:rogue_tokens, Decimal.new("0"))
    |> assign(:rogue_discount_saved, Decimal.new("0"))
    |> assign(:helio_amount, remaining_after_bux(socket.assigns.order))
    |> assign(:rogue_rate_locked, nil)
    |> assign(:rogue_rate_locked_at, nil)
  end

  defp lock_rogue_rate(socket) do
    rate = get_current_rogue_rate()

    socket
    |> assign(:rogue_rate_locked, rate)
    |> assign(:rogue_rate_locked_at, System.monotonic_time(:second))
    |> assign(:helio_amount, remaining_after_bux(socket.assigns.order))
  end

  defp recalculate_rogue(socket, rogue_usd) do
    order = socket.assigns.order
    remaining = remaining_after_bux(order)

    # Clamp to remaining amount
    rogue_usd = Decimal.min(rogue_usd, remaining)
    rogue_usd = Decimal.max(rogue_usd, Decimal.new("0"))

    rate = socket.assigns.rogue_rate_locked || get_current_rogue_rate()
    discount_rate = @rogue_discount_rate

    # Calculate: user pays 10% less in ROGUE
    discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
    tokens = if Decimal.gt?(rate, 0), do: Decimal.div(discounted, rate), else: Decimal.new("0")
    saved = Decimal.sub(rogue_usd, discounted)
    helio = Decimal.sub(remaining, rogue_usd)

    socket
    |> assign(:rogue_usd_amount, rogue_usd)
    |> assign(:rogue_tokens, Decimal.round(tokens, 2))
    |> assign(:rogue_discount_saved, Decimal.round(saved, 2))
    |> assign(:helio_amount, Decimal.max(helio, Decimal.new("0")))
  end

  defp advance_after_bux(socket) do
    order = socket.assigns.order

    cond do
      Decimal.gt?(order.rogue_payment_amount || Decimal.new("0"), 0) ->
        # ROGUE payment next — enable the ROGUE payment card
        socket
        |> assign(:rogue_payment_status, :pending)
        |> put_flash(:info, "BUX payment complete! Now pay with ROGUE.")

      Decimal.gt?(order.helio_payment_amount || Decimal.new("0"), 0) ->
        # Helio payment next — enable the Helio payment card
        socket
        |> assign(:helio_payment_status, :pending)
        |> put_flash(:info, "BUX payment complete! Now pay with card or crypto.")

      true ->
        # Fully paid — BUX covered everything
        {:ok, order} = Orders.update_order(order, %{status: "paid"})
        order = Orders.get_order(order.id)

        Orders.process_paid_order(order)

        socket
        |> assign_order(order)
        |> assign(:step, :confirmation)
    end
  end

  defp advance_after_rogue(socket) do
    order = socket.assigns.order

    cond do
      Decimal.gt?(order.helio_payment_amount || Decimal.new("0"), 0) ->
        # Helio payment next — enable the Helio payment card
        socket
        |> assign(:helio_payment_status, :pending)
        |> put_flash(:info, "ROGUE payment complete! Now pay with card or crypto.")

      true ->
        # Fully paid — BUX + ROGUE covered everything
        {:ok, order} = Orders.update_order(order, %{status: "paid"})
        order = Orders.get_order(order.id)

        Orders.process_paid_order(order)

        socket
        |> assign_order(order)
        |> assign(:step, :confirmation)
    end
  end

  defp maybe_complete_after_rogue(socket) do
    order = socket.assigns.order
    helio = order.helio_payment_amount || Decimal.new("0")

    if Decimal.compare(helio, 0) in [:eq, :lt] do
      # BUX + ROGUE covers everything — mark as paid
      {:ok, order} = Orders.update_order(order, %{status: "paid"})
      order = Orders.get_order(order.id)

      Orders.process_paid_order(order)

      socket
      |> assign_order(order)
      |> assign(:step, :confirmation)
      |> put_flash(:info, "Payment complete! Your order has been confirmed.")
    else
      socket
    end
  end

  defp remaining_after_bux(%Order{} = order) do
    Decimal.sub(order.subtotal, order.bux_discount_amount)
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

  defp parse_decimal(str) when is_binary(str) do
    case Decimal.parse(str) do
      {d, ""} -> d
      {d, _} -> d
      :error -> Decimal.new("0")
    end
  end

  defp parse_decimal(_), do: Decimal.new("0")

  # Check if ROGUE rate lock has expired (10 min TTL)
  def rate_expired?(socket) do
    case socket.assigns[:rogue_rate_locked_at] do
      nil -> true
      locked_at -> System.monotonic_time(:second) - locked_at > @rate_lock_ttl_seconds
    end
  end

  # Template helpers
  def format_usd(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  def step_number(:shipping), do: 1
  def step_number(:review), do: 2
  def step_number(:payment), do: 3
  def step_number(:confirmation), do: 4
  def step_number(_), do: 1

  def step_label(:shipping), do: "Shipping"
  def step_label(:review), do: "Review"
  def step_label(:payment), do: "Payment"
  def step_label(:confirmation), do: "Confirmed"
  def step_label(_), do: ""
end
