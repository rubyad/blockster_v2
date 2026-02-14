defmodule BlocksterV2Web.ContentAutomationLive.Authors do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.{AuthorRotator, FeedStore}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Author Personas")
      |> assign(authors: [], post_counts: %{}, loading: true)
      |> start_async(:load_data, fn -> load_author_data() end)

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_data, {:ok, data}, socket) do
    {:noreply, assign(socket, authors: data.authors, post_counts: data.post_counts, loading: false)}
  end

  def handle_async(:load_data, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  defp load_author_data do
    personas = AuthorRotator.personas()
    post_counts = FeedStore.count_posts_by_author()

    # Resolve user IDs for each persona
    authors =
      Enum.map(personas, fn persona ->
        user =
          BlocksterV2.Accounts.User
          |> BlocksterV2.Repo.get_by(email: persona.email)

        Map.put(persona, :user, user)
      end)

    %{authors: authors, post_counts: post_counts}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pt-24 px-4 md:px-8 max-w-7xl mx-auto pb-8">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-haas_medium_65 text-gray-900">Author Personas</h1>
          <p class="text-gray-500 text-sm mt-1"><%= length(@authors) %> personas configured</p>
        </div>
        <.link navigate={~p"/admin/content"} class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200 cursor-pointer">
          &larr; Dashboard
        </.link>
      </div>

      <%= if @loading do %>
        <div class="bg-white rounded-lg shadow p-8 text-center">
          <p class="text-gray-500 animate-pulse">Loading authors...</p>
        </div>
      <% else %>
        <div class="bg-white rounded-lg shadow overflow-hidden">
          <table class="w-full">
            <thead>
              <tr class="border-b border-gray-200">
                <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Author</th>
                <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Bio</th>
                <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Categories</th>
                <th class="text-right text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Posts</th>
                <th class="text-right text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Status</th>
              </tr>
            </thead>
            <tbody>
              <%= for author <- @authors do %>
                <tr class="border-b border-gray-100 hover:bg-gray-50">
                  <td class="px-4 py-3">
                    <p class="text-gray-900 text-sm font-medium"><%= author.username %></p>
                    <p class="text-gray-400 text-xs"><%= author.email %></p>
                  </td>
                  <td class="px-4 py-3">
                    <p class="text-gray-600 text-sm max-w-xs"><%= author.bio %></p>
                  </td>
                  <td class="px-4 py-3">
                    <div class="flex flex-wrap gap-1">
                      <%= for cat <- author.categories do %>
                        <span class="px-1.5 py-0.5 bg-gray-100 text-gray-600 rounded text-xs"><%= cat %></span>
                      <% end %>
                    </div>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <span class="text-gray-900 text-sm font-medium">
                      <%= if author.user, do: Map.get(@post_counts, author.user.id, 0), else: "—" %>
                    </span>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <%= if author.user do %>
                      <span class="px-2 py-0.5 bg-green-100 text-green-700 rounded text-xs">Active</span>
                    <% else %>
                      <span class="px-2 py-0.5 bg-red-100 text-red-700 rounded text-xs">No User</span>
                    <% end %>
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
