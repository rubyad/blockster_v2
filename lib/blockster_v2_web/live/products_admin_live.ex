defmodule BlocksterV2Web.ProductsAdminLive do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Shop

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      products = Shop.list_products(preload: [:images, :hub, :categories], order_by: [desc: :inserted_at])

      {:ok,
       socket
       |> assign(:products, products)
       |> assign(:page_title, "Manage Products")}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be an admin to access this page.")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = Shop.get_product!(id)
    {:ok, _} = Shop.delete_product(product)

    products = Shop.list_products(preload: [:images, :hub, :categories], order_by: [desc: :inserted_at])

    {:noreply,
     socket
     |> assign(:products, products)
     |> put_flash(:info, "Product deleted successfully.")}
  end

  @impl true
  def handle_event("toggle_status", %{"id" => id}, socket) do
    product = Shop.get_product!(id)

    new_status =
      case product.status do
        "active" -> "draft"
        "draft" -> "active"
        _ -> "active"
      end

    case Shop.update_product(product, %{status: new_status}) do
      {:ok, _updated_product} ->
        products = Shop.list_products(preload: [:images, :hub, :categories], order_by: [desc: :inserted_at])

        {:noreply,
         socket
         |> assign(:products, products)
         |> put_flash(:info, "Product status updated successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update product status.")}
    end
  end

  defp get_first_image(product) do
    case product.images do
      [first | _] -> first.src
      _ -> "https://via.placeholder.com/100x100?text=No+Image"
    end
  end

  defp status_badge(status) do
    case status do
      "active" ->
        assigns = %{}

        ~H"""
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
          Active
        </span>
        """

      "archived" ->
        assigns = %{}

        ~H"""
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
          Archived
        </span>
        """

      _ ->
        assigns = %{}

        ~H"""
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
          Draft
        </span>
        """
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 pt-24 pb-8">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Manage Products</h1>
        <.link
          navigate={~p"/admin/products/new"}
          class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
        >
          + New Product
        </.link>
      </div>

      <%= if Enum.empty?(@products) do %>
        <div class="text-center py-12 bg-gray-50 rounded-lg">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No products</h3>
          <p class="mt-1 text-sm text-gray-500">Get started by creating a new product.</p>
          <div class="mt-6">
            <.link
              navigate={~p"/admin/products/new"}
              class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
            >
              + New Product
            </.link>
          </div>
        </div>
      <% else %>
        <div class="bg-white shadow-md rounded-lg overflow-hidden">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Product</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Hub</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">BUX Discount</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Hub Token Discount</th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for product <- @products do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="flex items-center">
                      <div class="flex-shrink-0 h-12 w-12">
                        <img class="h-12 w-12 rounded-lg object-cover" src={get_first_image(product)} alt={product.title} />
                      </div>
                      <div class="ml-4">
                        <.link navigate={~p"/shop/#{product.handle}"} class="text-sm font-medium text-gray-900 max-w-xs truncate block hover:text-blue-600">
                          <%= product.title %>
                        </.link>
                        <div class="text-sm text-gray-500"><%= product.handle %></div>
                      </div>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <%= status_badge(product.status) %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= if product.hub, do: product.hub.name, else: "—" %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= product.bux_max_discount %>%
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= product.hub_token_max_discount %>%
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium space-x-2">
                    <button
                      phx-click="toggle_status"
                      phx-value-id={product.id}
                      class="cursor-pointer text-indigo-600 hover:text-indigo-900"
                    >
                      <%= if product.status == "active", do: "Unpublish", else: "Publish" %>
                    </button>
                    <.link
                      navigate={~p"/admin/products/#{product.id}/edit"}
                      class="cursor-pointer text-blue-600 hover:text-blue-900"
                    >
                      Edit
                    </.link>
                    <button
                      phx-click="delete"
                      phx-value-id={product.id}
                      data-confirm="Are you sure you want to delete this product?"
                      class="cursor-pointer text-red-600 hover:text-red-900"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end
end
