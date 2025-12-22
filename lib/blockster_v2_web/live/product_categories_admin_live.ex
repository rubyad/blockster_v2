defmodule BlocksterV2Web.ProductCategoriesAdminLive do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Shop

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      categories = Shop.list_categories()

      {:ok,
       socket
       |> assign(:categories, categories)
       |> assign(:page_title, "Manage Product Categories")
       |> assign(:show_form, false)
       |> assign(:editing_category, nil)
       |> assign(:form_name, "")
       |> assign(:form_description, "")}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be an admin to access this page.")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("show_new_form", _, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_category, nil)
     |> assign(:form_name, "")
     |> assign(:form_description, "")}
  end

  @impl true
  def handle_event("show_edit_form", %{"id" => id}, socket) do
    category = Shop.get_category!(id)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_category, category)
     |> assign(:form_name, category.name)
     |> assign(:form_description, category.description || "")}
  end

  @impl true
  def handle_event("cancel_form", _, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_category, nil)}
  end

  @impl true
  def handle_event("update_form", %{"name" => name, "description" => description}, socket) do
    {:noreply,
     socket
     |> assign(:form_name, name)
     |> assign(:form_description, description)}
  end

  @impl true
  def handle_event("save_category", %{"name" => name, "description" => description}, socket) do
    attrs = %{name: name, slug: slugify(name), description: description}

    result =
      case socket.assigns.editing_category do
        nil -> Shop.create_category(attrs)
        category -> Shop.update_category(category, attrs)
      end

    case result do
      {:ok, _category} ->
        categories = Shop.list_categories()

        {:noreply,
         socket
         |> assign(:categories, categories)
         |> assign(:show_form, false)
         |> assign(:editing_category, nil)
         |> put_flash(:info, "Category saved successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save category.")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    category = Shop.get_category!(id)

    case Shop.delete_category(category) do
      {:ok, _} ->
        categories = Shop.list_categories()

        {:noreply,
         socket
         |> assign(:categories, categories)
         |> put_flash(:info, "Category deleted successfully.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete category.")}
    end
  end

  defp slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp slugify(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 pt-24 pb-8">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Product Categories</h1>
        <button
          phx-click="show_new_form"
          class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
        >
          + New Category
        </button>
      </div>

      <%= if @show_form do %>
        <div class="bg-white shadow-md rounded-lg p-6 mb-8">
          <h2 class="text-xl font-semibold mb-4">
            <%= if @editing_category, do: "Edit Category", else: "New Category" %>
          </h2>
          <form phx-submit="save_category" phx-change="update_form" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Name *</label>
              <input
                type="text"
                name="name"
                value={@form_name}
                placeholder="Category name"
                required
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-blue-500 focus:border-blue-500"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Description</label>
              <textarea
                name="description"
                rows="3"
                placeholder="Category description (optional)"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-blue-500 focus:border-blue-500"
              ><%= @form_description %></textarea>
            </div>
            <div class="flex gap-3">
              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium"
              >
                <%= if @editing_category, do: "Update", else: "Create" %>
              </button>
              <button
                type="button"
                phx-click="cancel_form"
                class="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <%= if Enum.empty?(@categories) do %>
        <div class="text-center py-12 bg-gray-50 rounded-lg">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No categories</h3>
          <p class="mt-1 text-sm text-gray-500">Get started by creating a new category.</p>
        </div>
      <% else %>
        <div class="bg-white shadow-md rounded-lg overflow-hidden">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Slug</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Description</th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for category <- @categories do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    <%= category.name %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= category.slug %>
                  </td>
                  <td class="px-6 py-4 text-sm text-gray-500 max-w-xs truncate">
                    <%= category.description || "—" %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium space-x-2">
                    <button
                      phx-click="show_edit_form"
                      phx-value-id={category.id}
                      class="text-blue-600 hover:text-blue-900"
                    >
                      Edit
                    </button>
                    <button
                      phx-click="delete"
                      phx-value-id={category.id}
                      data-confirm="Are you sure you want to delete this category?"
                      class="text-red-600 hover:text-red-900"
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
