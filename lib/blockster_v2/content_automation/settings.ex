defmodule BlocksterV2.ContentAutomation.Settings do
  @moduledoc """
  Admin configuration for the content automation pipeline.
  Stored in Mnesia (persistent, replicated) with ETS cache (1-minute TTL) for fast reads.

  Mnesia table: :content_automation_settings
  Record format: {:content_automation_settings, key, value, updated_at, updated_by}
  """

  @cache_ttl :timer.minutes(1)

  @defaults %{
    target_queue_size: 10,
    category_config: %{},
    keyword_boosts: [],
    keyword_blocks: [],
    disabled_feeds: [],
    paused: false
  }

  @doc "Get a setting value. Falls back to default if not set."
  def get(key, default \\ nil) do
    default = default || Map.get(@defaults, key)

    case cached_get(key) do
      {:ok, value} ->
        value

      :miss ->
        case :mnesia.dirty_read({:content_automation_settings, key}) do
          [{:content_automation_settings, ^key, value, _updated_at, _updated_by}] ->
            cache_put(key, value)
            value

          [] ->
            default
        end
    end
  end

  @doc "Set a setting value. Invalidates cache immediately."
  def set(key, value, updated_by \\ nil) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    :mnesia.dirty_write(
      {:content_automation_settings, key, value, now, updated_by}
    )

    cache_invalidate(key)
    :ok
  end

  @doc "Check if the pipeline is paused."
  def paused?, do: get(:paused, false)

  @doc "Initialize the ETS cache table. Called from Settings or application startup."
  def init_cache do
    if :ets.whereis(:content_settings_cache) == :undefined do
      :ets.new(:content_settings_cache, [:set, :public, :named_table, read_concurrency: true])
    end
  end

  # ── ETS Cache (1-minute TTL) ──

  defp cached_get(key) do
    case :ets.lookup(:content_settings_cache, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at, do: {:ok, value}, else: :miss

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_put(key, value) do
    expires_at = System.monotonic_time(:millisecond) + @cache_ttl
    :ets.insert(:content_settings_cache, {key, value, expires_at})
  rescue
    ArgumentError -> :ok
  end

  defp cache_invalidate(key) do
    :ets.delete(:content_settings_cache, key)
  rescue
    ArgumentError -> :ok
  end
end
