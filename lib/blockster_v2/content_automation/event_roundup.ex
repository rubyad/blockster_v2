defmodule BlocksterV2.ContentAutomation.EventRoundup do
  @moduledoc """
  Weekly event roundup generation and admin-curated event management.

  Events come from two sources:
  1. Admin-curated `upcoming_events` Mnesia table (manually added)
  2. ContentGeneratedTopics with category "events" from PostgreSQL (RSS-sourced)

  The weekly roundup merges both sources, so it works even with zero admin-curated events.
  """

  require Logger

  alias BlocksterV2.Repo
  alias BlocksterV2.ContentAutomation.{ContentGeneratedTopic, ContentGenerator}

  import Ecto.Query

  # ── Admin-Curated Events (Mnesia) ──

  @doc "Add an event to the upcoming_events Mnesia table."
  def add_event(attrs) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.to_unix()

    record = {
      :upcoming_events,
      id,
      attrs[:name] || attrs["name"],
      attrs[:event_type] || attrs["event_type"],
      parse_date(attrs[:start_date] || attrs["start_date"]),
      parse_date(attrs[:end_date] || attrs["end_date"]),
      attrs[:location] || attrs["location"],
      attrs[:url] || attrs["url"],
      attrs[:description] || attrs["description"],
      attrs[:tier] || attrs["tier"] || "notable",
      attrs[:added_by] || attrs["added_by"],
      false,
      now
    }

    :mnesia.dirty_write(record)
    {:ok, id}
  end

  @doc "List all upcoming events from Mnesia, optionally filtered."
  def list_events(opts \\ []) do
    records = :mnesia.dirty_select(:upcoming_events, [{{:upcoming_events, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8", :"$9", :"$10", :"$11", :"$12"}, [], [:"$$"]}])

    events =
      Enum.map(records, fn [id, name, event_type, start_date, end_date, location, url, description, tier, added_by, article_generated, created_at] ->
        %{
          id: id,
          name: name,
          event_type: event_type,
          start_date: start_date,
          end_date: end_date,
          location: location,
          url: url,
          description: description,
          tier: tier,
          added_by: added_by,
          article_generated: article_generated,
          created_at: created_at,
          source: :admin
        }
      end)

    events = case opts[:sort] do
      :start_date -> Enum.sort_by(events, & &1.start_date, Date)
      _ -> Enum.sort_by(events, & &1.start_date, Date)
    end

    # Filter by date range if provided
    events = case opts[:from] do
      %Date{} = from -> Enum.filter(events, fn e -> e.start_date && Date.compare(e.start_date, from) != :lt end)
      _ -> events
    end

    case opts[:to] do
      %Date{} = to -> Enum.filter(events, fn e -> e.start_date && Date.compare(e.start_date, to) != :gt end)
      _ -> events
    end
  end

  @doc "Delete an event from Mnesia by ID."
  def delete_event(id) do
    :mnesia.dirty_delete(:upcoming_events, id)
    :ok
  end

  @doc "Mark an event as having an article generated."
  def mark_article_generated(id) do
    case :mnesia.dirty_read(:upcoming_events, id) do
      [{:upcoming_events, ^id, name, event_type, start_date, end_date, location, url, description, tier, added_by, _article_generated, created_at}] ->
        record = {:upcoming_events, id, name, event_type, start_date, end_date, location, url, description, tier, added_by, true, created_at}
        :mnesia.dirty_write(record)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  # ── Combined Event Sources ──

  @doc """
  Get events for the coming week from both sources.
  Returns a merged, deduplicated list of events.
  """
  def get_events_for_week(start_date \\ Date.utc_today()) do
    week_end = Date.add(start_date, 10)

    # Source 1: Admin-curated events from Mnesia
    admin_events = list_events(from: start_date, to: week_end)

    # Source 2: Recent topics categorized as "events" from PostgreSQL
    feed_events = get_event_topics_from_db(14)

    merge_event_sources(admin_events, feed_events)
  end

  @doc "Generate a weekly roundup article from all event sources."
  def generate_weekly_roundup do
    today = Date.utc_today()
    all_events = get_events_for_week(today)

    if all_events == [] do
      Logger.info("[EventRoundup] No events found for weekly roundup, skipping")
      {:error, :no_events}
    else
      formatted = format_events_for_prompt(all_events)

      params = %{
        topic: "What's Coming This Week in Crypto — #{format_week_range(today)}",
        category: "events",
        content_type: "news",
        instructions: formatted,
        template: "weekly_roundup"
      }

      Logger.info("[EventRoundup] Generating weekly roundup with #{length(all_events)} events")
      ContentGenerator.generate_on_demand(params)
    end
  end

  @doc "Format events as structured text for the Claude prompt."
  def format_events_for_prompt(events) do
    grouped = Enum.group_by(events, & &1.event_type)

    sections =
      [
        {"conference", "Conferences & Summits"},
        {"upgrade", "Protocol Upgrades & Launches"},
        {"unlock", "Token Events (Unlocks, TGEs)"},
        {"regulatory", "Regulatory & Governance"},
        {"ecosystem", "Ecosystem Milestones"}
      ]
      |> Enum.map(fn {type, heading} ->
        items = Map.get(grouped, type, [])
        if items != [] do
          item_lines = Enum.map(items, &format_single_event/1) |> Enum.join("\n")
          "### #{heading}\n#{item_lines}"
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    # Include any ungrouped types
    known_types = ~w(conference upgrade unlock regulatory ecosystem)
    ungrouped = Enum.reject(events, fn e -> e.event_type in known_types end)

    if ungrouped != [] do
      other_lines = Enum.map(ungrouped, &format_single_event/1) |> Enum.join("\n")
      sections <> "\n\n### Other Events\n#{other_lines}"
    else
      sections
    end
  end

  # ── Private Functions ──

  defp format_single_event(event) do
    date_str = format_event_dates(event.start_date, event.end_date)
    location_str = if event.location, do: " | #{event.location}", else: ""
    url_str = if event.url, do: " | #{event.url}", else: ""
    tier_str = if event[:tier], do: " [#{event.tier}]", else: ""
    desc_str = if event.description && event.description != "", do: "\n  #{event.description}", else: ""

    "- **#{event.name}**#{tier_str}: #{date_str}#{location_str}#{url_str}#{desc_str}"
  end

  defp format_event_dates(nil, _), do: "Date TBD"
  defp format_event_dates(start_date, nil), do: Calendar.strftime(start_date, "%B %d, %Y")
  defp format_event_dates(start_date, end_date) do
    if Date.compare(start_date, end_date) == :eq do
      Calendar.strftime(start_date, "%B %d, %Y")
    else
      "#{Calendar.strftime(start_date, "%B %d")} — #{Calendar.strftime(end_date, "%B %d, %Y")}"
    end
  end

  defp format_week_range(today) do
    week_end = Date.add(today, 7)
    "#{Calendar.strftime(today, "%B %d")} — #{Calendar.strftime(week_end, "%B %d, %Y")}"
  end

  defp get_event_topics_from_db(days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400, :second)

    ContentGeneratedTopic
    |> where([t], t.category == "events")
    |> where([t], t.inserted_at >= ^cutoff)
    |> where([t], is_nil(t.published_at))
    |> order_by([t], desc: t.inserted_at)
    |> limit(20)
    |> Repo.all()
    |> Enum.map(fn topic ->
      %{
        name: topic.title,
        event_type: "ecosystem",
        start_date: nil,
        end_date: nil,
        location: nil,
        url: List.first(topic.source_urls),
        description: nil,
        tier: "notable",
        source: :feed
      }
    end)
  end

  defp merge_event_sources(admin_events, feed_events) do
    # Deduplicate by name similarity — admin events take priority
    admin_names = MapSet.new(admin_events, fn e -> String.downcase(e.name) end)

    unique_feed =
      Enum.reject(feed_events, fn fe ->
        fe_name = String.downcase(fe.name)
        Enum.any?(admin_names, fn admin_name ->
          String.jaro_distance(admin_name, fe_name) > 0.85
        end)
      end)

    admin_events ++ unique_feed
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(%Date{} = d), do: d
  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
