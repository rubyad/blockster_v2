defmodule BlocksterV2Web.UserProfileLive do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user do
      {:ok, socket}
    else
      {:ok, socket |> put_flash(:error, "You must be logged in to view your profile") |> redirect(to: "/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        <!-- Profile Header Card -->
        <div class="bg-white rounded-lg shadow-lg overflow-hidden mb-6">
          <!-- Cover Image/Gradient -->
          <div class="h-32 bg-gradient-to-r from-[#8AE388] to-[#BAF55F]"></div>

          <!-- Profile Info -->
          <div class="px-6 pb-6">
            <div class="flex flex-col sm:flex-row items-start sm:items-end -mt-16 mb-4">
              <!-- Avatar -->
              <div class="relative mb-4 sm:mb-0">
                <div class="w-32 h-32 rounded-full border-4 border-white bg-[#AFB5FF] overflow-hidden shadow-lg">
                  <%= if @current_user.avatar_url do %>
                    <img src={@current_user.avatar_url} alt="Avatar" class="w-full h-full object-cover" />
                  <% else %>
                    <img src="/images/avatar.png" alt="Avatar" class="w-full h-full object-cover" />
                  <% end %>
                </div>
                <!-- Level Badge -->
                <div class="absolute -bottom-2 left-1/2 transform -translate-x-1/2">
                  <span class="flex h-8 items-center justify-center rounded-lg bg-gradient-to-r from-[#8AE388] to-[#BAF55F] px-3 text-black text-sm font-work_sans font-bold shadow-md">
                    Level {@current_user.level}
                  </span>
                </div>
              </div>

              <!-- Name and Username -->
              <div class="sm:ml-6 flex-1">
                <h1 class="text-3xl font-haas_bold_75 text-gray-900">
                  <%= @current_user.username || "User" %>
                </h1>
                <p class="text-sm text-gray-500 mt-1">
                  <%= if @current_user.auth_method == "email" do %>
                    <span class="inline-flex items-center gap-1">
                      <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                      </svg>
                      {@current_user.email}
                    </span>
                  <% else %>
                    <span class="inline-flex items-center gap-1">
                      <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                      </svg>
                      Wallet Connected
                    </span>
                  <% end %>
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Stats Grid -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
          <!-- BUX Balance Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-sm font-haas_medium_65 text-gray-500 uppercase">BUX Balance</h3>
              <.lightning_icon id="profile_bux" size="24" />
            </div>
            <p class="text-3xl font-haas_bold_75 text-gray-900">
              <%= @current_user.bux_balance %>
            </p>
            <p class="text-xs text-gray-500 mt-1">Earn more by reading articles</p>
          </div>

          <!-- Level Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-sm font-haas_medium_65 text-gray-500 uppercase">Level</h3>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-[#8AE388]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <p class="text-3xl font-haas_bold_75 text-gray-900">
              {@current_user.level}
            </p>
            <!-- Progress Bar -->
            <div class="mt-3">
              <div class="flex justify-between text-xs text-gray-500 mb-1">
                <span>{@current_user.experience_points} XP</span>
                <span>{@current_user.level * 1000} XP</span>
              </div>
              <div class="h-2 bg-gray-200 rounded-full overflow-hidden">
                <div
                  class="h-full bg-gradient-to-r from-[#8AE388] to-[#BAF55F]"
                  style={"width: #{min(100, rem(@current_user.experience_points, 1000) / 10)}%"}
                >
                </div>
              </div>
            </div>
          </div>

          <!-- Experience Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-sm font-haas_medium_65 text-gray-500 uppercase">Total XP</h3>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-[#8AE388]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4M7.835 4.697a3.42 3.42 0 001.946-.806 3.42 3.42 0 014.438 0 3.42 3.42 0 001.946.806 3.42 3.42 0 013.138 3.138 3.42 3.42 0 00.806 1.946 3.42 3.42 0 010 4.438 3.42 3.42 0 00-.806 1.946 3.42 3.42 0 01-3.138 3.138 3.42 3.42 0 00-1.946.806 3.42 3.42 0 01-4.438 0 3.42 3.42 0 00-1.946-.806 3.42 3.42 0 01-3.138-3.138 3.42 3.42 0 00-.806-1.946 3.42 3.42 0 010-4.438 3.42 3.42 0 00.806-1.946 3.42 3.42 0 013.138-3.138z" />
              </svg>
            </div>
            <p class="text-3xl font-haas_bold_75 text-gray-900">
              <%= @current_user.experience_points %>
            </p>
            <p class="text-xs text-gray-500 mt-1">
              <%= 1000 - rem(@current_user.experience_points, 1000) %> XP to next level
            </p>
          </div>
        </div>

        <!-- Account Details Card -->
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-xl font-haas_bold_75 text-gray-900">Account Details</h2>
          </div>

          <div class="px-6 py-4 space-y-4">
            <!-- Wallet Address -->
            <div>
              <label class="block text-sm font-haas_medium_65 text-gray-500 mb-1">
                Wallet Address
              </label>
              <div class="flex items-center gap-2">
                <code class="flex-1 text-sm bg-gray-50 px-4 py-3 rounded-lg border border-gray-200 font-mono">
                  {@current_user.wallet_address}
                </code>
                <button
                  phx-click="copy_wallet"
                  class="p-3 bg-gray-50 hover:bg-gray-100 rounded-lg border border-gray-200 transition-colors"
                  title="Copy to clipboard"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                  </svg>
                </button>
              </div>
            </div>

            <!-- Email (if available) -->
            <%= if @current_user.email do %>
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-500 mb-1">
                  Email Address
                </label>
                <div class="text-sm bg-gray-50 px-4 py-3 rounded-lg border border-gray-200">
                  {@current_user.email}
                </div>
              </div>
            <% end %>

            <!-- Auth Method -->
            <div>
              <label class="block text-sm font-haas_medium_65 text-gray-500 mb-1">
                Authentication Method
              </label>
              <div class="text-sm bg-gray-50 px-4 py-3 rounded-lg border border-gray-200 capitalize">
                {@current_user.auth_method}
              </div>
            </div>

            <!-- Chain ID -->
            <div>
              <label class="block text-sm font-haas_medium_65 text-gray-500 mb-1">
                Chain ID
              </label>
              <div class="text-sm bg-gray-50 px-4 py-3 rounded-lg border border-gray-200">
                {@current_user.chain_id}
              </div>
            </div>

            <!-- Member Since -->
            <div>
              <label class="block text-sm font-haas_medium_65 text-gray-500 mb-1">
                Member Since
              </label>
              <div class="text-sm bg-gray-50 px-4 py-3 rounded-lg border border-gray-200">
                <%= Calendar.strftime(@current_user.inserted_at, "%B %d, %Y") %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("copy_wallet", _params, socket) do
    {:noreply, socket |> put_flash(:info, "Wallet address copied to clipboard!")}
  end
end
