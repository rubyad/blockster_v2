defmodule BlocksterV2.Events.EventAttendee do
  use Ecto.Schema
  import Ecto.Changeset

  schema "event_attendees" do
    belongs_to :event, BlocksterV2.Events.Event
    belongs_to :user, BlocksterV2.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(event_attendee, attrs) do
    event_attendee
    |> cast(attrs, [:event_id, :user_id])
    |> validate_required([:event_id, :user_id])
    |> unique_constraint([:event_id, :user_id])
  end
end
