defmodule BlocksterV2Web.PostLive.PostsSixComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.ImageKit
  import BlocksterV2Web.SharedComponents, only: [token_badge: 1, video_play_icon: 1, earned_badges: 1]

  # Get BUX balance from the real-time bux_balances map, falling back to post's value
  defp get_bux_balance(assigns, post) do
    bux_balances = Map.get(assigns, :bux_balances, %{})
    Map.get(bux_balances, post.id, Map.get(post, :bux_balance, 0))
  end

  # Get user's earned rewards for a post, returns nil if no rewards
  defp get_user_reward(assigns, post) do
    user_post_rewards = Map.get(assigns, :user_post_rewards, %{})
    Map.get(user_post_rewards, post.id)
  end

  # Check if user has any rewards for this post
  defp has_earned_reward?(assigns, post) do
    reward = get_user_reward(assigns, post)
    reward != nil and (reward[:read_bux] > 0 or reward[:x_share_bux] > 0 or reward[:watch_bux] > 0)
  end

  # Count number of earned reward badges (read, share, watch)
  defp reward_badge_count(assigns, post) do
    case get_user_reward(assigns, post) do
      nil -> 0
      reward ->
        Enum.count([:read_bux, :x_share_bux, :watch_bux], fn key ->
          (reward[key] || 0) > 0
        end)
    end
  end
end
