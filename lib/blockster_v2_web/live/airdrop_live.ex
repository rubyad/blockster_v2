defmodule BlocksterV2Web.AirdropLive do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Get user's BUX balance from the hook (set by BuxBalanceHook)
    token_balances = socket.assigns[:token_balances] || %{}

    # Calculate the BUX balance (from token_balances map)
    user_bux_balance =
      case token_balances do
        %{"BUX" => balance} when is_number(balance) -> trunc(balance)
        _ -> 0
      end

    # Airdrop end time: 7 days from now (this would be set from contract in production)
    airdrop_end_time = DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.to_unix()

    # Schedule countdown updates every second when connected
    if connected?(socket) do
      :timer.send_interval(1000, self(), :tick)
    end

    socket =
      socket
      |> assign(:page_title, "USDT Airdrop")
      |> assign(:user_bux_balance, user_bux_balance)
      |> assign(:airdrop_end_time, airdrop_end_time)
      |> assign(:redeem_amount, "")
      |> assign(:time_remaining, calculate_time_remaining(airdrop_end_time))

    {:ok, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    time_remaining = calculate_time_remaining(socket.assigns.airdrop_end_time)
    {:noreply, assign(socket, :time_remaining, time_remaining)}
  end

  @impl true
  def handle_event("update_redeem_amount", %{"value" => value}, socket) do
    cleaned_value = value |> String.replace(~r/[^\d]/, "")
    {:noreply, assign(socket, :redeem_amount, cleaned_value)}
  end

  @impl true
  def handle_event("set_max", _params, socket) do
    max_amount = socket.assigns.user_bux_balance |> to_string()
    {:noreply, assign(socket, :redeem_amount, max_amount)}
  end

  @impl true
  def handle_event("redeem_bux", _params, socket) do
    current_user = socket.assigns[:current_user]

    if current_user == nil do
      {:noreply, socket |> redirect(to: ~p"/login")}
    else
      {:noreply, socket |> put_flash(:info, "Redemption coming soon! This is a preview.")}
    end
  end

  defp calculate_time_remaining(end_time) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    diff = max(end_time - now, 0)

    days = div(diff, 86400)
    remaining_after_days = rem(diff, 86400)
    hours = div(remaining_after_days, 3600)
    remaining_after_hours = rem(remaining_after_days, 3600)
    minutes = div(remaining_after_hours, 60)
    seconds = rem(remaining_after_hours, 60)

    %{
      days: days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      total_seconds: diff
    }
  end

  defp parse_amount(""), do: 0
  defp parse_amount(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> 0
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-2xl mx-auto px-4 pt-24 pb-8">
        <!-- Header -->
        <div class="text-center mb-6">
          <h1 class="text-3xl font-bold text-gray-900 font-haas_medium_65">USDT Airdrop</h1>
          <p class="text-gray-600 text-sm">Redeem BUX to win USDT prizes</p>
        </div>

        <!-- Main Card -->
        <div class="bg-white rounded-2xl shadow-sm border border-gray-200 overflow-hidden">
          <!-- Prize Pool Header -->
          <div class="bg-black text-white p-6 text-center">
            <p class="text-gray-400 text-sm font-medium uppercase tracking-wider mb-1">Total Prize Pool</p>
            <div class="text-4xl font-bold font-haas_medium_65">$2,000 USDT</div>
          </div>

          <!-- Countdown Section -->
          <div class="p-6 border-b border-gray-200">
            <p class="text-center text-gray-500 text-sm font-medium mb-4">Drawing In</p>
            <div class="flex justify-center gap-3">
              <div class="text-center">
                <div class="bg-gray-100 rounded-xl w-16 h-16 flex items-center justify-center">
                  <span class="text-2xl font-bold text-gray-900">
                    <%= String.pad_leading(to_string(@time_remaining.days), 2, "0") %>
                  </span>
                </div>
                <p class="text-gray-500 text-xs mt-1">Days</p>
              </div>
              <div class="text-center">
                <div class="bg-gray-100 rounded-xl w-16 h-16 flex items-center justify-center">
                  <span class="text-2xl font-bold text-gray-900">
                    <%= String.pad_leading(to_string(@time_remaining.hours), 2, "0") %>
                  </span>
                </div>
                <p class="text-gray-500 text-xs mt-1">Hours</p>
              </div>
              <div class="text-center">
                <div class="bg-gray-100 rounded-xl w-16 h-16 flex items-center justify-center">
                  <span class="text-2xl font-bold text-gray-900">
                    <%= String.pad_leading(to_string(@time_remaining.minutes), 2, "0") %>
                  </span>
                </div>
                <p class="text-gray-500 text-xs mt-1">Min</p>
              </div>
              <div class="text-center">
                <div class="bg-gray-100 rounded-xl w-16 h-16 flex items-center justify-center">
                  <span class="text-2xl font-bold text-gray-900">
                    <%= String.pad_leading(to_string(@time_remaining.seconds), 2, "0") %>
                  </span>
                </div>
                <p class="text-gray-500 text-xs mt-1">Sec</p>
              </div>
            </div>
          </div>

          <!-- Prize Breakdown -->
          <div class="p-6 border-b border-gray-200">
            <p class="text-gray-500 text-sm font-medium mb-4 text-center">Prize Distribution</p>
            <div class="grid grid-cols-4 gap-3">
              <div class="text-center p-3 bg-yellow-50 rounded-xl border border-yellow-200">
                <div class="text-lg mb-1">🥇</div>
                <p class="font-bold text-gray-900">$250</p>
                <p class="text-xs text-gray-500">1st Place</p>
              </div>
              <div class="text-center p-3 bg-gray-50 rounded-xl border border-gray-200">
                <div class="text-lg mb-1">🥈</div>
                <p class="font-bold text-gray-900">$150</p>
                <p class="text-xs text-gray-500">2nd Place</p>
              </div>
              <div class="text-center p-3 bg-amber-50 rounded-xl border border-amber-200">
                <div class="text-lg mb-1">🥉</div>
                <p class="font-bold text-gray-900">$100</p>
                <p class="text-xs text-gray-500">3rd Place</p>
              </div>
              <div class="text-center p-3 bg-green-50 rounded-xl border border-green-200">
                <div class="text-lg mb-1">🎁</div>
                <p class="font-bold text-gray-900">$50</p>
                <p class="text-xs text-gray-500">×30 Winners</p>
              </div>
            </div>
          </div>

          <!-- Redeem Section -->
          <div class="p-6">
            <p class="text-gray-500 text-sm font-medium mb-4 text-center">Enter the Airdrop</p>

            <!-- Balance Display -->
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

            <!-- Amount Input -->
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
              <%= if @redeem_amount != "" and parse_amount(@redeem_amount) > 0 do %>
                <p class="text-gray-500 text-sm mt-2">
                  = <span class="font-medium text-gray-900"><%= Number.Delimit.number_to_delimited(parse_amount(@redeem_amount), precision: 0) %></span> entries
                </p>
              <% end %>
            </div>

            <!-- Redeem Button -->
            <% amount = parse_amount(@redeem_amount) %>
            <% can_redeem = @current_user != nil && amount > 0 && amount <= @user_bux_balance %>
            <button
              type="button"
              phx-click="redeem_bux"
              disabled={!can_redeem}
              class={"w-full py-4 font-bold text-lg rounded-xl transition-all cursor-pointer disabled:cursor-not-allowed #{if can_redeem, do: "bg-black text-white hover:bg-gray-800", else: "bg-gray-200 text-gray-400"}"}
            >
              <%= cond do %>
                <% @current_user == nil -> %>
                  Login to Enter
                <% @redeem_amount == "" or amount == 0 -> %>
                  Enter Amount
                <% amount > @user_bux_balance -> %>
                  Insufficient Balance
                <% true -> %>
                  Redeem <%= Number.Delimit.number_to_delimited(amount, precision: 0) %> BUX
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
          </div>
        </div>

        <!-- How It Works -->
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

        <!-- Footer Note -->
        <p class="text-center text-gray-400 text-xs mt-6">
          Winners selected via on-chain verifiable randomness when countdown ends
        </p>
      </div>
    </div>
    """
  end
end
