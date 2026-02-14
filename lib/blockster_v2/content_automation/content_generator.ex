defmodule BlocksterV2.ContentAutomation.ContentGenerator do
  @moduledoc """
  Generates original articles from topics using Claude.

  Stateless module (not a GenServer) — called by TopicEngine after topic selection.
  Pipeline: load topic → build prompt → Claude API → TipTap conversion → quality check → enqueue.
  """

  require Logger

  alias BlocksterV2.ContentAutomation.{
    AuthorRotator,
    ClaudeClient,
    Config,
    EditorialFeedback,
    FeedStore,
    ImageFinder,
    PromptSchemas,
    QualityChecker,
    TipTapBuilder,
    TweetFinder
  }

  @doc """
  Generate an article for a topic and enqueue it for admin review.

  The topic must have its feed_items preloaded (source material for the prompt).
  Returns `{:ok, queue_entry}` or `{:error, reason}`.
  """
  def generate_article(%{id: topic_id, pipeline_id: pipeline_id} = topic) do
    Logger.info("[ContentGenerator] pipeline=#{pipeline_id} Starting generation for: \"#{topic.title}\"")

    source_items = topic.feed_items || []

    if Enum.empty?(source_items) do
      Logger.warning("[ContentGenerator] pipeline=#{pipeline_id} No source items for topic #{topic_id}")
      {:error, :no_source_items}
    else
      # Select an author persona for this topic's category
      case AuthorRotator.select_for_category(topic.category) do
        {:ok, persona} ->
          Logger.info("[ContentGenerator] pipeline=#{pipeline_id} Author: #{persona.username}")
          do_generate(topic, source_items, persona, pipeline_id)

        {:error, :no_author_found} ->
          Logger.error("[ContentGenerator] pipeline=#{pipeline_id} No author account found — run seeds first")
          {:error, :no_author_found}
      end
    end
  end

  defp do_generate(topic, source_items, persona, pipeline_id) do
    has_premium = Enum.any?(source_items, &(&1.tier == "premium"))
    prompt = build_generation_prompt(topic, source_items, persona, has_premium)
    tools = PromptSchemas.article_output_schema()

    case ClaudeClient.call_with_tools(prompt, tools,
      model: Config.content_model(),
      temperature: 0.7,
      max_tokens: 16_384
    ) do
      {:ok, article_data} ->
        process_claude_output(article_data, topic, persona, pipeline_id)

      {:error, reason} ->
        Logger.error("[ContentGenerator] pipeline=#{pipeline_id} Claude API error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── Process Claude Output ──

  defp process_claude_output(article_data, topic, persona, pipeline_id) do
    sections = article_data["sections"] || []
    tiptap_content = TipTapBuilder.build(sections)

    article = %{
      title: article_data["title"],
      excerpt: article_data["excerpt"],
      content: tiptap_content,
      tags: article_data["tags"] || [],
      category: topic.category,
      image_search_queries: article_data["image_search_queries"] || [],
      tweet_suggestions: article_data["tweet_suggestions"] || [],
      promotional_tweet: article_data["promotional_tweet"]
    }

    # Quality check first (before spending X API calls on tweets)
    case QualityChecker.validate(article) do
      :ok ->
        # Embed third-party tweets into the article content (if X API is configured)
        article = TweetFinder.find_and_embed_tweets(article)

        # Find featured image candidates (X API primary, Unsplash fallback)
        image_candidates = ImageFinder.find_image_candidates(article.image_search_queries, pipeline_id)
        article = Map.put(article, :image_candidates, image_candidates)

        # Auto-select best candidate as featured_image (admin can override in review)
        article =
          if image_candidates != [] do
            Map.put(article, :featured_image, hd(image_candidates).url)
          else
            article
          end

        enqueue_article(article, topic, persona, pipeline_id)

      {:reject, failures} ->
        failure_reasons = Enum.map_join(failures, ", ", fn {check, {:fail, msg}} -> "#{check}: #{msg}" end)
        Logger.warning("[ContentGenerator] pipeline=#{pipeline_id} Quality check failed: #{failure_reasons}")
        enqueue_rejected(article, topic, persona, pipeline_id, failure_reasons)
    end
  end

  defp enqueue_article(article, topic, persona, pipeline_id) do
    attrs = %{
      article_data: %{
        title: article.title,
        excerpt: article.excerpt,
        content: article.content,
        tags: article.tags,
        category: article.category,
        image_search_queries: article.image_search_queries,
        tweet_suggestions: article.tweet_suggestions,
        promotional_tweet: article.promotional_tweet,
        author_username: persona.username,
        image_candidates: article[:image_candidates] || [],
        featured_image: article[:featured_image]
      },
      author_id: persona.user_id,
      topic_id: topic.id,
      pipeline_id: pipeline_id,
      status: "pending"
    }

    case FeedStore.enqueue_article(attrs) do
      {:ok, entry} ->
        word_count = TipTapBuilder.count_words(article.content)

        Logger.info(
          "[ContentGenerator] pipeline=#{pipeline_id} Enqueued: \"#{article.title}\" " <>
          "(#{word_count} words, #{length(article.tags)} tags)"
        )

        Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "content_automation", {:content_automation, :article_enqueued, entry})
        {:ok, entry}

      {:error, changeset} ->
        Logger.error("[ContentGenerator] pipeline=#{pipeline_id} Failed to enqueue: #{inspect(changeset.errors)}")
        {:error, :enqueue_failed}
    end
  end

  defp enqueue_rejected(article, topic, persona, pipeline_id, reasons) do
    # Store rejected articles too so admin can see what was rejected and why
    attrs = %{
      article_data: %{
        title: article.title,
        excerpt: article.excerpt,
        content: article.content,
        tags: article.tags,
        category: article.category
      },
      author_id: persona.user_id,
      topic_id: topic.id,
      pipeline_id: pipeline_id,
      status: "rejected",
      rejected_reason: reasons
    }

    FeedStore.enqueue_article(attrs)
    {:error, {:quality_rejected, reasons}}
  end

  # ── Prompt Construction ──

  defp build_generation_prompt(topic, source_items, persona, has_premium) do
    word_target =
      if has_premium,
        do: "Write a substantial ~3-4 minute read (700-1000 words) with deeper analysis",
        else: "Write a focused ~2 minute read (400-500 words)"

    source_material = format_source_summaries(source_items)

    """
    You are #{persona.username}, a #{persona.bio} writing for Blockster, a crypto news
    and commentary platform with a pro-decentralization, pro-individual-liberty editorial stance.

    VOICE & STYLE:
    - #{persona.style}
    - Opinionated and direct. You believe in decentralization, sound money, and individual freedom.
    - Skeptical of government regulation, central banks, and surveillance.
    - Not conspiracy theory territory — informed, evidence-based skepticism.
    - Use concrete examples and data when available.
    - Conversational but authoritative. Occasional wit and sarcasm.
    - POSITIVE AND OPTIMISTIC — you are enthusiastic about the future of crypto and decentralization.
      You point out problems but always offer solutions or silver linings. You see the humor in things.
      You are an optimist, not a complainer. Even when criticizing, the tone is "here's why this is
      actually good for us" or "here's what we can do about it" — never doom and gloom.
    - NEVER use the phrase "Let that sink in" — it is overused and cliché.
    - #{word_target}

    CONTENT SAFETY:
    - NEVER recommend buying, selling, or holding specific tokens. No "buy the dip", "this will moon", etc.
    - NEVER predict specific prices or guaranteed returns.
    - Base all claims on facts from source material. Evidence-based skepticism, not conspiracy.
    - Do NOT start the article with generic openings like "In the world of crypto..." or
      "The crypto community is buzzing..." — use a specific, surprising hook every time.

    COUNTER-NARRATIVE FRAMING:
    - When source material comes from mainstream financial press (Bloomberg, FT, Reuters,
      The Economist, Forbes, TechCrunch, The Verge), these outlets often frame crypto stories
      through a pro-regulation, pro-institution, or statist lens.
    - Your job is to take their reporting (which is often excellent factually) and reframe it
      through a pro-freedom, pro-decentralization perspective.
    - Example: If Bloomberg reports "SEC moves to regulate DeFi protocols" with a tone of
      inevitability and approval, you should report the same facts but question whether this
      regulation serves individuals or incumbents, and highlight what freedoms are at stake.
    - When a mainstream source quotes a central banker or regulator approvingly, push back.
      What are they not saying? Who benefits from their proposals?
    - Use the credibility of these sources against them: "Even Bloomberg admits that..." or
      "The FT buried the lede here..." — leverage their authority while challenging their framing.

    ARTICLE STRUCTURE:
    1. Hook: Start with a provocative observation or the most interesting angle
    2. Context: Brief background (2-3 sentences, assume reader knows crypto basics)
    3. Analysis: Your take on what this means (this is the meat — be opinionated)
    4. Implications: What should crypto natives care about? What comes next?
    5. Closing: Punchy one-liner or call to action

    FORMATTING RULES:
    - Use "paragraph" for body text. Use markdown **bold** and *italic* for emphasis within text.
    - Use "heading" (level 2 or 3) for section breaks — don't overuse headings.
    - Use "blockquote" for key quotes or highlighted points.
    - Use "bullet_list" or "ordered_list" with "items" array for lists.
    - Do NOT use "spacer" — headings provide enough visual separation.
    - Keep paragraphs focused — 2-4 sentences each.

    LINKING RULES:
    - Include external links to back up claims and data points. Use markdown link syntax: [text](url)
    - Link to PRIMARY SOURCES: company blogs, official announcements, research papers, government
      documents, project websites, GitHub repos, on-chain data explorers.
    - DO NOT link to competing crypto media outlets (CoinDesk, The Block, Decrypt, CoinTelegraph,
      Bitcoin Magazine, etc.) — link to the original source they reported on instead.
    - Mainstream financial press links (Bloomberg, Reuters, FT) are OK when they are the source
      of the story you're reframing.
    - When referencing a project, protocol, or company, link to their official website or blog post.
    - Aim for 2-4 external links per article to add credibility and let readers dig deeper.

    #{premium_instruction(has_premium)}

    TOPIC:
    #{topic.title}

    SOURCE MATERIAL (use for facts only, DO NOT copy phrasing):
    #{source_material}

    KEY DATA POINTS:
    #{topic.key_facts || "Not available — synthesize from sources"}

    ANGLE TO TAKE:
    #{topic.selected_angle || List.first(topic.angles || []) || "Find the most interesting angle from the sources"}
    #{EditorialFeedback.build_memory_prompt_block()}
    """
  end

  defp premium_instruction(true) do
    """
    NOTE: This topic is sourced from premium mainstream outlets. Write a more substantial
    article — include deeper analysis and explicitly engage with the mainstream framing.
    Quote or reference the source outlet by name where it adds credibility or contrast.
    """
  end

  defp premium_instruction(false), do: ""

  defp format_source_summaries(source_items) do
    source_items
    |> Enum.map(fn item ->
      tier_label = if item.tier == "premium", do: "[PREMIUM] ", else: ""
      summary = truncate(item.summary, 300)
      "#{tier_label}#{item.source}: #{item.title}\n#{summary}"
    end)
    |> Enum.join("\n\n")
  end

  defp truncate(nil, _max), do: ""
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max)

end
