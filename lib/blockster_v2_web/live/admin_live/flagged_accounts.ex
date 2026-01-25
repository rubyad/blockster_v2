defmodule BlocksterV2Web.AdminLive.FlaggedAccounts do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      flagged_users = Accounts.list_flagged_accounts()

      {:ok, assign(socket, flagged_users: flagged_users)}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-haas_bold_75 mb-6">Flagged Multi-Account Attempts</h1>

      <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-6">
        <p class="text-sm text-yellow-800">
          <strong>⚠️ Security Alert:</strong> These users attempted to create multiple accounts
          or accessed the platform from devices already registered to other accounts.
        </p>
      </div>

      <div class="bg-white rounded-lg shadow">
        <table class="min-w-full">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Email
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Devices
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Last Suspicious Activity
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Account Created
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= if Enum.empty?(@flagged_users) do %>
              <tr>
                <td colspan="4" class="px-6 py-8 text-center text-gray-500">
                  No flagged accounts found
                </td>
              </tr>
            <% else %>
              <%= for user <- @flagged_users do %>
                <tr>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= user.email %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= user.registered_devices_count %> device(s)
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= if user.last_suspicious_activity_at do %>
                      <%= Calendar.strftime(user.last_suspicious_activity_at, "%Y-%m-%d %H:%M") %>
                    <% else %>
                      N/A
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= Calendar.strftime(user.inserted_at, "%Y-%m-%d %H:%M") %>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
