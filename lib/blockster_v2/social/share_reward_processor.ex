defmodule BlocksterV2.Social.ShareRewardProcessor do
  @moduledoc """
  Processes share rewards for X campaigns.
  Handles the full flow from share tracking to BUX minting.
  """

  require Logger

  alias BlocksterV2.{Repo, BuxMinter}
  alias BlocksterV2.Social
  alias BlocksterV2.Social.{XApiClient, XConnection, ShareCampaign, ShareReward}
  alias BlocksterV2.Accounts

  @doc """
  Processes a share action for a user.
  Creates a tweet with the share link and creates a pending reward.

  Returns {:ok, %{tweet: tweet_data, reward: reward}} or {:error, reason}
  """
  def process_share(user_id, campaign_id) do
    with {:user, user} when not is_nil(user) <- {:user, Accounts.get_user(user_id)},
         {:connection, %XConnection{} = connection} <- {:connection, Social.get_x_connection_for_user(user_id)},
         {:campaign, %ShareCampaign{} = campaign} <- {:campaign, Social.get_share_campaign(campaign_id)},
         {:active, true} <- {:active, ShareCampaign.active?(campaign)},
         {:not_participated, false} <- {:not_participated, Social.user_has_participated?(user_id, campaign_id)},
         {:token, {:ok, refreshed_connection}} <- {:token, ensure_valid_token(connection)},
         {:tweet, {:ok, tweet_data}} <- {:tweet, create_share_tweet(refreshed_connection, campaign)},
         {:reward, {:ok, reward}} <- {:reward, create_and_process_reward(user, campaign, refreshed_connection, tweet_data)} do
      {:ok, %{tweet: tweet_data, reward: reward}}
    else
      {:user, nil} -> {:error, "User not found"}
      {:connection, nil} -> {:error, "X account not connected"}
      {:campaign, nil} -> {:error, "Campaign not found"}
      {:active, false} -> {:error, "Campaign is not active"}
      {:not_participated, true} -> {:error, "Already participated in this campaign"}
      {:token, {:error, reason}} -> {:error, "Token refresh failed: #{reason}"}
      {:tweet, {:error, reason}} -> {:error, "Tweet failed: #{reason}"}
      {:reward, {:error, reason}} -> {:error, "Reward creation failed: #{reason}"}
    end
  end

  @doc """
  Verifies and processes reward for a pending share reward.
  Called after a user claims they've shared.
  """
  def verify_and_reward(reward_id) do
    with {:reward, %ShareReward{status: "pending"} = reward} <- {:reward, Repo.get(ShareReward, reward_id) |> Repo.preload([:user, :campaign, :x_connection])},
         {:verify, {:ok, verified_reward}} <- {:verify, verify_reward(reward)},
         {:mint, {:ok, final_reward}} <- {:mint, mint_reward(verified_reward)} do
      {:ok, final_reward}
    else
      {:reward, nil} -> {:error, "Reward not found"}
      {:reward, %ShareReward{status: status}} -> {:error, "Reward already #{status}"}
      {:verify, {:error, reason}} -> {:error, "Verification failed: #{reason}"}
      {:mint, {:error, reason}} -> {:error, "Minting failed: #{reason}"}
    end
  end

  @doc """
  Processes pending rewards that need verification.
  Can be called periodically to process old pending rewards.
  """
  def process_pending_rewards do
    pending_rewards = list_old_pending_rewards()

    results = Enum.map(pending_rewards, fn reward ->
      case verify_and_reward(reward.id) do
        {:ok, _} -> {:ok, reward.id}
        {:error, reason} -> {:error, reward.id, reason}
      end
    end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _, _}, &1))

    Logger.info("[ShareRewardProcessor] Processed #{successful} rewards, #{failed} failed")

    {:ok, %{successful: successful, failed: failed}}
  end

  # Private functions

  defp ensure_valid_token(%XConnection{} = connection) do
    if XConnection.token_needs_refresh?(connection) do
      refresh_token(connection)
    else
      {:ok, connection}
    end
  end

  defp refresh_token(%XConnection{} = connection) do
    refresh_token = XConnection.get_decrypted_refresh_token(connection)

    case XApiClient.refresh_token(refresh_token) do
      {:ok, token_data} ->
        Social.upsert_x_connection(connection.user_id, %{
          access_token: token_data.access_token,
          refresh_token: token_data.refresh_token,
          token_expires_at: calculate_expiry(token_data.expires_in)
        })

      {:error, reason} ->
        Logger.error("[ShareRewardProcessor] Token refresh failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp calculate_expiry(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
    |> DateTime.truncate(:second)
  end

  defp create_share_tweet(%XConnection{} = connection, %ShareCampaign{} = campaign) do
    access_token = XConnection.get_decrypted_access_token(connection)
    tweet_text = build_tweet_text(campaign)

    XApiClient.create_tweet(access_token, tweet_text)
  end

  defp build_tweet_text(%ShareCampaign{tweet_text: custom_text, tweet_url: url}) when not is_nil(custom_text) do
    "#{custom_text}\n\n#{url}"
  end

  defp build_tweet_text(%ShareCampaign{tweet_url: url, post: post}) when not is_nil(post) do
    "Check out this article: #{post.title}\n\n#{url}"
  end

  defp build_tweet_text(%ShareCampaign{tweet_url: url}) do
    "Check out this article! #{url}"
  end

  defp create_and_process_reward(user, campaign, connection, tweet_data) do
    # Extract tweet ID from response
    tweet_id = get_in(tweet_data, ["data", "id"])

    # Create reward with tweet info
    case Social.create_pending_reward(user.id, campaign.id, connection.id) do
      {:ok, reward} ->
        # Immediately verify and mark as verified since we just created the tweet
        case Social.verify_share_reward(reward, tweet_id) do
          {:ok, verified_reward} ->
            # Increment campaign share count
            Social.increment_campaign_shares(campaign)

            # Attempt immediate minting
            case mint_reward(verified_reward) do
              {:ok, rewarded} -> {:ok, rewarded}
              {:error, _} -> {:ok, verified_reward}  # Return verified even if minting fails
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, changeset} ->
        {:error, "Could not create reward: #{inspect(changeset.errors)}"}
    end
  end

  defp verify_reward(%ShareReward{} = reward) do
    # For rewards created through our flow, they're auto-verified
    # For manual verification, we could check the X API
    if reward.retweet_id do
      {:ok, reward}
    else
      # Try to verify via X API (optional, depends on whether we have the data)
      Social.verify_share_reward(reward, nil)
    end
  end

  defp mint_reward(%ShareReward{} = reward) do
    reward = Repo.preload(reward, [:user, :campaign])
    user = reward.user
    campaign = reward.campaign
    bux_amount = campaign.bux_reward

    # Get user's wallet address
    case user.smart_wallet_address do
      nil ->
        Social.mark_failed(reward, "User has no wallet address")
        {:error, "No wallet address"}

      wallet_address ->
        # Use campaign post_id for tracking
        case BuxMinter.mint_bux(wallet_address, bux_amount, user.id, campaign.post_id) do
          {:ok, _response} ->
            Social.mark_rewarded(reward, bux_amount)

          {:error, :not_configured} ->
            # In development, mark as rewarded anyway
            Logger.warning("[ShareRewardProcessor] BuxMinter not configured, marking reward without actual mint")
            Social.mark_rewarded(reward, bux_amount)

          {:error, reason} ->
            Logger.error("[ShareRewardProcessor] Mint failed: #{inspect(reason)}")
            Social.mark_failed(reward, "Mint failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp list_old_pending_rewards do
    # Get pending rewards older than 5 minutes
    import Ecto.Query

    five_minutes_ago = DateTime.utc_now() |> DateTime.add(-5 * 60, :second)

    from(r in ShareReward,
      where: r.status == "pending",
      where: r.inserted_at < ^five_minutes_ago,
      preload: [:user, :campaign, :x_connection]
    )
    |> Repo.all()
  end
end
