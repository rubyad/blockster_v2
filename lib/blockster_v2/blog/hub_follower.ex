defmodule BlocksterV2.Blog.HubFollower do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "hub_followers" do
    field :hub_id, :id, primary_key: true
    field :user_id, :id, primary_key: true

    # Notification preferences per hub
    field :notify_new_posts, :boolean, default: true
    field :notify_events, :boolean, default: true
    field :email_notifications, :boolean, default: true
    field :in_app_notifications, :boolean, default: true

    timestamps()
  end

  def changeset(hub_follower, attrs) do
    hub_follower
    |> cast(attrs, [:hub_id, :user_id, :notify_new_posts, :notify_events, :email_notifications, :in_app_notifications])
    |> validate_required([:hub_id, :user_id])
    |> unique_constraint([:hub_id, :user_id])
  end

  def notification_changeset(hub_follower, attrs) do
    hub_follower
    |> cast(attrs, [:notify_new_posts, :notify_events, :email_notifications, :in_app_notifications])
  end
end
