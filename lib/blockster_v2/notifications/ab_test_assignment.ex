defmodule BlocksterV2.Notifications.ABTestAssignment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ab_test_assignments" do
    field :variant_id, :string
    field :opened, :boolean, default: false
    field :clicked, :boolean, default: false

    belongs_to :ab_test, BlocksterV2.Notifications.ABTest
    belongs_to :user, BlocksterV2.Accounts.User
    belongs_to :email_log, BlocksterV2.Notifications.EmailLog

    timestamps(updated_at: false)
  end

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:ab_test_id, :user_id, :variant_id, :email_log_id, :opened, :clicked])
    |> validate_required([:ab_test_id, :user_id, :variant_id])
    |> unique_constraint([:ab_test_id, :user_id])
    |> foreign_key_constraint(:ab_test_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:email_log_id)
  end
end
