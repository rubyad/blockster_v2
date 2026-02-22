defmodule BlocksterV2.AdsManager.Schemas.Campaign do
  use Ecto.Schema
  import Ecto.Changeset

  @platforms ~w(x meta tiktok telegram)
  @statuses ~w(draft pending_approval active paused completed failed archived)
  @objectives ~w(traffic signups purchases engagement)
  @content_types ~w(post product game general)
  @creators ~w(ai admin)

  schema "ad_campaigns" do
    field :platform, :string
    field :platform_campaign_id, :string
    field :name, :string
    field :status, :string, default: "draft"
    field :objective, :string

    field :content_type, :string
    field :content_id, :integer

    field :budget_daily, :decimal
    field :budget_lifetime, :decimal
    field :spend_total, :decimal, default: Decimal.new(0)

    field :targeting_config, :map, default: %{}

    field :created_by, :string, default: "ai"
    field :ai_confidence_score, :decimal
    field :admin_override, :boolean, default: false
    field :admin_notes, :string

    field :scheduled_start, :utc_datetime
    field :scheduled_end, :utc_datetime

    belongs_to :account, BlocksterV2.AdsManager.Schemas.PlatformAccount
    belongs_to :created_by_user, BlocksterV2.Accounts.User, foreign_key: :created_by_user_id

    has_many :creatives, BlocksterV2.AdsManager.Schemas.Creative
    has_many :decisions, BlocksterV2.AdsManager.Schemas.Decision

    timestamps(type: :utc_datetime)
  end

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [:platform, :platform_campaign_id, :name, :status, :objective,
                    :content_type, :content_id, :budget_daily, :budget_lifetime, :spend_total,
                    :targeting_config, :created_by, :created_by_user_id, :ai_confidence_score,
                    :admin_override, :admin_notes, :scheduled_start, :scheduled_end, :account_id])
    |> validate_required([:platform, :name, :objective])
    |> validate_inclusion(:platform, @platforms)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:objective, @objectives)
    |> validate_inclusion(:content_type, @content_types ++ [nil])
    |> validate_inclusion(:created_by, @creators)
  end

  def status_changeset(campaign, status) do
    campaign
    |> change(status: status)
    |> validate_inclusion(:status, @statuses)
    |> validate_status_transition(campaign.status, status)
  end

  defp validate_status_transition(changeset, from, to) do
    valid_transitions = %{
      "draft" => ~w(pending_approval active failed),
      "pending_approval" => ~w(active draft failed),
      "active" => ~w(paused completed failed),
      "paused" => ~w(active completed archived),
      "completed" => ~w(archived),
      "failed" => ~w(draft archived)
    }

    allowed = Map.get(valid_transitions, from, [])

    if to in allowed do
      changeset
    else
      add_error(changeset, :status, "cannot transition from #{from} to #{to}")
    end
  end
end
