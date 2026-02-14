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
        # No visit record - cap client time to 2x min_read_time as sanity check
        client_time = Map.get(metrics, "time_spent", 0)
        time_spent = min(client_time, min_read_time * 2)

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

        # ANTI-EXPLOIT: Use server-side elapsed time instead of client-reported time_spent.
        # created_at was set when article-visited fired (record_visit). The server knows
        # exactly how long the user has been on the page. Take the minimum of client time
        # and server elapsed time - attackers cannot fake wall clock time on the server.
        client_time = Map.get(metrics, "time_spent", 0)
        server_elapsed = now - created_at
        time_spent = min(client_time, server_elapsed)

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
  Returns list of post IDs where a user has actually received BUX rewards.
  Used for filtering suggested posts to show unrewarded content first.

  A post is considered "read" only if the user has received a BUX reward for it
  (read_bux > 0 in user_post_rewards table).
  """
  def get_user_read_post_ids(user_id) when is_integer(user_id) do
    # Query user_post_rewards table for posts where user earned BUX
    pattern = {:user_post_rewards, :_, user_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

    :mnesia.dirty_match_object(pattern)
    |> Enum.filter(fn record ->
      # read_bux is at index 4
      read_bux = elem(record, 4)
      read_bux != nil and read_bux > 0
    end)
    |> Enum.map(fn record -> elem(record, 3) end)  # post_id is at index 3
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  def get_user_read_post_ids(_), do: []

  @doc """
  Gets all post rewards for a user as a map of post_id => reward details.
  Returns a map where each post has:
  - read_bux: BUX earned from reading
  - x_share_bux: BUX earned from X share
  - watch_bux: BUX earned from video watching
  - total_bux: Total BUX earned from this post

  Used for displaying earned badges on post cards.
  """
  def get_user_post_rewards_map(user_id) when is_integer(user_id) do
    # Get read/share rewards from user_post_rewards table
    read_share_pattern = {:user_post_rewards, :_, user_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

    read_share_map = :mnesia.dirty_match_object(read_share_pattern)
    |> Enum.reduce(%{}, fn record, acc ->
      post_id = elem(record, 3)
      read_bux = elem(record, 4) || 0
      x_share_bux = elem(record, 7) || 0

      # Only include if there's any reward
      if read_bux > 0 or x_share_bux > 0 do
        Map.put(acc, post_id, %{
          read_bux: read_bux,
          x_share_bux: x_share_bux,
          watch_bux: 0
        })
      else
        acc
      end
    end)

    # Get video watch rewards from user_video_engagement table
    # Pattern: table_name, key, user_id, post_id, high_water_mark, total_earnable_time, video_duration,
    #          completion_percentage, total_bux_earned (index 8), last_session_bux, total_pause_count,
    #          total_tab_away_count, session_count, last_watched_at, created_at, updated_at, video_tx_ids
    # Total: 17 elements (table name + 16 attributes)
    video_pattern = {:user_video_engagement, :_, user_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

    video_map = try do
      :mnesia.dirty_match_object(video_pattern)
      |> Enum.reduce(%{}, fn record, acc ->
        post_id = elem(record, 3)
        watch_bux = elem(record, 8) || 0

        if watch_bux > 0 do
          Map.put(acc, post_id, watch_bux)
        else
          acc
        end
      end)
    rescue
      _ -> %{}
    catch
      :exit, _ -> %{}
    end

    # Merge video rewards into read/share map
    Enum.reduce(video_map, read_share_map, fn {post_id, watch_bux}, acc ->
      existing = Map.get(acc, post_id, %{read_bux: 0, x_share_bux: 0, watch_bux: 0})
      Map.put(acc, post_id, Map.put(existing, :watch_bux, watch_bux))
    end)
  rescue
    _ -> %{}
  catch
    :exit, _ -> %{}
  end

  def get_user_post_rewards_map(_), do: %{}

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
  Gets all user multiplier components from the :user_multipliers Mnesia table.
  Returns a map with all multiplier values for display.
  """
  def get_user_multiplier_details(user_id) do
    case :mnesia.dirty_read({:user_multipliers, user_id}) do
      [] ->
        %{
          x_multiplier: 1,
          linkedin_multiplier: 1,
          personal_multiplier: 1,
          rogue_multiplier: 1,
          hardware_wallet_multiplier: 0,
          overall_multiplier: 1
        }
      [record] ->
        # {:user_multipliers, user_id, smart_wallet, x, linkedin, personal, rogue, overall, extra1, ...}
        # extra1 (index 8) is hardware_wallet_multiplier
        %{
          x_multiplier: elem(record, 3) || 1,
          linkedin_multiplier: elem(record, 4) || 1,
          personal_multiplier: elem(record, 5) || 1,
          rogue_multiplier: elem(record, 6) || 1,
          hardware_wallet_multiplier: elem(record, 8) || 0,
          overall_multiplier: elem(record, 7) || 1
        }
    end
  rescue
    _ -> %{x_multiplier: 1, linkedin_multiplier: 1, personal_multiplier: 1, rogue_multiplier: 1, hardware_wallet_multiplier: 0, overall_multiplier: 1}
  catch
    :exit, _ -> %{x_multiplier: 1, linkedin_multiplier: 1, personal_multiplier: 1, rogue_multiplier: 1, hardware_wallet_multiplier: 0, overall_multiplier: 1}
  end

  @doc """
  Gets user geographic multiplier from the User database record.
  Returns the geo_multiplier value, defaulting to 0.5 for unverified users.
  """
  def get_geo_multiplier(user_id) do
    case BlocksterV2.Repo.get(BlocksterV2.Accounts.User, user_id) do
      nil -> 0.5  # Default for non-existent users
      user -> Decimal.to_float(user.geo_multiplier || Decimal.new("0.5"))
    end
  rescue
    _ -> 0.5
  catch
    :exit, _ -> 0.5
  end

  @doc """
  Gets user X (Twitter) multiplier from the :user_multipliers Mnesia table.
  Returns the x_multiplier value, defaulting to 1 if not found or nil.
  Creates record with default values if user doesn't exist in the table.
  """
  def get_user_x_multiplier(user_id) do
    case :mnesia.dirty_read({:user_multipliers, user_id}) do
      [] ->
        # Create record with default values
        now = DateTime.utc_now()
        record = {:user_multipliers, user_id, nil, 1, 1, 1, 1, 1, nil, nil, nil, nil, now, now}
        :mnesia.dirty_write(record)
        1

      [record] ->
        # x_multiplier is at index 3 in the record tuple
        # {:user_multipliers, user_id, smart_wallet, x, linkedin, personal, rogue, overall, ...]
        elem(record, 3) || 1
    end
  rescue
    _ -> 1
  catch
    :exit, _ -> 1
  end

  @doc """
  Sets user X (Twitter) multiplier in the :user_multipliers Mnesia table.
  Creates record with default values if user doesn't exist in the table.
  Returns :ok on success.
  """
  def set_user_x_multiplier(user_id, x_multiplier) do
    now = DateTime.utc_now()

    case :mnesia.dirty_read({:user_multipliers, user_id}) do
      [] ->
        # Create new record with the x_multiplier
        # {:user_multipliers, user_id, smart_wallet, x, linkedin, personal, rogue, overall, extra1, extra2, extra3, extra4, created_at, updated_at}
        record = {:user_multipliers, user_id, nil, x_multiplier, 1, 1, 1, 1, nil, nil, nil, nil, now, now}
        :mnesia.dirty_write(record)
        Logger.info("[EngagementTracker] Created user_multipliers for user #{user_id} with x_multiplier=#{x_multiplier}")
        :ok

      [existing_record] ->
        # Update existing record - only change x_multiplier (index 3) and updated_at (index 13)
        updated_record = existing_record
          |> put_elem(3, x_multiplier)
          |> put_elem(13, now)
        :mnesia.dirty_write(updated_record)
        Logger.info("[EngagementTracker] Updated x_multiplier=#{x_multiplier} for user #{user_id}")
        :ok
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error setting x_multiplier: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit setting x_multiplier: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Calculates the BUX earned for reading an article.
  Formula: (engagement_score / 10) * base_bux_reward * user_multiplier * geo_multiplier
  """
  def calculate_bux_earned(engagement_score, base_bux_reward, user_multiplier, geo_multiplier \\ 1.0) do
    score_factor = engagement_score / 10.0
    base_reward = base_bux_reward || 1
    multiplier = user_multiplier || 1
    geo_mult = geo_multiplier || 1.0

    (score_factor * base_reward * multiplier * geo_mult)
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
  Gets all rewards for a user across all posts from the Mnesia table.
  Returns a list of activity maps sorted by updated_at (most recent first).

  Each activity includes:
  - type: :read (for article reads)
  - label: "Article Read"
  - amount: BUX earned
  - post_id: the post ID
  - timestamp: DateTime when the reward was recorded
  """
  def get_all_user_post_rewards(user_id) do
    # Use match_object to find all records for this user
    # Pattern matches on user_id at index 2
    pattern = {:user_post_rewards, :_, user_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

    records = :mnesia.dirty_match_object(pattern)

    # Convert records to activity list (only read rewards from this table)
    records
    |> Enum.flat_map(&record_to_read_activities/1)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp record_to_read_activities(record) do
    post_id = elem(record, 3)
    read_bux = elem(record, 4)
    read_tx_id = elem(record, 6)
    updated_at = elem(record, 16)

    # Convert unix timestamp to DateTime
    timestamp = DateTime.from_unix!(updated_at)

    if read_bux && read_bux > 0 do
      [%{
        type: :read,
        label: "Article Read",
        amount: read_bux,
        post_id: post_id,
        tx_id: read_tx_id,
        timestamp: timestamp
      }]
    else
      []
    end
  end

  @doc """
  Records BUX reward for reading an article.
  Returns {:ok, bux_earned} if new reward recorded, {:already_rewarded, existing_bux} if already exists.
  """
  def record_read_reward(user_id, post_id, bux_earned, tx_hash \\ nil) do
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
          tx_hash,           # read_tx_id
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
        {:ok, bux_earned}

      existing ->
        # Check if already has read reward (read_bux is at index 4)
        existing_read_bux = elem(existing, 4)

        if existing_read_bux && existing_read_bux > 0 do
          # Already received read reward
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
            tx_hash,                   # read_tx_id (index 6)
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
        # Update read_paid (index 5), read_tx_id (index 6), and updated_at (index 16)
        read_bux = elem(existing, 4) || 0
        current_paid = elem(existing, 14) || 0
        updated = existing
          |> put_elem(5, true)                        # read_paid
          |> put_elem(6, tx_id)                       # read_tx_id
          |> put_elem(14, current_paid + read_bux)    # total_paid_bux += read_bux
          |> put_elem(16, now)                        # updated_at

        :mnesia.dirty_write(updated)
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
  Records X share reward as earned AND paid in one operation.
  Called when user successfully retweets and receives their BUX reward.

  Updates user_post_rewards Mnesia table with:
  - x_share_bux: the BUX amount earned
  - x_share_paid: true
  - x_share_tx_id: the blockchain transaction hash
  - total_bux: incremented by bux_earned
  - total_paid_bux: incremented by bux_earned
  """
  def record_x_share_reward_paid(user_id, post_id, bux_earned, tx_hash) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    case get_rewards(user_id, post_id) do
      nil ->
        # No existing record - create new with X share reward already paid
        record = {
          :user_post_rewards,
          key,
          user_id,
          post_id,
          nil,               # read_bux (index 4)
          false,             # read_paid (index 5)
          nil,               # read_tx_id (index 6)
          bux_earned,        # x_share_bux (index 7)
          true,              # x_share_paid (index 8)
          tx_hash,           # x_share_tx_id (index 9)
          nil,               # linkedin_share_bux (index 10)
          false,             # linkedin_share_paid (index 11)
          nil,               # linkedin_share_tx_id (index 12)
          bux_earned,        # total_bux (index 13)
          bux_earned,        # total_paid_bux (index 14)
          now,               # created_at (index 15)
          now                # updated_at (index 16)
        }
        :mnesia.dirty_write(record)
        {:ok, bux_earned}

      existing ->
        # Check if already has X share reward (x_share_bux is at index 7)
        existing_x_bux = elem(existing, 7)

        if existing_x_bux && existing_x_bux > 0 do
          # Already received X share reward - just update tx if missing
          if elem(existing, 8) do
            {:already_rewarded, existing_x_bux}
          else
            # Update to mark as paid
            total_paid = (elem(existing, 14) || 0) + existing_x_bux
            updated = existing
              |> put_elem(8, true)           # x_share_paid
              |> put_elem(9, tx_hash)        # x_share_tx_id
              |> put_elem(14, total_paid)    # total_paid_bux
              |> put_elem(16, now)           # updated_at

            :mnesia.dirty_write(updated)
            {:ok, existing_x_bux}
          end
        else
          # Update with X share reward as paid
          total_bux = (elem(existing, 13) || 0) + bux_earned
          total_paid = (elem(existing, 14) || 0) + bux_earned
          created_at = elem(existing, 15)

          record = {
            :user_post_rewards,
            key,
            user_id,
            post_id,
            elem(existing, 4),         # read_bux (preserve)
            elem(existing, 5),         # read_paid (preserve)
            elem(existing, 6),         # read_tx_id (preserve)
            bux_earned,                # x_share_bux (index 7)
            true,                      # x_share_paid (index 8)
            tx_hash,                   # x_share_tx_id (index 9)
            elem(existing, 10),        # linkedin_share_bux (preserve)
            elem(existing, 11),        # linkedin_share_paid (preserve)
            elem(existing, 12),        # linkedin_share_tx_id (preserve)
            total_bux,                 # total_bux (index 13)
            total_paid,                # total_paid_bux (index 14)
            created_at,                # created_at (preserve)
            now                        # updated_at (index 16)
          }
          :mnesia.dirty_write(record)
          Logger.info("[EngagementTracker] Recorded X share reward paid for user #{user_id} on post #{post_id}: #{bux_earned} BUX, tx=#{tx_hash}")
          {:ok, bux_earned}
        end
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error recording X share reward paid: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit recording X share reward paid: #{inspect(e)}")
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
  Updates the user's BUX balance in the user_bux_points table (legacy).
  Uses the aggregate balance fetched from the blockchain.
  Also broadcasts the aggregate from user_bux_balances to subscribed LiveViews.

  Table structure: user_id, user_smart_wallet, bux_balance, extra_field1-4, created_at, updated_at
  """
  def update_user_bux_balance(user_id, wallet_address, aggregate_balance) do
    now = System.system_time(:second)

    case :mnesia.dirty_read({:user_bux_points, user_id}) do
      [] ->
        # No existing record - create new
        record = {
          :user_bux_points,
          user_id,
          wallet_address,
          aggregate_balance,
          nil,  # extra_field1
          nil,  # extra_field2
          nil,  # extra_field3
          nil,  # extra_field4
          now,  # created_at
          now   # updated_at
        }
        :mnesia.dirty_write(record)

        {:ok, aggregate_balance}

      [existing] ->
        # Update existing record with new balance
        updated = existing
          |> put_elem(2, wallet_address)      # user_smart_wallet
          |> put_elem(3, aggregate_balance)   # bux_balance
          |> put_elem(9, now)                 # updated_at
        :mnesia.dirty_write(updated)

        {:ok, aggregate_balance}
    end

    # NOTE: Broadcast removed - caller (sync_user_balances) handles broadcasting once at the end
    # to avoid multiple redundant broadcasts during batch updates
    {:ok, aggregate_balance}
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
  Gets the user's aggregate BUX balance from the user_bux_balances Mnesia table.
  Returns the sum of all token balances that was last synced from chain.
  Returns 0 if no record exists.
  """
  def get_user_bux_balance(user_id) do
    case :mnesia.dirty_read({:user_bux_balances, user_id}) do
      [] -> 0
      [record] -> elem(record, 4) || 0  # aggregate_bux_balance is at index 4
    end
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  @doc """
  Gets the BUX balance for a post from the post_bux_points table.
  Returns 0 if no record exists.
  Note: This can return negative values for internal use.
  For display purposes, use get_post_bux_balance_display/1.
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
  Gets pool balance for display purposes (always >= 0).
  Never shows negative values to users.
  """
  def get_post_bux_balance_display(post_id) do
    max(0, get_post_bux_balance(post_id))
  end

  @doc """
  Checks if pool is available for NEW earning actions.
  Returns true only if balance > 0.
  Used to determine if a new user can start earning.
  """
  def pool_available?(post_id) do
    get_post_bux_balance(post_id) > 0
  end

  @doc """
  Deducts amount from post's BUX pool with GUARANTEED payout.
  Pool CAN go negative to honor guaranteed earnings.

  This is used when a user completed an earning action that started
  when the pool was positive. They are guaranteed the full reward.

  Returns {:ok, new_balance} where new_balance can be negative.
  """
  def deduct_from_pool_guaranteed(post_id, amount) when is_number(amount) and amount > 0 do
    BlocksterV2.PostBuxPoolWriter.deduct_guaranteed(post_id, amount)
  end

  def deduct_from_pool_guaranteed(_post_id, _amount), do: {:ok, 0}

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
        {:ok, amount}

      [existing] ->
        # Add to existing balance
        current_balance = elem(existing, 4) || 0
        new_balance = current_balance + amount
        updated = existing
          |> put_elem(4, new_balance)  # bux_balance
          |> put_elem(11, now)         # updated_at
        :mnesia.dirty_write(updated)
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

  # =============================================================================
  # BUX Pool Functions (finite pool system)
  # =============================================================================

  @doc """
  Admin deposits BUX into a post's pool.
  Increases bux_balance (available to earn) and bux_deposited (lifetime total).

  IMPORTANT: This function delegates to PostBuxPoolWriter GenServer for serialized writes
  to prevent race conditions when multiple operations happen simultaneously.
  """
  def deposit_post_bux(post_id, amount) when is_integer(amount) and amount > 0 do
    BlocksterV2.PostBuxPoolWriter.deposit(post_id, amount)
  end

  @doc """
  Attempts to deduct BUX from post's pool. Returns amount that can be awarded.
  Does NOT mint - just checks availability and decrements pool.
  If pool has less than requested, returns whatever remains (partial).
  If pool is empty, returns 0.

  IMPORTANT: This function delegates to PostBuxPoolWriter GenServer for serialized writes
  to prevent race conditions when multiple users drain the pool simultaneously.

  Call this BEFORE minting. Only mint the returned amount.
  """
  def try_deduct_from_pool(post_id, requested_amount) when is_number(requested_amount) and requested_amount > 0 do
    BlocksterV2.PostBuxPoolWriter.try_deduct(post_id, requested_amount)
  end

  def try_deduct_from_pool(_post_id, _requested_amount), do: {:ok, 0, :invalid_amount}

  @doc """
  Gets pool statistics for a post.
  Returns {balance, deposited, distributed} tuple or {0, 0, 0} if no record exists.
  """
  def get_post_pool_stats(post_id) do
    case :mnesia.dirty_read({:post_bux_points, post_id}) do
      [] -> {0, 0, 0}
      [record] ->
        balance = elem(record, 4) || 0
        deposited = elem(record, 5) || 0
        distributed = elem(record, 6) || 0
        {balance, deposited, distributed}
    end
  rescue
    _ -> {0, 0, 0}
  catch
    :exit, _ -> {0, 0, 0}
  end

  @doc """
  Gets all post BUX balances from Mnesia.
  Returns a map of post_id => bux_balance for all posts with pool records.
  """
  def get_all_post_bux_balances() do
    :mnesia.dirty_match_object({:post_bux_points, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
    |> Enum.map(fn record ->
      post_id = elem(record, 1)
      balance = elem(record, 4) || 0
      {post_id, balance}
    end)
    |> Map.new()
  rescue
    _ -> %{}
  catch
    :exit, _ -> %{}
  end

  @doc """
  Gets all post total_distributed amounts from Mnesia.
  Returns a map of post_id => total_distributed for all posts with pool records.
  """
  def get_all_post_distributed_amounts() do
    :mnesia.dirty_match_object({:post_bux_points, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
    |> Enum.map(fn record ->
      post_id = elem(record, 1)
      distributed = elem(record, 6) || 0
      {post_id, distributed}
    end)
    |> Map.new()
  rescue
    _ -> %{}
  catch
    :exit, _ -> %{}
  end

  # =============================================================================
  # Per-Token Balance Functions (user_bux_balances table)
  # =============================================================================

  # Maps token names to their corresponding balance field index in the Mnesia record
  # Record structure: {:user_bux_balances, user_id, wallet, updated_at, aggregate, bux, moonbux, neobux, roguebux, flarebux, nftbux, nolchabux, solbux, spacebux, tronbux, tranbux}
  # NOTE: Hub tokens removed - only BUX is now actively used. Other indices kept for backward compatibility with existing Mnesia records.
  @token_field_indices %{
    "BUX" => 5
  }

  @doc """
  Updates a specific token balance for a user in the user_bux_balances table.
  NOTE: Hub tokens removed - only BUX and ROGUE are now actively used.
  ROGUE is stored in a separate table (user_rogue_balances).

  Table structure (0-indexed tuple positions):
  0: :user_bux_balances (table name)
  1: user_id
  2: user_smart_wallet
  3: updated_at
  4: aggregate_bux_balance (now equals BUX balance since hub tokens removed)
  5: bux_balance
  6-15: deprecated hub token fields (kept for backward compatibility)
  """
  def update_user_token_balance(user_id, wallet_address, token, balance, opts \\ []) do
    # Handle ROGUE separately (native token, stored in separate table)
    broadcast = Keyword.get(opts, :broadcast, true)

    if token == "ROGUE" do
      # ROGUE balance update - broadcast disabled here, caller handles it
      update_user_rogue_balance(user_id, wallet_address, balance, :rogue_chain)
    else
      now = System.system_time(:second)
      field_index = Map.get(@token_field_indices, token)

      if is_nil(field_index) do
        # Hub tokens removed - silently skip unknown tokens (only BUX supported now)
        Logger.debug("[EngagementTracker] Skipping unknown token '#{token}' (hub tokens removed)")
        {:error, :unknown_token}
      else
      # Parse balance to float for calculations
      balance_float = parse_balance(balance)

      case :mnesia.dirty_read({:user_bux_balances, user_id}) do
        [] ->
          # No existing record - create new with all zeros except the specified token
          record = create_new_balance_record(user_id, wallet_address, now, token, balance_float)
          :mnesia.dirty_write(record)
          # Broadcast if enabled (disabled during batch sync to avoid redundant updates)
          if broadcast do
            BlocksterV2Web.BuxBalanceHook.broadcast_balance_update(user_id, balance_float)
            BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update(user_id, %{"BUX" => balance_float})
          end
          {:ok, balance_float}

        [existing] ->
          # Update existing record
          updated = existing
            |> put_elem(2, wallet_address)           # user_smart_wallet
            |> put_elem(3, now)                      # updated_at
            |> put_elem(field_index, balance_float)  # specific token balance

          # Recalculate aggregate balance
          aggregate = calculate_aggregate_balance(updated)
          updated = put_elem(updated, 4, aggregate)

          :mnesia.dirty_write(updated)
          # Broadcast if enabled (disabled during batch sync to avoid redundant updates)
          if broadcast do
            BlocksterV2Web.BuxBalanceHook.broadcast_balance_update(user_id, aggregate)
            BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update(user_id, %{"BUX" => balance_float})
          end
          {:ok, balance_float}
      end
      end
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error updating user token balance: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit updating user token balance: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Optimistically deduct balance for a bet (before blockchain confirmation).
  Returns {:ok, new_balance} or {:error, reason}
  """
  def deduct_user_token_balance(user_id, wallet_address, token, amount) do
    case get_user_token_balances(user_id) do
      balances when is_map(balances) ->
        current_balance = Map.get(balances, token, 0.0)

        if current_balance >= amount do
          new_balance = current_balance - amount
          update_user_token_balance(user_id, wallet_address, token, new_balance)
          {:ok, new_balance}
        else
          {:error, "Insufficient #{token} balance"}
        end

      _ ->
        {:error, "Failed to get user balances"}
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error deducting token balance: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Refund balance when a bet fails (before blockchain confirmation).
  Returns {:ok, new_balance} or {:error, reason}
  """
  def credit_user_token_balance(user_id, wallet_address, token, amount) do
    case get_user_token_balances(user_id) do
      balances when is_map(balances) ->
        current_balance = Map.get(balances, token, 0.0)
        new_balance = current_balance + amount
        update_user_token_balance(user_id, wallet_address, token, new_balance)
        {:ok, new_balance}

      _ ->
        {:error, "Failed to get user balances"}
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error crediting token balance: #{inspect(e)}")
      {:error, e}
  end

  defp parse_balance(balance) when is_float(balance), do: balance
  defp parse_balance(balance) when is_integer(balance), do: balance * 1.0
  defp parse_balance(balance) when is_binary(balance) do
    case Float.parse(balance) do
      {val, _} -> val
      :error -> 0.0
    end
  end
  defp parse_balance(_), do: 0.0

  defp create_new_balance_record(user_id, wallet_address, now, token, balance) do
    # Create a record with all zeros, then set the specific token
    base_record = {
      :user_bux_balances,
      user_id,
      wallet_address,
      now,
      balance,   # aggregate starts as this token's balance
      0.0,       # blocksterbux_balance
      0.0,       # moonbux_balance
      0.0,       # neobux_balance
      0.0,       # roguebux_balance
      0.0,       # flarebux_balance
      0.0,       # nftbux_balance
      0.0,       # nolchabux_balance
      0.0,       # solbux_balance
      0.0,       # spacebux_balance
      0.0,       # tronbux_balance
      0.0        # tranbux_balance
    }

    # Set the specific token balance
    field_index = Map.get(@token_field_indices, token)
    put_elem(base_record, field_index, balance)
  end

  defp calculate_aggregate_balance(record) do
    # Sum all token balances (indices 5-15)
    Enum.reduce(5..15, 0.0, fn index, acc ->
      acc + (elem(record, index) || 0.0)
    end)
  end

  @doc """
  Updates ROGUE balance for a user (supports both Rogue Chain and Arbitrum).
  For now, only Rogue Chain is fetched by BuxMinter.
  Also updates the unified_multipliers table since ROGUE balance affects the ROGUE multiplier.
  """
  def update_user_rogue_balance(user_id, wallet_address, balance, chain \\ :rogue_chain) do
    now = System.system_time(:second)
    balance_float = parse_balance(balance)

    result = case :mnesia.dirty_read({:user_rogue_balances, user_id}) do
      [] ->
        # Create new record
        record = case chain do
          :rogue_chain ->
            {:user_rogue_balances, user_id, wallet_address, now, balance_float, 0.0}
          :arbitrum ->
            {:user_rogue_balances, user_id, wallet_address, now, 0.0, balance_float}
        end
        :mnesia.dirty_write(record)
        {:ok, balance_float}

      [existing] ->
        # Update existing record
        field_index = case chain do
          :rogue_chain -> 4  # rogue_balance_rogue_chain
          :arbitrum -> 5     # rogue_balance_arbitrum
        end

        updated = existing
          |> put_elem(2, wallet_address)       # user_smart_wallet
          |> put_elem(3, now)                   # updated_at
          |> put_elem(field_index, balance_float)

        :mnesia.dirty_write(updated)
        {:ok, balance_float}
    end

    # Update unified_multipliers table (V2 system) when ROGUE balance changes
    # Only update for rogue_chain since that's the smart wallet balance used for multiplier
    if chain == :rogue_chain do
      BlocksterV2.UnifiedMultiplier.update_rogue_multiplier(user_id)
    end

    # NOTE: Broadcast removed - caller (sync_user_balances) handles broadcasting once at the end
    # to avoid multiple redundant broadcasts during batch updates
    result
  rescue
    error ->
      Logger.error("[EngagementTracker] Error updating ROGUE balance: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Gets all token balances for a user from the user_bux_balances table.
  Returns a map with token names as keys and balances as values.
  Also includes ROGUE balances from user_rogue_balances table.
  NOTE: Hub tokens removed - only returns BUX and ROGUE.
  """
  def get_user_token_balances(user_id) do
    # Get BUX balance (hub tokens removed)
    bux_balance = case :mnesia.dirty_read({:user_bux_balances, user_id}) do
      [] ->
        Logger.info("[EngagementTracker] No user_bux_balances record for user #{user_id}")
        0.0

      [record] ->
        elem(record, 5) || 0.0
    end

    # Get ROGUE balance
    rogue_balance = case :mnesia.dirty_read({:user_rogue_balances, user_id}) do
      [] -> 0.0
      [rogue_record] -> elem(rogue_record, 4) || 0.0  # rogue_balance_rogue_chain
    end

    # Return only BUX and ROGUE (hub tokens removed)
    %{
      "BUX" => bux_balance,
      "ROGUE" => rogue_balance
    }
  rescue
    _ ->
      %{"BUX" => 0.0, "ROGUE" => 0.0}
  catch
    :exit, _ ->
      %{"BUX" => 0.0, "ROGUE" => 0.0}
  end

  @doc """
  Gets a specific token balance for a user.
  """
  def get_user_token_balance(user_id, token) do
    balances = get_user_token_balances(user_id)
    Map.get(balances, token, 0.0)
  end

  @doc """
  Debug function to dump a user's bux_balances record to the log.
  NOTE: Hub tokens removed - only shows BUX balance now.
  """
  def dump_user_bux_balances(user_id) do
    # Check if table exists first
    if :mnesia.system_info(:tables) |> Enum.member?(:user_bux_balances) do
      case :mnesia.dirty_read({:user_bux_balances, user_id}) do
        [] ->
          Logger.info("[DEBUG] No user_bux_balances record for user #{user_id}")
          nil
        [record] ->
          Logger.info("""
          [DEBUG] user_bux_balances for user #{user_id}:
            user_id:       #{elem(record, 1)}
            wallet:        #{elem(record, 2)}
            updated_at:    #{elem(record, 3)}
            BUX:           #{elem(record, 5)}
          """)
          record
      end
    else
      Logger.info("[DEBUG] user_bux_balances table not ready yet")
      nil
    end
  catch
    :exit, reason ->
      Logger.error("[DEBUG] Exit dumping user_bux_balances: #{inspect(reason)}")
      nil
  end

  # =============================================================================
  # Hub BUX Points Functions (hub_bux_points table)
  # =============================================================================

  @doc """
  Adds BUX earned to a hub's total in the hub_bux_points Mnesia table.
  Called after every successful mint to aggregate hub-level rewards.
  """
  def add_hub_bux_earned(nil, _amount), do: {:ok, 0}
  def add_hub_bux_earned(_hub_id, 0), do: {:ok, 0}
  def add_hub_bux_earned(hub_id, amount) do
    now = System.system_time(:second)

    result = case :mnesia.dirty_read({:hub_bux_points, hub_id}) do
      [] ->
        # No existing record - create new with this amount
        record = {
          :hub_bux_points,
          hub_id,
          amount,  # total_bux_rewarded
          nil,     # extra_field1
          nil,     # extra_field2
          nil,     # extra_field3
          nil,     # extra_field4
          now,     # created_at
          now      # updated_at
        }
        :mnesia.dirty_write(record)
        Logger.info("[EngagementTracker] Created hub_bux_points for hub #{hub_id}: total=#{amount}")
        {:ok, amount}

      [existing] ->
        # Add to existing total
        current_total = elem(existing, 2) || 0
        new_total = current_total + amount
        updated = existing
          |> put_elem(2, new_total)   # total_bux_rewarded
          |> put_elem(8, now)         # updated_at
        :mnesia.dirty_write(updated)
        Logger.info("[EngagementTracker] Updated hub_bux_points for hub #{hub_id}: total=#{new_total} (+#{amount})")
        {:ok, new_total}
    end

    # Broadcast the hub BUX balance update for real-time UI updates
    case result do
      {:ok, new_total} ->
        broadcast_hub_bux_update(hub_id, new_total)
        result
      _ ->
        result
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error adding hub bux earned: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit adding hub bux earned: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Broadcasts a hub BUX balance update for real-time UI updates.
  """
  def broadcast_hub_bux_update(hub_id, new_balance) do
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "hub_bux:#{hub_id}",
      {:hub_bux_update, hub_id, new_balance}
    )
    # Also broadcast to a global topic for index pages showing multiple hubs
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "hub_bux:all",
      {:hub_bux_update, hub_id, new_balance}
    )
  end

  @doc """
  Subscribe to BUX balance updates for a specific hub.
  """
  def subscribe_to_hub_bux(hub_id) do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "hub_bux:#{hub_id}")
  end

  @doc """
  Subscribe to all hub BUX balance updates (for index pages).
  """
  def subscribe_to_all_hub_bux_updates() do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "hub_bux:all")
  end

  @doc """
  Gets the total BUX rewarded for a specific hub.
  Returns 0 if no record exists.
  """
  def get_hub_bux_balance(nil), do: 0
  def get_hub_bux_balance(hub_id) do
    case :mnesia.dirty_read({:hub_bux_points, hub_id}) do
      [] -> 0
      [record] -> elem(record, 2) || 0
    end
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  @doc """
  Gets BUX totals for multiple hubs at once.
  Returns a map of hub_id => total_bux_rewarded.
  """
  def get_hub_bux_balances(hub_ids) when is_list(hub_ids) do
    hub_ids
    |> Enum.map(fn hub_id -> {hub_id, get_hub_bux_balance(hub_id)} end)
    |> Map.new()
  end

  @doc """
  Gets all hub BUX balances from Mnesia.
  Returns a map of hub_id => total_bux_rewarded.
  """
  def get_all_hub_bux_balances do
    case :mnesia.dirty_all_keys(:hub_bux_points) do
      keys when is_list(keys) ->
        keys
        |> Enum.map(fn hub_id ->
          case :mnesia.dirty_read({:hub_bux_points, hub_id}) do
            [record] -> {hub_id, elem(record, 2) || 0}
            [] -> {hub_id, 0}
          end
        end)
        |> Map.new()
      _ -> %{}
    end
  rescue
    _ -> %{}
  catch
    :exit, _ -> %{}
  end

  # =============================================================================
  # X OAuth State Functions (x_oauth_states table)
  # =============================================================================

  @oauth_state_ttl_seconds 15 * 60  # 15 minutes

  @doc """
  Creates a new OAuth state for X authentication flow.
  Returns {:ok, state_string} or {:error, reason}.

  Mnesia tuple structure:
  0: :x_oauth_states (table name)
  1: state (primary key - random string)
  2: user_id
  3: code_verifier
  4: redirect_path
  5: expires_at (Unix timestamp)
  6: inserted_at (Unix timestamp)
  """
  def create_x_oauth_state(user_id, code_verifier, redirect_path \\ "/profile") do
    state = generate_random_string(32)
    now = System.system_time(:second)
    expires_at = now + @oauth_state_ttl_seconds

    record = {
      :x_oauth_states,
      state,
      user_id,
      code_verifier,
      redirect_path,
      expires_at,
      now
    }

    :mnesia.dirty_write(record)
    Logger.info("[EngagementTracker] Created X OAuth state for user #{user_id}, expires in #{@oauth_state_ttl_seconds}s")
    {:ok, state}
  rescue
    e ->
      Logger.error("[EngagementTracker] Error creating X OAuth state: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit creating X OAuth state: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Gets a valid (non-expired) OAuth state by its state string.
  Returns the state record as a map or nil if not found/expired.
  """
  def get_valid_x_oauth_state(state) do
    now = System.system_time(:second)

    case :mnesia.dirty_read({:x_oauth_states, state}) do
      [] -> nil
      [record] ->
        expires_at = elem(record, 5)
        if expires_at > now do
          %{
            state: elem(record, 1),
            user_id: elem(record, 2),
            code_verifier: elem(record, 3),
            redirect_path: elem(record, 4),
            expires_at: expires_at,
            inserted_at: elem(record, 6)
          }
        else
          # Expired - clean it up
          :mnesia.dirty_delete({:x_oauth_states, state})
          nil
        end
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Consumes (deletes) an OAuth state after successful use.
  """
  def consume_x_oauth_state(state) when is_binary(state) do
    :mnesia.dirty_delete({:x_oauth_states, state})
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  def consume_x_oauth_state(%{state: state}), do: consume_x_oauth_state(state)

  @doc """
  Cleans up expired OAuth states.
  Returns the count of deleted states.
  """
  def cleanup_expired_x_oauth_states do
    now = System.system_time(:second)

    # Get all states and filter for expired ones
    case :mnesia.dirty_all_keys(:x_oauth_states) do
      keys when is_list(keys) ->
        expired_count = Enum.reduce(keys, 0, fn state, count ->
          case :mnesia.dirty_read({:x_oauth_states, state}) do
            [record] ->
              expires_at = elem(record, 5)
              if expires_at <= now do
                :mnesia.dirty_delete({:x_oauth_states, state})
                count + 1
              else
                count
              end
            [] -> count
          end
        end)

        if expired_count > 0 do
          Logger.info("[EngagementTracker] Cleaned up #{expired_count} expired X OAuth states")
        end
        expired_count

      _ -> 0
    end
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  # =============================================================================
  # X Connection Functions (x_connections table)
  # =============================================================================

  @doc """
  Creates or updates an X connection for a user.
  Implements account locking - once connected, user is locked to that X account.

  Returns {:ok, record_map} or {:error, :x_account_locked}.

  Mnesia tuple structure:
  0: :x_connections (table name)
  1: user_id (primary key)
  2: x_user_id
  3: x_username
  4: x_name
  5: x_profile_image_url
  6: access_token_encrypted
  7: refresh_token_encrypted
  8: token_expires_at
  9: scopes (list)
  10: connected_at
  11: x_score
  12: followers_count
  13: following_count
  14: tweet_count
  15: listed_count
  16: avg_engagement_rate
  17: original_tweets_analyzed
  18: account_created_at
  19: score_calculated_at
  20: updated_at
  """
  def upsert_x_connection(user_id, attrs) do
    now = System.system_time(:second)

    # Get attrs with defaults
    x_user_id = Map.get(attrs, :x_user_id)
    x_username = Map.get(attrs, :x_username)
    x_name = Map.get(attrs, :x_name)
    x_profile_image_url = Map.get(attrs, :x_profile_image_url)
    access_token = Map.get(attrs, :access_token)
    refresh_token = Map.get(attrs, :refresh_token)
    token_expires_at = datetime_to_unix(Map.get(attrs, :token_expires_at))
    scopes = Map.get(attrs, :scopes, [])
    connected_at = datetime_to_unix(Map.get(attrs, :connected_at)) || now

    # Encrypt tokens
    access_token_encrypted = encrypt_token(access_token)
    refresh_token_encrypted = encrypt_token(refresh_token)

    case :mnesia.dirty_read({:x_connections, user_id}) do
      [] ->
        # New connection - check if this X account is already connected to another user
        case get_x_connection_by_x_user_id(x_user_id) do
          nil ->
            # X account not connected anywhere else - create new record
            record = {
              :x_connections,
              user_id,
              x_user_id,
              x_username,
              x_name,
              x_profile_image_url,
              access_token_encrypted,
              refresh_token_encrypted,
              token_expires_at,
              scopes,
              connected_at,
              nil,   # x_score
              nil,   # followers_count
              nil,   # following_count
              nil,   # tweet_count
              nil,   # listed_count
              nil,   # avg_engagement_rate
              nil,   # original_tweets_analyzed
              nil,   # account_created_at
              nil,   # score_calculated_at
              now    # updated_at
            }
            :mnesia.dirty_write(record)
            Logger.info("[EngagementTracker] Created X connection for user #{user_id}: @#{x_username}")
            {:ok, x_connection_to_map(record)}

          existing ->
            # X account already connected to another user
            if existing.user_id == user_id do
              # Same user trying to reconnect - allow (shouldn't happen with new record check)
              record = {
                :x_connections, user_id, x_user_id, x_username, x_name, x_profile_image_url,
                access_token_encrypted, refresh_token_encrypted, token_expires_at, scopes,
                connected_at, nil, nil, nil, nil, nil, nil, nil, nil, nil, now
              }
              :mnesia.dirty_write(record)
              {:ok, x_connection_to_map(record)}
            else
              Logger.warning("[EngagementTracker] X account @#{x_username} already connected to user #{existing.user_id}")
              {:error, :x_account_locked}
            end
        end

      [existing_record] ->
        # Existing connection - check account locking
        existing_x_user_id = elem(existing_record, 2)

        if existing_x_user_id != nil and existing_x_user_id != x_user_id do
          # User is trying to connect a different X account - blocked!
          Logger.warning("[EngagementTracker] User #{user_id} locked to X account #{existing_x_user_id}, cannot connect #{x_user_id}")
          {:error, :x_account_locked}
        else
          # Same X account or first connection - update
          # Preserve existing score data
          record = {
            :x_connections,
            user_id,
            x_user_id,
            x_username,
            x_name,
            x_profile_image_url,
            access_token_encrypted,
            refresh_token_encrypted,
            token_expires_at,
            scopes,
            elem(existing_record, 10) || connected_at,  # preserve original connected_at
            elem(existing_record, 11),   # x_score
            elem(existing_record, 12),   # followers_count
            elem(existing_record, 13),   # following_count
            elem(existing_record, 14),   # tweet_count
            elem(existing_record, 15),   # listed_count
            elem(existing_record, 16),   # avg_engagement_rate
            elem(existing_record, 17),   # original_tweets_analyzed
            elem(existing_record, 18),   # account_created_at
            elem(existing_record, 19),   # score_calculated_at
            now
          }
          :mnesia.dirty_write(record)
          Logger.info("[EngagementTracker] Updated X connection for user #{user_id}: @#{x_username}")
          {:ok, x_connection_to_map(record)}
        end
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error upserting X connection: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit upserting X connection: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Gets X connection for a user by user_id.
  Returns map with decrypted tokens or nil.
  """
  def get_x_connection_by_user(user_id) do
    case :mnesia.dirty_read({:x_connections, user_id}) do
      [] -> nil
      [record] -> x_connection_to_map(record)
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Gets X connection by X user ID (for checking if account already connected).
  Returns map or nil.
  """
  def get_x_connection_by_x_user_id(nil), do: nil
  def get_x_connection_by_x_user_id(x_user_id) do
    # Use index lookup
    pattern = {:x_connections, :_, x_user_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

    case :mnesia.dirty_match_object(pattern) do
      [] -> nil
      [record | _] -> x_connection_to_map(record)
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Updates X connection with new token data.
  Used for token refresh.
  """
  def update_x_connection_tokens(user_id, access_token, refresh_token, expires_at) do
    now = System.system_time(:second)

    case :mnesia.dirty_read({:x_connections, user_id}) do
      [] ->
        {:error, :not_found}

      [existing] ->
        updated = existing
          |> put_elem(6, encrypt_token(access_token))
          |> put_elem(7, encrypt_token(refresh_token))
          |> put_elem(8, datetime_to_unix(expires_at))
          |> put_elem(20, now)
        :mnesia.dirty_write(updated)
        {:ok, x_connection_to_map(updated)}
    end
  rescue
    e -> {:error, e}
  catch
    :exit, e -> {:error, e}
  end

  @doc """
  Updates X score fields for a connection.
  """
  def update_x_connection_score(user_id, score_attrs) do
    now = System.system_time(:second)

    case :mnesia.dirty_read({:x_connections, user_id}) do
      [] ->
        {:error, :not_found}

      [existing] ->
        updated = existing
          |> put_elem(11, Map.get(score_attrs, :x_score, elem(existing, 11)))
          |> put_elem(12, Map.get(score_attrs, :followers_count, elem(existing, 12)))
          |> put_elem(13, Map.get(score_attrs, :following_count, elem(existing, 13)))
          |> put_elem(14, Map.get(score_attrs, :tweet_count, elem(existing, 14)))
          |> put_elem(15, Map.get(score_attrs, :listed_count, elem(existing, 15)))
          |> put_elem(16, Map.get(score_attrs, :avg_engagement_rate, elem(existing, 16)))
          |> put_elem(17, Map.get(score_attrs, :original_tweets_analyzed, elem(existing, 17)))
          |> put_elem(18, datetime_to_unix(Map.get(score_attrs, :account_created_at)) || elem(existing, 18))
          |> put_elem(19, now)  # score_calculated_at
          |> put_elem(20, now)  # updated_at
        :mnesia.dirty_write(updated)
        Logger.info("[EngagementTracker] Updated X score for user #{user_id}: score=#{Map.get(score_attrs, :x_score)}")
        {:ok, x_connection_to_map(updated)}
    end
  rescue
    e -> {:error, e}
  catch
    :exit, e -> {:error, e}
  end

  @doc """
  Deletes X connection for a user (disconnect).
  """
  def delete_x_connection(user_id) do
    :mnesia.dirty_delete({:x_connections, user_id})
    Logger.info("[EngagementTracker] Deleted X connection for user #{user_id}")
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  # Convert X connection record to map with decrypted tokens
  defp x_connection_to_map(record) do
    %{
      user_id: elem(record, 1),
      x_user_id: elem(record, 2),
      x_username: elem(record, 3),
      x_name: elem(record, 4),
      x_profile_image_url: elem(record, 5),
      access_token: decrypt_token(elem(record, 6)),
      refresh_token: decrypt_token(elem(record, 7)),
      token_expires_at: unix_to_datetime(elem(record, 8)),
      scopes: elem(record, 9) || [],
      connected_at: unix_to_datetime(elem(record, 10)),
      x_score: elem(record, 11),
      followers_count: elem(record, 12),
      following_count: elem(record, 13),
      tweet_count: elem(record, 14),
      listed_count: elem(record, 15),
      avg_engagement_rate: elem(record, 16),
      original_tweets_analyzed: elem(record, 17),
      account_created_at: unix_to_datetime(elem(record, 18)),
      score_calculated_at: unix_to_datetime(elem(record, 19)),
      updated_at: unix_to_datetime(elem(record, 20))
    }
  end

  # =============================================================================
  # Share Campaign Functions (share_campaigns table)
  # =============================================================================

  @doc """
  Creates a new share campaign for a post.
  Returns {:ok, campaign_map} or {:error, reason}.

  Mnesia tuple structure:
  0: :share_campaigns (table name)
  1: post_id (primary key)
  2: tweet_id
  3: tweet_url
  4: tweet_text
  5: bux_reward
  6: is_active
  7: starts_at
  8: ends_at
  9: max_participants
  10: total_shares
  11: inserted_at
  12: updated_at
  """
  def create_share_campaign(post_id, attrs) do
    now = System.system_time(:second)

    record = {
      :share_campaigns,
      post_id,
      Map.get(attrs, :tweet_id),
      Map.get(attrs, :tweet_url),
      Map.get(attrs, :tweet_text),
      Map.get(attrs, :bux_reward, 50),
      Map.get(attrs, :is_active, true),
      datetime_to_unix(Map.get(attrs, :starts_at)),
      datetime_to_unix(Map.get(attrs, :ends_at)),
      Map.get(attrs, :max_participants),
      0,    # total_shares starts at 0
      now,
      now
    }

    :mnesia.dirty_write(record)
    Logger.info("[EngagementTracker] Created share campaign for post #{post_id}: #{Map.get(attrs, :bux_reward, 50)} BUX")
    {:ok, share_campaign_to_map(record)}
  rescue
    e ->
      Logger.error("[EngagementTracker] Error creating share campaign: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit creating share campaign: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Gets share campaign by post_id.
  """
  def get_share_campaign(post_id) do
    case :mnesia.dirty_read({:share_campaigns, post_id}) do
      [] -> nil
      [record] -> share_campaign_to_map(record)
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Gets share campaign by tweet_id.
  """
  def get_share_campaign_by_tweet(nil), do: nil
  def get_share_campaign_by_tweet(tweet_id) do
    pattern = {:share_campaigns, :_, tweet_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

    case :mnesia.dirty_match_object(pattern) do
      [] -> nil
      [record | _] -> share_campaign_to_map(record)
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Lists all active share campaigns.
  """
  def list_active_share_campaigns do
    now = System.system_time(:second)

    case :mnesia.dirty_all_keys(:share_campaigns) do
      keys when is_list(keys) ->
        keys
        |> Enum.map(fn post_id ->
          case :mnesia.dirty_read({:share_campaigns, post_id}) do
            [record] -> record
            [] -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(fn record -> campaign_active?(record, now) end)
        |> Enum.map(&share_campaign_to_map/1)

      _ -> []
    end
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Updates a share campaign.
  """
  def update_share_campaign(post_id, attrs) do
    now = System.system_time(:second)

    case :mnesia.dirty_read({:share_campaigns, post_id}) do
      [] ->
        {:error, :not_found}

      [existing] ->
        updated = existing
          |> put_elem(2, Map.get(attrs, :tweet_id, elem(existing, 2)))
          |> put_elem(3, Map.get(attrs, :tweet_url, elem(existing, 3)))
          |> put_elem(4, Map.get(attrs, :tweet_text, elem(existing, 4)))
          |> put_elem(5, Map.get(attrs, :bux_reward, elem(existing, 5)))
          |> put_elem(6, Map.get(attrs, :is_active, elem(existing, 6)))
          |> put_elem(7, datetime_to_unix(Map.get(attrs, :starts_at)) || elem(existing, 7))
          |> put_elem(8, datetime_to_unix(Map.get(attrs, :ends_at)) || elem(existing, 8))
          |> put_elem(9, Map.get(attrs, :max_participants, elem(existing, 9)))
          |> put_elem(12, now)
        :mnesia.dirty_write(updated)
        {:ok, share_campaign_to_map(updated)}
    end
  rescue
    e -> {:error, e}
  catch
    :exit, e -> {:error, e}
  end

  @doc """
  Increments the total_shares count for a campaign.
  Returns {:ok, new_count}.
  """
  def increment_campaign_shares(post_id) do
    case :mnesia.dirty_read({:share_campaigns, post_id}) do
      [] ->
        {:error, :not_found}

      [existing] ->
        current = elem(existing, 10) || 0
        new_count = current + 1
        now = System.system_time(:second)
        updated = existing
          |> put_elem(10, new_count)
          |> put_elem(12, now)
        :mnesia.dirty_write(updated)
        {:ok, new_count}
    end
  rescue
    e -> {:error, e}
  catch
    :exit, e -> {:error, e}
  end

  # Check if campaign is active
  defp campaign_active?(record, now) do
    is_active = elem(record, 6)
    starts_at = elem(record, 7)
    ends_at = elem(record, 8)
    max_participants = elem(record, 9)
    total_shares = elem(record, 10)

    is_active == true and
      (is_nil(starts_at) or starts_at <= now) and
      (is_nil(ends_at) or ends_at > now) and
      (is_nil(max_participants) or total_shares < max_participants)
  end

  # Convert campaign record to map
  defp share_campaign_to_map(record) do
    %{
      post_id: elem(record, 1),
      tweet_id: elem(record, 2),
      tweet_url: elem(record, 3),
      tweet_text: elem(record, 4),
      bux_reward: elem(record, 5),
      is_active: elem(record, 6),
      starts_at: unix_to_datetime(elem(record, 7)),
      ends_at: unix_to_datetime(elem(record, 8)),
      max_participants: elem(record, 9),
      total_shares: elem(record, 10) || 0,
      inserted_at: unix_to_datetime(elem(record, 11)),
      updated_at: unix_to_datetime(elem(record, 12))
    }
  end

  # =============================================================================
  # Share Reward Functions (share_rewards table) - Enhanced from existing
  # =============================================================================

  @doc """
  Creates a pending share reward record.
  Returns {:ok, map} or {:error, :already_exists}.

  Uses existing share_rewards table which has:
  0: :share_rewards (table name)
  1: key ({user_id, campaign_id})
  2: id (PostgreSQL id - deprecated for Mnesia-only)
  3: user_id
  4: campaign_id
  5: x_connection_id
  6: retweet_id
  7: status
  8: bux_rewarded
  9: verified_at
  10: rewarded_at
  11: failure_reason
  12: tx_hash
  13: created_at
  14: updated_at
  """
  def create_pending_share_reward(user_id, campaign_id, x_connection_id \\ nil) do
    key = {user_id, campaign_id}
    now = System.system_time(:second)

    case :mnesia.dirty_read({:share_rewards, key}) do
      [_existing] ->
        {:error, :already_exists}

      [] ->
        record = {
          :share_rewards,
          key,
          nil,              # id (not needed for Mnesia-only)
          user_id,
          campaign_id,
          x_connection_id,
          nil,              # retweet_id
          "pending",        # status
          nil,              # bux_rewarded
          nil,              # verified_at
          nil,              # rewarded_at
          nil,              # failure_reason
          nil,              # tx_hash
          now,              # created_at
          now               # updated_at
        }
        :mnesia.dirty_write(record)
        Logger.info("[EngagementTracker] Created pending share reward for user #{user_id}, campaign #{campaign_id}")
        {:ok, share_reward_to_map(record)}
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error creating pending share reward: #{inspect(e)}")
      {:error, e}
  catch
    :exit, e ->
      Logger.error("[EngagementTracker] Exit creating pending share reward: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Marks a share reward as verified with the retweet ID.
  """
  def verify_share_reward(user_id, campaign_id, retweet_id) do
    key = {user_id, campaign_id}
    now = System.system_time(:second)

    case :mnesia.dirty_read({:share_rewards, key}) do
      [] ->
        {:error, :not_found}

      [existing] ->
        updated = existing
          |> put_elem(6, retweet_id)    # retweet_id
          |> put_elem(7, "verified")    # status
          |> put_elem(9, now)           # verified_at
          |> put_elem(14, now)          # updated_at
        :mnesia.dirty_write(updated)
        Logger.info("[EngagementTracker] Verified share reward for user #{user_id}, campaign #{campaign_id}")
        {:ok, share_reward_to_map(updated)}
    end
  rescue
    e -> {:error, e}
  catch
    :exit, e -> {:error, e}
  end

  @doc """
  Marks a share reward as rewarded with BUX amount and tx hash.
  """
  def mark_share_reward_paid(user_id, campaign_id, bux_amount, tx_hash) do
    key = {user_id, campaign_id}
    now = System.system_time(:second)

    case :mnesia.dirty_read({:share_rewards, key}) do
      [] ->
        {:error, :not_found}

      [existing] ->
        updated = existing
          |> put_elem(7, "rewarded")    # status
          |> put_elem(8, bux_amount)    # bux_rewarded
          |> put_elem(10, now)          # rewarded_at
          |> put_elem(12, tx_hash)      # tx_hash
          |> put_elem(14, now)          # updated_at
        :mnesia.dirty_write(updated)
        Logger.info("[EngagementTracker] Marked share reward paid for user #{user_id}, campaign #{campaign_id}: #{bux_amount} BUX")
        {:ok, share_reward_to_map(updated)}
    end
  rescue
    e -> {:error, e}
  catch
    :exit, e -> {:error, e}
  end

  @doc """
  Marks a share reward as failed with reason.
  """
  def mark_share_reward_failed(user_id, campaign_id, reason) do
    key = {user_id, campaign_id}
    now = System.system_time(:second)

    case :mnesia.dirty_read({:share_rewards, key}) do
      [] ->
        {:error, :not_found}

      [existing] ->
        updated = existing
          |> put_elem(7, "failed")      # status
          |> put_elem(11, reason)       # failure_reason
          |> put_elem(14, now)          # updated_at
        :mnesia.dirty_write(updated)
        Logger.info("[EngagementTracker] Marked share reward failed for user #{user_id}, campaign #{campaign_id}: #{reason}")
        {:ok, share_reward_to_map(updated)}
    end
  rescue
    e -> {:error, e}
  catch
    :exit, e -> {:error, e}
  end

  @doc """
  Gets a share reward by user_id and campaign_id.
  """
  def get_share_reward(user_id, campaign_id) do
    key = {user_id, campaign_id}

    case :mnesia.dirty_read({:share_rewards, key}) do
      [] -> nil
      [record] -> share_reward_to_map(record)
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Gets all pending share rewards created before a given timestamp.
  Used for background verification job.
  """
  def get_pending_share_rewards_before(before_timestamp) do
    before_unix = datetime_to_unix(before_timestamp)
    pattern = {:share_rewards, :_, :_, :_, :_, :_, :_, "pending", :_, :_, :_, :_, :_, :_, :_}

    :mnesia.dirty_match_object(pattern)
    |> Enum.filter(fn record -> elem(record, 13) < before_unix end)
    |> Enum.map(&share_reward_to_map/1)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Gets all share rewards for a user.
  """
  def get_user_share_rewards(user_id) do
    pattern = {:share_rewards, :_, :_, user_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

    :mnesia.dirty_match_object(pattern)
    |> Enum.map(&share_reward_to_map/1)
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Deletes a share reward by user_id and campaign_id.
  """
  def delete_share_reward(user_id, campaign_id) do
    key = {user_id, campaign_id}
    :mnesia.dirty_delete({:share_rewards, key})
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  # Convert share reward record to map
  defp share_reward_to_map(record) do
    %{
      user_id: elem(record, 3),
      campaign_id: elem(record, 4),
      x_connection_id: elem(record, 5),
      retweet_id: elem(record, 6),
      status: elem(record, 7),
      bux_rewarded: elem(record, 8),
      verified_at: unix_to_datetime(elem(record, 9)),
      rewarded_at: unix_to_datetime(elem(record, 10)),
      failure_reason: elem(record, 11),
      tx_hash: elem(record, 12),
      created_at: unix_to_datetime(elem(record, 13)),
      updated_at: unix_to_datetime(elem(record, 14))
    }
  end

  # =============================================================================
  # Token Encryption/Decryption Helpers
  # =============================================================================

  defp encrypt_token(nil), do: nil
  defp encrypt_token(token) when is_binary(token) do
    BlocksterV2.Encryption.encrypt(token)
  end

  defp decrypt_token(nil), do: nil
  defp decrypt_token(encrypted) when is_binary(encrypted) do
    BlocksterV2.Encryption.decrypt(encrypted)
  end

  # =============================================================================
  # DateTime/Unix Conversion Helpers
  # =============================================================================

  defp datetime_to_unix(nil), do: nil
  defp datetime_to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp datetime_to_unix(unix) when is_integer(unix), do: unix

  defp unix_to_datetime(nil), do: nil
  defp unix_to_datetime(unix) when is_integer(unix) do
    case DateTime.from_unix(unix) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp generate_random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, length)
  end

  # =============================================================================
  # VIDEO ENGAGEMENT FUNCTIONS (HIGH WATER MARK SYSTEM)
  # =============================================================================

  @doc """
  Records that a user started watching a video.
  Creates initial engagement record if not exists, or increments session count.
  """
  def record_video_view(user_id, post_id, video_duration \\ 0) do
    now = System.system_time(:second)
    key = {user_id, post_id}

    case :mnesia.dirty_read({:user_video_engagement, key}) do
      [] ->
        # Create new engagement record with high water mark at 0
        record = {
          :user_video_engagement,
          key,                    # 1: key
          user_id,                # 2: user_id
          post_id,                # 3: post_id
          0.0,                    # 4: high_water_mark (seconds)
          0.0,                    # 5: total_earnable_time
          video_duration,         # 6: video_duration
          0,                      # 7: completion_percentage
          0.0,                    # 8: total_bux_earned
          0.0,                    # 9: last_session_bux
          0,                      # 10: total_pause_count
          0,                      # 11: total_tab_away_count
          1,                      # 12: session_count
          now,                    # 13: last_watched_at
          now,                    # 14: created_at
          now,                    # 15: updated_at
          []                      # 16: video_tx_ids - list of %{tx_hash, bux_amount, timestamp}
        }
        :mnesia.dirty_write(record)

        # Update post stats
        increment_video_views(post_id)

        {:ok, :created}

      [existing] ->
        # Increment session count and update last_watched_at
        updated = existing
        |> put_elem(12, elem(existing, 12) + 1)  # session_count
        |> put_elem(13, now)                      # last_watched_at
        |> put_elem(15, now)                      # updated_at

        :mnesia.dirty_write(updated)
        {:ok, :updated}
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error recording video view: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Gets video engagement for a user/post.
  Returns the high water mark and total BUX earned.
  """
  def get_video_engagement(user_id, post_id) do
    key = {user_id, post_id}

    case :mnesia.dirty_read({:user_video_engagement, key}) do
      [] ->
        {:error, :not_found}

      [record] ->
        # Handle old records that may not have the video_tx_ids field (16 vs 17 elements)
        video_tx_ids = if tuple_size(record) >= 17, do: elem(record, 16), else: []

        {:ok, %{
          high_water_mark: elem(record, 4),
          total_earnable_time: elem(record, 5),
          video_duration: elem(record, 6),
          completion_percentage: elem(record, 7),
          total_bux_earned: elem(record, 8),
          last_session_bux: elem(record, 9),
          total_pause_count: elem(record, 10),
          total_tab_away_count: elem(record, 11),
          session_count: elem(record, 12),
          last_watched_at: elem(record, 13),
          video_tx_ids: video_tx_ids || []
        }}
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error getting video engagement: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Updates video engagement after a session completes.
  Updates high water mark and accumulates BUX earned.
  """
  def update_video_engagement_session(user_id, post_id, session_data) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    new_hwm = Map.get(session_data, :new_high_water_mark, 0)
    session_bux = Map.get(session_data, :session_bux, 0)
    pause_count = Map.get(session_data, :pause_count, 0)
    tab_away_count = Map.get(session_data, :tab_away_count, 0)
    session_earnable_time = Map.get(session_data, :session_earnable_time, 0)
    tx_hash = Map.get(session_data, :tx_hash)

    case :mnesia.dirty_read({:user_video_engagement, key}) do
      [] ->
        {:error, :not_found}

      [record] ->
        old_hwm = elem(record, 4)
        video_duration = elem(record, 6)

        # Only update high water mark if new position is higher
        updated_hwm = max(old_hwm, new_hwm)

        # Calculate new completion percentage
        completion = if video_duration > 0 do
          trunc((updated_hwm / video_duration) * 100) |> min(100)
        else
          0
        end

        # Accumulate totals
        new_total_earnable_time = elem(record, 5) + session_earnable_time
        new_total_bux = elem(record, 8) + session_bux
        new_total_pauses = elem(record, 10) + pause_count
        new_total_tab_away = elem(record, 11) + tab_away_count

        # Get existing tx_ids list (handle old records without this field)
        existing_tx_ids = if tuple_size(record) >= 17, do: elem(record, 16) || [], else: []

        # Append new tx if BUX was earned and tx_hash provided
        updated_tx_ids = if session_bux > 0 and tx_hash do
          existing_tx_ids ++ [%{tx_hash: tx_hash, bux_amount: session_bux, timestamp: now}]
        else
          existing_tx_ids
        end

        # Ensure record has all 17 fields (handle migration from 16-field records)
        base_record = if tuple_size(record) < 17 do
          Tuple.append(record, [])  # Add empty tx_ids field
        else
          record
        end

        updated_record = base_record
        |> put_elem(4, updated_hwm)              # high_water_mark
        |> put_elem(5, new_total_earnable_time)  # total_earnable_time
        |> put_elem(7, completion)               # completion_percentage
        |> put_elem(8, new_total_bux)            # total_bux_earned
        |> put_elem(9, session_bux)              # last_session_bux
        |> put_elem(10, new_total_pauses)        # total_pause_count
        |> put_elem(11, new_total_tab_away)      # total_tab_away_count
        |> put_elem(13, now)                     # last_watched_at
        |> put_elem(15, now)                     # updated_at
        |> put_elem(16, updated_tx_ids)          # video_tx_ids

        :mnesia.dirty_write(updated_record)

        # Update post stats if BUX was earned
        if session_bux > 0 do
          update_video_stats(post_id, %{
            bux_distributed_delta: session_bux,
            watch_time_delta: session_earnable_time,
            completion: completion >= 90
          })
        end

        {:ok, %{
          high_water_mark: updated_hwm,
          total_bux_earned: new_total_bux,
          completion_percentage: completion,
          video_tx_ids: updated_tx_ids
        }}
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error updating video session: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Simple high water mark update (no BUX earned, just position tracking).
  """
  def update_video_high_water_mark(user_id, post_id, new_position) do
    key = {user_id, post_id}
    now = System.system_time(:second)

    case :mnesia.dirty_read({:user_video_engagement, key}) do
      [] ->
        {:error, :not_found}

      [record] ->
        old_hwm = elem(record, 4)

        if new_position > old_hwm do
          video_duration = elem(record, 6)
          completion = if video_duration > 0 do
            trunc((new_position / video_duration) * 100) |> min(100)
          else
            0
          end

          updated = record
          |> put_elem(4, new_position)   # high_water_mark
          |> put_elem(7, completion)     # completion_percentage
          |> put_elem(13, now)           # last_watched_at
          |> put_elem(15, now)           # updated_at

          :mnesia.dirty_write(updated)
          {:ok, new_position}
        else
          {:ok, old_hwm}  # No change needed
        end
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error updating video high water mark: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Increments video view count for a post.
  """
  defp increment_video_views(post_id) do
    now = System.system_time(:second)

    case :mnesia.dirty_read({:post_video_stats, post_id}) do
      [] ->
        record = {:post_video_stats, post_id, 1, 0, 0, 0.0, now}
        :mnesia.dirty_write(record)

      [record] ->
        updated = record
        |> put_elem(2, elem(record, 2) + 1)  # total_views
        |> put_elem(6, now)                   # updated_at
        :mnesia.dirty_write(updated)
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error incrementing video views: #{inspect(e)}")
  end

  @doc """
  Updates aggregate video stats for a post.
  """
  defp update_video_stats(post_id, updates) do
    now = System.system_time(:second)

    case :mnesia.dirty_read({:post_video_stats, post_id}) do
      [] ->
        # Create if not exists
        record = {
          :post_video_stats,
          post_id,
          0,                                              # total_views
          Map.get(updates, :watch_time_delta, 0),        # total_watch_time
          if(Map.get(updates, :completion), do: 1, else: 0), # completions
          Map.get(updates, :bux_distributed_delta, 0.0), # bux_distributed
          now
        }
        :mnesia.dirty_write(record)

      [record] ->
        updated = record
        |> put_elem(3, elem(record, 3) + Map.get(updates, :watch_time_delta, 0))
        |> put_elem(4, elem(record, 4) + if(Map.get(updates, :completion), do: 1, else: 0))
        |> put_elem(5, elem(record, 5) + Map.get(updates, :bux_distributed_delta, 0.0))
        |> put_elem(6, now)

        :mnesia.dirty_write(updated)
    end
  rescue
    e ->
      Logger.error("[EngagementTracker] Error updating video stats: #{inspect(e)}")
  end
end
