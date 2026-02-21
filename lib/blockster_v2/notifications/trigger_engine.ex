defmodule BlocksterV2.Notifications.TriggerEngine do
  @moduledoc """
  Real-time notification triggers that fire based on user events and profile state.
  Called by UserEvents.track/3 after recording each event.
  Each trigger returns {:fire, notification_type, data} or :skip.
  """

  import Ecto.Query
  alias BlocksterV2.{Repo, Notifications, UserEvents}
  alias BlocksterV2.Notifications.{Notification, UserProfile}

  require Logger

  @bux_milestones [1_000, 5_000, 10_000, 25_000, 50_000, 100_000]
  @streak_milestones [3, 7, 14, 30]

  @doc """
  Evaluate all triggers for a user event. Fires notifications for any matching triggers.
  Returns list of fired notification types (for testing/logging).
  """
  def evaluate_triggers(user_id, event_type, metadata \\ %{}) do
    profile = UserEvents.get_profile(user_id)

    triggers = [
      &cart_abandonment_trigger/3,
      &bux_milestone_trigger/3,
      &reading_streak_trigger/3,
      &hub_recommendation_trigger/3,
      &price_drop_trigger/3,
      &purchase_thank_you_trigger/3,
      &dormancy_warning_trigger/3,
      &referral_opportunity_trigger/3
    ]

    fired =
      Enum.reduce(triggers, [], fn trigger, acc ->
        case trigger.({user_id, event_type, metadata}, profile, %{}) do
          {:fire, notif_type, data} ->
            fire_notification(user_id, notif_type, data)
            [notif_type | acc]

          :skip ->
            acc
        end
      end)

    Enum.reverse(fired)
  end

  # ============ Triggers ============

  @doc false
  def cart_abandonment_trigger({user_id, event_type, _metadata}, profile, _opts) do
    if event_type == "session_end" and has_carted_items?(profile) do
      last_cart_event = UserEvents.get_last_event(user_id, "product_add_to_cart")

      if last_cart_event && hours_since(last_cart_event.inserted_at) >= 2 &&
           !already_sent_today?(user_id, "cart_abandonment") do
        products = if profile, do: profile.carted_not_purchased || [], else: []
        hours = if last_cart_event, do: round(hours_since(last_cart_event.inserted_at)), else: 2

        {:fire, "cart_abandonment", %{
          products: products,
          hours_since: hours
        }}
      else
        :skip
      end
    else
      :skip
    end
  end

  @doc false
  def bux_milestone_trigger({user_id, _event_type, metadata}, _profile, _opts) do
    new_balance = get_metadata_decimal(metadata, "new_balance")

    if new_balance do
      milestone = Enum.find(@bux_milestones, fn m ->
        Decimal.compare(new_balance, Decimal.new(m)) != :lt &&
          Decimal.compare(Decimal.sub(new_balance, Decimal.new(m)), Decimal.new(500)) == :lt
      end)

      if milestone && !milestone_already_celebrated?(user_id, milestone) do
        {:fire, "bux_milestone", %{
          milestone: milestone,
          balance: Decimal.to_string(new_balance)
        }}
      else
        :skip
      end
    else
      :skip
    end
  end

  @doc false
  def reading_streak_trigger({user_id, event_type, _metadata}, profile, _opts) do
    if event_type == "article_read_complete" && profile do
      streak = profile.consecutive_active_days || 0

      milestone = Enum.find(@streak_milestones, fn m -> streak == m end)

      if milestone && !streak_already_celebrated?(user_id, milestone) do
        {:fire, "bux_milestone", %{
          type: "reading_streak",
          days: milestone
        }}
      else
        :skip
      end
    else
      :skip
    end
  end

  @doc false
  def hub_recommendation_trigger({user_id, event_type, metadata}, _profile, _opts) do
    if event_type == "article_read_complete" do
      category_id = metadata["category_id"] || metadata[:category_id]

      if category_id do
        reads_in_cat = count_category_reads_last_7d(user_id, to_string(category_id))

        if reads_in_cat >= 3 do
          unsubscribed_hubs = get_hubs_in_category_not_followed(user_id, category_id)

          if unsubscribed_hubs != [] do
            {:fire, "content_recommendation", %{
              hubs: Enum.take(unsubscribed_hubs, 3),
              reason: "category_interest",
              category_id: category_id
            }}
          else
            :skip
          end
        else
          :skip
        end
      else
        :skip
      end
    else
      :skip
    end
  end

  @doc false
  def price_drop_trigger({user_id, event_type, metadata}, profile, _opts) do
    if event_type == "product_price_changed" do
      product_id = metadata["product_id"] || metadata[:product_id]
      old_price = metadata["old_price"] || metadata[:old_price]
      new_price = metadata["new_price"] || metadata[:new_price]

      viewed = if profile, do: profile.viewed_products_last_30d || [], else: []

      product_id_int =
        case product_id do
          id when is_integer(id) -> id
          id when is_binary(id) ->
            case Integer.parse(id) do
              {int, _} -> int
              :error -> nil
            end
          _ -> nil
        end

      if product_id_int && product_id_int in viewed && new_price && old_price do
        old_dec = to_decimal(old_price)
        new_dec = to_decimal(new_price)

        if old_dec && new_dec && Decimal.compare(new_dec, old_dec) == :lt do
          savings_pct =
            old_dec
            |> Decimal.sub(new_dec)
            |> Decimal.div(old_dec)
            |> Decimal.mult(100)
            |> Decimal.round(0)
            |> Decimal.to_integer()

          {:fire, "price_drop", %{
            product_id: product_id_int,
            old_price: Decimal.to_string(old_dec),
            new_price: Decimal.to_string(new_dec),
            savings_pct: savings_pct
          }}
        else
          :skip
        end
      else
        :skip
      end
    else
      :skip
    end
  end

  @doc false
  def purchase_thank_you_trigger({_user_id, event_type, metadata}, profile, _opts) do
    if event_type == "purchase_complete" && profile && profile.purchase_count == 1 do
      order_id = metadata["order_id"] || metadata[:order_id]

      {:fire, "referral_prompt", %{
        type: "first_purchase_thank_you",
        order_id: order_id
      }}
    else
      :skip
    end
  end

  @doc false
  def dormancy_warning_trigger({user_id, event_type, _metadata}, profile, _opts) do
    if event_type == "daily_login" && profile do
      days_away = profile.days_since_last_active || 0

      if days_away >= 5 && days_away <= 14 &&
           !already_sent_today?(user_id, "re_engagement") do
        {:fire, "welcome", %{
          type: "welcome_back",
          days_away: days_away
        }}
      else
        :skip
      end
    else
      :skip
    end
  end

  @doc false
  def referral_opportunity_trigger({user_id, event_type, _metadata}, profile, _opts) do
    if event_type in ["article_share", "bux_earned"] && profile do
      propensity = profile.referral_propensity || 0.0

      if propensity > 0.6 && !sent_referral_prompt_this_week?(user_id) do
        {:fire, "referral_prompt", %{
          trigger: event_type
        }}
      else
        :skip
      end
    else
      :skip
    end
  end

  # ============ Notification Firing ============

  defp fire_notification(user_id, type, data) do
    attrs = %{
      type: type,
      category: notification_category(type),
      title: notification_title(type, data),
      body: notification_body(type, data),
      metadata: data
    }

    case Notifications.create_notification(user_id, attrs) do
      {:ok, _notification} ->
        Logger.info("TriggerEngine fired #{type} for user #{user_id}")
        :ok

      {:error, reason} ->
        Logger.warning("TriggerEngine failed to fire #{type} for user #{user_id}: #{inspect(reason)}")
        :error
    end
  end

  defp notification_category("cart_abandonment"), do: "offers"
  defp notification_category("bux_milestone"), do: "rewards"
  defp notification_category("content_recommendation"), do: "content"
  defp notification_category("price_drop"), do: "offers"
  defp notification_category("referral_prompt"), do: "social"
  defp notification_category("welcome"), do: "system"
  defp notification_category(_), do: "system"

  defp notification_title("cart_abandonment", _data), do: "You left something behind"
  defp notification_title("bux_milestone", %{type: "reading_streak", days: days}),
    do: "#{days}-day reading streak!"
  defp notification_title("bux_milestone", %{milestone: m}),
    do: "You hit #{format_number(m)} BUX!"
  defp notification_title("content_recommendation", _data), do: "Hubs you might like"
  defp notification_title("price_drop", %{savings_pct: pct}),
    do: "Price dropped #{pct}%!"
  defp notification_title("referral_prompt", %{type: "first_purchase_thank_you"}),
    do: "Thanks for your first purchase!"
  defp notification_title("referral_prompt", _data), do: "Share Blockster, earn BUX"
  defp notification_title("welcome", %{type: "welcome_back", days_away: d}),
    do: "Welcome back! #{d} days is too long"
  defp notification_title(type, _data), do: "Notification: #{type}"

  defp notification_body("cart_abandonment", %{products: products}) do
    count = length(products)
    "You have #{count} item#{if count != 1, do: "s"} waiting in your cart."
  end
  defp notification_body("bux_milestone", %{type: "reading_streak", days: days}),
    do: "You've read articles #{days} days in a row. Keep it up!"
  defp notification_body("bux_milestone", %{milestone: m, balance: bal}),
    do: "Your BUX balance just hit #{format_number(m)}! Current balance: #{bal}"
  defp notification_body("content_recommendation", %{hubs: hubs}) do
    names = Enum.map_join(hubs, ", ", fn h -> h[:name] || h["name"] || "Hub" end)
    "Based on your reading: #{names}"
  end
  defp notification_body("price_drop", %{savings_pct: pct}),
    do: "A product you viewed just dropped #{pct}% in price!"
  defp notification_body("referral_prompt", %{type: "first_purchase_thank_you"}),
    do: "Invite friends and you'll both earn 500 BUX."
  defp notification_body("referral_prompt", _data),
    do: "Share your referral link — earn 500 BUX for each friend who joins."
  defp notification_body("welcome", %{days_away: d}),
    do: "You missed #{d} days of content. Here's what's new."
  defp notification_body(_, _), do: ""

  # ============ Private Helpers ============

  defp has_carted_items?(nil), do: false
  defp has_carted_items?(profile), do: (profile.carted_not_purchased || []) != []

  defp hours_since(nil), do: 999
  defp hours_since(%NaiveDateTime{} = ndt) do
    NaiveDateTime.diff(NaiveDateTime.utc_now(), ndt, :second) / 3600.0
  end
  defp hours_since(%DateTime{} = dt) do
    DateTime.diff(DateTime.utc_now(), dt, :second) / 3600.0
  end

  defp already_sent_today?(user_id, type) do
    today_start =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.to_date()
      |> NaiveDateTime.new!(~T[00:00:00])

    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type == ^type,
      where: n.inserted_at >= ^today_start
    )
    |> Repo.exists?()
  end

  defp milestone_already_celebrated?(user_id, milestone) do
    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type == "bux_milestone",
      where: fragment("?->>'milestone' = ?", n.metadata, ^to_string(milestone))
    )
    |> Repo.exists?()
  end

  defp streak_already_celebrated?(user_id, days) do
    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type == "bux_milestone",
      where: fragment("?->>'type' = 'reading_streak' AND ?->>'days' = ?", n.metadata, n.metadata, ^to_string(days))
    )
    |> Repo.exists?()
  end

  defp count_category_reads_last_7d(user_id, category_id) do
    since = NaiveDateTime.utc_now() |> NaiveDateTime.add(-7, :day)

    from(e in BlocksterV2.Notifications.UserEvent,
      where: e.user_id == ^user_id,
      where: e.event_type == "article_read_complete",
      where: e.inserted_at >= ^since,
      where: fragment("?->>'category_id' = ?", e.metadata, ^category_id)
    )
    |> Repo.aggregate(:count, :id)
  end

  defp get_hubs_in_category_not_followed(user_id, category_id) do
    followed_hub_ids = BlocksterV2.Blog.get_user_followed_hub_ids(user_id)

    from(h in BlocksterV2.Blog.Hub,
      where: h.category_id == ^category_id,
      where: h.id not in ^followed_hub_ids,
      limit: 3,
      select: %{id: h.id, name: h.name, slug: h.slug}
    )
    |> Repo.all()
  end

  defp sent_referral_prompt_this_week?(user_id) do
    week_start =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.to_date()
      |> Date.beginning_of_week(:monday)
      |> NaiveDateTime.new!(~T[00:00:00])

    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type == "referral_prompt",
      where: n.inserted_at >= ^week_start
    )
    |> Repo.exists?()
  end

  defp get_metadata_decimal(metadata, key) do
    val = metadata[key] || metadata[String.to_atom(key)]

    case val do
      nil -> nil
      %Decimal{} = d -> d
      v when is_number(v) -> Decimal.new(v)
      v when is_binary(v) ->
        case Decimal.parse(v) do
          {d, _} -> d
          :error -> nil
        end
      _ -> nil
    end
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(v) when is_number(v), do: Decimal.new(v)
  defp to_decimal(v) when is_binary(v) do
    case Decimal.parse(v) do
      {d, _} -> d
      :error -> nil
    end
  end
  defp to_decimal(_), do: nil

  defp format_number(n) when n >= 1_000 do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.reverse/1)
    |> String.reverse()
    |> String.replace(~r/^,/, "")
  end
  defp format_number(n), do: Integer.to_string(n)
end
