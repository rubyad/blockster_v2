defmodule BlocksterV2.Social do
  @moduledoc """
  The Social context handles X (Twitter) integration for share campaigns.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Social.{XConnection, XOauthState, ShareCampaign, ShareReward, XApiClient}

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

    %ShareReward{}
    |> ShareReward.changeset(%{
      user_id: user_id,
      campaign_id: campaign_id,
      x_connection_id: x_connection_id,
      status: "pending"
    })
    |> Repo.insert()
  end

  @doc """
  Marks a share reward as verified after confirming the retweet.
  """
  def verify_share_reward(%ShareReward{} = reward, retweet_id) do
    reward
    |> ShareReward.verify_changeset(%{retweet_id: retweet_id})
    |> Repo.update()
  end

  @doc """
  Marks a share reward as rewarded and records the BUX amount.
  """
  def mark_rewarded(%ShareReward{} = reward, bux_amount) do
    reward
    |> ShareReward.reward_changeset(bux_amount)
    |> Repo.update()
  end

  @doc """
  Marks a share reward as failed with a reason.
  """
  def mark_failed(%ShareReward{} = reward, reason) do
    reward
    |> ShareReward.fail_changeset(reason)
    |> Repo.update()
  end

  @doc """
  Deletes a share reward (used when share fails due to token issues so user can retry).
  """
  def delete_share_reward(%ShareReward{} = reward) do
    Repo.delete(reward)
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
end
