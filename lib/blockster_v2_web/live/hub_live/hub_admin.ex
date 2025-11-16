defmodule BlocksterV2Web.HubLive.HubAdmin do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.Post
  alias BlocksterV2.Repo
  import Ecto.Query

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    hub = Blog.get_hub_by_slug!(slug)
    posts = list_hub_posts(hub.id)

    {:ok,
     socket
     |> assign(:page_title, "#{hub.name} - Admin")
     |> assign(:hub, hub)
     |> assign(:live_action, :index)
     |> assign(:editing_post, nil)
     |> stream(:posts, posts)}
  end

  @impl true
  def handle_params(%{"post_id" => post_id} = _params, _url, socket) do
    post = Blog.get_post!(post_id)

    {:noreply,
     socket
     |> assign(:editing_post, post)
     |> assign(:form, to_form(Post.changeset(post, %{})))}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :editing_post, nil)}
  end

  @impl true
  def handle_event("edit_post", %{"post-id" => post_id}, socket) do
    {:noreply,
     socket
     |> push_patch(to: ~p"/hub/#{socket.assigns.hub.slug}/admin?post_id=#{post_id}")}
  end

  @impl true
  def handle_event("validate", %{"post" => post_params}, socket) do
    changeset =
      socket.assigns.editing_post
      |> Post.changeset(post_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"post" => post_params}, socket) do
    case Blog.update_post(socket.assigns.editing_post, post_params) do
      {:ok, post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post updated successfully")
         |> stream_insert(:posts, post)
         |> push_patch(to: ~p"/hub/#{socket.assigns.hub.slug}/admin")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp list_hub_posts(hub_id) do
    from(p in BlocksterV2.Blog.Post,
      where: p.hub_id == ^hub_id and not is_nil(p.published_at),
      order_by: [desc: p.published_at],
      preload: [:author, :category, :hub]
    )
    |> Repo.all()
  end
end
