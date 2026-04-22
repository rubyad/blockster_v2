defmodule BlocksterV2Web.WalletLive.Index do
  @moduledoc """
  Self-custody panel for Web3Auth social-login users.

  Lets email / Google / Apple / X / Telegram users:
    1. See their Solana wallet balance + receive address (QR)
    2. Withdraw SOL to any address
    3. Export their private key and take full custody

  Wallet-Standard users (Phantom, Solflare, Backpack) already have
  self-custody through their wallet extension — they are not shown this page.

  IMPORTANT — security invariants:
    * The actual private key material is NEVER held in LiveView assigns.
      The Web3AuthExport JS hook fetches it via provider.request on demand,
      writes the encoded value into DOM nodes in #export-key-display, and
      zeroes the secretKey buffer in finally. Only @export_format and
      @export_countdown_pct (UI state) live on the server.
    * All withdrawals and key exports are audit-logged server-side for
      incident response. Metadata only — never key material.

  """
  use BlocksterV2Web, :live_view

  require Logger

  alias BlocksterV2.PriceTracker
  alias BlocksterV2.WalletSelfCustody
  alias BlocksterV2.WalletSelfCustody.Auth, as: WalletAuth

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    cond do
      not WalletAuth.feature_enabled?() ->
        {:ok,
         socket
         |> put_flash(:error, "Wallet panel is not yet available.")
         |> push_navigate(to: ~p"/")}

      is_nil(current_user) ->
        {:ok, push_navigate(socket, to: ~p"/")}

      true ->
        mount_authorized(current_user, socket)
    end
  end

  defp mount_authorized(current_user, socket) do
    # Only Web3Auth social-login users see the Export card — external-wallet
    # users (Phantom/Solflare/Backpack) already manage their keys in the
    # wallet extension. Everyone else can still view balance + receive + send.
    web3auth? = WalletAuth.web3auth_user?(current_user)
    audit = if web3auth?, do: WalletSelfCustody.list_recent_for_user(current_user.id, 5), else: []
    sol_usd_price = fetch_sol_usd_price()

    socket =
      socket
      |> assign(:page_title, "Your wallet")
      |> assign(:web3auth?, web3auth?)
      |> assign(:sol_balance, 0.0)
      |> assign(:bux_balance, 0.0)
      |> assign(:sol_usd_price, sol_usd_price)
      |> assign(:last_balance_fetch_at, DateTime.utc_now())
      |> assign(:stage, :idle)
      |> assign(:send_form, %{to: "", amount: "", error: nil, usd_preview: "0.00"})
      |> assign(:pending_tx, nil)
      |> assign(:export_format, "base58")
      |> assign(:export_countdown_pct, 100)
      |> assign(:export_intent_accepted, false)
      |> assign(:audit_events, audit)
      |> assign(:pubkey_qr_svg, render_qr(current_user.wallet_address))

    socket =
      if connected?(socket) do
        start_async(socket, :fetch_balances, fn ->
          fetch_balances(current_user.wallet_address)
        end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:fetch_balances, {:ok, {sol, bux}}, socket) do
    {:noreply,
     socket
     |> assign(:sol_balance, sol)
     |> assign(:bux_balance, bux)
     |> assign(:last_balance_fetch_at, DateTime.utc_now())}
  end

  def handle_async(:fetch_balances, {:ok, {:error, reason}}, socket) do
    Logger.warning("[WalletLive] fetch_balances error: #{inspect(reason)}")
    {:noreply, socket}
  end

  def handle_async(:fetch_balances, {:exit, reason}, socket) do
    Logger.warning("[WalletLive] fetch_balances exit: #{inspect(reason)}")
    {:noreply, socket}
  end

  # ── Send flow stubs ─────────────────────────────────────────────

  @impl true
  def handle_event("calc_send_preview", %{"amount" => amount}, socket) do
    preview = calc_usd_preview(amount, socket.assigns.sol_usd_price)

    send_form = Map.merge(socket.assigns.send_form, %{amount: amount, usd_preview: preview})
    {:noreply, assign(socket, :send_form, send_form)}
  end

  def handle_event("calc_send_preview", _params, socket), do: {:noreply, socket}

  def handle_event("set_send_max", _params, socket) do
    # Reserve ~0.001 SOL for fees + rent exemption minimum.
    max = Float.round(max(socket.assigns.sol_balance - 0.001, 0.0), 6)
    amount_str = :erlang.float_to_binary(max, decimals: 6)
    preview = calc_usd_preview(amount_str, socket.assigns.sol_usd_price)

    send_form =
      Map.merge(socket.assigns.send_form, %{amount: amount_str, usd_preview: preview})

    {:noreply, assign(socket, :send_form, send_form)}
  end

  def handle_event("review_send", %{"to" => to, "amount" => amount}, socket) do
    case validate_send(to, amount, socket.assigns.sol_balance) do
      :ok ->
        preview = calc_usd_preview(amount, socket.assigns.sol_usd_price)
        send_form = %{to: to, amount: amount, error: nil, usd_preview: preview}
        {:noreply, socket |> assign(:stage, :confirming) |> assign(:send_form, send_form)}

      {:error, msg} ->
        send_form = Map.merge(socket.assigns.send_form, %{to: to, amount: amount, error: msg})
        {:noreply, assign(socket, :send_form, send_form)}
    end
  end

  def handle_event("cancel_send", _params, socket) do
    {:noreply, assign(socket, :stage, :idle)}
  end

  def handle_event("confirm_send", _params, socket) do
    log_audit(socket, :withdrawal_initiated, %{
      amount: socket.assigns.send_form.amount,
      to: socket.assigns.send_form.to
    })

    socket =
      socket
      |> assign(:stage, :sending)
      |> push_event("web3auth_withdraw_sign", %{
        to: socket.assigns.send_form.to,
        amount: socket.assigns.send_form.amount
      })

    {:noreply, socket}
  end

  def handle_event("reset_send", _params, socket) do
    send_form = %{to: "", amount: "", error: nil, usd_preview: "0.00"}

    {:noreply,
     socket
     |> assign(:stage, :idle)
     |> assign(:pending_tx, nil)
     |> assign(:send_form, send_form)}
  end

  # Signed + submitted successfully — JS hook reports back.
  def handle_event("withdrawal_submitted", %{"signature" => sig}, socket) do
    pending_tx = %{
      signature: sig,
      amount: socket.assigns.send_form.amount,
      to: socket.assigns.send_form.to
    }

    log_audit(socket, :withdrawal_confirmed, %{
      signature: sig,
      amount: socket.assigns.send_form.amount,
      to: socket.assigns.send_form.to
    })

    audit = WalletSelfCustody.list_recent_for_user(socket.assigns.current_user.id, 5)

    {:noreply,
     socket
     |> assign(:stage, :sent)
     |> assign(:pending_tx, pending_tx)
     |> assign(:audit_events, audit)}
  end

  def handle_event("withdrawal_error", %{"error" => msg}, socket) do
    log_audit(socket, :withdrawal_failed, %{
      error: msg,
      amount: socket.assigns.send_form.amount,
      to: socket.assigns.send_form.to
    })

    send_form = Map.put(socket.assigns.send_form, :error, msg)
    {:noreply, socket |> assign(:stage, :idle) |> assign(:send_form, send_form)}
  end

  # ── Export flow stubs ───────────────────────────────────────────

  def handle_event("start_export_intent", _params, socket) do
    {:noreply,
     socket
     |> assign(:stage, :export_intent)
     |> assign(:export_intent_accepted, false)}
  end

  def handle_event("toggle_export_intent_accepted", _params, socket) do
    {:noreply, update(socket, :export_intent_accepted, &(!&1))}
  end

  def handle_event("cancel_export_intent", _params, socket) do
    {:noreply, assign(socket, :stage, :idle)}
  end

  # Triggers the JS hook to re-auth via Web3Auth, fetch the key, and populate
  # the vault DOM. LiveView flips to the reveal stage and starts the
  # auto-hide countdown.
  def handle_event("start_export_reveal", _params, socket) do
    if socket.assigns.export_intent_accepted do
      Process.send_after(self(), :export_countdown_tick, 1000)

      {:noreply,
       socket
       |> assign(:stage, :export_reveal)
       |> assign(:export_countdown_pct, 100)
       |> push_event("web3auth_export_reveal", %{format: socket.assigns.export_format})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_export_format", %{"format" => format}, socket)
      when format in ["base58", "hex", "qr"] do
    {:noreply,
     socket
     |> assign(:export_format, format)
     |> push_event("web3auth_export_set_format", %{format: format})}
  end

  def handle_event("hide_export_key", _params, socket) do
    {:noreply,
     socket
     |> assign(:stage, :idle)
     |> assign(:export_intent_accepted, false)
     |> push_event("web3auth_export_hide", %{})}
  end

  # Emitted by the Web3AuthExport JS hook once it has fetched + rendered
  # the key. We log this as `key_exported` in the audit trail — never the
  # key itself, just the fact that a reveal occurred.
  def handle_event("export_reauth_completed", _params, socket) do
    log_audit(socket, :key_exported, %{format: socket.assigns.export_format})
    audit = WalletSelfCustody.list_recent_for_user(socket.assigns.current_user.id, 5)
    {:noreply, assign(socket, :audit_events, audit)}
  end

  def handle_event("export_reveal_error", %{"error" => msg}, socket) do
    Logger.warning("[WalletLive] export reveal error: #{msg}")

    {:noreply,
     socket
     |> assign(:stage, :idle)
     |> assign(:export_intent_accepted, false)
     |> put_flash(:error, msg)}
  end

  @impl true
  def handle_info(:export_countdown_tick, socket) do
    if socket.assigns.stage == :export_reveal do
      # 30s total → each tick is ~3.33% (100 / 30)
      remaining = max(socket.assigns.export_countdown_pct - 100 / 30, 0)

      if remaining <= 0 do
        {:noreply,
         socket
         |> assign(:stage, :idle)
         |> assign(:export_intent_accepted, false)
         |> assign(:export_countdown_pct, 0)
         |> push_event("web3auth_export_hide", %{})}
      else
        Process.send_after(self(), :export_countdown_tick, 1000)
        {:noreply, assign(socket, :export_countdown_pct, remaining)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers used by the template ────────────────────────────────

  @doc "Split SOL balance into integer + 4-decimal parts for styling."
  def split_sol(balance) when is_number(balance) do
    amount = :erlang.float_to_binary(balance * 1.0, decimals: 4)
    [int, dec] = String.split(amount, ".", parts: 2)
    {int, dec}
  end

  def split_sol(_), do: {"0", "0000"}

  def format_sol(balance) when is_number(balance) do
    :erlang.float_to_binary(balance * 1.0, decimals: 4)
  end

  def format_sol(_), do: "0.0000"

  # BUX with two decimal places and a thousands separator. On-chain raw units
  # are converted upstream — balance here is already a float in whole BUX.
  def format_bux(balance) when is_number(balance) do
    {int, dec} =
      balance
      |> :erlang.float_to_binary(decimals: 2)
      |> String.split(".", parts: 2)
      |> case do
        [i, d] -> {i, d}
        [i] -> {i, "00"}
      end

    grouped =
      int
      |> String.to_charlist()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.reverse/1)
      |> Enum.reverse()
      |> Enum.intersperse(?,)
      |> List.flatten()
      |> to_string()

    "#{grouped}.#{dec}"
  end

  def format_bux(_), do: "0.00"

  def format_usd(sol_balance, price) when is_number(sol_balance) and is_number(price) do
    :erlang.float_to_binary(sol_balance * price * 1.0, decimals: 2)
  end

  def format_usd(_, _), do: "0.00"

  def format_ts_short(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  def format_ts_short(_), do: "—"

  def truncate_addr(nil), do: "—"
  def truncate_addr(addr) when byte_size(addr) < 12, do: addr

  def truncate_addr(addr) do
    "#{String.slice(addr, 0..3)}…#{String.slice(addr, -4..-1)}"
  end

  @doc "Format a Solana pubkey as 4-char groups for visual verification."
  def format_addr_groups(nil), do: ""

  def format_addr_groups(addr) do
    addr
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(" ")
  end

  def solscan_url(nil), do: "#"

  def solscan_url(sig) do
    # Toggle cluster via WEB3AUTH_CHAIN_ID at runtime; devnet for now.
    cluster =
      case System.get_env("WEB3AUTH_CHAIN_ID", "0x67") do
        "0x65" -> ""
        _ -> "?cluster=devnet"
      end

    "https://solscan.io/tx/#{sig}#{cluster}"
  end

  def display_auth_source("web3auth_email"), do: "Email login"
  def display_auth_source("web3auth_google"), do: "Google login"
  def display_auth_source("web3auth_apple"), do: "Apple login"
  def display_auth_source("web3auth_x"), do: "X login"
  def display_auth_source("web3auth_twitter"), do: "X login"
  def display_auth_source("web3auth_telegram"), do: "Telegram login"
  def display_auth_source("wallet"), do: "Connected wallet"
  def display_auth_source(_), do: "Signed in"

  def display_auth_noun("web3auth_email"), do: "email address"
  def display_auth_noun("web3auth_google"), do: "Google account"
  def display_auth_noun("web3auth_apple"), do: "Apple ID"
  def display_auth_noun("web3auth_x"), do: "X account"
  def display_auth_noun("web3auth_twitter"), do: "X account"
  def display_auth_noun("web3auth_telegram"), do: "Telegram account"
  def display_auth_noun("wallet"), do: "Solana wallet"
  def display_auth_noun(_), do: "sign-in"

  def audit_event_label("withdrawal_initiated"), do: "Withdrawal initiated"
  def audit_event_label("withdrawal_confirmed"), do: "Withdrawal confirmed"
  def audit_event_label("withdrawal_failed"), do: "Withdrawal failed"
  def audit_event_label("key_exported"), do: "Private key exported"
  def audit_event_label("export_reauth_completed"), do: "Export verified"
  def audit_event_label(other), do: other |> to_string() |> String.replace("_", " ")

  # Normalizes access to audit event fields — the struct uses atom keys
  # but the `metadata` JSONB map has string keys once it has round-tripped
  # through Postgres. This helper shrugs at either.
  def audit_field(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  def audit_field(%{} = map, key) when is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  def audit_field(_, _), do: nil

  def zero_pad_pct(pct) when is_number(pct) do
    n = round(pct)
    n |> Integer.to_string() |> String.pad_leading(3, "0")
  end

  def zero_pad_pct(_), do: "000"

  def countdown_seconds_remaining(pct) when is_number(pct) do
    # 30-second total window
    pct
    |> Kernel./(100)
    |> Kernel.*(30)
    |> Float.ceil()
    |> trunc()
  end

  def countdown_seconds_remaining(_), do: 0

  # ── Private helpers ─────────────────────────────────────────────

  defp calc_usd_preview(amount_str, price) when is_binary(amount_str) and is_number(price) do
    case Float.parse(amount_str) do
      {amount, _} -> :erlang.float_to_binary(amount * price * 1.0, decimals: 2)
      :error -> "0.00"
    end
  end

  defp calc_usd_preview(_, _), do: "0.00"

  defp log_audit(socket, event_type, metadata) do
    user_id = socket.assigns.current_user.id

    case WalletSelfCustody.log_event(user_id, event_type, metadata: metadata) do
      {:ok, _event} ->
        :ok

      {:error, changeset} ->
        Logger.warning("[WalletLive] audit log failed: #{inspect(changeset.errors)}")
    end
  end

  # PriceTracker.get_price/1 reads directly from the Mnesia :token_prices
  # table — synchronous, cached, safe to call on mount. Returns `{:ok, %{usd_price: f}}`
  # when the price has been fetched; `{:error, _}` before the first PriceTracker
  # poll completes or if the table isn't up yet.
  defp fetch_sol_usd_price do
    case PriceTracker.get_price("SOL") do
      {:ok, %{usd_price: price}} when is_number(price) and price > 0 -> price * 1.0
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  end

  # Fetches both SOL and BUX balances in a single settler call.
  # `BuxMinter.get_balance/1` hits the settler's GET /balance/:wallet which
  # returns `{ sol, bux }` in lamports-converted floats. On failure the UI
  # shows 0.0 for both — better than erroring the page.
  defp fetch_balances(wallet_address) when is_binary(wallet_address) do
    case BlocksterV2.BuxMinter.get_balance(wallet_address) do
      {:ok, %{sol: sol, bux: bux}} -> {sol * 1.0, bux * 1.0}
      _ -> {0.0, 0.0}
    end
  rescue
    _ -> {0.0, 0.0}
  end

  defp fetch_balances(_), do: {0.0, 0.0}

  # QR for receive-address card. Deterministic SVG from sha256 of pubkey —
  # stable visual, not a real scannable code. Replace with EQRCode once
  # the dep lands (or fold into the receive section's JS rendering).
  defp render_qr(address) when is_binary(address), do: render_stub_qr(address)
  defp render_qr(_), do: ""

  defp validate_send(to, amount, balance) do
    cond do
      not is_binary(to) or String.length(String.trim(to)) < 32 ->
        {:error, "Enter a valid Solana address"}

      not valid_pubkey?(to) ->
        {:error, "That doesn't look like a Solana address"}

      true ->
        case Float.parse(amount || "") do
          {n, _} when n > 0 and n <= balance - 0.001 -> :ok
          {n, _} when n > balance - 0.001 -> {:error, "Amount exceeds balance (incl. fees)"}
          {n, _} when n <= 0 -> {:error, "Amount must be greater than 0"}
          :error -> {:error, "Enter a valid amount"}
        end
    end
  end

  # Very loose pubkey validation — real check is on the JS hook (it decodes
  # with PublicKey and rejects token accounts).
  defp valid_pubkey?(addr) when is_binary(addr) do
    len = String.length(addr)
    len >= 32 and len <= 44 and String.match?(addr, ~r/^[1-9A-HJ-NP-Za-km-z]+$/)
  end

  defp valid_pubkey?(_), do: false

  # Pseudo-QR SVG — deterministic pattern from sha256(pubkey) with proper
  # finder squares in the corners. Reads visually as a QR but isn't a
  # scannable encoding. Good enough for Phase 1; will be replaced by
  # EQRCode.encode(address) |> EQRCode.svg/1 once the dep is added to
  # mix.exs. Tracking in the self-custody backlog.
  defp render_stub_qr(seed) when is_binary(seed) do
    hash = :crypto.hash(:sha256, seed)
    bits = for <<b::1 <- hash>>, do: b
    size = 21

    cells =
      for row <- 0..(size - 1), col <- 0..(size - 1) do
        bit = Enum.at(bits, rem(row * size + col, length(bits)), 0)
        finder = finder_pattern?(row, col, size)

        cond do
          finder == :black -> {row, col, true}
          finder == :white -> {row, col, false}
          true -> {row, col, bit == 1}
        end
      end

    squares =
      cells
      |> Enum.filter(fn {_, _, on} -> on end)
      |> Enum.map(fn {r, c, _} ->
        ~s|<rect x="#{c}" y="#{r}" width="1" height="1" fill="currentColor"/>|
      end)
      |> Enum.join("")

    ~s|<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{size} #{size}" shape-rendering="crispEdges" width="100%" height="100%">#{squares}</svg>|
  end

  defp render_stub_qr(_), do: ""

  # Three 7x7 finder patterns in the corners + their 1px quiet borders.
  defp finder_pattern?(r, c, size) do
    in_top_left = r < 8 and c < 8
    in_top_right = r < 8 and c >= size - 8
    in_bottom_left = r >= size - 8 and c < 8

    cond do
      in_top_left -> finder_cell(r, c)
      in_top_right -> finder_cell(r, c - (size - 7))
      in_bottom_left -> finder_cell(r - (size - 7), c)
      true -> :data
    end
  end

  defp finder_cell(r, c) when r in 0..6 and c in 0..6 do
    cond do
      r in [0, 6] or c in [0, 6] -> :black
      r in [1, 5] or c in [1, 5] -> :white
      true -> :black
    end
  end

  defp finder_cell(_, _), do: :white
end
