defmodule BlocksterV2Web.PostLive.Form do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.Post

  @impl true
  def mount(_params, _session, socket) do
    # Load all authors (users with is_author = true) for admin dropdown
    authors = if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      BlocksterV2.Accounts.list_authors()
    else
      []
    end

    {:ok, assign(socket, authors: authors)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    # Auto-populate author_name with username for new posts
    post = if socket.assigns.current_user && socket.assigns.current_user.username do
      %Post{author_name: socket.assigns.current_user.username}
    else
      %Post{}
    end

    socket
    |> assign(:page_title, "New Post")
    |> assign(:post, post)
    |> assign_form(Blog.change_post(post))
  end

  defp apply_action(socket, :edit, %{"slug" => slug}) do
    post = Blog.get_post_by_slug!(slug)

    socket
    |> assign(:page_title, "Edit Post - #{post.title}")
    |> assign(:post, post)
    |> assign_form(Blog.change_post(post))
  end

  @impl true
  def handle_event("validate", %{"post" => post_params}, socket) do
    post_params = parse_content(post_params)

    changeset =
      socket.assigns.post
      |> Blog.change_post(post_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"post" => post_params}, socket) do
    post_params = parse_content(post_params)
    save_post(socket, socket.assigns.live_action, post_params)
  end

  defp save_post(socket, :edit, post_params) do
    case Blog.update_post(socket.assigns.post, post_params) do
      {:ok, post} ->
        # Update SortedPostsCache with new published_at and category_id
        BlocksterV2.SortedPostsCache.update_post(post.id, post.published_at, post.category_id)

        {:noreply,
         socket
         |> put_flash(:info, "Post updated successfully")
         |> push_navigate(to: ~p"/#{post.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_post(socket, :new, post_params) do
    # Add author_id from current user
    post_params = Map.put(post_params, "author_id", socket.assigns.current_user.id)

    case Blog.create_post(post_params) do
      {:ok, post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post created successfully")
         |> push_navigate(to: ~p"/#{post.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp parse_content(%{"content" => content} = params) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> Map.put(params, "content", decoded)
      {:error, _} -> params
    end
  end

  defp parse_content(params), do: params
end
