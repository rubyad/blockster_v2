defmodule BlocksterV2Web.OrderAdminLive.Show do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Orders

  @admin_statuses [
    {"Paid", "paid"},
    {"Processing", "processing"},
    {"Shipped", "shipped"},
    {"Delivered", "delivered"}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = Orders.get_order(id)

    if order do
      {:ok,
       socket
       |> assign(order: order)
       |> assign(admin_statuses: @admin_statuses)
       |> assign(tracking_number: order.tracking_number || "")
       |> assign(flash_message: nil)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Order not found")
       |> redirect(to: ~p"/admin/orders")}
    end
  end

  @impl true
  def handle_event("update_status", %{"status" => status}, socket) do
    order = socket.assigns.order

    case Orders.update_order(order, %{status: status}) do
      {:ok, updated_order} ->
        order = Orders.get_order(updated_order.id)
        {:noreply, socket |> assign(order: order) |> assign(flash_message: "Status updated to #{status_label(status)}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  @impl true
  def handle_event("save_tracking", %{"tracking_number" => tracking}, socket) do
    order = socket.assigns.order

    case Orders.update_order(order, %{tracking_number: tracking}) do
      {:ok, updated_order} ->
        order = Orders.get_order(updated_order.id)
        {:noreply, socket |> assign(order: order) |> assign(tracking_number: tracking) |> assign(flash_message: "Tracking number saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save tracking number")}
    end
  end

  @impl true
  def handle_event("update_tracking_input", %{"tracking_number" => tracking}, socket) do
    {:noreply, assign(socket, tracking_number: tracking)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 pt-24 pb-8">
      <div class="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8">
        <%!-- Header --%>
        <div class="mb-6 flex items-center justify-between">
          <div>
            <.link navigate={~p"/admin/orders"} class="text-sm text-blue-600 hover:text-blue-800 cursor-pointer">
              &larr; Back to Orders
            </.link>
            <h1 class="text-2xl font-bold text-gray-900 mt-1">Order <%= @order.order_number %></h1>
          </div>
          <span class={["inline-flex items-center px-3 py-1 rounded-full text-sm font-medium", status_style(@order.status)]}>
            <%= status_label(@order.status) %>
          </span>
        </div>

        <%= if @flash_message do %>
          <div class="mb-4 p-3 bg-green-50 border border-green-200 rounded-lg text-sm text-green-800">
            <%= @flash_message %>
          </div>
        <% end %>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Main column --%>
          <div class="lg:col-span-2 space-y-6">
            <%!-- Order Items --%>
            <div class="bg-white rounded-lg shadow">
              <div class="px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-semibold text-gray-900">Items</h2>
              </div>
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-200">
                  <thead class="bg-gray-50">
                    <tr>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Product</th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Variant</th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Qty</th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Price</th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Subtotal</th>
                    </tr>
                  </thead>
                  <tbody class="bg-white divide-y divide-gray-200">
                    <%= for item <- @order.order_items do %>
                      <tr>
                        <td class="px-6 py-4">
                          <div class="flex items-center gap-3">
                            <%= if item.product_image do %>
                              <img src={item.product_image} class="w-10 h-10 rounded object-cover" />
                            <% end %>
                            <span class="text-sm font-medium text-gray-900"><%= item.product_title %></span>
                          </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                          <%= item.variant_title || "--" %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          <%= item.quantity %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          $<%= Decimal.round(item.unit_price, 2) %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          $<%= Decimal.round(item.subtotal, 2) %>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>

            <%!-- Payment Breakdown --%>
            <div class="bg-white rounded-lg shadow">
              <div class="px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-semibold text-gray-900">Payment Breakdown</h2>
              </div>
              <div class="px-6 py-4 space-y-3">
                <div class="flex justify-between text-sm">
                  <span class="text-gray-600">Subtotal</span>
                  <span class="font-medium">$<%= Decimal.round(@order.subtotal, 2) %></span>
                </div>

                <%= if @order.bux_tokens_burned > 0 do %>
                  <div class="flex justify-between text-sm">
                    <span class="text-yellow-700">BUX Sent</span>
                    <span class="font-medium text-yellow-700"><%= @order.bux_tokens_burned %> BUX (-$<%= Decimal.round(@order.bux_discount_amount, 2) %>)</span>
                  </div>
                  <%= if @order.bux_burn_tx_hash do %>
                    <div class="text-xs text-gray-400 text-right">
                      TX: <a href={"https://roguescan.io/tx/#{@order.bux_burn_tx_hash}"} target="_blank" class="text-blue-500 hover:underline cursor-pointer font-mono"><%= String.slice(@order.bux_burn_tx_hash, 0, 16) %>...</a>
                    </div>
                  <% end %>
                <% end %>

                <%= if Decimal.gt?(@order.rogue_tokens_sent || Decimal.new(0), 0) do %>
                  <div class="flex justify-between text-sm">
                    <span class="text-purple-700">ROGUE Sent</span>
                    <span class="font-medium text-purple-700"><%= format_rogue(@order.rogue_tokens_sent) %> ROGUE (-$<%= Decimal.round(@order.rogue_payment_amount || Decimal.new(0), 2) %>)</span>
                  </div>
                  <%= if @order.rogue_payment_tx_hash do %>
                    <div class="text-xs text-gray-400 text-right">
                      TX: <a href={"https://roguescan.io/tx/#{@order.rogue_payment_tx_hash}"} target="_blank" class="text-blue-500 hover:underline cursor-pointer font-mono"><%= String.slice(@order.rogue_payment_tx_hash, 0, 16) %>...</a>
                    </div>
                  <% end %>
                <% end %>

                <%= if Decimal.gt?(@order.helio_payment_amount || Decimal.new(0), 0) do %>
                  <div class="flex justify-between text-sm">
                    <span class="text-blue-700">Helio Payment</span>
                    <span class="font-medium text-blue-700">$<%= Decimal.round(@order.helio_payment_amount, 2) %> (<%= @order.helio_payment_currency %>)</span>
                  </div>
                <% end %>

                <div class="border-t border-gray-200 pt-3 flex justify-between text-sm font-semibold">
                  <span>Total</span>
                  <span>$<%= Decimal.round(@order.subtotal, 2) %></span>
                </div>
              </div>
            </div>

            <%!-- Affiliate Payouts --%>
            <%= if @order.affiliate_payouts != [] do %>
              <div class="bg-white rounded-lg shadow">
                <div class="px-6 py-4 border-b border-gray-200">
                  <h2 class="text-lg font-semibold text-gray-900">Affiliate Payouts</h2>
                  <p class="text-xs text-gray-500 mt-1">
                    Referrer: <%= if @order.referrer, do: @order.referrer.email || @order.referrer.username, else: "Unknown" %>
                  </p>
                </div>
                <div class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-gray-200">
                    <thead class="bg-gray-50">
                      <tr>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Currency</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Basis</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Rate</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Commission</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                      </tr>
                    </thead>
                    <tbody class="bg-white divide-y divide-gray-200">
                      <%= for payout <- @order.affiliate_payouts do %>
                        <tr>
                          <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900"><%= payout.currency %></td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600"><%= Decimal.round(payout.basis_amount, 2) %></td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600"><%= Decimal.mult(payout.commission_rate, 100) |> Decimal.round(0) %>%</td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900"><%= Decimal.round(payout.commission_amount, 2) %> <%= payout.currency %></td>
                          <td class="px-6 py-4 whitespace-nowrap">
                            <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", payout_status_style(payout.status)]}>
                              <%= payout.status %>
                              <%= if payout.held_until do %>
                                (until <%= Calendar.strftime(payout.held_until, "%b %d") %>)
                              <% end %>
                            </span>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Sidebar --%>
          <div class="space-y-6">
            <%!-- Actions --%>
            <div class="bg-white rounded-lg shadow">
              <div class="px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-semibold text-gray-900">Actions</h2>
              </div>
              <div class="px-6 py-4 space-y-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Update Status</label>
                  <div class="flex gap-2">
                    <form phx-change="update_status" class="flex-1">
                      <select
                        name="status"
                        class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 cursor-pointer"
                      >
                        <%= for {label, value} <- @admin_statuses do %>
                          <option value={value} selected={value == @order.status}><%= label %></option>
                        <% end %>
                      </select>
                    </form>
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Tracking Number</label>
                  <form phx-submit="save_tracking" phx-change="update_tracking_input">
                    <div class="flex gap-2">
                      <input
                        type="text"
                        name="tracking_number"
                        value={@tracking_number}
                        placeholder="Enter tracking number"
                        class="flex-1 px-3 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      />
                      <button
                        type="submit"
                        class="px-3 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 cursor-pointer"
                      >
                        Save
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            </div>

            <%!-- Customer --%>
            <div class="bg-white rounded-lg shadow">
              <div class="px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-semibold text-gray-900">Customer</h2>
              </div>
              <div class="px-6 py-4 space-y-2 text-sm">
                <%= if @order.user do %>
                  <div>
                    <span class="text-gray-500">Email:</span>
                    <span class="text-gray-900"><%= @order.user.email %></span>
                  </div>
                  <div>
                    <span class="text-gray-500">Username:</span>
                    <span class="text-gray-900"><%= @order.user.username || "--" %></span>
                  </div>
                  <div>
                    <span class="text-gray-500">User ID:</span>
                    <span class="text-gray-900"><%= @order.user.id %></span>
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Shipping --%>
            <div class="bg-white rounded-lg shadow">
              <div class="px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-semibold text-gray-900">Shipping Address</h2>
              </div>
              <div class="px-6 py-4 text-sm text-gray-900 space-y-1">
                <%= if @order.shipping_name do %>
                  <div class="font-medium"><%= @order.shipping_name %></div>
                  <div><%= @order.shipping_address_line1 %></div>
                  <%= if @order.shipping_address_line2 do %>
                    <div><%= @order.shipping_address_line2 %></div>
                  <% end %>
                  <div><%= @order.shipping_city %>, <%= @order.shipping_state %> <%= @order.shipping_postal_code %></div>
                  <div><%= @order.shipping_country %></div>
                  <%= if @order.shipping_phone do %>
                    <div class="text-gray-500"><%= @order.shipping_phone %></div>
                  <% end %>
                  <div class="text-gray-500"><%= @order.shipping_email %></div>
                <% else %>
                  <div class="text-gray-400">No shipping address provided</div>
                <% end %>
              </div>
            </div>

            <%!-- Order Details --%>
            <div class="bg-white rounded-lg shadow">
              <div class="px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-semibold text-gray-900">Details</h2>
              </div>
              <div class="px-6 py-4 space-y-2 text-sm">
                <div class="flex justify-between">
                  <span class="text-gray-500">Order ID</span>
                  <span class="text-gray-900 font-mono text-xs"><%= @order.id %></span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-500">Created</span>
                  <span class="text-gray-900"><%= Calendar.strftime(@order.inserted_at, "%b %d, %Y %I:%M %p") %></span>
                </div>
                <%= if @order.tracking_number do %>
                  <div class="flex justify-between">
                    <span class="text-gray-500">Tracking</span>
                    <span class="text-gray-900 font-mono text-xs"><%= @order.tracking_number %></span>
                  </div>
                <% end %>
                <%= if @order.fulfillment_notified_at do %>
                  <div class="flex justify-between">
                    <span class="text-gray-500">Fulfillment Notified</span>
                    <span class="text-gray-900"><%= Calendar.strftime(@order.fulfillment_notified_at, "%b %d, %Y %I:%M %p") %></span>
                  </div>
                <% end %>
                <%= if @order.notes do %>
                  <div class="mt-2">
                    <span class="text-gray-500">Notes:</span>
                    <p class="text-gray-900 mt-1"><%= @order.notes %></p>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_label("pending"), do: "Pending"
  defp status_label("bux_pending"), do: "BUX Pending"
  defp status_label("bux_paid"), do: "BUX Paid"
  defp status_label("rogue_pending"), do: "ROGUE Pending"
  defp status_label("rogue_paid"), do: "ROGUE Paid"
  defp status_label("helio_pending"), do: "Helio Pending"
  defp status_label("paid"), do: "Paid"
  defp status_label("processing"), do: "Processing"
  defp status_label("shipped"), do: "Shipped"
  defp status_label("delivered"), do: "Delivered"
  defp status_label("expired"), do: "Expired"
  defp status_label("cancelled"), do: "Cancelled"
  defp status_label("refunded"), do: "Refunded"
  defp status_label(other), do: other

  defp format_rogue(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
    |> then(fn str ->
      case String.split(str, ".") do
        [int, dec] -> "#{add_commas(int)}.#{dec}"
        [int] -> add_commas(int)
      end
    end)
  end

  defp add_commas(int_str) do
    int_str |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()
  end

  defp status_style("paid"), do: "bg-green-100 text-green-800"
  defp status_style("processing"), do: "bg-blue-100 text-blue-800"
  defp status_style("shipped"), do: "bg-indigo-100 text-indigo-800"
  defp status_style("delivered"), do: "bg-emerald-100 text-emerald-800"
  defp status_style("cancelled"), do: "bg-red-100 text-red-800"
  defp status_style("refunded"), do: "bg-orange-100 text-orange-800"
  defp status_style("expired"), do: "bg-gray-100 text-gray-800"
  defp status_style("pending"), do: "bg-yellow-100 text-yellow-800"
  defp status_style(_), do: "bg-gray-100 text-gray-800"

  defp payout_status_style("paid"), do: "bg-green-100 text-green-800"
  defp payout_status_style("pending"), do: "bg-yellow-100 text-yellow-800"
  defp payout_status_style("held"), do: "bg-blue-100 text-blue-800"
  defp payout_status_style("failed"), do: "bg-red-100 text-red-800"
  defp payout_status_style(_), do: "bg-gray-100 text-gray-800"
end
