defmodule BlocksterV2Web.ContentAutomationLive.Queue do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.{FeedStore, ContentPublisher, TimeHelper}

  @categories ~w(defi rwa regulation gaming trading token_launches gambling privacy macro_trends investment bitcoin ethereum altcoins nft ai_crypto stablecoins cbdc security_hacks adoption mining fundraising events)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "content_automation")
    end

    socket =
      socket
      |> assign(page_title: "Article Queue")
      |> assign(filter_category: nil, filter_author: nil, sort: :newest)
      |> assign(expanded: MapSet.new(), editing: MapSet.new())
      |> assign(reject_modal: nil, reject_reason: "")
      |> assign(categories: @categories)
      |> assign(queue_entries: [], loading: true)
      |> load_entries()

    {:ok, socket}
  end

  defp load_entries(socket) do
    opts = [
      status: ["pending", "draft", "approved"],
      order: socket.assigns.sort
    ]

    opts = if socket.assigns.filter_category, do: Keyword.put(opts, :category, socket.assigns.filter_category), else: opts
    opts = if socket.assigns.filter_author, do: Keyword.put(opts, :author_id, socket.assigns.filter_author), else: opts

    entries = FeedStore.get_queue_entries(opts)
    assign(socket, queue_entries: entries, loading: false)
  end

  @impl true
  def handle_event("filter", %{"category" => cat}, socket) do
    cat = if cat == "", do: nil, else: cat
    {:noreply, socket |> assign(filter_category: cat) |> load_entries()}
  end

  def handle_event("sort", %{"order" => order}, socket) do
    order = if order == "oldest", do: :oldest, else: :newest
    {:noreply, socket |> assign(sort: order) |> load_entries()}
  end

  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded
    expanded = if MapSet.member?(expanded, id), do: MapSet.delete(expanded, id), else: MapSet.put(expanded, id)
    {:noreply, assign(socket, expanded: expanded)}
  end

  def handle_event("toggle_edit", %{"id" => id}, socket) do
    editing = socket.assigns.editing
    editing = if MapSet.member?(editing, id), do: MapSet.delete(editing, id), else: MapSet.put(editing, id)
    {:noreply, assign(socket, editing: editing)}
  end

  def handle_event("save_edit", %{"id" => id, "title" => title, "excerpt" => excerpt, "category" => category} = params, socket) do
    entry = Enum.find(socket.assigns.queue_entries, &(&1.id == id))

    if entry do
      tags_str = params["tags"] || ""
      tags = tags_str |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

      updated_data =
        entry.article_data
        |> Map.put("title", title)
        |> Map.put("excerpt", excerpt)
        |> Map.put("category", category)
        |> Map.put("tags", tags)

      case FeedStore.update_queue_entry(id, %{article_data: updated_data, status: "draft"}) do
        {:ok, _} ->
          editing = MapSet.delete(socket.assigns.editing, id)
          {:noreply, socket |> assign(editing: editing) |> load_entries() |> put_flash(:info, "Draft saved")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Save failed")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_image", %{"id" => id, "url" => url}, socket) do
    entry = Enum.find(socket.assigns.queue_entries, &(&1.id == id))

    if entry do
      updated_data = Map.put(entry.article_data, "featured_image", url)

      case FeedStore.update_queue_entry(id, %{article_data: updated_data}) do
        {:ok, _} ->
          {:noreply, load_entries(socket)}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Image selection failed")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("preview", %{"id" => id}, socket) do
    entry = FeedStore.get_queue_entry(id) |> BlocksterV2.Repo.preload(:author)

    if entry do
      # If draft post already exists, just redirect to it
      if entry.post_id do
        post = BlocksterV2.Repo.get(BlocksterV2.Blog.Post, entry.post_id)

        if post do
          {:noreply, redirect(socket, to: "/#{post.slug}")}
        else
          # Post was deleted — create a new draft
          create_and_redirect_to_draft(entry, socket)
        end
      else
        create_and_redirect_to_draft(entry, socket)
      end
    else
      {:noreply, put_flash(socket, :error, "Entry not found")}
    end
  end

  defp create_and_redirect_to_draft(entry, socket) do
    case ContentPublisher.create_draft_post(entry) do
      {:ok, post} ->
        {:noreply,
         socket
         |> load_entries()
         |> redirect(to: "/#{post.slug}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Draft creation failed: #{inspect(reason)}")}
    end
  end

  def handle_event("approve", %{"id" => id}, socket) do
    entry = FeedStore.get_queue_entry(id) |> BlocksterV2.Repo.preload(:author)

    case ContentPublisher.publish_queue_entry(entry) do
      {:ok, post} ->
        {:noreply,
         socket
         |> load_entries()
         |> put_flash(:info, "Published: \"#{post.title}\"")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Publish failed: #{inspect(reason)}")}
    end
  end

  def handle_event("open_reject", %{"id" => id}, socket) do
    {:noreply, assign(socket, reject_modal: id, reject_reason: "")}
  end

  def handle_event("close_reject", _params, socket) do
    {:noreply, assign(socket, reject_modal: nil, reject_reason: "")}
  end

  def handle_event("update_reject_reason", %{"reason" => reason}, socket) do
    {:noreply, assign(socket, reject_reason: reason)}
  end

  def handle_event("confirm_reject", _params, socket) do
    id = socket.assigns.reject_modal
    reason = socket.assigns.reject_reason
    reason = if reason == "", do: nil, else: reason

    # Clean up draft post if one was created for preview
    entry = FeedStore.get_queue_entry(id)
    if entry && entry.post_id, do: ContentPublisher.cleanup_draft_post(entry.post_id)

    FeedStore.reject_queue_entry(id, reason)

    {:noreply,
     socket
     |> assign(reject_modal: nil, reject_reason: "")
     |> load_entries()
     |> put_flash(:info, "Article rejected")}
  end

  # PubSub — debounce rapid updates to avoid flashing and state interference
  @impl true
  def handle_info({:content_automation, _, _}, socket) do
    if socket.assigns[:reload_timer] do
      {:noreply, socket}
    else
      timer = Process.send_after(self(), :debounced_reload, 3_000)
      {:noreply, assign(socket, reload_timer: timer)}
    end
  end

  def handle_info(:debounced_reload, socket) do
    {:noreply, socket |> assign(reload_timer: nil) |> load_entries()}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp time_ago(nil), do: ""
  defp time_ago(%NaiveDateTime{} = dt), do: time_ago(DateTime.from_naive!(dt, "Etc/UTC"))
  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp word_count(article_data) do
    case article_data["content"] do
      %{"content" => nodes} when is_list(nodes) ->
        BlocksterV2.ContentAutomation.TipTapBuilder.count_words(article_data["content"])
      _ -> 0
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pt-24 px-4 md:px-8 max-w-7xl mx-auto pb-8">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-haas_medium_65 text-gray-900">Article Queue</h1>
          <p class="text-gray-500 text-sm mt-1"><%= length(@queue_entries) %> articles pending review</p>
        </div>
        <.link navigate={~p"/admin/content"} class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200 cursor-pointer">
          &larr; Dashboard
        </.link>
      </div>

      <%!-- Filters --%>
      <div class="flex items-center gap-4 mb-6">
        <form phx-change="filter">
          <select name="category" class="bg-white border border-gray-300 text-gray-700 rounded-lg px-3 py-2 text-sm cursor-pointer">
            <option value="">All Categories</option>
            <%= for cat <- @categories do %>
              <option value={cat} selected={@filter_category == cat}><%= String.replace(cat, "_", " ") |> String.capitalize() %></option>
            <% end %>
          </select>
        </form>
        <form phx-change="sort">
          <select name="order" class="bg-white border border-gray-300 text-gray-700 rounded-lg px-3 py-2 text-sm cursor-pointer">
            <option value="newest" selected={@sort == :newest}>Newest First</option>
            <option value="oldest" selected={@sort == :oldest}>Oldest First</option>
          </select>
        </form>
      </div>

      <%!-- Queue Entries --%>
      <%= if @queue_entries == [] do %>
        <div class="bg-white rounded-lg shadow p-12 text-center">
          <p class="text-gray-500 text-lg">No articles pending review</p>
          <p class="text-gray-400 text-sm mt-2">New articles will appear here as the pipeline generates them</p>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for entry <- @queue_entries do %>
            <div class="bg-white rounded-lg shadow overflow-hidden">
              <%!-- Card Header --%>
              <div class="p-4">
                <%= if MapSet.member?(@editing, entry.id) do %>
                  <%!-- Inline Edit Mode --%>
                  <form phx-submit="save_edit" class="space-y-3">
                    <input type="hidden" name="id" value={entry.id} />
                    <div>
                      <label class="text-xs text-gray-500 uppercase">Title</label>
                      <input type="text" name="title" value={entry.article_data["title"]} class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded px-3 py-2 text-sm mt-1" />
                    </div>
                    <div>
                      <label class="text-xs text-gray-500 uppercase">Excerpt</label>
                      <textarea name="excerpt" rows="2" class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded px-3 py-2 text-sm mt-1"><%= entry.article_data["excerpt"] %></textarea>
                    </div>
                    <div class="flex gap-3">
                      <div class="flex-1">
                        <label class="text-xs text-gray-500 uppercase">Category</label>
                        <select name="category" class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded px-3 py-2 text-sm mt-1 cursor-pointer">
                          <%= for cat <- @categories do %>
                            <option value={cat} selected={entry.article_data["category"] == cat}><%= String.replace(cat, "_", " ") |> String.capitalize() %></option>
                          <% end %>
                        </select>
                      </div>
                      <div class="flex-1">
                        <label class="text-xs text-gray-500 uppercase">Tags (comma-separated)</label>
                        <input type="text" name="tags" value={Enum.join(entry.article_data["tags"] || [], ", ")} class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded px-3 py-2 text-sm mt-1" />
                      </div>
                    </div>

                    <%!-- Image Candidates --%>
                    <%= if (entry.article_data["image_candidates"] || []) != [] do %>
                      <div>
                        <label class="text-xs text-gray-500 uppercase">Featured Image (click to select)</label>
                        <div class="flex gap-2 mt-1">
                          <%= for candidate <- entry.article_data["image_candidates"] || [] do %>
                            <button
                              type="button"
                              phx-click="select_image"
                              phx-value-id={entry.id}
                              phx-value-url={candidate["url"]}
                              class={"w-24 h-24 rounded-lg overflow-hidden border-2 cursor-pointer #{if entry.article_data["featured_image"] == candidate["url"], do: "border-blue-500", else: "border-gray-300 hover:border-gray-400"}"}
                            >
                              <img src={BlocksterV2.ImageKit.url(candidate["url"], width: 200, height: 200)} class="w-full h-full object-cover" loading="lazy" />
                            </button>
                          <% end %>
                        </div>
                      </div>
                    <% end %>

                    <div class="flex items-center gap-2 pt-2">
                      <button type="submit" class="px-4 py-2 bg-[#CAFC00] text-black rounded text-sm font-medium cursor-pointer hover:bg-[#b8e600]">
                        Save Draft
                      </button>
                      <button type="button" phx-click="toggle_edit" phx-value-id={entry.id} class="px-4 py-2 bg-gray-100 text-gray-700 rounded text-sm cursor-pointer hover:bg-gray-200">
                        Cancel
                      </button>
                    </div>
                  </form>
                <% else %>
                  <%!-- View Mode --%>
                  <div class="flex items-start justify-between gap-4">
                    <%!-- Featured image thumbnail --%>
                    <%= if entry.article_data["featured_image"] do %>
                      <div class="w-16 h-16 rounded-lg overflow-hidden shrink-0">
                        <img src={BlocksterV2.ImageKit.url(entry.article_data["featured_image"], width: 128, height: 128)} class="w-full h-full object-cover" loading="lazy" />
                      </div>
                    <% end %>

                    <div class="flex-1 min-w-0">
                      <h3 class="text-gray-900 font-medium"><%= entry.article_data["title"] %></h3>
                      <div class="flex flex-wrap items-center gap-x-2 gap-y-1 mt-1 text-xs text-gray-500">
                        <span><%= entry.article_data["author_username"] || "Unknown" %></span>
                        <span>&middot;</span>
                        <span><%= entry.article_data["category"] |> to_string() |> String.replace("_", " ") |> String.capitalize() %></span>
                        <span>&middot;</span>
                        <span><%= word_count(entry.article_data) %> words</span>
                        <span>&middot;</span>
                        <span><%= time_ago(entry.inserted_at) %></span>
                        <span class={"ml-1 px-1.5 py-0.5 rounded text-xs #{cond do
                          entry.status == "approved" -> "bg-green-100 text-green-700"
                          entry.status == "draft" -> "bg-blue-100 text-blue-700"
                          true -> "bg-yellow-100 text-yellow-700"
                        end}"}><%= if entry.status == "approved" && entry.scheduled_at, do: "scheduled", else: entry.status %></span>
                        <span class={"ml-1 px-1.5 py-0.5 rounded text-xs #{case entry.content_type do
                          "opinion" -> "bg-purple-100 text-purple-700"
                          "offer" -> "bg-emerald-100 text-emerald-700"
                          _ -> "bg-sky-100 text-sky-700"
                        end}"}><%= (entry.content_type || "news") |> String.capitalize() %></span>
                        <%= if entry.content_type == "offer" && entry.offer_type do %>
                          <span class="ml-1 px-1.5 py-0.5 rounded text-xs bg-emerald-50 text-emerald-600"><%= entry.offer_type |> String.replace("_", " ") %></span>
                        <% end %>
                        <%= if entry.expires_at do %>
                          <span class="ml-1 text-xs text-orange-600">Expires: <%= Calendar.strftime(entry.expires_at, "%b %d") %></span>
                        <% end %>
                        <%= if entry.scheduled_at && entry.status == "approved" do %>
                          <span class="ml-1 text-xs text-blue-600"><%= TimeHelper.format_display(entry.scheduled_at) %></span>
                        <% end %>
                      </div>
                      <%!-- Tags --%>
                      <div class="flex flex-wrap gap-1 mt-2">
                        <%= for tag <- (entry.article_data["tags"] || []) do %>
                          <span class="px-2 py-0.5 bg-gray-100 text-gray-600 rounded text-xs"><%= tag %></span>
                        <% end %>
                      </div>
                    </div>

                    <%!-- Actions --%>
                    <div class="flex items-center gap-2 shrink-0">
                      <button phx-click="toggle_edit" phx-value-id={entry.id} class="px-3 py-1.5 bg-gray-100 text-gray-700 rounded text-xs hover:bg-gray-200 cursor-pointer">
                        Edit
                      </button>
                      <.link navigate={~p"/admin/content/queue/#{entry.id}/edit"} class="px-3 py-1.5 bg-gray-100 text-gray-700 rounded text-xs hover:bg-gray-200 cursor-pointer">
                        Full Edit
                      </.link>
                      <button phx-click="preview" phx-value-id={entry.id} class="px-3 py-1.5 bg-indigo-600 text-white rounded text-xs hover:bg-indigo-700 cursor-pointer">
                        Preview
                      </button>
                      <button phx-click="approve" phx-value-id={entry.id} class="px-3 py-1.5 bg-green-600 text-white rounded text-xs hover:bg-green-700 cursor-pointer">
                        Publish Now
                      </button>
                      <button phx-click="open_reject" phx-value-id={entry.id} class="px-3 py-1.5 bg-red-600 text-white rounded text-xs hover:bg-red-700 cursor-pointer">
                        Reject
                      </button>
                    </div>
                  </div>

                  <%!-- Expandable Preview --%>
                  <div class="mt-2">
                    <p class="text-gray-500 text-sm"><%= entry.article_data["excerpt"] %></p>
                    <button phx-click="toggle_expand" phx-value-id={entry.id} class="text-xs text-blue-600 mt-2 cursor-pointer hover:underline">
                      <%= if MapSet.member?(@expanded, entry.id), do: "Hide preview ▲", else: "Show preview ▼" %>
                    </button>
                    <%= if MapSet.member?(@expanded, entry.id) do %>
                      <div id={"preview-#{entry.id}"} phx-hook="TwitterWidgets" class="mt-3 p-4 bg-gray-50 rounded-lg border border-gray-200 prose prose-sm max-w-none">
                        <%= BlocksterV2Web.PostLive.TipTapRenderer.render_content(entry.article_data["content"]) %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Reject Modal --%>
      <%= if @reject_modal do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
          <div class="bg-white rounded-xl shadow-xl p-6 w-full max-w-md" phx-click-away="close_reject">
            <h3 class="text-gray-900 text-lg font-haas_medium_65 mb-4">Reject Article</h3>
            <form phx-change="update_reject_reason">
              <label class="text-sm text-gray-500">Reason (optional)</label>
              <textarea
                name="reason"
                rows="3"
                placeholder="Too similar to yesterday's piece..."
                class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded px-3 py-2 text-sm mt-1"
              ><%= @reject_reason %></textarea>
            </form>
            <div class="flex items-center gap-3 mt-4">
              <button phx-click="close_reject" class="px-4 py-2 bg-gray-100 text-gray-700 rounded text-sm cursor-pointer hover:bg-gray-200">Cancel</button>
              <button phx-click="confirm_reject" class="px-4 py-2 bg-red-600 text-white rounded text-sm cursor-pointer hover:bg-red-700">Reject Article</button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
