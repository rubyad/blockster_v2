defmodule BlocksterV2Web.AirdropLive do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Airdrop
  alias BlocksterV2.Wallets

  # ============================================================
  # Mount
  # ============================================================

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    token_balances = socket.assigns[:token_balances] || %{}

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
        DateTime.new!(~D[2026-03-01], ~T[17:00:00], "Etc/UTC") |> DateTime.to_unix()
      end

    {user_entries, connected_wallet} =
      if current_user && round_id do
        entries = Airdrop.get_user_entries(current_user.id, round_id)
        wallet = Wallets.get_connected_wallet(current_user.id)
        {entries, wallet}
      else
        {[], nil}
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

    socket =
      socket
      |> assign(:page_title, "USDT Airdrop")
      |> assign(:user_bux_balance, user_bux_balance)
      |> assign(:airdrop_end_time, airdrop_end_time)
      |> assign(:redeem_amount, "")
      |> assign(:time_remaining, calculate_time_remaining(airdrop_end_time))
      |> assign(:current_round, current_round)
      |> assign(:user_entries, Enum.reverse(user_entries))
      |> assign(:entry_results, entry_results)
      |> assign(:total_entries, total_entries)
      |> assign(:participant_count, participant_count)
      |> assign(:connected_wallet, connected_wallet)
      |> assign(:airdrop_drawn, airdrop_drawn)
      |> assign(:winners, winners)
      |> assign(:verification_data, verification_data)
      |> assign(:redeeming, false)
      |> assign(:claiming_index, nil)
      |> assign(:show_fairness_modal, false)

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

  def handle_event("redeem_bux", _params, socket) do
    user = socket.assigns[:current_user]
    round = socket.assigns.current_round
    amount = parse_amount(socket.assigns.redeem_amount)
    wallet = socket.assigns.connected_wallet

    cond do
      user == nil ->
        {:noreply, redirect(socket, to: ~p"/login")}

      !user.phone_verified ->
        {:noreply, put_flash(socket, :error, "Verify your phone number to enter the airdrop")}

      wallet == nil ->
        {:noreply, put_flash(socket, :error, "Connect an external wallet on your profile page first")}

      round == nil || round.status != "open" ->
        {:noreply, put_flash(socket, :error, "Airdrop is not currently open")}

      amount <= 0 ->
        {:noreply, put_flash(socket, :error, "Enter a valid amount")}

      amount > socket.assigns.user_bux_balance ->
        {:noreply, put_flash(socket, :error, "Insufficient BUX balance")}

      true ->
        external_wallet = wallet.wallet_address
        round_id = round.round_id

        start_async(socket, :redeem_bux, fn ->
          Airdrop.redeem_bux(user, amount, round_id, external_wallet: external_wallet)
        end)

        {:noreply, assign(socket, redeeming: true)}
    end
  end

  def handle_event("claim_prize", %{"winner-index" => index_str}, socket) do
    user = socket.assigns.current_user
    round_id = socket.assigns.current_round.round_id
    winner_index = String.to_integer(index_str)
    wallet = socket.assigns.connected_wallet

    if wallet == nil do
      {:noreply, put_flash(socket, :error, "Connect an external wallet on your profile page to claim")}
    else
      user_id = user.id
      claim_wallet = wallet.wallet_address

      start_async(socket, :claim_prize, fn ->
        # TODO: Phase 5 will call BUX Minter for real Arbitrum tx hash
        claim_tx = "pending"
        Airdrop.claim_prize(user_id, round_id, winner_index, claim_tx, claim_wallet)
      end)

      {:noreply, assign(socket, claiming_index: winner_index)}
    end
  end

  def handle_event("show_fairness_modal", _params, socket) do
    {:noreply, assign(socket, show_fairness_modal: true)}
  end

  def handle_event("close_fairness_modal", _params, socket) do
    {:noreply, assign(socket, show_fairness_modal: false)}
  end

  # ============================================================
  # Async Handlers
  # ============================================================

  @impl true
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
        {:round_not_open, _} -> "Airdrop is not currently open"
        :round_not_found -> "No active airdrop round"
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
     |> put_flash(:info, "The airdrop has been drawn! Check your results.")}
  end

  # ============================================================
  # Render
  # ============================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-2xl mx-auto px-4 pt-6 md:pt-24 pb-8">
        <%!-- Main Card --%>
        <div class="bg-white rounded-2xl shadow-sm border border-gray-200 overflow-hidden">
          <%!-- Prize Pool Header --%>
          <div class="bg-black text-white p-6 text-center">
            <p class="text-gray-400 text-sm font-medium uppercase tracking-wider mb-1">Total Prize Pool</p>
            <div class="text-4xl font-bold font-haas_medium_65">$2,000 USDT</div>
          </div>

          <%!-- Countdown --%>
          <div class="p-6 border-b border-gray-200">
            <p class="text-center text-gray-500 text-sm font-medium mb-2">
              <%= if @airdrop_drawn, do: "Drawing Complete", else: "Drawing On" %>
            </p>
            <p class="text-center text-gray-900 font-haas_medium_65 text-lg mb-4">
              <%= if @current_round do %>
                <%= Calendar.strftime(@current_round.end_time, "%B %d, %Y at %I:%M %p") %> UTC
              <% else %>
                March 1, 2026 at 12:00 PM EST
              <% end %>
            </p>
            <div class="flex justify-center gap-3">
              <.countdown_box value={@time_remaining.days} label="Days" />
              <.countdown_box value={@time_remaining.hours} label="Hours" />
              <.countdown_box value={@time_remaining.minutes} label="Min" />
              <.countdown_box value={@time_remaining.seconds} label="Sec" />
            </div>
          </div>

          <%!-- Prize Distribution --%>
          <div class="p-6 border-b border-gray-200">
            <p class="text-gray-500 text-sm font-medium mb-4 text-center">Prize Distribution</p>
            <div class="grid grid-cols-4 gap-3">
              <div class="text-center p-3 bg-yellow-50 rounded-xl border border-yellow-200">
                <div class="text-lg mb-1">&#x1F947;</div>
                <p class="font-bold text-gray-900">$250</p>
                <p class="text-xs text-gray-500">1st Place</p>
              </div>
              <div class="text-center p-3 bg-gray-50 rounded-xl border border-gray-200">
                <div class="text-lg mb-1">&#x1F948;</div>
                <p class="font-bold text-gray-900">$150</p>
                <p class="text-xs text-gray-500">2nd Place</p>
              </div>
              <div class="text-center p-3 bg-amber-50 rounded-xl border border-amber-200">
                <div class="text-lg mb-1">&#x1F949;</div>
                <p class="font-bold text-gray-900">$100</p>
                <p class="text-xs text-gray-500">3rd Place</p>
              </div>
              <div class="text-center p-3 bg-green-50 rounded-xl border border-green-200">
                <div class="text-lg mb-1">&#x1F381;</div>
                <p class="font-bold text-gray-900">$50</p>
                <p class="text-xs text-gray-500">&times;30 Winners</p>
              </div>
            </div>
          </div>

          <%!-- Main Content --%>
          <%= if @airdrop_drawn do %>
            <.celebration_section {assigns} />
          <% else %>
            <.entry_section {assigns} />
          <% end %>
        </div>

        <%!-- Receipt Panels --%>
        <%= if @user_entries != [] do %>
          <div class="mt-6 space-y-3">
            <p class="text-gray-500 text-sm font-medium">Your Entries</p>
            <%= for entry <- @user_entries do %>
              <.receipt_panel
                entry={entry}
                entry_results={@entry_results}
                airdrop_drawn={@airdrop_drawn}
                current_user={@current_user}
                connected_wallet={@connected_wallet}
                claiming_index={@claiming_index}
              />
            <% end %>
          </div>
        <% end %>

        <%!-- How It Works --%>
        <div class="mt-6 bg-white rounded-2xl shadow-sm border border-gray-200 p-6">
          <p class="text-gray-900 font-medium mb-4 text-center">How It Works</p>
          <div class="grid grid-cols-3 gap-4">
            <div class="text-center">
              <div class="w-10 h-10 bg-black rounded-full flex items-center justify-center mx-auto mb-2">
                <span class="text-white font-bold">1</span>
              </div>
              <p class="text-sm font-medium text-gray-900">Earn BUX</p>
              <p class="text-xs text-gray-500 mt-1">Read articles to earn BUX tokens</p>
            </div>
            <div class="text-center">
              <div class="w-10 h-10 bg-black rounded-full flex items-center justify-center mx-auto mb-2">
                <span class="text-white font-bold">2</span>
              </div>
              <p class="text-sm font-medium text-gray-900">Redeem</p>
              <p class="text-xs text-gray-500 mt-1">1 BUX = 1 entry</p>
            </div>
            <div class="text-center">
              <div class="w-10 h-10 bg-black rounded-full flex items-center justify-center mx-auto mb-2">
                <span class="text-white font-bold">3</span>
              </div>
              <p class="text-sm font-medium text-gray-900">Win</p>
              <p class="text-xs text-gray-500 mt-1">33 winners selected on-chain</p>
            </div>
          </div>
        </div>

        <p class="text-center text-gray-400 text-xs mt-6">
          Winners selected via on-chain verifiable randomness when countdown ends
        </p>
      </div>
    </div>

    <%!-- Provably Fair Modal --%>
    <%= if @show_fairness_modal && @verification_data do %>
      <.fairness_modal {assigns} />
    <% end %>
    """
  end

  # ============================================================
  # Function Components
  # ============================================================

  defp countdown_box(assigns) do
    ~H"""
    <div class="text-center">
      <div class="bg-gray-100 rounded-xl w-16 h-16 flex items-center justify-center">
        <span class="text-2xl font-bold text-gray-900">
          <%= String.pad_leading(to_string(@value), 2, "0") %>
        </span>
      </div>
      <p class="text-gray-500 text-xs mt-1"><%= @label %></p>
    </div>
    """
  end

  defp entry_section(assigns) do
    amount = parse_amount(assigns.redeem_amount)
    round_open = assigns.current_round != nil && assigns.current_round.status == "open"

    can_redeem =
      assigns.current_user != nil &&
        assigns.current_user.phone_verified == true &&
        assigns.connected_wallet != nil &&
        amount > 0 &&
        amount <= assigns.user_bux_balance &&
        round_open &&
        !assigns.redeeming

    assigns = assign(assigns, parsed_amount: amount, can_redeem: can_redeem, round_open: round_open)

    ~H"""
    <div class="p-6">
      <%!-- Pool Stats --%>
      <%= if @total_entries > 0 do %>
        <div class="text-center mb-4">
          <span class="text-gray-500 text-sm">
            <span class="font-medium text-gray-900"><%= Number.Delimit.number_to_delimited(@total_entries, precision: 0) %> BUX</span>
            from
            <span class="font-medium text-gray-900"><%= @participant_count %></span>
            <%= if @participant_count == 1, do: "participant", else: "participants" %>
          </span>
        </div>
      <% end %>

      <%= if @round_open do %>
        <p class="text-gray-500 text-sm font-medium mb-4 text-center">Enter the Airdrop</p>

        <%!-- Balance Display --%>
        <div class="flex items-center justify-between mb-4 p-3 bg-gray-50 rounded-xl">
          <span class="text-gray-600 text-sm">Your BUX Balance</span>
          <span class="font-bold text-gray-900">
            <%= if @current_user do %>
              <%= Number.Delimit.number_to_delimited(@user_bux_balance, precision: 0) %> BUX
            <% else %>
              <.link navigate={~p"/login"} class="text-blue-500 hover:underline cursor-pointer text-sm font-normal">
                Login to view
              </.link>
            <% end %>
          </span>
        </div>

        <%!-- Amount Input --%>
        <div class="mb-4">
          <label class="block text-sm font-medium text-gray-700 mb-2">BUX to Redeem</label>
          <div class="flex gap-2">
            <div class="flex-1 relative">
              <input
                type="text"
                inputmode="numeric"
                value={@redeem_amount}
                phx-keyup="update_redeem_amount"
                placeholder="Enter amount"
                class="w-full bg-white border border-gray-300 rounded-lg pl-4 pr-16 py-3 text-gray-900 text-lg font-medium focus:outline-none focus:border-gray-500 focus:ring-1 focus:ring-gray-500"
                disabled={@current_user == nil}
              />
              <button
                type="button"
                phx-click="set_max"
                class="absolute right-2 top-1/2 -translate-y-1/2 px-3 py-1 bg-gray-200 text-gray-700 rounded text-sm font-medium hover:bg-gray-300 transition-all cursor-pointer"
                disabled={@current_user == nil}
              >
                MAX
              </button>
            </div>
          </div>
          <%= if @redeem_amount != "" and @parsed_amount > 0 do %>
            <p class="text-gray-500 text-sm mt-2">
              = <span class="font-medium text-gray-900"><%= Number.Delimit.number_to_delimited(@parsed_amount, precision: 0) %></span> entries
            </p>
          <% end %>
        </div>

        <%!-- Redeem Button --%>
        <button
          type="button"
          phx-click="redeem_bux"
          disabled={!@can_redeem}
          class={"w-full py-4 font-bold text-lg rounded-xl transition-all cursor-pointer disabled:cursor-not-allowed #{if @can_redeem, do: "bg-black text-white hover:bg-gray-800", else: "bg-gray-200 text-gray-400"}"}
        >
          <%= cond do %>
            <% @redeeming -> %>
              Redeeming...
            <% @current_user == nil -> %>
              Login to Enter
            <% @current_user.phone_verified != true -> %>
              Verify Phone to Enter
            <% @connected_wallet == nil -> %>
              Connect Wallet to Enter
            <% @redeem_amount == "" or @parsed_amount == 0 -> %>
              Enter Amount
            <% @parsed_amount > @user_bux_balance -> %>
              Insufficient Balance
            <% true -> %>
              Redeem <%= Number.Delimit.number_to_delimited(@parsed_amount, precision: 0) %> BUX
          <% end %>
        </button>

        <%= if @current_user == nil do %>
          <p class="text-center text-gray-500 text-sm mt-4">
            <.link navigate={~p"/login"} class="text-blue-500 hover:underline cursor-pointer">Login</.link>
            or
            <.link navigate={~p"/login"} class="text-blue-500 hover:underline cursor-pointer">Sign up</.link>
            to participate
          </p>
        <% end %>
      <% else %>
        <div class="text-center py-6">
          <p class="text-gray-500 text-sm font-medium">
            <%= if @current_round && @current_round.status == "closed" do %>
              Entries closed — drawing winners...
            <% else %>
              Airdrop opening soon
            <% end %>
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp celebration_section(assigns) do
    top_three = Enum.take(assigns.winners, 3)
    assigns = assign(assigns, top_three: top_three)

    ~H"""
    <%!-- Celebration Header --%>
    <div class="bg-gradient-to-b from-gray-900 to-black p-8 text-center">
      <div class="text-4xl mb-3">&#x1F3C6;</div>
      <h2 class="text-2xl md:text-3xl font-bold text-white font-haas_medium_65 mb-2">
        The Airdrop Has Been Drawn!
      </h2>
      <p class="text-gray-400">Congratulations to our 33 winners</p>
    </div>

    <%!-- Top 3 Winners --%>
    <div class="p-6 border-b border-gray-200">
      <div class="grid grid-cols-3 gap-3">
        <%= for winner <- @top_three do %>
          <% {bg, border, label} = podium_style(winner.winner_index) %>
          <div class={"text-center p-4 rounded-xl border #{bg} #{border}"}>
            <div class="text-2xl mb-1"><%= podium_medal(winner.winner_index) %></div>
            <p class="font-bold text-gray-900 text-lg">$<%= format_prize_usd(winner.prize_usd) %></p>
            <p class="text-xs text-gray-500 mt-1"><%= label %></p>
            <p class="text-xs text-gray-400 mt-2 font-mono"><%= truncate_address(winner.wallet_address) %></p>
            <p class="text-xs text-gray-500">
              Position #<%= Number.Delimit.number_to_delimited(winner.random_number, precision: 0) %>
            </p>
          </div>
        <% end %>
      </div>
    </div>

    <%!-- Pool Stats --%>
    <%= if @total_entries > 0 do %>
      <div class="px-6 pt-4 text-center">
        <span class="text-gray-500 text-sm">
          <span class="font-medium text-gray-900"><%= Number.Delimit.number_to_delimited(@total_entries, precision: 0) %> BUX</span>
          from
          <span class="font-medium text-gray-900"><%= @participant_count %></span>
          participants
        </span>
      </div>
    <% end %>

    <%!-- Winners Table --%>
    <div class="p-6">
      <p class="text-gray-900 font-medium mb-4">All 33 Winners</p>
      <div class="overflow-x-auto -mx-6 px-6">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-gray-200 text-left">
              <th class="pb-3 pr-3 text-gray-500 font-medium">#</th>
              <th class="pb-3 pr-3 text-gray-500 font-medium">Winner</th>
              <th class="pb-3 pr-3 text-gray-500 font-medium">Position</th>
              <th class="pb-3 pr-3 text-gray-500 font-medium hidden sm:table-cell">Block</th>
              <th class="pb-3 pr-3 text-gray-500 font-medium">Prize</th>
              <th class="pb-3 text-gray-500 font-medium">Status</th>
            </tr>
          </thead>
          <tbody>
            <%= for winner <- @winners do %>
              <% row_bg = case winner.winner_index do
                0 -> "bg-yellow-50/50"
                1 -> "bg-gray-50/50"
                2 -> "bg-amber-50/50"
                _ -> ""
              end %>
              <tr class={"border-b border-gray-100 #{row_bg}"}>
                <td class="py-3 pr-3 font-medium text-gray-900"><%= winner.winner_index + 1 %></td>
                <td class="py-3 pr-3">
                  <a
                    href={"https://roguescan.io/address/#{winner.wallet_address}"}
                    target="_blank"
                    class="text-blue-500 hover:underline font-mono text-xs cursor-pointer"
                  >
                    <%= truncate_address(winner.wallet_address) %>
                  </a>
                </td>
                <td class="py-3 pr-3 font-mono text-xs text-gray-600">
                  #<%= Number.Delimit.number_to_delimited(winner.random_number, precision: 0) %>
                </td>
                <td class="py-3 pr-3 text-xs text-gray-500 hidden sm:table-cell">
                  #<%= Number.Delimit.number_to_delimited(winner.deposit_start, precision: 0) %>&ndash;#<%= Number.Delimit.number_to_delimited(winner.deposit_end, precision: 0) %>
                </td>
                <td class="py-3 pr-3 font-medium text-gray-900">$<%= format_prize_usd(winner.prize_usd) %></td>
                <td class="py-3">
                  <.winner_status
                    winner={winner}
                    current_user={@current_user}
                    connected_wallet={@connected_wallet}
                    claiming_index={@claiming_index}
                  />
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%!-- Verify Fairness --%>
      <div class="mt-6 text-center">
        <button
          type="button"
          phx-click="show_fairness_modal"
          class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors cursor-pointer"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
          </svg>
          Verify Fairness
        </button>
      </div>
    </div>
    """
  end

  defp winner_status(assigns) do
    ~H"""
    <%= cond do %>
      <% @winner.claimed -> %>
        <span class="inline-flex items-center gap-1 text-xs font-medium text-green-700 bg-green-50 px-2 py-1 rounded-full">
          Claimed
          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
          </svg>
        </span>
        <%= if @winner.claim_tx && @winner.claim_tx != "pending" do %>
          <a href={"https://arbiscan.io/tx/#{@winner.claim_tx}"} target="_blank" class="text-blue-500 hover:underline text-xs ml-1 cursor-pointer">
            tx
          </a>
        <% end %>
      <% @current_user && @winner.user_id == @current_user.id && @connected_wallet != nil -> %>
        <button
          type="button"
          phx-click="claim_prize"
          phx-value-winner-index={@winner.winner_index}
          disabled={@claiming_index == @winner.winner_index}
          class="text-xs font-medium text-white bg-black px-3 py-1 rounded-full hover:bg-gray-800 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <%= if @claiming_index == @winner.winner_index, do: "Claiming...", else: "Claim" %>
        </button>
      <% @current_user && @winner.user_id == @current_user.id -> %>
        <.link navigate={~p"/member/#{@current_user.slug}"} class="text-xs font-medium text-blue-500 hover:underline cursor-pointer">
          Connect Wallet
        </.link>
      <% true -> %>
        <span class="text-xs text-gray-400">&mdash;</span>
    <% end %>
    """
  end

  defp receipt_panel(assigns) do
    wins = Map.get(assigns.entry_results, assigns.entry.id, [])
    assigns = assign(assigns, wins: wins, has_wins: wins != [])

    ~H"""
    <div class={"bg-white rounded-xl border p-4 shadow-sm #{if @has_wins && @airdrop_drawn, do: "border-yellow-300 bg-yellow-50/30", else: "border-gray-200"}"}>
      <%= if @has_wins && @airdrop_drawn do %>
        <%!-- Winning Receipt --%>
        <%= for win <- @wins do %>
          <div class="flex items-start justify-between mb-3">
            <div>
              <p class="font-bold text-gray-900">
                &#x1F3C6; Winner! &mdash; <%= ordinal(win.winner_index + 1) %> Place
              </p>
              <p class="text-sm text-gray-600">
                Prize: <span class="font-bold">$<%= format_prize_usd(win.prize_usd) %> USDT</span>
              </p>
            </div>
            <div>
              <%= cond do %>
                <% win.claimed -> %>
                  <span class="inline-flex items-center gap-1 text-xs font-medium text-green-700 bg-green-50 px-2 py-1 rounded-full">
                    Claimed
                    <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                    </svg>
                  </span>
                <% @current_user && @connected_wallet -> %>
                  <button
                    type="button"
                    phx-click="claim_prize"
                    phx-value-winner-index={win.winner_index}
                    disabled={@claiming_index == win.winner_index}
                    class="text-xs font-medium text-white bg-black px-3 py-1.5 rounded-lg hover:bg-gray-800 transition-colors cursor-pointer disabled:opacity-50"
                  >
                    <%= if @claiming_index == win.winner_index, do: "Claiming...", else: "Claim $#{format_prize_usd(win.prize_usd)}" %>
                  </button>
                <% @current_user -> %>
                  <.link navigate={~p"/member/#{@current_user.slug}"} class="text-xs text-blue-500 hover:underline cursor-pointer">
                    Connect Wallet to Claim
                  </.link>
                <% true -> %>
              <% end %>
            </div>
          </div>
          <p class="text-xs text-gray-500 mb-2">
            Winning Position: <span class="font-mono">#<%= Number.Delimit.number_to_delimited(win.random_number, precision: 0) %></span>
          </p>
        <% end %>
      <% else %>
        <%= if @airdrop_drawn do %>
          <div class="flex items-center gap-2 mb-2">
            <p class="text-sm text-gray-500">
              Redeemed <%= Number.Delimit.number_to_delimited(@entry.amount, precision: 0) %> BUX &mdash; No win this round
            </p>
          </div>
        <% else %>
          <div class="flex items-center gap-2 mb-2">
            <svg class="w-4 h-4 text-green-500 shrink-0" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
            </svg>
            <p class="font-medium text-gray-900">
              Redeemed <%= Number.Delimit.number_to_delimited(@entry.amount, precision: 0) %> BUX
            </p>
          </div>
        <% end %>
      <% end %>

      <%!-- Entry Details --%>
      <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-500 mt-2">
        <span>Block: <span class="font-mono">#<%= Number.Delimit.number_to_delimited(@entry.start_position, precision: 0) %>&ndash;#<%= Number.Delimit.number_to_delimited(@entry.end_position, precision: 0) %></span></span>
        <span>Entries: <%= Number.Delimit.number_to_delimited(@entry.amount, precision: 0) %></span>
        <span><%= format_datetime(@entry.inserted_at) %></span>
      </div>

      <%= if @entry.deposit_tx do %>
        <div class="mt-2">
          <a href={"https://roguescan.io/tx/#{@entry.deposit_tx}"} target="_blank" class="text-xs text-blue-500 hover:underline cursor-pointer">
            View on RogueScan &rarr;
          </a>
        </div>
      <% end %>
    </div>
    """
  end

  defp fairness_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4" phx-window-keydown="close_fairness_modal" phx-key="Escape">
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_fairness_modal"></div>

      <div class="relative bg-white rounded-2xl shadow-xl max-w-lg w-full max-h-[90vh] overflow-y-auto">
        <%!-- Header --%>
        <div class="sticky top-0 bg-white border-b border-gray-200 p-6 rounded-t-2xl flex items-center justify-between z-10">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 bg-gray-900 rounded-xl flex items-center justify-center">
              <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
              </svg>
            </div>
            <h3 class="text-lg font-bold text-gray-900">Provably Fair Verification</h3>
          </div>
          <button type="button" phx-click="close_fairness_modal" class="p-2 text-gray-400 hover:text-gray-600 rounded-lg hover:bg-gray-100 transition-colors cursor-pointer">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <%!-- Steps --%>
        <div class="p-6 space-y-6">
          <%!-- Step 1: Commitment --%>
          <div class="flex gap-4">
            <div class="shrink-0 w-8 h-8 bg-gray-900 rounded-full flex items-center justify-center">
              <span class="text-white text-sm font-bold">1</span>
            </div>
            <div class="flex-1 min-w-0">
              <h4 class="font-medium text-gray-900 mb-1">Before Airdrop Opened</h4>
              <p class="text-sm text-gray-500 mb-3">
                We committed to a secret seed before anyone could enter. This hash was published on-chain &mdash; we can't change it.
              </p>
              <div class="bg-gray-50 rounded-lg p-3">
                <p class="text-xs text-gray-500 mb-1">Commitment Hash</p>
                <p class="text-xs font-mono text-gray-700 break-all"><%= @verification_data.commitment_hash %></p>
              </div>
            </div>
          </div>

          <%!-- Step 2: Block Hash --%>
          <div class="flex gap-4">
            <div class="shrink-0 w-8 h-8 bg-gray-900 rounded-full flex items-center justify-center">
              <span class="text-white text-sm font-bold">2</span>
            </div>
            <div class="flex-1 min-w-0">
              <h4 class="font-medium text-gray-900 mb-1">Airdrop Closed</h4>
              <p class="text-sm text-gray-500 mb-3">
                The blockchain provided external randomness we couldn't predict. Nobody can control future block hashes.
              </p>
              <div class="bg-gray-50 rounded-lg p-3">
                <p class="text-xs text-gray-500 mb-1">Block Hash at Close</p>
                <p class="text-xs font-mono text-gray-700 break-all"><%= @verification_data.block_hash_at_close %></p>
              </div>
            </div>
          </div>

          <%!-- Step 3: Seed Revealed --%>
          <div class="flex gap-4">
            <div class="shrink-0 w-8 h-8 bg-gray-900 rounded-full flex items-center justify-center">
              <span class="text-white text-sm font-bold">3</span>
            </div>
            <div class="flex-1 min-w-0">
              <h4 class="font-medium text-gray-900 mb-1">Seed Revealed</h4>
              <p class="text-sm text-gray-500 mb-3">
                We revealed our secret seed. Verify it matches the commitment from Step 1.
              </p>
              <div class="bg-gray-50 rounded-lg p-3 space-y-2">
                <div>
                  <p class="text-xs text-gray-500 mb-1">Server Seed</p>
                  <p class="text-xs font-mono text-gray-700 break-all"><%= @verification_data.server_seed %></p>
                </div>
                <div class="flex items-center gap-2 pt-2 border-t border-gray-200">
                  <svg class="w-4 h-4 text-green-500 shrink-0" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                  </svg>
                  <p class="text-xs text-green-700 font-medium">SHA256(Server Seed) matches commitment hash</p>
                </div>
              </div>
            </div>
          </div>

          <%!-- Step 4: Winner Derivation --%>
          <div class="flex gap-4">
            <div class="shrink-0 w-8 h-8 bg-gray-900 rounded-full flex items-center justify-center">
              <span class="text-white text-sm font-bold">4</span>
            </div>
            <div class="flex-1 min-w-0">
              <h4 class="font-medium text-gray-900 mb-1">Winner Derivation</h4>
              <p class="text-sm text-gray-500 mb-3">
                Each winner is derived deterministically. Anyone can re-run this math to verify every winner.
              </p>
              <div class="bg-gray-50 rounded-lg p-3 mb-3">
                <p class="text-xs text-gray-500 mb-1">Formula</p>
                <p class="text-xs font-mono text-gray-700">Combined Seed = keccak256(Server Seed + Block Hash)</p>
                <p class="text-xs font-mono text-gray-700 mt-1">
                  Winner[i] = keccak256(Combined, i) mod <%= Number.Delimit.number_to_delimited(@verification_data.total_entries, precision: 0) %> + 1
                </p>
              </div>
              <div class="bg-gray-50 rounded-lg overflow-hidden">
                <table class="w-full text-xs">
                  <thead>
                    <tr class="border-b border-gray-200">
                      <th class="text-left p-2 text-gray-500 font-medium">#</th>
                      <th class="text-left p-2 text-gray-500 font-medium">Position</th>
                      <th class="text-left p-2 text-gray-500 font-medium">Winner</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for winner <- @winners do %>
                      <tr class="border-b border-gray-100 last:border-0">
                        <td class="p-2 text-gray-600"><%= winner.winner_index + 1 %></td>
                        <td class="p-2 font-mono text-gray-700">#<%= Number.Delimit.number_to_delimited(winner.random_number, precision: 0) %></td>
                        <td class="p-2 font-mono text-gray-500"><%= truncate_address(winner.wallet_address) %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>

        <%!-- Footer --%>
        <div class="border-t border-gray-200 p-6 text-center">
          <p class="text-xs text-gray-500">
            All values are stored on-chain and verifiable on
            <a href="https://roguescan.io" target="_blank" class="text-blue-500 hover:underline cursor-pointer">RogueScan</a>
          </p>
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

  defp parse_amount(str) do
    case Integer.parse(str) do
      {num, _} -> max(num, 0)
      :error -> 0
    end
  end

  defp compute_entry_results(user_entries, winners) do
    for entry <- user_entries, into: %{} do
      matching_wins =
        Enum.filter(winners, fn w ->
          w.random_number >= entry.start_position and w.random_number <= entry.end_position
        end)

      {entry.id, matching_wins}
    end
  end

  defp truncate_address(nil), do: raw("&mdash;")
  defp truncate_address(addr) when byte_size(addr) < 10, do: addr
  defp truncate_address(addr), do: "#{String.slice(addr, 0, 6)}...#{String.slice(addr, -4, 4)}"

  defp format_prize_usd(cents) when is_integer(cents), do: Number.Delimit.number_to_delimited(div(cents, 100), precision: 0)

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %I:%M %p UTC")
  defp format_datetime(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %I:%M %p")

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n), do: "#{n}th"

  defp podium_style(0), do: {"bg-gradient-to-br from-amber-100 to-yellow-50", "border-amber-300", "1st Place"}
  defp podium_style(1), do: {"bg-gradient-to-br from-gray-100 to-slate-50", "border-gray-300", "2nd Place"}
  defp podium_style(2), do: {"bg-gradient-to-br from-orange-100 to-amber-50", "border-orange-300", "3rd Place"}

  defp podium_medal(0), do: raw("&#x1F947;")
  defp podium_medal(1), do: raw("&#x1F948;")
  defp podium_medal(2), do: raw("&#x1F949;")
end
