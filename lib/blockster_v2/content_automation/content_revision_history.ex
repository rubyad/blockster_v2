defmodule BlocksterV2.ContentAutomation.ContentRevisionHistory do
  @moduledoc """
  Tracks revision history for queue entries.

  Each row captures a single revision request: the admin's instruction,
  the article state before and after the revision, and the outcome status.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @valid_statuses ["pending", "completed", "failed"]

  schema "content_revision_history" do
    field :instruction, :string
    field :revision_number, :integer
    field :article_data_before, :map
    field :article_data_after, :map
    field :status, :string, default: "pending"
    field :error_reason, :string

    belongs_to :queue_entry, BlocksterV2.ContentAutomation.ContentPublishQueue, type: :binary_id
    belongs_to :requester, BlocksterV2.Accounts.User, foreign_key: :requested_by

    timestamps()
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [
      :queue_entry_id, :instruction, :revision_number, :article_data_before,
      :article_data_after, :status, :error_reason, :requested_by
    ])
    |> validate_required([:queue_entry_id, :instruction, :revision_number, :article_data_before])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
