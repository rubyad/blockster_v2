defmodule BlocksterV2.PaymentIntents do
  @moduledoc """
  Context for SOL payment intents. Creates an intent per order (generating a
  fresh ephemeral keypair via the settler service), polls status, and records
  sweep transactions.

  The private key material lives on the settler — Elixir only ever sees the
  pubkey. That keeps Solana signing confined to one service.
  """

  import Ecto.Query
  require Logger

  alias BlocksterV2.Repo
  alias BlocksterV2.Orders.{Order, PaymentIntent}
  alias BlocksterV2.Shop.Pricing
  alias BlocksterV2.SettlerClient

  # Window in which the buyer must fund the ephemeral address. After this,
  # the intent is marked expired and the order reverts to the checkout step.
  @intent_ttl_seconds 15 * 60

  @doc """
  Creates a payment intent for `order` using `buyer_wallet` (the connected
  Solana address). Quotes the SOL amount at the current rate and asks the
  settler to generate the ephemeral keypair.

  `opts`:
    * `:payment_mode` — `"manual"` (default) or `"wallet_sign"`. Web3Auth
      users default to `"wallet_sign"`; pass user-aware mode via
      `payment_mode_for_user/1`.

  Returns `{:ok, intent}` or `{:error, reason}`.
  """
  def create_for_order(%Order{} = order, buyer_wallet, opts \\ []) when is_binary(buyer_wallet) do
    payment_mode = Keyword.get(opts, :payment_mode, "manual")
    total_usd = total_usd_due(order)
    rate = Pricing.sol_usd_rate()
    expected_sol = Decimal.to_float(total_usd) / rate
    expected_lamports = round(expected_sol * 1_000_000_000)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, @intent_ttl_seconds, :second)

    with {:ok, %{pubkey: pubkey}} <- SettlerClient.create_payment_intent(order.id),
         {:ok, intent} <-
           PaymentIntent.create_changeset(%{
             order_id: order.id,
             buyer_wallet: buyer_wallet,
             pubkey: pubkey,
             expected_lamports: expected_lamports,
             quoted_usd: total_usd,
             quoted_sol_usd_rate: Decimal.from_float(rate),
             expires_at: expires_at,
             payment_mode: payment_mode
           })
           |> Repo.insert() do
      {:ok, intent}
    end
  end

  @web3auth_auth_methods ~w(web3auth_email web3auth_google web3auth_apple web3auth_x web3auth_telegram)

  @doc """
  Decide the payment mode for a user. Web3Auth social users sign locally
  from their exported ed25519 key with the settler as fee_payer — direct
  settler-mediated transfer (`wallet_sign`). Wallet users transfer from
  their own SOL balance to the ephemeral address (`manual`).

  Unknown / nil users default to `manual` (the safer behavior — no settler
  fee burn if someone hits the checkout without a session somehow).
  """
  def payment_mode_for_user(%{auth_method: auth}) when auth in @web3auth_auth_methods,
    do: "wallet_sign"

  def payment_mode_for_user(_), do: "manual"

  @doc "Fetches the current intent for an order, or nil."
  def get_for_order(order_id) do
    Repo.get_by(PaymentIntent, order_id: order_id)
  end

  @doc "Intents that are still awaiting a buyer transfer."
  def list_pending do
    from(i in PaymentIntent, where: i.status == "pending")
    |> Repo.all()
  end

  @doc "Intents that were funded but haven't been swept to treasury."
  def list_fundings_to_sweep do
    from(i in PaymentIntent, where: i.status == "funded")
    |> Repo.all()
  end

  @doc """
  Marks an intent as funded. Called by the watcher after the settler confirms
  the ephemeral address received >= expected_lamports.
  """
  @doc """
  Records the tx signature the buyer's wallet produced, BEFORE the settler
  watcher has confirmed the ephemeral address funded. Lets us preserve the
  buyer-side sig even if settler's `getSignaturesForAddress` lookup lags —
  we'd rather show the actual tx than leave the confirmation page tx-less.
  """
  def record_submitted_tx_sig(intent_id, tx_sig) when is_binary(tx_sig) and tx_sig != "" do
    case Repo.get(PaymentIntent, intent_id) do
      nil ->
        {:error, :not_found}

      intent ->
        intent
        |> Ecto.Changeset.change(%{funded_tx_sig: tx_sig})
        |> Repo.update()
    end
  end

  def record_submitted_tx_sig(_, _), do: {:error, :invalid_sig}

  def mark_funded(intent_id, tx_sig, funded_lamports) do
    Repo.get(PaymentIntent, intent_id)
    |> case do
      nil ->
        {:error, :not_found}

      intent ->
        # Prefer the sig the caller passed (settler's best-effort lookup),
        # fall back to whatever's already on the row (typically recorded
        # via record_submitted_tx_sig/2 from the buyer). Prevents the
        # watcher from clobbering a known-good sig with a nil when
        # getSignaturesForAddress races balance propagation on the RPC.
        resolved_sig = tx_sig || intent.funded_tx_sig

        attrs = %{
          status: "funded",
          funded_tx_sig: resolved_sig,
          funded_lamports: funded_lamports,
          funded_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        # Commit the intent-funded + order-paid writes together. Broadcast
        # AFTER the transaction returns — if we broadcast from inside the
        # transaction, subscribers racing a fresh read on a different
        # connection see the pre-commit state and skip the paid-status
        # branch (root cause of "confirmation didn't show until refresh").
        case Repo.transaction(fn ->
               {:ok, updated} = intent |> PaymentIntent.funded_changeset(attrs) |> Repo.update()
               {:ok, order} = mark_order_paid(intent.order_id)
               {updated, order}
             end) do
          {:ok, {updated, order}} ->
            broadcast_order(order)
            {:ok, updated}

          {:error, _} = err ->
            err
        end
    end
  end

  defp broadcast_order(order) do
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "order:#{order.id}",
      {:order_updated, order}
    )
  end

  @doc "Marks an intent as swept (funds moved out of ephemeral → treasury)."
  def mark_swept(intent_id, sweep_tx_sig) do
    Repo.get(PaymentIntent, intent_id)
    |> case do
      nil ->
        {:error, :not_found}

      intent ->
        intent
        |> PaymentIntent.swept_changeset(%{
          status: "swept",
          swept_tx_sig: sweep_tx_sig,
          swept_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
    end
  end

  @doc "Marks an intent expired + releases its order (status → cancelled)."
  def mark_expired(intent_id) do
    Repo.get(PaymentIntent, intent_id)
    |> case do
      nil ->
        {:error, :not_found}

      intent ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Repo.transaction(fn ->
          {:ok, updated} =
            intent |> PaymentIntent.status_changeset("expired", now) |> Repo.update()

          {:ok, _} = release_order(intent.order_id)
          updated
        end)
    end
  end

  def mark_checked(intent_id) do
    Repo.get(PaymentIntent, intent_id)
    |> case do
      nil ->
        :ok

      intent ->
        intent
        |> PaymentIntent.status_changeset(
          intent.status,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update()

        :ok
    end
  end

  def expired?(%PaymentIntent{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  # Total amount the buyer owes after BUX discount + shipping, in USD.
  defp total_usd_due(%Order{} = order) do
    subtotal = order.subtotal || Decimal.new(0)
    shipping = order.shipping_cost || Decimal.new(0)
    discount = order.bux_discount_amount || Decimal.new(0)

    subtotal
    |> Decimal.add(shipping)
    |> Decimal.sub(discount)
    |> Decimal.max(Decimal.new(0))
  end

  defp mark_order_paid(order_id) do
    Repo.get(Order, order_id)
    |> case do
      nil ->
        {:error, :order_not_found}

      order ->
        order
        |> Ecto.Changeset.change(%{status: "paid"})
        |> Repo.update()
    end
  end

  defp release_order(order_id) do
    Repo.get(Order, order_id)
    |> case do
      nil ->
        {:ok, nil}

      order ->
        order
        |> Ecto.Changeset.change(%{status: "cancelled"})
        |> Repo.update()
    end
  end
end
