defmodule BlocksterV2.LpPriceHistory do
  @moduledoc """
  Records LP price snapshots for pool charts.
  Stores in Mnesia :lp_price_history table, keyed by {vault_type, timestamp}.
  Samples are throttled to at most one per minute per vault.

  Provides downsampled history by timeframe (matching FateSwap's approach):
  - 1H:  60-second intervals
  - 24H: 5-minute intervals
  - 7D:  30-minute intervals
  - 30D: 2-hour intervals
  - All: 1-day intervals
  """

  @min_interval 60
  @prune_days 30

  @doc """
  Record a price snapshot if enough time has passed since the last one.
  Broadcasts {:chart_point, point} on PubSub for real-time chart updates.
  Pass `force: true` to bypass throttle (used for settlement-triggered updates).
  """
  def record(vault_type, lp_price, opts \\ [])

  def record(vault_type, lp_price, opts) when is_binary(vault_type) and is_number(lp_price) and lp_price > 0 do
    now = System.system_time(:second)
    force = Keyword.get(opts, :force, false)

    should_write =
      if force do
        true
      else
        case get_latest(vault_type) do
          {ts, _price} when ts > now - @min_interval -> false
          _ -> true
        end
      end

    if should_write do
      record = {:lp_price_history, {vault_type, now}, vault_type, now, lp_price}
      :mnesia.dirty_write(record)

      point = %{time: now, value: lp_price}
      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "pool_chart:#{vault_type}", {:chart_point, point})

      :ok
    else
      :throttled
    end
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  def record(_, _, _), do: :ok

  @doc """
  Get price history for a vault type, downsampled by timeframe.
  Returns [%{time: unix, value: float}] sorted ascending.
  """
  def get_price_history(vault_type, timeframe \\ "24H") do
    {window, interval} = timeframe_params(timeframe)

    entries =
      case window do
        :all ->
          :mnesia.dirty_index_read(:lp_price_history, vault_type, :vault_type)
          |> Enum.sort_by(fn record -> elem(record, 3) end)
          |> Enum.map(fn record -> %{time: elem(record, 3), value: elem(record, 4)} end)

        seconds ->
          cutoff = System.system_time(:second) - seconds

          :mnesia.dirty_index_read(:lp_price_history, vault_type, :vault_type)
          |> Enum.filter(fn record -> elem(record, 3) >= cutoff end)
          |> Enum.sort_by(fn record -> elem(record, 3) end)
          |> Enum.map(fn record -> %{time: elem(record, 3), value: elem(record, 4)} end)
      end

    downsample(entries, interval)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Compute chart stats (high, low, change_pct) from a list of data points.
  """
  def compute_stats([]), do: nil

  def compute_stats(data) when is_list(data) do
    values = Enum.map(data, & &1.value)
    first = List.first(values)
    last = List.last(values)

    change_pct =
      if is_number(first) and first > 0 and is_number(last) do
        (last - first) / first * 100
      end

    %{
      high: Enum.max(values),
      low: Enum.min(values),
      change_pct: change_pct
    }
  end

  @doc """
  Prune entries older than 30 days.
  """
  def prune do
    cutoff = System.system_time(:second) - @prune_days * 86400

    :mnesia.dirty_match_object({:lp_price_history, :_, :_, :_, :_})
    |> Enum.filter(fn record -> elem(record, 3) < cutoff end)
    |> Enum.each(fn record -> :mnesia.dirty_delete({:lp_price_history, elem(record, 1)}) end)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  # ── Private ──

  defp get_latest(vault_type) do
    :mnesia.dirty_index_read(:lp_price_history, vault_type, :vault_type)
    |> Enum.max_by(fn record -> elem(record, 3) end, fn -> nil end)
    |> case do
      nil -> nil
      record -> {elem(record, 3), elem(record, 4)}
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # Timeframe → {window_seconds, downsample_interval}
  defp timeframe_params("1H"), do: {3_600, 60}
  defp timeframe_params("24H"), do: {86_400, 300}
  defp timeframe_params("7D"), do: {604_800, 1_800}
  defp timeframe_params("30D"), do: {2_592_000, 7_200}
  defp timeframe_params("All"), do: {:all, 86_400}
  defp timeframe_params(_), do: {86_400, 300}

  # Downsample: group by time bucket, take last point per bucket.
  # Skip downsampling when data is sparse (< 500 points) to avoid
  # collapsing a handful of points into an even smaller set.
  defp downsample([], _interval), do: []
  defp downsample(entries, _interval) when length(entries) < 500, do: entries

  defp downsample(entries, interval) do
    entries
    |> Enum.group_by(fn %{time: t} -> div(t, interval) end)
    |> Enum.sort_by(fn {bucket, _} -> bucket end)
    |> Enum.map(fn {_bucket, points} -> List.last(points) end)
  end
end
