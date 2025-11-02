defmodule BlocksterV2Web.AdminLive do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Accounts

  @impl true
  def mount(_params, _session, socket) do
    # Load all users ordered by most recent first
    users = Accounts.list_users()
    {:ok, assign(socket, users: users)}
  end

  @impl true
  def handle_event("toggle_author_status", %{"user-id" => user_id}, socket) do
    user = Accounts.get_user(user_id)

    if user do
      case Accounts.update_user(user, %{is_author: !user.is_author}) do
        {:ok, _updated_user} ->
          # Reload users list
          users = Accounts.list_users()
          {:noreply, assign(socket, users: users)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200">
            <h1 class="text-2xl font-bold text-gray-900">User Management</h1>
            <p class="mt-1 text-sm text-gray-600">View all registered users</p>
          </div>

          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Wallet Address
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Email
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Username
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Auth Method
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Level
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    BUX
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Joined
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Author Status
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for user <- @users do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="flex items-center">
                        <code class="text-xs text-gray-900 bg-gray-100 px-2 py-1 rounded">
                          <%= String.slice(user.wallet_address, 0..9) %>...
                        </code>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if user.email do %>
                        <span class="text-sm text-gray-900"><%= user.email %></span>
                      <% else %>
                        <span class="text-sm text-gray-400">—</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if user.username do %>
                        <span class="text-sm text-gray-900"><%= user.username %></span>
                      <% else %>
                        <span class="text-sm text-gray-400">—</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={[
                        "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                        if(user.auth_method == "email", do: "bg-blue-100 text-blue-800", else: "bg-purple-100 text-purple-800")
                      ]}>
                        <%= user.auth_method %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= user.level %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= user.bux_balance %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= Calendar.strftime(user.inserted_at, "%b %d, %Y") %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <button
                        phx-click="toggle_author_status"
                        phx-value-user-id={user.id}
                        class={[
                          "px-3 py-1 rounded-full text-xs font-semibold transition-colors",
                          if(user.is_author, do: "bg-green-100 text-green-800 hover:bg-green-200", else: "bg-gray-100 text-gray-600 hover:bg-gray-200")
                        ]}
                      >
                        <%= if user.is_author, do: "Author ✓", else: "Make Author" %>
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div class="px-6 py-4 bg-gray-50 border-t border-gray-200">
            <p class="text-sm text-gray-600">
              Total users: <span class="font-semibold"><%= length(@users) %></span>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
