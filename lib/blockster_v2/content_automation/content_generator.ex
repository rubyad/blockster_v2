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
    prompt = build_prompt_for_type(topic, source_items, persona, has_premium)
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
    # Collect verified source URLs from feed items for revision context
    source_urls = (topic.feed_items || [])
      |> Enum.filter(& &1.url)
      |> Enum.map(fn item -> %{source: item.source, title: item.title, url: item.url} end)

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
        featured_image: article[:featured_image],
        source_urls: source_urls
      },
      author_id: persona.user_id,
      topic_id: topic.id,
      pipeline_id: pipeline_id,
      status: "pending",
      content_type: topic.content_type || "news",
      offer_type: topic.offer_type
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

  # ── On-Demand Generation ──

  @doc """
  Generate an article from admin-provided details (no RSS feed items needed).

  Accepts a map with:
    - `topic` (string, required) — what the article is about
    - `category` (string, required)
    - `instructions` (string, required) — detailed context, links, data points
    - `angle` (string, optional) — editorial perspective
    - `author_id` (integer, optional) — override author selection
    - `content_type` (string, optional) — "news", "opinion", or "offer"

  Returns `{:ok, queue_entry}` or `{:error, reason}`.
  """
  def generate_on_demand(params) do
    category = params.category || "defi"
    content_type = params[:content_type] || "opinion"

    author_result =
      if params[:author_id] do
        persona = Enum.find(AuthorRotator.personas(), fn p ->
          case AuthorRotator.select_for_category(category) do
            {:ok, %{user_id: uid}} -> uid == params[:author_id]
            _ -> false
          end
        end)

        if persona do
          {:ok, Map.put(persona, :user_id, params[:author_id])}
        else
          # Fall back to category-based selection
          AuthorRotator.select_for_category(category)
        end
      else
        AuthorRotator.select_for_category(category)
      end

    case author_result do
      {:ok, persona} ->
        pipeline_id = "on_demand_#{System.system_time(:millisecond)}"
        Logger.info("[ContentGenerator] On-demand generation: \"#{params.topic}\" by #{persona.username}")
        do_generate_on_demand(params, persona, pipeline_id, content_type)

      {:error, :no_author_found} ->
        Logger.error("[ContentGenerator] No author found for on-demand generation")
        {:error, :no_author_found}
    end
  end

  defp do_generate_on_demand(params, persona, pipeline_id, content_type) do
    prompt = build_on_demand_prompt(params, persona, content_type)
    tools = PromptSchemas.article_output_schema()

    case ClaudeClient.call_with_tools(prompt, tools,
      model: Config.content_model(),
      temperature: 0.7,
      max_tokens: 16_384
    ) do
      {:ok, article_data} ->
        process_on_demand_output(article_data, params, persona, pipeline_id, content_type)

      {:error, reason} ->
        Logger.error("[ContentGenerator] pipeline=#{pipeline_id} On-demand Claude API error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_on_demand_output(article_data, params, persona, pipeline_id, content_type) do
    sections = article_data["sections"] || []
    tiptap_content = TipTapBuilder.build(sections)

    article = %{
      title: article_data["title"],
      excerpt: article_data["excerpt"],
      content: tiptap_content,
      tags: article_data["tags"] || [],
      category: params.category,
      image_search_queries: article_data["image_search_queries"] || [],
      tweet_suggestions: article_data["tweet_suggestions"] || [],
      promotional_tweet: article_data["promotional_tweet"]
    }

    case QualityChecker.validate(article) do
      :ok ->
        article = TweetFinder.find_and_embed_tweets(article)
        image_candidates = ImageFinder.find_image_candidates(article.image_search_queries, pipeline_id)
        article = Map.put(article, :image_candidates, image_candidates)

        article =
          if image_candidates != [] do
            Map.put(article, :featured_image, hd(image_candidates).url)
          else
            article
          end

        enqueue_on_demand_article(article, params, persona, pipeline_id, content_type)

      {:reject, failures} ->
        # For on-demand, enqueue even if quality check fails — admin explicitly requested it
        Logger.warning("[ContentGenerator] pipeline=#{pipeline_id} On-demand quality warnings: #{inspect(failures)}")
        enqueue_on_demand_article(article, params, persona, pipeline_id, content_type)
    end
  end

  defp enqueue_on_demand_article(article, params, persona, pipeline_id, content_type) do
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
        featured_image: article[:featured_image],
        source_urls: [],
        on_demand: true,
        admin_instructions: params.instructions
      },
      author_id: persona.user_id,
      pipeline_id: pipeline_id,
      status: "pending",
      content_type: content_type
    }

    case FeedStore.enqueue_article(attrs) do
      {:ok, entry} ->
        word_count = TipTapBuilder.count_words(article.content)

        Logger.info(
          "[ContentGenerator] pipeline=#{pipeline_id} On-demand enqueued: \"#{article.title}\" " <>
          "(#{word_count} words)"
        )

        Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "content_automation", {:content_automation, :article_enqueued, entry})
        {:ok, entry}

      {:error, changeset} ->
        Logger.error("[ContentGenerator] pipeline=#{pipeline_id} Failed to enqueue on-demand: #{inspect(changeset.errors)}")
        {:error, :enqueue_failed}
    end
  end

  defp build_on_demand_prompt(params, persona, content_type) do
    base_prompt = case content_type do
      "news" -> build_on_demand_news_prompt(params, persona)
      "offer" -> build_on_demand_offer_prompt(params, persona)
      _ -> build_on_demand_opinion_prompt(params, persona)
    end

    base_prompt <> "\n" <> EditorialFeedback.build_memory_prompt_block()
  end

  defp build_on_demand_opinion_prompt(params, persona) do
    angle_section = if params[:angle] && params.angle != "" do
      "\nANGLE TO TAKE:\n#{params.angle}"
    else
      ""
    end

    """
    You are #{persona.username}, a #{persona.bio} writing for Blockster, a crypto news
    and commentary platform with a pro-decentralization, pro-individual-liberty editorial stance.

    VOICE & STYLE:
    - #{persona.style}
    - Opinionated and direct. You believe in decentralization, sound money, and individual freedom.
    - Use concrete examples and data when available.
    - Conversational but authoritative. Occasional wit and sarcasm.
    - Write a substantial article (700-1000 words)

    CONTENT SAFETY:
    - NEVER recommend buying, selling, or holding specific tokens.
    - Base all claims on the provided details. Evidence-based, not speculation.

    FORMATTING RULES:
    - Use "paragraph" for body text. Use markdown **bold** and *italic* for emphasis.
    - Use "heading" (level 2 or 3) for section breaks.
    - Use "blockquote" for key quotes or highlighted points.
    - Use "bullet_list" or "ordered_list" for lists.
    - Keep paragraphs focused — 2-4 sentences each.

    LINKING RULES:
    - ONLY use URLs explicitly provided in the admin instructions below.
    - NEVER fabricate or guess URLs.

    TOPIC:
    #{params.topic}

    ADMIN-PROVIDED DETAILS AND SOURCE MATERIAL:
    #{params.instructions}
    #{angle_section}
    """
  end

  defp build_on_demand_news_prompt(params, _persona) do
    """
    You are a professional crypto journalist writing for Blockster, a web3 news platform.

    VOICE & STYLE:
    - Neutral, factual, and professional. Report the news — do not editorialize.
    - Clear, concise language. Lead with the most important facts.
    - Write a focused article (500-800 words)

    FORMATTING RULES:
    - Use "paragraph" for body text. Use markdown **bold** and *italic* for emphasis.
    - Use "heading" (level 2 or 3) for section breaks.
    - Use "blockquote" for key quotes.
    - Use "bullet_list" or "ordered_list" for lists.

    LINKING RULES:
    - ONLY use URLs explicitly provided in the admin instructions below.
    - NEVER fabricate or guess URLs.

    TOPIC:
    #{params.topic}

    ADMIN-PROVIDED DETAILS AND SOURCE MATERIAL:
    #{params.instructions}
    """
  end

  defp build_on_demand_offer_prompt(params, _persona) do
    """
    You are a helpful DeFi/crypto researcher writing for Blockster. Explain this opportunity
    clearly so readers can make an informed decision.

    VOICE & STYLE:
    - Neutral, factual, and helpful. You are NOT selling anything.
    - Be specific with numbers: APY, TVL, minimum deposits, fee structures.
    - Write a focused article (400-600 words)

    STRUCTURE:
    1. The Opportunity — What is it? What are the terms?
    2. How It Works — Step-by-step instructions.
    3. The Risks — Smart contract risk, impermanent loss, regulatory risk.
    4. Timeline — When does it start/end?
    5. Bottom Line — Who this is for and who should skip it.

    MANDATORY:
    - Include "This is not financial advice. Always do your own research." at the end.

    FORMATTING RULES:
    - Use "paragraph" for body text. Use markdown **bold** and *italic* for emphasis.
    - Use "heading" (level 2 or 3) for each section.
    - Use "bullet_list" or "ordered_list" for steps.

    LINKING RULES:
    - ONLY use URLs explicitly provided in the admin instructions below.

    TOPIC:
    #{params.topic}

    ADMIN-PROVIDED DETAILS AND SOURCE MATERIAL:
    #{params.instructions}
    """
  end

  # ── Prompt Construction ──

  defp build_prompt_for_type(topic, source_items, persona, has_premium) do
    case topic.content_type do
      "news" -> build_news_prompt(topic, source_items, persona, has_premium)
      "offer" -> build_offer_prompt(topic, source_items, persona, has_premium)
      _ -> build_opinion_prompt(topic, source_items, persona, has_premium)
    end
  end

  defp build_opinion_prompt(topic, source_items, persona, has_premium) do
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
      You see the humor in things. You are an optimist, not a complainer.
    - #{word_target}

    STRUCTURAL VARIETY (rotate between these approaches — do NOT always use the same structure):
    - Data-first: Lead with numbers, stats, or on-chain data. Let the data tell the story.
    - Narrative: Tell the story of a specific project, person, or event chronologically.
    - Analysis: Deep-dive into what happened and why it matters.
    - Opinion: State your position upfront and defend it with evidence.
    - Trend report: Survey multiple related developments and identify the pattern.

    DO NOT default to the "here's the problem... but actually it's good" structure. This negative-
    then-positive seesaw pattern is overused. Mix it up. Not every article needs a counter-narrative.
    Sometimes lead with opportunity, sometimes with analysis, sometimes with data.

    BANNED PHRASES (never use these):
    - "Let that sink in" — cliché
    - "X is a feature, not a bug" — overused in crypto writing
    - "And that's the point." — overused mic drop
    - "In the world of crypto..." — generic opening
    - "The crypto community is buzzing..." — generic opening

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
    - CRITICAL: ONLY use URLs from the SOURCE MATERIAL list above. Each source includes a verified URL.
      NEVER fabricate, guess, or hallucinate URLs. If you cannot find a URL for a claim, state the
      fact without linking it.
    - Use markdown link syntax: [text](url)
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

  defp build_news_prompt(topic, source_items, _persona, has_premium) do
    word_target =
      if has_premium,
        do: "Write a substantial ~3-4 minute read (700-1000 words) with deeper context",
        else: "Write a focused ~2 minute read (400-500 words)"

    source_material = format_source_summaries(source_items)

    """
    You are a professional crypto journalist writing for Blockster, a web3 news platform.

    VOICE & STYLE:
    - Neutral, factual, and professional. Report the news — do not editorialize.
    - Use clear, concise language. Lead with the most important facts.
    - Attribute claims to their sources. Use direct quotes where available.
    - DO NOT inject personal opinions, predictions, or crypto-optimist framing.
    - DO NOT use phrases like "this is bullish", "this could be huge", "exciting development".
    - #{word_target}

    STRUCTURE:
    1. Lead with the key news (who, what, when, where, why) in the first paragraph
    2. Follow with supporting details, context, and background
    3. Include relevant data points, numbers, and quotes
    4. End with implications or what to watch next — NOT with an opinion

    TONE: Think Reuters or Bloomberg crypto desk, not a crypto influencer blog.

    FORMATTING RULES:
    - Use "paragraph" for body text. Use markdown **bold** and *italic* for emphasis within text.
    - Use "heading" (level 2 or 3) for section breaks — don't overuse headings.
    - Use "blockquote" for key quotes or highlighted points.
    - Use "bullet_list" or "ordered_list" with "items" array for lists.
    - Do NOT use "spacer" — headings provide enough visual separation.
    - Keep paragraphs focused — 2-4 sentences each.

    LINKING RULES:
    - CRITICAL: ONLY use URLs from the SOURCE MATERIAL list above. NEVER fabricate URLs.
    - Use markdown link syntax: [text](url)
    - Link to PRIMARY SOURCES: official announcements, research papers, project websites.
    - Aim for 2-4 external links per article.

    TOPIC:
    #{topic.title}

    SOURCE MATERIAL (use for facts, DO NOT copy phrasing):
    #{source_material}

    KEY DATA POINTS:
    #{topic.key_facts || "Not available — synthesize from sources"}
    #{EditorialFeedback.build_memory_prompt_block()}
    """
  end

  defp build_offer_prompt(topic, source_items, _persona, _has_premium) do
    source_material = format_source_summaries(source_items)

    """
    You are a helpful DeFi/crypto researcher writing for Blockster. Your job is to explain
    an opportunity clearly so readers can make an informed decision.

    VOICE & STYLE:
    - Neutral, factual, and helpful. You are NOT selling anything.
    - Explain like you're talking to a friend who's crypto-literate but hasn't seen this yet.
    - DO NOT use hype language ("This is huge!", "Don't miss out!", "To the moon!").
    - DO NOT guarantee returns or imply risk-free profit.
    - Be specific with numbers: APY, TVL, minimum deposits, fee structures.
    - Write a focused ~2 minute read (400-600 words)

    STRUCTURE (follow this order):
    1. **The Opportunity** — What is it? Who's offering it? What are the terms?
       Lead with the most important number (APY, discount %, reward amount).
    2. **How It Works** — Step-by-step for someone who wants to participate.
       Be specific: which wallet, which chain, which pool/market.
    3. **The Risks** — Smart contract risk, impermanent loss, regulatory risk,
       protocol track record, audit status. Be thorough and honest.
    4. **Timeline** — When does it start? When does it end? Is it ongoing?
       If time-limited, make the deadline prominent.
    5. **Bottom Line** — One-sentence summary of who this is good for and who should skip it.

    MANDATORY:
    - Include "This is not financial advice. Always do your own research." at the end.
    - If the APY/reward seems unsustainably high, say so explicitly.
    - Link to the actual protocol/exchange page where readers can take action.
    - Mention the chain (Ethereum, Arbitrum, etc.) and any gas cost implications.

    FORMATTING RULES:
    - Use "paragraph" for body text. Use markdown **bold** and *italic* for emphasis.
    - Use "heading" (level 2 or 3) for each section.
    - Use "bullet_list" or "ordered_list" for steps and risk items.
    - Keep paragraphs focused — 2-4 sentences each.

    LINKING RULES:
    - CRITICAL: ONLY use URLs from the SOURCE MATERIAL list. NEVER fabricate URLs.
    - Use markdown link syntax: [text](url)

    TOPIC:
    #{topic.title}

    SOURCE MATERIAL:
    #{source_material}

    KEY DATA POINTS:
    #{topic.key_facts || "Not available — synthesize from sources"}
    #{EditorialFeedback.build_memory_prompt_block()}
    """
  end

  defp format_source_summaries(source_items) do
    source_items
    |> Enum.map(fn item ->
      tier_label = if item.tier == "premium", do: "[PREMIUM] ", else: ""
      summary = truncate(item.summary, 300)
      url_line = if item.url, do: "\nURL: #{item.url}", else: ""
      "#{tier_label}#{item.source}: #{item.title}#{url_line}\n#{summary}"
    end)
    |> Enum.join("\n\n")
  end

  defp truncate(nil, _max), do: ""
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max)

end
