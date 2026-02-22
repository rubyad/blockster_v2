defmodule BlocksterV2.AdsManager.Schemas.Budget do
  use Ecto.Schema
  import Ecto.Changeset

  @period_types ~w(daily weekly monthly)
  @statuses ~w(active exhausted closed)

  schema "ad_budgets" do
    field :platform, :string
    field :period_type, :string
    field :period_start, :date
    field :period_end, :date
    field :allocated_amount, :decimal
    field :spent_amount, :decimal, default: Decimal.new(0)
    field :status, :string, default: "active"

    timestamps(type: :utc_datetime)
  end

  def changeset(budget, attrs) do
    budget
    |> cast(attrs, [:platform, :period_type, :period_start, :period_end,
                    :allocated_amount, :spent_amount, :status])
    |> validate_required([:period_type, :period_start, :period_end, :allocated_amount])
    |> validate_inclusion(:period_type, @period_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:allocated_amount, greater_than: 0)
  end

  def remaining_amount(%__MODULE__{allocated_amount: allocated, spent_amount: spent}) do
    Decimal.sub(allocated, spent)
  end
end
