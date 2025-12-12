defmodule BlocksterV2.Social.ShareCampaign do
  use Ecto.Schema
  import Ecto.Changeset

  alias BlocksterV2.Blog.Post
  alias BlocksterV2.Social.ShareReward

  schema "share_campaigns" do
    belongs_to :post, Post
    has_many :share_rewards, ShareReward, foreign_key: :campaign_id

    field :tweet_id, :string
    field :tweet_url, :string
    field :tweet_text, :string
    field :bux_reward, :integer, default: 50
    field :is_active, :boolean, default: true
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :max_participants, :integer
    field :total_shares, :integer, default: 0

    timestamps()
  end

  @required_fields [:post_id, :tweet_id, :tweet_url]
  @optional_fields [:tweet_text, :bux_reward, :is_active, :starts_at, :ends_at, :max_participants, :total_shares]

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:bux_reward, greater_than_or_equal_to: 0)
    |> validate_number(:max_participants, greater_than: 0)
    |> unique_constraint(:post_id)
    |> validate_dates()
  end

  defp validate_dates(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt do
      add_error(changeset, :ends_at, "must be after starts_at")
    else
      changeset
    end
  end

  def active?(%__MODULE__{is_active: false}), do: false
  def active?(%__MODULE__{starts_at: starts_at, ends_at: ends_at, max_participants: max, total_shares: shares}) do
    now = DateTime.utc_now()

    within_time_window = cond do
      starts_at && DateTime.compare(now, starts_at) == :lt -> false
      ends_at && DateTime.compare(now, ends_at) == :gt -> false
      true -> true
    end

    under_participant_limit = is_nil(max) || shares < max

    within_time_window && under_participant_limit
  end
end
