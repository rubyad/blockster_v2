defmodule BlocksterV2Web.UserProfileLive do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Social

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user do
      x_connection = Social.get_x_connection_for_user(socket.assigns.current_user.id)

      {:ok, assign(socket,
        editing_username: false,
        username_form: %{"username" => socket.assigns.current_user.username},
        x_connection: x_connection
      )}
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
            <!-- Username -->
            <div>
              <label class="block text-sm font-haas_medium_65 text-gray-500 mb-1">
                Username
              </label>
              <%= if @editing_username do %>
                <form phx-submit="save_username" class="flex items-center gap-2">
                  <input
                    type="text"
                    name="username"
                    value={@username_form["username"]}
                    phx-change="update_username_form"
                    class="flex-1 text-sm bg-white px-4 py-3 rounded-lg border border-gray-300 focus:border-[#8AE388] focus:ring-2 focus:ring-[#8AE388] focus:ring-opacity-50 outline-none transition-all"
                    placeholder="Enter username"
                  />
                  <button
                    type="submit"
                    class="px-4 py-3 bg-gradient-to-b from-[#8AE388] to-[#BAF55F] text-[#141414] rounded-lg font-haas_medium_65 hover:shadow-lg transition-all text-sm"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_edit_username"
                    class="px-4 py-3 bg-gray-100 text-gray-700 rounded-lg font-haas_medium_65 hover:bg-gray-200 transition-all text-sm"
                  >
                    Cancel
                  </button>
                </form>
              <% else %>
                <div class="flex items-center gap-2">
                  <div class="flex-1 text-sm bg-gray-50 px-4 py-3 rounded-lg border border-gray-200">
                    <%= @current_user.username || "Not set" %>
                  </div>
                  <button
                    phx-click="edit_username"
                    class="p-3 bg-gray-50 hover:bg-gray-100 rounded-lg border border-gray-200 transition-colors"
                    title="Edit username"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                    </svg>
                  </button>
                </div>
              <% end %>
            </div>

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

        <!-- Connected Accounts Card -->
        <div class="bg-white rounded-lg shadow mt-6">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-xl font-haas_bold_75 text-gray-900">Connected Accounts</h2>
            <p class="text-sm text-gray-500 mt-1">Connect your social accounts to earn BUX rewards for sharing</p>
          </div>

          <div class="px-6 py-4 space-y-4">
            <!-- X (Twitter) Connection -->
            <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg border border-gray-200">
              <div class="flex items-center gap-3">
                <!-- X Logo -->
                <div class="w-10 h-10 bg-black rounded-lg flex items-center justify-center">
                  <svg class="w-5 h-5 text-white" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
                  </svg>
                </div>
                <div>
                  <%= if @x_connection do %>
                    <div class="flex items-center gap-2">
                      <span class="text-sm font-haas_medium_65 text-gray-900">@{@x_connection.x_username}</span>
                      <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800">
                        Connected
                      </span>
                    </div>
                    <p class="text-xs text-gray-500">
                      Connected <%= Calendar.strftime(@x_connection.connected_at, "%b %d, %Y") %>
                    </p>
                  <% else %>
                    <span class="text-sm font-haas_medium_65 text-gray-900">X (Twitter)</span>
                    <p class="text-xs text-gray-500">Connect to earn BUX for retweets</p>
                  <% end %>
                </div>
              </div>

              <%= if @x_connection do %>
                <.link
                  href={~p"/auth/x/disconnect"}
                  method="delete"
                  data-confirm="Are you sure you want to disconnect your X account?"
                  class="px-4 py-2 text-sm font-haas_medium_65 text-red-600 hover:text-red-700 hover:bg-red-50 rounded-lg transition-colors"
                >
                  Disconnect
                </.link>
              <% else %>
                <.link
                  href={~p"/auth/x?redirect=/profile"}
                  class="px-4 py-2 bg-black text-white text-sm font-haas_medium_65 rounded-lg hover:bg-gray-800 transition-colors"
                >
                  Connect X
                </.link>
              <% end %>
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

  @impl true
  def handle_event("edit_username", _params, socket) do
    {:noreply, assign(socket, editing_username: true)}
  end

  @impl true
  def handle_event("cancel_edit_username", _params, socket) do
    {:noreply, assign(socket, editing_username: false, username_form: %{"username" => socket.assigns.current_user.username})}
  end

  @impl true
  def handle_event("update_username_form", %{"username" => username}, socket) do
    {:noreply, assign(socket, username_form: %{"username" => username})}
  end

  @impl true
  def handle_event("save_username", %{"username" => username}, socket) do
    current_user = socket.assigns.current_user

    case BlocksterV2.Accounts.update_user(current_user, %{username: username}) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(current_user: updated_user, editing_username: false)
         |> put_flash(:info, "Username updated successfully!")}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Failed to update username")}
    end
  end
end
