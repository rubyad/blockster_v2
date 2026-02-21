defmodule BlocksterV2.Workers.ReferralLeaderboardWorker do
  @moduledoc """
  Sends weekly referral leaderboard emails.
  Scheduled Tuesdays at 10 AM UTC.
  """

  use Oban.Worker, queue: :email_marketing, max_attempts: 3

  alias BlocksterV2.Notifications.ReferralEngine

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    leaderboard = ReferralEngine.weekly_leaderboard(limit: 10)

    if leaderboard == [] do
      Logger.info("ReferralLeaderboardWorker: no referrals this week, skipping")
      :ok
    else
      # Log leaderboard for now — email delivery would use EmailBuilder
      top = List.first(leaderboard)

      Logger.info(
        "ReferralLeaderboardWorker: top referrer is user #{top.user_id} " <>
          "with #{top.referrals_converted} referrals (#{top.bux_earned} BUX earned)"
      )

      :ok
    end
  end
end
