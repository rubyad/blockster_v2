defmodule BlocksterV2.Workers.PromoEmailWorker do
  @moduledoc """
  Sends promotional campaign emails to targeted recipients.
  Triggered when an admin sends/schedules a campaign.
  """

  use Oban.Worker, queue: :email_marketing, max_attempts: 3

  alias BlocksterV2.{Notifications, Repo, Mailer}
  alias BlocksterV2.Notifications.{RateLimiter, EmailBuilder, Campaign}
  import Ecto.Query

  @doc """
  Enqueue a promotional email campaign for processing.
  """
  def enqueue_campaign(campaign_id) do
    %{campaign_id: campaign_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_id" => campaign_id, "user_id" => user_id}}) do
    # Individual user send
    campaign = Notifications.get_campaign(campaign_id)

    if campaign do
      send_campaign_to_user(campaign, user_id)
    else
      :ok
    end
  end

  def perform(%Oban.Job{args: %{"campaign_id" => campaign_id}}) do
    campaign = Notifications.get_campaign!(campaign_id)

    # Update status to sending
    Notifications.update_campaign_status(campaign, "sending")

    recipients = get_campaign_recipients(campaign)

    Enum.each(recipients, fn user ->
      %{campaign_id: campaign_id, user_id: user.id}
      |> __MODULE__.new()
      |> Oban.insert()
    end)

    # Update campaign stats
    Notifications.update_campaign(campaign, %{
      status: "sent",
      sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
      total_recipients: length(recipients)
    })

    :ok
  end

  defp send_campaign_to_user(campaign, user_id) do
    case RateLimiter.can_send?(user_id, :email, "special_offer") do
      :ok ->
        user = Repo.get(BlocksterV2.Accounts.User, user_id)

        if user && user.email do
          prefs = Notifications.get_preferences(user_id)
          token = if prefs, do: prefs.unsubscribe_token, else: ""

          email =
            EmailBuilder.promotional(
              user.email,
              user.username || user.email,
              token,
              %{
                title: campaign.title || campaign.subject,
                body: campaign.plain_text_body || campaign.body || "",
                image_url: campaign.image_url,
                action_url: campaign.action_url,
                action_label: campaign.action_label
              }
            )

          case Mailer.deliver(email) do
            {:ok, _} ->
              Notifications.create_email_log(%{
                user_id: user_id,
                campaign_id: campaign.id,
                email_type: "promotional",
                subject: email.subject,
                sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
              })

              # Create in-app notification if campaign has send_in_app
              if campaign.send_in_app do
                Notifications.create_notification(user_id, %{
                  type: "special_offer",
                  category: "offers",
                  title: campaign.title || campaign.subject,
                  body: campaign.plain_text_body || "",
                  image_url: campaign.image_url,
                  action_url: campaign.action_url,
                  action_label: campaign.action_label,
                  campaign_id: campaign.id
                })
              end

              # Enqueue SMS if campaign has send_sms enabled
              if campaign.send_sms do
                sms_type = if campaign.type == "sms_blast", do: :flash_sale, else: :special_offer
                BlocksterV2.Workers.SmsNotificationWorker.enqueue(user_id, sms_type, %{
                  title: campaign.title || campaign.subject,
                  url: campaign.action_url || "blockster-v2.fly.dev/shop"
                })
              end

              :ok

            {:error, reason} ->
              {:error, reason}
          end
        else
          :ok
        end

      :defer ->
        %{campaign_id: campaign.id, user_id: user_id}
        |> __MODULE__.new(schedule_in: 3600)
        |> Oban.insert()
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp get_campaign_recipients(campaign) do
    base_query = from(u in BlocksterV2.Accounts.User, where: not is_nil(u.email))

    query =
      case campaign.target_audience do
        "all" -> base_query
        "hub_followers" when not is_nil(campaign.target_hub_id) ->
          from(u in base_query,
            join: hf in "hub_followers",
            on: hf.user_id == u.id and hf.hub_id == ^campaign.target_hub_id
          )
        "phone_verified" ->
          from(u in base_query, where: u.phone_verified == true)
        _ -> base_query
      end

    Repo.all(query)
    |> Enum.filter(fn user ->
      case Notifications.get_preferences(user.id) do
        nil -> false
        prefs -> prefs.email_enabled && prefs.email_special_offers
      end
    end)
  end
end
