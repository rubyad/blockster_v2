defmodule BlocksterV2.Notifications.ABTest do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ~w(running completed winner_applied)
  @valid_elements ~w(subject body cta_text cta_color send_time image article_count layout)

  schema "ab_tests" do
    field :name, :string
    field :email_type, :string
    field :element_tested, :string
    field :status, :string, default: "running"
    field :variants, {:array, :map}, default: []
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime
    field :min_sample_size, :integer, default: 100
    field :confidence_threshold, :float, default: 0.95
    field :winning_variant, :string
    field :results, :map, default: %{}

    has_many :assignments, BlocksterV2.Notifications.ABTestAssignment

    timestamps()
  end

  def changeset(test, attrs) do
    test
    |> cast(attrs, [
      :name, :email_type, :element_tested, :status, :variants,
      :start_date, :end_date, :min_sample_size, :confidence_threshold,
      :winning_variant, :results
    ])
    |> validate_required([:name, :email_type, :element_tested, :start_date])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:element_tested, @valid_elements)
    |> validate_number(:min_sample_size, greater_than: 0)
    |> validate_number(:confidence_threshold, greater_than: 0.0, less_than_or_equal_to: 1.0)
  end

  def valid_statuses, do: @valid_statuses
  def valid_elements, do: @valid_elements
end
