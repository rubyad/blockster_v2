defmodule BlocksterV2.FingerprintVerifier do
  @moduledoc "Server-side verification of FingerprintJS Pro events via v3 Server API."
  require Logger

  @api_base "https://api.fpjs.io"
  @max_age_ms 120_000
  @min_confidence 0.90
  @allowed_origins [
    "https://blockster-v2.fly.dev",
    "https://blockster.com",
    "https://www.blockster.com",
    "https://v2.blockster.com"
  ]

  @doc """
  Verifies a FingerprintJS event by request_id against the Server API.

  Returns:
  - `{:ok, :verified}` — all checks passed
  - `{:ok, :skipped}` — API unavailable or not configured (graceful degradation)
  - `{:error, reason}` — verification failed (fake/stale/mismatched event)
  """
  def verify_event(request_id, expected_visitor_id) do
    api_key = Application.get_env(:blockster_v2, :fingerprintjs_server_api_key)

    cond do
      is_nil(api_key) || api_key == "" ->
        Logger.warning("[FingerprintVerifier] Server API key not configured, skipping verification")
        {:ok, :skipped}

      is_nil(request_id) || request_id == "" ->
        {:error, :missing_request_id}

      is_nil(expected_visitor_id) || expected_visitor_id == "" ->
        {:error, :missing_visitor_id}

      true ->
        do_verify(request_id, expected_visitor_id, api_key)
    end
  end

  defp do_verify(request_id, expected_visitor_id, api_key) do
    url = "#{@api_base}/events/#{request_id}"

    case Req.get(url, headers: [{"Auth-API-Key", api_key}], receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        validate_event(body, expected_visitor_id)

      {:ok, %Req.Response{status: 404}} ->
        Logger.warning("[FingerprintVerifier] Request ID not found: #{request_id}")
        {:error, :request_not_found}

      {:ok, %Req.Response{status: 403}} ->
        Logger.error("[FingerprintVerifier] Invalid API key (403)")
        {:ok, :skipped}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("[FingerprintVerifier] API returned #{status}, skipping verification")
        {:ok, :skipped}

      {:error, reason} ->
        Logger.warning("[FingerprintVerifier] API unreachable: #{inspect(reason)}, skipping verification")
        {:ok, :skipped}
    end
  end

  defp validate_event(body, expected_visitor_id) do
    with {:ok, data} <- extract_identification_data(body),
         :ok <- check_visitor_id(data, expected_visitor_id),
         :ok <- check_freshness(data),
         :ok <- check_origin(data),
         :ok <- check_confidence(data) do
      {:ok, :verified}
    end
  end

  defp extract_identification_data(body) do
    case get_in(body, ["products", "identification", "data"]) do
      nil -> {:error, :invalid_response}
      data -> {:ok, data}
    end
  end

  defp check_visitor_id(data, expected_visitor_id) do
    if data["visitorId"] == expected_visitor_id do
      :ok
    else
      Logger.warning("[FingerprintVerifier] visitorId mismatch: got #{data["visitorId"]}, expected #{expected_visitor_id}")
      {:error, :visitor_id_mismatch}
    end
  end

  defp check_freshness(data) do
    case data["timestamp"] do
      nil ->
        {:error, :missing_timestamp}

      timestamp_ms when is_integer(timestamp_ms) ->
        now_ms = System.system_time(:millisecond)
        age = now_ms - timestamp_ms

        if age <= @max_age_ms do
          :ok
        else
          Logger.warning("[FingerprintVerifier] Event too old: #{age}ms (max #{@max_age_ms}ms)")
          {:error, :event_expired}
        end

      timestamp_str when is_binary(timestamp_str) ->
        # FingerprintJS v3 may return ISO 8601 timestamps
        case DateTime.from_iso8601(timestamp_str) do
          {:ok, dt, _offset} ->
            age_ms = DateTime.diff(DateTime.utc_now(), dt, :millisecond)

            if age_ms <= @max_age_ms do
              :ok
            else
              Logger.warning("[FingerprintVerifier] Event too old: #{age_ms}ms (max #{@max_age_ms}ms)")
              {:error, :event_expired}
            end

          _ ->
            {:error, :invalid_timestamp}
        end

      _ ->
        {:error, :invalid_timestamp}
    end
  end

  defp check_origin(data) do
    case data["url"] do
      nil ->
        # If no URL in response, skip origin check (don't block on missing data)
        :ok

      url when is_binary(url) ->
        origin = extract_origin(url)

        if origin in @allowed_origins do
          :ok
        else
          # Also allow localhost in dev
          if Application.get_env(:blockster_v2, :env) == :dev do
            :ok
          else
            Logger.warning("[FingerprintVerifier] Origin mismatch: #{origin}")
            {:error, :origin_mismatch}
          end
        end
    end
  end

  defp check_confidence(data) do
    score = get_in(data, ["confidence", "score"])

    cond do
      is_nil(score) ->
        # If no confidence in response, skip check
        :ok

      is_number(score) and score >= @min_confidence ->
        :ok

      is_number(score) ->
        Logger.warning("[FingerprintVerifier] Low confidence: #{score} (min #{@min_confidence})")
        {:error, :low_confidence}

      true ->
        {:error, :invalid_confidence}
    end
  end

  defp extract_origin(url) do
    uri = URI.parse(url)

    case {uri.scheme, uri.host} do
      {scheme, host} when is_binary(scheme) and is_binary(host) ->
        "#{scheme}://#{host}"

      _ ->
        url
    end
  end
end
