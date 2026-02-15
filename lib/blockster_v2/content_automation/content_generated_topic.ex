defmodule BlocksterV2.ContentAutomation.ContentGeneratedTopic do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "content_generated_topics" do
    field :title, :string
    field :category, :string
    field :source_urls, {:array, :string}, default: []
    field :rank_score, :float
    field :source_count, :integer
    field :pipeline_id, :binary_id
    field :published_at, :utc_datetime
    field :content_type, :string, default: "news"
    field :offer_type, :string
    field :expires_at, :utc_datetime

    belongs_to :article, BlocksterV2.Blog.Post
    belongs_to :author, BlocksterV2.Accounts.User

    has_many :feed_items, BlocksterV2.ContentAutomation.ContentFeedItem, foreign_key: :topic_cluster_id

    timestamps()
  end

  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [:title, :category, :source_urls, :rank_score, :source_count, :article_id, :author_id, :pipeline_id, :published_at, :content_type, :offer_type, :expires_at])
    |> validate_required([:title])
  end
end
