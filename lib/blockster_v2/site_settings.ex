defmodule BlocksterV2.SiteSettings do
  @moduledoc """
  Context for managing site-wide settings stored in the database.
  Uses ETS caching to minimize database queries.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.SiteSettings.Setting

  @cache_table :site_settings_cache
  @cache_ttl_ms :timer.minutes(5)

  @doc """
  Ensures the ETS cache table exists. Called on application start.
  """
  def init_cache do
    try do
      :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])
    rescue
      ArgumentError -> :ok
    end
    :ok
  end

  @doc """
  Gets a setting value by key. Returns nil if not found.
  Uses ETS cache with TTL to minimize DB queries.
  """
  def get(key) when is_binary(key) do
    init_cache()
    now = System.monotonic_time(:millisecond)

    cache_result =
      try do
        :ets.lookup(@cache_table, key)
      rescue
        ArgumentError -> []
      end

    case cache_result do
      [{^key, value, expires_at}] when expires_at > now ->
        # Cache hit and not expired
        value

      _ ->
        # Cache miss or expired - fetch from DB
        value = fetch_from_db(key)
        cache_value(key, value)
        value
    end
  end

  @doc """
  Gets a setting value by key with a default if not found.
  """
  def get(key, default) when is_binary(key) do
    get(key) || default
  end

  @doc """
  Gets multiple settings by keys in a single query.
  Returns a map of key => value.
  """
  def get_many(keys) when is_list(keys) do
    init_cache()

    now = System.monotonic_time(:millisecond)

    # Check cache for each key
    {cached, missing} =
      Enum.reduce(keys, {%{}, []}, fn key, {cached_acc, missing_acc} ->
        cache_result =
          try do
            :ets.lookup(@cache_table, key)
          rescue
            ArgumentError -> []
          end

        case cache_result do
          [{^key, value, expires_at}] when expires_at > now ->
            {Map.put(cached_acc, key, value), missing_acc}

          _ ->
            {cached_acc, [key | missing_acc]}
        end
      end)

    # Fetch missing keys from DB in one query
    db_values =
      if missing != [] do
        Setting
        |> where([s], s.key in ^missing)
        |> Repo.all()
        |> Enum.reduce(%{}, fn setting, acc ->
          cache_value(setting.key, setting.value)
          Map.put(acc, setting.key, setting.value)
        end)
      else
        %{}
      end

    # Cache nil for keys not found in DB
    Enum.each(missing -- Map.keys(db_values), fn key ->
      cache_value(key, nil)
    end)

    Map.merge(cached, db_values)
  end

  @doc """
  Gets all settings with a given prefix in a single query.
  Returns a map of key => value.
  """
  def get_by_prefix(prefix) when is_binary(prefix) do
    init_cache()

    Setting
    |> where([s], like(s.key, ^"#{prefix}%"))
    |> Repo.all()
    |> Enum.reduce(%{}, fn setting, acc ->
      cache_value(setting.key, setting.value)
      Map.put(acc, setting.key, setting.value)
    end)
  end

  @doc """
  Sets a setting value. Creates if doesn't exist, updates if it does.
  Invalidates cache on write.
  """
  def set(key, value) when is_binary(key) do
    init_cache()

    result =
      case Repo.get_by(Setting, key: key) do
        nil ->
          %Setting{}
          |> Setting.changeset(%{key: key, value: value})
          |> Repo.insert()

        setting ->
          setting
          |> Setting.changeset(%{value: value})
          |> Repo.update()
      end

    # Invalidate cache on successful write
    case result do
      {:ok, _} -> invalidate_cache(key)
      _ -> :ok
    end

    result
  end

  @doc """
  Deletes a setting by key.
  """
  def delete(key) when is_binary(key) do
    init_cache()

    result =
      case Repo.get_by(Setting, key: key) do
        nil -> {:ok, nil}
        setting -> Repo.delete(setting)
      end

    invalidate_cache(key)
    result
  end

  @doc """
  Clears the entire cache. Useful after bulk updates.
  """
  def clear_cache do
    init_cache()
    :ets.delete_all_objects(@cache_table)
    :ok
  end

  # Private functions

  defp fetch_from_db(key) do
    case Repo.get_by(Setting, key: key) do
      nil -> nil
      setting -> setting.value
    end
  end

  defp cache_value(key, value) do
    try do
      expires_at = System.monotonic_time(:millisecond) + @cache_ttl_ms
      :ets.insert(@cache_table, {key, value, expires_at})
    rescue
      ArgumentError -> :ok
    end
  end

  defp invalidate_cache(key) do
    try do
      :ets.delete(@cache_table, key)
    rescue
      ArgumentError -> :ok
    end
  end
end
