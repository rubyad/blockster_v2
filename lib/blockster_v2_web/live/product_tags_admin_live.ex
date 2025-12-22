defmodule BlocksterV2Web.ProductTagsAdminLive do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Shop

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      tags = Shop.list_tags()

      {:ok,
       socket
       |> assign(:tags, tags)
       |> assign(:page_title, "Manage Product Tags")
       |> assign(:show_form, false)
       |> assign(:editing_tag, nil)
       |> assign(:form_name, "")}
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
     |> assign(:editing_tag, nil)
     |> assign(:form_name, "")}
  end

  @impl true
  def handle_event("show_edit_form", %{"id" => id}, socket) do
    tag = Shop.get_tag!(id)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_tag, tag)
     |> assign(:form_name, tag.name)}
  end

  @impl true
  def handle_event("cancel_form", _, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_tag, nil)}
  end

  @impl true
  def handle_event("update_form", %{"name" => name}, socket) do
    {:noreply, assign(socket, :form_name, name)}
  end

  @impl true
  def handle_event("save_tag", %{"name" => name}, socket) do
    attrs = %{name: name, slug: slugify(name)}

    result =
      case socket.assigns.editing_tag do
        nil -> Shop.create_tag(attrs)
        tag -> Shop.update_tag(tag, attrs)
      end

    case result do
      {:ok, _tag} ->
        tags = Shop.list_tags()

        {:noreply,
         socket
         |> assign(:tags, tags)
         |> assign(:show_form, false)
         |> assign(:editing_tag, nil)
         |> put_flash(:info, "Tag saved successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save tag.")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    tag = Shop.get_tag!(id)

    case Shop.delete_tag(tag) do
      {:ok, _} ->
        tags = Shop.list_tags()

        {:noreply,
         socket
         |> assign(:tags, tags)
         |> put_flash(:info, "Tag deleted successfully.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete tag.")}
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
        <h1 class="text-3xl font-bold text-gray-900">Product Tags</h1>
        <button
          phx-click="show_new_form"
          class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-medium transition-colors"
        >
          + New Tag
        </button>
      </div>

      <%= if @show_form do %>
        <div class="bg-white shadow-md rounded-lg p-6 mb-8">
          <h2 class="text-xl font-semibold mb-4">
            <%= if @editing_tag, do: "Edit Tag", else: "New Tag" %>
          </h2>
          <form phx-submit="save_tag" phx-change="update_form" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Name *</label>
              <input
                type="text"
                name="name"
                value={@form_name}
                placeholder="Tag name"
                required
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-blue-500 focus:border-blue-500"
              />
            </div>
            <div class="flex gap-3">
              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium"
              >
                <%= if @editing_tag, do: "Update", else: "Create" %>
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

      <%= if Enum.empty?(@tags) do %>
        <div class="text-center py-12 bg-gray-50 rounded-lg">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No tags</h3>
          <p class="mt-1 text-sm text-gray-500">Get started by creating a new tag.</p>
        </div>
      <% else %>
        <div class="bg-white shadow-md rounded-lg overflow-hidden">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Slug</th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for tag <- @tags do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    <%= tag.name %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= tag.slug %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium space-x-2">
                    <button
                      phx-click="show_edit_form"
                      phx-value-id={tag.id}
                      class="text-blue-600 hover:text-blue-900"
                    >
                      Edit
                    </button>
                    <button
                      phx-click="delete"
                      phx-value-id={tag.id}
                      data-confirm="Are you sure you want to delete this tag?"
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
