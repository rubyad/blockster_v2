defmodule BlocksterV2Web.PostLive.Form do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.Post

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Post")
    |> assign(:post, %Post{})
    |> assign_form(Blog.change_post(%Post{}))
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
        {:noreply,
         socket
         |> put_flash(:info, "Post updated successfully")
         |> push_navigate(to: ~p"/#{post.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_post(socket, :new, post_params) do
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
