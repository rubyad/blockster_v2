defmodule BlocksterV2.Notifications.ContentSelector do
  @moduledoc """
  Selects and ranks articles for a specific user based on their profile.
  Used by: Daily Digest, Hub Post Alerts, Recommendations, Re-engagement.
  """

  import Ecto.Query
  alias BlocksterV2.{Repo, Blog, UserEvents}

  @doc """
  Select the best N articles for a user based on their profile.
  Returns articles ranked by personalized relevance score.

  Options:
  - count: number of articles (default 5)
  - since: only articles published since (default 1 day ago)
  - pool: :all, :hub_subscriptions, :trending (default :all)
  """
  def select_articles(user_id, opts \\ []) do
    count = Keyword.get(opts, :count, 5)
    since = Keyword.get(opts, :since, days_ago(1))
    pool = Keyword.get(opts, :pool, :all)

    profile = UserEvents.get_profile(user_id)
    candidates = get_candidate_pool(pool, user_id, since)

    # Read article IDs to exclude already-read ones
    read_ids = get_read_article_ids(user_id)

    candidates
    |> Enum.map(fn article ->
      score = calculate_relevance_score(article, profile)
      {article, score}
    end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> Enum.reject(fn {article, _} -> article.id in read_ids end)
    |> Enum.take(count)
    |> Enum.map(fn {article, _score} -> article end)
  end

  @doc """
  Calculate a personalized relevance score (0.0-1.0) for an article
  against a user profile.
  """
  def calculate_relevance_score(article, nil), do: calculate_base_score(article)
  def calculate_relevance_score(article, profile) do
    hub_score = hub_preference_score(article, profile)
    category_score = category_preference_score(article, profile)
    recency_score = recency_score(article)
    popularity_score = popularity_score(article)

    # Weighted scoring
    score =
      hub_score * 0.35 +
      category_score * 0.25 +
      recency_score * 0.25 +
      popularity_score * 0.15

    Float.round(min(max(score, 0.0), 1.0), 3)
  end

  # ============ Private: Candidate Pools ============

  defp get_candidate_pool(:hub_subscriptions, user_id, since) do
    hub_ids = Blog.get_user_followed_hub_ids(user_id)
    get_articles_from_hubs(hub_ids, since)
  end

  defp get_candidate_pool(:trending, _user_id, since) do
    get_trending_articles(since)
  end

  defp get_candidate_pool(:all, user_id, since) do
    hub_articles = get_candidate_pool(:hub_subscriptions, user_id, since)
    trending = get_trending_articles(since)
    Enum.uniq_by(hub_articles ++ trending, & &1.id)
  end

  defp get_articles_from_hubs([], _since), do: []
  defp get_articles_from_hubs(hub_ids, since) do
    from(p in BlocksterV2.Blog.Post,
      where: p.hub_id in ^hub_ids,
      where: not is_nil(p.published_at),
      where: p.published_at >= ^since,
      order_by: [desc: p.published_at],
      limit: 20,
      preload: [:hub]
    )
    |> Repo.all()
  end

  defp get_trending_articles(since) do
    from(p in BlocksterV2.Blog.Post,
      where: not is_nil(p.published_at),
      where: p.published_at >= ^since,
      order_by: [desc: p.published_at],
      limit: 20,
      preload: [:hub]
    )
    |> Repo.all()
  end

  # ============ Private: Score Components ============

  defp hub_preference_score(article, profile) do
    preferred_hubs = profile.preferred_hubs || []
    hub_id = article.hub_id

    case Enum.find(preferred_hubs, fn h -> h["id"] == hub_id end) do
      nil -> 0.0
      hub -> hub["score"] || 0.0
    end
  end

  defp category_preference_score(article, profile) do
    preferred_cats = profile.preferred_categories || []
    cat_id = article.category_id

    case Enum.find(preferred_cats, fn c -> c["id"] == cat_id end) do
      nil -> 0.0
      cat -> cat["score"] || 0.0
    end
  end

  defp recency_score(article) do
    published_at = article.published_at
    if is_nil(published_at) do
      0.0
    else
      hours_ago = NaiveDateTime.diff(NaiveDateTime.utc_now(), published_at, :hour)
      # Decay: 1.0 for <1h, 0.5 for 12h, ~0 for 48h+
      max(1.0 - (hours_ago / 48.0), 0.0)
    end
  end

  defp popularity_score(article) do
    views = Map.get(article, :view_count, 0) || 0
    # Logarithmic scale so it doesn't dominate
    min(:math.log10(max(views, 1)) / 4.0, 1.0)
  end

  defp calculate_base_score(article) do
    recency_score(article) * 0.6 + popularity_score(article) * 0.4
  end

  # ============ Private: Helpers ============

  defp get_read_article_ids(user_id) do
    from(e in BlocksterV2.Notifications.UserEvent,
      where: e.user_id == ^user_id,
      where: e.event_type in ["article_read_complete", "article_view"],
      where: e.target_type == "post",
      where: not is_nil(e.target_id),
      select: e.target_id,
      distinct: true
    )
    |> Repo.all()
    |> Enum.map(fn id ->
      case Integer.parse(id) do
        {int, _} -> int
        :error -> id
      end
    end)
  end

  defp days_ago(n) do
    NaiveDateTime.utc_now() |> NaiveDateTime.add(-n * 86400, :second)
  end
end
