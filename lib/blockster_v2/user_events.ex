defmodule BlocksterV2.UserEvents do
  @moduledoc """
  Fire-and-forget event tracking system. Records user behavior events
  for personalization, analytics, and notification optimization.

  Events are appended to the user_events table and periodically aggregated
  into user_profiles by the ProfileRecalcWorker.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Notifications.{UserEvent, UserProfile}

  require Logger

  @doc """
  Track a single user event. Fire-and-forget — never blocks the caller.
  Returns :ok immediately. Event insertion happens asynchronously.

  ## Examples

      UserEvents.track(user_id, "article_view", %{target_type: "post", target_id: 42})
      UserEvents.track(user_id, "purchase_complete", %{order_id: 123, total: "45.00"})
  """
  def track(user_id, event_type, metadata \\ %{}) when is_integer(user_id) and is_binary(event_type) do
    Task.start(fn ->
      attrs = %{
        user_id: user_id,
        event_type: event_type,
        event_category: UserEvent.categorize(event_type),
        target_type: metadata[:target_type] || metadata["target_type"],
        target_id: stringify(metadata[:target_id] || metadata["target_id"]),
        metadata: drop_extracted_keys(metadata),
        session_id: metadata[:session_id] || metadata["session_id"],
        source: metadata[:source] || metadata["source"] || "web",
        referrer: metadata[:referrer] || metadata["referrer"]
      }

      case UserEvent.changeset(attrs) |> Repo.insert() do
        {:ok, _event} ->
          increment_events_since_calc(user_id)
          broadcast_event(user_id, event_type, metadata)

        {:error, changeset} ->
          Logger.warning("Failed to track event #{event_type} for user #{user_id}: #{inspect(changeset.errors)}")
      end
    end)

    :ok
  end

  @doc """
  Track a single user event synchronously. Returns {:ok, event} or {:error, changeset}.
  Use this when you need to confirm the event was recorded (e.g., in tests).
  """
  def track_sync(user_id, event_type, metadata \\ %{}) when is_integer(user_id) do
    attrs = %{
      user_id: user_id,
      event_type: event_type,
      event_category: UserEvent.categorize(event_type),
      target_type: metadata[:target_type] || metadata["target_type"],
      target_id: stringify(metadata[:target_id] || metadata["target_id"]),
      metadata: drop_extracted_keys(metadata),
      session_id: metadata[:session_id] || metadata["session_id"],
      source: metadata[:source] || metadata["source"] || "web",
      referrer: metadata[:referrer] || metadata["referrer"]
    }

    case UserEvent.changeset(attrs) |> Repo.insert() do
      {:ok, event} ->
        increment_events_since_calc(user_id)
        broadcast_event(user_id, event_type, metadata)
        {:ok, event}

      error ->
        error
    end
  end

  @doc """
  Batch insert multiple events. More efficient for high-volume tracking.
  Events should be pre-formatted maps matching the user_events schema.
  """
  def track_batch(events) when is_list(events) do
    Task.start(fn ->
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      rows =
        Enum.map(events, fn event ->
          %{
            user_id: event[:user_id] || event["user_id"],
            event_type: event[:event_type] || event["event_type"],
            event_category: UserEvent.categorize(event[:event_type] || event["event_type"]),
            target_type: event[:target_type] || event["target_type"],
            target_id: stringify(event[:target_id] || event["target_id"]),
            metadata: event[:metadata] || event["metadata"] || %{},
            session_id: event[:session_id] || event["session_id"],
            source: event[:source] || event["source"] || "web",
            referrer: event[:referrer] || event["referrer"],
            inserted_at: now
          }
        end)

      Repo.insert_all("user_events", rows, on_conflict: :nothing)
    end)

    :ok
  end

  @doc "Get events for a user within a time range."
  def get_events(user_id, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    event_type = Keyword.get(opts, :event_type)
    limit = Keyword.get(opts, :limit, 1000)

    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    UserEvent
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.inserted_at >= ^since)
    |> maybe_filter_event_type(event_type)
    |> order_by([e], [desc: e.inserted_at, desc: e.id])
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Count events of a specific type for a user within a time range."
  def count_events(user_id, event_type, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    UserEvent
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.event_type == ^event_type)
    |> where([e], e.inserted_at >= ^since)
    |> Repo.aggregate(:count, :id)
  end

  @doc "Get the most recent event of a specific type for a user."
  def get_last_event(user_id, event_type) do
    UserEvent
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.event_type == ^event_type)
    |> order_by([e], [desc: e.inserted_at, desc: e.id])
    |> limit(1)
    |> Repo.one()
  end

  @doc "Get distinct event types for a user within a time range."
  def get_event_types(user_id, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    UserEvent
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.inserted_at >= ^since)
    |> select([e], e.event_type)
    |> distinct(true)
    |> Repo.all()
  end

  @doc "Get events grouped by type with counts for a user."
  def event_summary(user_id, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    UserEvent
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.inserted_at >= ^since)
    |> group_by([e], e.event_type)
    |> select([e], {e.event_type, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Get user IDs that have events since their last profile calculation."
  def users_needing_profile_update(min_events \\ 1) do
    from(p in UserProfile,
      where: p.events_since_last_calc >= ^min_events,
      select: p.user_id,
      order_by: [desc: p.events_since_last_calc]
    )
    |> Repo.all()
  end

  @doc "Get user IDs with events but no profile yet."
  def users_without_profiles do
    from(e in UserEvent,
      left_join: p in UserProfile, on: p.user_id == e.user_id,
      where: is_nil(p.id),
      select: e.user_id,
      distinct: true
    )
    |> Repo.all()
  end

  # ============ Profile CRUD ============

  @doc "Get or create a user profile."
  def get_or_create_profile(user_id) do
    case Repo.get_by(UserProfile, user_id: user_id) do
      nil ->
        %UserProfile{}
        |> UserProfile.changeset(%{user_id: user_id})
        |> Repo.insert()

      profile ->
        {:ok, profile}
    end
  end

  @doc "Get a user profile (returns nil if not found)."
  def get_profile(user_id) do
    Repo.get_by(UserProfile, user_id: user_id)
  end

  @doc "Upsert a user profile with calculated data."
  def upsert_profile(user_id, attrs) do
    case Repo.get_by(UserProfile, user_id: user_id) do
      nil ->
        %UserProfile{}
        |> UserProfile.changeset(Map.put(attrs, :user_id, user_id))
        |> Repo.insert()

      profile ->
        profile
        |> UserProfile.changeset(attrs)
        |> Repo.update()
    end
  end

  # ============ Private Helpers ============

  defp broadcast_event(user_id, event_type, metadata) do
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "user_events",
      {:user_event, user_id, event_type, metadata}
    )
  rescue
    _ -> :ok
  end

  defp increment_events_since_calc(user_id) do
    from(p in UserProfile, where: p.user_id == ^user_id)
    |> Repo.update_all(inc: [events_since_last_calc: 1])
  end

  defp maybe_filter_event_type(query, nil), do: query
  defp maybe_filter_event_type(query, event_type) do
    where(query, [e], e.event_type == ^event_type)
  end

  @extracted_keys [
    :target_type, :target_id, :session_id, :source, :referrer,
    "target_type", "target_id", "session_id", "source", "referrer"
  ]

  defp drop_extracted_keys(metadata) do
    metadata
    |> Map.drop(@extracted_keys)
    |> stringify_keys()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp stringify(nil), do: nil
  defp stringify(val) when is_binary(val), do: val
  defp stringify(val), do: to_string(val)
end
