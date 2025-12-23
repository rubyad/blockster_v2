defmodule BlocksterV2Web.ArtistsAdminLive do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Shop
  alias BlocksterV2.Shop.Artist

  @impl true
  def mount(_params, _session, socket) do
    artists = Shop.list_artists()

    {:ok,
     socket
     |> assign(:artists, artists)
     |> assign(:editing_artist, nil)
     |> assign(:show_new_form, false)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("show_new_form", _, socket) do
    changeset = Shop.change_artist(%Artist{})

    {:noreply,
     socket
     |> assign(:show_new_form, true)
     |> assign(:editing_artist, nil)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("cancel", _, socket) do
    {:noreply,
     socket
     |> assign(:show_new_form, false)
     |> assign(:editing_artist, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    artist = Shop.get_artist!(id)
    changeset = Shop.change_artist(artist)

    {:noreply,
     socket
     |> assign(:editing_artist, artist)
     |> assign(:show_new_form, false)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"artist" => artist_params}, socket) do
    if socket.assigns.editing_artist do
      case Shop.update_artist(socket.assigns.editing_artist, artist_params) do
        {:ok, _artist} ->
          {:noreply,
           socket
           |> put_flash(:info, "Artist updated successfully")
           |> assign(:artists, Shop.list_artists())
           |> assign(:editing_artist, nil)
           |> assign(:form, nil)}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    else
      case Shop.create_artist(artist_params) do
        {:ok, _artist} ->
          {:noreply,
           socket
           |> put_flash(:info, "Artist created successfully")
           |> assign(:artists, Shop.list_artists())
           |> assign(:show_new_form, false)
           |> assign(:form, nil)}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    artist = Shop.get_artist!(id)

    case Shop.delete_artist(artist) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Artist deleted successfully")
         |> assign(:artists, Shop.list_artists())}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete artist")}
    end
  end

  @impl true
  def handle_event("generate_slug", %{"artist" => %{"name" => name}}, socket) do
    slug = generate_slug(name)

    form =
      if socket.assigns.editing_artist do
        Shop.change_artist(socket.assigns.editing_artist, %{"name" => name, "slug" => slug})
      else
        Shop.change_artist(%Artist{}, %{"name" => name, "slug" => slug})
      end

    {:noreply, assign(socket, :form, to_form(form))}
  end

  defp generate_slug(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp generate_slug(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 pt-24 pb-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
            <div>
              <h1 class="text-2xl font-bold text-gray-900">Artist Management</h1>
              <p class="mt-1 text-sm text-gray-600">Create, edit, and delete artists</p>
            </div>
            <%= unless @show_new_form || @editing_artist do %>
              <button
                phx-click="show_new_form"
                class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer"
              >
                New Artist
              </button>
            <% end %>
          </div>

          <%= if @show_new_form || @editing_artist do %>
            <div class="px-6 py-4 border-b border-gray-200 bg-gray-50">
              <h2 class="text-lg font-semibold text-gray-900 mb-4">
                <%= if @editing_artist, do: "Edit Artist", else: "New Artist" %>
              </h2>
              <.form for={@form} phx-submit="save" phx-change="generate_slug" class="space-y-4">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Name *</label>
                    <input
                      type="text"
                      name="artist[name]"
                      value={@form[:name].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      placeholder="Artist name"
                      required
                    />
                    <%= if @form[:name].errors != [] do %>
                      <p class="mt-1 text-sm text-red-600">
                        <%= Enum.map(@form[:name].errors, fn {msg, _} -> msg end) |> Enum.join(", ") %>
                      </p>
                    <% end %>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Slug *</label>
                    <input
                      type="text"
                      name="artist[slug]"
                      value={@form[:slug].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      placeholder="artist-slug"
                      required
                    />
                    <%= if @form[:slug].errors != [] do %>
                      <p class="mt-1 text-sm text-red-600">
                        <%= Enum.map(@form[:slug].errors, fn {msg, _} -> msg end) |> Enum.join(", ") %>
                      </p>
                    <% end %>
                  </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Artist Image</label>
                    <div class="artist-image-upload">
                      <div class="flex items-center gap-4">
                        <div class="image-preview-container">
                          <%= if @form[:image].value && @form[:image].value != "" do %>
                            <img src={@form[:image].value} class="w-20 h-20 rounded-full object-cover border border-gray-300" alt="Artist preview" />
                          <% else %>
                            <div class="w-20 h-20 rounded-full bg-gray-100 border-2 border-dashed border-gray-300 flex items-center justify-center">
                              <svg class="w-8 h-8 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                              </svg>
                            </div>
                          <% end %>
                        </div>
                        <div class="flex-1">
                          <label class="flex items-center justify-center px-4 py-2 bg-white border border-gray-300 rounded-lg cursor-pointer hover:bg-gray-50 transition-colors">
                            <svg class="w-5 h-5 mr-2 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                            </svg>
                            <span class="text-sm text-gray-600">Upload Image</span>
                            <input
                              type="file"
                              accept="image/*"
                              class="hidden"
                              phx-hook="ArtistImageUpload"
                              id={"artist-image-upload-#{if @editing_artist, do: @editing_artist.id, else: "new"}"}
                            />
                          </label>
                          <p class="upload-status hidden text-xs text-gray-500 mt-1 text-center"></p>
                        </div>
                      </div>
                      <input
                        type="hidden"
                        name="artist[image]"
                        value={@form[:image].value}
                      />
                    </div>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Website</label>
                    <input
                      type="text"
                      name="artist[website]"
                      value={@form[:website].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      placeholder="https://artist-website.com"
                    />
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Description</label>
                  <textarea
                    name="artist[description]"
                    rows="3"
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    placeholder="Artist description"
                  ><%= @form[:description].value %></textarea>
                </div>

                <!-- Social URLs -->
                <div class="border-t pt-4 mt-4">
                  <h3 class="text-md font-medium text-gray-900 mb-3">Social Links</h3>
                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Twitter/X</label>
                      <input
                        type="text"
                        name="artist[twitter_url]"
                        value={@form[:twitter_url].value}
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                        placeholder="https://x.com/..."
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Instagram</label>
                      <input
                        type="text"
                        name="artist[instagram_url]"
                        value={@form[:instagram_url].value}
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                        placeholder="https://instagram.com/..."
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">YouTube</label>
                      <input
                        type="text"
                        name="artist[youtube_url]"
                        value={@form[:youtube_url].value}
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                        placeholder="https://youtube.com/..."
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">TikTok</label>
                      <input
                        type="text"
                        name="artist[tiktok_url]"
                        value={@form[:tiktok_url].value}
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                        placeholder="https://tiktok.com/..."
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Discord</label>
                      <input
                        type="text"
                        name="artist[discord_url]"
                        value={@form[:discord_url].value}
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                        placeholder="https://discord.gg/..."
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Telegram</label>
                      <input
                        type="text"
                        name="artist[telegram_url]"
                        value={@form[:telegram_url].value}
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                        placeholder="https://t.me/..."
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">LinkedIn</label>
                      <input
                        type="text"
                        name="artist[linkedin_url]"
                        value={@form[:linkedin_url].value}
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                        placeholder="https://linkedin.com/..."
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Reddit</label>
                      <input
                        type="text"
                        name="artist[reddit_url]"
                        value={@form[:reddit_url].value}
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                        placeholder="https://reddit.com/..."
                      />
                    </div>
                  </div>
                </div>

                <div class="flex gap-3 pt-4">
                  <button
                    type="submit"
                    class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer"
                  >
                    <%= if @editing_artist, do: "Update Artist", else: "Create Artist" %>
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
                    Artist
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Slug
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Website
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Socials
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for artist <- @artists do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="flex items-center">
                        <%= if artist.image do %>
                          <img src={artist.image} alt={artist.name} class="w-10 h-10 rounded-full object-cover mr-3" />
                        <% else %>
                          <div class="w-10 h-10 rounded-full bg-gray-200 flex items-center justify-center mr-3">
                            <span class="text-gray-500 font-medium"><%= String.first(artist.name) %></span>
                          </div>
                        <% end %>
                        <span class="text-sm font-medium text-gray-900"><%= artist.name %></span>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <code class="text-xs text-gray-600 bg-gray-100 px-2 py-1 rounded"><%= artist.slug %></code>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if artist.website do %>
                        <a href={artist.website} target="_blank" class="text-sm text-blue-600 hover:underline cursor-pointer">
                          <%= artist.website |> String.replace(~r/https?:\/\//, "") |> String.slice(0..30) %><%= if String.length(artist.website) > 30, do: "..." %>
                        </a>
                      <% else %>
                        <span class="text-sm text-gray-400">—</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="flex gap-2">
                        <%= if artist.twitter_url do %>
                          <a href={artist.twitter_url} target="_blank" class="text-gray-400 hover:text-gray-600 cursor-pointer" title="Twitter/X">𝕏</a>
                        <% end %>
                        <%= if artist.instagram_url do %>
                          <a href={artist.instagram_url} target="_blank" class="text-gray-400 hover:text-pink-500 cursor-pointer" title="Instagram">IG</a>
                        <% end %>
                        <%= if artist.youtube_url do %>
                          <a href={artist.youtube_url} target="_blank" class="text-gray-400 hover:text-red-500 cursor-pointer" title="YouTube">YT</a>
                        <% end %>
                        <%= if artist.discord_url do %>
                          <a href={artist.discord_url} target="_blank" class="text-gray-400 hover:text-indigo-500 cursor-pointer" title="Discord">DC</a>
                        <% end %>
                        <% social_count = Enum.count([artist.twitter_url, artist.instagram_url, artist.youtube_url, artist.discord_url, artist.telegram_url, artist.tiktok_url, artist.linkedin_url, artist.reddit_url], & &1) %>
                        <%= if social_count == 0 do %>
                          <span class="text-sm text-gray-400">—</span>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <div class="flex gap-2">
                        <button
                          phx-click="edit"
                          phx-value-id={artist.id}
                          class="text-blue-600 hover:text-blue-800 font-medium cursor-pointer"
                        >
                          Edit
                        </button>
                        <button
                          phx-click="delete"
                          phx-value-id={artist.id}
                          data-confirm="Are you sure you want to delete this artist? Products with this artist will no longer have an artist assigned."
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
              Total artists: <span class="font-semibold"><%= length(@artists) %></span>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
