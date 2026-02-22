defmodule BlocksterV2.Notifications.Campaign do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_types ~w(email_blast push_notification sms_blast multi_channel)
  @valid_statuses ~w(draft scheduled sending sent cancelled)
  @valid_audiences ~w(all hub_followers active_users dormant_users phone_verified custom
                       bux_gamers rogue_gamers bux_balance rogue_holders)

  schema "notification_campaigns" do
    field :name, :string
    field :type, :string
    field :status, :string, default: "draft"

    # Content
    field :subject, :string
    field :title, :string
    field :body, :string
    field :plain_text_body, :string
    field :image_url, :string
    field :action_url, :string
    field :action_label, :string

    # Targeting
    field :target_audience, :string, default: "all"
    field :target_criteria, :map, default: %{}

    # Channels
    field :send_email, :boolean, default: true
    field :send_sms, :boolean, default: false
    field :send_in_app, :boolean, default: true

    # Scheduling
    field :scheduled_at, :utc_datetime
    field :sent_at, :utc_datetime
    field :timezone_aware, :boolean, default: true

    # Stats
    field :total_recipients, :integer, default: 0
    field :emails_sent, :integer, default: 0
    field :emails_opened, :integer, default: 0
    field :emails_clicked, :integer, default: 0
    field :sms_sent, :integer, default: 0
    field :in_app_delivered, :integer, default: 0
    field :in_app_read, :integer, default: 0

    belongs_to :target_hub, BlocksterV2.Blog.Hub
    belongs_to :created_by, BlocksterV2.Accounts.User

    has_many :notifications, BlocksterV2.Notifications.Notification
    has_many :email_logs, BlocksterV2.Notifications.EmailLog

    timestamps()
  end

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [
      :name, :type, :status, :subject, :title, :body, :plain_text_body,
      :image_url, :action_url, :action_label, :target_audience, :target_hub_id,
      :target_criteria, :send_email, :send_sms, :send_in_app, :scheduled_at,
      :sent_at, :timezone_aware, :created_by_id
    ])
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:target_audience, @valid_audiences)
    |> foreign_key_constraint(:target_hub_id)
    |> foreign_key_constraint(:created_by_id)
  end

  def status_changeset(campaign, status) do
    campaign
    |> cast(%{status: status}, [:status])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
