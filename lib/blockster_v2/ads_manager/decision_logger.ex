defmodule BlocksterV2.AdsManager.DecisionLogger do
  @moduledoc """
  Audit trail for all AI ads decisions. Every action the AI takes is logged
  with full context, reasoning, and outcome.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.AdsManager.Schemas.Decision

  require Logger

  def log_decision(attrs) do
    %Decision{}
    |> Decision.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, decision} ->
        Logger.info("[AdsDecisionLogger] #{attrs[:decision_type]} — #{attrs[:outcome]}")
        {:ok, decision}

      {:error, changeset} ->
        Logger.error("[AdsDecisionLogger] Failed to log decision: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def list_decisions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    campaign_id = Keyword.get(opts, :campaign_id)
    decision_type = Keyword.get(opts, :decision_type)

    Decision
    |> maybe_filter_campaign(campaign_id)
    |> maybe_filter_type(decision_type)
    |> order_by([d], desc: d.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def recent_decisions(limit \\ 10) do
    Decision
    |> order_by([d], desc: d.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def decisions_for_campaign(campaign_id) do
    Decision
    |> where([d], d.campaign_id == ^campaign_id)
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  def today_decision_count do
    today_start = DateTime.utc_now() |> DateTime.to_date() |> DateTime.new!(~T[00:00:00])

    Decision
    |> where([d], d.inserted_at >= ^today_start)
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_filter_campaign(query, nil), do: query
  defp maybe_filter_campaign(query, id), do: where(query, [d], d.campaign_id == ^id)

  defp maybe_filter_type(query, nil), do: query
  defp maybe_filter_type(query, type), do: where(query, [d], d.decision_type == ^type)
end
