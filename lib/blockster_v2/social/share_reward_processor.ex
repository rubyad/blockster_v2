defmodule BlocksterV2.Social.ShareRewardProcessor do
  @moduledoc """
  Processes share rewards for X campaigns.
  Handles the full flow from share tracking to BUX minting.

  Uses Mnesia for all data storage via EngagementTracker.
  """

  require Logger

  alias BlocksterV2.{BuxMinter, EngagementTracker}
  alias BlocksterV2.Social
  alias BlocksterV2.Social.XApiClient
  alias BlocksterV2.Accounts
  alias BlocksterV2.Blog

  @doc """
  Processes a share action for a user.
  Creates a tweet with the share link and creates a pending reward.

  Returns {:ok, %{tweet: tweet_data, reward: reward}} or {:error, reason}
  """
  def process_share(user_id, campaign_id) do
    with {:user, user} when not is_nil(user) <- {:user, Accounts.get_user(user_id)},
         {:connection, connection} when not is_nil(connection) <- {:connection, Social.get_x_connection_for_user(user_id)},
         {:campaign, campaign} when not is_nil(campaign) <- {:campaign, Social.get_share_campaign(campaign_id)},
         {:active, true} <- {:active, campaign_active?(campaign)},
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
  def verify_and_reward(user_id, campaign_id) do
    with {:reward, reward} when not is_nil(reward) <- {:reward, Social.get_share_reward(user_id, campaign_id)},
         {:pending, true} <- {:pending, reward.status == "pending"},
         {:verify, {:ok, verified_reward}} <- {:verify, verify_reward(user_id, campaign_id, reward)},
         {:mint, {:ok, final_reward}} <- {:mint, mint_reward(user_id, campaign_id, verified_reward)} do
      {:ok, final_reward}
    else
      {:reward, nil} -> {:error, "Reward not found"}
      {:pending, false} -> {:error, "Reward already processed"}
      {:verify, {:error, reason}} -> {:error, "Verification failed: #{reason}"}
      {:mint, {:error, reason}} -> {:error, "Minting failed: #{reason}"}
    end
  end

  @doc """
  Processes pending rewards that need verification.
  Can be called periodically to process old pending rewards.
  """
  def process_pending_rewards do
    five_minutes_ago = DateTime.utc_now() |> DateTime.add(-5 * 60, :second)
    pending_rewards = EngagementTracker.get_pending_share_rewards_before(five_minutes_ago)

    results = Enum.map(pending_rewards, fn reward ->
      case verify_and_reward(reward.user_id, reward.campaign_id) do
        {:ok, _} -> {:ok, {reward.user_id, reward.campaign_id}}
        {:error, reason} -> {:error, {reward.user_id, reward.campaign_id}, reason}
      end
    end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _, _}, &1))

    Logger.info("[ShareRewardProcessor] Processed #{successful} rewards, #{failed} failed")

    {:ok, %{successful: successful, failed: failed}}
  end

  # Private functions

  defp campaign_active?(campaign) do
    now = DateTime.utc_now()

    campaign.is_active == true and
      (is_nil(campaign.starts_at) or DateTime.compare(now, campaign.starts_at) != :lt) and
      (is_nil(campaign.ends_at) or DateTime.compare(now, campaign.ends_at) == :lt) and
      (is_nil(campaign.max_participants) or campaign.total_shares < campaign.max_participants)
  end

  defp ensure_valid_token(connection) do
    if token_needs_refresh?(connection) do
      refresh_token(connection)
    else
      {:ok, connection}
    end
  end

  defp token_needs_refresh?(%{token_expires_at: nil}), do: false
  defp token_needs_refresh?(%{token_expires_at: expires_at}) when is_struct(expires_at, DateTime) do
    five_minutes_from_now = DateTime.utc_now() |> DateTime.add(5, :minute)
    DateTime.compare(expires_at, five_minutes_from_now) == :lt
  end
  defp token_needs_refresh?(_), do: false

  defp refresh_token(connection) do
    refresh_token_value = Map.get(connection, :refresh_token)

    case XApiClient.refresh_token(refresh_token_value) do
      {:ok, token_data} ->
        expires_at = calculate_expiry(token_data.expires_in)

        case EngagementTracker.update_x_connection_tokens(
          connection.user_id,
          token_data.access_token,
          token_data.refresh_token,
          expires_at
        ) do
          {:ok, updated} -> {:ok, updated}
          {:error, reason} -> {:error, reason}
        end

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

  defp create_share_tweet(connection, campaign) do
    access_token = Map.get(connection, :access_token)
    tweet_text = build_tweet_text(campaign)

    XApiClient.create_tweet(access_token, tweet_text)
  end

  defp build_tweet_text(%{tweet_text: custom_text, tweet_url: url}) when not is_nil(custom_text) do
    "#{custom_text}\n\n#{url}"
  end

  defp build_tweet_text(%{tweet_url: url, post_id: post_id}) when not is_nil(post_id) do
    case Blog.get_post(post_id) do
      nil -> "Check out this article! #{url}"
      post -> "Check out this article: #{post.title}\n\n#{url}"
    end
  end

  defp build_tweet_text(%{tweet_url: url}) do
    "Check out this article! #{url}"
  end

  defp create_and_process_reward(user, campaign, connection, tweet_data) do
    # Extract tweet ID from response
    tweet_id = get_in(tweet_data, ["data", "id"])
    post_id = campaign.post_id

    # Create reward with connection info
    x_connection_id = connection.user_id  # Using user_id as the Mnesia key for x_connections

    case Social.create_pending_reward(user.id, post_id, x_connection_id) do
      {:ok, _reward} ->
        # Immediately verify and mark as verified since we just created the tweet
        case Social.verify_share_reward(user.id, post_id, tweet_id) do
          {:ok, verified_reward} ->
            # Increment campaign share count
            EngagementTracker.increment_campaign_shares(post_id)

            # Attempt immediate minting
            case mint_reward(user.id, post_id, verified_reward) do
              {:ok, rewarded} -> {:ok, rewarded}
              {:error, _} -> {:ok, verified_reward}  # Return verified even if minting fails
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, "Could not create reward: #{inspect(reason)}"}
    end
  end

  defp verify_reward(user_id, campaign_id, reward) do
    # For rewards created through our flow, they're auto-verified
    # For manual verification, we could check the X API
    if reward.retweet_id do
      {:ok, reward}
    else
      # Try to verify via X API (optional, depends on whether we have the data)
      Social.verify_share_reward(user_id, campaign_id, nil)
    end
  end

  defp mint_reward(user_id, campaign_id, _reward) do
    user = Accounts.get_user(user_id)
    campaign = Social.get_share_campaign(campaign_id)

    if is_nil(user) or is_nil(campaign) do
      Social.mark_failed(user_id, campaign_id, "User or campaign not found")
      {:error, "User or campaign not found"}
    else
      bux_amount = campaign.bux_reward
      post_id = campaign.post_id

      # Get hub_id from the campaign's post (if it has one)
      post = Blog.get_post(post_id)
      hub_id = post && post.hub_id

      # Get user's wallet address
      case user.smart_wallet_address do
        nil ->
          Social.mark_failed(user_id, campaign_id, "User has no wallet address")
          {:error, "No wallet address"}

        wallet_address ->
          # Use campaign post_id for tracking, include hub_id for hub BUX totals
          case BuxMinter.mint_bux(wallet_address, bux_amount, user_id, post_id, :x_share, "BUX", hub_id) do
            {:ok, response} ->
              tx_hash = response["transactionHash"]
              Social.mark_rewarded(user_id, campaign_id, bux_amount, tx_hash: tx_hash, post_id: post_id)

            {:error, :not_configured} ->
              # In development, mark as rewarded anyway
              Logger.warning("[ShareRewardProcessor] BuxMinter not configured, marking reward without actual mint")
              Social.mark_rewarded(user_id, campaign_id, bux_amount, post_id: post_id)

            {:error, reason} ->
              Logger.error("[ShareRewardProcessor] Mint failed: #{inspect(reason)}")
              Social.mark_failed(user_id, campaign_id, "Mint failed: #{inspect(reason)}")
              {:error, reason}
          end
      end
    end
  end
end
