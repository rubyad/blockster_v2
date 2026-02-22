defmodule BlocksterV2.AdsManager.Schemas.Instruction do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "ai_ads_instructions" do
    field :instruction_text, :string
    field :parsed_intent, :map
    field :actions_taken, :map
    field :status, :string, default: "pending"
    field :completed_at, :utc_datetime
    field :inserted_at, :utc_datetime

    belongs_to :admin_user, BlocksterV2.Accounts.User, foreign_key: :admin_user_id
  end

  def changeset(instruction, attrs) do
    instruction
    |> cast(attrs, [:admin_user_id, :instruction_text, :parsed_intent, :actions_taken,
                    :status, :completed_at])
    |> validate_required([:admin_user_id, :instruction_text])
    |> validate_inclusion(:status, @statuses)
    |> put_change(:inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
