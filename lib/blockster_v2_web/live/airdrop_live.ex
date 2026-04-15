defmodule BlocksterV2Web.AirdropLive do
  use BlocksterV2Web, :live_view

  require Logger

  alias BlocksterV2.Airdrop
  alias BlocksterV2Web.DesignSystem

  @quick_chips [100, 1_000, 2_500, 10_000]
  @winners_collapsed_count 8

  # ============================================================
  # Mount
  # ============================================================

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    token_balances = socket.assigns[:token_balances] || %{}
    wallet_address = socket.assigns[:wallet_address]

    user_bux_balance =
      case token_balances do
        %{"BUX" => balance} when is_number(balance) -> trunc(balance)
        _ -> 0
      end

    current_round = Airdrop.get_current_round()
    round_id = if current_round, do: current_round.round_id

    airdrop_end_time =
      if current_round do
        DateTime.to_unix(current_round.end_time)
      else
        # Default countdown if no round
        DateTime.new!(~D[2026-05-01], ~T[17:00:00], "Etc/UTC") |> DateTime.to_unix()
      end

    user_entries =
      if current_user && round_id do
        Airdrop.get_user_entries(current_user.id, round_id)
      else
        []
      end

    {total_entries, participant_count} =
      if round_id do
        {Airdrop.get_total_entries(round_id), Airdrop.get_participant_count(round_id)}
      else
        {0, 0}
      end

    airdrop_drawn = current_round != nil && current_round.status == "drawn"

    {winners, verification_data, entry_results} =
      if airdrop_drawn do
        w = Airdrop.get_winners(round_id)

        vd =
          case Airdrop.get_verification_data(round_id) do
            {:ok, data} -> data
            _ -> nil
          end

        er = compute_entry_results(user_entries, w)
        {w, vd, er}
      else
        {[], nil, %{}}
      end

    if connected?(socket) do
      if round_id, do: Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "airdrop:#{round_id}")
      :timer.send_interval(1000, self(), :tick)
    end

    prize_summary = Airdrop.prize_summary()

    socket =
      socket
      |> assign(:page_title, "Airdrop")
      |> assign(:user_bux_balance, user_bux_balance)
      |> assign(:airdrop_end_time, airdrop_end_time)
      |> assign(:prize_summary, prize_summary)
      |> assign(:redeem_amount, "")
      |> assign(:time_remaining, calculate_time_remaining(airdrop_end_time))
      |> assign(:current_round, current_round)
      |> assign(:user_entries, Enum.reverse(user_entries))
      |> assign(:entry_results, entry_results)
      |> assign(:total_entries, total_entries)
      |> assign(:participant_count, participant_count)
      |> assign(:wallet_connected, wallet_address != nil)
      |> assign(:airdrop_drawn, airdrop_drawn)
      |> assign(:winners, winners)
      |> assign(:verification_data, verification_data)
      |> assign(:redeeming, false)
      |> assign(:claiming_index, nil)
      |> assign(:show_fairness_modal, false)
      |> assign(:show_all_winners, false)

    {:ok, socket}
  end

  # ============================================================
  # Event Handlers
  # ============================================================

  @impl true
  def handle_event("update_redeem_amount", %{"value" => value}, socket) do
    cleaned_value = String.replace(value, ~r/[^\d]/, "")
    {:noreply, assign(socket, :redeem_amount, cleaned_value)}
  end

  def handle_event("set_max", _params, socket) do
    max_amount = socket.assigns.user_bux_balance |> to_string()
    {:noreply, assign(socket, :redeem_amount, max_amount)}
  end

  def handle_event("set_amount", %{"value" => value}, socket) do
    cleaned = String.replace(to_string(value), ~r/[^\d]/, "")
    {:noreply, assign(socket, :redeem_amount, cleaned)}
  end

  def handle_event("toggle_show_all_winners", _params, socket) do
    {:noreply, assign(socket, :show_all_winners, !socket.assigns.show_all_winners)}
  end

  def handle_event("redeem_bux", _params, socket) do
    user = socket.assigns[:current_user]
    round = socket.assigns.current_round
    amount = parse_amount(socket.assigns.redeem_amount)
    wallet_address = socket.assigns[:wallet_address]

    cond do
      user == nil ->
        {:noreply, put_flash(socket, :error, "Connect your wallet to enter the airdrop")}

      !user.phone_verified ->
        {:noreply, put_flash(socket, :error, "Verify your phone number to enter the airdrop")}

      wallet_address == nil ->
        {:noreply, put_flash(socket, :error, "Connect your Solana wallet to enter")}

      round == nil || round.status != "open" ->
        {:noreply, put_flash(socket, :error, "Airdrop is not currently open")}

      amount <= 0 ->
        {:noreply, put_flash(socket, :error, "Enter a valid amount")}

      amount > socket.assigns.user_bux_balance ->
        {:noreply, put_flash(socket, :error, "Insufficient BUX balance")}

      true ->
        round_id = round.round_id
        user_id = user.id

        # Build unsigned deposit tx via settler → push to JS hook for wallet signing
        socket =
          start_async(socket, :build_deposit_tx, fn ->
            # Get deposit count for this user to determine entry_index
            entry_count = length(Airdrop.get_user_entries(user_id, round_id))
            BlocksterV2.BuxMinter.airdrop_build_deposit(wallet_address, round_id, entry_count, amount)
          end)

        {:noreply, assign(socket, redeeming: true)}
    end
  end

  def handle_event("airdrop_deposit_confirmed", %{"signature" => signature, "amount" => amount, "round_id" => round_id}, socket) do
    user = socket.assigns[:current_user]
    wallet_address = socket.assigns[:wallet_address]

    if user == nil do
      {:noreply, socket |> assign(redeeming: false) |> put_flash(:error, "Session expired")}
    else
      Logger.info("[Airdrop] Deposit confirmed: #{signature} for #{amount} BUX (user #{user.id})")

      socket =
        start_async(socket, :redeem_bux, fn ->
          Airdrop.redeem_bux(user, amount, round_id, deposit_tx: signature)
        end)

      # Sync on-chain balances in background
      if wallet_address do
        BlocksterV2.BuxMinter.sync_user_balances_async(user.id, wallet_address, force: true)
      end

      {:noreply, socket}
    end
  end

  def handle_event("airdrop_deposit_error", %{"error" => error}, socket) do
    Logger.error("[Airdrop] Deposit failed: #{error}")
    {:noreply, socket |> assign(redeeming: false) |> put_flash(:error, error)}
  end

  def handle_event("claim_prize", %{"winner-index" => index_str}, socket) do
    _user = socket.assigns.current_user
    round_id = socket.assigns.current_round.round_id
    winner_index = String.to_integer(index_str)
    wallet_address = socket.assigns[:wallet_address]

    if wallet_address == nil do
      {:noreply, put_flash(socket, :error, "Connect your Solana wallet to claim")}
    else
      # Build unsigned claim tx via settler → push to JS hook for wallet signing
      socket =
        start_async(socket, :build_claim_tx, fn ->
          BlocksterV2.BuxMinter.airdrop_build_claim(wallet_address, round_id, winner_index)
        end)

      {:noreply, assign(socket, claiming_index: winner_index)}
    end
  end

  def handle_event("airdrop_claim_confirmed", %{"signature" => signature, "winner_index" => winner_index_str}, socket) do
    user = socket.assigns.current_user
    round_id = socket.assigns.current_round.round_id
    winner_index = if is_binary(winner_index_str), do: String.to_integer(winner_index_str), else: winner_index_str
    wallet_address = socket.assigns[:wallet_address] || ""

    socket =
      start_async(socket, :claim_prize, fn ->
        Airdrop.claim_prize(user.id, round_id, winner_index, signature, wallet_address)
      end)

    {:noreply, socket}
  end

  def handle_event("airdrop_claim_error", %{"error" => error}, socket) do
    Logger.error("[Airdrop] Claim failed: #{error}")
    {:noreply, socket |> assign(claiming_index: nil) |> put_flash(:error, error)}
  end

  def handle_event("show_fairness_modal", _params, socket) do
    {:noreply, assign(socket, show_fairness_modal: true)}
  end

  def handle_event("close_fairness_modal", _params, socket) do
    {:noreply, assign(socket, show_fairness_modal: false)}
  end

  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  # ============================================================
  # Async Handlers
  # ============================================================

  @impl true
  def handle_async(:build_deposit_tx, {:ok, {:ok, %{"transaction" => tx_base64}}}, socket) do
    amount = parse_amount(socket.assigns.redeem_amount)
    round_id = socket.assigns.current_round.round_id

    {:noreply,
     socket
     |> push_event("sign_airdrop_deposit", %{
       transaction: tx_base64,
       amount: amount,
       round_id: round_id
     })}
  end

  def handle_async(:build_deposit_tx, {:ok, {:error, reason}}, socket) do
    Logger.error("[Airdrop] Build deposit tx failed: #{inspect(reason)}")
    {:noreply, socket |> assign(redeeming: false) |> put_flash(:error, "Failed to build deposit transaction")}
  end

  def handle_async(:build_deposit_tx, {:exit, _reason}, socket) do
    {:noreply, socket |> assign(redeeming: false) |> put_flash(:error, "Deposit failed unexpectedly")}
  end

  def handle_async(:build_claim_tx, {:ok, {:ok, %{"transaction" => tx_base64}}}, socket) do
    winner_index = socket.assigns.claiming_index
    round_id = socket.assigns.current_round.round_id

    {:noreply,
     socket
     |> push_event("sign_airdrop_claim", %{
       transaction: tx_base64,
       round_id: round_id,
       winner_index: winner_index
     })}
  end

  def handle_async(:build_claim_tx, {:ok, {:error, reason}}, socket) do
    Logger.error("[Airdrop] Build claim tx failed: #{inspect(reason)}")
    {:noreply, socket |> assign(claiming_index: nil) |> put_flash(:error, "Failed to build claim transaction")}
  end

  def handle_async(:build_claim_tx, {:exit, _reason}, socket) do
    {:noreply, socket |> assign(claiming_index: nil) |> put_flash(:error, "Claim failed unexpectedly")}
  end

  def handle_async(:redeem_bux, {:ok, {:ok, entry}}, socket) do
    amount = entry.amount
    round_id = entry.round_id
    new_balance = max(socket.assigns.user_bux_balance - amount, 0)
    updated_entries = [entry | socket.assigns.user_entries]
    new_total = socket.assigns.total_entries + amount
    was_first_entry = socket.assigns.user_entries == []
    new_participants = socket.assigns.participant_count + if(was_first_entry, do: 1, else: 0)

    Phoenix.PubSub.broadcast_from(
      BlocksterV2.PubSub,
      self(),
      "airdrop:#{round_id}",
      {:airdrop_deposit, round_id, new_total, new_participants}
    )

    {:noreply,
     socket
     |> assign(
       user_bux_balance: new_balance,
       user_entries: updated_entries,
       total_entries: new_total,
       participant_count: new_participants,
       redeeming: false,
       redeem_amount: ""
     )
     |> put_flash(:info, "Successfully redeemed #{Number.Delimit.number_to_delimited(amount, precision: 0)} BUX!")}
  end

  def handle_async(:redeem_bux, {:ok, {:error, reason}}, socket) do
    message =
      case reason do
        :phone_not_verified -> "Phone verification required"
        :invalid_amount -> "Invalid amount"
        :insufficient_balance -> "Insufficient BUX balance"
        {:round_not_open, _} -> "Airdrop is not currently open"
        :round_not_found -> "No active airdrop round"
        {:deposit_failed, _} -> "On-chain BUX deposit failed — try again"
        _ -> "Redemption failed"
      end

    {:noreply, socket |> assign(redeeming: false) |> put_flash(:error, message)}
  end

  def handle_async(:redeem_bux, {:exit, _reason}, socket) do
    {:noreply, socket |> assign(redeeming: false) |> put_flash(:error, "Redemption failed unexpectedly")}
  end

  def handle_async(:claim_prize, {:ok, {:ok, updated_winner}}, socket) do
    winners =
      Enum.map(socket.assigns.winners, fn w ->
        if w.winner_index == updated_winner.winner_index, do: updated_winner, else: w
      end)

    entry_results = compute_entry_results(socket.assigns.user_entries, winners)

    {:noreply,
     socket
     |> assign(winners: winners, entry_results: entry_results, claiming_index: nil)
     |> put_flash(:info, "Prize claimed successfully!")}
  end

  def handle_async(:claim_prize, {:ok, {:error, reason}}, socket) do
    message =
      case reason do
        :already_claimed -> "Prize already claimed"
        :not_your_prize -> "This prize doesn't belong to you"
        :winner_not_found -> "Winner not found"
        :claim_tx_failed -> "Prize claim failed — try again"
        _ -> "Claim failed"
      end

    {:noreply, socket |> assign(claiming_index: nil) |> put_flash(:error, message)}
  end

  def handle_async(:claim_prize, {:exit, _reason}, socket) do
    {:noreply, socket |> assign(claiming_index: nil) |> put_flash(:error, "Claim failed unexpectedly")}
  end

  # ============================================================
  # Info Handlers
  # ============================================================

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :time_remaining, calculate_time_remaining(socket.assigns.airdrop_end_time))}
  end

  def handle_info({:airdrop_deposit, _round_id, total_entries, participant_count}, socket) do
    {:noreply, assign(socket, total_entries: total_entries, participant_count: participant_count)}
  end

  def handle_info({:airdrop_drawn, round_id, winners}, socket) do
    entry_results = compute_entry_results(socket.assigns.user_entries, winners)

    verification_data =
      case Airdrop.get_verification_data(round_id) do
        {:ok, data} -> data
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(airdrop_drawn: true, winners: winners, entry_results: entry_results, verification_data: verification_data)
     |> put_flash(:info, "The airdrop has been drawn! Winners revealing...")}
  end

  def handle_info({:airdrop_winner_revealed, _round_id, winner}, socket) do
    existing = socket.assigns.winners
    idx = Enum.find_index(existing, &(&1.winner_index == winner.winner_index))

    winners =
      if idx do
        # Update existing winner (e.g., prize_registered changed)
        List.replace_at(existing, idx, winner)
      else
        existing ++ [winner]
      end

    entry_results = compute_entry_results(socket.assigns.user_entries, winners)
    {:noreply, assign(socket, winners: winners, entry_results: entry_results)}
  end

  # ============================================================
  # Render
  # ============================================================

  @impl true
  def render(assigns) do
    parsed_amount = parse_amount(assigns.redeem_amount)
    round_open = assigns.current_round != nil && assigns.current_round.status == "open"
    round_label = round_status_label(assigns)

    can_redeem =
      assigns.current_user != nil &&
        assigns.current_user.phone_verified == true &&
        assigns.wallet_connected &&
        parsed_amount > 0 &&
        parsed_amount <= assigns.user_bux_balance &&
        round_open &&
        !assigns.redeeming

    pool_share_pct = compute_pool_share(parsed_amount, assigns.total_entries)
    odds_text = compute_odds_text(parsed_amount, assigns.total_entries)
    expected_value_dollars = compute_expected_value(parsed_amount, assigns.total_entries, assigns.prize_summary.total)
    position_start = assigns.total_entries + 1
    position_end = assigns.total_entries + max(parsed_amount, 1)

    visible_winners =
      if assigns.show_all_winners or length(assigns.winners) <= @winners_collapsed_count do
        assigns.winners
      else
        Enum.take(assigns.winners, @winners_collapsed_count)
      end

    user_winning_results =
      if assigns.airdrop_drawn do
        assigns.entry_results
        |> Map.values()
        |> List.flatten()
      else
        []
      end

    assigns =
      assigns
      |> assign(:parsed_amount, parsed_amount)
      |> assign(:round_open, round_open)
      |> assign(:round_label, round_label)
      |> assign(:can_redeem, can_redeem)
      |> assign(:pool_share_pct, pool_share_pct)
      |> assign(:odds_text, odds_text)
      |> assign(:expected_value_dollars, expected_value_dollars)
      |> assign(:position_start, position_start)
      |> assign(:position_end, position_end)
      |> assign(:quick_chips, @quick_chips)
      |> assign(:visible_winners, visible_winners)
      |> assign(:winners_collapsed_count, @winners_collapsed_count)
      |> assign(:user_winning_results, user_winning_results)

    ~H"""
    <div class="min-h-screen bg-[#fafaf9]">
      <DesignSystem.header
        current_user={@current_user}
        active="airdrop"
        bux_balance={Map.get(assigns, :bux_balance, 0)}
        token_balances={Map.get(assigns, :token_balances, %{})}
        cart_item_count={Map.get(assigns, :cart_item_count, 0)}
        unread_notification_count={Map.get(assigns, :unread_notification_count, 0)}
        notification_dropdown_open={Map.get(assigns, :notification_dropdown_open, false)}
        recent_notifications={Map.get(assigns, :recent_notifications, [])}
        search_query={Map.get(assigns, :search_query, "")}
        search_results={Map.get(assigns, :search_results, [])}
        show_search_results={Map.get(assigns, :show_search_results, false)}
        connecting={Map.get(assigns, :connecting, false)}
        show_why_earn_bux={true}
      />

      <%!-- AirdropSolanaHook mount point — preserved exactly --%>
      <div id="airdrop-solana-hook" phx-hook="AirdropSolanaHook" class="hidden"></div>

      <main class="max-w-[1280px] mx-auto px-6">
        <.airdrop_page_hero {assigns} />

        <%= if @airdrop_drawn do %>
          <.drawn_state_section {assigns} />
        <% else %>
          <.open_state_section {assigns} />
        <% end %>

        <.how_it_works_section />
      </main>

      <DesignSystem.footer />
    </div>

    <%= if @show_fairness_modal && @verification_data do %>
      <.fairness_modal {assigns} />
    <% end %>
    """
  end

  # ============================================================
  # Function Components — page sections
  # ============================================================

  defp airdrop_page_hero(assigns) do
    headline_lines =
      if assigns.airdrop_drawn do
        ["The airdrop", "has been drawn"]
      else
        ["$#{format_prize_usd(assigns.prize_summary.total)}", "up for grabs"]
      end

    description =
      if assigns.airdrop_drawn do
        "Round #{round_number_or_dash(assigns.current_round)} has settled. Top 33 winners revealed below — provably fair, fully verifiable on chain."
      else
        "Redeem the BUX you earned reading. 1 BUX = 1 entry. 33 winners drawn on chain when the countdown hits zero. Provably fair, settled on Solana."
      end

    assigns =
      assigns
      |> assign(:headline_lines, headline_lines)
      |> assign(:description, description)

    ~H"""
    <section class="pt-12 pb-10">
      <div class="grid grid-cols-12 gap-8 items-end">
        <div class="col-span-12 md:col-span-7">
          <div class="flex items-center gap-2 mb-3">
            <span class="text-[10px] font-bold tracking-[0.16em] uppercase text-neutral-400">
              {@round_label}
            </span>
            <%= if @round_open do %>
              <span class="inline-flex items-center gap-1 bg-[#22C55E]/[0.12] text-[#15803d] border border-[#22C55E]/30 px-2 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider">
                <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E] animate-pulse"></span>
                Live
              </span>
            <% end %>
          </div>
          <h1 class="font-bold text-[60px] md:text-[80px] mb-3 leading-[0.96] tracking-[-0.022em] text-[#141414]">
            <%= for {line, idx} <- Enum.with_index(@headline_lines) do %>
              <%= if idx > 0 do %><br /><% end %>{line}
            <% end %>
          </h1>
          <p class="text-[16px] leading-[1.5] text-neutral-600 max-w-[560px]">
            {@description}
          </p>
        </div>
        <div class="col-span-12 md:col-span-5">
          <div class="grid grid-cols-3 gap-3">
            <.hero_stat label="Total pool" value={"$" <> format_prize_usd(@prize_summary.total)} sub="USDC + SOL" />
            <.hero_stat label="Winners" value="33" sub="drawn at close" />
            <.hero_stat label="Rate" value="1:1" sub="BUX → entry" />
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :sub, :string, default: nil

  defp hero_stat(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-neutral-200/70 p-4 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
      <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-neutral-400 mb-2">{@label}</div>
      <div class="font-mono font-bold text-[26px] text-[#141414] leading-none tabular-nums">{@value}</div>
      <%= if @sub do %>
        <div class="text-[10px] text-neutral-500 mt-1.5">{@sub}</div>
      <% end %>
    </div>
    """
  end

  defp open_state_section(assigns) do
    ~H"""
    <section class="py-10 border-t border-neutral-200/70">
      <div class="grid grid-cols-12 gap-8">
        <div class="col-span-12 md:col-span-7 space-y-6">
          <.countdown_card {assigns} />
          <.prize_distribution_card {assigns} />
          <.pool_stats_card {assigns} />
          <%= if @current_round && Map.get(@current_round, :commitment_hash) do %>
            <.commitment_card current_round={@current_round} />
          <% end %>
        </div>

        <div class="col-span-12 md:col-span-5">
          <div class="lg:sticky lg:top-[100px] self-start">
            <.entry_form_card {assigns} />
            <%= if @user_entries != [] do %>
              <div class="mt-5 space-y-3">
                <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold px-2">
                  Your entries · {length(@user_entries)} {if length(@user_entries) == 1, do: "redemption", else: "redemptions"}
                </div>
                <%= for entry <- @user_entries do %>
                  <.receipt_panel
                    entry={entry}
                    entry_results={@entry_results}
                    airdrop_drawn={@airdrop_drawn}
                    current_user={@current_user}
                    wallet_connected={@wallet_connected}
                    claiming_index={@claiming_index}
                  />
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp countdown_card(assigns) do
    end_time_str =
      if assigns.current_round do
        Calendar.strftime(assigns.current_round.end_time, "%B %-d · %H:%M UTC")
      else
        "May 1 · 17:00 UTC"
      end

    round_number = round_number_or_dash(assigns.current_round)
    assigns = assigns |> assign(:end_time_str, end_time_str) |> assign(:round_number, round_number)

    ~H"""
    <div class="bg-white rounded-2xl border border-neutral-200/70 p-7 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
      <div class="flex items-baseline justify-between mb-5">
        <div>
          <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-neutral-400 mb-1">
            <%= if @airdrop_drawn, do: "Drawing complete", else: "Drawing on" %>
          </div>
          <h2 class="font-bold text-[18px] text-[#141414] tracking-tight">{@end_time_str}</h2>
        </div>
        <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold">
          <svg class="w-3 h-3 inline-block mr-1 -mt-0.5 text-neutral-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="10" />
            <polyline points="12 6 12 12 16 14" />
          </svg>
          Round {@round_number}
        </div>
      </div>

      <div class="grid grid-cols-4 gap-3">
        <.countdown_box value={@time_remaining.days} label="Days" />
        <.countdown_box value={@time_remaining.hours} label="Hours" />
        <.countdown_box value={@time_remaining.minutes} label="Min" />
        <.countdown_box value={@time_remaining.seconds} label="Sec" />
      </div>
    </div>
    """
  end

  attr :value, :integer, required: true
  attr :label, :string, required: true

  defp countdown_box(assigns) do
    ~H"""
    <div class="bg-neutral-50 border border-neutral-200/70 rounded-2xl p-4 text-center">
      <div class="font-mono font-bold text-[40px] text-[#141414] leading-none tracking-tight tabular-nums">
        {String.pad_leading(to_string(@value), 2, "0")}
      </div>
      <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold mt-2">{@label}</div>
    </div>
    """
  end

  defp prize_distribution_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-neutral-200/70 p-7 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
      <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-neutral-400 mb-1">Prize distribution</div>
      <h2 class="font-bold text-[20px] text-[#141414] tracking-tight mb-5">
        33 winners · ${format_prize_usd(@prize_summary.total)} total
      </h2>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div class="bg-gradient-to-br from-[#fffbeb] to-[#fef3c7] border border-[#facc15]/40 rounded-2xl p-5 text-center">
          <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-[#a16207] mb-2">1st place</div>
          <div class="font-mono font-bold text-[28px] text-[#141414] leading-none">${format_prize_usd(@prize_summary.first)}</div>
          <div class="text-[10px] text-neutral-500 mt-1.5">1 winner</div>
        </div>
        <div class="bg-gradient-to-br from-neutral-50 to-neutral-100 border border-neutral-200 rounded-2xl p-5 text-center">
          <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-2">2nd place</div>
          <div class="font-mono font-bold text-[28px] text-[#141414] leading-none">${format_prize_usd(@prize_summary.second)}</div>
          <div class="text-[10px] text-neutral-500 mt-1.5">1 winner</div>
        </div>
        <div class="bg-gradient-to-br from-orange-50 to-amber-50 border border-orange-200 rounded-2xl p-5 text-center">
          <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-orange-700 mb-2">3rd place</div>
          <div class="font-mono font-bold text-[28px] text-[#141414] leading-none">${format_prize_usd(@prize_summary.third)}</div>
          <div class="text-[10px] text-neutral-500 mt-1.5">1 winner</div>
        </div>
        <div class="bg-[#CAFC00]/[0.12] border border-[#CAFC00]/40 rounded-2xl p-5 text-center">
          <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-[#141414] mb-2">4th–33rd</div>
          <div class="font-mono font-bold text-[28px] text-[#141414] leading-none">${format_prize_usd(@prize_summary.rest)}</div>
          <div class="text-[10px] text-neutral-500 mt-1.5">×{@prize_summary.rest_count} winners</div>
        </div>
      </div>
    </div>
    """
  end

  defp pool_stats_card(assigns) do
    avg_entry =
      if assigns.participant_count > 0 do
        div(assigns.total_entries, assigns.participant_count)
      else
        0
      end

    assigns = assign(assigns, :avg_entry, avg_entry)

    ~H"""
    <div class="bg-white rounded-2xl border border-neutral-200/70 p-7 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
      <div class="grid grid-cols-3 gap-6">
        <div>
          <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-neutral-400 mb-2">Total deposited</div>
          <div class="font-mono font-bold text-[32px] text-[#141414] leading-none tabular-nums">
            {Number.Delimit.number_to_delimited(@total_entries, precision: 0)}
          </div>
          <div class="text-[10px] text-neutral-500 mt-1.5">BUX entries in pool</div>
        </div>
        <div>
          <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-neutral-400 mb-2">Participants</div>
          <div class="font-mono font-bold text-[32px] text-[#141414] leading-none tabular-nums">
            {Number.Delimit.number_to_delimited(@participant_count, precision: 0)}
          </div>
          <div class="text-[10px] text-neutral-500 mt-1.5">{if @participant_count == 1, do: "reader entered", else: "readers entered"}</div>
        </div>
        <div>
          <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-neutral-400 mb-2">Avg entry</div>
          <div class="font-mono font-bold text-[32px] text-[#141414] leading-none tabular-nums">
            {Number.Delimit.number_to_delimited(@avg_entry, precision: 0)}
          </div>
          <div class="text-[10px] text-neutral-500 mt-1.5">BUX per player</div>
        </div>
      </div>
    </div>
    """
  end

  attr :current_round, :map, required: true

  defp commitment_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-neutral-200/70 p-6 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
      <div class="flex items-center gap-3 mb-4">
        <div class="w-9 h-9 rounded-xl bg-[#CAFC00]/[0.15] border border-[#CAFC00]/40 grid place-items-center">
          <svg class="w-5 h-5 text-[#141414]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
          </svg>
        </div>
        <div>
          <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold">Provably fair commitment</div>
          <div class="text-[13px] font-bold text-[#141414]">SHA-256 published before round opened</div>
        </div>
      </div>
      <div class="bg-neutral-50 border border-neutral-200 rounded-xl p-3">
        <div class="text-[9px] text-neutral-500 font-bold uppercase tracking-[0.14em] mb-1">Commitment hash</div>
        <div class="font-mono text-[11px] text-[#141414] break-all">{@current_round.commitment_hash}</div>
      </div>
      <div class="mt-3 text-[11px] text-neutral-500 leading-relaxed">
        The server seed is locked in on chain. Slot at close + revealed seed determines all 33 winners. Anyone can re-run the algorithm.
      </div>
    </div>
    """
  end

  defp entry_form_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
      <%!-- Dark header strip --%>
      <div class="bg-[#0a0a0a] text-white px-6 py-4 flex items-center justify-between">
        <div>
          <div class="text-[10px] uppercase tracking-[0.14em] text-white/60 font-bold">Enter the airdrop</div>
          <div class="text-[15px] font-bold mt-0.5">Redeem BUX → get entries</div>
        </div>
        <div class="w-9 h-9 rounded-xl bg-[#CAFC00] grid place-items-center">
          <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-5 h-5 rounded-full" />
        </div>
      </div>

      <div class="p-6">
        <%= if @round_open do %>
          <%!-- Balance display --%>
          <div class="flex items-center justify-between mb-5 p-3 bg-neutral-50 border border-neutral-200 rounded-xl">
            <span class="text-[12px] text-neutral-600">Your BUX balance</span>
            <span class="font-mono font-bold text-[14px] text-[#141414]">
              <%= if @current_user do %>
                {Number.Delimit.number_to_delimited(@user_bux_balance, precision: 0)} BUX
              <% else %>
                <span class="text-neutral-400 font-normal text-[12px]">Connect wallet to view</span>
              <% end %>
            </span>
          </div>

          <%!-- Amount input --%>
          <div class="mb-2">
            <label class="text-[11px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-2 block">BUX to redeem</label>
            <div class="relative">
              <input
                type="text"
                inputmode="numeric"
                value={@redeem_amount}
                phx-keyup="update_redeem_amount"
                placeholder="0"
                class="w-full bg-white border border-neutral-200 rounded-xl pl-4 pr-16 py-3 text-[20px] font-mono font-bold text-[#141414] focus:outline-none focus:border-[#141414]"
                disabled={@current_user == nil}
              />
              <button
                type="button"
                phx-click="set_max"
                class="absolute right-2 top-1/2 -translate-y-1/2 px-3 py-1 bg-neutral-900 text-[#CAFC00] rounded-full text-[10px] font-mono font-bold hover:bg-neutral-800 transition-colors cursor-pointer disabled:opacity-50"
                disabled={@current_user == nil}
              >
                MAX
              </button>
            </div>
            <div class="mt-2 flex items-center justify-between text-[11px]">
              <span class="text-neutral-500">
                <%= if @parsed_amount > 0 do %>
                  = <span class="font-mono font-bold text-[#141414]">{Number.Delimit.number_to_delimited(@parsed_amount, precision: 0)}</span> entries
                <% else %>
                  Enter amount above
                <% end %>
              </span>
              <%= if @parsed_amount > 0 do %>
                <span class="text-neutral-500">
                  Position <span class="font-mono">#{Number.Delimit.number_to_delimited(@position_start, precision: 0)}</span>
                  – <span class="font-mono">#{Number.Delimit.number_to_delimited(@position_end, precision: 0)}</span>
                </span>
              <% end %>
            </div>
          </div>

          <%!-- Quick amount chips --%>
          <div class="grid grid-cols-4 gap-2 mt-4 mb-6">
            <%= for chip <- @quick_chips do %>
              <% active = @parsed_amount == chip %>
              <% chip_class = if active, do: "px-2 py-2 bg-white border border-[#141414] rounded-full text-[11px] font-mono font-bold text-[#141414] cursor-pointer", else: "px-2 py-2 bg-white border border-neutral-200 hover:border-[#141414] rounded-full text-[11px] font-mono text-neutral-600 hover:text-[#141414] transition-colors cursor-pointer disabled:opacity-50" %>
              <button
                type="button"
                phx-click="set_amount"
                phx-value-value={chip}
                class={chip_class}
                disabled={@current_user == nil}
              >
                {Number.Delimit.number_to_delimited(chip, precision: 0)}
              </button>
            <% end %>
          </div>

          <%!-- Odds preview --%>
          <div class="bg-neutral-50 border border-neutral-200 rounded-xl p-4 mb-5 space-y-2">
            <div class="flex items-center justify-between text-[11px]">
              <span class="text-neutral-500">Your share of pool</span>
              <span class="font-mono font-bold text-[#141414]">{@pool_share_pct}</span>
            </div>
            <div class="flex items-center justify-between text-[11px]">
              <span class="text-neutral-500">Odds (any prize)</span>
              <span class="font-mono font-bold text-[#141414]">{@odds_text}</span>
            </div>
            <div class="flex items-center justify-between text-[11px]">
              <span class="text-neutral-500">Expected value</span>
              <span class="font-mono font-bold text-[#15803d]">{@expected_value_dollars}</span>
            </div>
          </div>

          <%!-- Submit --%>
          <% submit_class = if @can_redeem, do: "w-full inline-flex items-center justify-center gap-2 bg-[#0a0a0a] text-white px-5 py-3.5 rounded-full text-[14px] font-bold hover:bg-[#1a1a22] transition-colors cursor-pointer", else: "w-full inline-flex items-center justify-center gap-2 bg-neutral-200 text-neutral-400 px-5 py-3.5 rounded-full text-[14px] font-bold cursor-not-allowed" %>
          <button
            type="button"
            phx-click="redeem_bux"
            disabled={!@can_redeem}
            class={submit_class}
          >
            <%= cond do %>
              <% @redeeming -> %>
                Redeeming...
              <% @current_user == nil -> %>
                Connect Wallet to Enter
              <% @current_user.phone_verified != true -> %>
                Verify Phone to Enter
              <% !@wallet_connected -> %>
                Connect Wallet to Enter
              <% @parsed_amount == 0 -> %>
                Enter Amount
              <% @parsed_amount > @user_bux_balance -> %>
                Insufficient Balance
              <% true -> %>
                Redeem {Number.Delimit.number_to_delimited(@parsed_amount, precision: 0)} BUX
            <% end %>
          </button>

          <%= if @current_user && @current_user.phone_verified && @wallet_connected do %>
            <div class="mt-4 flex items-center justify-center gap-2 text-[10px] text-neutral-400">
              <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
              </svg>
              Phone verified · Solana wallet connected
            </div>
          <% end %>
        <% else %>
          <div class="text-center py-6">
            <p class="text-neutral-500 text-sm font-bold">
              <%= if @current_round && @current_round.status == "closed" do %>
                Entries closed — drawing winners...
              <% else %>
                Airdrop opening soon
              <% end %>
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp drawn_state_section(assigns) do
    top_three = Enum.take(assigns.winners, 3)

    has_loser_entries =
      assigns.user_entries != [] and
        Enum.all?(assigns.user_entries, fn e ->
          Map.get(assigns.entry_results, e.id, []) == []
        end)

    assigns =
      assigns
      |> assign(:top_three, top_three)
      |> assign(:has_winning_receipt, assigns.user_winning_results != [])
      |> assign(:has_loser_entries, has_loser_entries)

    ~H"""
    <section class="py-10 border-t border-neutral-200/70">
      <%!-- Mono divider --%>
      <div class="text-center mb-10">
        <span class="font-mono text-[11px] tracking-[0.16em] uppercase text-neutral-400">
          Drawn state · winners revealed ↓
        </span>
      </div>

      <%!-- Dark celebration banner --%>
      <div class="rounded-2xl overflow-hidden bg-[#0a0a0a] text-white relative mb-6">
        <div class="absolute inset-0">
          <div class="absolute top-0 right-0 w-[60%] h-full bg-gradient-to-l from-[#CAFC00]/[0.12] to-transparent"></div>
          <div class="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-white/15 to-transparent"></div>
          <div class="absolute inset-0 bg-[radial-gradient(circle_at_30%_30%,rgba(255,255,255,0.04)_1.5px,transparent_1.5px)]" style="background-size: 32px 32px;"></div>
        </div>
        <div class="relative px-10 py-12 text-center">
          <div class="text-[10px] font-bold uppercase tracking-[0.16em] text-[#CAFC00] mb-3">
            Round {round_number_or_dash(@current_round)} · drawn
          </div>
          <h2 class="font-bold tracking-[-0.022em] leading-[0.96] text-white text-[44px] md:text-[56px] mb-3">
            The airdrop has been drawn
          </h2>
          <p class="text-white/60 text-[14px] max-w-[460px] mx-auto">
            Congratulations to all 33 winners. The provably-fair algorithm is publicly verifiable.
          </p>
          <div class="mt-6 flex items-center justify-center gap-3 flex-wrap">
            <button
              type="button"
              phx-click="show_fairness_modal"
              class="inline-flex items-center gap-2 bg-[#CAFC00] text-black px-4 py-2.5 rounded-full text-[12px] font-bold hover:bg-white transition-colors cursor-pointer"
            >
              <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M9 12l2 2 4-4" />
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
              </svg>
              Verify fairness
            </button>
            <a
              href={drawn_state_solscan_url(@verification_data)}
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-2 bg-white/10 ring-1 ring-white/20 backdrop-blur text-white px-4 py-2.5 rounded-full text-[12px] hover:bg-white/20 transition-colors cursor-pointer"
            >
              View on Solscan ↗
            </a>
          </div>
        </div>
      </div>

      <%!-- Top 3 podium --%>
      <%= if @top_three != [] do %>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <%= for winner <- @top_three do %>
            <% style = podium_style(winner.winner_index) %>
            <div class={"rounded-2xl p-6 text-center relative overflow-hidden border " <> style.bg <> " " <> style.border}>
              <div class={"absolute top-0 left-0 right-0 h-1 bg-gradient-to-r " <> style.bar}></div>
              <div class={"text-[10px] font-bold uppercase tracking-[0.14em] mb-2 mt-2 " <> style.label_color}>
                {ordinal(winner.winner_index + 1)} place
              </div>
              <div class="font-mono font-bold text-[44px] text-[#141414] leading-none mb-1">
                ${format_prize_usd(winner.prize_usd)}
              </div>
              <div class="text-[11px] text-neutral-500 font-mono">{truncate_address(winner.wallet_address)}</div>
              <div class={"mt-3 pt-3 border-t text-[10px] text-neutral-500 " <> style.divider}>
                Position <span class="font-mono">#{Number.Delimit.number_to_delimited(winner.random_number, precision: 0)}</span>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Verification metadata --%>
      <%= if @verification_data do %>
        <div class="bg-white rounded-2xl border border-neutral-200/70 p-6 shadow-[0_1px_3px_rgba(0,0,0,0.04)] mb-6">
          <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div>
              <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold mb-2">Slot at close</div>
              <div class="font-mono text-[14px] text-[#141414]">{@verification_data.slot_at_close}</div>
              <%= if @verification_data.close_tx do %>
                <a href={"https://solscan.io/tx/#{@verification_data.close_tx}?cluster=devnet"} target="_blank" rel="noopener" class="text-[10px] text-neutral-400 hover:text-[#141414] font-mono cursor-pointer">close tx ↗</a>
              <% end %>
            </div>
            <div>
              <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold mb-2">Server seed (revealed)</div>
              <div class="font-mono text-[12px] text-[#141414] break-all leading-relaxed">{@verification_data.server_seed}</div>
            </div>
            <div>
              <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold mb-2">SHA-256 verification</div>
              <div class="inline-flex items-center gap-1.5 bg-[#22C55E]/10 text-[#15803d] border border-[#22C55E]/25 px-2 py-1 rounded-full text-[10px] font-bold">
                <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                  <polyline points="20 6 9 17 4 12" />
                </svg>
                Matches commitment
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Full winners table --%>
      <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden mb-6">
        <div class="px-6 py-4 border-b border-neutral-100 flex items-center justify-between">
          <div>
            <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-neutral-400 mb-1">All 33 winners</div>
            <h3 class="font-bold text-[18px] text-[#141414] tracking-tight">Round {round_number_or_dash(@current_round)} results</h3>
          </div>
          <span class="text-[10px] font-mono text-neutral-400">
            {Number.Delimit.number_to_delimited(@total_entries, precision: 0)} BUX · {Number.Delimit.number_to_delimited(@participant_count, precision: 0)} players
          </span>
        </div>
        <div class="grid grid-cols-[60px_1fr_140px_140px_120px] px-6 py-3 bg-neutral-50/70 border-b border-neutral-100 text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold">
          <div>#</div>
          <div>Wallet</div>
          <div>Position</div>
          <div>Prize</div>
          <div class="text-right">Status</div>
        </div>
        <div class="divide-y divide-neutral-100">
          <%= for winner <- @visible_winners do %>
            <% row_bg = winners_row_bg(winner.winner_index) %>
            <div class={"px-6 py-3 transition-colors hover:bg-black/[0.02] " <> row_bg}>
              <div class="grid grid-cols-[60px_1fr_140px_140px_120px] items-center gap-3">
                <div class={"font-mono font-bold text-[13px] " <> winner_index_color(winner.winner_index)}>
                  {winner.winner_index + 1}
                </div>
                <div class="font-mono text-[12px] text-[#141414]">{truncate_address(winner.wallet_address)}</div>
                <div class="font-mono text-[11px] text-neutral-500">
                  #{Number.Delimit.number_to_delimited(winner.random_number, precision: 0)}
                </div>
                <div class="font-mono font-bold text-[13px] text-[#141414]">${format_prize_usd(winner.prize_usd)}</div>
                <div class="text-right">
                  <.winner_status
                    winner={winner}
                    current_user={@current_user}
                    wallet_connected={@wallet_connected}
                    claiming_index={@claiming_index}
                  />
                </div>
              </div>
            </div>
          <% end %>

          <%= if length(@winners) > @winners_collapsed_count do %>
            <div class="px-6 py-4 text-center">
              <button
                type="button"
                phx-click="toggle_show_all_winners"
                class="text-[12px] text-neutral-500 hover:text-[#141414] underline cursor-pointer"
              >
                <%= if @show_all_winners do %>
                  Show top {@winners_collapsed_count} only
                <% else %>
                  Show all {length(@winners)} winners
                <% end %>
              </button>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Your receipt — winning --%>
      <%= if @has_winning_receipt do %>
        <%= for win <- @user_winning_results do %>
          <div class="bg-gradient-to-br from-[#fffbeb] to-[#fef3c7] border border-[#facc15] rounded-2xl p-6 shadow-[0_1px_3px_rgba(250,204,21,0.15)] mb-3">
            <div class="flex items-start gap-4">
              <div class="w-12 h-12 rounded-xl bg-[#facc15] grid place-items-center shrink-0">
                <svg class="w-6 h-6 text-[#a16207]" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M12 2L15.09 8.26L22 9.27L17 14.14L18.18 21.02L12 17.77L5.82 21.02L7 14.14L2 9.27L8.91 8.26L12 2z" />
                </svg>
              </div>
              <div class="flex-1">
                <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-[#a16207] mb-1">
                  Your receipt
                </div>
                <h3 class="font-bold text-[20px] text-[#141414] tracking-tight mb-2">
                  Winner — {ordinal(win.winner_index + 1)} place · ${format_prize_usd(win.prize_usd)}
                </h3>
                <p class="text-[12px] text-neutral-700 mb-4">
                  Position <span class="font-mono font-bold">#{Number.Delimit.number_to_delimited(win.random_number, precision: 0)}</span> from your redemption fell into a winning slot.
                </p>
                <%= cond do %>
                  <% win.claimed -> %>
                    <span class="inline-flex items-center gap-1 text-[12px] font-bold text-[#15803d] bg-[#22C55E]/10 border border-[#22C55E]/25 px-3 py-1.5 rounded-full">
                      Claimed
                      <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                      </svg>
                    </span>
                  <% @current_user && @wallet_connected -> %>
                    <button
                      type="button"
                      phx-click="claim_prize"
                      phx-value-winner-index={win.winner_index}
                      disabled={@claiming_index == win.winner_index}
                      class="inline-flex items-center gap-2 bg-[#0a0a0a] text-white px-5 py-2.5 rounded-full text-[12px] font-bold hover:bg-[#1a1a22] transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      <%= if @claiming_index == win.winner_index, do: "Claiming...", else: "Claim $#{format_prize_usd(win.prize_usd)}" %>
                      <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="none">
                        <path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                      </svg>
                    </button>
                  <% true -> %>
                    <span class="text-[11px] text-neutral-500">Connect wallet to claim</span>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>

      <%= if @has_loser_entries do %>
        <div class="bg-white border border-neutral-200/70 rounded-2xl p-5">
          <div class="flex items-center justify-between">
            <div>
              <div class="text-[12px] text-neutral-600">
                Your other entries · {length(@user_entries)} {if length(@user_entries) == 1, do: "redemption", else: "redemptions"}
              </div>
              <div class="text-[10px] text-neutral-500 mt-0.5">No wins this round</div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Receipts list (your entries) --%>
      <%= if @user_entries != [] do %>
        <div class="mt-6 space-y-3">
          <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold px-2">
            Your entries · {length(@user_entries)} {if length(@user_entries) == 1, do: "redemption", else: "redemptions"}
          </div>
          <%= for entry <- @user_entries do %>
            <.receipt_panel
              entry={entry}
              entry_results={@entry_results}
              airdrop_drawn={@airdrop_drawn}
              current_user={@current_user}
              wallet_connected={@wallet_connected}
              claiming_index={@claiming_index}
            />
          <% end %>
        </div>
      <% end %>
    </section>
    """
  end

  defp how_it_works_section(assigns) do
    ~H"""
    <section class="py-12 border-t border-neutral-200/70">
      <div class="text-center mb-10">
        <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-neutral-400 mb-2">Provably fair · settled on chain</div>
        <h2 class="font-bold tracking-[-0.022em] text-[#141414] text-[36px] md:text-[44px]">How it works</h2>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-5">
        <.step_card number="1" title="Earn BUX reading" body="Read articles to earn BUX tokens. The more you engage, the more entries you can buy." />
        <.step_card number="2" title="Redeem · 1 BUX = 1 entry" body="Each BUX you redeem gets a sequential position in the entry pool. Redeem any amount, any time before the draw." />
        <.step_card number="3" title="33 winners drawn on chain" body="When the timer hits zero, the on-chain commit-reveal uses the next Solana slot to draw 33 winners. Prizes are claimed by signing a tx." />
      </div>
    </section>
    """
  end

  attr :number, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true

  defp step_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-neutral-200/70 p-7 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
      <div class="w-10 h-10 rounded-xl bg-[#CAFC00] grid place-items-center mb-5">
        <span class="font-mono font-bold text-[16px] text-black">{@number}</span>
      </div>
      <h3 class="font-bold text-[18px] text-[#141414] mb-2 tracking-tight">{@title}</h3>
      <p class="text-[13px] text-neutral-600 leading-relaxed">{@body}</p>
    </div>
    """
  end

  # ============================================================
  # Function Components — winner status + receipts
  # ============================================================

  defp winner_status(assigns) do
    ~H"""
    <%= cond do %>
      <% @winner.claimed -> %>
        <span class="inline-flex items-center gap-1 bg-[#22C55E]/10 text-[#15803d] border border-[#22C55E]/25 px-2 py-0.5 rounded-full text-[9px] font-bold uppercase tracking-wider">
          <svg class="w-2.5 h-2.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="20 6 9 17 4 12" />
          </svg>
          Claimed
        </span>
        <%= if @winner.claim_tx && @winner.claim_tx != "pending" do %>
          <a href={"https://solscan.io/tx/#{@winner.claim_tx}?cluster=devnet"} target="_blank" rel="noopener" class="text-blue-500 hover:underline text-[10px] ml-1 font-mono cursor-pointer">↗</a>
        <% end %>
      <% @current_user && @winner.user_id == @current_user.id && @wallet_connected -> %>
        <button
          type="button"
          phx-click="claim_prize"
          phx-value-winner-index={@winner.winner_index}
          disabled={@claiming_index == @winner.winner_index}
          class="inline-flex items-center gap-1 bg-[#0a0a0a] text-white px-3 py-1 rounded-full text-[10px] font-bold hover:bg-[#1a1a22] transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <%= if @claiming_index == @winner.winner_index, do: "Claiming...", else: "Claim $#{format_prize_usd(@winner.prize_usd)}" %>
        </button>
      <% @current_user && @winner.user_id == @current_user.id -> %>
        <span class="text-[10px] text-neutral-400">Connect wallet</span>
      <% true -> %>
        <span class="text-[10px] text-neutral-400">—</span>
    <% end %>
    """
  end

  defp receipt_panel(assigns) do
    wins = Map.get(assigns.entry_results, assigns.entry.id, [])
    assigns = assign(assigns, wins: wins, has_wins: wins != [])

    ~H"""
    <% panel_class = if @has_wins && @airdrop_drawn, do: "bg-gradient-to-br from-[#fffbeb] to-[#fef3c7] border border-[#facc15] rounded-2xl p-4 shadow-[0_1px_3px_rgba(0,0,0,0.04)]", else: "bg-white rounded-2xl border border-neutral-200/70 p-4 shadow-[0_1px_3px_rgba(0,0,0,0.04)]" %>
    <div class={panel_class}>
      <%= if @has_wins && @airdrop_drawn do %>
        <%= for win <- @wins do %>
          <div class="flex items-center gap-2 mb-2">
            <svg class="w-4 h-4 text-[#a16207] shrink-0" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 2L15.09 8.26L22 9.27L17 14.14L18.18 21.02L12 17.77L5.82 21.02L7 14.14L2 9.27L8.91 8.26L12 2z" />
            </svg>
            <span class="text-[13px] font-bold text-[#141414]">
              Winner · {ordinal(win.winner_index + 1)} place · ${format_prize_usd(win.prize_usd)}
            </span>
          </div>
          <p class="text-[10px] text-neutral-500 mb-2">
            Winning position <span class="font-mono">#{Number.Delimit.number_to_delimited(win.random_number, precision: 0)}</span>
          </p>
        <% end %>
      <% else %>
        <%= if @airdrop_drawn do %>
          <div class="flex items-center gap-2 mb-2">
            <span class="text-[13px] text-neutral-500">
              Redeemed {Number.Delimit.number_to_delimited(@entry.amount, precision: 0)} BUX — no win
            </span>
          </div>
        <% else %>
          <div class="flex items-center gap-2 mb-2">
            <svg class="w-4 h-4 text-[#22C55E] shrink-0" viewBox="0 0 24 24" fill="currentColor">
              <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z" />
            </svg>
            <span class="text-[13px] font-bold text-[#141414]">
              Redeemed {Number.Delimit.number_to_delimited(@entry.amount, precision: 0)} BUX
            </span>
          </div>
        <% end %>
      <% end %>

      <div class="flex flex-wrap gap-x-3 gap-y-1 text-[10px] text-neutral-500">
        <span>Block <span class="font-mono">#{Number.Delimit.number_to_delimited(@entry.start_position, precision: 0)} – #{Number.Delimit.number_to_delimited(@entry.end_position, precision: 0)}</span></span>
        <span>·</span>
        <span>Entries: {Number.Delimit.number_to_delimited(@entry.amount, precision: 0)}</span>
        <span>·</span>
        <span>{format_datetime(@entry.inserted_at)}</span>
      </div>

      <%= if @entry.deposit_tx do %>
        <a href={"https://solscan.io/tx/#{@entry.deposit_tx}?cluster=devnet"} target="_blank" rel="noopener" class="mt-2 inline-block text-[10px] text-neutral-400 hover:text-[#141414] font-mono cursor-pointer">
          {String.slice(@entry.deposit_tx, 0, 4)}…{String.slice(@entry.deposit_tx, -4, 4)} ↗
        </a>
      <% end %>
    </div>
    """
  end

  # ============================================================
  # Fairness modal — preserved verbatim
  # ============================================================

  defp fairness_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/50 flex items-end sm:items-center justify-center z-50 p-0 sm:p-4" phx-click="close_fairness_modal" phx-window-keydown="close_fairness_modal" phx-key="Escape">
      <div class="bg-white rounded-none sm:rounded-2xl w-full sm:max-w-lg max-h-[100vh] sm:max-h-[90vh] overflow-y-auto shadow-xl" phx-click="stop_propagation">
        <%!-- Header --%>
        <div class="sticky top-0 bg-white border-b border-gray-200 p-3 sm:p-4 sm:rounded-t-2xl flex items-center justify-between z-10">
          <div class="flex items-center gap-2">
            <svg class="w-4 sm:w-5 h-4 sm:h-5 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
            </svg>
            <h2 class="text-base sm:text-lg font-bold text-gray-900">Provably Fair Verification</h2>
          </div>
          <button type="button" phx-click="close_fairness_modal" class="text-gray-400 hover:text-gray-600 cursor-pointer">
            <svg class="w-5 sm:w-6 h-5 sm:h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <%!-- Content --%>
        <div class="p-3 sm:p-4 space-y-3 sm:space-y-4">
          <%!-- Round Details --%>
          <div class="bg-blue-50 rounded-lg p-2 sm:p-3 border border-blue-200">
            <p class="text-xs sm:text-sm font-medium text-blue-800 mb-1 sm:mb-2">Round Details</p>
            <div class="grid grid-cols-2 gap-1 sm:gap-2 text-xs sm:text-sm">
              <div class="text-blue-600">Round ID:</div>
              <div class="font-mono text-[10px] sm:text-xs">{@verification_data.round_id}</div>
              <div class="text-blue-600">Total Entries:</div>
              <div class="text-xs sm:text-sm">{Number.Delimit.number_to_delimited(@verification_data.total_entries, precision: 0)}</div>
              <div class="text-blue-600">Winners:</div>
              <div class="text-xs sm:text-sm">33</div>
            </div>
          </div>

          <%!-- Step 1: Commitment --%>
          <div class="space-y-2">
            <div class="flex items-center gap-2">
              <div class="shrink-0 w-6 h-6 bg-gray-900 rounded-full flex items-center justify-center">
                <span class="text-white text-xs font-bold">1</span>
              </div>
              <h4 class="text-xs sm:text-sm font-medium text-gray-900">Commitment Published Before Round Opened</h4>
            </div>
            <p class="text-[10px] sm:text-xs text-gray-500 ml-8">
              Before anyone could enter, we generated a secret server seed and published its SHA-256 hash on-chain. This commitment cannot be changed after the fact.
            </p>
            <div class="ml-8">
              <label class="text-[10px] sm:text-xs font-medium text-gray-700">Commitment Hash (SHA-256 of Server Seed)</label>
              <%= if @verification_data.start_round_tx do %>
                <a href={"https://solscan.io/tx/#{@verification_data.start_round_tx}?cluster=devnet"} target="_blank" class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2 py-1.5 rounded break-all block overflow-x-auto text-blue-600 hover:underline cursor-pointer">
                  {@verification_data.commitment_hash}
                </a>
              <% else %>
                <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2 py-1.5 rounded break-all block overflow-x-auto">
                  {@verification_data.commitment_hash}
                </code>
              <% end %>
            </div>
          </div>

          <%!-- Step 2: Slot Captured --%>
          <div class="space-y-2">
            <div class="flex items-center gap-2">
              <div class="shrink-0 w-6 h-6 bg-gray-900 rounded-full flex items-center justify-center">
                <span class="text-white text-xs font-bold">2</span>
              </div>
              <h4 class="text-xs sm:text-sm font-medium text-gray-900">Airdrop Closed — Solana Slot Captured</h4>
            </div>
            <p class="text-[10px] sm:text-xs text-gray-500 ml-8">
              When the countdown expired, the Solana slot number at the time of close was captured on-chain as external randomness. Nobody — including us — could predict or control this value.
            </p>
            <div class="ml-8">
              <label class="text-[10px] sm:text-xs font-medium text-gray-700">Slot at Close</label>
              <%= if @verification_data.close_tx do %>
                <a href={"https://solscan.io/tx/#{@verification_data.close_tx}?cluster=devnet"} target="_blank" class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2 py-1.5 rounded break-all block overflow-x-auto text-blue-600 hover:underline cursor-pointer">
                  {@verification_data.slot_at_close}
                </a>
              <% else %>
                <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2 py-1.5 rounded break-all block overflow-x-auto">
                  {@verification_data.slot_at_close}
                </code>
              <% end %>
            </div>
          </div>

          <%!-- Step 3: Server Seed Revealed --%>
          <div class="space-y-2">
            <div class="flex items-center gap-2">
              <div class="shrink-0 w-6 h-6 bg-gray-900 rounded-full flex items-center justify-center">
                <span class="text-white text-xs font-bold">3</span>
              </div>
              <h4 class="text-xs sm:text-sm font-medium text-gray-900">Server Seed Revealed</h4>
            </div>
            <p class="text-[10px] sm:text-xs text-gray-500 ml-8">
              After the draw, our secret server seed is revealed. You can verify that SHA-256(server_seed) produces the exact commitment hash from Step 1.
            </p>
            <div class="ml-8 space-y-2">
              <div>
                <label class="text-[10px] sm:text-xs font-medium text-gray-700">Server Seed (revealed)</label>
                <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2 py-1.5 rounded break-all block overflow-x-auto">
                  {@verification_data.server_seed}
                </code>
              </div>
              <div class="flex items-center gap-2 bg-green-50 rounded-lg p-2 border border-green-200">
                <svg class="w-4 h-4 text-green-500 shrink-0" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                </svg>
                <p class="text-[10px] sm:text-xs text-green-700 font-medium">SHA-256(Server Seed) matches commitment hash from Step 1</p>
              </div>
            </div>
          </div>

          <%!-- Step 4: Winner Derivation Algorithm --%>
          <div class="space-y-2">
            <div class="flex items-center gap-2">
              <div class="shrink-0 w-6 h-6 bg-gray-900 rounded-full flex items-center justify-center">
                <span class="text-white text-xs font-bold">4</span>
              </div>
              <h4 class="text-xs sm:text-sm font-medium text-gray-900">Winner Derivation Algorithm</h4>
            </div>
            <p class="text-[10px] sm:text-xs text-gray-500 ml-8">
              Each winner position is derived deterministically from the combined seed. Anyone can re-run this exact algorithm to reproduce every winner.
            </p>
            <div class="ml-8 space-y-2">
              <div class="bg-green-50 rounded-lg p-2 sm:p-3 border border-green-200">
                <p class="text-[10px] sm:text-xs font-medium text-green-800 mb-1 sm:mb-2">Algorithm</p>
                <ol class="text-[10px] sm:text-xs text-green-700 space-y-0.5 sm:space-y-1 list-decimal ml-4">
                  <li>Combine seeds: <span class="font-mono">combined = SHA256(server_seed | slot_at_close)</span></li>
                  <li>For each winner i (0 to 32):</li>
                  <li class="ml-4"><span class="font-mono">hash = SHA256(combined, i)</span></li>
                  <li class="ml-4"><span class="font-mono">position = (hash mod {Number.Delimit.number_to_delimited(@verification_data.total_entries, precision: 0)}) + 1</span></li>
                  <li>Map position to the entry block that contains it → winner's wallet</li>
                </ol>
              </div>

              <div class="bg-gray-50 rounded-lg overflow-hidden">
                <table class="w-full text-xs">
                  <thead>
                    <tr class="border-b border-gray-200">
                      <th class="text-left p-2 text-gray-500 font-medium">#</th>
                      <th class="text-left p-2 text-gray-500 font-medium">Position</th>
                      <th class="text-left p-2 text-gray-500 font-medium">Winner</th>
                      <th class="text-left p-2 text-gray-500 font-medium">Prize</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for winner <- @winners do %>
                      <tr class="border-b border-gray-100 last:border-0">
                        <td class="p-2 text-gray-600">{winner.winner_index + 1}</td>
                        <td class="p-2 font-mono text-gray-700">#{Number.Delimit.number_to_delimited(winner.random_number, precision: 0)}</td>
                        <td class="p-2 font-mono text-gray-500">{truncate_address(winner.wallet_address)}</td>
                        <td class="p-2 text-gray-700">${format_prize_usd(winner.prize_usd)}</td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <%!-- Step 5: External Verification --%>
          <div class="border-t pt-3 sm:pt-4">
            <p class="text-xs sm:text-sm font-medium text-gray-700 mb-1 sm:mb-2">Verify Externally</p>
            <p class="text-[10px] sm:text-xs text-gray-500 mb-2 sm:mb-3">
              Click each link to independently verify using external tools:
            </p>
            <div class="space-y-2 sm:space-y-3">
              <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                <p class="text-[10px] sm:text-xs text-gray-600 mb-1">1. Verify server seed matches commitment</p>
                <a href={"https://md5calc.com/hash/sha256/#{@verification_data.server_seed}"} target="_blank" class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer">
                  SHA-256(server_seed) → Click to verify
                </a>
                <p class="text-[10px] sm:text-xs text-gray-400 mt-1 font-mono break-all">Expected: {@verification_data.commitment_hash}</p>
              </div>

              <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                <p class="text-[10px] sm:text-xs text-gray-600 mb-1">2. Verify combined seed (SHA-256)</p>
                <p class="text-[10px] sm:text-xs text-gray-400 mt-1 font-mono break-all">
                  SHA256({@verification_data.server_seed} | {@verification_data.slot_at_close})
                </p>
              </div>

              <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                <p class="text-[10px] sm:text-xs text-gray-600 mb-1">3. View on-chain program state</p>
                <a
                  href={"https://solscan.io/account/wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG?cluster=devnet"}
                  target="_blank"
                  class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer block"
                >
                  Airdrop Program on Solscan →
                </a>
              </div>
            </div>
          </div>
        </div>

        <%!-- Footer --%>
        <div class="p-4 border-t bg-gray-50 sm:rounded-b-2xl">
          <button type="button" phx-click="close_fairness_modal" class="w-full py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-all cursor-pointer">
            Close
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================
  # Helpers
  # ============================================================

  defp calculate_time_remaining(end_time) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    diff = max(end_time - now, 0)

    days = div(diff, 86400)
    remaining_after_days = rem(diff, 86400)
    hours = div(remaining_after_days, 3600)
    remaining_after_hours = rem(remaining_after_days, 3600)
    minutes = div(remaining_after_hours, 60)
    seconds = rem(remaining_after_hours, 60)

    %{days: days, hours: hours, minutes: minutes, seconds: seconds, total_seconds: diff}
  end

  defp parse_amount(""), do: 0
  defp parse_amount(nil), do: 0

  defp parse_amount(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> max(num, 0)
      :error -> 0
    end
  end

  defp parse_amount(n) when is_integer(n), do: max(n, 0)

  defp compute_entry_results(user_entries, winners) do
    for entry <- user_entries, into: %{} do
      matching_wins =
        Enum.filter(winners, fn w ->
          w.random_number >= entry.start_position and w.random_number <= entry.end_position
        end)

      {entry.id, matching_wins}
    end
  end

  defp truncate_address(nil), do: "—"
  defp truncate_address(addr) when byte_size(addr) < 10, do: addr
  defp truncate_address(addr), do: "#{String.slice(addr, 0, 6)}…#{String.slice(addr, -4, 4)}"

  defp format_prize_usd(cents) when is_integer(cents) do
    dollars = cents / 100
    if dollars == trunc(dollars) do
      Number.Delimit.number_to_delimited(trunc(dollars), precision: 0)
    else
      Number.Delimit.number_to_delimited(dollars, precision: 2)
    end
  end

  defp format_prize_usd(_), do: "0"

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y · %H:%M UTC")
  defp format_datetime(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y · %H:%M")

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n), do: "#{n}th"

  # Round status / numbering
  defp round_status_label(%{current_round: nil}), do: "Round — · Opening soon"

  defp round_status_label(%{current_round: round, airdrop_drawn: drawn}) do
    suffix =
      cond do
        drawn -> "Drawn"
        round.status == "open" -> "Open for entries"
        round.status == "closed" -> "Drawing winners"
        true -> "Opening soon"
      end

    "Round #{round.round_id} · #{suffix}"
  end

  defp round_number_or_dash(nil), do: "—"
  defp round_number_or_dash(round), do: "#{round.round_id}"

  # Pool share + odds + EV math
  defp compute_pool_share(0, _), do: "—"
  defp compute_pool_share(_, total) when total < 0, do: "—"

  defp compute_pool_share(amount, total) do
    pct = amount / (total + amount) * 100
    "#{:erlang.float_to_binary(pct, decimals: 2)}%"
  end

  defp compute_odds_text(0, _), do: "—"

  defp compute_odds_text(amount, total) do
    pool = total + amount
    odds = 33 * amount / max(pool, 1)
    cond do
      odds <= 0 -> "—"
      odds >= 1 -> "Guaranteed"
      true ->
        denom = round(1 / odds)
        "~1 in #{Number.Delimit.number_to_delimited(denom, precision: 0)}"
    end
  end

  defp compute_expected_value(0, _, _), do: "—"

  defp compute_expected_value(amount, total, prize_total_cents) do
    pool = total + amount
    share = amount / max(pool, 1)
    expected_dollars = share * (prize_total_cents / 100)
    "~$#{:erlang.float_to_binary(expected_dollars, decimals: 2)}"
  end

  # Drawn-state Solscan helpers
  defp drawn_state_solscan_url(nil), do: "https://solscan.io/account/wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG?cluster=devnet"

  defp drawn_state_solscan_url(%{draw_tx: tx}) when is_binary(tx) and tx != "" do
    "https://solscan.io/tx/#{tx}?cluster=devnet"
  end

  defp drawn_state_solscan_url(_), do: "https://solscan.io/account/wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG?cluster=devnet"

  # Podium card styles
  defp podium_style(0) do
    %{
      bg: "bg-gradient-to-br from-[#fffbeb] to-[#fef3c7]",
      border: "border-[#facc15]",
      bar: "from-[#facc15] to-[#f59e0b]",
      label_color: "text-[#a16207]",
      divider: "border-[#facc15]/30"
    }
  end

  defp podium_style(1) do
    %{
      bg: "bg-gradient-to-br from-neutral-50 to-neutral-100",
      border: "border-neutral-300",
      bar: "from-neutral-400 to-neutral-500",
      label_color: "text-neutral-600",
      divider: "border-neutral-300/50"
    }
  end

  defp podium_style(2) do
    %{
      bg: "bg-gradient-to-br from-orange-50 to-amber-50",
      border: "border-orange-300",
      bar: "from-orange-400 to-amber-500",
      label_color: "text-orange-700",
      divider: "border-orange-300/30"
    }
  end

  defp podium_style(_) do
    %{
      bg: "bg-white",
      border: "border-neutral-200",
      bar: "from-neutral-200 to-neutral-300",
      label_color: "text-neutral-500",
      divider: "border-neutral-200"
    }
  end

  # Winners table row tinting
  defp winners_row_bg(0), do: "bg-[#fffbeb]/40"
  defp winners_row_bg(1), do: "bg-neutral-50/40"
  defp winners_row_bg(2), do: "bg-orange-50/30"
  defp winners_row_bg(_), do: ""

  defp winner_index_color(0), do: "text-[#a16207]"
  defp winner_index_color(1), do: "text-neutral-500"
  defp winner_index_color(2), do: "text-orange-700"
  defp winner_index_color(_), do: "text-neutral-500"
end
