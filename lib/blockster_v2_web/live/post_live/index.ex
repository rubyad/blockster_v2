defmodule BlocksterV2Web.PostLive.Index do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.Post

  @impl true
  def mount(_params, _session, socket) do
    posts = Blog.list_published_posts()
    interview_posts =
      Blog.list_published_posts_by_tag("interview", limit: 10)
      |> Enum.shuffle()
    categories = Blog.list_categories()

    {:ok,
     socket
     |> assign(:posts, posts)
     |> assign(:interview_posts, interview_posts)
     |> assign(:categories, categories)
     |> assign(:selected_category, nil)
     |> assign(:selected_interview_category, nil)
     |> assign(:page_title, "Latest Posts")
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_search_results, false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Latest Posts")
    |> assign(:post, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Post")
    |> assign(:post, %Post{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    post = Blog.get_post!(id)

    socket
    |> assign(:page_title, "Edit Post")
    |> assign(:post, post)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    post = Blog.get_post!(id)
    {:ok, _} = Blog.delete_post(post)

    # After deletion, navigate back to the index page to ensure the list is refreshed.
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    filtered_posts = if category == "" do
      Blog.list_published_posts()
    else
      Blog.list_published_posts_by_category(category)
    end

    {:noreply,
     socket
     |> assign(:posts, filtered_posts)
     |> assign(:selected_category, if(category == "", do: nil, else: category))}
  end

  @impl true
  def handle_event("filter_interview_category", %{"category" => category}, socket) do
    all_interview_posts = Blog.list_published_posts_by_tag("interview", limit: 10)

    filtered_posts = if category == "" do
      Enum.shuffle(all_interview_posts)
    else
      all_interview_posts
      |> Enum.filter(fn post -> post.category.name == category end)
      |> Enum.shuffle()
    end

    {:noreply,
     socket
     |> assign(:interview_posts, filtered_posts)
     |> assign(:selected_interview_category, if(category == "", do: nil, else: category))}
  end

  @impl true
  def handle_event("search_posts", %{"value" => query}, socket) do
    results = if String.length(query) >= 2 do
      Blog.search_posts_fulltext(query, limit: 20)
    else
      []
    end

    IO.puts("🔍 SEARCH DEBUG")
    IO.inspect(query, label: "Query")
    IO.inspect(length(results), label: "Results count")
    IO.inspect(String.length(query) >= 2, label: "Show dropdown")

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)
     |> assign(:show_search_results, String.length(query) >= 2)}
  end

  @impl true
  def handle_event("close_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_search_results, false)}
  end

  @impl true
  def handle_info({BlocksterV2Web.PostLive.FormComponent, {:saved, _post}}, socket) do
    {:noreply,
     socket
     |> assign(:posts, Blog.list_published_posts())
     |> assign(:selected_category, nil)}
  end
end
