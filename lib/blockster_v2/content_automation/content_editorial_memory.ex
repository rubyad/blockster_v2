defmodule BlocksterV2.ContentAutomation.ContentEditorialMemory do
  @moduledoc """
  Persistent editorial memory entries that shape all future content generation.

  Each entry is a brand guideline (e.g. "never use the phrase 'crypto winter'")
  that gets injected into every article generation prompt across all author personas.

  Supports soft-delete via `active` flag and categorization for organization.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @valid_categories ["global", "tone", "terminology", "topics", "formatting"]

  schema "content_editorial_memory" do
    field :instruction, :string
    field :category, :string, default: "global"
    field :active, :boolean, default: true

    belongs_to :creator, BlocksterV2.Accounts.User, foreign_key: :created_by
    belongs_to :source_queue_entry, BlocksterV2.ContentAutomation.ContentPublishQueue,
      type: :binary_id,
      foreign_key: :source_queue_entry_id

    timestamps()
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:instruction, :category, :active, :created_by, :source_queue_entry_id])
    |> validate_required([:instruction])
    |> validate_inclusion(:category, @valid_categories)
    |> validate_length(:instruction, min: 5, max: 500)
  end
end
