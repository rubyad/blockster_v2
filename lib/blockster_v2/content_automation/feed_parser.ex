defmodule BlocksterV2.ContentAutomation.FeedParser do
  @moduledoc """
  RSS/Atom feed parser using fast_rss.
  Auto-detects format and returns normalized item maps.
  """

  require Logger

  @doc """
  Parse an RSS or Atom feed body string.
  Returns the parsed feed map or an empty map with "items" key on failure.
  """
  def parse(body) when is_binary(body) do
    result =
      cond do
        String.contains?(body, "<feed") -> FastRSS.parse_atom(body)
        String.contains?(body, "<rss") -> FastRSS.parse_rss(body)
        String.contains?(body, "<rdf:RDF") -> FastRSS.parse_rss(body)
        true -> {:error, :unknown_format}
      end

    case result do
      {:ok, feed} -> feed
      {:error, reason} ->
        Logger.warning("[FeedParser] Parse failed: #{inspect(reason)}")
        %{"items" => [], "entries" => []}
    end
  end

  @doc """
  Extract normalized item maps from a parsed feed.
  Handles both RSS (items) and Atom (entries) formats.
  """
  def extract_items(parsed_feed) do
    items = parsed_feed["items"] || parsed_feed["entries"] || []

    items
    |> Enum.map(fn entry ->
      %{
        title: extract_title(entry),
        url: extract_url(entry),
        summary: extract_summary(entry),
        published_at: parse_date(entry["pub_date"] || entry["published"] || entry["updated"])
      }
    end)
    |> Enum.reject(fn item -> is_nil(item.url) or is_nil(item.title) end)
  end

  # ── Field Extraction ──

  defp extract_title(%{"title" => title}) when is_binary(title), do: String.trim(title)
  defp extract_title(%{"title" => %{"value" => title}}) when is_binary(title), do: String.trim(title)
  defp extract_title(_), do: nil

  defp extract_url(%{"link" => link}) when is_binary(link), do: String.trim(link)
  defp extract_url(%{"links" => [%{"href" => href} | _]}), do: String.trim(href)
  defp extract_url(%{"link" => %{"href" => href}}), do: String.trim(href)
  defp extract_url(_), do: nil

  defp extract_summary(%{"description" => desc}) when is_binary(desc), do: truncate_summary(desc)
  defp extract_summary(%{"summary" => %{"value" => summary}}) when is_binary(summary), do: truncate_summary(summary)
  defp extract_summary(%{"content" => content}) when is_binary(content), do: truncate_summary(content)
  defp extract_summary(_), do: nil

  defp truncate_summary(text) do
    text
    |> strip_html()
    |> String.slice(0, 2000)
    |> String.trim()
  end

  defp strip_html(text) do
    text
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # ── Date Parsing ──

  defp parse_date(nil), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp parse_date(date_string) when is_binary(date_string) do
    # Try ISO 8601 first (Atom feeds)
    with {:error, _} <- DateTime.from_iso8601(date_string),
         # Try RFC 2822 manually (RSS feeds: "Mon, 12 Feb 2026 10:30:00 +0000")
         {:error, _} <- parse_rfc2822(date_string) do
      Logger.debug("[FeedParser] Could not parse date: #{date_string}")
      DateTime.utc_now() |> DateTime.truncate(:second)
    else
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      {:ok, dt} -> DateTime.truncate(dt, :second)
    end
  end

  defp parse_date(_), do: DateTime.utc_now() |> DateTime.truncate(:second)

  # Basic RFC 2822 parser for RSS pub_date fields
  defp parse_rfc2822(str) do
    # Pattern: "Wed, 12 Feb 2026 10:30:00 +0000" or "Wed, 12 Feb 2026 10:30:00 GMT"
    months = %{
      "Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4, "May" => 5, "Jun" => 6,
      "Jul" => 7, "Aug" => 8, "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12
    }

    regex = ~r/\w+,?\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})/

    case Regex.run(regex, str) do
      [_, day, month_str, year, hour, min, sec] ->
        month = Map.get(months, month_str)

        if month do
          case NaiveDateTime.new(
            String.to_integer(year),
            month,
            String.to_integer(day),
            String.to_integer(hour),
            String.to_integer(min),
            String.to_integer(sec)
          ) do
            {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
            error -> error
          end
        else
          {:error, :invalid_month}
        end

      _ ->
        {:error, :no_match}
    end
  end
end
