defmodule BlocksterV2.AdsManager.Schemas.PlatformAccount do
  use Ecto.Schema
  import Ecto.Changeset

  @platforms ~w(x meta tiktok telegram)
  @statuses ~w(active suspended disabled)

  schema "ad_platform_accounts" do
    field :platform, :string
    field :account_name, :string
    field :platform_account_id, :string
    field :status, :string, default: "active"
    field :credentials_ref, :string
    field :daily_budget_limit, :decimal
    field :monthly_budget_limit, :decimal
    field :notes, :string

    has_many :campaigns, BlocksterV2.AdsManager.Schemas.Campaign, foreign_key: :account_id

    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:platform, :account_name, :platform_account_id, :status, :credentials_ref,
                    :daily_budget_limit, :monthly_budget_limit, :notes])
    |> validate_required([:platform, :account_name])
    |> validate_inclusion(:platform, @platforms)
    |> validate_inclusion(:status, @statuses)
  end
end
