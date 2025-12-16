defmodule BlocksterV2Web.CategoriesAdminLive do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.Tag

  @impl true
  def mount(_params, _session, socket) do
    categories = Blog.list_categories()

    {:ok,
     socket
     |> assign(:categories, categories)
     |> assign(:editing_category, nil)
     |> assign(:show_new_form, false)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("show_new_form", _, socket) do
    changeset = Blog.change_category(%Blog.Category{})

    {:noreply,
     socket
     |> assign(:show_new_form, true)
     |> assign(:editing_category, nil)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("cancel", _, socket) do
    {:noreply,
     socket
     |> assign(:show_new_form, false)
     |> assign(:editing_category, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    category = Blog.get_category!(id)
    changeset = Blog.change_category(category)

    {:noreply,
     socket
     |> assign(:editing_category, category)
     |> assign(:show_new_form, false)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"category" => category_params}, socket) do
    if socket.assigns.editing_category do
      # Update existing category
      case Blog.update_category(socket.assigns.editing_category, category_params) do
        {:ok, _category} ->
          {:noreply,
           socket
           |> put_flash(:info, "Category updated successfully")
           |> assign(:categories, Blog.list_categories())
           |> assign(:editing_category, nil)
           |> assign(:form, nil)}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    else
      # Create new category
      case Blog.create_category(category_params) do
        {:ok, _category} ->
          {:noreply,
           socket
           |> put_flash(:info, "Category created successfully")
           |> assign(:categories, Blog.list_categories())
           |> assign(:show_new_form, false)
           |> assign(:form, nil)}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    category = Blog.get_category!(id)

    case Blog.delete_category(category) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category deleted successfully")
         |> assign(:categories, Blog.list_categories())}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete category")}
    end
  end

  @impl true
  def handle_event("generate_slug", %{"category" => %{"name" => name}}, socket) do
    slug = Tag.generate_slug(name)

    form =
      if socket.assigns.editing_category do
        Blog.change_category(socket.assigns.editing_category, %{"name" => name, "slug" => slug})
      else
        Blog.change_category(%Blog.Category{}, %{"name" => name, "slug" => slug})
      end

    {:noreply, assign(socket, :form, to_form(form))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
            <div>
              <h1 class="text-2xl font-bold text-gray-900">Category Management</h1>
              <p class="mt-1 text-sm text-gray-600">Create, edit, and delete categories</p>
            </div>
            <%= unless @show_new_form || @editing_category do %>
              <button
                phx-click="show_new_form"
                class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors"
              >
                New Category
              </button>
            <% end %>
          </div>

          <%= if @show_new_form || @editing_category do %>
            <div class="px-6 py-4 border-b border-gray-200 bg-gray-50">
              <h2 class="text-lg font-semibold text-gray-900 mb-4">
                <%= if @editing_category, do: "Edit Category", else: "New Category" %>
              </h2>
              <.form for={@form} phx-submit="save" phx-change="generate_slug" class="space-y-4">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Name</label>
                    <input
                      type="text"
                      name="category[name]"
                      value={@form[:name].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      placeholder="Category name"
                      required
                    />
                    <%= if @form[:name].errors != [] do %>
                      <p class="mt-1 text-sm text-red-600">
                        <%= Enum.map(@form[:name].errors, fn {msg, _} -> msg end) |> Enum.join(", ") %>
                      </p>
                    <% end %>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Slug</label>
                    <input
                      type="text"
                      name="category[slug]"
                      value={@form[:slug].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      placeholder="category-slug"
                      required
                    />
                    <%= if @form[:slug].errors != [] do %>
                      <p class="mt-1 text-sm text-red-600">
                        <%= Enum.map(@form[:slug].errors, fn {msg, _} -> msg end) |> Enum.join(", ") %>
                      </p>
                    <% end %>
                  </div>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Description (optional)</label>
                  <textarea
                    name="category[description]"
                    rows="3"
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    placeholder="Category description"
                  ><%= @form[:description].value %></textarea>
                </div>
                <div class="flex gap-3">
                  <button
                    type="submit"
                    class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors"
                  >
                    <%= if @editing_category, do: "Update Category", else: "Create Category" %>
                  </button>
                  <button
                    type="button"
                    phx-click="cancel"
                    class="bg-gray-200 hover:bg-gray-300 text-gray-700 px-4 py-2 rounded-lg text-sm font-medium transition-colors"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            </div>
          <% end %>

          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Name
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Slug
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Description
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for category <- @categories do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class="text-sm font-medium text-gray-900"><%= category.name %></span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <code class="text-xs text-gray-600 bg-gray-100 px-2 py-1 rounded"><%= category.slug %></code>
                    </td>
                    <td class="px-6 py-4">
                      <span class="text-sm text-gray-500 truncate max-w-xs block">
                        <%= category.description || "—" %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <div class="flex gap-2">
                        <button
                          phx-click="edit"
                          phx-value-id={category.id}
                          class="text-blue-600 hover:text-blue-800 font-medium"
                        >
                          Edit
                        </button>
                        <button
                          phx-click="delete"
                          phx-value-id={category.id}
                          data-confirm="Are you sure you want to delete this category? Posts with this category will no longer have a category assigned."
                          class="text-red-600 hover:text-red-800 font-medium"
                        >
                          Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div class="px-6 py-4 bg-gray-50 border-t border-gray-200">
            <p class="text-sm text-gray-600">
              Total categories: <span class="font-semibold"><%= length(@categories) %></span>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
