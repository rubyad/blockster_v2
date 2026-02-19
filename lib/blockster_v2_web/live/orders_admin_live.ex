defmodule BlocksterV2Web.OrdersAdminLive do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Orders

  @statuses [
    {"All", "all"},
    {"Pending", "pending"},
    {"BUX Paid", "bux_paid"},
    {"ROGUE Paid", "rogue_paid"},
    {"Paid", "paid"},
    {"Processing", "processing"},
    {"Shipped", "shipped"},
    {"Delivered", "delivered"},
    {"Cancelled", "cancelled"},
    {"Refunded", "refunded"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    orders = Orders.list_orders_admin()

    {:ok,
     socket
     |> assign(orders: orders)
     |> assign(status_filter: "all")
     |> assign(statuses: @statuses)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    orders = Orders.list_orders_admin(%{status: status})
    {:noreply, socket |> assign(orders: orders) |> assign(status_filter: status)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 pt-24 pb-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-2xl font-bold text-gray-900">Orders</h1>
                <p class="mt-1 text-sm text-gray-600">
                  <%= length(@orders) %> order<%= if length(@orders) != 1, do: "s" %>
                </p>
              </div>
              <div>
                <form phx-change="filter_status">
                  <select
                    name="status"
                    class="px-4 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 cursor-pointer"
                  >
                    <%= for {label, value} <- @statuses do %>
                      <option value={value} selected={value == @status_filter}><%= label %></option>
                    <% end %>
                  </select>
                </form>
              </div>
            </div>
          </div>

          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Order
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Customer
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Payment
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Total
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Date
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= if Enum.empty?(@orders) do %>
                  <tr>
                    <td colspan="7" class="px-6 py-12 text-center text-sm text-gray-500">
                      No orders found
                    </td>
                  </tr>
                <% end %>
                <%= for order <- @orders do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <.link
                        navigate={~p"/admin/orders/#{order.id}"}
                        class="text-sm font-medium text-blue-600 hover:text-blue-800 hover:underline cursor-pointer"
                      >
                        <%= order.order_number %>
                      </.link>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="text-sm text-gray-900">
                        <%= if order.shipping_email, do: order.shipping_email, else: order.user && order.user.email %>
                      </div>
                      <div class="text-xs text-gray-500">
                        <%= if order.shipping_name, do: order.shipping_name %>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", status_style(order.status)]}>
                        <%= status_label(order.status) %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="flex flex-col gap-0.5">
                        <%= if order.bux_tokens_burned > 0 do %>
                          <span class="text-xs text-yellow-700"><%= order.bux_tokens_burned %> BUX</span>
                        <% end %>
                        <%= if Decimal.gt?(order.rogue_tokens_sent || Decimal.new(0), 0) do %>
                          <span class="text-xs text-purple-700"><%= format_rogue(order.rogue_tokens_sent) %> ROGUE</span>
                        <% end %>
                        <%= if Decimal.gt?(order.helio_payment_amount || Decimal.new(0), 0) do %>
                          <span class="text-xs text-blue-700">$<%= Decimal.round(order.helio_payment_amount, 2) %> <%= order.helio_payment_currency %></span>
                        <% end %>
                        <%= if order.bux_tokens_burned == 0 and not Decimal.gt?(order.rogue_tokens_sent || Decimal.new(0), 0) and not Decimal.gt?(order.helio_payment_amount || Decimal.new(0), 0) do %>
                          <span class="text-xs text-gray-400">--</span>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      $<%= Decimal.round(order.subtotal, 2) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= Calendar.strftime(order.inserted_at, "%b %d, %Y") %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <.link
                        navigate={~p"/admin/orders/#{order.id}"}
                        class="text-blue-600 hover:text-blue-800 cursor-pointer"
                      >
                        View
                      </.link>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div class="px-6 py-4 bg-gray-50 border-t border-gray-200">
            <p class="text-sm text-gray-600">
              Showing <span class="font-semibold"><%= length(@orders) %></span> orders
              <%= if @status_filter != "all" do %>
                with status "<%= status_label(@status_filter) %>"
              <% end %>
            </p>
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
end
