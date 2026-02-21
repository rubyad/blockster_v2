defmodule BlocksterV2.Notifications.EmailLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notification_email_log" do
    field :email_type, :string
    field :subject, :string
    field :sent_at, :utc_datetime
    field :opened_at, :utc_datetime
    field :clicked_at, :utc_datetime
    field :bounced, :boolean, default: false
    field :unsubscribed, :boolean, default: false
    field :sendgrid_message_id, :string

    belongs_to :user, BlocksterV2.Accounts.User
    belongs_to :notification, BlocksterV2.Notifications.Notification
    belongs_to :campaign, BlocksterV2.Notifications.Campaign

    timestamps()
  end

  def changeset(email_log, attrs) do
    email_log
    |> cast(attrs, [
      :user_id, :notification_id, :campaign_id, :email_type,
      :subject, :sent_at, :sendgrid_message_id
    ])
    |> validate_required([:user_id, :email_type, :sent_at])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:notification_id)
    |> foreign_key_constraint(:campaign_id)
  end
end
