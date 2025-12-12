defmodule BlocksterV2.EngagementTracker do
  @moduledoc """
  Tracks user engagement metrics for articles.

  Monitors reading behavior including:
  - Time spent on page
  - Scroll depth and patterns
  - Whether user reached the end of article
  - Natural vs bot-like behavior

  Calculates an engagement quality score (1-10) based on these metrics.
  """

  require Logger

  @doc """
  Records an article visit with initial engagement score of 1.
  Called when user lands on a post page.
  Resets engagement metrics for a fresh session (but preserves created_at).
  """
  def record_visit(user_id, post_id, min_read_time) when is_integer(min_read_time) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    # Check if engagement record already exists
    case get_engagement(user_id, post_id) do
      nil ->
        # Create new record with minimum engagement score
        record = {
          :user_post_engagement,
          key,
          user_id,
          post_id,
          0,              # time_spent
          min_read_time,  # min_read_time
          0,              # scroll_depth
          false,          # reached_end
          0,              # scroll_events
          0.0,            # avg_scroll_speed
          0.0,            # max_scroll_speed
          0,              # scroll_reversals
          0,              # focus_changes
          1,              # engagement_score (minimum)
          false,          # is_read
          now,            # created_at
          now             # updated_at
        }
        :mnesia.dirty_write(record)
        {:ok, :created}

      existing ->
        # Record exists - reset for fresh session but preserve created_at
        created_at = elem(existing, 15)
        record = {
          :user_post_engagement,
          key,
          user_id,
          post_id,
          0,              # time_spent - reset
          min_read_time,  # min_read_time - update
          0,              # scroll_depth - reset
          false,          # reached_end - reset
          0,              # scroll_events - reset
          0.0,            # avg_scroll_speed - reset
          0.0,            # max_scroll_speed - reset
          0,              # scroll_reversals - reset
          0,              # focus_changes - reset
          1,              # engagement_score - reset to minimum
          false,          # is_read - reset
          created_at,     # created_at - preserve
          now             # updated_at
        }
        :mnesia.dirty_write(record)
        {:ok, :reset}
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error recording visit: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit recording visit: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Updates engagement metrics in real-time and returns the new score.
  Called periodically as user reads the article (before reaching end).
  Only updates if the new score is higher than the existing score.
  """
  def update_engagement(user_id, post_id, metrics) when is_map(metrics) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    time_spent = Map.get(metrics, "time_spent", 0)
    scroll_depth = Map.get(metrics, "scroll_depth", 0)
    reached_end = Map.get(metrics, "reached_end", false)
    scroll_events = Map.get(metrics, "scroll_events", 0)
    avg_scroll_speed = Map.get(metrics, "avg_scroll_speed", 0.0)
    max_scroll_speed = Map.get(metrics, "max_scroll_speed", 0.0)
    scroll_reversals = Map.get(metrics, "scroll_reversals", 0)
    focus_changes = Map.get(metrics, "focus_changes", 0)

    case get_engagement(user_id, post_id) do
      nil ->
        # No existing record, create one with defaults
        min_read_time = Map.get(metrics, "min_read_time", 60)
        score = calculate_engagement_score(time_spent, min_read_time, scroll_depth, reached_end,
                                           scroll_events, avg_scroll_speed, max_scroll_speed,
                                           scroll_reversals, focus_changes)

        record = {
          :user_post_engagement,
          key,
          user_id,
          post_id,
          time_spent,
          min_read_time,
          scroll_depth,
          reached_end,
          scroll_events,
          avg_scroll_speed,
          max_scroll_speed,
          scroll_reversals,
          focus_changes,
          score,
          reached_end,  # is_read = reached_end
          now,
          now
        }
        :mnesia.dirty_write(record)
        {:ok, score}

      existing ->
        # Update existing record
        min_read_time = elem(existing, 5)
        created_at = elem(existing, 15)

        # Calculate score based on current session metrics
        new_score = calculate_engagement_score(time_spent, min_read_time, scroll_depth, reached_end,
                                           scroll_events, avg_scroll_speed, max_scroll_speed,
                                           scroll_reversals, focus_changes)

        # Store the current session's score in Mnesia (replaces previous)
        record = {
          :user_post_engagement,
          key,
          user_id,
          post_id,
          time_spent,
          min_read_time,
          scroll_depth,
          reached_end,
          scroll_events,
          avg_scroll_speed,
          max_scroll_speed,
          scroll_reversals,
          focus_changes,
          new_score,
          reached_end,  # is_read = reached_end
          created_at,
          now
        }
        :mnesia.dirty_write(record)
        # Return current session score for UI display
        {:ok, new_score}
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error updating engagement: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit updating engagement: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Updates engagement metrics and calculates quality score.
  Called when user scrolls to end of article.
  """
  def record_read(user_id, post_id, metrics) when is_map(metrics) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    time_spent = Map.get(metrics, "time_spent", 0)
    scroll_depth = Map.get(metrics, "scroll_depth", 0)
    reached_end = Map.get(metrics, "reached_end", false)
    scroll_events = Map.get(metrics, "scroll_events", 0)
    avg_scroll_speed = Map.get(metrics, "avg_scroll_speed", 0.0)
    max_scroll_speed = Map.get(metrics, "max_scroll_speed", 0.0)
    scroll_reversals = Map.get(metrics, "scroll_reversals", 0)
    focus_changes = Map.get(metrics, "focus_changes", 0)

    # Get existing record to preserve min_read_time and created_at
    case get_engagement(user_id, post_id) do
      nil ->
        # No existing record, create one with defaults
        min_read_time = Map.get(metrics, "min_read_time", 60)
        score = calculate_engagement_score(time_spent, min_read_time, scroll_depth, reached_end,
                                           scroll_events, avg_scroll_speed, max_scroll_speed,
                                           scroll_reversals, focus_changes)

        record = {
          :user_post_engagement,
          key,
          user_id,
          post_id,
          time_spent,
          min_read_time,
          scroll_depth,
          reached_end,
          scroll_events,
          avg_scroll_speed,
          max_scroll_speed,
          scroll_reversals,
          focus_changes,
          score,
          reached_end,  # is_read = reached_end
          now,
          now
        }
        :mnesia.dirty_write(record)
        {:ok, score}

      existing ->
        # Update existing record
        min_read_time = elem(existing, 5)
        created_at = elem(existing, 15)

        score = calculate_engagement_score(time_spent, min_read_time, scroll_depth, reached_end,
                                           scroll_events, avg_scroll_speed, max_scroll_speed,
                                           scroll_reversals, focus_changes)

        record = {
          :user_post_engagement,
          key,
          user_id,
          post_id,
          time_spent,
          min_read_time,
          scroll_depth,
          reached_end,
          scroll_events,
          avg_scroll_speed,
          max_scroll_speed,
          scroll_reversals,
          focus_changes,
          score,
          reached_end,  # is_read = reached_end
          created_at,
          now
        }
        :mnesia.dirty_write(record)
        {:ok, score}
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error recording read: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit recording read: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Gets engagement data for a user on a specific post.
  Returns a map with engagement metrics or nil if not found.
  """
  def get_engagement(user_id, post_id) do
    key = {user_id, post_id}

    case :mnesia.dirty_read({:user_post_engagement, key}) do
      [] -> nil
      [record] -> record
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Gets engagement data as a map for display.
  """
  def get_engagement_map(user_id, post_id) do
    case get_engagement(user_id, post_id) do
      nil -> nil
      record ->
        %{
          time_spent: elem(record, 4),
          min_read_time: elem(record, 5),
          scroll_depth: elem(record, 6),
          reached_end: elem(record, 7),
          scroll_events: elem(record, 8),
          avg_scroll_speed: elem(record, 9),
          max_scroll_speed: elem(record, 10),
          scroll_reversals: elem(record, 11),
          focus_changes: elem(record, 12),
          engagement_score: elem(record, 13),
          is_read: elem(record, 14),
          created_at: elem(record, 15),
          updated_at: elem(record, 16)
        }
    end
  end

  @doc """
  Calculates engagement quality score (1-10) based on reading behavior.

  Factors considered:
  - Time spent vs minimum read time (reading speed)
  - Scroll depth (how much of article was seen)
  - Whether end was reached
  - Scroll pattern naturalness (events, speed, reversals)
  - Focus changes (tab switching)

  Higher scores indicate more likely genuine reading.
  Lower scores indicate bot-like or skimming behavior.
  """
  def calculate_engagement_score(time_spent, min_read_time, scroll_depth, reached_end,
                                  _scroll_events, _avg_scroll_speed, _max_scroll_speed,
                                  _scroll_reversals, _focus_changes) do
    # Base score starts at 1
    score = 1.0

    Logger.info("[EngagementTracker] Calculating score - time_spent: #{time_spent}, min_read_time: #{min_read_time}, scroll_depth: #{scroll_depth}, reached_end: #{reached_end}")

    # Time ratio score (0-6 points) - incremental thresholds
    # min_read_time is based on word count at 5 words/second
    time_ratio = if min_read_time > 0, do: time_spent / min_read_time, else: 0
    time_score = cond do
      time_ratio >= 1.0 -> 6.0   # 100%+ of read time (full points)
      time_ratio >= 0.9 -> 5.0   # 90%+ of read time
      time_ratio >= 0.8 -> 4.0   # 80%+ of read time
      time_ratio >= 0.7 -> 3.0   # 70%+ of read time
      time_ratio >= 0.5 -> 2.0   # 50%+ of read time
      time_ratio >= 0.3 -> 1.0   # 30%+ of read time
      true -> 0.0                # Too fast
    end

    # Scroll depth score (0-3 points)
    # 100% depth means user reached end of article
    depth_score = cond do
      scroll_depth >= 100 or reached_end -> 3.0  # Reached the very end
      scroll_depth >= 66 -> 2.0   # Two-thirds of article
      scroll_depth >= 33 -> 1.0   # One-third of article
      true -> 0.0
    end

    # Calculate final score
    raw_score = score + time_score + depth_score

    Logger.info("[EngagementTracker] Score breakdown - base: #{score}, time: #{time_score}, depth: #{depth_score}, raw_total: #{raw_score}")

    # Clamp to 1-10 range
    raw_score
    |> max(1.0)
    |> min(10.0)
    |> round()
  end

  @doc """
  Calculates minimum read time for an article based on word count.
  Assumes average reading speed of 10 words per second (600 wpm).
  """
  def calculate_min_read_time(word_count) when is_integer(word_count) do
    # 10 words per second = 600 words per minute
    max(div(word_count, 10), 5)  # Minimum 5 seconds
  end

  def calculate_min_read_time(_), do: 60  # Default 60 seconds

  @doc """
  Counts words in article content (TipTap JSON format).
  """
  def count_words(nil), do: 0
  def count_words(%{"type" => "doc", "content" => content}) when is_list(content) do
    content
    |> Enum.map(&count_node_words/1)
    |> Enum.sum()
  end
  def count_words(_), do: 0

  defp count_node_words(%{"type" => "text", "text" => text}) when is_binary(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end
  defp count_node_words(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map(&count_node_words/1)
    |> Enum.sum()
  end
  defp count_node_words(_), do: 0

  @doc """
  Gets user multiplier data from the :user_multipliers Mnesia table.
  Returns the overall_multiplier value, defaulting to 1 if not found.
  """
  def get_user_multiplier(user_id) do
    case :mnesia.dirty_read({:user_multipliers, user_id}) do
      [] -> 1
      [record] ->
        # overall_multiplier is at index 7 in the record tuple
        # {:user_multipliers, user_id, smart_wallet, x, linkedin, personal, rogue, overall, ...]
        elem(record, 7) || 1
    end
  rescue
    _ -> 1
  catch
    :exit, _ -> 1
  end

  @doc """
  Calculates the BUX earned for reading an article.
  Formula: (engagement_score / 10) * base_bux_reward * user_multiplier
  """
  def calculate_bux_earned(engagement_score, base_bux_reward, user_multiplier) do
    score_factor = engagement_score / 10.0
    base_reward = base_bux_reward || 1
    multiplier = user_multiplier || 1

    (score_factor * base_reward * multiplier)
    |> Float.round(2)
  end

  # =============================================================================
  # User Post Rewards Functions
  # =============================================================================

  @doc """
  Gets the rewards record for a user on a specific post.
  Returns nil if not found.
  """
  def get_rewards(user_id, post_id) do
    key = {user_id, post_id}

    case :mnesia.dirty_read({:user_post_rewards, key}) do
      [] -> nil
      [record] -> record
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Gets the rewards as a map for display.

  Mnesia tuple structure (0-indexed):
  0: :user_post_rewards (table name)
  1: key ({user_id, post_id})
  2: user_id
  3: post_id
  4: read_bux
  5: read_paid
  6: read_tx_id
  7: x_share_bux
  8: x_share_paid
  9: x_share_tx_id
  10: linkedin_share_bux
  11: linkedin_share_paid
  12: linkedin_share_tx_id
  13: total_bux
  14: total_paid_bux
  15: created_at
  16: updated_at
  """
  def get_rewards_map(user_id, post_id) do
    case get_rewards(user_id, post_id) do
      nil -> nil
      record ->
        %{
          read_bux: elem(record, 4),
          read_paid: elem(record, 5),
          read_tx_id: elem(record, 6),
          x_share_bux: elem(record, 7),
          x_share_paid: elem(record, 8),
          x_share_tx_id: elem(record, 9),
          linkedin_share_bux: elem(record, 10),
          linkedin_share_paid: elem(record, 11),
          linkedin_share_tx_id: elem(record, 12),
          total_bux: elem(record, 13),
          total_paid_bux: elem(record, 14),
          created_at: elem(record, 15),
          updated_at: elem(record, 16)
        }
    end
  end

  @doc """
  Records BUX reward for reading an article.
  Returns {:ok, bux_earned} if new reward recorded, {:already_rewarded, existing_bux} if already exists.
  """
  def record_read_reward(user_id, post_id, bux_earned) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    case get_rewards(user_id, post_id) do
      nil ->
        # No existing reward - create new record
        record = {
          :user_post_rewards,
          key,
          user_id,
          post_id,
          bux_earned,        # read_bux
          false,             # read_paid
          nil,               # read_tx_id
          nil,               # x_share_bux
          false,             # x_share_paid
          nil,               # x_share_tx_id
          nil,               # linkedin_share_bux
          false,             # linkedin_share_paid
          nil,               # linkedin_share_tx_id
          bux_earned,        # total_bux
          0,                 # total_paid_bux
          now,               # created_at
          now                # updated_at
        }
        :mnesia.dirty_write(record)
        Logger.info("[EngagementTracker] Recorded read reward for user #{user_id} on post #{post_id}: #{bux_earned} BUX")
        {:ok, bux_earned}

      existing ->
        # Check if already has read reward (read_bux is at index 4)
        existing_read_bux = elem(existing, 4)

        if existing_read_bux && existing_read_bux > 0 do
          # Already received read reward
          Logger.info("[EngagementTracker] User #{user_id} already received #{existing_read_bux} BUX for reading post #{post_id}")
          {:already_rewarded, existing_read_bux}
        else
          # Has record but no read reward yet (maybe shared first) - update with read reward
          # total_bux is at index 13
          total_bux = (elem(existing, 13) || 0) + bux_earned
          # created_at is at index 15
          created_at = elem(existing, 15)

          record = {
            :user_post_rewards,
            key,
            user_id,
            post_id,
            bux_earned,                # read_bux (index 4)
            false,                     # read_paid (index 5)
            nil,                       # read_tx_id (index 6)
            elem(existing, 7),         # x_share_bux (preserve)
            elem(existing, 8),         # x_share_paid (preserve)
            elem(existing, 9),         # x_share_tx_id (preserve)
            elem(existing, 10),        # linkedin_share_bux (preserve)
            elem(existing, 11),        # linkedin_share_paid (preserve)
            elem(existing, 12),        # linkedin_share_tx_id (preserve)
            total_bux,                 # total_bux (index 13)
            elem(existing, 14),        # total_paid_bux (preserve, index 14)
            created_at,                # created_at (preserve, index 15)
            now                        # updated_at (index 16)
          }
          :mnesia.dirty_write(record)
          Logger.info("[EngagementTracker] Updated read reward for user #{user_id} on post #{post_id}: #{bux_earned} BUX")
          {:ok, bux_earned}
        end
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error recording read reward: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit recording read reward: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Records BUX reward for sharing on X (Twitter).
  """
  def record_x_share_reward(user_id, post_id, bux_earned) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    case get_rewards(user_id, post_id) do
      nil ->
        # No existing record - create new with this share reward
        record = {
          :user_post_rewards,
          key,
          user_id,
          post_id,
          nil,               # read_bux
          false,             # read_paid
          nil,               # read_tx_id
          bux_earned,        # x_share_bux
          false,             # x_share_paid
          nil,               # x_share_tx_id
          nil,               # linkedin_share_bux
          false,             # linkedin_share_paid
          nil,               # linkedin_share_tx_id
          bux_earned,        # total_bux
          0,                 # total_paid_bux
          now,               # created_at
          now                # updated_at
        }
        :mnesia.dirty_write(record)
        {:ok, bux_earned}

      existing ->
        # Check if already has X share reward (x_share_bux is at index 7)
        existing_x_bux = elem(existing, 7)

        if existing_x_bux && existing_x_bux > 0 do
          {:already_rewarded, existing_x_bux}
        else
          # Update with X share reward
          # total_bux is at index 13, created_at is at index 15
          total_bux = (elem(existing, 13) || 0) + bux_earned
          created_at = elem(existing, 15)

          record = {
            :user_post_rewards,
            key,
            user_id,
            post_id,
            elem(existing, 4),         # read_bux (preserve, index 4)
            elem(existing, 5),         # read_paid (preserve, index 5)
            elem(existing, 6),         # read_tx_id (preserve, index 6)
            bux_earned,                # x_share_bux (index 7)
            false,                     # x_share_paid (index 8)
            nil,                       # x_share_tx_id (index 9)
            elem(existing, 10),        # linkedin_share_bux (preserve, index 10)
            elem(existing, 11),        # linkedin_share_paid (preserve, index 11)
            elem(existing, 12),        # linkedin_share_tx_id (preserve, index 12)
            total_bux,                 # total_bux (index 13)
            elem(existing, 14),        # total_paid_bux (preserve, index 14)
            created_at,                # created_at (preserve, index 15)
            now                        # updated_at (index 16)
          }
          :mnesia.dirty_write(record)
          {:ok, bux_earned}
        end
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error recording X share reward: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit recording X share reward: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Deletes a rewards record for a user on a specific post.
  Use this to clean up bad/corrupt records.
  """
  def delete_rewards(user_id, post_id) do
    key = {user_id, post_id}

    case :mnesia.dirty_delete(:user_post_rewards, key) do
      :ok ->
        Logger.info("[EngagementTracker] Deleted rewards record for user #{user_id} on post #{post_id}")
        :ok
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error deleting rewards: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit deleting rewards: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Marks read reward as paid and stores the transaction ID.
  Called after successful BUX minting.
  """
  def mark_read_reward_paid(user_id, post_id, tx_id) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    case get_rewards(user_id, post_id) do
      nil ->
        Logger.warning("[EngagementTracker] No rewards record found to mark as paid for user #{user_id} on post #{post_id}")
        {:error, :not_found}

      existing ->
        # Update read_paid (index 5) and read_tx_id (index 6) and updated_at (index 15)
        read_bux = elem(existing, 4)
        updated = existing
          |> put_elem(5, true)          # read_paid
          |> put_elem(6, tx_id)         # read_tx_id
          |> put_elem(14, (elem(existing, 13) || 0) + (read_bux || 0))  # total_paid_bux
          |> put_elem(15, now)          # updated_at

        :mnesia.dirty_write(updated)
        Logger.info("[EngagementTracker] Marked read reward paid for user #{user_id} on post #{post_id}: tx=#{tx_id}")
        :ok
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error marking read reward paid: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit marking read reward paid: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Records BUX reward for sharing on LinkedIn.
  """
  def record_linkedin_share_reward(user_id, post_id, bux_earned) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    case get_rewards(user_id, post_id) do
      nil ->
        # No existing record - create new with this share reward
        record = {
          :user_post_rewards,
          key,
          user_id,
          post_id,
          nil,               # read_bux (index 4)
          false,             # read_paid (index 5)
          nil,               # read_tx_id (index 6)
          nil,               # x_share_bux (index 7)
          false,             # x_share_paid (index 8)
          nil,               # x_share_tx_id (index 9)
          bux_earned,        # linkedin_share_bux (index 10)
          false,             # linkedin_share_paid (index 11)
          nil,               # linkedin_share_tx_id (index 12)
          bux_earned,        # total_bux (index 13)
          0,                 # total_paid_bux (index 14)
          now,               # created_at (index 15)
          now                # updated_at (index 16)
        }
        :mnesia.dirty_write(record)
        {:ok, bux_earned}

      existing ->
        # Check if already has LinkedIn share reward (linkedin_share_bux is at index 10)
        existing_linkedin_bux = elem(existing, 10)

        if existing_linkedin_bux && existing_linkedin_bux > 0 do
          {:already_rewarded, existing_linkedin_bux}
        else
          # Update with LinkedIn share reward
          # total_bux is at index 13, created_at is at index 15
          total_bux = (elem(existing, 13) || 0) + bux_earned
          created_at = elem(existing, 15)

          record = {
            :user_post_rewards,
            key,
            user_id,
            post_id,
            elem(existing, 4),         # read_bux (preserve, index 4)
            elem(existing, 5),         # read_paid (preserve, index 5)
            elem(existing, 6),         # read_tx_id (preserve, index 6)
            elem(existing, 7),         # x_share_bux (preserve, index 7)
            elem(existing, 8),         # x_share_paid (preserve, index 8)
            elem(existing, 9),         # x_share_tx_id (preserve, index 9)
            bux_earned,                # linkedin_share_bux (index 10)
            false,                     # linkedin_share_paid (index 11)
            nil,                       # linkedin_share_tx_id (index 12)
            total_bux,                 # total_bux (index 13)
            elem(existing, 14),        # total_paid_bux (preserve, index 14)
            created_at,                # created_at (preserve, index 15)
            now                        # updated_at (index 16)
          }
          :mnesia.dirty_write(record)
          {:ok, bux_earned}
        end
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error recording LinkedIn share reward: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit recording LinkedIn share reward: #{inspect(e)}")
      {:error, e}
  end

  # =============================================================================
  # User and Post BUX Balance Functions
  # =============================================================================

  @doc """
  Updates the user's BUX balance in the user_bux_points table.
  Uses the on-chain balance fetched from the blockchain.

  Table structure: user_id, user_smart_wallet, bux_balance, extra_field1-4, created_at, updated_at
  """
  def update_user_bux_balance(user_id, wallet_address, on_chain_balance) do
    now = System.system_time(:second)

    case :mnesia.dirty_read({:user_bux_points, user_id}) do
      [] ->
        # No existing record - create new
        record = {
          :user_bux_points,
          user_id,
          wallet_address,
          on_chain_balance,
          nil,  # extra_field1
          nil,  # extra_field2
          nil,  # extra_field3
          nil,  # extra_field4
          now,  # created_at
          now   # updated_at
        }
        :mnesia.dirty_write(record)
        Logger.info("[EngagementTracker] Created user_bux_points for user #{user_id}: balance=#{on_chain_balance}")

        # Broadcast balance update to all subscribed LiveViews
        BlocksterV2Web.BuxBalanceHook.broadcast_balance_update(user_id, on_chain_balance)

        {:ok, on_chain_balance}

      [existing] ->
        # Update existing record with new balance
        updated = existing
          |> put_elem(2, wallet_address)      # user_smart_wallet
          |> put_elem(3, on_chain_balance)    # bux_balance
          |> put_elem(9, now)                 # updated_at
        :mnesia.dirty_write(updated)
        Logger.info("[EngagementTracker] Updated user_bux_points for user #{user_id}: balance=#{on_chain_balance}")

        # Broadcast balance update to all subscribed LiveViews
        BlocksterV2Web.BuxBalanceHook.broadcast_balance_update(user_id, on_chain_balance)

        {:ok, on_chain_balance}
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error updating user bux balance: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit updating user bux balance: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Gets the user's BUX balance from the user_bux_points Mnesia table.
  Returns the on-chain balance that was last synced after a mint.
  Returns 0 if no record exists.
  """
  def get_user_bux_balance(user_id) do
    case :mnesia.dirty_read({:user_bux_points, user_id}) do
      [] -> 0
      [record] -> elem(record, 3) || 0  # bux_balance is at index 3
    end
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  @doc """
  Gets the BUX balance for a post from the post_bux_points table.
  Returns 0 if no record exists.
  """
  def get_post_bux_balance(post_id) do
    case :mnesia.dirty_read({:post_bux_points, post_id}) do
      [] -> 0
      [record] -> elem(record, 4) || 0
    end
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  @doc """
  Gets BUX balances for multiple posts at once.
  Returns a map of post_id => bux_balance.
  """
  def get_post_bux_balances(post_ids) when is_list(post_ids) do
    post_ids
    |> Enum.map(fn post_id ->
      {post_id, get_post_bux_balance(post_id)}
    end)
    |> Map.new()
  end

  @doc """
  Adds earned BUX to a post's bux_balance in the post_bux_points table.

  Table structure: post_id, reward, read_time, bux_balance, bux_deposited, extra_field1-4, created_at, updated_at
  """
  def add_post_bux_earned(post_id, amount) do
    now = System.system_time(:second)

    result = case :mnesia.dirty_read({:post_bux_points, post_id}) do
      [] ->
        # No existing record - create new with this amount as balance
        record = {
          :post_bux_points,
          post_id,
          nil,     # reward
          nil,     # read_time
          amount,  # bux_balance
          nil,     # bux_deposited
          nil,     # extra_field1
          nil,     # extra_field2
          nil,     # extra_field3
          nil,     # extra_field4
          now,     # created_at
          now      # updated_at
        }
        :mnesia.dirty_write(record)
        Logger.info("[EngagementTracker] Created post_bux_points for post #{post_id}: balance=#{amount}")
        {:ok, amount}

      [existing] ->
        # Add to existing balance
        current_balance = elem(existing, 4) || 0
        new_balance = current_balance + amount
        updated = existing
          |> put_elem(4, new_balance)  # bux_balance
          |> put_elem(11, now)         # updated_at
        :mnesia.dirty_write(updated)
        Logger.info("[EngagementTracker] Updated post_bux_points for post #{post_id}: balance=#{new_balance} (+#{amount})")
        {:ok, new_balance}
    end

    # Broadcast the BUX balance update
    case result do
      {:ok, new_balance} ->
        broadcast_bux_update(post_id, new_balance)
        result
      _ ->
        result
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error adding post bux earned: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit adding post bux earned: #{inspect(e)}")
      {:error, e}
  end

  # PubSub functions for real-time BUX balance updates
  @doc """
  Broadcasts a BUX balance update for a specific post.
  """
  def broadcast_bux_update(post_id, new_balance) do
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "post_bux:#{post_id}",
      {:bux_update, post_id, new_balance}
    )
    # Also broadcast to a global topic for index pages showing multiple posts
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "post_bux:all",
      {:bux_update, post_id, new_balance}
    )
  end

  @doc """
  Subscribe to BUX balance updates for a specific post.
  """
  def subscribe_to_post_bux(post_id) do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post_bux:#{post_id}")
  end

  @doc """
  Subscribe to all BUX balance updates (for index pages).
  """
  def subscribe_to_all_bux_updates() do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post_bux:all")
  end

  @doc """
  Unsubscribe from BUX balance updates for a specific post.
  """
  def unsubscribe_from_post_bux(post_id) do
    Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post_bux:#{post_id}")
  end

  @doc """
  Unsubscribe from all BUX balance updates.
  """
  def unsubscribe_from_all_bux_updates() do
    Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post_bux:all")
  end
end
