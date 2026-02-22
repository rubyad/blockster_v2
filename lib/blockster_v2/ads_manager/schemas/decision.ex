defmodule BlocksterV2.AdsManager.Schemas.Decision do
  use Ecto.Schema
  import Ecto.Changeset

  @decision_types ~w(create_campaign pause_campaign resume_campaign adjust_budget adjust_bid
                     create_offer generate_creative rebalance_budget evaluate_post
                     performance_check anomaly_detected)
  @outcomes ~w(success failure pending_approval skipped)

  schema "ai_ads_decisions" do
    field :decision_type, :string
    field :input_context, :map
    field :reasoning, :string
    field :action_taken, :map
    field :outcome, :string
    field :outcome_details, :map
    field :budget_impact, :decimal

    field :platform, :string
    field :admin_instruction_id, :integer
    field :inserted_at, :utc_datetime

    belongs_to :campaign, BlocksterV2.AdsManager.Schemas.Campaign
  end

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, [:decision_type, :input_context, :reasoning, :action_taken, :outcome,
                    :outcome_details, :budget_impact, :campaign_id, :platform, :admin_instruction_id])
    |> validate_required([:decision_type, :input_context, :reasoning, :action_taken, :outcome])
    |> validate_inclusion(:decision_type, @decision_types)
    |> validate_inclusion(:outcome, @outcomes)
    |> put_change(:inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
