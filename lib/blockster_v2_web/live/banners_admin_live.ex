defmodule BlocksterV2Web.BannersAdminLive do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Ads
  alias BlocksterV2.Ads.Banner

  @placements [
    {"Listings — Top (Desktop) [home/category/tag]", "homepage_top_desktop"},
    {"Listings — Top (Mobile) [home/category/tag]", "homepage_top_mobile"},
    {"Listings — Inline (Desktop) [home/category/tag]", "homepage_inline_desktop"},
    {"Listings — Inline (Mobile) [home/category/tag]", "homepage_inline_mobile"},
    {"Article — Left Sidebar", "sidebar_left"},
    {"Article — Right Sidebar", "sidebar_right"},
    {"Article — Bottom", "article_bottom"},
    {"Video Player — Top", "video_player_top"},
    {"Play — Left Sidebar", "play_sidebar_left"},
    {"Play — Right Sidebar", "play_sidebar_right"},
    {"Airdrop — Left Sidebar", "airdrop_sidebar_left"},
    {"Airdrop — Right Sidebar", "airdrop_sidebar_right"},
    {"Mobile — Top", "mobile_top"},
    {"Mobile — Mid", "mobile_mid"},
    {"Mobile — Bottom", "mobile_bottom"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:banners, Ads.list_banners())
     |> assign(:editing_banner, nil)
     |> assign(:show_new_form, false)
     |> assign(:form, nil)
     |> assign(:placements, @placements)}
  end

  @impl true
  def handle_event("show_new_form", _, socket) do
    changeset = Banner.changeset(%Banner{is_active: true}, %{})

    {:noreply,
     socket
     |> assign(:show_new_form, true)
     |> assign(:editing_banner, nil)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("cancel", _, socket) do
    {:noreply,
     socket
     |> assign(:show_new_form, false)
     |> assign(:editing_banner, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    banner = Ads.get_banner!(id)
    changeset = Banner.changeset(banner, %{})

    {:noreply,
     socket
     |> assign(:editing_banner, banner)
     |> assign(:show_new_form, false)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"banner" => params}, socket) do
    base = socket.assigns.editing_banner || %Banner{}

    changeset =
      base
      |> Banner.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"banner" => params}, socket) do
    if socket.assigns.editing_banner do
      case Ads.update_banner(socket.assigns.editing_banner, params) do
        {:ok, _banner} ->
          {:noreply,
           socket
           |> put_flash(:info, "Banner updated")
           |> assign(:banners, Ads.list_banners())
           |> assign(:editing_banner, nil)
           |> assign(:form, nil)}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    else
      case Ads.create_banner(params) do
        {:ok, _banner} ->
          {:noreply,
           socket
           |> put_flash(:info, "Banner created")
           |> assign(:banners, Ads.list_banners())
           |> assign(:show_new_form, false)
           |> assign(:form, nil)}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    banner = Ads.get_banner!(id)

    case Ads.toggle_active(banner) do
      {:ok, _} ->
        {:noreply, assign(socket, :banners, Ads.list_banners())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update banner")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    banner = Ads.get_banner!(id)

    case Ads.delete_banner(banner) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Banner deleted")
         |> assign(:banners, Ads.list_banners())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete banner")}
    end
  end

  defp placement_label(value) do
    case Enum.find(@placements, fn {_label, v} -> v == value end) do
      {label, _} -> label
      nil -> value
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 pt-24 pb-12">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
            <div>
              <h1 class="text-2xl font-bold text-gray-900">Ad Banners</h1>
              <p class="mt-1 text-sm text-gray-600">
                Manage banner ads shown in article sidebars and mobile placements.
              </p>
            </div>
            <%= unless @show_new_form || @editing_banner do %>
              <button
                phx-click="show_new_form"
                class="bg-gray-900 hover:bg-black text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer"
              >
                New Banner
              </button>
            <% end %>
          </div>

          <%= if @show_new_form || @editing_banner do %>
            <div class="px-6 py-4 border-b border-gray-200 bg-gray-50">
              <h2 class="text-lg font-semibold text-gray-900 mb-4">
                {if @editing_banner, do: "Edit Banner", else: "New Banner"}
              </h2>
              <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-4">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Name</label>
                    <input
                      type="text"
                      name="banner[name]"
                      value={@form[:name].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                      placeholder="Internal name (e.g. Acme Q2 Right Sidebar)"
                      required
                    />
                    <%= if @form[:name].errors != [] do %>
                      <p class="mt-1 text-sm text-red-600">
                        {Enum.map(@form[:name].errors, fn {msg, _} -> msg end) |> Enum.join(", ")}
                      </p>
                    <% end %>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Placement</label>
                    <select
                      name="banner[placement]"
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900 cursor-pointer"
                      required
                    >
                      <option value="">Select a placement…</option>
                      <%= for {label, value} <- @placements do %>
                        <option value={value} selected={@form[:placement].value == value}>
                          {label}
                        </option>
                      <% end %>
                    </select>
                    <%= if @form[:placement].errors != [] do %>
                      <p class="mt-1 text-sm text-red-600">
                        {Enum.map(@form[:placement].errors, fn {msg, _} -> msg end) |> Enum.join(", ")}
                      </p>
                    <% end %>
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Banner Image</label>
                  <div class="flex items-start gap-4">
                    <img
                      id="banner_image_preview"
                      src={@form[:image_url].value || ""}
                      alt="Banner preview"
                      class={[
                        "h-28 w-auto max-w-[240px] object-contain rounded border border-gray-200 bg-gray-50",
                        if(@form[:image_url].value in [nil, ""], do: "hidden", else: "")
                      ]}
                    />
                    <div class="flex-1 space-y-2">
                      <input
                        type="file"
                        id="banner_image_file"
                        phx-hook="BannerAdminUpload"
                        data-input="banner_image_url_input"
                        data-preview="banner_image_preview"
                        accept="image/*"
                        class="block w-full text-sm text-gray-700 file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-gray-900 file:text-white hover:file:bg-black file:cursor-pointer cursor-pointer"
                      />
                      <p class="text-xs text-gray-500">
                        PNG, JPG, GIF, or WebP. Max 25MB. Animated GIFs supported.
                      </p>
                      <input
                        type="hidden"
                        id="banner_image_url_input"
                        name="banner[image_url]"
                        value={@form[:image_url].value}
                      />
                      <%= if @form[:image_url].value not in [nil, ""] do %>
                        <p class="text-xs text-gray-600 break-all">
                          <span class="font-medium">URL:</span> {@form[:image_url].value}
                        </p>
                      <% end %>
                    </div>
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Link URL</label>
                  <input
                    type="url"
                    name="banner[link_url]"
                    value={@form[:link_url].value}
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                    placeholder="https://example.com"
                  />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Dimensions</label>
                    <input
                      type="text"
                      name="banner[dimensions]"
                      value={@form[:dimensions].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                      placeholder="300x600"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
                    <input
                      type="date"
                      name="banner[start_date]"
                      value={@form[:start_date].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">End Date</label>
                    <input
                      type="date"
                      name="banner[end_date]"
                      value={@form[:end_date].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                    />
                  </div>
                </div>

                <div class="flex items-center gap-2">
                  <input
                    type="hidden"
                    name="banner[is_active]"
                    value="false"
                  />
                  <input
                    type="checkbox"
                    id="banner_is_active"
                    name="banner[is_active]"
                    value="true"
                    checked={@form[:is_active].value in [true, "true"]}
                    class="h-4 w-4 rounded border-gray-300 text-gray-900 focus:ring-gray-900 cursor-pointer"
                  />
                  <label for="banner_is_active" class="text-sm text-gray-700 cursor-pointer">
                    Active
                  </label>
                </div>

                <div class="flex gap-3">
                  <button
                    type="submit"
                    class="bg-gray-900 hover:bg-black text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer"
                  >
                    {if @editing_banner, do: "Update Banner", else: "Create Banner"}
                  </button>
                  <button
                    type="button"
                    phx-click="cancel"
                    class="bg-gray-200 hover:bg-gray-300 text-gray-700 px-4 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer"
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
                    Preview
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Name
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Placement
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Stats
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= if @banners == [] do %>
                  <tr>
                    <td colspan="6" class="px-6 py-12 text-center text-sm text-gray-500">
                      No banners yet. Click "New Banner" to add one.
                    </td>
                  </tr>
                <% end %>
                <%= for banner <- @banners do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if banner.image_url do %>
                        <img
                          src={banner.image_url}
                          alt={banner.name}
                          class="h-12 w-auto max-w-[120px] object-contain rounded border border-gray-200"
                        />
                      <% else %>
                        <div class="h-12 w-20 bg-gray-100 rounded border border-dashed border-gray-300 flex items-center justify-center text-xs text-gray-400">
                          No image
                        </div>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="text-sm font-medium text-gray-900">{banner.name}</div>
                      <%= if banner.link_url do %>
                        <a
                          href={banner.link_url}
                          target="_blank"
                          class="text-xs text-blue-600 hover:underline truncate max-w-[200px] block"
                        >
                          {banner.link_url}
                        </a>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                        {placement_label(banner.placement)}
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <button
                        phx-click="toggle_active"
                        phx-value-id={banner.id}
                        class={[
                          "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium cursor-pointer",
                          if(banner.is_active,
                            do: "bg-green-100 text-green-800 hover:bg-green-200",
                            else: "bg-gray-100 text-gray-600 hover:bg-gray-200"
                          )
                        ]}
                      >
                        {if banner.is_active, do: "Active", else: "Inactive"}
                      </button>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-xs text-gray-600">
                      <div>{banner.impressions} impr.</div>
                      <div>{banner.clicks} clicks</div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <div class="flex gap-3">
                        <button
                          phx-click="edit"
                          phx-value-id={banner.id}
                          class="text-blue-600 hover:text-blue-800 font-medium cursor-pointer"
                        >
                          Edit
                        </button>
                        <button
                          phx-click="delete"
                          phx-value-id={banner.id}
                          data-confirm="Delete this banner permanently?"
                          class="text-red-600 hover:text-red-800 font-medium cursor-pointer"
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
              Total banners: <span class="font-semibold">{length(@banners)}</span>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
