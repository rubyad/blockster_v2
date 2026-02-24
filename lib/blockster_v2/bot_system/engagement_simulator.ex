defmodule BlocksterV2.BotSystem.EngagementSimulator do
  @moduledoc """
  Pure functions for simulating realistic reading behavior.
  Generates decay-curve schedules and reading/video metrics.
  No GenServer — called by BotCoordinator.
  """

  # Decay curve buckets: {start_ms, end_ms, percentage}
  # Heavy front-load: ~55% in first hour, then gradual tail
  @decay_buckets [
    {0, :timer.minutes(5), 0.15},                # Instant readers
    {:timer.minutes(5), :timer.minutes(15), 0.15}, # Early birds
    {:timer.minutes(15), :timer.minutes(30), 0.13}, # First wave
    {:timer.minutes(30), :timer.hours(1), 0.12},   # Catching up
    {:timer.hours(1), :timer.hours(4), 0.12},      # Steady flow
    {:timer.hours(4), :timer.hours(12), 0.10},     # Afternoon readers
    {:timer.hours(12), :timer.hours(48), 0.10},    # Next-day readers
    {:timer.hours(48), :timer.hours(168), 0.13}    # Long tail
  ]

  # Engagement score distribution weights
  # {min_score_target, max_score_target, weight}
  @score_distribution [
    {1, 3, 0.10},    # Fast skimmers
    {4, 5, 0.20},    # Partial readers
    {6, 8, 0.40},    # Good readers
    {9, 10, 0.30}    # Thorough readers
  ]

  @doc """
  Generates a decay-curve reading schedule for a newly published post.

  Returns a sorted list of `{delay_ms, bot_id}` tuples representing when
  each bot should start reading the post.

  ## Parameters
    - `active_bot_ids` - list of currently active bot user IDs
    - `opts` - keyword list:
      - `:post_age_ms` - age of post in milliseconds (0 for new posts, used for backfill)

  ## Returns
    - `[{delay_ms, bot_id}]` sorted ascending by delay
  """
  def generate_reading_schedule(active_bot_ids, opts \\ []) when is_list(active_bot_ids) do
    if active_bot_ids == [] do
      []
    else
      post_age_ms = Keyword.get(opts, :post_age_ms, 0)
      total_active = length(active_bot_ids)

      # 60-85% of active bots will read this post
      reader_percentage = random_float(0.60, 0.85)
      reader_count = max(1, round(total_active * reader_percentage))

      # Pick random readers from active pool
      readers = Enum.take_random(active_bot_ids, reader_count)

      # Distribute readers across time buckets
      assign_to_buckets(readers, post_age_ms)
      |> Enum.sort_by(fn {delay_ms, _bot_id} -> delay_ms end)
    end
  end

  @doc """
  Generates a backfill schedule for an existing post.
  Skips time buckets that have already passed based on post age.
  Returns empty list if post is older than 7 days.
  """
  def generate_backfill_schedule(active_bot_ids, post_age_ms) do
    if post_age_ms >= :timer.hours(168) do
      []
    else
      generate_reading_schedule(active_bot_ids, post_age_ms: post_age_ms)
    end
  end

  @doc """
  Picks an engagement score target for a bot, returning metrics parameters.

  Returns `{target_time_ratio, target_scroll_depth}` where:
    - `target_time_ratio` is the fraction of min_read_time the bot will spend (0.1 - 1.2)
    - `target_scroll_depth` is 0-100 percentage
  """
  def generate_score_target do
    roll = :rand.uniform()
    {min_score, max_score} = pick_score_range(roll)

    # Map score to time_ratio and scroll_depth
    score = min_score + :rand.uniform() * (max_score - min_score)
    target_time_ratio = score_to_time_ratio(score)
    target_scroll_depth = score_to_scroll_depth(score)

    {target_time_ratio, target_scroll_depth, score}
  end

  @doc """
  Generates realistic reading metrics for the mid-read update.

  ## Parameters
    - `target_time_ratio` - fraction of total read time elapsed (~0.5 for mid-read)
    - `target_scroll_depth` - final target scroll depth
    - `min_read_time` - minimum read time in seconds
    - `progress` - 0.0 to 1.0 indicating how far through the read
  """
  def generate_partial_metrics(target_time_ratio, target_scroll_depth, min_read_time, progress) do
    partial_depth = target_scroll_depth * progress * random_float(0.85, 1.0)
    partial_time = round(min_read_time * target_time_ratio * progress)

    %{
      "time_spent" => max(partial_time, 1),
      "scroll_depth" => min(round(partial_depth), 100),
      "reached_end" => false,
      "scroll_events" => Enum.random(5..60),
      "avg_scroll_speed" => random_float(200.0, 800.0),
      "max_scroll_speed" => random_float(600.0, 2500.0),
      "scroll_reversals" => Enum.random(1..10),
      "focus_changes" => Enum.random(0..2)
    }
  end

  @doc """
  Generates final reading metrics for the record_read call.

  ## Parameters
    - `target_time_ratio` - fraction of min_read_time the bot spent
    - `target_scroll_depth` - final scroll depth (0-100)
    - `min_read_time` - minimum read time in seconds
  """
  def generate_final_metrics(target_time_ratio, target_scroll_depth, min_read_time) do
    time_spent = round(min_read_time * target_time_ratio)
    depth = min(round(target_scroll_depth + random_float(-2.0, 2.0)), 100) |> max(0)
    reached_end = depth >= 95

    %{
      "time_spent" => max(time_spent, 1),
      "scroll_depth" => depth,
      "reached_end" => reached_end,
      "scroll_events" => Enum.random(15..120),
      "avg_scroll_speed" => random_float(200.0, 800.0),
      "max_scroll_speed" => random_float(600.0, 2500.0),
      "scroll_reversals" => Enum.random(3..20),
      "focus_changes" => Enum.random(0..4)
    }
  end

  @doc """
  Generates video watch parameters for a bot.

  Returns `{watch_percentage, watch_time_seconds}` where:
    - `watch_percentage` is 30-100% of total video duration
    - `watch_time_seconds` is the actual seconds to watch
  """
  def generate_video_params(video_duration_seconds) when video_duration_seconds > 0 do
    watch_pct = random_float(0.30, 1.0)
    watch_seconds = round(video_duration_seconds * watch_pct)
    {watch_pct, max(watch_seconds, 1)}
  end

  def generate_video_params(_), do: {0.0, 0}

  @doc """
  Calculates video session BUX earned.

  Formula: (watch_seconds / 60) * bux_per_minute * multiplier
  """
  def calculate_video_bux(watch_seconds, bux_per_minute, multiplier) do
    minutes_watched = watch_seconds / 60.0
    bux = minutes_watched * (bux_per_minute || 1.0) * (multiplier || 1.0)
    Float.round(bux, 2)
  end

  # --- Private Functions ---

  defp assign_to_buckets(readers, post_age_ms) do
    # Filter out buckets that have already passed
    available_buckets = Enum.filter(@decay_buckets, fn {_start, end_ms, _pct} ->
      end_ms > post_age_ms
    end)

    if available_buckets == [] do
      []
    else
      # Normalize percentages for remaining buckets
      total_pct = Enum.reduce(available_buckets, 0.0, fn {_, _, pct}, acc -> acc + pct end)

      # Assign readers to buckets proportionally
      {assignments, _remaining} =
        Enum.reduce(available_buckets, {[], readers}, fn {start_ms, end_ms, pct}, {acc, remaining_readers} ->
          if remaining_readers == [] do
            {acc, []}
          else
            normalized_pct = pct / total_pct
            count = max(1, round(length(readers) * normalized_pct))
            {batch, rest} = Enum.split(remaining_readers, count)

            # Adjust start for partially elapsed buckets
            effective_start = max(start_ms - post_age_ms, 0)
            effective_end = max(end_ms - post_age_ms, effective_start + 1000)

            new_entries = Enum.map(batch, fn bot_id ->
              delay = Enum.random(effective_start..effective_end)
              {delay, bot_id}
            end)

            {acc ++ new_entries, rest}
          end
        end)

      assignments
    end
  end

  defp pick_score_range(roll) do
    {_range, result} =
      Enum.reduce_while(@score_distribution, {0.0, {1, 3}}, fn {min_s, max_s, weight}, {cumulative, _} ->
        new_cumulative = cumulative + weight
        if roll <= new_cumulative do
          {:halt, {new_cumulative, {min_s, max_s}}}
        else
          {:cont, {new_cumulative, {min_s, max_s}}}
        end
      end)

    result
  end

  defp score_to_time_ratio(score) when score <= 3, do: random_float(0.1, 0.3)
  defp score_to_time_ratio(score) when score <= 5, do: random_float(0.3, 0.5)
  defp score_to_time_ratio(score) when score <= 8, do: random_float(0.7, 0.9)
  defp score_to_time_ratio(_score), do: random_float(1.0, 1.2)

  defp score_to_scroll_depth(score) when score <= 3, do: random_float(10.0, 33.0)
  defp score_to_scroll_depth(score) when score <= 5, do: random_float(33.0, 66.0)
  defp score_to_scroll_depth(score) when score <= 8, do: random_float(66.0, 100.0)
  defp score_to_scroll_depth(_score), do: random_float(95.0, 100.0)

  defp random_float(min, max) when min < max do
    min + :rand.uniform() * (max - min)
  end
end
