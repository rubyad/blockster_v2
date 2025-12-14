defmodule BlocksterV2.Social do
  @moduledoc """
  The Social context handles X (Twitter) integration for share campaigns.
  """

  require Logger
  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Social.{XConnection, XOauthState, ShareCampaign, ShareReward, XApiClient}
  alias BlocksterV2.EngagementTracker

  # =============================================================================
  # X OAuth State Management
  # =============================================================================

  @doc """
  Creates a new OAuth state for starting the X OAuth flow.
  Returns {:ok, state} where state includes the authorization URL parameters.
  """
  def create_oauth_state(attrs \\ %{}) do
    XOauthState.new(attrs)
    |> Repo.insert()
  end

  @doc """
  Retrieves and validates an OAuth state by state string.
  Returns nil if not found or expired.
  """
  def get_valid_oauth_state(state) do
    case Repo.get_by(XOauthState, state: state) do
      nil -> nil
      oauth_state ->
        if XOauthState.expired?(oauth_state) do
          Repo.delete(oauth_state)
          nil
        else
          oauth_state
        end
    end
  end

  @doc """
  Consumes an OAuth state (deletes it after use).
  """
  def consume_oauth_state(oauth_state) do
    Repo.delete(oauth_state)
  end

  @doc """
  Cleans up expired OAuth states (for periodic cleanup job).
  """
  def cleanup_expired_oauth_states do
    now = DateTime.utc_now()

    from(s in XOauthState, where: s.expires_at < ^now)
    |> Repo.delete_all()
  end

  # =============================================================================
  # X Connection Management
  # =============================================================================

  @doc """
  Gets a user's X connection.
  """
  def get_x_connection_for_user(user_id) do
    Repo.get_by(XConnection, user_id: user_id)
  end

  @doc """
  Gets an X connection by X user ID.
  """
  def get_x_connection_by_x_user_id(x_user_id) do
    Repo.get_by(XConnection, x_user_id: x_user_id)
  end

  @doc """
  Creates or updates an X connection for a user.
  If the user already has a connection, it updates the tokens.
  """
  def upsert_x_connection(user_id, attrs) do
    case get_x_connection_for_user(user_id) do
      nil ->
        %XConnection{}
        |> XConnection.changeset(Map.put(attrs, :user_id, user_id))
        |> Repo.insert()

      existing ->
        existing
        |> XConnection.update_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Disconnects a user's X account.
  """
  def disconnect_x_account(user_id) do
    case get_x_connection_for_user(user_id) do
      nil -> {:ok, nil}
      connection -> Repo.delete(connection)
    end
  end

  @doc """
  Refreshes an X connection's access token if it's expired or about to expire.
  """
  def maybe_refresh_token(%XConnection{} = connection) do
    if XConnection.token_needs_refresh?(connection) do
      refresh_x_token(connection)
    else
      {:ok, connection}
    end
  end

  defp refresh_x_token(connection) do
    refresh_token = XConnection.decrypt_refresh_token(connection)

    if is_nil(refresh_token) do
      {:error, "No refresh token available"}
    else
      case XApiClient.refresh_token(refresh_token) do
        {:ok, token_data} ->
          expires_at =
            if token_data.expires_in do
              DateTime.utc_now()
              |> DateTime.add(token_data.expires_in, :second)
              |> DateTime.truncate(:second)
            end

          attrs = %{
            access_token: token_data.access_token,
            refresh_token: token_data.refresh_token,
            token_expires_at: expires_at
          }

          case update_x_connection(connection, attrs) do
            {:ok, updated_connection} ->
              {:ok, updated_connection}

            {:error, changeset} ->
              {:error, "Failed to save refreshed token: #{inspect(changeset.errors)}"}
          end

        {:error, reason} ->
          {:error, "Token refresh failed: #{reason}"}
      end
    end
  end

  @doc """
  Updates an X connection with new attributes.
  """
  def update_x_connection(%XConnection{} = connection, attrs) do
    connection
    |> XConnection.update_changeset(attrs)
    |> Repo.update()
  end

  # =============================================================================
  # Share Campaign Management
  # =============================================================================

  @doc """
  Gets a share campaign by ID.
  """
  def get_share_campaign(id) do
    Repo.get(ShareCampaign, id)
  end

  @doc """
  Gets a share campaign by post ID.
  """
  def get_campaign_for_post(post_id) do
    Repo.get_by(ShareCampaign, post_id: post_id)
    |> Repo.preload(:post)
  end

  @doc """
  Gets all share campaigns.
  """
  def list_share_campaigns do
    from(c in ShareCampaign,
      order_by: [desc: c.inserted_at],
      preload: [:post]
    )
    |> Repo.all()
  end

  @doc """
  Gets all active share campaigns.
  """
  def list_active_campaigns do
    now = DateTime.utc_now()

    from(c in ShareCampaign,
      where: c.is_active == true,
      where: is_nil(c.starts_at) or c.starts_at <= ^now,
      where: is_nil(c.ends_at) or c.ends_at > ^now,
      where: is_nil(c.max_participants) or c.total_shares < c.max_participants,
      order_by: [desc: c.inserted_at],
      preload: [:post]
    )
    |> Repo.all()
  end

  @doc """
  Creates a share campaign for a post.
  """
  def create_share_campaign(attrs) do
    %ShareCampaign{}
    |> ShareCampaign.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a share campaign.
  """
  def update_share_campaign(%ShareCampaign{} = campaign, attrs) do
    campaign
    |> ShareCampaign.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deactivates a share campaign.
  """
  def deactivate_campaign(%ShareCampaign{} = campaign) do
    update_share_campaign(campaign, %{is_active: false})
  end

  @doc """
  Increments the total shares count for a campaign.
  """
  def increment_campaign_shares(%ShareCampaign{id: id}) do
    from(c in ShareCampaign, where: c.id == ^id)
    |> Repo.update_all(inc: [total_shares: 1])
  end

  # =============================================================================
  # Share Reward Management
  # =============================================================================

  @doc """
  Gets a share reward by user and campaign.
  """
  def get_share_reward(user_id, campaign_id) do
    Repo.get_by(ShareReward, user_id: user_id, campaign_id: campaign_id)
  end

  @doc """
  Gets a successful share reward by user and campaign (verified or rewarded status only).
  Returns nil for pending or failed rewards.
  """
  def get_successful_share_reward(user_id, campaign_id) do
    from(r in ShareReward,
      where: r.user_id == ^user_id and r.campaign_id == ^campaign_id,
      where: r.status in ["verified", "rewarded"]
    )
    |> Repo.one()
  end

  @doc """
  Creates a pending share reward when user initiates a retweet.
  If a failed or pending reward already exists, it deletes it first to allow retry.
  """
  def create_pending_reward(user_id, campaign_id, x_connection_id \\ nil) do
    # Delete any existing failed/pending rewards to allow retry
    from(r in ShareReward,
      where: r.user_id == ^user_id and r.campaign_id == ^campaign_id,
      where: r.status in ["pending", "failed"]
    )
    |> Repo.delete_all()

    # Also delete from Mnesia
    delete_share_reward_from_mnesia(user_id, campaign_id)

    result =
      %ShareReward{}
      |> ShareReward.changeset(%{
        user_id: user_id,
        campaign_id: campaign_id,
        x_connection_id: x_connection_id,
        status: "pending"
      })
      |> Repo.insert()

    # Sync to Mnesia on success
    case result do
      {:ok, reward} ->
        sync_share_reward_to_mnesia(reward)
        {:ok, reward}

      error ->
        error
    end
  end

  @doc """
  Marks a share reward as verified after confirming the retweet.
  """
  def verify_share_reward(%ShareReward{} = reward, retweet_id) do
    result =
      reward
      |> ShareReward.verify_changeset(%{retweet_id: retweet_id})
      |> Repo.update()

    # Sync to Mnesia on success
    case result do
      {:ok, updated_reward} ->
        sync_share_reward_to_mnesia(updated_reward)
        {:ok, updated_reward}

      error ->
        error
    end
  end

  @doc """
  Marks a share reward as rewarded and records the BUX amount and optional tx_hash.
  Also updates the user_post_rewards Mnesia table with the X share reward when post_id is provided.

  Options:
  - tx_hash: blockchain transaction hash (optional)
  - post_id: the post ID for updating user_post_rewards Mnesia table (optional)
  """
  def mark_rewarded(%ShareReward{} = reward, bux_amount, opts \\ []) do
    tx_hash = opts[:tx_hash]
    post_id = opts[:post_id]

    result =
      reward
      |> ShareReward.reward_changeset(bux_amount, tx_hash)
      |> Repo.update()

    # Sync to Mnesia on success
    case result do
      {:ok, updated_reward} ->
        sync_share_reward_to_mnesia(updated_reward)

        # Also update user_post_rewards Mnesia table with the X share reward
        if post_id do
          # Convert Decimal bux_amount to float for Mnesia storage
          bux_float = case bux_amount do
            %Decimal{} = d -> Decimal.to_float(d)
            n when is_number(n) -> n * 1.0
            _ -> 0.0
          end

          EngagementTracker.record_x_share_reward_paid(
            updated_reward.user_id,
            post_id,
            bux_float,
            tx_hash
          )
        end

        {:ok, updated_reward}

      error ->
        error
    end
  end

  @doc """
  Marks a share reward as failed with a reason.
  """
  def mark_failed(%ShareReward{} = reward, reason) do
    result =
      reward
      |> ShareReward.fail_changeset(reason)
      |> Repo.update()

    # Sync to Mnesia on success
    case result do
      {:ok, updated_reward} ->
        sync_share_reward_to_mnesia(updated_reward)
        {:ok, updated_reward}

      error ->
        error
    end
  end

  @doc """
  Deletes a share reward (used when share fails due to token issues so user can retry).
  """
  def delete_share_reward(%ShareReward{} = reward) do
    result = Repo.delete(reward)

    # Also delete from Mnesia
    case result do
      {:ok, deleted_reward} ->
        delete_share_reward_from_mnesia(deleted_reward.user_id, deleted_reward.campaign_id)
        {:ok, deleted_reward}

      error ->
        error
    end
  end

  @doc """
  Gets all pending rewards for a user.
  """
  def list_pending_rewards_for_user(user_id) do
    from(r in ShareReward,
      where: r.user_id == ^user_id and r.status == "pending",
      preload: [:campaign]
    )
    |> Repo.all()
  end

  @doc """
  Gets all share rewards for a campaign.
  """
  def list_rewards_for_campaign(campaign_id) do
    from(r in ShareReward,
      where: r.campaign_id == ^campaign_id,
      order_by: [desc: r.inserted_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Checks if a user has already participated in a campaign.
  """
  def user_has_participated?(user_id, campaign_id) do
    from(r in ShareReward,
      where: r.user_id == ^user_id and r.campaign_id == ^campaign_id
    )
    |> Repo.exists?()
  end

  @doc """
  Gets all share rewards for a user (rewarded status only) from Mnesia.
  Returns a list of activity maps sorted by rewarded_at (most recent first).

  Each activity includes:
  - type: :x_share
  - label: "X Share"
  - amount: BUX earned
  - retweet_id: the X post/retweet ID (for linking to tweet)
  - timestamp: DateTime when the reward was given
  """
  def list_user_share_rewards(user_id) do
    # Read from Mnesia share_rewards table
    # Pattern matches on user_id at index 3 (after key, id)
    pattern = {:share_rewards, :_, :_, user_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

    records = :mnesia.dirty_match_object(pattern)

    # Filter to only rewarded status and convert to activity maps
    records
    |> Enum.filter(fn record -> elem(record, 7) == "rewarded" end)
    |> Enum.map(&share_reward_record_to_activity/1)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp share_reward_record_to_activity(record) do
    # Mnesia record structure:
    # {:share_rewards, key, id, user_id, campaign_id, x_connection_id, retweet_id, status,
    #  bux_rewarded, verified_at, rewarded_at, failure_reason, tx_hash, created_at, updated_at}
    retweet_id = elem(record, 6)
    bux_rewarded = elem(record, 8)
    rewarded_at = elem(record, 10)
    tx_hash = elem(record, 12)

    # Convert unix timestamp to DateTime
    timestamp = if rewarded_at, do: DateTime.from_unix!(rewarded_at), else: DateTime.utc_now()

    %{
      type: :x_share,
      label: "X Share",
      amount: bux_rewarded,
      retweet_id: retweet_id,
      tx_id: tx_hash,
      timestamp: timestamp
    }
  end

  @doc """
  Gets campaign stats.
  """
  def get_campaign_stats(campaign_id) do
    from(r in ShareReward,
      where: r.campaign_id == ^campaign_id,
      select: %{
        total: count(r.id),
        pending: count(fragment("CASE WHEN ? = 'pending' THEN 1 END", r.status)),
        verified: count(fragment("CASE WHEN ? = 'verified' THEN 1 END", r.status)),
        rewarded: count(fragment("CASE WHEN ? = 'rewarded' THEN 1 END", r.status)),
        failed: count(fragment("CASE WHEN ? = 'failed' THEN 1 END", r.status)),
        total_bux: sum(r.bux_rewarded)
      }
    )
    |> Repo.one()
  end

  # =============================================================================
  # Mnesia Share Rewards Sync
  # =============================================================================

  @doc """
  Syncs all share_rewards from PostgreSQL to Mnesia.
  Use this to backfill existing records or recover from data loss.
  Returns {:ok, count} on success.
  """
  def sync_all_share_rewards_to_mnesia do
    rewards = Repo.all(ShareReward)
    count = length(rewards)

    Logger.info("[Social] Starting sync of #{count} share_rewards from PostgreSQL to Mnesia")

    results =
      Enum.map(rewards, fn reward ->
        sync_share_reward_to_mnesia(reward)
      end)

    success_count = Enum.count(results, &(&1 == :ok))
    error_count = count - success_count

    Logger.info("[Social] Sync complete: #{success_count} succeeded, #{error_count} failed")

    {:ok, %{total: count, success: success_count, errors: error_count}}
  end

  @doc """
  Syncs a ShareReward record to Mnesia.
  Called automatically when a reward is created or updated in PostgreSQL.
  """
  defp sync_share_reward_to_mnesia(%ShareReward{} = reward) do
    key = {reward.user_id, reward.campaign_id}
    now = System.system_time(:second)

    # Convert DateTime fields to unix timestamps
    verified_at = datetime_to_unix(reward.verified_at)
    rewarded_at = datetime_to_unix(reward.rewarded_at)
    created_at = datetime_to_unix(reward.inserted_at)

    # Convert Decimal to float for storage
    bux_rewarded =
      case reward.bux_rewarded do
        nil -> nil
        %Decimal{} = d -> Decimal.to_float(d)
        n when is_number(n) -> n
      end

    record =
      {:share_rewards, key, reward.id, reward.user_id, reward.campaign_id,
       reward.x_connection_id, reward.retweet_id, reward.status, bux_rewarded,
       verified_at, rewarded_at, reward.failure_reason, reward.tx_hash,
       created_at, now}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} ->
        Logger.debug("[Social] Synced share_reward to Mnesia: user_id=#{reward.user_id}, campaign_id=#{reward.campaign_id}, status=#{reward.status}")
        :ok

      {:aborted, reason} ->
        Logger.error("[Social] Failed to sync share_reward to Mnesia: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("[Social] Exception syncing share_reward to Mnesia: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Deletes a share reward from Mnesia by user_id and campaign_id.
  """
  defp delete_share_reward_from_mnesia(user_id, campaign_id) do
    key = {user_id, campaign_id}

    case :mnesia.transaction(fn -> :mnesia.delete({:share_rewards, key}) end) do
      {:atomic, :ok} ->
        Logger.debug("[Social] Deleted share_reward from Mnesia: user_id=#{user_id}, campaign_id=#{campaign_id}")
        :ok

      {:aborted, reason} ->
        Logger.error("[Social] Failed to delete share_reward from Mnesia: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("[Social] Exception deleting share_reward from Mnesia: #{inspect(e)}")
      {:error, e}
  end

  # Helper to convert DateTime to unix timestamp
  defp datetime_to_unix(nil), do: nil
  defp datetime_to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp datetime_to_unix(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end
end
