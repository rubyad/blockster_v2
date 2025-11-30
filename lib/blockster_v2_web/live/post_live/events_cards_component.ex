defmodule BlocksterV2Web.PostLive.EventsCardsComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.Events

  @impl true
  def update(assigns, socket) do
    # Load published events, limit to 3 for the cards display
    events = Events.list_published_events() |> Enum.take(3)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:events, events)}
  end

  defp format_date(date) do
    case date do
      %Date{} ->
        day = date.day
        month = Calendar.strftime(date, "%b") |> String.upcase()
        {day, month}

      _ ->
        {12, "DEC"}
    end
  end

  defp format_datetime(date, time) do
    case {date, time} do
      {%Date{}, %Time{}} ->
        date_str = Calendar.strftime(date, "%b %d, %Y")
        {hour, am_pm} = if time.hour >= 12, do: {if(time.hour == 12, do: 12, else: time.hour - 12), "PM"}, else: {if(time.hour == 0, do: 12, else: time.hour), "AM"}
        time_str = "#{hour}:#{String.pad_leading(Integer.to_string(time.minute), 2, "0")} #{am_pm}"
        "#{date_str} • #{time_str}"

      _ ->
        "Dec 12, 2025 • 6:00 PM"
    end
  end

  defp format_price(price) do
    case Decimal.to_float(price) do
      0.0 -> "Free"
      amount -> "$#{:erlang.float_to_binary(amount, decimals: 0)}"
    end
  end

  defp get_attendee_count(event) do
    length(event.attendees || [])
  end

  defp get_category_tag(index) do
    case rem(index, 3) do
      0 -> "NFT's"
      1 -> "Trading"
      2 -> "Networking"
    end
  end

  defp get_event_image(index) do
    case rem(index, 3) do
      0 -> "/images/nendorring.png"
      1 -> "/images/w3-1.png"
      2 -> "/images/w3-2.png"
    end
  end
end
