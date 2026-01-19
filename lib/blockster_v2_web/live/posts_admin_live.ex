defmodule BlocksterV2Web.PostsAdminLive do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.Post
  alias BlocksterV2.EngagementTracker

  @impl true
  def mount(_params, _session, socket) do
    # Check if user is admin
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      posts = Blog.list_posts()
      categories = Blog.list_categories()
      tags = Blog.list_tags()
      hubs = Blog.list_hubs()
      authors = get_all_authors()

      # Fetch pool balances from Mnesia
      pool_balances = EngagementTracker.get_all_post_bux_balances()

      # Attach pool balance to each post
      posts_with_pools = Enum.map(posts, fn post ->
        Map.put(post, :pool_balance, Map.get(pool_balances, post.id, 0))
      end)

      {:ok,
       socket
       |> assign(:all_posts, posts_with_pools)
       |> assign(:posts, posts_with_pools)
       |> assign(:categories, categories)
       |> assign(:tags, tags)
       |> assign(:hubs, hubs)
       |> assign(:authors, authors)
       |> assign(:editing_post_id, nil)
       |> assign(:editing_field, nil)
       |> assign(:filter_hub, nil)
       |> assign(:filter_author, nil)
       |> assign(:filter_category, nil)
       |> assign(:filter_status, "all")
       |> assign(:hub_search_results, [])
       |> assign(:author_search_results, [])
       |> assign(:selected_posts, MapSet.new())
       |> assign(:sort_by, :published_at)
       |> assign(:sort_dir, :desc)
       |> assign(:page_title, "Manage Posts")}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be an admin to access this page.")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("toggle_publish", %{"id" => id}, socket) do
    post = Blog.get_post!(id)

    result =
      if Post.published?(post) do
        Blog.update_post(post, %{published_at: nil})
      else
        # Use custom_published_at if set, otherwise use current time
        published_date =
          if post.custom_published_at do
            post.custom_published_at
          else
            DateTime.utc_now() |> DateTime.truncate(:second)
          end

        Blog.update_post(post, %{published_at: published_date})
      end

    case result do
      {:ok, _updated_post} ->
        all_posts = Blog.list_posts()

        {:noreply,
         socket
         |> assign(:all_posts, all_posts)
         |> assign(:posts, apply_filters(all_posts, socket.assigns))
         |> put_flash(:info, "Post status updated successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update post status.")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    post = Blog.get_post!(id)
    {:ok, _} = Blog.delete_post(post)

    all_posts = Blog.list_posts()

    {:noreply,
     socket
     |> assign(:all_posts, all_posts)
     |> assign(:posts, apply_filters(all_posts, socket.assigns))
     |> put_flash(:info, "Post deleted successfully.")}
  end

  @impl true
  def handle_event("start_edit", %{"id" => id, "field" => field}, socket) do
    {:noreply,
     socket
     |> assign(:editing_post_id, String.to_integer(id))
     |> assign(:editing_field, field)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_post_id, nil)
     |> assign(:editing_field, nil)}
  end

  @impl true
  def handle_event("update_author", %{"id" => id, "author_id" => author_id}, socket) do
    post = Blog.get_post!(id)

    case Blog.update_post(post, %{author_id: author_id}) do
      {:ok, _updated_post} ->
        all_posts = Blog.list_posts()

        {:noreply,
         socket
         |> assign(:all_posts, all_posts)
         |> assign(:posts, apply_filters(all_posts, socket.assigns))
         |> assign(:editing_post_id, nil)
         |> assign(:editing_field, nil)
         |> put_flash(:info, "Author updated successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update author.")}
    end
  end

  @impl true
  def handle_event("update_hub", %{"id" => id, "hub_id" => hub_id}, socket) do
    post = Blog.get_post!(id)

    attrs =
      if hub_id == "" do
        %{hub_id: nil}
      else
        %{hub_id: hub_id}
      end

    case Blog.update_post(post, attrs) do
      {:ok, _updated_post} ->
        all_posts = Blog.list_posts()

        {:noreply,
         socket
         |> assign(:all_posts, all_posts)
         |> assign(:posts, apply_filters(all_posts, socket.assigns))
         |> assign(:editing_post_id, nil)
         |> assign(:editing_field, nil)
         |> put_flash(:info, "Hub updated successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update hub.")}
    end
  end

  @impl true
  def handle_event("update_category", %{"id" => id, "category_id" => category_id}, socket) do
    post = Blog.get_post!(id)

    attrs =
      if category_id == "" do
        %{category_id: nil}
      else
        %{category_id: category_id}
      end

    case Blog.update_post(post, attrs) do
      {:ok, _updated_post} ->
        all_posts = Blog.list_posts()

        {:noreply,
         socket
         |> assign(:all_posts, all_posts)
         |> assign(:posts, apply_filters(all_posts, socket.assigns))
         |> assign(:editing_post_id, nil)
         |> assign(:editing_field, nil)
         |> put_flash(:info, "Category updated successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update category.")}
    end
  end

  @impl true
  def handle_event("update_tags", %{"id" => id, "tag_ids" => tag_ids}, socket) do
    post = Blog.get_post!(id)

    # Convert tag_ids to list of integers
    tag_id_list =
      tag_ids
      |> Map.values()
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.to_integer/1)

    case Blog.update_post_tags_by_ids(post, tag_id_list) do
      {:ok, _updated_post} ->
        all_posts = Blog.list_posts()

        {:noreply,
         socket
         |> assign(:all_posts, all_posts)
         |> assign(:posts, apply_filters(all_posts, socket.assigns))
         |> assign(:editing_post_id, nil)
         |> assign(:editing_field, nil)
         |> put_flash(:info, "Tags updated successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update tags.")}
    end
  end

  @impl true
  def handle_event("search_hub", %{"value" => query}, socket) do
    results =
      if query == "" do
        []
      else
        socket.assigns.hubs
        |> Enum.filter(fn hub ->
          String.contains?(String.downcase(hub.name), String.downcase(query))
        end)
        |> Enum.take(10)
      end

    {:noreply, assign(socket, :hub_search_results, results)}
  end

  @impl true
  def handle_event("select_hub", %{"id" => id, "name" => _name}, socket) do
    filter_hub = if id == "", do: nil, else: id

    filtered_posts = apply_filters(socket.assigns.all_posts, %{
      filter_hub: filter_hub,
      filter_author: socket.assigns.filter_author,
      filter_category: socket.assigns.filter_category,
      filter_status: socket.assigns.filter_status
    })

    {:noreply,
     socket
     |> assign(:filter_hub, filter_hub)
     |> assign(:hub_search_results, [])
     |> assign(:posts, filtered_posts)}
  end

  @impl true
  def handle_event("search_author", %{"value" => query}, socket) do
    results =
      if query == "" do
        []
      else
        socket.assigns.authors
        |> Enum.filter(fn author ->
          name = author.name || author.email || ""
          String.contains?(String.downcase(name), String.downcase(query))
        end)
        |> Enum.take(10)
      end

    {:noreply, assign(socket, :author_search_results, results)}
  end

  @impl true
  def handle_event("select_author", %{"id" => id, "name" => _name}, socket) do
    filter_author = if id == "", do: nil, else: id

    filtered_posts = apply_filters(socket.assigns.all_posts, %{
      filter_hub: socket.assigns.filter_hub,
      filter_author: filter_author,
      filter_category: socket.assigns.filter_category,
      filter_status: socket.assigns.filter_status
    })

    {:noreply,
     socket
     |> assign(:filter_author, filter_author)
     |> assign(:author_search_results, [])
     |> assign(:posts, filtered_posts)}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    filter_category = if category == "", do: nil, else: category

    filtered_posts = apply_filters(socket.assigns.all_posts, %{
      filter_hub: socket.assigns.filter_hub,
      filter_author: socket.assigns.filter_author,
      filter_category: filter_category,
      filter_status: socket.assigns.filter_status
    })

    {:noreply,
     socket
     |> assign(:filter_category, filter_category)
     |> assign(:posts, filtered_posts)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    filtered_posts = apply_filters(socket.assigns.all_posts, %{
      filter_hub: socket.assigns.filter_hub,
      filter_author: socket.assigns.filter_author,
      filter_category: socket.assigns.filter_category,
      filter_status: status
    })

    {:noreply,
     socket
     |> assign(:filter_status, status)
     |> assign(:posts, filtered_posts)}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filter_hub, nil)
     |> assign(:filter_author, nil)
     |> assign(:filter_category, nil)
     |> assign(:filter_status, "all")
     |> assign(:hub_search_results, [])
     |> assign(:author_search_results, [])
     |> assign(:posts, socket.assigns.all_posts)}
  end

  defp status_badge(post) do
    if Post.published?(post) do
      assigns = %{}

      ~H"""
      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
        Published
      </span>
      """
    else
      assigns = %{}

      ~H"""
      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
        Draft
      </span>
      """
    end
  end

  defp format_date(nil), do: "N/A"

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp truncate(nil, _length), do: ""

  defp truncate(text, length) do
    if String.length(text) > length do
      String.slice(text, 0, length) <> "..."
    else
      text
    end
  end

  defp get_all_authors do
    alias BlocksterV2.Accounts.User
    alias BlocksterV2.Repo
    import Ecto.Query

    from(u in User,
      where: u.is_author == true or u.is_admin == true,
      select: %{id: u.id, name: u.username, email: u.email},
      order_by: [asc: u.username]
    )
    |> Repo.all()
  end

  defp get_hub_name(_hubs, nil), do: ""

  defp get_hub_name(hubs, hub_id) do
    case Enum.find(hubs, &(to_string(&1.id) == hub_id)) do
      nil -> ""
      hub -> hub.name
    end
  end

  defp get_author_name(_authors, nil), do: ""

  defp get_author_name(authors, author_id) do
    case Enum.find(authors, &(to_string(&1.id) == author_id)) do
      nil -> ""
      author -> author.name || author.email
    end
  end

  defp apply_filters(posts, filters) do
    posts
    |> filter_by_hub(filters[:filter_hub])
    |> filter_by_author(filters[:filter_author])
    |> filter_by_category(filters[:filter_category])
    |> filter_by_status(filters[:filter_status])
  end

  defp filter_by_hub(posts, nil), do: posts

  defp filter_by_hub(posts, hub_id) do
    Enum.filter(posts, fn post ->
      post.hub && to_string(post.hub.id) == hub_id
    end)
  end

  defp filter_by_author(posts, nil), do: posts

  defp filter_by_author(posts, author_id) do
    Enum.filter(posts, fn post ->
      to_string(post.author_id) == author_id
    end)
  end

  defp filter_by_category(posts, nil), do: posts

  defp filter_by_category(posts, category_id) do
    Enum.filter(posts, fn post ->
      post.category && to_string(post.category.id) == category_id
    end)
  end

  defp filter_by_status(posts, "all"), do: posts

  defp filter_by_status(posts, "published") do
    Enum.filter(posts, &Post.published?/1)
  end

  defp filter_by_status(posts, "draft") do
    Enum.filter(posts, fn post -> !Post.published?(post) end)
  end

  # =============================================================================
  # Pool Management Event Handlers
  # =============================================================================

  @impl true
  def handle_event("deposit_single", %{"amount" => amount_str, "post-id" => post_id}, socket) do
    with {amount, _} <- Integer.parse(amount_str),
         true <- amount > 0,
         post_id <- String.to_integer(post_id),
         {:ok, new_balance} <- EngagementTracker.deposit_post_bux(post_id, amount) do
      # Update the post in both lists
      all_posts = update_post_balance(socket.assigns.all_posts, post_id, new_balance)
      posts = update_post_balance(socket.assigns.posts, post_id, new_balance)

      {:noreply,
       socket
       |> assign(:all_posts, all_posts)
       |> assign(:posts, posts)
       |> put_flash(:info, "Deposited #{amount} BUX to pool")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid deposit amount")}
    end
  end

  @impl true
  def handle_event("bulk_deposit", %{"amount" => amount_str}, socket) do
    with {amount, _} <- Integer.parse(amount_str),
         true <- amount > 0 do
      selected_ids = MapSet.to_list(socket.assigns.selected_posts)

      # Deposit to each selected post
      results = Enum.map(selected_ids, fn post_id ->
        EngagementTracker.deposit_post_bux(post_id, amount)
      end)

      success_count = Enum.count(results, &match?({:ok, _}, &1))

      # Refresh pool balances
      pool_balances = EngagementTracker.get_all_post_bux_balances()
      all_posts = Enum.map(socket.assigns.all_posts, fn post ->
        Map.put(post, :pool_balance, Map.get(pool_balances, post.id, 0))
      end)
      posts = apply_filters(all_posts, socket.assigns)

      {:noreply,
       socket
       |> assign(:all_posts, all_posts)
       |> assign(:posts, posts)
       |> assign(:selected_posts, MapSet.new())
       |> put_flash(:info, "Deposited #{amount} BUX to #{success_count} posts")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid amount")}
    end
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.selected_posts
    new_selected = if MapSet.member?(selected, id) do
      MapSet.delete(selected, id)
    else
      MapSet.put(selected, id)
    end
    {:noreply, assign(socket, :selected_posts, new_selected)}
  end

  @impl true
  def handle_event("toggle_all", _, socket) do
    all_ids = Enum.map(socket.assigns.posts, & &1.id) |> MapSet.new()
    new_selected = if MapSet.size(socket.assigns.selected_posts) == MapSet.size(all_ids) do
      MapSet.new()
    else
      all_ids
    end
    {:noreply, assign(socket, :selected_posts, new_selected)}
  end

  @impl true
  def handle_event("clear_selection", _, socket) do
    {:noreply, assign(socket, :selected_posts, MapSet.new())}
  end

  @impl true
  def handle_event("sort", %{"by" => column}, socket) do
    column = String.to_atom(column)
    dir = if socket.assigns.sort_by == column && socket.assigns.sort_dir == :desc, do: :asc, else: :desc

    posts = sort_posts(socket.assigns.posts, column, dir)

    {:noreply, assign(socket, posts: posts, sort_by: column, sort_dir: dir)}
  end

  defp update_post_balance(posts, post_id, new_balance) do
    Enum.map(posts, fn post ->
      if post.id == post_id, do: Map.put(post, :pool_balance, new_balance), else: post
    end)
  end

  defp sort_posts(posts, :pool_balance, :desc) do
    Enum.sort_by(posts, fn p -> Map.get(p, :pool_balance, 0) end, :desc)
  end

  defp sort_posts(posts, :pool_balance, :asc) do
    Enum.sort_by(posts, fn p -> Map.get(p, :pool_balance, 0) end, :asc)
  end

  defp sort_posts(posts, :published_at, :desc) do
    Enum.sort_by(posts, fn p -> p.published_at || p.inserted_at end, {:desc, DateTime})
  end

  defp sort_posts(posts, :published_at, :asc) do
    Enum.sort_by(posts, fn p -> p.published_at || p.inserted_at end, {:asc, DateTime})
  end

  defp sort_posts(posts, _column, _dir), do: posts

  defp format_pool_balance(balance) when is_number(balance) do
    Number.Delimit.number_to_delimited(balance, precision: 0)
  end

  defp format_pool_balance(_), do: "0"
end
