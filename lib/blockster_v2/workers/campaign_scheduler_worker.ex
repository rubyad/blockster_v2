defmodule BlocksterV2.Workers.CampaignSchedulerWorker do
  @moduledoc """
  Periodic worker that checks for scheduled campaigns whose send time has arrived
  and enqueues them for delivery via PromoEmailWorker.

  Runs every minute via Oban cron.
  """

  use Oban.Worker, queue: :email_marketing, max_attempts: 1

  alias BlocksterV2.{Repo, Notifications}
  alias BlocksterV2.Notifications.Campaign
  import Ecto.Query

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    campaigns =
      from(c in Campaign,
        where: c.status == "scheduled",
        where: not is_nil(c.scheduled_at),
        where: c.scheduled_at <= ^now
      )
      |> Repo.all()

    Enum.each(campaigns, fn campaign ->
      Notifications.update_campaign_status(campaign, "draft")
      BlocksterV2.Workers.PromoEmailWorker.enqueue_campaign(campaign.id)
    end)

    :ok
  end
end
