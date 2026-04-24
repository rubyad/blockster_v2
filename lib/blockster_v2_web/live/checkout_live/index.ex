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
            # `@shipping_phase` is read by the stepper helper (SHOP-12), so
            # paid-order mounts also need it assigned — `:rate_selection`
            # here is a no-op value since `@step == :confirmation` already
            # trumps any shipping-phase sub-state.
            {:ok,
             socket
             |> assign_order(order)
             |> assign(:step, :confirmation)
             |> assign(:shipping_phase, :rate_selection)
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

            # Recovery: if we're landing on a paid order that never ran its
            # post-paid side effects (cart clear, confirmation email, etc.),
            # fire them here. Happens when the previous session's LV missed
            # the {:order_updated, _} broadcast (PubSub drop / commit race
            # pre-2026-04-24) so `Orders.process_paid_order` never ran and
            # the cart wasn't cleared. `process_paid_order` is idempotent —
            # checks `fulfillment_notified_at` before firing side effects.
            if order.status == "paid" and is_nil(order.fulfillment_notified_at) do
              Orders.process_paid_order(order)
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
             |> maybe_load_payment_intent()
             |> maybe_create_payment_intent()}
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

    # SHOP-10: first touch flips error visibility on so "can't be blank"
    # messages don't render on an un-touched form.
    {:noreply,
     socket
     |> assign(:shipping_changeset, changeset)
     |> assign(:show_validation_errors, true)}
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
        # SHOP-10: failed submit flips the error visibility on (if it wasn't
        # already) so the user can see which fields need work.
        {:noreply,
         socket
         |> assign(:shipping_changeset, changeset)
         |> assign(:show_validation_errors, true)}
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

  def handle_event("initiate_bux_payment", _params, socket) do
    order = socket.assigns.order
    user = socket.assigns.current_user
    bux_amount = order.bux_tokens_burned

    cond do
      bux_amount <= 0 ->
        {:noreply, socket}

      # Re-entrant retry: order already flipped to bux_pending + Mnesia was
      # already debited on the first attempt. Skip the second deduct and
      # just re-fire the client event so the (now working) hook can try
      # the burn again. Without this guard, refresh-then-retry double-
      # deducts — the bug the stuck-processing ticket originally tripped.
      order.status == "bux_pending" and order.bux_burn_tx_hash in [nil, ""] ->
        {:noreply,
         socket
         |> assign(:bux_payment_status, :processing)
         |> push_event("initiate_bux_payment_client", %{
           amount: bux_amount,
           order_id: order.id
         })}

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

  # User-initiated cancel from the :processing UI. Only valid when the burn
  # genuinely never landed (tx hash still nil) — otherwise we'd refund BUX
  # the user already lost on chain. Reuses the refund path in bux_payment_error.
  def handle_event("cancel_bux_payment", _params, socket) do
    order = socket.assigns.order

    cond do
      order.bux_burn_tx_hash not in [nil, ""] ->
        {:noreply, put_flash(socket, :error, "BUX already burned on chain — cannot cancel.")}

      order.status not in ["bux_pending", "pending"] ->
        {:noreply, put_flash(socket, :error, "Order is no longer in a cancellable state.")}

      true ->
        handle_event("bux_payment_error", %{"error" => "Cancelled by user"}, socket)
        |> then(fn {:noreply, s} ->
          {:noreply, assign(s, :bux_payment_status, :pending) |> put_flash(:info, "BUX refunded to your balance.")}
        end)
    end
  end

  # ── SOL direct payment ─────────────────────────────────────────────────────

  def handle_event("initiate_sol_payment", _params, socket) do
    case socket.assigns[:payment_intent] do
      nil ->
        {:noreply, maybe_create_payment_intent(socket)}

      %{status: "pending"} = intent ->
        # Flip status immediately so the UI reflects "in progress" while the
        # wallet modal opens. Without this, `phx-disable-with` resolves the
        # instant the push_event returns and the user sees the button snap
        # back to "Pay X SOL" while their wallet is loading.
        {:noreply,
         socket
         |> assign(:sol_payment_status, :signing)
         |> push_event("send_sol_payment", %{
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

    # Persist the buyer's tx sig on the intent before the watcher runs —
    # settler's `getSignaturesForAddress` lookup is best-effort and can
    # return null right after the tx lands (balance is visible but the
    # sig index hasn't caught up). Recording here guarantees the
    # confirmation page shows the actual tx link.
    if intent = socket.assigns[:payment_intent] do
      Task.start(fn -> PaymentIntents.record_submitted_tx_sig(intent.id, sig) end)
    end

    # JS already confirmed on-chain (via getSignatureStatuses polling in
    # signAndConfirm) before pushing this event. Don't wait up to 10s for
    # the next PaymentIntentWatcher tick — fire the check inline. The
    # watcher hits the settler, flips the intent to funded, and broadcasts
    # {:order_updated, order} which this LV already subscribes to.
    Task.start(fn -> BlocksterV2.PaymentIntentWatcher.tick_once() end)

    # Safety net: if the broadcast is missed (LV remount race, transient
    # pubsub drop) schedule a polling check. Retries stop once the LV
    # sees status == :completed.
    Process.send_after(self(), :poll_intent_status, 1500)

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

    socket =
      socket
      |> assign_order(order)
      |> assign(:sol_payment_status, :completed)
      |> maybe_load_payment_intent()
      |> assign(:step, if(order.status == "paid", do: :confirmation, else: socket.assigns.step))
      |> put_flash(:info, "Payment confirmed! Your order is placed.")
      |> refresh_token_balances_async()

    {:noreply, socket}
  end

  # Fallback polling in case the PubSub broadcast was missed. Runs tick_once
  # → if the order has been marked paid by now, transitions via the
  # {:order_updated, ...} path which this LV also subscribes to. Stops
  # polling once we observe :completed status (PubSub got through).
  def handle_info(:poll_intent_status, socket) do
    if socket.assigns.sol_payment_status == :completed do
      {:noreply, socket}
    else
      Task.start(fn -> BlocksterV2.PaymentIntentWatcher.tick_once() end)

      # Also do a direct DB re-read — if mark_funded landed but the
      # broadcast was dropped, we pick it up from the DB shape.
      order = Orders.get_order(socket.assigns.order.id)

      cond do
        order.status == "paid" ->
          Orders.process_paid_order(order)

          {:noreply,
           socket
           |> assign_order(order)
           |> assign(:sol_payment_status, :completed)
           |> maybe_load_payment_intent()
           |> assign(:step, :confirmation)
           |> put_flash(:info, "Payment confirmed! Your order is placed.")
           |> refresh_token_balances_async()}

        true ->
          Process.send_after(self(), :poll_intent_status, 1500)
          {:noreply, socket}
      end
    end
  end

  def handle_info({ref, balances}, socket) when is_reference(ref) and is_map(balances) do
    Process.demonitor(ref, [:flush])
    merged = Map.merge(socket.assigns[:token_balances] || %{}, balances)

    user_id = socket.assigns.current_user && socket.assigns.current_user.id
    if user_id, do: BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update(user_id, balances)

    {:noreply, assign(socket, :token_balances, merged)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Re-read the user's SOL + BUX balances on-chain after payment so the
  # header pill drops by the SOL paid + any BUX burned. Runs in a Task so
  # the LV doesn't block on RPC. Result arrives via the `{ref, balances}`
  # handle_info above.
  defp refresh_token_balances_async(socket) do
    user = socket.assigns[:current_user]
    wallet = socket.assigns[:wallet_address]

    if user && is_binary(wallet) do
      Task.async(fn ->
        BlocksterV2.BuxMinter.sync_user_balances(user.id, wallet)
        sol = BlocksterV2.EngagementTracker.get_user_sol_balance(user.id)
        bux = BlocksterV2.EngagementTracker.get_user_solana_bux_balance(user.id)
        %{"SOL" => sol, "BUX" => bux}
      end)
    end

    socket
  end

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp assign_order(socket, order), do: assign(socket, :order, order)

  defp assign_shipping_form(socket, order) do
    changeset = Order.shipping_changeset(order, %{})

    # SHOP-10: errors stay hidden until the first `validate_shipping` event
    # flips this on (or the user attempts `save_shipping`). Checkout mount
    # with empty required fields MUST NOT flash "can't be blank" per-field.
    socket
    |> assign(:shipping_changeset, changeset)
    |> assign_new(:show_validation_errors, fn -> false end)
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

    socket
    |> assign(:bux_payment_status, bux_status)
    |> assign(:sol_payment_status, sol_status)
    |> assign(:sol_usd_rate, rate)
    |> assign(:remaining_usd, remaining_usd)
    |> assign(:remaining_sol, remaining_sol)
    |> assign(:remaining_lamports, round(remaining_sol * @sol_mark_lamports))
    |> assign(:payment_intent, nil)
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

  @doc """
  SHOP-10: returns the per-field error list only after the user has interacted
  with the shipping form. On mount with empty required fields the changeset
  already has "can't be blank" errors, but we hide them until first
  `validate_shipping` / `save_shipping` sets `@show_validation_errors` true.
  """
  def shipping_field_errors(_changeset, false, _field), do: []

  def shipping_field_errors(changeset, true, field) do
    Keyword.get_values(changeset.errors, field)
  end

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

  @doc """
  SHOP-12: stepper-visual step number keyed on `{step, shipping_phase}` so
  dot progression matches user perception. Once the user submits the
  shipping address the app is logically still in `:shipping` but UX-wise
  they've moved past it — light dot 2 during `:rate_selection`.
  """
  def visual_step_number(:shipping, :rate_selection), do: 2
  def visual_step_number(step, _phase), do: step_number(step)

  def step_label(:shipping), do: "Shipping"
  def step_label(:review), do: "Review"
  def step_label(:payment), do: "Payment"
  def step_label(:confirmation), do: "Confirmed"
  def step_label(_), do: ""
end
