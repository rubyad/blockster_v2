defmodule BlocksterV2.Social do
  @moduledoc """
  The Social context handles X (Twitter) integration for share campaigns.

  All data is stored in Mnesia via EngagementTracker functions.
  PostgreSQL is no longer used for X OAuth, connections, campaigns, or rewards.
  """

  require Logger
  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.Social.XApiClient
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Repo

  # =============================================================================
  # X OAuth State Management
  # =============================================================================

  @doc """
  Creates a new OAuth state for starting the X OAuth flow.
  Returns {:ok, state_string} or {:error, reason}.
  """
  def create_oauth_state(user_id, code_verifier, redirect_path \\ "/profile") do
    EngagementTracker.create_x_oauth_state(user_id, code_verifier, redirect_path)
  end

  @doc """
  Retrieves and validates an OAuth state by state string.
  Returns the state map or nil if not found or expired.
  """
  def get_valid_oauth_state(state) do
    EngagementTracker.get_valid_x_oauth_state(state)
  end

  @doc """
  Consumes an OAuth state (deletes it after use).
  """
  def consume_oauth_state(state) when is_binary(state) do
    EngagementTracker.consume_x_oauth_state(state)
  end
  def consume_oauth_state(%{state: state}), do: consume_oauth_state(state)
  def consume_oauth_state(_), do: :ok

  @doc """
  Cleans up expired OAuth states (for periodic cleanup job).
  """
  def cleanup_expired_oauth_states do
    EngagementTracker.cleanup_expired_x_oauth_states()
  end

  # =============================================================================
  # X Connection Management
  # =============================================================================

  @doc """
  Gets a user's X connection.
  Returns a map with connection data or nil.
  """
  def get_x_connection_for_user(user_id) do
    EngagementTracker.get_x_connection_by_user(user_id)
  end

  @doc """
  Gets an X connection by X user ID.
  """
  def get_x_connection_by_x_user_id(x_user_id) do
    EngagementTracker.get_x_connection_by_x_user_id(x_user_id)
  end

  @doc """
  Creates or updates an X connection for a user.
  If the user already has a connection, it updates the tokens.

  Users are locked to the first X account they connect. If they try to connect
  a different X account, returns {:error, :x_account_locked}.

  Also updates the user's locked_x_user_id in PostgreSQL for the first connection.
  """
  def upsert_x_connection(user_id, attrs) do
    x_user_id = Map.get(attrs, :x_user_id) || Map.get(attrs, "x_user_id")

    # Check if user is already locked to a different X account in PostgreSQL
    user = Repo.get!(User, user_id)

    case check_x_account_lock(user, x_user_id) do
      {:ok, :first_connection} ->
        # First X connection - lock the user to this X account in PostgreSQL
        with {:ok, _user} <- lock_user_to_x_account(user, x_user_id),
             {:ok, connection} <- EngagementTracker.upsert_x_connection(user_id, attrs) do
          {:ok, connection}
        end

      {:ok, :same_account} ->
        # Reconnecting same X account - allow
        EngagementTracker.upsert_x_connection(user_id, attrs)

      {:error, :x_account_locked} = error ->
        # Trying to connect a different X account
        error
    end
  end

  defp check_x_account_lock(%User{locked_x_user_id: nil}, _x_user_id) do
    {:ok, :first_connection}
  end

  defp check_x_account_lock(%User{locked_x_user_id: locked_id}, x_user_id)
       when locked_id == x_user_id do
    {:ok, :same_account}
  end

  defp check_x_account_lock(%User{locked_x_user_id: _locked_id}, _x_user_id) do
    {:error, :x_account_locked}
  end

  defp lock_user_to_x_account(user, x_user_id) do
    result = user
    |> Ecto.Changeset.change(%{locked_x_user_id: x_user_id})
    |> Ecto.Changeset.unique_constraint(:locked_x_user_id, name: :users_locked_x_user_id_index)
    |> Repo.update()

    case result do
      {:ok, user} -> {:ok, user}
      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :locked_x_user_id) do
          # Find the user who has this X account linked
          existing_user = Repo.get_by(User, locked_x_user_id: x_user_id)
          existing_email = if existing_user, do: mask_email(existing_user.email), else: nil
          {:error, {:x_account_already_linked, existing_email}}
        else
          result
        end
    end
  end

  # Mask email for privacy: "john.doe@example.com" -> "j***e@example.com"
  defp mask_email(nil), do: nil
  defp mask_email(email) do
    case String.split(email, "@") do
      [local, domain] when byte_size(local) > 2 ->
        first = String.first(local)
        last = String.last(local)
        "#{first}***#{last}@#{domain}"
      _ ->
        "***@***"
    end
  end

  @doc """
  Disconnects a user's X account.
  """
  def disconnect_x_account(user_id) do
    EngagementTracker.delete_x_connection(user_id)
  end

  @doc """
  Refreshes an X connection's access token if it's expired or about to expire.
  """
  def maybe_refresh_token(connection) when is_map(connection) do
    needs_refresh = token_needs_refresh?(connection)
    Logger.info("[X Auth] Token refresh check: needs_refresh=#{needs_refresh}, expires_at=#{inspect(connection[:token_expires_at])}, now=#{inspect(DateTime.utc_now())}")

    if needs_refresh do
      Logger.info("[X Auth] Attempting token refresh for user #{connection[:user_id]}")
      refresh_x_token(connection)
    else
      {:ok, connection}
    end
  end

  # X access tokens expire after 2 hours. Refresh if token expires within 1 hour
  # to be safe, since we can't validate tokens without an API call.
  @token_refresh_buffer_minutes 60

  defp token_needs_refresh?(%{token_expires_at: nil}), do: false
  defp token_needs_refresh?(%{token_expires_at: expires_at}) when is_struct(expires_at, DateTime) do
    buffer_time = DateTime.utc_now() |> DateTime.add(@token_refresh_buffer_minutes, :minute)
    DateTime.compare(expires_at, buffer_time) == :lt
  end
  defp token_needs_refresh?(_), do: false

  defp refresh_x_token(connection) do
    refresh_token = Map.get(connection, :refresh_token)

    if is_nil(refresh_token) do
      Logger.error("[X Auth] No refresh token available for user #{connection[:user_id]}")
      {:error, "No refresh token available"}
    else
      Logger.info("[X Auth] Calling X API to refresh token for user #{connection[:user_id]}")
      case XApiClient.refresh_token(refresh_token) do
        {:ok, token_data} ->
          Logger.info("[X Auth] Token refresh successful, new token expires in #{token_data.expires_in}s")
          expires_at =
            if token_data.expires_in do
              DateTime.utc_now()
              |> DateTime.add(token_data.expires_in, :second)
              |> DateTime.truncate(:second)
            end

          case EngagementTracker.update_x_connection_tokens(
            connection.user_id,
            token_data.access_token,
            token_data.refresh_token,
            expires_at
          ) do
            {:ok, updated_connection} ->
              Logger.info("[X Auth] Updated tokens in Mnesia for user #{connection[:user_id]}")
              {:ok, updated_connection}

            {:error, reason} ->
              Logger.error("[X Auth] Failed to save refreshed token: #{inspect(reason)}")
              {:error, "Failed to save refreshed token: #{inspect(reason)}"}
          end

        {:error, reason} ->
          Logger.error("[X Auth] Token refresh failed for user #{connection[:user_id]}: #{reason}")
          {:error, "Token refresh failed: #{reason}"}
      end
    end
  end

  @doc """
  Updates an X connection's score data.
  """
  def update_x_connection_score(user_id, score_attrs) do
    EngagementTracker.update_x_connection_score(user_id, score_attrs)
  end

  # =============================================================================
  # Share Campaign Management
  # =============================================================================

  @doc """
  Gets a share campaign by post ID.
  """
  def get_share_campaign(post_id) do
    EngagementTracker.get_share_campaign(post_id)
  end

  @doc """
  Gets a share campaign by post ID (alias for get_share_campaign).
  """
  def get_campaign_for_post(post_id) do
    EngagementTracker.get_share_campaign(post_id)
  end

  @doc """
  Gets all share campaigns.
  """
  def list_share_campaigns do
    # Get all campaign keys and fetch each
    case :mnesia.dirty_all_keys(:share_campaigns) do
      keys when is_list(keys) ->
        keys
        |> Enum.map(&EngagementTracker.get_share_campaign/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      _ -> []
    end
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Gets all active share campaigns.
  """
  def list_active_campaigns do
    EngagementTracker.list_active_share_campaigns()
  end

  @doc """
  Creates a share campaign for a post.
  """
  def create_share_campaign(attrs) do
    post_id = Map.get(attrs, :post_id) || Map.get(attrs, "post_id")
    EngagementTracker.create_share_campaign(post_id, attrs)
  end

  @doc """
  Updates a share campaign.
  """
  def update_share_campaign(campaign, attrs) when is_map(campaign) do
    post_id = Map.get(campaign, :post_id) || Map.get(campaign, "post_id")
    EngagementTracker.update_share_campaign(post_id, attrs)
  end

  @doc """
  Deactivates a share campaign.
  """
  def deactivate_campaign(campaign) when is_map(campaign) do
    post_id = Map.get(campaign, :post_id)
    EngagementTracker.update_share_campaign(post_id, %{is_active: false})
  end

  @doc """
  Increments the total shares count for a campaign.
  """
  def increment_campaign_shares(campaign) when is_map(campaign) do
    post_id = Map.get(campaign, :post_id)
    EngagementTracker.increment_campaign_shares(post_id)
  end

  # =============================================================================
  # Share Reward Management
  # =============================================================================

  @doc """
  Gets a share reward by user and campaign.
  """
  def get_share_reward(user_id, campaign_id) do
    EngagementTracker.get_share_reward(user_id, campaign_id)
  end

  @doc """
  Gets a successful share reward by user and campaign (verified or rewarded status only).
  Returns nil for pending or failed rewards.
  """
  def get_successful_share_reward(user_id, campaign_id) do
    case EngagementTracker.get_share_reward(user_id, campaign_id) do
      %{status: status} = reward when status in ["verified", "rewarded"] -> reward
      _ -> nil
    end
  end

  @doc """
  Creates a pending share reward when user initiates a retweet.
  If a reward already exists, returns {:error, :already_exists}.
  """
  def create_pending_reward(user_id, campaign_id, x_connection_id \\ nil) do
    # First delete any existing failed/pending rewards to allow retry
    case EngagementTracker.get_share_reward(user_id, campaign_id) do
      %{status: status} when status in ["pending", "failed"] ->
        EngagementTracker.delete_share_reward(user_id, campaign_id)
      _ ->
        :ok
    end

    EngagementTracker.create_pending_share_reward(user_id, campaign_id, x_connection_id)
  end

  @doc """
  Marks a share reward as verified after confirming the retweet.
  """
  def verify_share_reward(user_id, campaign_id, retweet_id) do
    EngagementTracker.verify_share_reward(user_id, campaign_id, retweet_id)
  end

  @doc """
  Marks a share reward as rewarded and records the BUX amount and optional tx_hash.
  Also updates the user_post_rewards Mnesia table with the X share reward when post_id is provided.

  Options:
  - tx_hash: blockchain transaction hash (optional)
  - post_id: the post ID for updating user_post_rewards Mnesia table (optional)
  """
  def mark_rewarded(user_id, campaign_id, bux_amount, opts \\ []) do
    tx_hash = opts[:tx_hash]
    post_id = opts[:post_id]

    result = EngagementTracker.mark_share_reward_paid(user_id, campaign_id, bux_amount, tx_hash)

    # Also update user_post_rewards Mnesia table with the X share reward
    case result do
      {:ok, _reward} when not is_nil(post_id) ->
        # Convert Decimal bux_amount to float for Mnesia storage
        bux_float = case bux_amount do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_number(n) -> n * 1.0
          _ -> 0.0
        end

        EngagementTracker.record_x_share_reward_paid(
          user_id,
          post_id,
          bux_float,
          tx_hash
        )
        result

      _ ->
        result
    end
  end

  @doc """
  Marks a share reward as failed with a reason.
  """
  def mark_failed(user_id, campaign_id, reason) do
    EngagementTracker.mark_share_reward_failed(user_id, campaign_id, reason)
  end

  @doc """
  Deletes a share reward (used when share fails due to token issues so user can retry).
  """
  def delete_share_reward(user_id, campaign_id) do
    EngagementTracker.delete_share_reward(user_id, campaign_id)
  end

  @doc """
  Gets all pending rewards for a user.
  """
  def list_pending_rewards_for_user(user_id) do
    EngagementTracker.get_user_share_rewards(user_id)
    |> Enum.filter(& &1.status == "pending")
  end

  @doc """
  Gets all share rewards for a campaign.
  """
  def list_rewards_for_campaign(campaign_id) do
    # Use pattern match on campaign_id
    pattern = {:share_rewards, :_, :_, :_, campaign_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

    :mnesia.dirty_match_object(pattern)
    |> Enum.map(&share_reward_tuple_to_map/1)
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp share_reward_tuple_to_map(record) do
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

  defp unix_to_datetime(nil), do: nil
  defp unix_to_datetime(unix) when is_integer(unix), do: DateTime.from_unix!(unix)

  @doc """
  Checks if a user has already participated in a campaign.
  """
  def user_has_participated?(user_id, campaign_id) do
    EngagementTracker.get_share_reward(user_id, campaign_id) != nil
  end

  @doc """
  Gets all share rewards for a user (rewarded status only) from Mnesia.
  Returns a list of activity maps sorted by rewarded_at (most recent first).
  """
  def list_user_share_rewards(user_id) do
    EngagementTracker.get_user_share_rewards(user_id)
    |> Enum.filter(& &1.status == "rewarded")
    |> Enum.map(fn reward ->
      %{
        type: :x_share,
        label: "X Share",
        amount: reward.bux_rewarded,
        retweet_id: reward.retweet_id,
        tx_id: reward.tx_hash,
        timestamp: reward.rewarded_at || reward.updated_at
      }
    end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  @doc """
  Gets campaign stats.
  """
  def get_campaign_stats(campaign_id) do
    rewards = list_rewards_for_campaign(campaign_id)

    %{
      total: length(rewards),
      pending: Enum.count(rewards, & &1.status == "pending"),
      verified: Enum.count(rewards, & &1.status == "verified"),
      rewarded: Enum.count(rewards, & &1.status == "rewarded"),
      failed: Enum.count(rewards, & &1.status == "failed"),
      total_bux: rewards |> Enum.map(& &1.bux_rewarded || 0) |> Enum.sum()
    }
  end
end
