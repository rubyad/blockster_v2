defmodule BlocksterV2.ContentAutomation.QualityChecker do
  @moduledoc """
  Validates generated articles before they enter the publish queue.
  Returns `:ok` or `{:reject, failures}` with a list of check failures.

  Automated checks only — human review (originality, hallucinations, tone)
  happens during admin queue review.
  """

  alias BlocksterV2.ContentAutomation.{FeedStore, TipTapBuilder}

  @min_words 350
  @max_words 1200
  @min_paragraphs 3
  @min_tags 2
  @max_tags 5
  @dedup_overlap_threshold 0.6

  @doc """
  Run all quality checks on an article map.

  Expects a map with keys: :title, :excerpt, :content (TipTap JSON), :tags.
  """
  def validate(article) do
    checks = [
      {:word_count, check_word_count(article)},
      {:structure, check_structure(article)},
      {:duplicate, check_not_duplicate(article)},
      {:tags, check_tags(article)},
      {:tiptap_valid, check_tiptap_format(article)}
    ]

    failures = Enum.reject(checks, fn {_, result} -> result == :ok end)

    if Enum.empty?(failures), do: :ok, else: {:reject, failures}
  end

  defp check_word_count(article) do
    count = TipTapBuilder.count_words(article.content)

    cond do
      count < @min_words -> {:fail, "Too short: #{count} words (min #{@min_words})"}
      count > @max_words -> {:fail, "Too long: #{count} words (max #{@max_words})"}
      true -> :ok
    end
  end

  defp check_structure(article) do
    nodes = get_in(article.content, ["content"]) || []
    paragraphs = Enum.count(nodes, &(&1["type"] == "paragraph"))

    cond do
      is_nil(article.title) or article.title == "" ->
        {:fail, "Missing title"}

      is_nil(article.excerpt) or article.excerpt == "" ->
        {:fail, "Missing excerpt"}

      paragraphs < @min_paragraphs ->
        {:fail, "Only #{paragraphs} paragraphs (min #{@min_paragraphs})"}

      true ->
        :ok
    end
  end

  defp check_not_duplicate(%{title: nil}), do: :ok
  defp check_not_duplicate(%{title: ""}), do: :ok

  defp check_not_duplicate(article) do
    recent_titles = FeedStore.get_generated_topic_titles(days: 7)
    title_words = significant_words(article.title)

    is_dup =
      Enum.any?(recent_titles, fn recent ->
        recent_words = significant_words(recent)
        overlap = MapSet.intersection(title_words, recent_words) |> MapSet.size()
        min_size = min(MapSet.size(title_words), MapSet.size(recent_words))
        min_size > 0 and overlap / min_size > @dedup_overlap_threshold
      end)

    if is_dup, do: {:fail, "Too similar to recent article"}, else: :ok
  end

  defp check_tags(article) do
    tags = article.tags || []

    cond do
      length(tags) < @min_tags -> {:fail, "Only #{length(tags)} tags (min #{@min_tags})"}
      length(tags) > @max_tags -> {:fail, "#{length(tags)} tags (max #{@max_tags})"}
      true -> :ok
    end
  end

  defp check_tiptap_format(article) do
    case article.content do
      %{"type" => "doc", "content" => nodes} when is_list(nodes) -> :ok
      _ -> {:fail, "Invalid TipTap JSON format"}
    end
  end

  @stopwords ~w(the a an is are was were be been being have has had do does did
    will would shall should may might can could of in to for on with
    at by from as into about between through after before its this that
    their they them these those and or but not no nor so yet also just)

  defp significant_words(title) do
    title
    |> String.downcase()
    |> String.split(~r/\W+/, trim: true)
    |> Enum.reject(&(&1 in @stopwords))
    |> MapSet.new()
  end
end
