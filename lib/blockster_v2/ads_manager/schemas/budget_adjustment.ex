defmodule BlocksterV2.AdsManager.Schemas.BudgetAdjustment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ad_budget_adjustments" do
    field :old_amount, :decimal
    field :new_amount, :decimal
    field :reason, :string
    field :decided_by, :string
    field :inserted_at, :utc_datetime

    belongs_to :budget, BlocksterV2.AdsManager.Schemas.Budget
    belongs_to :campaign, BlocksterV2.AdsManager.Schemas.Campaign
  end

  def changeset(adjustment, attrs) do
    adjustment
    |> cast(attrs, [:budget_id, :campaign_id, :old_amount, :new_amount, :reason, :decided_by])
    |> validate_required([:reason, :decided_by])
    |> put_change(:inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
