defmodule BlocksterV2.Notifications.SendTimeOptimizer do
  @moduledoc """
  Per-user send-time optimization. Determines the best time to send
  emails/notifications based on historical engagement patterns.

  Uses the user's `best_email_hour_utc` from their profile, and falls back
  to population-level defaults when individual data is insufficient.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Notifications.{UserProfile, EmailLog}

  @default_hour 10
  @min_emails_for_optimization 5

  @doc """
  Get the optimal send hour (0-23 UTC) for a specific user.
  Returns the user's best hour if they have enough email engagement data,
  otherwise returns the population default.
  """
  def optimal_send_hour(user_id) do
    profile = Repo.get_by(UserProfile, user_id: user_id)

    cond do
      profile && profile.best_email_hour_utc ->
        profile.best_email_hour_utc

      true ->
        population_best_hour() || @default_hour
    end
  end

  @doc """
  Get the optimal send hour from a profile struct directly.
  """
  def optimal_send_hour_from_profile(nil), do: @default_hour
  def optimal_send_hour_from_profile(profile) do
    if profile.best_email_hour_utc do
      profile.best_email_hour_utc
    else
      @default_hour
    end
  end

  @doc """
  Calculate the best hour across all users (population level).
  Returns the hour with the highest average open rate.
  """
  def population_best_hour do
    result =
      from(l in EmailLog,
        where: not is_nil(l.opened_at),
        group_by: fragment("EXTRACT(HOUR FROM ?)", l.opened_at),
        order_by: [desc: count(l.id)],
        select: fragment("CAST(EXTRACT(HOUR FROM ?) AS INTEGER)", l.opened_at),
        limit: 1
      )
      |> Repo.one()

    result
  end

  @doc """
  Calculate the delay in seconds until the user's optimal send time.
  Returns 0 if the optimal time is now or has passed today.
  """
  def delay_until_optimal(user_id) do
    optimal_hour = optimal_send_hour(user_id)
    now = DateTime.utc_now()
    current_hour = now.hour

    cond do
      current_hour == optimal_hour ->
        0

      current_hour < optimal_hour ->
        # Later today
        (optimal_hour - current_hour) * 3600

      true ->
        # Tomorrow
        (24 - current_hour + optimal_hour) * 3600
    end
  end

  @doc """
  Calculate delay from a profile struct directly.
  """
  def delay_from_profile(profile) do
    optimal_hour = optimal_send_hour_from_profile(profile)
    now = DateTime.utc_now()
    current_hour = now.hour

    cond do
      current_hour == optimal_hour -> 0
      current_hour < optimal_hour -> (optimal_hour - current_hour) * 3600
      true -> (24 - current_hour + optimal_hour) * 3600
    end
  end

  @doc """
  Check if a user has enough engagement data for personalized send times.
  """
  def has_sufficient_data?(user_id) do
    email_count =
      from(l in EmailLog,
        where: l.user_id == ^user_id,
        where: not is_nil(l.opened_at)
      )
      |> Repo.aggregate(:count, :id)

    email_count >= @min_emails_for_optimization
  end

  @doc """
  Get a map of hour => open_count for a user's email engagement.
  Useful for analytics display.
  """
  def hourly_engagement_distribution(user_id) do
    from(l in EmailLog,
      where: l.user_id == ^user_id,
      where: not is_nil(l.opened_at),
      group_by: fragment("EXTRACT(HOUR FROM ?)", l.opened_at),
      select: {fragment("CAST(EXTRACT(HOUR FROM ?) AS INTEGER)", l.opened_at), count(l.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Get send-time optimization stats for the notification system.
  Returns %{users_optimized, users_default, population_best_hour}.
  """
  def optimization_stats do
    optimized =
      from(p in UserProfile,
        where: not is_nil(p.best_email_hour_utc)
      )
      |> Repo.aggregate(:count, :id)

    total =
      from(p in UserProfile)
      |> Repo.aggregate(:count, :id)

    %{
      users_optimized: optimized,
      users_default: total - optimized,
      population_best_hour: population_best_hour() || @default_hour
    }
  end
end
