defmodule BlocksterV2.Events do
  @moduledoc """
  The Events context.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.Repo

  alias BlocksterV2.Events.Event
  alias BlocksterV2.Events.EventAttendee

  @doc """
  Returns the list of events.

  ## Examples

      iex> list_events()
      [%Event{}, ...]

  """
  def list_events do
    Repo.all(Event)
    |> Repo.preload([:organizer, :hub, :attendees, :tags])
  end

  @doc """
  Returns all events (including drafts, published, and cancelled).
  """
  def list_all_events do
    from(e in Event,
      order_by: [desc: e.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Returns the list of published events.
  """
  def list_published_events do
    from(e in Event,
      where: e.status == "published",
      order_by: [desc: e.date],
      preload: [:organizer, :hub, :attendees, :tags]
    )
    |> Repo.all()
  end

  @doc """
  Returns the list of events for a specific hub.
  """
  def list_events_by_hub(hub_id) do
    from(e in Event,
      where: e.hub_id == ^hub_id and e.status == "published",
      order_by: [desc: e.date],
      preload: [:organizer, :hub, :attendees, :tags]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single event by slug.

  Returns nil if the Event does not exist.

  ## Examples

      iex> get_event_by_slug("my-event")
      %Event{}

      iex> get_event_by_slug("non-existent")
      nil

  """
  def get_event_by_slug(slug) do
    Repo.get_by(Event, slug: slug)
  end

  @doc """
  Returns the list of events organized by a specific user.
  """
  def list_events_by_organizer(organizer_id) do
    from(e in Event,
      where: e.organizer_id == ^organizer_id,
      order_by: [desc: e.date],
      preload: [:organizer, :hub, :attendees, :tags]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single event.

  Raises `Ecto.NoResultsError` if the Event does not exist.

  ## Examples

      iex> get_event!(123)
      %Event{}

      iex> get_event!(456)
      ** (Ecto.NoResultsError)

  """
  def get_event!(id) do
    Repo.get!(Event, id)
    |> Repo.preload([:organizer, :hub, :attendees, :tags])
  end

  @doc """
  Gets an event by slug.
  """
  def get_event_by_slug(slug) do
    from(e in Event,
      where: e.slug == ^slug,
      preload: [:organizer, :hub, :attendees, :tags]
    )
    |> Repo.one()
  end

  @doc """
  Creates an event.

  ## Examples

      iex> create_event(%{field: value})
      {:ok, %Event{}}

      iex> create_event(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an event.

  ## Examples

      iex> update_event(event, %{field: new_value})
      {:ok, %Event{}}

      iex> update_event(event, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an event.

  ## Examples

      iex> delete_event(event)
      {:ok, %Event{}}

      iex> delete_event(event)
      {:error, %Ecto.Changeset{}}

  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking event changes.

  ## Examples

      iex> change_event(event)
      %Ecto.Changeset{data: %Event{}}

  """
  def change_event(%Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs)
  end

  @doc """
  Registers a user as an attendee for an event.
  """
  def register_attendee(event_id, user_id) do
    %EventAttendee{}
    |> EventAttendee.changeset(%{event_id: event_id, user_id: user_id})
    |> Repo.insert()
  end

  @doc """
  Unregisters a user from an event.
  """
  def unregister_attendee(event_id, user_id) do
    from(ea in EventAttendee,
      where: ea.event_id == ^event_id and ea.user_id == ^user_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Checks if a user is attending an event.
  """
  def attending?(event_id, user_id) do
    from(ea in EventAttendee,
      where: ea.event_id == ^event_id and ea.user_id == ^user_id
    )
    |> Repo.exists?()
  end

  @doc """
  Gets the count of attendees for an event.
  """
  def count_attendees(event_id) do
    from(ea in EventAttendee,
      where: ea.event_id == ^event_id,
      select: count(ea.id)
    )
    |> Repo.one()
  end
end
