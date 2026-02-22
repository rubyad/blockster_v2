defmodule BlocksterV2.Notifications do
  @moduledoc """
  Context for managing notifications, preferences, campaigns, and email logs.
  """
  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Notifications.{Notification, NotificationPreference, Campaign, EmailLog}

  @pubsub BlocksterV2.PubSub
  @topic_prefix "notifications:"

  # ============ Notifications ============

  def create_notification(user_id, attrs) when is_integer(user_id) do
    %Notification{}
    |> Notification.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
    |> case do
      {:ok, notification} ->
        broadcast_new_notification(user_id, notification)
        {:ok, notification}

      error ->
        error
    end
  end

  def get_notification!(id), do: Repo.get!(Notification, id)

  def get_notification(id), do: Repo.get(Notification, id)

  def list_notifications(user_id, opts \\ []) do
    category = Keyword.get(opts, :category)
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    Notification
    |> where([n], n.user_id == ^user_id)
    |> where([n], is_nil(n.dismissed_at))
    |> maybe_filter_category(category)
    |> maybe_filter_status(status)
    |> order_by([n], [desc: n.inserted_at, desc: n.id])
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def list_recent_notifications(user_id, limit \\ 10) do
    Notification
    |> where([n], n.user_id == ^user_id)
    |> where([n], is_nil(n.dismissed_at))
    |> order_by([n], [desc: n.inserted_at, desc: n.id])
    |> limit(^limit)
    |> Repo.all()
  end

  def unread_count(user_id) do
    Notification
    |> where([n], n.user_id == ^user_id)
    |> where([n], is_nil(n.read_at))
    |> where([n], is_nil(n.dismissed_at))
    |> Repo.aggregate(:count, :id)
  end

  def mark_as_read(notification_id) do
    case get_notification(notification_id) do
      nil -> {:error, :not_found}
      notification ->
        notification
        |> Notification.read_changeset()
        |> Repo.update()
    end
  end

  def mark_as_clicked(notification_id) do
    case get_notification(notification_id) do
      nil -> {:error, :not_found}
      notification ->
        notification
        |> Notification.click_changeset()
        |> Repo.update()
    end
  end

  def dismiss_notification(notification_id) do
    case get_notification(notification_id) do
      nil -> {:error, :not_found}
      notification ->
        notification
        |> Notification.dismiss_changeset()
        |> Repo.update()
    end
  end

  def mark_all_as_read(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Notification
      |> where([n], n.user_id == ^user_id)
      |> where([n], is_nil(n.read_at))
      |> where([n], is_nil(n.dismissed_at))
      |> Repo.update_all(set: [read_at: now])

    broadcast_count_update(user_id, 0)
    {:ok, count}
  end

  # ============ Notification Preferences ============

  def get_preferences(user_id) do
    Repo.get_by(NotificationPreference, user_id: user_id)
  end

  def get_or_create_preferences(user_id) do
    case get_preferences(user_id) do
      nil -> create_preferences(user_id)
      prefs -> {:ok, prefs}
    end
  end

  def create_preferences(user_id) do
    token = NotificationPreference.generate_unsubscribe_token()

    %NotificationPreference{}
    |> NotificationPreference.changeset(%{user_id: user_id, unsubscribe_token: token})
    |> Repo.insert()
  end

  def update_preferences(user_id, attrs) do
    case get_or_create_preferences(user_id) do
      {:ok, prefs} ->
        prefs
        |> NotificationPreference.changeset(attrs)
        |> Repo.update()

      error ->
        error
    end
  end

  def find_by_unsubscribe_token(token) do
    Repo.get_by(NotificationPreference, unsubscribe_token: token)
  end

  def unsubscribe_all(token) do
    case find_by_unsubscribe_token(token) do
      nil ->
        {:error, :not_found}

      prefs ->
        prefs
        |> NotificationPreference.changeset(%{email_enabled: false, sms_enabled: false})
        |> Repo.update()
    end
  end

  # ============ Campaigns ============

  def create_campaign(attrs) do
    %Campaign{}
    |> Campaign.changeset(attrs)
    |> Repo.insert()
  end

  def get_campaign!(id), do: Repo.get!(Campaign, id)

  def get_campaign(id), do: Repo.get(Campaign, id)

  def list_campaigns(opts \\ []) do
    status = Keyword.get(opts, :status)

    Campaign
    |> maybe_filter_campaign_status(status)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  def update_campaign(%Campaign{} = campaign, attrs) do
    campaign
    |> Campaign.changeset(attrs)
    |> Repo.update()
  end

  def update_campaign_status(%Campaign{} = campaign, status) do
    campaign
    |> Campaign.status_changeset(status)
    |> Repo.update()
  end

  # ============ Email Logs ============

  def create_email_log(attrs) do
    %EmailLog{}
    |> EmailLog.changeset(attrs)
    |> Repo.insert()
  end

  def emails_sent_today(user_id) do
    today_start = DateTime.utc_now() |> DateTime.to_date() |> DateTime.new!(~T[00:00:00])

    EmailLog
    |> where([l], l.user_id == ^user_id)
    |> where([l], l.sent_at >= ^today_start)
    |> Repo.aggregate(:count, :id)
  end

  def sms_sent_this_week(user_id) do
    week_start =
      DateTime.utc_now()
      |> DateTime.to_date()
      |> Date.beginning_of_week(:monday)
      |> DateTime.new!(~T[00:00:00])

    EmailLog
    |> where([l], l.user_id == ^user_id)
    |> where([l], l.email_type == "sms")
    |> where([l], l.sent_at >= ^week_start)
    |> Repo.aggregate(:count, :id)
  end

  # ============ PubSub ============

  def broadcast_new_notification(user_id, notification) do
    Phoenix.PubSub.broadcast(@pubsub, "#{@topic_prefix}#{user_id}", {:new_notification, notification})
  end

  def broadcast_count_update(user_id, count) do
    Phoenix.PubSub.broadcast(@pubsub, "#{@topic_prefix}#{user_id}", {:notification_count_updated, count})
  end

  # ============ User Search ============

  def search_users(query_str, limit \\ 10) when is_binary(query_str) do
    search = "%#{query_str}%"

    from(u in BlocksterV2.Accounts.User,
      where: ilike(u.email, ^search) or ilike(u.wallet_address, ^search) or ilike(u.username, ^search),
      where: not is_nil(u.email),
      limit: ^limit,
      select: %{id: u.id, email: u.email, username: u.username, wallet_address: u.wallet_address}
    )
    |> Repo.all()
  end

  # ============ Campaign Queries ============

  def delete_campaign(%Campaign{} = campaign) do
    Repo.delete(campaign)
  end

  def campaign_recipient_count(campaign) do
    base = from(u in BlocksterV2.Accounts.User, where: not is_nil(u.email))

    case campaign.target_audience do
      "hub_followers" when not is_nil(campaign.target_hub_id) ->
        from(u in base,
          join: hf in "hub_followers",
          on: hf.user_id == u.id and hf.hub_id == ^campaign.target_hub_id
        )
        |> Repo.aggregate(:count, :id)

      "active_users" ->
        week_ago = DateTime.utc_now() |> DateTime.add(-7, :day) |> DateTime.truncate(:second)
        from(u in base, where: u.updated_at >= ^week_ago)
        |> Repo.aggregate(:count, :id)

      "dormant_users" ->
        month_ago = DateTime.utc_now() |> DateTime.add(-30, :day) |> DateTime.truncate(:second)
        from(u in base, where: u.updated_at < ^month_ago)
        |> Repo.aggregate(:count, :id)

      "phone_verified" ->
        from(u in base, where: u.phone_verified == true)
        |> Repo.aggregate(:count, :id)

      "custom" ->
        user_ids = get_in(campaign.target_criteria, ["user_ids"]) || []
        if user_ids == [] do
          0
        else
          from(u in base, where: u.id in ^user_ids) |> Repo.aggregate(:count, :id)
        end

      audience when audience in ~w(bux_gamers rogue_gamers bux_balance rogue_holders) ->
        user_ids = get_mnesia_user_ids(audience, campaign.target_criteria)
        if user_ids == [] do
          0
        else
          from(u in base, where: u.id in ^user_ids) |> Repo.aggregate(:count, :id)
        end

      _ ->
        Repo.aggregate(base, :count, :id)
    end
  end

  @doc """
  Get user IDs from Mnesia tables based on audience type and criteria.
  """
  def get_mnesia_user_ids(audience, criteria \\ %{})

  def get_mnesia_user_ids("bux_gamers", _criteria) do
    try do
      :mnesia.dirty_all_keys(:user_betting_stats)
      |> Enum.filter(fn user_id ->
        case :mnesia.dirty_read(:user_betting_stats, user_id) do
          [record] -> elem(record, 3) > 0
          _ -> false
        end
      end)
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end

  def get_mnesia_user_ids("rogue_gamers", _criteria) do
    try do
      :mnesia.dirty_all_keys(:user_betting_stats)
      |> Enum.filter(fn user_id ->
        case :mnesia.dirty_read(:user_betting_stats, user_id) do
          [record] -> elem(record, 10) > 0
          _ -> false
        end
      end)
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end

  def get_mnesia_user_ids("bux_balance", criteria) do
    operator = criteria["operator"] || "above"
    threshold = parse_threshold(criteria["threshold"])

    try do
      :mnesia.dirty_all_keys(:user_bux_balances)
      |> Enum.filter(fn user_id ->
        case :mnesia.dirty_read(:user_bux_balances, user_id) do
          [record] ->
            balance = elem(record, 5)
            case operator do
              "above" -> is_number(balance) and balance >= threshold
              "below" -> is_number(balance) and balance < threshold
              _ -> false
            end
          _ -> false
        end
      end)
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end

  def get_mnesia_user_ids("rogue_holders", _criteria) do
    try do
      :mnesia.dirty_all_keys(:user_rogue_balances)
      |> Enum.filter(fn user_id ->
        case :mnesia.dirty_read(:user_rogue_balances, user_id) do
          [record] ->
            balance = elem(record, 4)
            is_number(balance) and balance > 0
          _ -> false
        end
      end)
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end

  def get_mnesia_user_ids(_, _), do: []

  defp parse_threshold(nil), do: 0
  defp parse_threshold(val) when is_number(val), do: val
  defp parse_threshold(val) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> num
      :error -> 0
    end
  end
  defp parse_threshold(_), do: 0

  # ============ Dedup ============

  def already_notified?(user_id, dedup_key) do
    from(n in Notification,
      where: n.user_id == ^user_id,
      where: fragment("?->>'dedup_key' = ?", n.metadata, ^dedup_key),
      limit: 1
    )
    |> Repo.exists?()
  end

  def get_campaign_stats(campaign_id) do
    campaign = get_campaign!(campaign_id)

    email_logs =
      from(l in EmailLog,
        where: l.campaign_id == ^campaign_id,
        select: %{
          sent: count(l.id),
          opened: count(l.opened_at),
          clicked: count(l.clicked_at),
          bounced: filter(count(l.id), l.bounced == true)
        }
      )
      |> Repo.one()

    notifications =
      from(n in Notification,
        where: n.campaign_id == ^campaign_id,
        select: %{
          delivered: count(n.id),
          read: count(n.read_at),
          clicked: count(n.clicked_at)
        }
      )
      |> Repo.one()

    %{
      campaign: campaign,
      email: email_logs || %{sent: 0, opened: 0, clicked: 0, bounced: 0},
      in_app: notifications || %{delivered: 0, read: 0, clicked: 0}
    }
  end

  def update_email_log(%EmailLog{} = log, attrs) do
    log
    |> EmailLog.changeset(attrs)
    |> Repo.update()
  end

  def get_email_log_by_message_id(message_id) do
    Repo.get_by(EmailLog, sendgrid_message_id: message_id)
  end

  def top_campaigns(limit \\ 5) do
    Campaign
    |> where([c], c.status == "sent" and c.emails_sent > 0)
    |> order_by([c], desc: c.emails_opened)
    |> limit(^limit)
    |> Repo.all()
  end

  def hub_subscription_stats do
    from(hf in BlocksterV2.Blog.HubFollower,
      join: h in BlocksterV2.Blog.Hub, on: h.id == hf.hub_id,
      group_by: [h.id, h.name],
      select: %{
        hub_id: h.id,
        hub_name: h.name,
        follower_count: count(hf.user_id),
        notify_enabled: filter(count(hf.user_id), hf.notify_new_posts == true)
      },
      order_by: [desc: count(hf.user_id)]
    )
    |> Repo.all()
  end

  # ============ Private Helpers ============

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, category) do
    where(query, [n], n.category == ^category)
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, :unread) do
    where(query, [n], is_nil(n.read_at))
  end
  defp maybe_filter_status(query, :read) do
    where(query, [n], not is_nil(n.read_at))
  end

  defp maybe_filter_campaign_status(query, nil), do: query
  defp maybe_filter_campaign_status(query, status) do
    where(query, [c], c.status == ^status)
  end
end
