defmodule BlocksterV2.ContentAutomation.EditorialFeedback do
  @moduledoc """
  Editorial feedback system for the content automation pipeline.

  Two capabilities:
  1. Article revision: Admin submits instruction → Claude revises → queue entry updated.
  2. Editorial memory: Admin saves brand preferences → injected into all future prompts.

  Stateless module — called by admin actions (LiveView or context functions).
  """

  require Logger

  alias BlocksterV2.Repo
  alias BlocksterV2.ContentAutomation.{
    AuthorRotator,
    ClaudeClient,
    Config,
    ContentEditorialMemory,
    ContentRevisionHistory,
    FeedStore,
    PromptSchemas,
    TipTapBuilder,
    TweetPlacer
  }
  import Ecto.Query

  # ── Article Revision ──

  @doc """
  Revise a queue entry based on admin feedback.

  Takes a queue entry ID and an instruction string. Calls Claude to revise the
  article, updates the queue entry, and records the revision in history.

  Options:
    - `:requested_by` — admin user ID (for audit trail)

  Returns `{:ok, updated_queue_entry}` or `{:error, reason}`.
  """
  def revise_article(queue_entry_id, instruction, opts \\ []) do
    requested_by = Keyword.get(opts, :requested_by)

    with {:ok, entry} <- load_revisable_entry(queue_entry_id),
         {:ok, revision} <- create_revision_record(entry, instruction, requested_by),
         {:ok, revised_article_data} <- call_claude_for_revision(entry, instruction),
         {:ok, updated_entry} <- apply_revision(entry, revised_article_data),
         {:ok, _revision} <- complete_revision(revision, revised_article_data) do
      Logger.info(
        "[EditorialFeedback] Revision #{revision.revision_number} completed " <>
        "for queue entry #{queue_entry_id}"
      )

      {:ok, updated_entry}
    else
      {:error, {:claude_revision_failed, _} = reason} = err ->
        Logger.error("[EditorialFeedback] Revision failed for #{queue_entry_id}: #{inspect(reason)}")
        # Try to mark revision as failed (best-effort)
        mark_latest_revision_failed(queue_entry_id, inspect(reason))
        err

      {:error, reason} = err ->
        Logger.error("[EditorialFeedback] Revision failed for #{queue_entry_id}: #{inspect(reason)}")
        err
    end
  end

  # ── Editorial Memory ──

  @doc """
  Add a new editorial memory entry. Applied to all future content generation.

  Options:
    - `:category` — "global" (default), "tone", "terminology", "topics", "formatting"
    - `:created_by` — admin user ID
    - `:source_queue_entry_id` — optional link to the article that inspired this rule
  """
  def add_memory(instruction, opts \\ []) do
    attrs = %{
      instruction: instruction,
      category: Keyword.get(opts, :category, "global"),
      created_by: Keyword.get(opts, :created_by),
      source_queue_entry_id: Keyword.get(opts, :source_queue_entry_id)
    }

    %ContentEditorialMemory{}
    |> ContentEditorialMemory.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  List all active editorial memory entries, optionally filtered by category.
  """
  def list_memories(opts \\ []) do
    category = Keyword.get(opts, :category)

    query = from(m in ContentEditorialMemory,
      where: m.active == true,
      order_by: [asc: m.inserted_at]
    )

    query =
      if category do
        where(query, [m], m.category == ^category)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Deactivate an editorial memory entry (soft delete).
  """
  def deactivate_memory(memory_id) do
    case Repo.get(ContentEditorialMemory, memory_id) do
      nil -> {:error, :not_found}
      memory ->
        memory
        |> Ecto.Changeset.change(%{active: false})
        |> Repo.update()
    end
  end

  @doc """
  Reactivate a previously deactivated memory entry.
  """
  def reactivate_memory(memory_id) do
    case Repo.get(ContentEditorialMemory, memory_id) do
      nil -> {:error, :not_found}
      memory ->
        memory
        |> Ecto.Changeset.change(%{active: true})
        |> Repo.update()
    end
  end

  @doc """
  Build the editorial memory block to inject into generation prompts.
  Returns a string (possibly empty if no memories exist).

  Called by ContentGenerator.build_generation_prompt/4.
  """
  def build_memory_prompt_block do
    memories = list_memories()

    if Enum.empty?(memories) do
      ""
    else
      entries =
        memories
        |> Enum.map(fn m ->
          category_label = if m.category != "global", do: "[#{m.category}] ", else: ""
          "- #{category_label}#{m.instruction}"
        end)
        |> Enum.join("\n")

      """

      EDITORIAL MEMORY (apply these rules to EVERY article):
      #{entries}
      """
    end
  end

  # ── Revision History Queries ──

  @doc """
  Get revision history for a queue entry, ordered by revision number.
  """
  def get_revision_history(queue_entry_id) do
    from(r in ContentRevisionHistory,
      where: r.queue_entry_id == ^queue_entry_id,
      order_by: [asc: r.revision_number],
      preload: [:requester]
    )
    |> Repo.all()
  end

  # ── Private: Revision Pipeline ──

  defp load_revisable_entry(queue_entry_id) do
    case FeedStore.get_queue_entry(queue_entry_id) do
      nil ->
        {:error, :not_found}

      %{status: status} = entry when status in ["pending", "draft"] ->
        {:ok, entry}

      %{status: status} ->
        {:error, {:not_revisable, status}}
    end
  end

  defp create_revision_record(entry, instruction, requested_by) do
    revision_number = (entry.revision_count || 0) + 1

    attrs = %{
      queue_entry_id: entry.id,
      instruction: instruction,
      revision_number: revision_number,
      article_data_before: entry.article_data,
      status: "pending",
      requested_by: requested_by
    }

    %ContentRevisionHistory{}
    |> ContentRevisionHistory.changeset(attrs)
    |> Repo.insert()
  end

  defp call_claude_for_revision(entry, instruction) do
    article_data = entry.article_data
    author_username = article_data["author_username"]
    persona = AuthorRotator.get_persona(author_username)

    prompt = build_revision_prompt(article_data, instruction, persona)
    tools = PromptSchemas.article_output_schema()

    case ClaudeClient.call_with_tools(prompt, tools,
      model: Config.content_model(),
      temperature: 0.5,
      max_tokens: 16_384
    ) do
      {:ok, revised_data} ->
        {:ok, revised_data}

      {:error, reason} ->
        {:error, {:claude_revision_failed, reason}}
    end
  end

  defp build_revision_prompt(article_data, instruction, persona) do
    persona_context =
      if persona do
        "You are #{persona.username}, a #{persona.bio}. Style: #{persona.style}"
      else
        "You are a Blockster editorial writer."
      end

    current_sections = reverse_tiptap_to_sections(article_data["content"])
    editorial_memory = build_memory_prompt_block()

    """
    #{persona_context}

    You previously wrote the following article for Blockster. An editor has requested changes.
    Apply the editor's instruction while preserving the article's voice, structure, and factual content
    unless the instruction specifically asks you to change those.
    #{editorial_memory}

    CURRENT ARTICLE:
    Title: #{article_data["title"]}
    Excerpt: #{article_data["excerpt"]}
    Tags: #{Enum.join(article_data["tags"] || [], ", ")}
    Category: #{article_data["category"]}

    Content:
    #{format_sections_for_prompt(current_sections)}

    #{format_source_urls_for_revision(article_data)}
    EDITOR'S INSTRUCTION:
    #{instruction}

    Rewrite the FULL article applying the editor's changes. Return the complete article
    (not just the changed parts). Keep the same general structure unless the instruction
    asks for structural changes.

    NOTE: Embedded tweets ([tweet: ...] markers above) are preserved automatically —
    do NOT try to include them in your sections output. Focus only on the text content.
    """
  end

  defp format_source_urls_for_revision(article_data) do
    case article_data["source_urls"] do
      urls when is_list(urls) and urls != [] ->
        url_lines = Enum.map_join(urls, "\n", fn u ->
          "- #{u["source"]}: #{u["title"]} — #{u["url"]}"
        end)

        """
        SOURCE URLs (VERIFIED — use these for any link corrections):
        #{url_lines}

        CRITICAL: Only use URLs from this list. NEVER fabricate or guess URLs.
        """

      _ ->
        ""
    end
  end

  defp apply_revision(entry, revised_claude_data) do
    sections = revised_claude_data["sections"] || []
    tiptap_content = TipTapBuilder.build(sections)

    # Preserve tweet nodes from original content — Claude can't output them
    # because the schema doesn't include "tweet" type
    tiptap_content = reinsert_tweet_nodes(entry.article_data["content"], tiptap_content)

    updated_article_data =
      entry.article_data
      |> Map.put("title", revised_claude_data["title"])
      |> Map.put("excerpt", revised_claude_data["excerpt"])
      |> Map.put("content", tiptap_content)
      |> Map.put("tags", revised_claude_data["tags"] || entry.article_data["tags"])
      |> Map.put("promotional_tweet", revised_claude_data["promotional_tweet"] || entry.article_data["promotional_tweet"])
      |> Map.put("image_search_queries", revised_claude_data["image_search_queries"] || entry.article_data["image_search_queries"])

    new_revision_count = (entry.revision_count || 0) + 1

    entry
    |> Ecto.Changeset.change(%{
      article_data: updated_article_data,
      revision_count: new_revision_count
    })
    |> Repo.update()
  end

  defp complete_revision(revision, revised_article_data) do
    sections = revised_article_data["sections"] || []
    tiptap_content = TipTapBuilder.build(sections)

    after_data = %{
      "title" => revised_article_data["title"],
      "excerpt" => revised_article_data["excerpt"],
      "content" => tiptap_content,
      "tags" => revised_article_data["tags"]
    }

    revision
    |> Ecto.Changeset.change(%{
      status: "completed",
      article_data_after: after_data
    })
    |> Repo.update()
  end

  defp mark_latest_revision_failed(queue_entry_id, reason) do
    from(r in ContentRevisionHistory,
      where: r.queue_entry_id == ^queue_entry_id and r.status == "pending",
      order_by: [desc: r.revision_number],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> :ok
      revision ->
        revision
        |> Ecto.Changeset.change(%{status: "failed", error_reason: reason})
        |> Repo.update()
    end
  rescue
    _ -> :ok
  end

  # ── TipTap Reverse Parsing ──

  # Converts TipTap JSON back into a human-readable representation for the revision prompt.
  # Best-effort — doesn't need to be perfect since it's just for Claude to understand current content.
  defp reverse_tiptap_to_sections(nil), do: []
  defp reverse_tiptap_to_sections(%{"type" => "doc", "content" => nodes}) do
    Enum.map(nodes, &node_to_section_text/1)
  end
  defp reverse_tiptap_to_sections(_), do: []

  defp node_to_section_text(%{"type" => "paragraph", "content" => content}) do
    "[paragraph] #{extract_text(content)}"
  end
  defp node_to_section_text(%{"type" => "paragraph"}) do
    "[paragraph]"
  end
  defp node_to_section_text(%{"type" => "heading", "attrs" => %{"level" => level}, "content" => content}) do
    "[heading #{level}] #{extract_text(content)}"
  end
  defp node_to_section_text(%{"type" => "blockquote", "content" => content}) do
    inner = Enum.map_join(content, " ", fn node ->
      extract_text(node["content"] || [])
    end)
    "[blockquote] #{inner}"
  end
  defp node_to_section_text(%{"type" => "bulletList", "content" => items}) do
    item_texts = Enum.map(items, fn item ->
      "  - #{extract_text(get_in(item, ["content"]) || [])}"
    end)
    "[bullet_list]\n#{Enum.join(item_texts, "\n")}"
  end
  defp node_to_section_text(%{"type" => "orderedList", "content" => items}) do
    item_texts = items |> Enum.with_index(1) |> Enum.map(fn {item, i} ->
      "  #{i}. #{extract_text(get_in(item, ["content"]) || [])}"
    end)
    "[ordered_list]\n#{Enum.join(item_texts, "\n")}"
  end
  defp node_to_section_text(%{"type" => "spacer"}), do: "[spacer]"
  defp node_to_section_text(%{"type" => "tweet", "attrs" => %{"url" => url}}), do: "[tweet: #{url}]"
  defp node_to_section_text(%{"type" => type}), do: "[#{type}]"

  defp extract_text(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", fn
      %{"type" => "text", "text" => text} -> text
      %{"type" => "hardBreak"} -> "\n"
      %{"content" => children} -> extract_text(children)
      _ -> ""
    end)
  end
  defp extract_text(_), do: ""

  defp format_sections_for_prompt(sections) do
    Enum.join(sections, "\n\n")
  end

  # ── Tweet Preservation ──

  # Extract tweet nodes from original content and re-insert them into revised content
  # using TweetPlacer for smart, evenly-spaced distribution.
  # Admin can then manually reposition tweets in the TipTap editor.
  defp reinsert_tweet_nodes(
    %{"type" => "doc", "content" => original_nodes},
    %{"type" => "doc", "content" => revised_nodes}
  ) do
    tweet_nodes = Enum.filter(original_nodes, &(&1["type"] == "tweet"))

    if tweet_nodes == [] do
      %{"type" => "doc", "content" => revised_nodes}
    else
      content_nodes = Enum.reject(revised_nodes, &(&1["type"] == "tweet"))
      merged = TweetPlacer.distribute_tweets(content_nodes, tweet_nodes)
      %{"type" => "doc", "content" => merged}
    end
  end

  defp reinsert_tweet_nodes(_, revised_content), do: revised_content
end
