defmodule BlocksterV2Web.CheckoutLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Orders
  alias BlocksterV2.Orders.Order
  alias BlocksterV2.Shop.BalanceManager
  alias BlocksterV2.Shipping

  require Logger

  # ROGUE payment removed in Phase 9 (Solana migration)
  # @rogue_discount_rate and @rate_lock_ttl_seconds no longer needed

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
            # Note: rogue_pending/rogue_paid kept for backwards compat with old orders
            {:ok,
             socket
             |> put_flash(:error, "This order cannot be modified")
             |> redirect(to: ~p"/cart")}

          %Order{status: "helio_pending"} = order ->
            # Helio payment in progress — subscribe for webhook + start polling
            if connected?(socket) do
              Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "order:#{order.id}")
              Process.send_after(self(), :poll_helio_payment, 3_000)
              Process.send_after(self(), :check_order_status, 3_000)
            end

            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :payment)
             |> assign(:shipping_phase, :address)
             |> assign(:page_title, "Checkout")
             |> assign_shipping_form(order)
             |> assign_shipping_rates(order)
             |> assign_rogue_defaults()
             |> assign_payment_defaults()
             |> assign(:bux_payment_status, if(order.bux_tokens_burned > 0, do: :completed, else: :pending))
             |> assign(:rogue_payment_status, if(Decimal.gt?(order.rogue_payment_amount || Decimal.new("0"), 0), do: :completed, else: :pending))
             |> assign(:helio_payment_status, :processing)}

          %Order{status: s} = order when s in ["rogue_paid", "rogue_pending"] ->
            # Legacy ROGUE statuses — treat as bux_paid for backwards compat
            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :payment)
             |> assign(:shipping_phase, :address)
             |> assign(:page_title, "Checkout")
             |> assign_shipping_form(order)
             |> assign_shipping_rates(order)
             |> assign_rogue_defaults()
             |> assign_payment_defaults()
             |> assign(:bux_payment_status, if(order.bux_tokens_burned > 0, do: :completed, else: :pending))
             |> assign(:rogue_payment_status, :completed)}

          %Order{status: "bux_paid"} = order ->
            # BUX already paid, resume at payment step
            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :payment)
             |> assign(:shipping_phase, :address)
             |> assign(:page_title, "Checkout")
             |> assign_shipping_form(order)
             |> assign_shipping_rates(order)
             |> assign_rogue_defaults()
             |> assign_payment_defaults()
             |> assign(:bux_payment_status, :completed)
             |> assign(:rogue_payment_status, :pending)}

          order ->
            # If shipping already saved with a rate, show rate selection
            shipping_phase =
              if order.shipping_country && order.shipping_country != "" do
                :rate_selection
              else
                :address
              end

            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :shipping)
             |> assign(:shipping_phase, shipping_phase)
             |> assign(:page_title, "Checkout")
             |> assign_shipping_form(order)
             |> assign_shipping_rates(order)
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
         |> assign(:shipping_phase, :rate_selection)
         |> assign_shipping_rates(order)}

      {:error, changeset} ->
        {:noreply, assign(socket, :shipping_changeset, changeset)}
    end
  end

  def handle_event("select_shipping_rate", %{"rate" => rate_key}, socket) do
    case Shipping.get_rate(rate_key) do
      nil ->
        {:noreply, put_flash(socket, :error, "Invalid shipping option")}

      rate ->
        order = socket.assigns.order

        case Orders.update_order_shipping_rate(order, %{
               shipping_cost: rate.cost,
               shipping_method: rate_key
             }) do
          {:ok, order} ->
            order = Orders.get_order(order.id)

            {:noreply,
             socket
             |> assign_order(order)
             |> assign(:step, :review)
             |> assign(:helio_amount, remaining_after_bux(order))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to save shipping option")}
        end
    end
  end

  # ROGUE payment removed in Phase 9 (Solana migration) — no-op for backwards compat
  def handle_event("set_rogue_amount", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("proceed_to_payment", _params, socket) do
    order = socket.assigns.order
    # Remaining after BUX discount goes entirely to Helio (no ROGUE step)
    helio = remaining_after_bux(order)

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
      order = socket.assigns.order

      socket =
        case step_atom do
          :shipping ->
            socket
            |> assign_shipping_form(order)
            |> assign(:shipping_phase, :rate_selection)
            |> assign_shipping_rates(order)

          _ ->
            socket
        end

      {:noreply, assign(socket, :step, step_atom)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit_shipping_address", _params, socket) do
    {:noreply,
     socket
     |> assign(:shipping_phase, :address)
     |> assign_shipping_form(socket.assigns.order)}
  end

  # ── BUX Payment ─────────────────────────────────────────────────────────────

  def handle_event("initiate_bux_payment", _params, socket) do
    order = socket.assigns.order
    user = socket.assigns.current_user
    bux_amount = order.bux_tokens_burned

    if bux_amount <= 0 do
      # No BUX to send, skip to next step
      {:noreply, advance_after_bux(socket)}
    else
      # Attempt optimistic BUX deduction via BalanceManager
      case BalanceManager.deduct_bux(user.id, bux_amount) do
        {:ok, _new_balance} ->
          # Update order status to bux_pending
          {:ok, order} = Orders.update_order(order, %{status: "bux_pending"})
          order = Orders.get_order(order.id)

          # Trigger client-side BUX transfer via JS hook
          {:noreply,
           socket
           |> assign_order(order)
           |> assign(:bux_payment_status, :processing)
           |> push_event("initiate_bux_payment_client", %{amount: bux_amount, order_id: order.id})}

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
    if user.wallet_address do
      BlocksterV2.BuxMinter.sync_user_balances_async(user.id, user.wallet_address, force: true)
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

  # ── ROGUE Payment (deprecated — Solana migration Phase 9) ──────────────────
  # These handlers are kept as no-ops for backwards compatibility with any
  # in-flight orders that may still reference ROGUE payment events.

  def handle_event("initiate_rogue_payment", _params, socket) do
    {:noreply, advance_after_bux(socket)}
  end

  def handle_event("rogue_payment_complete", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("rogue_payment_error", _params, socket) do
    {:noreply, put_flash(socket, :error, "ROGUE payments are no longer supported.")}
  end

  def handle_event("advance_after_rogue", _params, socket) do
    {:noreply, advance_after_bux(socket)}
  end

  # ── Helio Payment ────────────────────────────────────────────────────────

  def handle_event("initiate_helio_payment", _params, socket) do
    order = socket.assigns.order

    # Subscribe for webhook-driven completion
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "order:#{order.id}")

    # Update order status to helio_pending
    {:ok, order} = Orders.update_order(order, %{status: "helio_pending"})
    order = Orders.get_order(order.id)

    paylink_id = Application.get_env(:blockster_v2, :helio_paylink_id)

    # Start polling for completed payment (checks both Helio API and our DB)
    Process.send_after(self(), :poll_helio_payment, 5_000)
    Process.send_after(self(), :check_order_status, 3_000)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:helio_payment_status, :widget_ready)
     |> push_event("helio_render_widget", %{
       paylink_id: paylink_id,
       amount: Decimal.to_string(order.helio_payment_amount),
       order_id: order.id,
       order_number: order.order_number
     })}
  end

  def handle_event("helio_payment_success", params, socket) do
    # Client-side widget reports success — complete the order immediately
    order = socket.assigns.order
    txid = params["transaction_id"] || params["transactionId"]

    {:ok, order} =
      Orders.complete_helio_payment(order, %{
        helio_transaction_id: txid,
        helio_charge_id: order.helio_charge_id,
        helio_payer_address: nil,
        helio_payment_currency: "UNKNOWN"
      })

    order = Orders.get_order(order.id)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:helio_payment_status, :completed)
     |> assign(:step, :confirmation)
     |> put_flash(:info, "Payment confirmed! Your order has been placed.")}
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
         |> put_flash(:info, "Click 'Send BUX' to complete your payment.")
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
        # Remaining balance needs Helio — proceed to confirmation with info
        {:noreply,
         socket
         |> assign(:step, :confirmation)
         |> put_flash(:info, "Order placed! Card/crypto payment processing will be available soon.")}
    end
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

  # ── DB Order Status Polling (catches webhook updates) ─────────────────────

  def handle_info(:check_order_status, socket) do
    if socket.assigns.step == :payment and
       socket.assigns.helio_payment_status in [:widget_ready, :processing, :confirming] do
      order = Orders.get_order(socket.assigns.order.id)

      if order.status in ["paid", "processing", "shipped", "completed"] do
        {:noreply,
         socket
         |> assign_order(order)
         |> assign(:helio_payment_status, :completed)
         |> assign(:step, :confirmation)
         |> put_flash(:info, "Payment confirmed! Your order has been placed.")}
      else
        Process.send_after(self(), :check_order_status, 5_000)
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # ── Helio Payment Polling ──────────────────────────────────────────────────

  def handle_info(:poll_helio_payment, socket) do
    order = socket.assigns.order

    # Only poll if payment is still pending/widget_ready/processing
    if socket.assigns.helio_payment_status in [:widget_ready, :processing, :confirming] and
       order.status in ["helio_pending", "rogue_paid", "bux_paid"] do
      paylink_id = Application.get_env(:blockster_v2, :helio_paylink_id)
      order_id = order.id

      start_async(socket, :poll_helio, fn ->
        case BlocksterV2.Helio.get_paylink_transactions(paylink_id) do
          {:ok, transactions} ->
            # Find a completed transaction matching this order
            Enum.find(transactions, fn tx ->
              meta = parse_tx_meta(tx)
              meta["order_id"] == order_id and tx["status"] in ["COMPLETED", "SUCCESS", "CREATED"]
            end)

          _ ->
            nil
        end
      end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:poll_helio, {:ok, nil}, socket) do
    # No matching transaction yet — poll again in 10 seconds
    if socket.assigns.helio_payment_status in [:widget_ready, :processing, :confirming] do
      Process.send_after(self(), :poll_helio_payment, 5_000)
    end

    {:noreply, socket}
  end

  def handle_async(:poll_helio, {:ok, tx}, socket) do
    # Found a completed transaction — complete the order
    order = socket.assigns.order

    if order.status in ["helio_pending", "rogue_paid", "bux_paid"] do
      currency = BlocksterV2Web.HelioWebhookController.detect_payment_currency(tx)

      {:ok, order} =
        Orders.complete_helio_payment(order, %{
          helio_transaction_id: tx["id"],
          helio_charge_id: tx["chargeId"] || order.helio_charge_id,
          helio_payer_address: tx["senderAddress"],
          helio_payment_currency: currency
        })

      order = Orders.get_order(order.id)

      {:noreply,
       socket
       |> assign_order(order)
       |> assign(:helio_payment_status, :completed)
       |> assign(:step, :confirmation)
       |> put_flash(:info, "Payment confirmed! Your order has been placed.")}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:poll_helio, {:exit, _reason}, socket) do
    # Poll crashed — schedule retry
    if socket.assigns.helio_payment_status in [:widget_ready, :processing, :confirming] do
      Process.send_after(self(), :poll_helio_payment, 5_000)
    end

    {:noreply, socket}
  end

  defp parse_tx_meta(tx) do
    # Try multiple locations where Helio might put the additionalJSON
    raw =
      get_in(tx, ["meta", "customerDetails", "additionalJSON"]) ||
      get_in(tx, ["meta", "additionalJSON"]) ||
      get_in(tx, ["customerDetails", "additionalJSON"]) ||
      tx["meta"]

    case raw do
      s when is_binary(s) ->
        case Jason.decode(s) do
          {:ok, decoded} when is_map(decoded) -> decoded
          _ -> %{}
        end

      m when is_map(m) ->
        m

      _ ->
        %{}
    end
  end

  # ── Private Helpers ──────────────────────────────────────────────────────────

  defp assign_order(socket, order) do
    assign(socket, :order, order)
  end

  defp assign_shipping_form(socket, order) do
    changeset = Order.shipping_changeset(order, %{})
    assign(socket, :shipping_changeset, changeset)
  end

  defp assign_shipping_rates(socket, order) do
    country = order.shipping_country || ""
    zone = Shipping.detect_zone(country)
    rates = Shipping.rates_for_zone(zone)

    socket
    |> assign(:shipping_zone, zone)
    |> assign(:shipping_rates, rates)
    |> assign(:selected_shipping_rate, order.shipping_method)
  end

  defp assign_payment_defaults(socket) do
    order = socket.assigns.order

    bux_status =
      cond do
        order.bux_tokens_burned <= 0 -> :pending
        order.bux_burn_tx_hash != nil -> :completed
        order.status in ["bux_paid", "rogue_paid", "paid", "processing", "shipped", "completed"] -> :completed
        true -> :pending
      end

    rogue_status =
      cond do
        !Decimal.gt?(order.rogue_payment_amount || Decimal.new("0"), 0) -> :pending
        order.rogue_payment_tx_hash != nil -> :completed
        order.status in ["rogue_paid", "paid", "processing", "shipped", "completed"] -> :completed
        true -> :pending
      end

    helio_status =
      cond do
        !Decimal.gt?(order.helio_payment_amount || Decimal.new("0"), 0) -> :pending
        order.helio_transaction_id != nil -> :completed
        order.status in ["paid", "processing", "shipped", "completed"] -> :completed
        order.status == "helio_pending" -> :processing
        true -> :pending
      end

    socket
    |> assign(:bux_payment_status, bux_status)
    |> assign(:rogue_payment_status, rogue_status)
    |> assign(:helio_payment_status, helio_status)
  end

  # ROGUE defaults are zeroed out — ROGUE payment removed in Solana migration.
  # Assigns kept because template and other functions reference them.
  defp assign_rogue_defaults(socket) do
    socket
    |> assign(:rogue_usd_amount, Decimal.new("0"))
    |> assign(:rogue_tokens, Decimal.new("0"))
    |> assign(:rogue_discount_saved, Decimal.new("0"))
    |> assign(:helio_amount, remaining_after_bux(socket.assigns.order))
    |> assign(:rogue_rate_locked, nil)
    |> assign(:rogue_rate_locked_at, nil)
    |> assign(:rogue_balance, Decimal.new("0"))
  end

  defp advance_after_bux(socket) do
    order = socket.assigns.order

    cond do
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

  defp remaining_after_bux(%Order{} = order) do
    shipping = order.shipping_cost || Decimal.new("0")

    order.subtotal
    |> Decimal.add(shipping)
    |> Decimal.sub(order.bux_discount_amount)
  end

  # ROGUE rate and balance functions deprecated — Solana migration Phase 9
  # Kept as stubs returning zero for any remaining references.
  defp get_current_rogue_rate, do: Decimal.new("0")
  defp get_user_rogue_balance(_user), do: Decimal.new("0")

  defp parse_decimal(str) when is_binary(str) do
    case Decimal.parse(str) do
      {d, ""} -> d
      {d, _} -> d
      :error -> Decimal.new("0")
    end
  end

  defp parse_decimal(_), do: Decimal.new("0")

  # ROGUE rate lock check — deprecated, always returns true (no ROGUE payments)
  def rate_expired?(_socket), do: true

  # Template helpers
  def format_usd(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  def format_rogue(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
    |> format_with_commas()
  end

  defp format_with_commas(str) do
    case String.split(str, ".") do
      [int_part, dec_part] ->
        "#{add_commas(int_part)}.#{dec_part}"

      [int_part] ->
        add_commas(int_part)
    end
  end

  defp add_commas(int_str) do
    int_str
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
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
