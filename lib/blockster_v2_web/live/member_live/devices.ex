defmodule BlocksterV2Web.MemberLive.Devices do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user do
      devices = Accounts.get_user_devices(user.id)
      {:ok, assign(socket, devices: devices)}
    else
      {:ok, redirect(socket, to: ~p"/login")}
    end
  end

  @impl true
  def handle_event("remove_device", %{"fingerprint_id" => fingerprint_id}, socket) do
    user = socket.assigns.current_user

    case Accounts.remove_user_device(user.id, fingerprint_id) do
      {:ok, :device_removed} ->
        devices = Accounts.get_user_devices(user.id)
        {:noreply,
         socket
         |> assign(devices: devices)
         |> put_flash(:info, "Device removed successfully")}

      {:error, :cannot_remove_last_device} ->
        {:noreply, put_flash(socket, :error, "Cannot remove your last device")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove device")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-haas_bold_75 mb-2">Registered Devices</h1>
        <p class="text-gray-600">
          Manage devices that are registered to your account
        </p>
      </div>

      <div class="bg-white rounded-lg shadow">
        <div class="px-6 py-4 border-b border-gray-200">
          <p class="text-sm text-gray-600">
            You have <span class="font-semibold"><%= length(@devices) %></span> device(s) registered to your account.
          </p>
          <p class="text-sm text-gray-500 mt-2">
            <strong>Note:</strong> The first device you used to create your account cannot be removed.
          </p>
        </div>

        <%= if Enum.empty?(@devices) do %>
          <div class="px-6 py-8 text-center text-gray-500">
            No devices registered
          </div>
        <% else %>
          <ul class="divide-y divide-gray-200">
            <%= for device <- @devices do %>
              <li class="px-6 py-4">
                <div class="flex items-center justify-between">
                  <div class="flex-1">
                    <div class="flex items-center gap-2 mb-1">
                      <%= if device.is_primary do %>
                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                          Primary Device
                        </span>
                      <% else %>
                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                          Secondary Device
                        </span>
                      <% end %>
                      <%= if device.device_name do %>
                        <span class="text-sm text-gray-900 font-medium">
                          <%= device.device_name %>
                        </span>
                      <% end %>
                    </div>
                    <div class="text-sm text-gray-600 space-y-1">
                      <p>
                        <span class="font-medium">First used:</span>
                        <%= Calendar.strftime(device.first_seen_at, "%B %d, %Y at %I:%M %p") %>
                      </p>
                      <p>
                        <span class="font-medium">Last used:</span>
                        <%= Calendar.strftime(device.last_seen_at, "%B %d, %Y at %I:%M %p") %>
                      </p>
                      <%= if device.fingerprint_confidence do %>
                        <p class="text-xs text-gray-500">
                          Confidence: <%= Float.round(device.fingerprint_confidence * 100, 1) %>%
                        </p>
                      <% end %>
                    </div>
                  </div>
                  <%= unless device.is_primary do %>
                    <button
                      phx-click="remove_device"
                      phx-value-fingerprint_id={device.fingerprint_id}
                      data-confirm="Are you sure you want to remove this device? You'll need to re-verify it if you log in from this device again."
                      class="ml-4 px-4 py-2 text-sm font-medium text-red-600 hover:text-red-800 hover:bg-red-50 rounded-md transition-colors cursor-pointer"
                    >
                      Remove
                    </button>
                  <% else %>
                    <div class="ml-4 px-4 py-2 text-sm text-gray-400">
                      Cannot remove
                    </div>
                  <% end %>
                </div>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <div class="mt-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
        <h3 class="text-sm font-semibold text-blue-900 mb-2">About Device Management</h3>
        <ul class="text-sm text-blue-800 space-y-1">
          <li>• Your primary device (first device used) cannot be removed for security reasons</li>
          <li>• You can add new devices by logging in from them</li>
          <li>• Removing a device will require re-verification if you log in from it again</li>
          <li>• Each device can only be registered to one account (anti-abuse protection)</li>
        </ul>
      </div>

      <div class="mt-6">
        <.link
          navigate={~p"/profile"}
          class="inline-flex items-center text-sm text-gray-600 hover:text-gray-900 cursor-pointer"
        >
          ← Back to Profile
        </.link>
      </div>
    </div>
    """
  end
end
