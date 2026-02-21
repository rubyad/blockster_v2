defmodule BlocksterV2Web.ContentAutomationLive.Events do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.{EventRoundup, ContentGenerator}

  @event_types ~w(conference upgrade unlock regulatory ecosystem)
  @tiers ~w(major notable minor)

  @impl true
  def mount(_params, _session, socket) do
    events = EventRoundup.list_events(sort: :start_date)

    {:ok,
     assign(socket,
       page_title: "Upcoming Events",
       events: events,
       show_form: false,
       form: default_form(),
       generating: false,
       generating_roundup: false,
       error: nil,
       event_types: @event_types,
       tiers: @tiers
     )}
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form, error: nil)}
  end

  def handle_event("validate_event", %{"event" => params}, socket) do
    {:noreply, assign(socket, form: params)}
  end

  def handle_event("add_event", %{"event" => params}, socket) do
    name = String.trim(params["name"] || "")
    url = String.trim(params["url"] || "")
    start_date = params["start_date"] || ""

    cond do
      name == "" ->
        {:noreply, assign(socket, error: "Event name is required")}

      start_date == "" ->
        {:noreply, assign(socket, error: "Start date is required")}

      url == "" ->
        {:noreply, assign(socket, error: "Event URL is required")}

      true ->
        attrs = %{
          name: name,
          event_type: params["event_type"] || "conference",
          start_date: params["start_date"],
          end_date: params["end_date"],
          location: String.trim(params["location"] || ""),
          url: url,
          description: String.trim(params["description"] || ""),
          tier: params["tier"] || "notable",
          added_by: socket.assigns[:current_user] && socket.assigns.current_user.id
        }

        case EventRoundup.add_event(attrs) do
          {:ok, _id} ->
            events = EventRoundup.list_events(sort: :start_date)

            {:noreply,
             socket
             |> assign(events: events, show_form: false, form: default_form(), error: nil)
             |> put_flash(:info, "Event added: #{name}")}

          {:error, reason} ->
            {:noreply, assign(socket, error: "Failed to add event: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("delete_event", %{"id" => id}, socket) do
    EventRoundup.delete_event(id)
    events = EventRoundup.list_events(sort: :start_date)
    {:noreply, assign(socket, events: events) |> put_flash(:info, "Event deleted")}
  end

  def handle_event("generate_preview", %{"id" => id}, socket) do
    event = Enum.find(socket.assigns.events, &(&1.id == id))

    if event do
      params = %{
        topic: event.name,
        category: "events",
        content_type: "news",
        instructions: event.description || "",
        template: "event_preview",
        event_dates: format_dates(event.start_date, event.end_date),
        event_url: event.url,
        event_location: event.location
      }

      socket =
        socket
        |> assign(generating: id, error: nil)
        |> start_async(:generate_preview, fn ->
          result = ContentGenerator.generate_on_demand(params)
          {id, result}
        end)

      {:noreply, socket}
    else
      {:noreply, assign(socket, error: "Event not found")}
    end
  end

  def handle_event("generate_roundup", _params, socket) do
    socket =
      socket
      |> assign(generating_roundup: true, error: nil)
      |> start_async(:generate_roundup, fn -> EventRoundup.generate_weekly_roundup() end)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:generate_preview, {:ok, {event_id, {:ok, entry}}}, socket) do
    EventRoundup.mark_article_generated(event_id)
    events = EventRoundup.list_events(sort: :start_date)

    {:noreply,
     socket
     |> assign(generating: false, events: events)
     |> put_flash(:info, "Preview generated: \"#{entry.article_data["title"]}\"")
     |> push_navigate(to: ~p"/admin/content/queue/#{entry.id}/edit")}
  end

  def handle_async(:generate_preview, {:ok, {_event_id, {:error, reason}}}, socket) do
    {:noreply, assign(socket, generating: false, error: "Generation failed: #{inspect(reason)}")}
  end

  def handle_async(:generate_preview, {:exit, reason}, socket) do
    {:noreply, assign(socket, generating: false, error: "Generation crashed: #{inspect(reason)}")}
  end

  def handle_async(:generate_roundup, {:ok, {:ok, entry}}, socket) do
    {:noreply,
     socket
     |> assign(generating_roundup: false)
     |> put_flash(:info, "Weekly roundup generated: \"#{entry.article_data["title"]}\"")
     |> push_navigate(to: ~p"/admin/content/queue/#{entry.id}/edit")}
  end

  def handle_async(:generate_roundup, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, generating_roundup: false, error: "Roundup generation failed: #{inspect(reason)}")}
  end

  def handle_async(:generate_roundup, {:exit, reason}, socket) do
    {:noreply, assign(socket, generating_roundup: false, error: "Roundup crashed: #{inspect(reason)}")}
  end

  defp default_form do
    %{
      "name" => "",
      "event_type" => "conference",
      "start_date" => "",
      "end_date" => "",
      "location" => "",
      "url" => "",
      "description" => "",
      "tier" => "notable"
    }
  end

  defp format_dates(nil, _), do: "TBD"
  defp format_dates(start_date, nil), do: Calendar.strftime(start_date, "%b %d, %Y")
  defp format_dates(start_date, end_date) do
    if Date.compare(start_date, end_date) == :eq do
      Calendar.strftime(start_date, "%b %d, %Y")
    else
      "#{Calendar.strftime(start_date, "%b %d")} — #{Calendar.strftime(end_date, "%b %d, %Y")}"
    end
  end

  defp type_label("conference"), do: "Conference"
  defp type_label("upgrade"), do: "Upgrade"
  defp type_label("unlock"), do: "Token Unlock"
  defp type_label("regulatory"), do: "Regulatory"
  defp type_label("ecosystem"), do: "Ecosystem"
  defp type_label(other), do: String.capitalize(other || "")

  defp tier_badge_class("major"), do: "bg-red-100 text-red-700"
  defp tier_badge_class("notable"), do: "bg-yellow-100 text-yellow-700"
  defp tier_badge_class("minor"), do: "bg-gray-100 text-gray-600"
  defp tier_badge_class(_), do: "bg-gray-100 text-gray-600"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pt-24 px-4 md:px-8 max-w-7xl mx-auto pb-8">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-haas_medium_65 text-gray-900">Upcoming Events</h1>
          <p class="text-gray-500 text-sm mt-1"><%= length(@events) %> events tracked</p>
        </div>
        <div class="flex gap-3">
          <button
            phx-click="generate_roundup"
            disabled={@generating_roundup}
            class={"px-4 py-2 bg-gray-900 text-white rounded-lg text-sm font-haas_medium_65 cursor-pointer hover:bg-gray-800 disabled:opacity-50 disabled:cursor-not-allowed"}
          >
            <%= if @generating_roundup, do: "Generating...", else: "Generate Weekly Roundup" %>
          </button>
          <button
            phx-click="toggle_form"
            class="px-4 py-2 bg-gray-900 text-white rounded-lg text-sm font-haas_medium_65 cursor-pointer hover:bg-gray-700"
          >
            <%= if @show_form, do: "Cancel", else: "Add Event" %>
          </button>
          <.link navigate={~p"/admin/content"} class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200 cursor-pointer">
            &larr; Dashboard
          </.link>
        </div>
      </div>

      <%= if @error do %>
        <div class="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
          <p class="text-red-700 text-sm"><%= @error %></p>
        </div>
      <% end %>

      <%= if @generating_roundup do %>
        <div class="bg-white rounded-lg shadow p-8 text-center mb-6">
          <div class="inline-block animate-spin rounded-full h-8 w-8 border-4 border-gray-300 border-t-[#CAFC00] mb-4"></div>
          <p class="text-gray-900 font-haas_medium_65">Generating weekly roundup...</p>
          <p class="text-gray-500 text-sm mt-2">Collecting events and generating article. This typically takes 30-60 seconds.</p>
        </div>
      <% end %>

      <%!-- Add Event Form --%>
      <%= if @show_form do %>
        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-lg font-haas_medium_65 text-gray-900 mb-4">Add Event</h2>
          <form phx-submit="add_event" phx-change="validate_event" class="space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-900 mb-1">Event Name <span class="text-red-500">*</span></label>
                <input
                  type="text"
                  name="event[name]"
                  value={@form["name"]}
                  placeholder="e.g., ETH Denver 2026"
                  class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
                />
              </div>
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-900 mb-1">Type</label>
                <select
                  name="event[event_type]"
                  class="w-full bg-gray-50 border border-gray-300 text-gray-700 rounded-lg px-3 py-2 text-sm cursor-pointer"
                >
                  <%= for t <- @event_types do %>
                    <option value={t} selected={@form["event_type"] == t}><%= type_label(t) %></option>
                  <% end %>
                </select>
              </div>
            </div>

            <div class="grid grid-cols-3 gap-4">
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-900 mb-1">Start Date <span class="text-red-500">*</span></label>
                <input
                  type="date"
                  name="event[start_date]"
                  value={@form["start_date"]}
                  class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
                />
              </div>
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-900 mb-1">End Date <span class="text-gray-400 text-xs font-normal">(optional)</span></label>
                <input
                  type="date"
                  name="event[end_date]"
                  value={@form["end_date"]}
                  class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
                />
              </div>
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-900 mb-1">Tier</label>
                <select
                  name="event[tier]"
                  class="w-full bg-gray-50 border border-gray-300 text-gray-700 rounded-lg px-3 py-2 text-sm cursor-pointer"
                >
                  <%= for t <- @tiers do %>
                    <option value={t} selected={@form["tier"] == t}><%= String.capitalize(t) %></option>
                  <% end %>
                </select>
              </div>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-900 mb-1">Location <span class="text-gray-400 text-xs font-normal">(optional)</span></label>
                <input
                  type="text"
                  name="event[location]"
                  value={@form["location"]}
                  placeholder="e.g., Denver, Colorado"
                  class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
                />
              </div>
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-900 mb-1">URL <span class="text-red-500">*</span></label>
                <input
                  type="url"
                  name="event[url]"
                  value={@form["url"]}
                  placeholder="https://ethdenver.com"
                  class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
                />
              </div>
            </div>

            <div>
              <label class="block text-sm font-haas_medium_65 text-gray-900 mb-1">Description <span class="text-gray-400 text-xs font-normal">(optional)</span></label>
              <textarea
                name="event[description]"
                rows="2"
                placeholder="Brief description of the event"
                class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
              ><%= @form["description"] %></textarea>
            </div>

            <div class="flex justify-end">
              <button
                type="submit"
                class="px-5 py-2 bg-gray-900 text-white rounded-lg text-sm font-haas_medium_65 cursor-pointer hover:bg-gray-800"
              >
                Add Event
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <%!-- Events Table --%>
      <%= if @events == [] do %>
        <div class="bg-white rounded-lg shadow p-8 text-center">
          <p class="text-gray-500">No events tracked yet. Add events to generate weekly roundups.</p>
        </div>
      <% else %>
        <div class="bg-white rounded-lg shadow overflow-hidden">
          <table class="w-full">
            <thead>
              <tr class="border-b border-gray-200">
                <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Event</th>
                <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Type</th>
                <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Date(s)</th>
                <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Location</th>
                <th class="text-center text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Tier</th>
                <th class="text-center text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Article</th>
                <th class="text-right text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for event <- @events do %>
                <tr class="border-b border-gray-100 hover:bg-gray-50">
                  <td class="px-4 py-3">
                    <p class="text-gray-900 text-sm font-medium"><%= event.name %></p>
                    <%= if event.url do %>
                      <a href={event.url} target="_blank" class="text-blue-500 text-xs hover:underline"><%= event.url %></a>
                    <% end %>
                  </td>
                  <td class="px-4 py-3">
                    <span class="text-gray-600 text-sm"><%= type_label(event.event_type) %></span>
                  </td>
                  <td class="px-4 py-3">
                    <span class="text-gray-900 text-sm"><%= format_dates(event.start_date, event.end_date) %></span>
                  </td>
                  <td class="px-4 py-3">
                    <span class="text-gray-600 text-sm"><%= event.location || "—" %></span>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <span class={"px-2 py-0.5 rounded text-xs #{tier_badge_class(event.tier)}"}>
                      <%= String.capitalize(event.tier || "notable") %>
                    </span>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <%= if event.article_generated do %>
                      <span class="px-2 py-0.5 bg-green-100 text-green-700 rounded text-xs">Generated</span>
                    <% else %>
                      <span class="text-gray-400 text-xs">—</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <div class="flex items-center justify-end gap-2">
                      <%= if event.tier in ["major", "notable"] && !event.article_generated do %>
                        <button
                          phx-click="generate_preview"
                          phx-value-id={event.id}
                          disabled={@generating == event.id}
                          class="px-3 py-1 bg-gray-900 text-white rounded text-xs font-haas_medium_65 cursor-pointer hover:bg-gray-800 disabled:opacity-50"
                        >
                          <%= if @generating == event.id, do: "Generating...", else: "Generate Preview" %>
                        </button>
                      <% end %>
                      <button
                        phx-click="delete_event"
                        phx-value-id={event.id}
                        data-confirm="Delete this event?"
                        class="px-3 py-1 bg-red-50 text-red-600 rounded text-xs cursor-pointer hover:bg-red-100"
                      >
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end
end
