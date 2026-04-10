defmodule BlocksterV2Web.PostLive.Redesign.Shared do
  @moduledoc """
  Shared helpers for the redesigned homepage layout components.

  All four cycling layouts (`ThreeColumn`, `Mosaic`, `VideoLayout`, `Editorial`)
  reuse these helpers for BUX balance lookup, post-card rendering, hub badge
  rendering, and author initials. Keeping them here so any tweak (e.g. how the
  reward badge is formatted) lands in one place.
  """

  @doc """
  Returns the user's earned reward for a post from `user_post_rewards`, or nil.
  """
  def user_reward(assigns, post) do
    user_post_rewards = Map.get(assigns, :user_post_rewards, %{})
    Map.get(user_post_rewards, post.id)
  end

  @doc """
  Whether the user has already earned a reward for this post.
  """
  def has_earned_reward?(assigns, post) do
    reward = user_reward(assigns, post)
    reward != nil and (reward[:read_bux] > 0 or reward[:x_share_bux] > 0 or reward[:watch_bux] > 0)
  end

  @doc """
  Looks up the live BUX balance for a post from the parent's `bux_balances`
  assign map, falling back to whatever value the post struct already has.
  """
  def bux_balance(assigns, post) do
    bux_balances = Map.get(assigns, :bux_balances, %{})
    Map.get(bux_balances, post.id, Map.get(post, :bux_balance, 0))
  end

  @doc """
  Returns the hub primary color for the post's hub, falling back to the
  brand purple when no hub is associated.
  """
  def hub_color(post) do
    case post.hub do
      %{color_primary: color} when is_binary(color) and color != "" -> color
      _ -> "#7D00FF"
    end
  end

  @doc """
  Returns the hub display name, or nil if no hub is associated.
  """
  def hub_name(post) do
    case post.hub do
      %{name: name} when is_binary(name) -> name
      _ -> nil
    end
  end

  @doc """
  Returns the category display name, or nil.
  """
  def category_name(post) do
    case post.category do
      %{name: name} when is_binary(name) -> name
      _ -> nil
    end
  end

  @doc """
  Returns the author display name, or "Anonymous" when missing.
  """
  def author_name(post) do
    cond do
      is_binary(Map.get(post, :author_name)) and post.author_name != "" -> post.author_name
      match?(%{display_name: dn} when is_binary(dn) and dn != "", post.author) -> post.author.display_name
      match?(%{username: un} when is_binary(un) and un != "", post.author) -> post.author.username
      true -> "Anonymous"
    end
  end

  @doc """
  Returns 2-letter uppercase initials for an author display name.
  """
  def author_initials(post) do
    name = author_name(post)

    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
    |> case do
      "" -> "??"
      i -> i
    end
  end

  @doc """
  Returns an estimated reading time in minutes for a post.
  Falls back to 5 minutes when no signal is available.
  """
  def read_minutes(post) do
    cond do
      is_integer(Map.get(post, :reading_time)) and post.reading_time > 0 -> post.reading_time
      true -> 5
    end
  end

  @doc """
  Returns a video duration string formatted as MM:SS for the player overlay.
  Returns nil when not a video or no duration set.
  """
  def video_duration(post) do
    case Map.get(post, :video_duration) do
      seconds when is_integer(seconds) and seconds > 0 ->
        minutes = div(seconds, 60)
        remainder = rem(seconds, 60)
        :io_lib.format("~B:~2..0B", [minutes, remainder]) |> IO.iodata_to_binary()

      _ ->
        nil
    end
  end

  @doc """
  Returns the featured image URL for a post, falling back to a placeholder.
  """
  def post_image(post) do
    case Map.get(post, :featured_image) do
      url when is_binary(url) and url != "" -> url
      _ -> "https://picsum.photos/seed/blockster-#{post.id}/640/360"
    end
  end

  @doc """
  Truncates a long excerpt to N characters with an ellipsis.
  """
  def short_excerpt(nil, _max), do: nil

  def short_excerpt(text, max) when is_binary(text) do
    if String.length(text) > max do
      String.slice(text, 0, max) <> "…"
    else
      text
    end
  end
end
