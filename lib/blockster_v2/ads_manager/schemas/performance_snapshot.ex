defmodule BlocksterV2.AdsManager.Schemas.PerformanceSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ad_performance_snapshots" do
    field :platform, :string
    field :snapshot_at, :utc_datetime

    field :impressions, :integer, default: 0
    field :clicks, :integer, default: 0
    field :conversions, :integer, default: 0
    field :spend, :decimal, default: Decimal.new(0)

    field :ctr, :decimal
    field :cpc, :decimal
    field :cpm, :decimal
    field :roas, :decimal

    field :platform_metrics, :map, default: %{}
    field :inserted_at, :utc_datetime

    belongs_to :campaign, BlocksterV2.AdsManager.Schemas.Campaign
    belongs_to :creative, BlocksterV2.AdsManager.Schemas.Creative
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:campaign_id, :creative_id, :platform, :snapshot_at,
                    :impressions, :clicks, :conversions, :spend,
                    :ctr, :cpc, :cpm, :roas, :platform_metrics])
    |> validate_required([:platform, :snapshot_at])
    |> compute_metrics()
    |> put_change(:inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp compute_metrics(changeset) do
    impressions = get_field(changeset, :impressions) || 0
    clicks = get_field(changeset, :clicks) || 0
    spend = get_field(changeset, :spend) || Decimal.new(0)

    changeset
    |> maybe_put_ctr(clicks, impressions)
    |> maybe_put_cpc(spend, clicks)
    |> maybe_put_cpm(spend, impressions)
  end

  defp maybe_put_ctr(changeset, clicks, impressions) when impressions > 0 do
    put_change(changeset, :ctr, Decimal.div(Decimal.new(clicks), Decimal.new(impressions)))
  end
  defp maybe_put_ctr(changeset, _, _), do: changeset

  defp maybe_put_cpc(changeset, spend, clicks) when clicks > 0 do
    put_change(changeset, :cpc, Decimal.div(spend, Decimal.new(clicks)))
  end
  defp maybe_put_cpc(changeset, _, _), do: changeset

  defp maybe_put_cpm(changeset, spend, impressions) when impressions > 0 do
    cpm = Decimal.mult(Decimal.div(spend, Decimal.new(impressions)), Decimal.new(1000))
    put_change(changeset, :cpm, cpm)
  end
  defp maybe_put_cpm(changeset, _, _), do: changeset
end
