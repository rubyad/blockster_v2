defmodule BlocksterV2Web.PostLive.FormComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.Blog

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
    category_options = [{"Select a category", ""}] ++ Enum.map(categories, &{&1.name, &1.name})

    # Initialize author autocomplete state
    authors = Map.get(assigns, :authors, [])
    filtered_authors = authors
    show_author_dropdown = false

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_tags, selected_tags)
     |> assign(:available_tags, available_tags)
     |> assign(:filtered_tags, available_tags)
     |> assign(:tag_search, "")
     |> assign(:category_options, category_options)
     |> assign(:filtered_authors, filtered_authors)
     |> assign(:show_author_dropdown, show_author_dropdown)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"post" => post_params}, socket) do
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

  def handle_event("save", %{"post" => post_params}, socket) do
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

    save_post(socket, socket.assigns.action, post_params)
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
  def handle_event("select_author", %{"username" => username}, socket) do
    # Update the form with the selected username
    changeset =
      socket.assigns.form.source
      |> Ecto.Changeset.put_change(:author_name, username)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:show_author_dropdown, false)
     |> assign_form(changeset)}
  end

  defp save_post(socket, :edit, post_params) do
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

    case Blog.update_post(socket.assigns.post, post_params) do
      {:ok, post} ->
        # Update tags after updating post
        Blog.update_post_tags(post, tags)

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

  defp save_post(socket, :new, post_params) do
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
end
