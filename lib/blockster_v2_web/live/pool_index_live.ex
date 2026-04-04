defmodule BlocksterV2Web.PoolIndexLive do
  use BlocksterV2Web, :live_view
  require Logger

  import BlocksterV2Web.PoolComponents

  alias BlocksterV2.BuxMinter

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Liquidity Pools")
      |> assign(pool_stats: nil)
      |> assign(pool_loading: true)

    socket =
      if connected?(socket) do
        start_async(socket, :fetch_pool_stats, fn -> BuxMinter.get_pool_stats() end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:fetch_pool_stats, {:ok, {:ok, stats}}, socket) do
    {:noreply, assign(socket, pool_stats: stats, pool_loading: false)}
  end

  def handle_async(:fetch_pool_stats, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, pool_loading: false)}
  end

  def handle_async(:fetch_pool_stats, {:exit, _reason}, socket) do
    {:noreply, assign(socket, pool_loading: false)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-3xl mx-auto px-4 sm:px-6 pt-8 sm:pt-16 pb-16">
        <%!-- Header --%>
        <div class="mb-8 sm:mb-10">
          <.link navigate={~p"/play"} class="inline-flex items-center gap-1.5 text-sm text-gray-400 hover:text-gray-700 font-haas_roman_55 mb-4 transition-colors cursor-pointer">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
            </svg>
            Back to Play
          </.link>
          <h1 class="text-2xl sm:text-3xl font-haas_bold_75 text-gray-900 tracking-tight">
            Liquidity Pools
          </h1>
          <p class="text-sm text-gray-500 mt-1.5 font-haas_roman_55">
            Deposit liquidity to the bankroll. Earn from every bet's house edge.
          </p>
        </div>

        <%!-- Pool Cards --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
          <.pool_card vault_type="sol" pool_stats={@pool_stats} loading={@pool_loading} />
          <.pool_card vault_type="bux" pool_stats={@pool_stats} loading={@pool_loading} />
        </div>

        <%!-- How It Works --%>
        <div class="mt-10 sm:mt-14">
          <h3 class="text-xs font-haas_medium_65 text-gray-400 uppercase tracking-wider mb-4">How it works</h3>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div class="bg-white rounded-xl border border-gray-200/80 p-4 shadow-[0_1px_2px_rgba(0,0,0,0.04)]">
              <div class="w-7 h-7 rounded-lg bg-gray-100 flex items-center justify-center mb-3">
                <span class="text-sm font-haas_medium_65 text-gray-500">1</span>
              </div>
              <h4 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Deposit</h4>
              <p class="text-xs text-gray-500 font-haas_roman_55 leading-relaxed">
                Add SOL or BUX to the pool and receive LP tokens representing your share.
              </p>
            </div>
            <div class="bg-white rounded-xl border border-gray-200/80 p-4 shadow-[0_1px_2px_rgba(0,0,0,0.04)]">
              <div class="w-7 h-7 rounded-lg bg-gray-100 flex items-center justify-center mb-3">
                <span class="text-sm font-haas_medium_65 text-gray-500">2</span>
              </div>
              <h4 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Earn</h4>
              <p class="text-xs text-gray-500 font-haas_roman_55 leading-relaxed">
                When players bet and lose, the pool grows. Your LP tokens increase in value over time.
              </p>
            </div>
            <div class="bg-white rounded-xl border border-gray-200/80 p-4 shadow-[0_1px_2px_rgba(0,0,0,0.04)]">
              <div class="w-7 h-7 rounded-lg bg-gray-100 flex items-center justify-center mb-3">
                <span class="text-sm font-haas_medium_65 text-gray-500">3</span>
              </div>
              <h4 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Withdraw</h4>
              <p class="text-xs text-gray-500 font-haas_roman_55 leading-relaxed">
                Burn LP tokens anytime to receive your share of the pool, including profits.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
