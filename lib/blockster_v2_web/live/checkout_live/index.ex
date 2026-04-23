defmodule BlocksterV2Web.CheckoutLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Orders
  alias BlocksterV2.Orders.Order
  alias BlocksterV2.Shop.BalanceManager
  alias BlocksterV2.Shipping
  alias BlocksterV2.PaymentIntents
  alias BlocksterV2.Shop.Pricing

  require Logger

  @sol_mark_lamports 1_000_000_000

  @impl true
  def mount(%{"order_id" => order_id}, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Please connect your wallet to continue checkout")
         |> redirect(to: ~p"/")}

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

          %Order{status: s} = order when s in ["cancelled", "expired", "refunded"] ->
            {:ok,
             socket
             |> put_flash(:error, "This order cannot be modified")
             |> assign_order(order)
             |> redirect(to: ~p"/cart")}

          order ->
            shipping_phase =
              if order.shipping_country && order.shipping_country != "" do
                :rate_selection
              else
                :address
              end

            step =
              cond do
                order.status in ["bux_paid", "bux_pending"] -> :payment
                order.shipping_cost && Decimal.gt?(order.shipping_cost, Decimal.new(0)) and
                  order.shipping_country && order.shipping_country != "" -> :review
                true -> :shipping
              end

            if connected?(socket) do
              Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "order:#{order.id}")
            end

            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, step)
             |> assign(:shipping_phase, shipping_phase)
             |> assign(:page_title, "Checkout")
             |> assign_shipping_form(order)
             |> assign_shipping_rates(order)
             |> assign_payment_defaults()
             |> maybe_load_payment_intent()}
        end
    end
  end

  # ── Shipping step ───────────────────────────────────────────────────────────

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
            {:noreply, socket |> assign_order(order) |> assign(:step, :review)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to save shipping option")}
        end
    end
  end

  def handle_event("edit_shipping_address", _params, socket) do
    {:noreply,
     socket
     |> assign(:shipping_phase, :address)
     |> assign_shipping_form(socket.assigns.order)}
  end

  # ── Review → Payment ────────────────────────────────────────────────────────

  def handle_event("proceed_to_payment", _params, socket) do
    order = socket.assigns.order
    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:step, :payment)
     |> assign_payment_defaults()
     |> maybe_create_payment_intent()}
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

  # ── BUX discount burn (optional; only when BUX tokens were allocated) ───────

  def handle_event("toggle_bux_warning_ack", _params, socket) do
    {:noreply, assign(socket, :bux_warning_ack, not socket.assigns.bux_warning_ack)}
  end

  def handle_event("initiate_bux_payment", _params, socket) do
    order = socket.assigns.order
    user = socket.assigns.current_user
    bux_amount = order.bux_tokens_burned

    cond do
      bux_amount <= 0 ->
        {:noreply, socket}

      not socket.assigns.bux_warning_ack ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Please acknowledge that BUX is non-refundable before continuing."
         )}

      true ->
        case BalanceManager.deduct_bux(user.id, bux_amount) do
          {:ok, _new_balance} ->
            now = DateTime.utc_now() |> DateTime.truncate(:second)

            {:ok, order} =
              Orders.update_order(order, %{status: "bux_pending", bux_burn_started_at: now})

            order = Orders.get_order(order.id)

            {:noreply,
             socket
             |> assign_order(order)
             |> assign(:bux_payment_status, :processing)
             |> push_event("initiate_bux_payment_client", %{
               amount: bux_amount,
               order_id: order.id
             })}

          {:error, :insufficient, current_balance} ->
            {:noreply,
             socket
             |> assign(:bux_payment_status, :failed)
             |> put_flash(
               :error,
               "Insufficient BUX balance. You have #{trunc(current_balance)} BUX but need #{bux_amount} BUX."
             )}
        end
    end
  end

  # Canonical SHOP-15 success event — the rebuilt JS hook pushes this with the
  # burn tx signature after confirming via `getSignatureStatuses` polling
  # (CLAUDE.md; NEVER confirmTransaction). Keep the legacy `bux_payment_complete`
  # handler below as a thin shim so a half-rolled-out hook can't brick an
  # in-flight checkout.
  def handle_event("bux_burn_confirmed", %{"sig" => sig}, socket) do
    finalize_bux_burn(socket, sig)
  end

  def handle_event("bux_payment_complete", %{"tx_hash" => hash}, socket) do
    finalize_bux_burn(socket, hash)
  end

  defp finalize_bux_burn(socket, tx_hash) when is_binary(tx_hash) and byte_size(tx_hash) > 0 do
    order = socket.assigns.order

    # Idempotent: if the sig already landed (two firings of the same event,
    # e.g. hook retries on flaky websocket), re-use the existing order.
    order =
      if order.bux_burn_tx_hash in [nil, ""] do
        {:ok, order} = Orders.complete_bux_payment(order, tx_hash)
        Orders.get_order(order.id)
      else
        order
      end

    user = socket.assigns.current_user

    if user.wallet_address do
      BlocksterV2.BuxMinter.sync_user_balances_async(user.id, user.wallet_address, force: true)
    end

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:bux_payment_status, :completed)
     |> put_flash(:info, "BUX applied!")
     |> maybe_create_payment_intent()}
  end

  defp finalize_bux_burn(socket, _), do: {:noreply, socket}

  def handle_event("bux_payment_error", %{"error" => err}, socket) do
    order = socket.assigns.order
    user = socket.assigns.current_user

    if order.bux_tokens_burned > 0 do
      BalanceManager.credit_bux(user.id, order.bux_tokens_burned)
    end

    {:ok, order} = Orders.update_order(order, %{status: "pending"})
    order = Orders.get_order(order.id)

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:bux_payment_status, :failed)
     |> put_flash(:error, "BUX payment failed: #{err}")}
  end

  # ── SOL direct payment ─────────────────────────────────────────────────────

  def handle_event("initiate_sol_payment", _params, socket) do
    case socket.assigns[:payment_intent] do
      nil ->
        {:noreply, maybe_create_payment_intent(socket)}

      %{status: "pending"} = intent ->
        {:noreply,
         push_event(socket, "send_sol_payment", %{
           to: intent.pubkey,
           lamports: intent.expected_lamports,
           order_id: socket.assigns.order.id
         })}

      _intent ->
        {:noreply, socket}
    end
  end

  def handle_event("sol_payment_submitted", %{"signature" => sig}, socket) do
    Logger.info("[Checkout] SOL payment submitted: #{sig}")
    {:noreply, assign(socket, :sol_payment_status, :confirming)}
  end

  def handle_event("sol_payment_error", %{"error" => err}, socket) do
    {:noreply,
     socket
     |> assign(:sol_payment_status, :failed)
     |> put_flash(:error, "Wallet rejected: #{err}")}
  end

  # ── PubSub: watcher broadcasts when intent is funded ────────────────────────

  @impl true
  def handle_info({:order_updated, updated_order}, socket) do
    order = Orders.get_order(updated_order.id)

    if order.status == "paid" do
      Orders.process_paid_order(order)
    end

    {:noreply,
     socket
     |> assign_order(order)
     |> assign(:sol_payment_status, :completed)
     |> maybe_load_payment_intent()
     |> assign(:step, if(order.status == "paid", do: :confirmation, else: socket.assigns.step))
     |> put_flash(:info, "Payment confirmed! Your order is placed.")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp assign_order(socket, order), do: assign(socket, :order, order)

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
    rate = Pricing.sol_usd_rate()

    remaining_usd = remaining_after_bux(order)
    remaining_sol = Decimal.to_float(remaining_usd) / rate

    bux_status =
      cond do
        order.bux_tokens_burned <= 0 -> :not_applicable
        order.bux_burn_tx_hash != nil -> :completed
        order.status in ["bux_paid", "paid"] -> :completed
        true -> :pending
      end

    sol_status =
      cond do
        order.status == "paid" -> :completed
        Decimal.eq?(remaining_usd, Decimal.new(0)) -> :not_applicable
        true -> :pending
      end

    # bux_warning_ack: SHOP-14 pre-burn non-refundable acknowledgement. If the
    # burn already landed (or there's no BUX to burn) the gate is moot — default
    # true so the UI doesn't re-prompt. Otherwise default false; user ticks the
    # checkbox before the burn CTA enables.
    bux_warning_ack =
      bux_status in [:completed, :not_applicable] or order.bux_burn_started_at != nil

    socket
    |> assign(:bux_payment_status, bux_status)
    |> assign(:sol_payment_status, sol_status)
    |> assign(:sol_usd_rate, rate)
    |> assign(:remaining_usd, remaining_usd)
    |> assign(:remaining_sol, remaining_sol)
    |> assign(:remaining_lamports, round(remaining_sol * @sol_mark_lamports))
    |> assign(:payment_intent, nil)
    |> assign_new(:bux_warning_ack, fn -> bux_warning_ack end)
  end

  defp maybe_load_payment_intent(socket) do
    case PaymentIntents.get_for_order(socket.assigns.order.id) do
      nil -> socket
      intent -> assign(socket, :payment_intent, intent)
    end
  end

  defp maybe_create_payment_intent(socket) do
    order = socket.assigns.order
    user = socket.assigns.current_user

    cond do
      socket.assigns[:payment_intent] != nil ->
        socket

      Decimal.eq?(remaining_after_bux(order), Decimal.new(0)) ->
        # Fully covered by BUX — mark order paid and jump to confirmation
        {:ok, paid} = Orders.update_order(order, %{status: "paid"})
        paid = Orders.get_order(paid.id)
        Orders.process_paid_order(paid)

        socket
        |> assign_order(paid)
        |> assign(:step, :confirmation)

      order.bux_tokens_burned > 0 and order.bux_burn_tx_hash in [nil, ""] ->
        # Still waiting on the BUX burn tx — don't create the SOL intent until
        # BUX has actually been applied (otherwise the intent amount changes).
        socket

      true ->
        wallet = user.wallet_address || ""

        case PaymentIntents.check_sol_payment_allowed(user, order) do
          {:error, :web3auth_sol_not_supported} ->
            # Phase 7 gate: Web3Auth users can't pay in SOL in v1 — settler
            # has no path to take SOL off them without a wallet-standard
            # signing UX. Point them at BUX pricing or ask them to connect
            # a wallet.
            socket
            |> assign(:sol_payment_status, :gated)
            |> put_flash(
              :error,
              "SOL checkout is wallet-only right now. Pay with BUX, or connect a Solana wallet."
            )

          :ok ->
            mode = PaymentIntents.payment_mode_for_user(user)

            case PaymentIntents.create_for_order(order, wallet, payment_mode: mode) do
              {:ok, intent} ->
                assign(socket, :payment_intent, intent)

              {:error, reason} ->
                Logger.error("[Checkout] intent creation failed: #{inspect(reason)}")

                socket
                |> assign(:sol_payment_status, :failed)
                |> put_flash(:error, "Could not generate payment address. Please refresh.")
            end
        end
    end
  end

  defp remaining_after_bux(%Order{} = order) do
    shipping = order.shipping_cost || Decimal.new("0")
    discount = order.bux_discount_amount || Decimal.new("0")

    order.subtotal
    |> Decimal.add(shipping)
    |> Decimal.sub(discount)
    |> Decimal.max(Decimal.new(0))
  end

  # ── Template helpers ────────────────────────────────────────────────────────

  def format_usd(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  def format_sol_amount(nil), do: "0.00"
  def format_sol_amount(float) when is_number(float), do: Pricing.format_sol(float)

  def payment_step_copy(%{order: %Order{bux_tokens_burned: bux}}) when bux > 0 do
    "First burn the BUX you redeemed (one Solana tx), then send SOL to your one-time payment address to complete the order."
  end

  def payment_step_copy(_assigns) do
    "Send SOL directly from your connected wallet to your one-time payment address. We'll confirm on chain and mark your order paid."
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
