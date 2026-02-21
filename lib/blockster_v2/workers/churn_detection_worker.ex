defmodule BlocksterV2.Workers.ChurnDetectionWorker do
  @moduledoc """
  Daily scan for at-risk users. Evaluates churn risk and fires
  appropriate intervention notifications.
  Scheduled daily at 6 AM UTC.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias BlocksterV2.Notifications.{ChurnPredictor, RevivalEngine}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    at_risk_profiles = ChurnPredictor.get_at_risk_users(0.5)

    Logger.info("ChurnDetectionWorker: found #{length(at_risk_profiles)} at-risk users")

    interventions_fired =
      Enum.reduce(at_risk_profiles, 0, fn profile, count ->
        if !ChurnPredictor.intervention_sent_recently?(profile.user_id) do
          prediction = ChurnPredictor.predict_churn(profile)

          case ChurnPredictor.fire_intervention(profile.user_id, prediction) do
            {:ok, _notification} ->
              Logger.info(
                "ChurnDetectionWorker: fired #{prediction.level} intervention for user #{profile.user_id} " <>
                  "(score: #{prediction.score})"
              )
              count + 1

            :skip ->
              count

            {:error, reason} ->
              Logger.warning(
                "ChurnDetectionWorker: failed to fire intervention for user #{profile.user_id}: #{inspect(reason)}"
              )
              count
          end
        else
          count
        end
      end)

    Logger.info("ChurnDetectionWorker: fired #{interventions_fired} interventions")
    :ok
  end
end
