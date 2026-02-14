defmodule BlocksterV2.ContentAutomation.ImageFinder do
  @moduledoc """
  Finds featured images for automated articles.

  Priority order:
    1. Bing Image Search (best for news: people, logos, places)
    2. Google Custom Search Images (fallback)
    3. X (Twitter) image search (authentic editorial photos)
    4. Unsplash (stock photo fallback)

  Downloads images and uploads originals to S3. ImageKit handles all
  on-the-fly transforms (cropping, resizing) at display time.

  Called after ContentGenerator returns article with image_search_queries.
  """

  require Logger

  alias BlocksterV2.ContentAutomation.Config

  @bing_image_url "https://api.bing.microsoft.com/v7.0/images/search"
  @google_cse_url "https://www.googleapis.com/customsearch/v1"
  @x_search_url "https://api.twitter.com/2/tweets/search/recent"
  @unsplash_search_url "https://api.unsplash.com/search/photos"

  @min_width 800
  @min_height 600
  @max_candidates 5

  @doc """
  Find up to 5 candidate featured images for an article.

  Returns a list of maps:
    [%{url: s3_url, source: "bing" | "google" | "x" | "unsplash", source_url: "...", type: :lifestyle | :graphic}]

  Gracefully returns [] if all APIs are unavailable or no images found.
  """
  def find_image_candidates(search_queries, pipeline_id) when is_list(search_queries) do
    if Enum.empty?(search_queries) do
      Logger.debug("[ImageFinder] pipeline=#{pipeline_id} No search queries provided")
      []
    else
      do_find_candidates(search_queries, pipeline_id)
    end
  end

  def find_image_candidates(_, _pipeline_id), do: []

  defp do_find_candidates(search_queries, pipeline_id) do
    # Phase 1: Bing Image Search (best source for news imagery)
    all_candidates = search_bing(search_queries, pipeline_id)

    # Phase 2: Fill from Google CSE if needed
    all_candidates =
      if length(all_candidates) < @max_candidates do
        remaining = @max_candidates - length(all_candidates)
        google_candidates = search_google_cse(search_queries, pipeline_id)
        all_candidates ++ Enum.take(google_candidates, remaining)
      else
        all_candidates
      end

    # Phase 3: X image search disabled to conserve tweet read quota

    # Phase 4: Fill from Unsplash as last resort
    all_candidates =
      if length(all_candidates) < 3 do
        remaining = 3 - length(all_candidates)
        unsplash_candidates = search_unsplash(search_queries, remaining, pipeline_id)
        all_candidates ++ unsplash_candidates
      else
        all_candidates
      end

    # Phase 4: Download and upload top candidates to S3
    final =
      all_candidates
      |> Enum.uniq_by(& &1.media_url)
      |> Enum.take(@max_candidates)
      |> download_and_upload(pipeline_id)

    Logger.info("[ImageFinder] pipeline=#{pipeline_id} Found #{length(final)} image candidates")
    final
  rescue
    e ->
      Logger.error("[ImageFinder] pipeline=#{pipeline_id} Crashed: #{Exception.message(e)}")
      []
  end

  # ── Bing Image Search ──

  defp search_bing(search_queries, pipeline_id) do
    api_key = Config.bing_image_api_key()

    if is_nil(api_key) or api_key == "" do
      Logger.debug("[ImageFinder] pipeline=#{pipeline_id} No Bing API key, skipping")
      []
    else
      search_queries
      |> Enum.take(3)
      |> Enum.flat_map(fn query -> search_bing_for_images(query, api_key, pipeline_id) end)
      |> Enum.uniq_by(& &1.media_url)
      |> score_and_rank()
    end
  end

  defp search_bing_for_images(query, api_key, pipeline_id) do
    params = %{
      "q" => query,
      "count" => "5",
      "imageType" => "Photo",
      "size" => "Large",
      "safeSearch" => "Moderate"
    }

    case Req.get(@bing_image_url,
      params: params,
      headers: [{"Ocp-Apim-Subscription-Key", api_key}],
      receive_timeout: 10_000,
      connect_options: [timeout: 5_000]
    ) do
      {:ok, %{status: 200, body: %{"value" => images}}} when is_list(images) ->
        Logger.debug("[ImageFinder] pipeline=#{pipeline_id} Bing returned #{length(images)} for: #{query}")

        images
        |> Enum.filter(fn img ->
          w = img["width"] || 0
          h = img["height"] || 0
          w >= @min_width and h >= @min_height
        end)
        |> Enum.map(fn img ->
          w = img["width"] || 1200
          h = img["height"] || 800

          %{
            media_url: img["contentUrl"],
            width: w,
            height: h,
            source: "bing",
            source_url: img["hostPageUrl"] || img["contentUrl"],
            type: classify_image(w, h)
          }
        end)

      {:ok, %{status: 200, body: _body}} ->
        Logger.debug("[ImageFinder] pipeline=#{pipeline_id} Bing no results for: #{query}")
        []

      {:ok, %{status: 429}} ->
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Bing rate limited")
        []

      {:ok, %{status: status, body: body}} ->
        error_msg = get_in(body, ["error", "message"]) || "unknown"
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Bing returned #{status}: #{error_msg}")
        []

      {:error, reason} ->
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Bing failed: #{inspect(reason)}")
        []
    end
  end

  # ── Google Custom Search Images ──

  defp search_google_cse(search_queries, pipeline_id) do
    api_key = Config.google_cse_api_key()
    cx = Config.google_cse_cx()

    if is_nil(api_key) or api_key == "" or is_nil(cx) or cx == "" do
      Logger.debug("[ImageFinder] pipeline=#{pipeline_id} No Google CSE credentials, skipping")
      []
    else
      # Search with up to 3 queries (each uses 1 API call from 100/day free quota)
      search_queries
      |> Enum.take(3)
      |> Enum.flat_map(fn query -> search_google_for_images(query, api_key, cx, pipeline_id) end)
      |> Enum.uniq_by(& &1.media_url)
      |> score_and_rank()
    end
  end

  defp search_google_for_images(query, api_key, cx, pipeline_id) do
    params = %{
      "key" => api_key,
      "cx" => cx,
      "q" => query,
      "searchType" => "image",
      "imgSize" => "xlarge",
      "imgType" => "photo",
      "num" => "5",
      "safe" => "active"
    }

    case Req.get(@google_cse_url,
      params: params,
      receive_timeout: 10_000,
      connect_options: [timeout: 5_000]
    ) do
      {:ok, %{status: 200, body: %{"items" => items}}} when is_list(items) ->
        Logger.debug("[ImageFinder] pipeline=#{pipeline_id} Google CSE returned #{length(items)} for: #{query}")

        items
        |> Enum.filter(fn item ->
          w = get_in(item, ["image", "width"]) || 0
          h = get_in(item, ["image", "height"]) || 0
          w >= @min_width and h >= @min_height
        end)
        |> Enum.map(fn item ->
          w = get_in(item, ["image", "width"]) || 1200
          h = get_in(item, ["image", "height"]) || 800

          %{
            media_url: item["link"],
            width: w,
            height: h,
            source: "google",
            source_url: get_in(item, ["image", "contextLink"]) || item["link"],
            type: classify_image(w, h)
          }
        end)

      {:ok, %{status: 200, body: body}} ->
        # No items key means no results
        Logger.debug("[ImageFinder] pipeline=#{pipeline_id} Google CSE no results for: #{query} (#{inspect(Map.keys(body || %{}))})")
        []

      {:ok, %{status: 429}} ->
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Google CSE rate limited")
        []

      {:ok, %{status: status, body: body}} ->
        error_msg = get_in(body, ["error", "message"]) || "unknown"
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Google CSE returned #{status}: #{error_msg}")
        []

      {:error, reason} ->
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Google CSE failed: #{inspect(reason)}")
        []
    end
  end

  # ── X API Search ──

  defp search_x(search_queries, pipeline_id) do
    bearer = Config.x_bearer_token()

    if is_nil(bearer) or bearer == "" do
      Logger.debug("[ImageFinder] pipeline=#{pipeline_id} No X bearer token, skipping X search")
      []
    else
      search_queries
      |> Enum.flat_map(fn query -> search_x_for_images(query, bearer, pipeline_id) end)
      |> Enum.uniq_by(& &1.media_url)
      |> score_and_rank()
    end
  end

  defp search_x_for_images(query, bearer, pipeline_id) do
    sanitized_query = String.replace(query, "$", "")

    params = %{
      "query" => "#{sanitized_query} has:images -is:retweet",
      "max_results" => "20",
      "tweet.fields" => "author_id,created_at",
      "expansions" => "attachments.media_keys",
      "media.fields" => "url,width,height,type"
    }

    case Req.get(@x_search_url,
      params: params,
      headers: [{"authorization", "Bearer #{bearer}"}],
      receive_timeout: 15_000,
      connect_options: [timeout: 5_000]
    ) do
      {:ok, %{status: 200, body: body}} ->
        extract_x_candidates(body)

      {:ok, %{status: 429}} ->
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} X API rate limited for: #{query}")
        []

      {:ok, %{status: status}} ->
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} X API returned #{status} for: #{query}")
        []

      {:error, reason} ->
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} X API failed: #{inspect(reason)}")
        []
    end
  end

  defp extract_x_candidates(body) do
    media_map =
      (get_in(body, ["includes", "media"]) || [])
      |> Enum.filter(&(&1["type"] == "photo"))
      |> Map.new(&{&1["media_key"], &1})

    tweets = body["data"] || []

    Enum.flat_map(tweets, fn tweet ->
      media_keys = get_in(tweet, ["attachments", "media_keys"]) || []

      Enum.flat_map(media_keys, fn key ->
        case Map.get(media_map, key) do
          %{"url" => url, "width" => w, "height" => h} when is_binary(url) and w >= @min_width and h >= @min_height ->
            [%{
              media_url: url,
              width: w,
              height: h,
              source: "x",
              source_url: "https://x.com/i/status/#{tweet["id"]}",
              type: classify_image(w, h)
            }]

          _ ->
            []
        end
      end)
    end)
  end

  # ── Unsplash API Search ──

  defp search_unsplash(search_queries, max_needed, pipeline_id) do
    access_key = Config.unsplash_access_key()

    if is_nil(access_key) or access_key == "" do
      Logger.debug("[ImageFinder] pipeline=#{pipeline_id} No Unsplash key, skipping Unsplash search")
      []
    else
      query = List.first(search_queries, "cryptocurrency")

      case Req.get(@unsplash_search_url,
        params: %{
          "query" => query,
          "per_page" => "#{max_needed + 2}",
          "orientation" => "landscape"
        },
        headers: [{"authorization", "Client-ID #{access_key}"}],
        receive_timeout: 10_000,
        connect_options: [timeout: 5_000]
      ) do
        {:ok, %{status: 200, body: %{"results" => results}}} ->
          results
          |> Enum.take(max_needed)
          |> Enum.map(fn photo ->
            %{
              media_url: photo["urls"]["regular"],
              width: photo["width"] || 1200,
              height: photo["height"] || 800,
              source: "unsplash",
              source_url: photo["links"]["html"],
              type: :lifestyle
            }
          end)

        {:ok, %{status: 429}} ->
          Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Unsplash rate limited")
          []

        {:ok, %{status: status}} ->
          Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Unsplash returned #{status}")
          []

        {:error, reason} ->
          Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Unsplash failed: #{inspect(reason)}")
          []
      end
    end
  end

  # ── Scoring & Ranking ──

  defp score_and_rank(candidates) do
    Enum.sort_by(candidates, fn c ->
      type_score = if c.type == :lifestyle, do: 1000, else: 0
      res_score = c.width * c.height / 1_000_000
      -(type_score + res_score)
    end)
  end

  defp classify_image(w, h) do
    ratio = w / h

    cond do
      ratio > 1.2 and ratio < 1.9 -> :lifestyle
      ratio > 0.6 and ratio < 0.85 -> :lifestyle
      true -> :graphic
    end
  end

  # ── Download & Upload ──

  defp download_and_upload(candidates, pipeline_id) do
    candidates
    |> Task.async_stream(
      fn candidate -> process_candidate(candidate, pipeline_id) end,
      max_concurrency: 3,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, result}} -> [result]
      {:ok, {:error, reason}} ->
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Candidate failed: #{inspect(reason)}")
        []
      {:exit, :timeout} ->
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Candidate download timed out")
        []
      _ ->
        []
    end)
  end

  defp process_candidate(candidate, pipeline_id) do
    with {:ok, image_binary, content_type} <- download_image(candidate.media_url),
         {:ok, s3_url} <- upload_to_s3(image_binary, content_type, pipeline_id) do
      {:ok, %{
        url: s3_url,
        source: candidate.source,
        source_url: candidate.source_url,
        type: candidate.type
      }}
    end
  end

  defp download_image(url) do
    # For X images, request original quality
    url = if String.contains?(url, "pbs.twimg.com"), do: "#{url}:orig", else: url

    case Req.get(url, receive_timeout: 15_000, max_redirects: 3) do
      {:ok, %{status: 200, body: body, headers: headers}} when is_binary(body) and byte_size(body) > 1000 ->
        content_type = get_content_type(headers, body)
        {:ok, body, content_type}

      {:ok, %{status: status}} ->
        {:error, {:download_failed, status}}

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end

  defp get_content_type(headers, body) do
    header_type =
      headers
      |> Enum.find_value(fn
        {"content-type", value} when is_list(value) -> List.first(value)
        {"content-type", value} when is_binary(value) -> value
        _ -> nil
      end)

    cond do
      header_type && String.contains?(header_type, "png") -> "image/png"
      header_type && String.contains?(header_type, "webp") -> "image/webp"
      header_type && String.contains?(header_type, "jpeg") -> "image/jpeg"
      header_type && String.contains?(header_type, "jpg") -> "image/jpeg"
      match?(<<0x89, 0x50, 0x4E, 0x47, _::binary>>, body) -> "image/png"
      match?(<<0xFF, 0xD8, _::binary>>, body) -> "image/jpeg"
      true -> "image/jpeg"
    end
  end

  defp upload_to_s3(image_binary, content_type, pipeline_id) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    hex = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    ext = content_type_to_ext(content_type)
    filename = "content/featured/#{timestamp}-#{hex}#{ext}"

    bucket = Application.get_env(:blockster_v2, :s3_bucket)
    region = Application.get_env(:blockster_v2, :s3_region, "us-east-1")

    case ExAws.S3.put_object(bucket, filename, image_binary,
      content_type: content_type,
      acl: :public_read
    )
    |> ExAws.request() do
      {:ok, _} ->
        public_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{filename}"
        Logger.info("[ImageFinder] pipeline=#{pipeline_id} Uploaded #{filename}")
        {:ok, public_url}

      {:error, reason} ->
        Logger.error("[ImageFinder] pipeline=#{pipeline_id} S3 upload failed: #{inspect(reason)}")
        {:error, :s3_upload_failed}
    end
  end

  defp content_type_to_ext("image/png"), do: ".png"
  defp content_type_to_ext("image/webp"), do: ".webp"
  defp content_type_to_ext(_), do: ".jpg"
end
