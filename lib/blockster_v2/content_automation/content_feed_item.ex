defmodule BlocksterV2.ContentAutomation.ContentFeedItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "content_feed_items" do
    field :url, :string
    field :title, :string
    field :summary, :string
    field :source, :string
    field :tier, :string
    field :weight, :float, default: 1.0
    field :published_at, :utc_datetime
    field :fetched_at, :utc_datetime
    field :processed, :boolean, default: false

    belongs_to :topic_cluster, BlocksterV2.ContentAutomation.ContentGeneratedTopic, type: :binary_id

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:url, :title, :summary, :source, :tier, :weight, :published_at, :fetched_at, :processed, :topic_cluster_id])
    |> validate_required([:url, :title, :source, :tier, :fetched_at])
    |> validate_inclusion(:tier, ["premium", "standard"])
    |> unique_constraint(:url)
  end
end
