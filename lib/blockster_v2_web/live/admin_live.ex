defmodule BlocksterV2Web.AdminLive do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.{Accounts, BuxMinter, Blog, Notifications, Mailer}
  alias BlocksterV2.Notifications.EmailBuilder

  @impl true
  def mount(_params, _session, socket) do
    # Load all users ordered by most recent first
    users = Accounts.list_users()

    {:ok,
     socket
     |> assign(users: users)
     |> assign(filtered_users: users)
     |> assign(filter_query: "")
     |> assign(send_bux_user_id: nil)
     |> assign(send_bux_amount: "")
     |> assign(send_bux_status: nil)
     |> assign(send_rogue_user_id: nil)
     |> assign(send_rogue_amount: "")
     |> assign(send_rogue_status: nil)
     |> assign(digest_status: nil)
     |> assign(hub_post_status: nil)}
  end

  defp filter_users(users, ""), do: users

  defp filter_users(users, query) do
    query = String.downcase(query)

    Enum.filter(users, fn user ->
      matches_email = user.email && String.contains?(String.downcase(user.email), query)
      matches_username = user.username && String.contains?(String.downcase(user.username), query)
      matches_wallet = user.wallet_address && String.contains?(String.downcase(user.wallet_address), query)
      matches_smart_wallet = user.smart_wallet_address && String.contains?(String.downcase(user.smart_wallet_address), query)

      matches_email || matches_username || matches_wallet || matches_smart_wallet
    end)
  end

  @impl true
  def handle_event("filter_users", %{"query" => query}, socket) do
    filtered = filter_users(socket.assigns.users, query)

    {:noreply,
     socket
     |> assign(filter_query: query)
     |> assign(filtered_users: filtered)}
  end

  @impl true
  def handle_event("toggle_author_status", %{"user-id" => user_id}, socket) do
    user = Accounts.get_user(user_id)

    if user do
      case Accounts.update_user(user, %{is_author: !user.is_author}) do
        {:ok, _updated_user} ->
          # Reload users list
          users = Accounts.list_users()
          filtered = filter_users(users, socket.assigns.filter_query)
          {:noreply, socket |> assign(users: users) |> assign(filtered_users: filtered)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_admin_status", %{"user-id" => user_id}, socket) do
    user = Accounts.get_user(user_id)

    if user do
      case Accounts.update_user(user, %{is_admin: !user.is_admin}) do
        {:ok, _updated_user} ->
          # Reload users list
          users = Accounts.list_users()
          filtered = filter_users(users, socket.assigns.filter_query)
          {:noreply, socket |> assign(users: users) |> assign(filtered_users: filtered)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_send_bux", %{"user-id" => user_id}, socket) do
    {:noreply,
     socket
     |> assign(send_bux_user_id: String.to_integer(user_id))
     |> assign(send_bux_amount: "")
     |> assign(send_bux_status: nil)}
  end

  @impl true
  def handle_event("close_send_bux", _params, socket) do
    {:noreply,
     socket
     |> assign(send_bux_user_id: nil)
     |> assign(send_bux_amount: "")
     |> assign(send_bux_status: nil)}
  end

  @impl true
  def handle_event("update_bux_amount", %{"amount" => amount}, socket) do
    {:noreply, assign(socket, send_bux_amount: amount)}
  end

  @impl true
  def handle_event("send_bux", _params, socket) do
    user_id = socket.assigns.send_bux_user_id
    amount_str = socket.assigns.send_bux_amount

    case Integer.parse(amount_str) do
      {amount, ""} when amount > 0 ->
        user = Accounts.get_user(user_id)

        if user && user.smart_wallet_address do
          # Send BUX using the mint function
          case BuxMinter.mint_bux(user.smart_wallet_address, amount, user.id, nil, :signup) do
            {:ok, result} ->
              # Reload users to show updated balance
              users = Accounts.list_users()
              filtered = filter_users(users, socket.assigns.filter_query)
              tx_hash = result["transactionHash"]

              {:noreply,
               socket
               |> assign(users: users)
               |> assign(filtered_users: filtered)
               |> assign(send_bux_status: {:success, amount, tx_hash})
               |> assign(send_bux_amount: "")}

            {:error, reason} ->
              {:noreply, assign(socket, send_bux_status: {:error, "Failed: #{inspect(reason)}"})}
          end
        else
          {:noreply, assign(socket, send_bux_status: {:error, "User has no smart wallet address"})}
        end

      _ ->
        {:noreply, assign(socket, send_bux_status: {:error, "Please enter a valid positive integer"})}
    end
  end

  @impl true
  def handle_event("open_send_rogue", %{"user-id" => user_id}, socket) do
    {:noreply,
     socket
     |> assign(send_rogue_user_id: String.to_integer(user_id))
     |> assign(send_rogue_amount: "")
     |> assign(send_rogue_status: nil)}
  end

  @impl true
  def handle_event("close_send_rogue", _params, socket) do
    {:noreply,
     socket
     |> assign(send_rogue_user_id: nil)
     |> assign(send_rogue_amount: "")
     |> assign(send_rogue_status: nil)}
  end

  @impl true
  def handle_event("update_rogue_amount", %{"amount" => amount}, socket) do
    {:noreply, assign(socket, send_rogue_amount: amount)}
  end

  @impl true
  def handle_event("send_rogue", _params, socket) do
    user_id = socket.assigns.send_rogue_user_id
    amount_str = socket.assigns.send_rogue_amount

    case Float.parse(amount_str) do
      {amount, _} when amount > 0 ->
        user = Accounts.get_user(user_id)

        if user && user.smart_wallet_address do
          case BuxMinter.transfer_rogue(user.smart_wallet_address, amount, user.id, "admin_send") do
            {:ok, result} ->
              BuxMinter.sync_user_balances_async(user.id, user.smart_wallet_address, force: true)
              tx_hash = result["transactionHash"]

              {:noreply,
               socket
               |> assign(send_rogue_status: {:success, amount, tx_hash})
               |> assign(send_rogue_amount: "")}

            {:error, reason} ->
              {:noreply, assign(socket, send_rogue_status: {:error, "Failed: #{inspect(reason)}"})}
          end
        else
          {:noreply, assign(socket, send_rogue_status: {:error, "User has no smart wallet address"})}
        end

      _ ->
        {:noreply, assign(socket, send_rogue_status: {:error, "Please enter a valid positive number"})}
    end
  end

  @impl true
  def handle_event("send_test_digest", _params, socket) do
    admin = socket.assigns.current_user

    if is_nil(admin) || is_nil(admin.email) do
      {:noreply, assign(socket, digest_status: {:error, "You don't have an email address set"})}
    else
      posts = Blog.list_published_posts_by_date(limit: 5)

      if posts == [] do
        {:noreply, assign(socket, digest_status: {:error, "No published posts found"})}
      else
        articles =
          Enum.map(posts, fn post ->
            hub_name = if post.hub, do: post.hub.name, else: nil

            image_url =
              if post.featured_image do
                "#{post.featured_image}?tr=w-200,h-200,fo-auto"
              else
                nil
              end

            %{
              title: post.title,
              slug: post.slug,
              image_url: image_url,
              hub_name: hub_name,
              excerpt: post.excerpt
            }
          end)

        token =
          case Notifications.get_or_create_preferences(admin.id) do
            {:ok, prefs} -> prefs.unsubscribe_token
            _ -> ""
          end

        email =
          EmailBuilder.daily_digest(
            admin.email,
            admin.username || admin.email,
            token,
            %{articles: articles, date: Date.utc_today()}
          )

        case Mailer.deliver(email) do
          {:ok, _} ->
            {:noreply, assign(socket, digest_status: {:ok, length(posts), admin.email})}

          {:error, reason} ->
            {:noreply, assign(socket, digest_status: {:error, "Delivery failed: #{inspect(reason)}"})}
        end
      end
    end
  end

  @impl true
  def handle_event("send_test_hub_post", _params, socket) do
    admin = socket.assigns.current_user

    if is_nil(admin) || is_nil(admin.email) do
      {:noreply, assign(socket, hub_post_status: {:error, "You don't have an email address set"})}
    else
      # Find the latest published post that belongs to a hub
      import Ecto.Query
      post =
        BlocksterV2.Repo.one(
          from p in BlocksterV2.Blog.Post,
            where: not is_nil(p.hub_id) and not is_nil(p.published_at),
            order_by: [desc: p.published_at],
            limit: 1,
            preload: [:hub]
        )

      if is_nil(post) do
        {:noreply, assign(socket, hub_post_status: {:error, "No hub posts found"})}
      else
        hub_name = if post.hub, do: post.hub.name

        token =
          case Notifications.get_or_create_preferences(admin.id) do
            {:ok, prefs} -> prefs.unsubscribe_token
            _ -> ""
          end

        email =
          EmailBuilder.single_article(
            admin.email,
            admin.username || admin.email,
            token,
            %{
              title: post.title,
              body: post.excerpt || "",
              image_url: post.featured_image,
              slug: post.slug,
              hub_name: hub_name
            }
          )

        case Mailer.deliver(email) do
          {:ok, _} ->
            {:noreply, assign(socket, hub_post_status: {:ok, post.title, admin.email})}

          {:error, reason} ->
            {:noreply, assign(socket, hub_post_status: {:error, "Delivery failed: #{inspect(reason)}"})}
        end
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 pt-24 pb-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-2xl font-bold text-gray-900">User Management</h1>
                <p class="mt-1 text-sm text-gray-600">View all registered users</p>
              </div>
              <div class="flex items-center gap-3">
                <div class="flex items-start gap-2">
                  <div>
                    <button
                      phx-click="send_test_digest"
                      class="px-4 py-2 text-sm font-semibold text-white bg-gray-900 rounded-lg hover:bg-gray-800 transition-colors cursor-pointer"
                    >
                      Send Test Digest
                    </button>
                    <%= if @digest_status do %>
                      <%= case @digest_status do %>
                        <% {:ok, count, to_email} -> %>
                          <p class="text-xs text-green-600 mt-1">Sent <%= count %> articles to <%= to_email %></p>
                        <% {:error, msg} -> %>
                          <p class="text-xs text-red-600 mt-1"><%= msg %></p>
                      <% end %>
                    <% end %>
                  </div>
                  <div>
                    <button
                      phx-click="send_test_hub_post"
                      class="px-4 py-2 text-sm font-semibold text-gray-900 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors cursor-pointer"
                    >
                      Send Test Hub Post
                    </button>
                    <%= if @hub_post_status do %>
                      <%= case @hub_post_status do %>
                        <% {:ok, title, to_email} -> %>
                          <p class="text-xs text-green-600 mt-1">Sent "<%= title %>" to <%= to_email %></p>
                        <% {:error, msg} -> %>
                          <p class="text-xs text-red-600 mt-1"><%= msg %></p>
                      <% end %>
                    <% end %>
                  </div>
                </div>
                <div class="w-80">
                  <form phx-change="filter_users">
                    <input
                      type="text"
                      name="query"
                      value={@filter_query}
                      placeholder="Filter by email, username, or wallet..."
                      class="w-full px-4 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      phx-debounce="200"
                    />
                  </form>
                </div>
              </div>
            </div>
          </div>

          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Smart Wallet
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Email
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Username
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Auth Method
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Level
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    BUX
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Joined
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Admin Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Author Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Send BUX
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Send ROGUE
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for user <- @filtered_users do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4">
                      <%= if user.smart_wallet_address do %>
                        <a
                          href={"https://roguescan.io/address/#{user.smart_wallet_address}"}
                          target="_blank"
                          class="text-xs text-blue-600 hover:text-blue-800 hover:underline font-mono cursor-pointer"
                        >
                          <%= user.smart_wallet_address %>
                        </a>
                      <% else %>
                        <span class="text-xs text-gray-400">No smart wallet</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if user.email do %>
                        <span class="text-sm text-gray-900"><%= user.email %></span>
                      <% else %>
                        <span class="text-sm text-gray-400">—</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if user.username do %>
                        <span class="text-sm text-gray-900"><%= user.username %></span>
                      <% else %>
                        <span class="text-sm text-gray-400">—</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={[
                        "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                        if(user.auth_method == "email", do: "bg-blue-100 text-blue-800", else: "bg-purple-100 text-purple-800")
                      ]}>
                        <%= user.auth_method %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= user.level %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= user.bux_balance %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= Calendar.strftime(user.inserted_at, "%b %d, %Y") %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <button
                        phx-click="toggle_admin_status"
                        phx-value-user-id={user.id}
                        class={[
                          "px-3 py-1 rounded-full text-xs font-semibold transition-colors",
                          if(user.is_admin, do: "bg-red-100 text-red-800 hover:bg-red-200", else: "bg-gray-100 text-gray-600 hover:bg-gray-200")
                        ]}
                      >
                        <%= if user.is_admin, do: "Admin ✓", else: "Make Admin" %>
                      </button>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <button
                        phx-click="toggle_author_status"
                        phx-value-user-id={user.id}
                        class={[
                          "px-3 py-1 rounded-full text-xs font-semibold transition-colors cursor-pointer",
                          if(user.is_author, do: "bg-green-100 text-green-800 hover:bg-green-200", else: "bg-gray-100 text-gray-600 hover:bg-gray-200")
                        ]}
                      >
                        <%= if user.is_author, do: "Author ✓", else: "Make Author" %>
                      </button>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <%= if @send_bux_user_id == user.id do %>
                        <form phx-change="update_bux_amount" phx-submit="send_bux" class="flex items-center gap-2">
                          <input
                            type="number"
                            name="amount"
                            min="1"
                            placeholder="Amount"
                            value={@send_bux_amount}
                            autofocus
                            class="w-20 px-2 py-1 text-xs border border-gray-300 rounded focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                          />
                          <button
                            type="submit"
                            disabled={@send_bux_amount == ""}
                            class="px-2 py-1 text-xs font-semibold text-white bg-green-600 rounded hover:bg-green-700 disabled:bg-gray-300 disabled:cursor-not-allowed cursor-pointer"
                          >
                            Send
                          </button>
                          <button
                            type="button"
                            phx-click="close_send_bux"
                            class="px-2 py-1 text-xs text-gray-600 hover:text-gray-800 cursor-pointer"
                          >
                            Cancel
                          </button>
                        </form>
                        <%= if @send_bux_status do %>
                          <%= case @send_bux_status do %>
                            <% {:success, amount, tx_hash} -> %>
                              <div class="mt-1 text-xs text-green-600">
                                Sent <%= amount %> BUX! TX:
                                <a
                                  href={"https://roguescan.io/tx/#{tx_hash}"}
                                  target="_blank"
                                  class="text-blue-600 hover:underline cursor-pointer font-mono break-all"
                                >
                                  <%= tx_hash %>
                                </a>
                              </div>
                            <% {:error, message} -> %>
                              <div class="mt-1 text-xs text-red-600">
                                <%= message %>
                              </div>
                          <% end %>
                        <% end %>
                      <% else %>
                        <%= if user.smart_wallet_address do %>
                          <button
                            phx-click="open_send_bux"
                            phx-value-user-id={user.id}
                            class="px-3 py-1 rounded-full text-xs font-semibold bg-blue-100 text-blue-800 hover:bg-blue-200 transition-colors cursor-pointer"
                          >
                            Send BUX
                          </button>
                        <% else %>
                          <span class="text-xs text-gray-400">—</span>
                        <% end %>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <%= if @send_rogue_user_id == user.id do %>
                        <form phx-change="update_rogue_amount" phx-submit="send_rogue" class="flex items-center gap-2">
                          <input
                            type="number"
                            name="amount"
                            min="0.001"
                            step="0.001"
                            placeholder="Amount"
                            value={@send_rogue_amount}
                            autofocus
                            class="w-20 px-2 py-1 text-xs border border-gray-300 rounded focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                          />
                          <button
                            type="submit"
                            disabled={@send_rogue_amount == ""}
                            class="px-2 py-1 text-xs font-semibold text-white bg-purple-600 rounded hover:bg-purple-700 disabled:bg-gray-300 disabled:cursor-not-allowed cursor-pointer"
                          >
                            Send
                          </button>
                          <button
                            type="button"
                            phx-click="close_send_rogue"
                            class="px-2 py-1 text-xs text-gray-600 hover:text-gray-800 cursor-pointer"
                          >
                            Cancel
                          </button>
                        </form>
                        <%= if @send_rogue_status do %>
                          <%= case @send_rogue_status do %>
                            <% {:success, amount, tx_hash} -> %>
                              <div class="mt-1 text-xs text-green-600">
                                Sent <%= amount %> ROGUE! TX:
                                <a
                                  href={"https://roguescan.io/tx/#{tx_hash}"}
                                  target="_blank"
                                  class="text-blue-600 hover:underline cursor-pointer font-mono break-all"
                                >
                                  <%= tx_hash %>
                                </a>
                              </div>
                            <% {:error, message} -> %>
                              <div class="mt-1 text-xs text-red-600">
                                <%= message %>
                              </div>
                          <% end %>
                        <% end %>
                      <% else %>
                        <%= if user.smart_wallet_address do %>
                          <button
                            phx-click="open_send_rogue"
                            phx-value-user-id={user.id}
                            class="px-3 py-1 rounded-full text-xs font-semibold bg-purple-100 text-purple-800 hover:bg-purple-200 transition-colors cursor-pointer"
                          >
                            Send ROGUE
                          </button>
                        <% else %>
                          <span class="text-xs text-gray-400">—</span>
                        <% end %>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div class="px-6 py-4 bg-gray-50 border-t border-gray-200">
            <p class="text-sm text-gray-600">
              <%= if @filter_query != "" do %>
                Showing <span class="font-semibold"><%= length(@filtered_users) %></span> of <span class="font-semibold"><%= length(@users) %></span> users
              <% else %>
                Total users: <span class="font-semibold"><%= length(@users) %></span>
              <% end %>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
