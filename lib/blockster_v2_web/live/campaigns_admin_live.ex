defmodule BlocksterV2Web.CampaignsAdminLive do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Social
  alias BlocksterV2.Social.ShareCampaign
  alias BlocksterV2.Blog

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      campaigns = Social.list_share_campaigns()
      posts = Blog.list_posts()

      {:ok,
       socket
       |> assign(:campaigns, campaigns)
       |> assign(:posts, posts)
       |> assign(:show_form, false)
       |> assign(:editing_campaign, nil)
       |> assign(:form, to_form(%{}))
       |> assign(:page_title, "Share Campaigns")}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be an admin to access this page.")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white p-8">
      <div class="max-w-6xl mx-auto">
        <div class="flex justify-between items-center mb-8">
          <h1 class="text-3xl font-bold">Share Campaigns</h1>
          <button
            phx-click="new_campaign"
            class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg font-medium"
          >
            + New Campaign
          </button>
        </div>

        <%= if @show_form do %>
          <div class="bg-gray-800 rounded-lg p-6 mb-8">
            <h2 class="text-xl font-bold mb-4">
              <%= if @editing_campaign, do: "Edit Campaign", else: "Create New Campaign" %>
            </h2>

            <.form for={@form} phx-submit="save_campaign" class="space-y-4">
              <div>
                <label class="block text-sm font-medium mb-2">Post</label>
                <select name="post_id" class="w-full bg-gray-700 rounded-lg px-4 py-2 text-white" required>
                  <option value="">Select a post...</option>
                  <%= for post <- @posts do %>
                    <option
                      value={post.id}
                      selected={@editing_campaign && @editing_campaign.post_id == post.id}
                    >
                      <%= post.title %>
                    </option>
                  <% end %>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Tweet ID (the tweet to retweet)</label>
                <input
                  type="text"
                  name="tweet_id"
                  value={@editing_campaign && @editing_campaign.tweet_id}
                  class="w-full bg-gray-700 rounded-lg px-4 py-2 text-white"
                  placeholder="e.g., 1234567890123456789"
                  required
                />
                <p class="text-xs text-gray-400 mt-1">
                  Find the tweet ID from the URL: twitter.com/user/status/<span class="text-blue-400">1234567890123456789</span>
                </p>
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Tweet URL</label>
                <input
                  type="url"
                  name="tweet_url"
                  value={@editing_campaign && @editing_campaign.tweet_url}
                  class="w-full bg-gray-700 rounded-lg px-4 py-2 text-white"
                  placeholder="https://twitter.com/blockster/status/1234567890123456789"
                  required
                />
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Custom Tweet Text (optional)</label>
                <textarea
                  name="tweet_text"
                  class="w-full bg-gray-700 rounded-lg px-4 py-2 text-white"
                  placeholder="Custom text for shares..."
                  rows="3"
                ><%= @editing_campaign && @editing_campaign.tweet_text %></textarea>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium mb-2">BUX Reward</label>
                  <input
                    type="number"
                    name="bux_reward"
                    value={(@editing_campaign && @editing_campaign.bux_reward) || 50}
                    class="w-full bg-gray-700 rounded-lg px-4 py-2 text-white"
                    min="0"
                    required
                  />
                </div>

                <div>
                  <label class="block text-sm font-medium mb-2">Max Participants (optional)</label>
                  <input
                    type="number"
                    name="max_participants"
                    value={@editing_campaign && @editing_campaign.max_participants}
                    class="w-full bg-gray-700 rounded-lg px-4 py-2 text-white"
                    placeholder="Leave empty for unlimited"
                    min="1"
                  />
                </div>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium mb-2">Start Date (optional)</label>
                  <input
                    type="datetime-local"
                    name="starts_at"
                    value={format_datetime_local(@editing_campaign && @editing_campaign.starts_at)}
                    class="w-full bg-gray-700 rounded-lg px-4 py-2 text-white"
                  />
                </div>

                <div>
                  <label class="block text-sm font-medium mb-2">End Date (optional)</label>
                  <input
                    type="datetime-local"
                    name="ends_at"
                    value={format_datetime_local(@editing_campaign && @editing_campaign.ends_at)}
                    class="w-full bg-gray-700 rounded-lg px-4 py-2 text-white"
                  />
                </div>
              </div>

              <div class="flex items-center gap-2">
                <input
                  type="checkbox"
                  name="is_active"
                  id="is_active"
                  value="true"
                  checked={is_nil(@editing_campaign) || @editing_campaign.is_active}
                  class="rounded bg-gray-700 border-gray-600"
                />
                <label for="is_active" class="text-sm font-medium">Active</label>
              </div>

              <div class="flex gap-4">
                <button
                  type="submit"
                  class="px-6 py-2 bg-green-600 hover:bg-green-700 rounded-lg font-medium"
                >
                  <%= if @editing_campaign, do: "Update", else: "Create" %> Campaign
                </button>
                <button
                  type="button"
                  phx-click="cancel_form"
                  class="px-6 py-2 bg-gray-600 hover:bg-gray-700 rounded-lg font-medium"
                >
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        <% end %>

        <div class="bg-gray-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-gray-700">
              <tr>
                <th class="px-4 py-3 text-left">Post</th>
                <th class="px-4 py-3 text-left">BUX Reward</th>
                <th class="px-4 py-3 text-left">Shares</th>
                <th class="px-4 py-3 text-left">Status</th>
                <th class="px-4 py-3 text-left">Period</th>
                <th class="px-4 py-3 text-left">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for campaign <- @campaigns do %>
                <tr class="border-t border-gray-700 hover:bg-gray-750">
                  <td class="px-4 py-3">
                    <a href={"/#{campaign.post.slug}"} class="text-blue-400 hover:underline" target="_blank">
                      <%= truncate(campaign.post.title, 40) %>
                    </a>
                  </td>
                  <td class="px-4 py-3">
                    <span class="text-yellow-400 font-bold"><%= campaign.bux_reward %> BUX</span>
                  </td>
                  <td class="px-4 py-3">
                    <%= campaign.total_shares %><%= if campaign.max_participants do %>/<%= campaign.max_participants %><% end %>
                  </td>
                  <td class="px-4 py-3">
                    <%= if ShareCampaign.active?(campaign) do %>
                      <span class="px-2 py-1 bg-green-900 text-green-400 rounded text-sm">Active</span>
                    <% else %>
                      <span class="px-2 py-1 bg-red-900 text-red-400 rounded text-sm">Inactive</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-sm text-gray-400">
                    <%= format_campaign_period(campaign) %>
                  </td>
                  <td class="px-4 py-3">
                    <div class="flex gap-2">
                      <button
                        phx-click="edit_campaign"
                        phx-value-id={campaign.id}
                        class="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-sm"
                      >
                        Edit
                      </button>
                      <button
                        phx-click="toggle_active"
                        phx-value-id={campaign.id}
                        class={"px-3 py-1 rounded text-sm #{if campaign.is_active, do: "bg-yellow-600 hover:bg-yellow-700", else: "bg-green-600 hover:bg-green-700"}"}
                      >
                        <%= if campaign.is_active, do: "Deactivate", else: "Activate" %>
                      </button>
                      <a
                        href={campaign.tweet_url}
                        target="_blank"
                        class="px-3 py-1 bg-gray-600 hover:bg-gray-700 rounded text-sm"
                      >
                        View Tweet
                      </a>
                    </div>
                  </td>
                </tr>
              <% end %>

              <%= if Enum.empty?(@campaigns) do %>
                <tr>
                  <td colspan="6" class="px-4 py-8 text-center text-gray-400">
                    No campaigns yet. Create one to get started!
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("new_campaign", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_campaign, nil)
     |> assign(:form, to_form(%{}))}
  end

  @impl true
  def handle_event("edit_campaign", %{"id" => id}, socket) do
    campaign = Social.get_share_campaign(id)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_campaign, campaign)
     |> assign(:form, to_form(%{}))}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_campaign, nil)}
  end

  @impl true
  def handle_event("save_campaign", params, socket) do
    attrs = %{
      post_id: params["post_id"],
      tweet_id: params["tweet_id"],
      tweet_url: params["tweet_url"],
      tweet_text: nullify_empty(params["tweet_text"]),
      bux_reward: parse_integer(params["bux_reward"], 50),
      max_participants: parse_integer(params["max_participants"], nil),
      starts_at: parse_datetime(params["starts_at"]),
      ends_at: parse_datetime(params["ends_at"]),
      is_active: params["is_active"] == "true"
    }

    result =
      if socket.assigns.editing_campaign do
        Social.update_share_campaign(socket.assigns.editing_campaign, attrs)
      else
        Social.create_share_campaign(attrs)
      end

    case result do
      {:ok, _campaign} ->
        action = if socket.assigns.editing_campaign, do: "updated", else: "created"
        campaigns = Social.list_share_campaigns()

        {:noreply,
         socket
         |> assign(:campaigns, campaigns)
         |> assign(:show_form, false)
         |> assign(:editing_campaign, nil)
         |> put_flash(:info, "Campaign #{action} successfully.")}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)

        {:noreply, put_flash(socket, :error, "Error: #{errors}")}
    end
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    campaign = Social.get_share_campaign(id)
    new_status = !campaign.is_active

    case Social.update_share_campaign(campaign, %{is_active: new_status}) do
      {:ok, _} ->
        campaigns = Social.list_share_campaigns()
        action = if new_status, do: "activated", else: "deactivated"

        {:noreply,
         socket
         |> assign(:campaigns, campaigns)
         |> put_flash(:info, "Campaign #{action}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update campaign status.")}
    end
  end

  # Helper functions

  defp truncate(nil, _length), do: ""

  defp truncate(text, length) do
    if String.length(text) > length do
      String.slice(text, 0, length) <> "..."
    else
      text
    end
  end

  defp format_datetime_local(nil), do: nil

  defp format_datetime_local(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%dT%H:%M")
  end

  defp format_campaign_period(campaign) do
    start_str = if campaign.starts_at, do: format_date(campaign.starts_at), else: "Now"
    end_str = if campaign.ends_at, do: format_date(campaign.ends_at), else: "Never"
    "#{start_str} - #{end_str}"
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp nullify_empty(""), do: nil
  defp nullify_empty(str), do: str

  defp parse_integer(nil, default), do: default
  defp parse_integer("", default), do: default

  defp parse_integer(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str <> ":00Z") do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
