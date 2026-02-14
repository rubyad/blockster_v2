defmodule BlocksterV2.ContentAutomation.TweetPlacer do
  @moduledoc """
  Smart placement of tweet nodes throughout TipTap article content.

  Distributes tweets evenly among paragraphs so they never stack adjacent
  to each other and appear at natural reading breaks.

  Used by TweetFinder (initial placement), EditorialFeedback (revision preservation),
  and the EditArticle LiveView (manual add/refresh).
  """

  @doc """
  Distribute tweet nodes evenly throughout content nodes.

  Takes a list of non-tweet content nodes and a list of tweet nodes,
  returns a merged list with tweets spaced evenly between paragraphs.
  """
  def distribute_tweets(content_nodes, tweet_nodes) when tweet_nodes == [], do: content_nodes

  def distribute_tweets(content_nodes, tweet_nodes) do
    # Find paragraph indices (positions where we can insert tweets — after paragraphs)
    paragraph_indices =
      content_nodes
      |> Enum.with_index()
      |> Enum.filter(fn {node, _i} -> node["type"] == "paragraph" end)
      |> Enum.map(fn {_node, i} -> i end)

    para_count = length(paragraph_indices)
    tweet_count = length(tweet_nodes)

    if para_count < 2 do
      # Too few paragraphs, just append tweets at the end
      content_nodes ++ tweet_nodes
    else
      # Calculate insertion points — evenly spaced, never at the very start
      # For N tweets in P paragraphs, place at positions P/(N+1), 2P/(N+1), etc.
      insert_after_indices =
        1..tweet_count
        |> Enum.map(fn i ->
          target_para = round(para_count * i / (tweet_count + 1))
          # Clamp: at least after 2nd paragraph, at most after 2nd-to-last
          target_para = max(2, min(target_para, para_count - 1))
          Enum.at(paragraph_indices, target_para - 1)
        end)
        |> Enum.uniq()
        |> ensure_spacing(paragraph_indices)

      # Pair tweets with insertion points (if fewer valid spots than tweets, append extras at end)
      paired = Enum.zip(insert_after_indices, tweet_nodes)
      leftover = Enum.drop(tweet_nodes, length(insert_after_indices))

      # Build result by inserting tweets after their target indices
      insert_map = Map.new(paired)

      result =
        content_nodes
        |> Enum.with_index()
        |> Enum.flat_map(fn {node, i} ->
          case Map.get(insert_map, i) do
            nil -> [node]
            tweet -> [node, tweet]
          end
        end)

      result ++ leftover
    end
  end

  @doc """
  Insert a single tweet into content that may already contain tweets.
  Places it at the best available gap — the largest stretch of content
  without a tweet.
  """
  def insert_tweet(content_nodes, tweet_node) do
    # Find existing tweet positions and paragraph positions
    indexed = Enum.with_index(content_nodes)

    tweet_positions =
      indexed
      |> Enum.filter(fn {node, _} -> node["type"] == "tweet" end)
      |> Enum.map(fn {_, i} -> i end)

    para_positions =
      indexed
      |> Enum.filter(fn {node, _} -> node["type"] == "paragraph" end)
      |> Enum.map(fn {_, i} -> i end)

    if para_positions == [] do
      content_nodes ++ [tweet_node]
    else
      # Find the best paragraph to insert after — the one in the largest gap between tweets
      best_position = find_best_gap(para_positions, tweet_positions, length(content_nodes))

      # Insert after the chosen paragraph
      {before, after_nodes} = Enum.split(content_nodes, best_position + 1)
      before ++ [tweet_node] ++ after_nodes
    end
  end

  # Find the paragraph position in the largest gap between existing tweets
  defp find_best_gap(para_positions, [], total_length) do
    # No existing tweets — pick a paragraph roughly 1/3 through
    target = length(para_positions) |> div(3) |> max(1)
    Enum.at(para_positions, target, List.last(para_positions))
  end

  defp find_best_gap(para_positions, tweet_positions, total_length) do
    # Create boundaries: [0, tweet1, tweet2, ..., end]
    boundaries = [-1 | tweet_positions] ++ [total_length]

    # Find the largest gap between consecutive boundaries
    gaps =
      boundaries
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> {a, b, b - a} end)
      |> Enum.sort_by(fn {_, _, size} -> -size end)

    # For the largest gap, find a paragraph near its midpoint
    {gap_start, gap_end, _} = List.first(gaps)
    midpoint = div(gap_start + gap_end, 2)

    # Pick the paragraph closest to the midpoint (but inside the gap)
    para_positions
    |> Enum.filter(fn p -> p > gap_start and p < gap_end end)
    |> Enum.min_by(fn p -> abs(p - midpoint) end, fn ->
      # Fallback: no paragraph in this gap, use the last paragraph
      List.last(para_positions)
    end)
  end

  # Ensure no two insertion points are adjacent (at least 2 nodes apart)
  defp ensure_spacing(indices, paragraph_indices) do
    indices
    |> Enum.reduce([], fn idx, acc ->
      case acc do
        [] -> [idx]
        [prev | _] ->
          if idx - prev < 3 do
            # Too close, try to find a later paragraph
            next = Enum.find(paragraph_indices, fn p -> p > prev + 2 end)
            if next && next not in acc, do: [next | acc], else: acc
          else
            [idx | acc]
          end
      end
    end)
    |> Enum.reverse()
  end
end
