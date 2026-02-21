defmodule BlocksterV2.Notifications.PriceAlertEngine do
  @moduledoc """
  ROGUE price movement notifications for holders.
  Monitors price changes and fires alerts when significant
  movements are detected.
  """

  import Ecto.Query
  alias BlocksterV2.{Repo, Notifications}
  alias BlocksterV2.Notifications.{UserProfile, Notification}

  require Logger

  @significant_change_pct 5.0
  @major_change_pct 10.0

  @doc """
  Evaluate if a price change warrants a notification.
  Returns {:fire, alert_data} or :skip.
  """
  def evaluate_price_change(old_price, new_price) when is_number(old_price) and is_number(new_price) and old_price > 0 do
    change_pct = (new_price - old_price) / old_price * 100.0
    abs_change = abs(change_pct)

    cond do
      abs_change >= @major_change_pct ->
        direction = if change_pct > 0, do: "up", else: "down"
        {:fire, %{
          severity: "major",
          direction: direction,
          change_pct: Float.round(change_pct, 1),
          old_price: old_price,
          new_price: new_price
        }}

      abs_change >= @significant_change_pct ->
        direction = if change_pct > 0, do: "up", else: "down"
        {:fire, %{
          severity: "significant",
          direction: direction,
          change_pct: Float.round(change_pct, 1),
          old_price: old_price,
          new_price: new_price
        }}

      true ->
        :skip
    end
  end

  def evaluate_price_change(_old, _new), do: :skip

  @doc """
  Get users who should receive ROGUE price alerts.
  Users are eligible if they have ROGUE gaming activity (rogue_curious+).
  """
  def get_alert_eligible_users do
    from(p in UserProfile,
      where: p.conversion_stage in ["rogue_curious", "rogue_buyer", "rogue_regular"],
      select: p
    )
    |> Repo.all()
  end

  @doc """
  Fire price alert notifications for eligible users.
  Returns count of notifications sent.
  """
  def fire_price_alerts(alert_data) do
    users = get_alert_eligible_users()

    Enum.reduce(users, 0, fn profile, count ->
      if !price_alert_sent_recently?(profile.user_id) do
        case fire_price_notification(profile.user_id, alert_data) do
          {:ok, _} -> count + 1
          _ -> count
        end
      else
        count
      end
    end)
  end

  @doc """
  Fire a single price alert notification for a user.
  """
  def fire_price_notification(user_id, alert_data) do
    {title, body} = price_alert_copy(alert_data)

    Notifications.create_notification(user_id, %{
      type: "price_drop",
      category: "rewards",
      title: title,
      body: body,
      action_url: "/play",
      action_label: if(alert_data.direction == "down", do: "Buy ROGUE", else: "Play Now"),
      metadata: %{
        severity: alert_data.severity,
        direction: alert_data.direction,
        change_pct: alert_data.change_pct,
        old_price: alert_data.old_price,
        new_price: alert_data.new_price
      }
    })
  end

  @doc """
  Generate title and body copy for price alerts.
  """
  def price_alert_copy(alert_data) do
    change = abs(alert_data.change_pct)

    case {alert_data.direction, alert_data.severity} do
      {"up", "major"} ->
        {"ROGUE is surging! +#{change}%",
         "ROGUE price jumped #{change}%. Your holdings are growing!"}

      {"up", _} ->
        {"ROGUE is up #{change}%",
         "ROGUE price increased. Good time to check your balance."}

      {"down", "major"} ->
        {"ROGUE dipped #{change}% — buying opportunity?",
         "ROGUE dropped #{change}%. This could be a good entry point."}

      {"down", _} ->
        {"ROGUE is down #{change}%",
         "ROGUE price dropped slightly. Consider buying the dip."}
    end
  end

  @doc """
  Check if a price alert was already sent to a user today.
  """
  def price_alert_sent_recently?(user_id) do
    today_start =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.to_date()
      |> NaiveDateTime.new!(~T[00:00:00])

    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type == "price_drop",
      where: fragment("?->>'severity' IS NOT NULL", n.metadata),
      where: n.inserted_at >= ^today_start
    )
    |> Repo.exists?()
  end
end
