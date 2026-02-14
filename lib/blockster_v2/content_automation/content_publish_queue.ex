defmodule BlocksterV2.ContentAutomation.ContentPublishQueue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @valid_statuses ["pending", "draft", "approved", "published", "rejected"]

  schema "content_publish_queue" do
    field :article_data, :map
    field :scheduled_at, :utc_datetime
    field :status, :string, default: "pending"
    field :pipeline_id, :binary_id
    field :rejected_reason, :string
    field :reviewed_at, :utc_datetime
    field :revision_count, :integer, default: 0

    belongs_to :author, BlocksterV2.Accounts.User
    belongs_to :topic, BlocksterV2.ContentAutomation.ContentGeneratedTopic, type: :binary_id
    belongs_to :post, BlocksterV2.Blog.Post
    belongs_to :reviewer, BlocksterV2.Accounts.User, foreign_key: :reviewed_by

    has_many :revisions, BlocksterV2.ContentAutomation.ContentRevisionHistory, foreign_key: :queue_entry_id

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:article_data, :author_id, :scheduled_at, :status, :pipeline_id,
                    :topic_id, :post_id, :rejected_reason, :reviewed_at, :reviewed_by,
                    :revision_count])
    |> validate_required([:article_data, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
