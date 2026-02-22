defmodule BlocksterV2Web.PostLive.FormComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.Blog
  alias BlocksterV2.Social
  alias BlocksterV2.EngagementTracker

  @impl true
  def update(assigns, socket) do
    post = Map.get(assigns, :post, %Blog.Post{})

    # Auto-populate author_name with username for new posts
    post = if !post.id && !post.author_name && assigns[:current_user] do
      %{post | author_name: assigns.current_user.username}
    else
      post
    end

    changeset = Blog.change_post(post)

    # Load all tags from database
    available_tags = Blog.list_tags() |> Enum.map(& &1.name)

    # Load existing tags for this post if editing
    selected_tags =
      if post.id do
        post.tags |> Enum.map(& &1.name)
      else
        []
      end

    # Load all categories from database
    categories = Blog.list_categories()
    category_options = [{"Select a category", ""}] ++ Enum.map(categories, &{&1.name, &1.id})

    # Load all hubs from database
    hubs = Blog.list_hubs()
    hub_options = [{"No Hub", ""}] ++ Enum.map(hubs, &{&1.name, &1.id})

    # Initialize hub autocomplete state
    filtered_hubs = hubs
    show_hub_dropdown = false

    # Get hub name for display if post has a hub
    hub_name = case post do
      %{hub: %Ecto.Association.NotLoaded{}} ->
        # Hub not loaded, try to load it if hub_id exists
        if post.hub_id do
          case Blog.get_hub(post.hub_id) do
            nil -> ""
            hub -> hub.name
          end
        else
          ""
        end
      %{hub: nil} -> ""
      %{hub: hub} when is_map(hub) -> hub.name
      _ -> ""
    end

    # Initialize author autocomplete state
    authors = Map.get(assigns, :authors, [])
    filtered_authors = authors
    show_author_dropdown = false

    # Get pool stats for existing posts (admin pool management)
    {pool_balance, pool_deposited, pool_distributed} =
      if post.id do
        EngagementTracker.get_post_pool_stats(post.id)
      else
        {0, 0, 0}
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:pool_balance, pool_balance)
     |> assign(:pool_deposited, pool_deposited)
     |> assign(:pool_distributed, pool_distributed)
     |> assign(:deposit_amount, "")
     |> assign(:selected_tags, selected_tags)
     |> assign(:available_tags, available_tags)
     |> assign(:filtered_tags, available_tags)
     |> assign(:tag_search, "")
     |> assign(:category_options, category_options)
     |> assign(:hub_options, hub_options)
     |> assign(:hubs, hubs)
     |> assign(:filtered_hubs, filtered_hubs)
     |> assign(:show_hub_dropdown, show_hub_dropdown)
     |> assign(:hub_name, hub_name)
     |> assign(:filtered_authors, filtered_authors)
     |> assign(:show_author_dropdown, show_author_dropdown)
     |> assign(:ad_platform_x, false)
     |> assign(:ad_platform_meta, false)
     |> assign(:ad_platform_tiktok, false)
     |> assign(:ad_platform_telegram, false)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"post" => post_params} = params, socket) do
    # Preserve ad platform checkbox state across form changes
    socket =
      socket
      |> assign(:ad_platform_x, params["ad_platform_x"] == "true")
      |> assign(:ad_platform_meta, params["ad_platform_meta"] == "true")
      |> assign(:ad_platform_tiktok, params["ad_platform_tiktok"] == "true")
      |> assign(:ad_platform_telegram, params["ad_platform_telegram"] == "true")

    post_params =
      post_params
      |> parse_content()
      |> parse_custom_published_at()

    # Preserve featured_image if not present in params (e.g., during tag changes)
    post_params =
      if is_nil(post_params["featured_image"]) || post_params["featured_image"] == "" do
        current_featured_image = socket.assigns.post.featured_image
        if current_featured_image do
          Map.put(post_params, "featured_image", current_featured_image)
        else
          post_params
        end
      else
        post_params
      end

    # Auto-generate slug from title if title exists and slug is empty
    post_params =
      if post_params["title"] && post_params["title"] != "" &&
           (is_nil(post_params["slug"]) or post_params["slug"] == "") do
        slug =
          post_params["title"]
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        Map.put(post_params, "slug", slug)
      else
        post_params
      end

    changeset =
      socket.assigns.post
      |> Blog.change_post(post_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", params, socket) do
    post_params = params["post"]
    campaign_tweet_url = params["campaign_tweet_url"]

    # Collect ad platform selections from checkboxes
    ad_platforms =
      ~w(x meta tiktok telegram)
      |> Enum.filter(fn p -> params["ad_platform_#{p}"] == "true" end)

    # Parse content and custom published date
    post_params =
      post_params
      |> parse_content()
      |> parse_custom_published_at()

    # Auto-generate slug from title if title exists and slug is empty
    post_params =
      if post_params["title"] && post_params["title"] != "" &&
           (is_nil(post_params["slug"]) or post_params["slug"] == "") do
        slug =
          post_params["title"]
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        Map.put(post_params, "slug", slug)
      else
        post_params
      end

    socket =
      socket
      |> assign(:ad_platform_x, "x" in ad_platforms)
      |> assign(:ad_platform_meta, "meta" in ad_platforms)
      |> assign(:ad_platform_tiktok, "tiktok" in ad_platforms)
      |> assign(:ad_platform_telegram, "telegram" in ad_platforms)

    save_post(socket, socket.assigns.action, post_params, campaign_tweet_url, ad_platforms)
  end

  def handle_event("remove_featured_image", _params, socket) do
    # Get current form data to preserve it
    current_data = get_current_form_data(socket.assigns.form)

    # Update only the featured_image field
    updated_data = Map.put(current_data, "featured_image", nil)

    changeset =
      socket.assigns.post
      |> Blog.change_post(updated_data)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("set_featured_image", %{"url" => url}, socket) do
    # Get current form data to preserve it
    current_data = get_current_form_data(socket.assigns.form)

    # Update only the featured_image field
    updated_data = Map.put(current_data, "featured_image", url)

    changeset =
      socket.assigns.post
      |> Blog.change_post(updated_data)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("search_tags", %{"value" => search_term}, socket) do
    filtered_tags =
      if String.trim(search_term) == "" do
        socket.assigns.available_tags
      else
        socket.assigns.available_tags
        |> Enum.filter(fn tag ->
          String.downcase(tag) =~ String.downcase(search_term)
        end)
      end

    {:noreply,
     socket
     |> assign(:tag_search, search_term)
     |> assign(:filtered_tags, filtered_tags)}
  end

  def handle_event("add_tag_from_input", %{"value" => tag_value}, socket) do
    tag = String.trim(tag_value)

    if tag != "" && tag not in socket.assigns.selected_tags do
      selected_tags = socket.assigns.selected_tags ++ [tag]

      # Create tag in database if it doesn't exist
      available_tags =
        if tag not in socket.assigns.available_tags do
          case Blog.get_or_create_tag(tag) do
            {:ok, _tag_record} ->
              socket.assigns.available_tags ++ [tag]

            {:error, _changeset} ->
              socket.assigns.available_tags
          end
        else
          socket.assigns.available_tags
        end

      {:noreply,
       socket
       |> assign(:selected_tags, selected_tags)
       |> assign(:available_tags, available_tags)
       |> assign(:filtered_tags, available_tags)
       |> assign(:tag_search, "")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_tag", %{"tag" => tag}, socket) do
    if tag not in socket.assigns.selected_tags do
      selected_tags = socket.assigns.selected_tags ++ [tag]
      {:noreply, assign(socket, :selected_tags, selected_tags)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_tag", %{"tag" => tag}, socket) do
    selected_tags = Enum.reject(socket.assigns.selected_tags, &(&1 == tag))
    {:noreply, assign(socket, :selected_tags, selected_tags)}
  end

  @impl true
  def handle_event("search_hubs", %{"value" => search_term}, socket) do
    hubs = socket.assigns[:hubs] || []

    filtered_hubs = if String.trim(search_term) == "" do
      hubs
    else
      Enum.filter(hubs, fn hub ->
        String.contains?(String.downcase(hub.name), String.downcase(search_term))
      end)
    end

    show_dropdown = String.trim(search_term) != "" && length(filtered_hubs) > 0

    {:noreply, assign(socket, filtered_hubs: filtered_hubs, show_hub_dropdown: show_dropdown, hub_name: search_term)}
  end

  @impl true
  def handle_event("select_hub", %{"hub_id" => hub_id, "hub_name" => hub_name}, socket) do
    # Update the form with the selected hub_id
    changeset =
      socket.assigns.form.source
      |> Ecto.Changeset.put_change(:hub_id, String.to_integer(hub_id))
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:show_hub_dropdown, false)
     |> assign(:hub_name, hub_name)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("clear_hub", _params, socket) do
    # Clear the hub selection
    changeset =
      socket.assigns.form.source
      |> Ecto.Changeset.put_change(:hub_id, nil)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:show_hub_dropdown, false)
     |> assign(:hub_name, "")
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("deposit_bux", %{"amount" => amount_str}, socket) do
    # Admin-only: Deposit BUX into the post's pool
    current_user = socket.assigns[:current_user]

    if current_user && current_user.is_admin && socket.assigns.post.id do
      case Integer.parse(amount_str) do
        {amount, _} when amount > 0 ->
          post_id = socket.assigns.post.id
          case EngagementTracker.deposit_post_bux(post_id, amount) do
            {:ok, new_balance} ->
              # Refresh pool stats
              {pool_balance, pool_deposited, pool_distributed} = EngagementTracker.get_post_pool_stats(post_id)

              {:noreply,
               socket
               |> assign(:pool_balance, pool_balance)
               |> assign(:pool_deposited, pool_deposited)
               |> assign(:pool_distributed, pool_distributed)
               |> assign(:deposit_amount, "")
               |> put_flash(:info, "Deposited #{amount} BUX. Pool now: #{new_balance}")}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Deposit failed: #{inspect(reason)}")}
          end

        _ ->
          {:noreply, put_flash(socket, :error, "Invalid amount")}
      end
    else
      {:noreply, put_flash(socket, :error, "Admin only")}
    end
  end

  @impl true
  def handle_event("search_authors", %{"post" => %{"author_name" => search_term}}, socket) do
    authors = socket.assigns[:authors] || []

    filtered_authors = if String.trim(search_term) == "" do
      authors
    else
      Enum.filter(authors, fn author ->
        String.contains?(String.downcase(author.username), String.downcase(search_term))
      end)
    end

    show_dropdown = String.trim(search_term) != "" && length(filtered_authors) > 0

    {:noreply, assign(socket, filtered_authors: filtered_authors, show_author_dropdown: show_dropdown)}
  end

  @impl true
  def handle_event("select_author", %{"username" => username, "user_id" => user_id}, socket) do
    # Update the form with the selected username and author_id
    changeset =
      socket.assigns.form.source
      |> Ecto.Changeset.put_change(:author_name, username)
      |> Ecto.Changeset.put_change(:author_id, String.to_integer(user_id))
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:show_author_dropdown, false)
     |> assign_form(changeset)}
  end

  defp save_post(socket, action, post_params, campaign_tweet_url, ad_platforms \\ [])

  defp save_post(socket, :edit, post_params, campaign_tweet_url, ad_platforms) do
    IO.inspect(post_params, label: "Updating post with params")

    # Extract and decode tags if present
    tags =
      case post_params["tags"] do
        tags_json when is_binary(tags_json) ->
          case Jason.decode(tags_json) do
            {:ok, decoded_tags} -> decoded_tags
            {:error, _} -> []
          end

        tags_list when is_list(tags_list) ->
          tags_list

        _ ->
          []
      end

    # Remove tags from post_params since we'll handle it separately
    post_params = Map.delete(post_params, "tags")

    # Preserve video fields if not explicitly provided or empty
    # This prevents accidental clearing of video data during edits
    post_params = preserve_video_fields(socket.assigns.post, post_params)

    case Blog.update_post(socket.assigns.post, post_params) do
      {:ok, post} ->
        # Update tags after updating post
        Blog.update_post_tags(post, tags)

        # Create campaign if tweet URL is provided
        maybe_create_campaign(post, campaign_tweet_url)

        # Trigger ad creation for selected platforms
        maybe_create_ads(post, ad_platforms)

        notify_parent({:saved, post})

        {:noreply,
         socket
         |> put_flash(:info, "Post updated successfully")
         |> push_navigate(to: ~p"/#{post.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        IO.inspect(changeset.errors, label: "Post update validation errors")
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_post(socket, :new, post_params, campaign_tweet_url, ad_platforms) do
    IO.inspect(post_params, label: "Creating new post with params")

    # Extract and decode tags if present
    tags =
      case post_params["tags"] do
        tags_json when is_binary(tags_json) ->
          case Jason.decode(tags_json) do
            {:ok, decoded_tags} -> decoded_tags
            {:error, _} -> []
          end

        tags_list when is_list(tags_list) ->
          tags_list

        _ ->
          []
      end

    # Remove tags from post_params since we'll handle it separately
    post_params = Map.delete(post_params, "tags")

    case Blog.create_post(post_params) do
      {:ok, post} ->
        # Update tags after creating post
        Blog.update_post_tags(post, tags)

        # Create campaign if tweet URL is provided
        maybe_create_campaign(post, campaign_tweet_url)

        # Trigger ad creation for selected platforms
        maybe_create_ads(post, ad_platforms)

        notify_parent({:saved, post})

        {:noreply,
         socket
         |> put_flash(:info, "Post created successfully")
         |> push_navigate(to: ~p"/#{post.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        IO.inspect(changeset.errors, label: "Post creation validation errors")
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp maybe_create_ads(_post, []), do: :ok
  defp maybe_create_ads(post, platforms) when is_list(platforms) do
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "ads_manager",
      {:create_ads_for_post, post, platforms}
    )
  end

  defp maybe_create_campaign(_post, nil), do: :ok
  defp maybe_create_campaign(_post, ""), do: :ok

  defp maybe_create_campaign(post, tweet_url) when is_binary(tweet_url) do
    # Extract tweet ID from URL (handles twitter.com and x.com)
    # e.g., https://twitter.com/blockster/status/1234567890123456789
    # or https://x.com/blockster/status/1234567890123456789
    case Regex.run(~r/(?:twitter\.com|x\.com)\/\w+\/status\/(\d+)/, tweet_url) do
      [_, tweet_id] ->
        attrs = %{
          post_id: post.id,
          tweet_id: tweet_id,
          tweet_url: tweet_url,
          bux_reward: 50,
          is_active: true
        }

        case Social.create_share_campaign(attrs) do
          {:ok, _campaign} ->
            IO.puts("Created share campaign for post #{post.id}")
            :ok

          {:error, changeset} ->
            IO.inspect(changeset.errors, label: "Failed to create campaign")
            :error
        end

      _ ->
        IO.puts("Could not extract tweet ID from URL: #{tweet_url}")
        :error
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp parse_content(%{"content" => content} = params) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> Map.put(params, "content", decoded)
      {:error, _} -> params
    end
  end

  defp parse_content(params), do: params

  # Parse custom_published_at from datetime-local input format to UTC DateTime
  defp parse_custom_published_at(%{"custom_published_at" => datetime_str} = params)
       when is_binary(datetime_str) and datetime_str != "" do
    case NaiveDateTime.from_iso8601(datetime_str) do
      {:ok, naive_dt} ->
        # Convert NaiveDateTime to UTC DateTime
        utc_datetime = DateTime.from_naive!(naive_dt, "Etc/UTC")
        Map.put(params, "custom_published_at", utc_datetime)

      {:error, _} ->
        params
    end
  end

  defp parse_custom_published_at(params), do: params

  # Helper to extract current form data
  defp get_current_form_data(form) do
    %{
      "title" => form[:title].value || "",
      "author_name" => form[:author_name].value || "",
      "category" => form[:category].value || "",
      "excerpt" => form[:excerpt].value || "",
      "content" => form[:content].value || %{},
      "featured_image" => form[:featured_image].value,
      "slug" => form[:slug].value || ""
    }
  end

  # Preserve video fields from existing post if not explicitly provided in params
  # Only preserves when the param key is absent (nil) - if the user explicitly
  # clears a field (empty string), we allow it so videos can be deleted
  defp preserve_video_fields(existing_post, params) do
    video_fields = [:video_url, :video_duration, :video_bux_per_minute, :video_max_reward]

    Enum.reduce(video_fields, params, fn field, acc ->
      field_str = Atom.to_string(field)
      param_value = Map.get(acc, field_str)
      existing_value = Map.get(existing_post, field)

      # Only preserve if param is completely absent (nil) - not when explicitly cleared ("")
      if is_nil(param_value) and not is_nil(existing_value) do
        Map.put(acc, field_str, existing_value)
      else
        acc
      end
    end)
  end
end
