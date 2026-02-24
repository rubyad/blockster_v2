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
                body: campaign.body || campaign.plain_text_body || "",
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
        "all" ->
          base_query

        "hub_followers" when not is_nil(campaign.target_hub_id) ->
          from(u in base_query,
            join: hf in "hub_followers",
            on: hf.user_id == u.id and hf.hub_id == ^campaign.target_hub_id
          )

        "not_hub_followers" when not is_nil(campaign.target_hub_id) ->
          from(u in base_query,
            left_join: hf in "hub_followers",
            on: hf.user_id == u.id and hf.hub_id == ^campaign.target_hub_id,
            where: is_nil(hf.user_id)
          )

        "active_users" ->
          week_ago = DateTime.utc_now() |> DateTime.add(-7, :day) |> DateTime.truncate(:second)
          from(u in base_query, where: u.updated_at >= ^week_ago)

        "dormant_users" ->
          month_ago = DateTime.utc_now() |> DateTime.add(-30, :day) |> DateTime.truncate(:second)
          from(u in base_query, where: u.updated_at < ^month_ago)

        "phone_verified" ->
          from(u in base_query, where: u.phone_verified == true)

        "not_phone_verified" ->
          from(u in base_query, where: u.phone_verified == false or is_nil(u.phone_verified))

        "x_connected" ->
          from(u in base_query, where: not is_nil(u.locked_x_user_id))

        "not_x_connected" ->
          from(u in base_query, where: is_nil(u.locked_x_user_id))

        "telegram_connected" ->
          from(u in base_query, where: not is_nil(u.telegram_user_id))

        "not_telegram_connected" ->
          from(u in base_query, where: is_nil(u.telegram_user_id))

        "has_external_wallet" ->
          from(u in base_query,
            join: cw in BlocksterV2.ConnectedWallet, on: cw.user_id == u.id,
            distinct: true
          )

        "no_external_wallet" ->
          from(u in base_query,
            left_join: cw in BlocksterV2.ConnectedWallet, on: cw.user_id == u.id,
            where: is_nil(cw.id)
          )

        "wallet_provider" ->
          provider = get_in(campaign.target_criteria || %{}, ["provider"]) || "metamask"
          from(u in base_query,
            join: cw in BlocksterV2.ConnectedWallet, on: cw.user_id == u.id,
            where: cw.provider == ^provider,
            distinct: true
          )

        "multiplier" ->
          criteria = campaign.target_criteria || %{}
          user_ids = Notifications.get_multiplier_user_ids(criteria)
          if user_ids == [], do: from(u in base_query, where: false), else: from(u in base_query, where: u.id in ^user_ids)

        "custom" ->
          user_ids = get_in(campaign.target_criteria || %{}, ["user_ids"]) || []
          if user_ids == [], do: from(u in base_query, where: false), else: from(u in base_query, where: u.id in ^user_ids)

        audience when audience in ~w(bux_gamers rogue_gamers bux_balance rogue_holders) ->
          user_ids = Notifications.get_mnesia_user_ids(audience, campaign.target_criteria || %{})
          if user_ids == [], do: from(u in base_query, where: false), else: from(u in base_query, where: u.id in ^user_ids)

        _ ->
          base_query
      end

    Repo.all(query)
    |> Enum.filter(fn user ->
      case Notifications.get_or_create_preferences(user.id) do
        {:ok, prefs} -> prefs.email_enabled && prefs.email_special_offers
        _ -> false
      end
    end)
  end
end
