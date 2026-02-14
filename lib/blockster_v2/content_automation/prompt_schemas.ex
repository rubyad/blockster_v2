defmodule BlocksterV2.ContentAutomation.PromptSchemas do
  @moduledoc """
  Shared Claude tool schemas for content automation.

  Used by ContentGenerator (initial generation) and EditorialFeedback (revisions)
  to ensure consistent structured output compatible with TipTapBuilder.
  """

  @doc """
  Returns the tool schema for article output.
  Forces Claude to return structured article data compatible with TipTapBuilder.
  """
  def article_output_schema do
    [%{
      "name" => "write_article",
      "description" => "Write the article content in structured format",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "title" => %{
            "type" => "string",
            "description" => "Catchy, opinionated headline (max 80 chars)"
          },
          "excerpt" => %{
            "type" => "string",
            "description" => "One-sentence summary for cards/social (max 160 chars)"
          },
          "sections" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "type" => %{
                  "type" => "string",
                  "enum" => ["paragraph", "heading", "blockquote", "bullet_list", "ordered_list"]
                },
                "text" => %{
                  "type" => "string",
                  "description" => "Text content (supports **bold**, *italic*, ~~strike~~, `code`, [text](url))"
                },
                "level" => %{
                  "type" => "integer",
                  "description" => "Heading level (2 or 3). Only for heading type."
                },
                "items" => %{
                  "type" => "array",
                  "items" => %{"type" => "string"},
                  "description" => "List items. Only for bullet_list/ordered_list types."
                }
              },
              "required" => ["type"]
            }
          },
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "minItems" => 2,
            "maxItems" => 5,
            "description" => "2-5 topic tags (e.g. 'Bitcoin', 'DeFi', 'Regulation')"
          },
          "image_search_queries" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "minItems" => 3,
            "maxItems" => 5,
            "description" => """
            Think like a PHOTO EDITOR, not a journalist. These queries search Google Images for the featured photo.
            DO NOT use article keywords — use VISUAL SUBJECT descriptions that return good photos.
            Rules:
            - Name specific people (e.g. "Donald Trump speaking", "Gary Gensler SEC")
            - Name specific companies/products (e.g. "Truth Social app", "Coinbase office")
            - Include one broader fallback (e.g. "cryptocurrency trading floor", "Wall Street stock exchange")
            - NEVER use abstract concepts ("regulation", "ETF application") — these return charts and diagrams, not photos
            - Prefer queries that return PHOTOGRAPHS of real people, places, and events
            Examples: "Elon Musk press conference", "Bitcoin ATM machine", "SEC headquarters Washington DC"
            """
          },
          "tweet_suggestions" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "maxItems" => 3,
            "description" => """
            Twitter/X search queries to find HIGH-ENGAGEMENT tweets to embed in this article.
            These queries are run against X API Recent Search — design them to return POPULAR tweets, not random ones.
            Rules:
            - Target SPECIFIC people who would comment on this topic: name them with "from:" operator
              e.g. "from:balaboris Bitcoin ETF", "from:VitalikButerin Ethereum"
            - Include well-known crypto voices, analysts, founders, journalists, or politicians relevant to the topic
            - One query should be broader (no from:) but use specific terms that attract high-engagement discussion
            - Think: "Who has a large audience AND would tweet about this?" — not just keyword matching
            - Avoid overly generic queries like "Bitcoin" or "crypto news" — too noisy
            - Good examples: "from:saborsinlei Bitcoin reserve", "Ethereum ETF approval min_faves:50", "from:CoinDesk Solana"
            """
          },
          "promotional_tweet" => %{
            "type" => "string",
            "maxLength" => 250,
            "description" => """
            A promotional tweet for @BlocksterCom's X account about this article.
            STRICT LIMIT: MUST be under 250 characters total (the {{ARTICLE_URL}} placeholder adds ~30 chars).
            Style: Open with emoji, tag relevant @accounts, use $CASHTAGS for tokens.
            Keep hashtags to 1-2 max.
            MUST end with a line break then: "Read the full story & earn BUX\u26A1\n{{ARTICLE_URL}}"
            Tone: Confident, fact-based, third-person brand voice.
            Do NOT exceed 250 characters — shorter is better.
            """
          }
        },
        "required" => ["title", "excerpt", "sections", "tags", "image_search_queries", "promotional_tweet"]
      }
    }]
  end
end
