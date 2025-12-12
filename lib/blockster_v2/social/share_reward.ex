defmodule BlocksterV2.Social.ShareReward do
  use Ecto.Schema
  import Ecto.Changeset

  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Social.{ShareCampaign, XConnection}

  @statuses ~w(pending verified rewarded failed)

  schema "share_rewards" do
    belongs_to :user, User
    belongs_to :campaign, ShareCampaign
    belongs_to :x_connection, XConnection

    field :retweet_id, :string
    field :status, :string, default: "pending"
    field :bux_rewarded, :decimal
    field :verified_at, :utc_datetime
    field :rewarded_at, :utc_datetime
    field :failure_reason, :string

    timestamps()
  end

  @required_fields [:user_id, :campaign_id]
  @optional_fields [:x_connection_id, :retweet_id, :status, :bux_rewarded, :verified_at, :rewarded_at, :failure_reason]

  def changeset(reward, attrs) do
    reward
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:bux_rewarded, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :campaign_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:x_connection_id)
  end

  def verify_changeset(reward, attrs) do
    reward
    |> cast(attrs, [:retweet_id, :status, :verified_at])
    |> put_change(:status, "verified")
    |> put_change(:verified_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def reward_changeset(reward, bux_amount) do
    reward
    |> change(%{
      status: "rewarded",
      bux_rewarded: bux_amount,
      rewarded_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def fail_changeset(reward, reason) do
    reward
    |> change(%{
      status: "failed",
      failure_reason: reason
    })
  end

  def pending?(%__MODULE__{status: "pending"}), do: true
  def pending?(_), do: false

  def verified?(%__MODULE__{status: "verified"}), do: true
  def verified?(_), do: false

  def rewarded?(%__MODULE__{status: "rewarded"}), do: true
  def rewarded?(_), do: false

  def failed?(%__MODULE__{status: "failed"}), do: true
  def failed?(_), do: false
end
