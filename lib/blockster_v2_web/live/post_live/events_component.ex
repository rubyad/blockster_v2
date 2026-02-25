defmodule BlocksterV2Web.PostLive.EventsComponent do
  use BlocksterV2Web, :live_component

  @impl true
  def update(assigns, socket) do
    # Get current date
    today = Date.utc_today()

    # Calculate calendar data for current month
    calendar_data = build_calendar(today.year, today.month)

    # Use event attendees from assigns if provided, otherwise empty list
    # (Previously loaded ALL users via Accounts.list_users() — full table scan)
    attendees = Map.get(assigns, :attendees, [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:today, today)
     |> assign(:current_month, today.month)
     |> assign(:current_year, today.year)
     |> assign(:calendar_data, calendar_data)
     |> assign(:show_attendees_popup, false)
     |> assign(:attendees, attendees)}
  end

  @impl true
  def handle_event("prev_month", _params, socket) do
    {year, month} = prev_month(socket.assigns.current_year, socket.assigns.current_month)
    calendar_data = build_calendar(year, month)

    {:noreply,
     socket
     |> assign(:current_year, year)
     |> assign(:current_month, month)
     |> assign(:calendar_data, calendar_data)}
  end

  @impl true
  def handle_event("next_month", _params, socket) do
    {year, month} = next_month(socket.assigns.current_year, socket.assigns.current_month)
    calendar_data = build_calendar(year, month)

    {:noreply,
     socket
     |> assign(:current_year, year)
     |> assign(:current_month, month)
     |> assign(:calendar_data, calendar_data)}
  end

  @impl true
  def handle_event("show_attendees", _params, socket) do
    {:noreply, assign(socket, :show_attendees_popup, true)}
  end

  @impl true
  def handle_event("hide_attendees", _params, socket) do
    {:noreply, assign(socket, :show_attendees_popup, false)}
  end

  defp build_calendar(year, month) do
    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)
    days_in_month = Date.days_in_month(first_day)

    # Get day of week for first day (1 = Monday, 7 = Sunday)
    starting_weekday = Date.day_of_week(first_day)

    # Calculate padding days before first day
    padding_before = rem(starting_weekday - 1, 7)

    # Calculate padding days after last day
    total_cells = padding_before + days_in_month
    padding_after = if rem(total_cells, 7) == 0, do: 0, else: 7 - rem(total_cells, 7)

    %{
      year: year,
      month: month,
      days_in_month: days_in_month,
      padding_before: padding_before,
      padding_after: padding_after,
      first_day: first_day,
      last_day: last_day
    }
  end

  defp prev_month(year, 1), do: {year - 1, 12}
  defp prev_month(year, month), do: {year, month - 1}

  defp next_month(year, 12), do: {year + 1, 1}
  defp next_month(year, month), do: {year, month + 1}

  defp month_name(month) do
    case month do
      1 -> "January"
      2 -> "February"
      3 -> "March"
      4 -> "April"
      5 -> "May"
      6 -> "June"
      7 -> "July"
      8 -> "August"
      9 -> "September"
      10 -> "October"
      11 -> "November"
      12 -> "December"
    end
  end

  defp get_initials(attendee) do
    name = attendee.username || attendee.email || "Anonymous"

    name
    |> String.split(["@", " ", "."])
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp get_avatar_color(attendee_id) do
    colors = [
      "from-purple-400 to-pink-400",
      "from-blue-400 to-cyan-400",
      "from-green-400 to-emerald-400",
      "from-orange-400 to-red-400",
      "from-yellow-400 to-orange-400",
      "from-pink-400 to-rose-400",
      "from-indigo-400 to-purple-400",
      "from-teal-400 to-green-400"
    ]

    index = rem(attendee_id, length(colors))
    Enum.at(colors, index)
  end
end
