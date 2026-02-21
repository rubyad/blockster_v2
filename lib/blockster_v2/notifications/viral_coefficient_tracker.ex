defmodule BlocksterV2.Notifications.ViralCoefficientTracker do
  @moduledoc """
  Tracks the referral viral coefficient (K-factor).
  K = invites_per_user * conversion_rate.
  K > 1.0 means viral (each user generates more than one new user).
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Notifications.UserProfile

  @doc """
  Calculate the current viral coefficient (K-factor).
  K = avg_referrals_sent * conversion_rate

  Returns %{k_factor, avg_invites, conversion_rate, total_referrers, total_converted}.
  """
  def calculate_k_factor do
    stats = referral_stats()

    k_factor =
      if stats.total_referrers > 0 do
        Float.round(stats.avg_invites * stats.conversion_rate, 3)
      else
        0.0
      end

    Map.put(stats, :k_factor, k_factor)
  end

  @doc """
  Get referral statistics from user profiles.
  """
  def referral_stats do
    result =
      from(p in UserProfile,
        where: p.referrals_sent > 0 or p.referrals_converted > 0,
        select: %{
          total_referrers: count(p.id),
          total_sent: sum(p.referrals_sent),
          total_converted: sum(p.referrals_converted)
        }
      )
      |> Repo.one()

    total_referrers = result.total_referrers || 0
    total_sent = result.total_sent || 0
    total_converted = result.total_converted || 0

    avg_invites = if total_referrers > 0, do: Float.round(total_sent / total_referrers, 2), else: 0.0
    conversion_rate = if total_sent > 0, do: Float.round(total_converted / total_sent, 4), else: 0.0

    %{
      total_referrers: total_referrers,
      total_sent: total_sent,
      total_converted: total_converted,
      avg_invites: avg_invites,
      conversion_rate: conversion_rate
    }
  end

  @doc """
  Check if viral coefficient is above the target threshold.
  Default target is 1.0 (viral).
  """
  def is_viral?(target \\ 1.0) do
    %{k_factor: k} = calculate_k_factor()
    k >= target
  end

  @doc """
  Get top referrers sorted by conversions.
  Returns list of %{user_id, referrals_sent, referrals_converted, personal_conversion_rate}.
  """
  def top_referrers(limit \\ 10) do
    from(p in UserProfile,
      where: p.referrals_converted > 0,
      order_by: [desc: p.referrals_converted],
      limit: ^limit,
      select: %{
        user_id: p.user_id,
        referrals_sent: p.referrals_sent,
        referrals_converted: p.referrals_converted
      }
    )
    |> Repo.all()
    |> Enum.map(fn entry ->
      rate =
        if entry.referrals_sent > 0 do
          Float.round(entry.referrals_converted / entry.referrals_sent, 2)
        else
          0.0
        end

      Map.put(entry, :personal_conversion_rate, rate)
    end)
  end

  @doc """
  Get referral funnel metrics.
  Returns %{total_users, users_who_shared, users_who_converted, share_rate, conversion_rate}.
  """
  def referral_funnel do
    total =
      from(p in UserProfile)
      |> Repo.aggregate(:count, :id)

    shared =
      from(p in UserProfile, where: p.referrals_sent > 0)
      |> Repo.aggregate(:count, :id)

    converted =
      from(p in UserProfile, where: p.referrals_converted > 0)
      |> Repo.aggregate(:count, :id)

    %{
      total_users: total,
      users_who_shared: shared,
      users_who_converted: converted,
      share_rate: if(total > 0, do: Float.round(shared / total, 4), else: 0.0),
      conversion_rate: if(shared > 0, do: Float.round(converted / shared, 4), else: 0.0)
    }
  end
end
