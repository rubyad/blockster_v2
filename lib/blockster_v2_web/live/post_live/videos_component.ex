defmodule BlocksterV2Web.PostLive.VideosComponent do
  use BlocksterV2Web, :live_component

  import BlocksterV2Web.SharedComponents, only: [token_badge: 1]

  # Get BUX balance from the real-time bux_balances map, falling back to post's value
  defp get_bux_balance(assigns, post) do
    bux_balances = Map.get(assigns, :bux_balances, %{})
    Map.get(bux_balances, post.id, Map.get(post, :bux_balance, 0))
  end
end
