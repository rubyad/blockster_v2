defmodule BlocksterV2Web.ContentAutomationLive.EditArticle do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.{FeedStore, ContentPublisher, EditorialFeedback, TimeHelper}
  alias BlocksterV2.Blog

  @memory_categories ~w(global tone terminology topics formatting)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    entry = FeedStore.get_queue_entry(id) |> BlocksterV2.Repo.preload(:author)

    if is_nil(entry) do
      {:ok, socket |> put_flash(:error, "Article not found") |> push_navigate(to: ~p"/admin/content/queue")}
    else
      revisions = EditorialFeedback.get_revision_history(entry.id)
      memories = EditorialFeedback.list_memories()
      db_categories = Blog.list_categories()
      available_tags = Blog.list_tags() |> Enum.map(& &1.name)

      # Resolve current category — article stores an internal key (e.g. "defi")
      # that ContentPublisher maps to a DB slug. Find the matching DB category.
      current_category_slug = resolve_article_category_slug(entry.article_data["category"])

      socket =
        socket
        |> assign(page_title: "Edit Article")
        |> assign(entry: entry)
        |> assign(db_categories: db_categories, memory_categories: @memory_categories)
        |> assign(
          title: entry.article_data["title"] || "",
          excerpt: entry.article_data["excerpt"] || "",
          category: current_category_slug,
          tags: entry.article_data["tags"] || [],
          featured_image: entry.article_data["featured_image"],
          image_candidates: entry.article_data["image_candidates"] || [],
          available_tags: available_tags,
          filtered_tags: available_tags,
          tag_search: "",
          promotional_tweet: entry.article_data["promotional_tweet"] || "",
          tweet_approved: entry.article_data["tweet_approved"] == true,
          scheduled_at: entry.scheduled_at
        )
        |> assign(
          revising: false,
          revisions: revisions,
          memories: memories
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("update_field", %{"field" => "title", "value" => value}, socket) do
    {:noreply, assign(socket, title: value)}
  end

  def handle_event("update_field", %{"field" => "excerpt", "value" => value}, socket) do
    {:noreply, assign(socket, excerpt: value)}
  end

  def handle_event("update_tweet", %{"value" => value}, socket) do
    {:noreply, assign(socket, promotional_tweet: value)}
  end

  def handle_event("toggle_tweet_approved", _params, socket) do
    {:noreply, assign(socket, tweet_approved: !socket.assigns.tweet_approved)}
  end

  def handle_event("update_scheduled_at", params, socket) do
    # phx-change on standalone input sends %{"value" => ...}
    # phx-click clear button sends %{"value" => ""}
    value = params["value"] || params["scheduled_at"] || ""

    if value == "" do
      {:noreply, assign(socket, scheduled_at: nil)}
    else
      # Input is in EST — convert to UTC for storage
      # datetime-local may send "YYYY-MM-DDTHH:MM" or "YYYY-MM-DDTHH:MM:SS"
      normalized = if String.length(value) == 16, do: value <> ":00", else: value

      case NaiveDateTime.from_iso8601(normalized) do
        {:ok, naive} ->
          utc_dt = TimeHelper.est_to_utc(naive)
          {:noreply, assign(socket, scheduled_at: utc_dt)}
        _ ->
          {:noreply, socket}
      end
    end
  end

  def handle_event("update_offer_field", %{"field" => field, "value" => value}, socket) do
    entry = socket.assigns.entry
    updates = case field do
      "expires_at" when value != "" ->
        case NaiveDateTime.from_iso8601(value <> ":00") do
          {:ok, naive} -> %{expires_at: DateTime.from_naive!(naive, "Etc/UTC")}
          _ -> %{}
        end
      "expires_at" -> %{expires_at: nil}
      f when f in ~w(cta_url cta_text offer_type) -> %{String.to_existing_atom(f) => value}
      _ -> %{}
    end

    if map_size(updates) > 0 do
      {:ok, updated} = FeedStore.update_queue_entry(entry.id, updates)
      {:noreply, assign(socket, entry: updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_category", %{"category" => value}, socket) do
    {:noreply, assign(socket, category: value)}
  end

  # Fallback when phx-change on bare select sends with _target key
  def handle_event("select_category", params, socket) do
    value = params["category"] || params["value"] || ""
    {:noreply, assign(socket, category: value)}
  end

  def handle_event("search_tags", %{"key" => "Enter", "value" => value}, socket) do
    handle_event("add_tag_from_input", %{"value" => value}, socket)
  end

  def handle_event("search_tags", %{"value" => search_term}, socket) do
    filtered =
      if String.trim(search_term) == "" do
        socket.assigns.available_tags
      else
        Enum.filter(socket.assigns.available_tags, fn tag ->
          String.downcase(tag) =~ String.downcase(search_term)
        end)
      end

    {:noreply, assign(socket, tag_search: search_term, filtered_tags: filtered)}
  end

  def handle_event("add_tag", %{"tag" => tag}, socket) do
    tag = String.trim(tag)

    if tag != "" and tag not in socket.assigns.tags do
      {:noreply, assign(socket, tags: socket.assigns.tags ++ [tag], tag_search: "", filtered_tags: socket.assigns.available_tags)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_tag_from_input", %{"value" => value}, socket) do
    tag = String.trim(value)

    if tag != "" and tag not in socket.assigns.tags do
      # Create in DB if new
      available_tags =
        if tag not in socket.assigns.available_tags do
          case Blog.get_or_create_tag(tag) do
            {:ok, _} -> socket.assigns.available_tags ++ [tag]
            {:error, _} -> socket.assigns.available_tags
          end
        else
          socket.assigns.available_tags
        end

      {:noreply,
       socket
       |> assign(tags: socket.assigns.tags ++ [tag], tag_search: "", available_tags: available_tags, filtered_tags: available_tags)}
    else
      {:noreply, assign(socket, tag_search: "")}
    end
  end

  def handle_event("remove_tag", %{"tag" => tag}, socket) do
    {:noreply, assign(socket, tags: List.delete(socket.assigns.tags, tag))}
  end

  def handle_event("select_image", %{"url" => url}, socket) do
    {:noreply, assign(socket, featured_image: url)}
  end

  def handle_event("set_featured_image", %{"url" => url}, socket) do
    {:noreply, assign(socket, featured_image: url)}
  end

  def handle_event("remove_image", _params, socket) do
    {:noreply, assign(socket, featured_image: nil)}
  end

  def handle_event("post_tweet", _params, socket) do
    tweet = String.trim(socket.assigns.promotional_tweet)
    entry = socket.assigns.entry

    cond do
      tweet == "" ->
        {:noreply, put_flash(socket, :error, "Tweet is empty")}

      String.length(tweet) > 280 ->
        {:noreply, put_flash(socket, :error, "Tweet exceeds 280 characters")}

      is_nil(entry.post_id) ->
        {:noreply, put_flash(socket, :error, "Publish the article first before tweeting")}

      true ->
        post = BlocksterV2.Blog.get_post!(entry.post_id)

        {:noreply,
         start_async(socket, :post_tweet, fn ->
           ContentPublisher.post_promotional_tweet(post, tweet)
         end)}
    end
  end

  # ── Preview ──

  def handle_event("preview", _params, socket) do
    entry = socket.assigns.entry

    if entry.post_id do
      # Draft post already exists — redirect to it
      post = BlocksterV2.Repo.get(BlocksterV2.Blog.Post, entry.post_id)

      if post do
        {:noreply, redirect(socket, to: "/#{post.slug}")}
      else
        create_preview_draft(entry, socket)
      end
    else
      create_preview_draft(entry, socket)
    end
  end

  defp create_preview_draft(entry, socket) do
    case ContentPublisher.create_draft_post(entry) do
      {:ok, post} ->
        # Reload entry to get updated post_id
        updated_entry = FeedStore.get_queue_entry(entry.id) |> BlocksterV2.Repo.preload([:author, :revisions])
        {:noreply, socket |> assign(entry: updated_entry) |> redirect(to: "/#{post.slug}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Preview failed: #{inspect(reason)}")}
    end
  end

  # ── Save / Publish (reads content from TipTap hidden input) ──

  def handle_event("save_article", %{"action" => action} = params, socket) do
    entry = socket.assigns.entry

    # Parse content from TipTap editor hidden input
    content = parse_editor_content(params["content"], entry.article_data["content"])

    updated_data =
      entry.article_data
      |> Map.put("title", socket.assigns.title)
      |> Map.put("excerpt", socket.assigns.excerpt)
      |> Map.put("category", socket.assigns.category)
      |> Map.put("tags", socket.assigns.tags)
      |> Map.put("featured_image", socket.assigns.featured_image)
      |> Map.put("promotional_tweet", socket.assigns.promotional_tweet)
      |> Map.put("tweet_approved", socket.assigns.tweet_approved)
      |> Map.put("content", content)

    case action do
      "publish" -> do_publish(socket, entry, updated_data)
      "approve" -> do_approve(socket, entry, updated_data)
      _ -> do_save_draft(socket, entry, updated_data)
    end
  end

  # ── Revision Events ──

  def handle_event("request_revision", %{"instruction" => instruction}, socket) do
    instruction = String.trim(instruction)

    if instruction == "" do
      {:noreply, put_flash(socket, :error, "Enter a revision instruction")}
    else
      entry_id = socket.assigns.entry.id
      admin_id = socket.assigns.current_user.id

      socket = assign(socket, revising: true)

      {:noreply,
       start_async(socket, :revise_article, fn ->
         EditorialFeedback.revise_article(entry_id, instruction, requested_by: admin_id)
       end)}
    end
  end

  # ── Memory Events ──

  def handle_event("add_memory", %{"instruction" => instruction, "category" => category}, socket) do
    instruction = String.trim(instruction)

    if instruction == "" do
      {:noreply, put_flash(socket, :error, "Enter a memory instruction")}
    else
      case EditorialFeedback.add_memory(instruction,
        category: category,
        created_by: socket.assigns.current_user.id,
        source_queue_entry_id: socket.assigns.entry.id
      ) do
        {:ok, _memory} ->
          memories = EditorialFeedback.list_memories()

          {:noreply,
           socket
           |> assign(memories: memories)
           |> put_flash(:info, "Memory saved — will apply to all future articles")}

        {:error, changeset} ->
          msg = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end) |> inspect()
          {:noreply, put_flash(socket, :error, "Failed to save: #{msg}")}
      end
    end
  end

  def handle_event("deactivate_memory", %{"id" => id}, socket) do
    EditorialFeedback.deactivate_memory(id)
    memories = EditorialFeedback.list_memories()
    {:noreply, assign(socket, memories: memories)}
  end

  # ── Async Handlers ──

  @impl true
  def handle_async(:revise_article, {:ok, {:ok, updated_entry}}, socket) do
    updated_entry = BlocksterV2.Repo.preload(updated_entry, :author)
    revisions = EditorialFeedback.get_revision_history(updated_entry.id)

    # Push new content to the TipTap editor (since phx-update="ignore" prevents re-render)
    content_json = Jason.encode!(updated_entry.article_data["content"] || %{})

    {:noreply,
     socket
     |> assign(
       entry: updated_entry,
       title: updated_entry.article_data["title"] || "",
       excerpt: updated_entry.article_data["excerpt"] || "",
       category: updated_entry.article_data["category"] || "",
       tags: updated_entry.article_data["tags"] || [],
       revising: false,
       revisions: revisions
     )
     |> push_event("reload-editor-content", %{content: content_json})}
  end

  def handle_async(:revise_article, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(revising: false)
     |> put_flash(:error, "Revision failed: #{inspect(reason)}")}
  end

  def handle_async(:revise_article, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(revising: false)
     |> put_flash(:error, "Revision crashed: #{inspect(reason)}")}
  end

  def handle_async(:post_tweet, {:ok, :ok}, socket) do
    {:noreply, put_flash(socket, :info, "Tweet posted to @BlocksterCom")}
  end

  def handle_async(:post_tweet, {:ok, {:error, reason}}, socket) do
    {:noreply, put_flash(socket, :error, "Tweet failed: #{inspect(reason)}")}
  end

  def handle_async(:post_tweet, {:exit, reason}, socket) do
    {:noreply, put_flash(socket, :error, "Tweet crashed: #{inspect(reason)}")}
  end

  # ── Private Save/Publish Helpers ──

  defp do_save_draft(socket, entry, updated_data) do
    attrs = %{article_data: updated_data, status: "draft", scheduled_at: socket.assigns.scheduled_at}

    case FeedStore.update_queue_entry(entry.id, attrs) do
      {:ok, updated} ->
        updated = BlocksterV2.Repo.preload(updated, :author)
        {:noreply, socket |> assign(entry: updated) |> put_flash(:info, "Draft saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Save failed")}
    end
  end

  defp do_approve(socket, entry, updated_data) do
    attrs = %{article_data: updated_data, status: "approved", scheduled_at: socket.assigns.scheduled_at}

    case FeedStore.update_queue_entry(entry.id, attrs) do
      {:ok, _} ->
        # If a specific time is set, schedule a precise publish timer
        if socket.assigns.scheduled_at do
          BlocksterV2.ContentAutomation.ContentQueue.schedule_at(socket.assigns.scheduled_at)
        end

        {:noreply,
         socket
         |> put_flash(:info, "Article scheduled — will publish #{if socket.assigns.scheduled_at, do: "at scheduled time", else: "on next check (~10 min)"}")
         |> push_navigate(to: ~p"/admin/content/queue")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Schedule failed")}
    end
  end

  defp do_publish(socket, entry, updated_data) do
    case FeedStore.update_queue_entry(entry.id, %{article_data: updated_data}) do
      {:ok, updated} ->
        updated = BlocksterV2.Repo.preload(updated, :author)

        case ContentPublisher.publish_queue_entry(updated) do
          {:ok, post} ->
            {:noreply,
             socket
             |> put_flash(:info, "Published: \"#{post.title}\"")
             |> push_navigate(to: ~p"/admin/content/queue")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Publish failed: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Save failed")}
    end
  end

  defp parse_editor_content(nil, fallback), do: fallback
  defp parse_editor_content("", fallback), do: fallback
  defp parse_editor_content("{}", fallback), do: fallback

  defp parse_editor_content(json_string, fallback) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, %{"type" => "doc"} = content} -> content
      _ -> fallback
    end
  end

  defp parse_editor_content(content, _fallback), do: content

  # ── Helpers ──

  # ContentPublisher maps internal keys (e.g. "trading") to DB slugs (e.g. "markets").
  # When the admin picks a category from the DB dropdown, we store the slug directly.
  # This map handles the initial load where article_data has the internal key.
  @internal_to_slug %{
    "defi" => "defi",
    "rwa" => "rwa",
    "regulation" => "regulation",
    "gaming" => "gaming",
    "trading" => "markets",
    "token_launches" => "token-launches",
    "gambling" => "gambling",
    "privacy" => "privacy",
    "macro_trends" => "macro",
    "investment" => "investment",
    "bitcoin" => "bitcoin",
    "ethereum" => "ethereum",
    "altcoins" => "altcoins",
    "nft" => "nfts",
    "ai_crypto" => "ai-crypto",
    "stablecoins" => "stablecoins",
    "cbdc" => "cbdc",
    "security_hacks" => "security",
    "adoption" => "adoption",
    "mining" => "mining"
  }

  defp resolve_article_category_slug(nil), do: ""
  defp resolve_article_category_slug(internal_key) do
    Map.get(@internal_to_slug, internal_key, internal_key)
  end

  defp word_count(article_data) do
    case article_data["content"] do
      %{"content" => nodes} when is_list(nodes) ->
        BlocksterV2.ContentAutomation.TipTapBuilder.count_words(article_data["content"])
      _ -> 0
    end
  end

  defp content_json(entry) do
    case entry.article_data["content"] do
      %{"type" => "doc"} = content -> Jason.encode!(content)
      _ -> "{}"
    end
  end

  # datetime-local input needs a value but we store UTC — JS hook handles conversion
  defp local_datetime_value(nil), do: ""
  defp local_datetime_value(dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M")

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pt-24 px-4 md:px-8 max-w-6xl mx-auto pb-8">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-haas_medium_65 text-gray-900">Edit Article</h1>
          <p class="text-gray-500 text-sm mt-1">
            <%= word_count(@entry.article_data) %> words
            &middot; by <%= @entry.article_data["author_username"] || "Unknown" %>
            &middot; Status: <span class="text-yellow-600 font-medium"><%= @entry.status %></span>
            &middot; <span class={"px-1.5 py-0.5 rounded text-xs #{case @entry.content_type do
              "opinion" -> "bg-purple-100 text-purple-700"
              "offer" -> "bg-emerald-100 text-emerald-700"
              _ -> "bg-sky-100 text-sky-700"
            end}"}><%= (@entry.content_type || "news") |> String.capitalize() %></span>
            <%= if (@entry.revision_count || 0) > 0 do %>
              &middot; <span class="text-blue-600"><%= @entry.revision_count %> revision(s)</span>
            <% end %>
          </p>
        </div>
        <.link navigate={~p"/admin/content/queue"} class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200 cursor-pointer">
          &larr; Back to Queue
        </.link>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%!-- Main Content (2/3) --%>
        <div class="lg:col-span-2 space-y-6">
          <form id="article-edit-form" phx-submit="save_article">
            <%!-- Sources Info --%>
            <div class="bg-white rounded-lg shadow p-4 mb-6">
              <h3 class="text-sm text-gray-500 uppercase tracking-wider mb-2">Source Articles</h3>
              <div class="flex flex-wrap gap-2">
                <%= for source <- (@entry.article_data["source_urls"] || []) do %>
                  <% url = if is_map(source), do: source["url"], else: source %>
                  <a href={url} target="_blank" rel="noopener" class="text-xs text-blue-600 hover:underline bg-gray-100 rounded px-2 py-1 cursor-pointer">
                    <%= if is_map(source), do: source["source"] || URI.parse(url).host, else: URI.parse(url).host || url %>
                  </a>
                <% end %>
                <%= if (@entry.article_data["source_urls"] || []) == [] do %>
                  <span class="text-xs text-gray-400">No source URLs recorded</span>
                <% end %>
              </div>
            </div>

            <%!-- Edit Form --%>
            <div class="bg-white rounded-lg shadow p-6 space-y-5 mb-6">
              <%!-- Title --%>
              <div>
                <label class="block text-sm text-gray-500 uppercase tracking-wider mb-1">Title</label>
                <input
                  type="text"
                  value={@title}
                  phx-blur="update_field"
                  phx-value-field="title"
                  phx-keyup="update_field"
                  phx-value-field="title"
                  class="w-full bg-white border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-lg focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none"
                />
              </div>

              <%!-- Excerpt --%>
              <div>
                <label class="block text-sm text-gray-500 uppercase tracking-wider mb-1">Excerpt</label>
                <textarea
                  phx-blur="update_field"
                  phx-value-field="excerpt"
                  rows="3"
                  class="w-full bg-white border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none"
                ><%= @excerpt %></textarea>
              </div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
                <%!-- Category --%>
                <div>
                  <label class="block text-sm text-gray-500 uppercase tracking-wider mb-1">Category</label>
                  <select phx-change="select_category" name="category" class="w-full bg-white border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm cursor-pointer focus:border-blue-500 outline-none">
                    <%= for cat <- @db_categories do %>
                      <option value={cat.slug} selected={@category == cat.slug}><%= cat.name %></option>
                    <% end %>
                  </select>
                </div>

                <%!-- Tags --%>
                <div>
                  <label class="block text-sm text-gray-500 uppercase tracking-wider mb-1">Tags</label>
                  <div class="flex flex-wrap gap-1 mb-2">
                    <%= for tag <- @tags do %>
                      <span class="inline-flex items-center gap-1 px-2 py-1 bg-blue-100 text-blue-800 rounded-full text-xs">
                        <%= tag %>
                        <button type="button" phx-click="remove_tag" phx-value-tag={tag} class="text-blue-400 hover:text-red-500 cursor-pointer">&times;</button>
                      </span>
                    <% end %>
                  </div>
                  <input
                    type="text"
                    value={@tag_search}
                    placeholder="Search or create tag..."
                    autocomplete="off"
                    phx-keyup="search_tags"
                    phx-key="*"
                    phx-debounce="200"
                    class="w-full bg-white border border-gray-300 text-gray-900 rounded px-3 py-2 text-sm outline-none focus:border-blue-500"
                  />
                  <div class="flex flex-wrap gap-1 mt-2 max-h-[120px] overflow-y-auto">
                    <%= for tag <- @filtered_tags do %>
                      <%= unless tag in @tags do %>
                        <button
                          type="button"
                          phx-click="add_tag"
                          phx-value-tag={tag}
                          class="px-2 py-1 bg-gray-50 border border-gray-200 text-gray-600 rounded-full text-xs cursor-pointer hover:bg-blue-50 hover:border-blue-300 hover:text-blue-700"
                        >
                          <%= tag %>
                        </button>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              </div>

              <%!-- Featured Image --%>
              <div>
                <label class="block text-sm text-gray-500 uppercase tracking-wider mb-2">Featured Image</label>
                <%= if @featured_image do %>
                  <div class="mb-3 relative">
                    <img src={BlocksterV2.ImageKit.url(@featured_image, width: 800, height: 400)} class="w-full max-w-lg rounded-lg border border-gray-200" loading="lazy" />
                    <button type="button" phx-click="remove_image" class="absolute top-2 right-2 bg-black/60 text-white rounded-full w-7 h-7 flex items-center justify-center text-sm cursor-pointer hover:bg-black/80">&times;</button>
                  </div>
                <% end %>
                <div class="flex items-center gap-3 mb-3">
                  <input
                    type="file"
                    id="content-featured-image-input"
                    accept="image/*"
                    phx-hook="ContentFeaturedImageUpload"
                    class="hidden"
                  />
                  <button
                    type="button"
                    id="content-featured-image-btn"
                    onclick="document.getElementById('content-featured-image-input').click()"
                    class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm cursor-pointer hover:bg-gray-200 flex items-center gap-2"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 20 20" fill="none">
                      <path d="M17 13V17H3V13H1V17C1 18.1 1.9 19 3 19H17C18.1 19 19 18.1 19 17V13H17ZM16 9L14.59 7.59L11 11.17V1H9V11.17L5.41 7.59L4 9L10 15L16 9Z" fill="currentColor"/>
                    </svg>
                    <%= if @featured_image, do: "Change Image", else: "Upload Image" %>
                  </button>
                </div>
                <%= if @image_candidates != [] do %>
                  <p class="text-xs text-gray-500 mb-2">Or select from generated candidates:</p>
                  <div class="flex gap-3">
                    <%= for candidate <- @image_candidates do %>
                      <button
                        type="button"
                        phx-click="select_image"
                        phx-value-url={candidate["url"]}
                        class={"w-24 h-24 rounded-lg overflow-hidden border-2 cursor-pointer #{if @featured_image == candidate["url"], do: "border-blue-500", else: "border-gray-300 hover:border-gray-400"}"}
                      >
                        <img src={BlocksterV2.ImageKit.url(candidate["url"], width: 192, height: 192)} class="w-full h-full object-cover" loading="lazy" />
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- TipTap Rich Text Editor --%>
            <div class="bg-white rounded-lg shadow p-6 mb-6">
              <label class="block text-sm text-gray-500 uppercase tracking-wider mb-3">Article Content</label>
              <p class="text-xs text-gray-400 mb-3">
                Full editor — use the toolbar for bold, italic, links, headings, tweets, images, and more.
              </p>
              <div
                id={"tiptap-editor-content-auto-#{@entry.id}"}
                phx-update="ignore"
                phx-hook="TipTapEditor"
                data-content={content_json(@entry)}
                class="tiptap-editor border border-gray-200 rounded-xl"
              >
                <div class="tiptap-toolbar"></div>
                <div class="editor-container"></div>
                <input
                  type="hidden"
                  name="content"
                  value={content_json(@entry)}
                />
              </div>
            </div>

            <%!-- Actions --%>
            <div class="bg-white rounded-lg shadow p-6">
              <div class="flex items-center gap-3">
                <button type="submit" name="action" value="draft" class="px-6 py-2.5 bg-gray-100 text-gray-700 rounded-lg text-sm font-medium cursor-pointer hover:bg-gray-200">
                  Save Draft
                </button>
                <button type="submit" name="action" value="approve" class="px-6 py-2.5 bg-blue-600 text-white rounded-lg text-sm font-medium cursor-pointer hover:bg-blue-700">
                  <%= if @scheduled_at, do: "Schedule", else: "Schedule Next" %>
                </button>
                <button type="button" phx-click="preview" class="px-6 py-2.5 bg-indigo-600 text-white rounded-lg text-sm font-medium cursor-pointer hover:bg-indigo-700">
                  Preview
                </button>
                <button type="submit" name="action" value="publish" class="px-6 py-2.5 bg-gray-900 text-white rounded-lg text-sm font-medium cursor-pointer hover:bg-gray-800">
                  Publish Now
                </button>
                <.link navigate={~p"/admin/content/queue"} class="px-6 py-2.5 text-gray-500 hover:text-gray-900 text-sm cursor-pointer">
                  Cancel
                </.link>
              </div>
            </div>
          </form>
        </div>

        <%!-- Sidebar (1/3) --%>
        <div class="space-y-6 lg:sticky lg:top-24 lg:self-start">
          <%!-- Promotional Tweet --%>
          <div class="bg-white rounded-lg shadow p-5">
            <h3 class="text-sm text-gray-500 uppercase tracking-wider mb-3">Promo Tweet</h3>
            <p class="text-xs text-gray-400 mb-2">
              Edit and post to @BlocksterCom. <code class="bg-gray-100 px-1 rounded text-[10px]">{"{{ARTICLE_URL}}"}</code> becomes the article link.
            </p>
            <textarea
              phx-keyup="update_tweet"
              phx-debounce="100"
              rows="5"
              class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-500 resize-none"
            ><%= @promotional_tweet %></textarea>
            <div class="flex items-center justify-between mt-2">
              <span class={"text-xs #{if String.length(@promotional_tweet) > 280, do: "text-red-500 font-medium", else: "text-gray-400"}"}>
                <%= String.length(@promotional_tweet) %>/280
              </span>
              <button
                type="button"
                phx-click="post_tweet"
                disabled={@promotional_tweet == "" or String.length(@promotional_tweet) > 280 or is_nil(@entry.post_id)}
                class={"px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer " <> if(@promotional_tweet == "" or String.length(@promotional_tweet) > 280 or is_nil(@entry.post_id), do: "bg-gray-200 text-gray-400 cursor-not-allowed", else: "bg-black text-white hover:bg-gray-800")}
              >
                Post Tweet
              </button>
            </div>
            <div class="flex items-center gap-2 mt-3 pt-3 border-t border-gray-200">
              <button
                type="button"
                phx-click="toggle_tweet_approved"
                class={"relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors " <> if(@tweet_approved, do: "bg-green-500", else: "bg-gray-300")}
              >
                <span class={"pointer-events-none inline-block h-4 w-4 rounded-full bg-white shadow transform transition-transform " <> if(@tweet_approved, do: "translate-x-4", else: "translate-x-0")} />
              </button>
              <span class="text-xs text-gray-700">Auto-post tweet on publish</span>
            </div>
            <%= if @tweet_approved and String.length(@promotional_tweet) > 280 do %>
              <p class="text-xs text-red-500 mt-1">Tweet exceeds 280 chars — will not be posted.</p>
            <% end %>
            <%= if is_nil(@entry.post_id) and not @tweet_approved do %>
              <p class="text-xs text-gray-400 mt-1">Enable to auto-tweet when this article is published.</p>
            <% end %>
          </div>

          <%!-- Schedule Publish --%>
          <div class="bg-white rounded-lg shadow p-5">
            <h3 class="text-sm text-gray-500 uppercase tracking-wider mb-3">Schedule Publish</h3>
            <p class="text-xs text-gray-400 mb-2">
              Set a date/time for automatic publishing. All times are Eastern (EST/EDT).
            </p>
            <input
              type="datetime-local"
              id="schedule-datetime"
              name="scheduled_at"
              value={if @scheduled_at, do: TimeHelper.format_for_input(@scheduled_at), else: ""}
              phx-change="update_scheduled_at"
              class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-500 cursor-pointer"
            />
            <%= if @scheduled_at do %>
              <div class="flex items-center justify-between mt-2">
                <span class="text-xs text-blue-600">
                  Scheduled: <%= TimeHelper.format_display(@scheduled_at) %>
                </span>
                <button type="button" phx-click="update_scheduled_at" phx-value-value="" class="text-xs text-red-500 hover:text-red-700 cursor-pointer">
                  Clear
                </button>
              </div>
            <% end %>
          </div>

          <%!-- Offer Details (only for offer content type) --%>
          <%= if @entry.content_type == "offer" do %>
            <div class="bg-white rounded-lg shadow p-5">
              <h3 class="text-sm text-gray-500 uppercase tracking-wider mb-3">Offer Details</h3>
              <div class="space-y-3">
                <div>
                  <label class="text-xs text-gray-500">CTA URL</label>
                  <input type="text" phx-blur="update_offer_field" phx-value-field="cta_url"
                    value={@entry.cta_url || ""} placeholder="https://app.aave.com/..."
                    class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded px-3 py-2 text-sm mt-1" />
                </div>
                <div>
                  <label class="text-xs text-gray-500">CTA Button Text</label>
                  <input type="text" phx-blur="update_offer_field" phx-value-field="cta_text"
                    value={@entry.cta_text || ""} placeholder="Stake on Aave"
                    class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded px-3 py-2 text-sm mt-1" />
                </div>
                <div>
                  <label class="text-xs text-gray-500">Offer Type</label>
                  <select phx-change="update_offer_field" name="value" phx-value-field="offer_type"
                    class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded px-3 py-2 text-sm mt-1">
                    <option value="">Select...</option>
                    <option value="yield_opportunity" selected={@entry.offer_type == "yield_opportunity"}>Yield Opportunity</option>
                    <option value="exchange_promotion" selected={@entry.offer_type == "exchange_promotion"}>Exchange Promotion</option>
                    <option value="token_launch" selected={@entry.offer_type == "token_launch"}>Token Launch</option>
                    <option value="airdrop" selected={@entry.offer_type == "airdrop"}>Airdrop</option>
                    <option value="listing" selected={@entry.offer_type == "listing"}>Listing</option>
                  </select>
                </div>
                <div>
                  <label class="text-xs text-gray-500">Expiration Date (UTC)</label>
                  <input type="datetime-local" phx-blur="update_offer_field" phx-value-field="expires_at"
                    value={if @entry.expires_at, do: Calendar.strftime(@entry.expires_at, "%Y-%m-%dT%H:%M")}
                    class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded px-3 py-2 text-sm mt-1" />
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Request Revision --%>
          <div class="bg-white rounded-lg shadow p-5">
            <h3 class="text-sm text-gray-500 uppercase tracking-wider mb-3">Request AI Revision</h3>
            <p class="text-xs text-gray-400 mb-3">
              Describe changes and Claude will rewrite the article while preserving voice and facts.
            </p>
            <form phx-submit="request_revision">
              <textarea
                name="instruction"
                rows="4"
                placeholder="Make the headline shorter and punchier. Tone down the sarcasm in paragraph 2. Add a bullet list of key takeaways..."
                class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-500 resize-none"
                disabled={@revising}
              ></textarea>
              <button
                type="submit"
                disabled={@revising}
                class={"w-full mt-2 px-4 py-2.5 rounded-lg text-sm font-medium cursor-pointer #{if @revising, do: "bg-gray-300 text-gray-500 cursor-wait", else: "bg-blue-600 text-white hover:bg-blue-700"}"}
              >
                <%= if @revising, do: "Revising...", else: "Request Revision" %>
              </button>
            </form>

            <%!-- Revision History --%>
            <%= if @revisions != [] do %>
              <div class="mt-4 border-t border-gray-200 pt-3">
                <p class="text-xs text-gray-500 uppercase tracking-wider mb-2">Revision History</p>
                <div class="space-y-2">
                  <%= for rev <- Enum.reverse(@revisions) do %>
                    <div class="bg-gray-50 rounded p-2">
                      <div class="flex items-center justify-between">
                        <span class="text-xs font-medium text-gray-700">Rev #<%= rev.revision_number %></span>
                        <span class={"text-xs #{if rev.status == "completed", do: "text-green-600", else: "text-red-600"}"}><%= rev.status %></span>
                      </div>
                      <p class="text-xs text-gray-600 mt-1 line-clamp-2"><%= rev.instruction %></p>
                      <p class="text-xs text-gray-400 mt-0.5"><%= time_ago(rev.inserted_at) %></p>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Editorial Memory --%>
          <div class="bg-white rounded-lg shadow p-5">
            <h3 class="text-sm text-gray-500 uppercase tracking-wider mb-3">Editorial Memory</h3>
            <p class="text-xs text-gray-400 mb-3">
              Rules saved here apply to ALL future articles generated by the pipeline.
            </p>
            <form phx-submit="add_memory">
              <textarea
                name="instruction"
                rows="3"
                placeholder="Never use exclamation marks in headlines. Always mention regulatory implications. Avoid the phrase 'crypto winter'..."
                class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-500 resize-none"
              ></textarea>
              <select
                name="category"
                class="w-full bg-gray-50 border border-gray-300 text-gray-700 rounded-lg px-3 py-2 text-sm cursor-pointer mt-2"
              >
                <%= for cat <- @memory_categories do %>
                  <option value={cat}><%= String.capitalize(cat) %></option>
                <% end %>
              </select>
              <button
                type="submit"
                class="w-full mt-2 px-4 py-2.5 bg-blue-600 text-white rounded-lg text-sm font-medium cursor-pointer hover:bg-blue-700"
              >
                Save to Memory
              </button>
            </form>

            <%!-- Active Memories --%>
            <%= if @memories != [] do %>
              <div class="mt-4 border-t border-gray-200 pt-3">
                <p class="text-xs text-gray-500 uppercase tracking-wider mb-2">Active Rules (<%= length(@memories) %>)</p>
                <div class="space-y-2 max-h-[300px] overflow-y-auto">
                  <%= for mem <- @memories do %>
                    <div class="bg-gray-50 rounded p-2 group">
                      <div class="flex items-start justify-between gap-2">
                        <div class="min-w-0">
                          <span class="inline-block px-1.5 py-0.5 bg-blue-100 text-blue-700 rounded text-[10px] uppercase mb-1"><%= mem.category %></span>
                          <p class="text-xs text-gray-700 line-clamp-2"><%= mem.instruction %></p>
                        </div>
                        <button
                          type="button"
                          phx-click="deactivate_memory"
                          phx-value-id={mem.id}
                          class="text-gray-400 hover:text-red-500 text-xs shrink-0 opacity-0 group-hover:opacity-100 cursor-pointer"
                          title="Deactivate"
                        >
                          &times;
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
