defmodule BlocksterV2.Notifications.SystemConfig do
  @moduledoc """
  Central configuration store for the notification system.
  All configurable values (referral amounts, trigger thresholds, copy templates,
  rate limits) stored in a single PostgreSQL jsonb row, cached in ETS with 5-minute TTL.

  The AI Manager writes here, everything else reads from here.
  """

  import Ecto.Query
  alias BlocksterV2.Repo

  require Logger

  @ets_table :system_config_cache
  @cache_ttl_ms :timer.minutes(5)

  @defaults %{
    # Referral amounts
    "referrer_signup_bux" => 500,
    "referee_signup_bux" => 250,
    "phone_verify_bux" => 500,

    # Trigger thresholds
    "bux_milestones" => [1_000, 5_000, 10_000, 25_000, 50_000, 100_000],
    "reading_streak_days" => [3, 7, 14, 30],
    "dormancy_min_days" => 5,
    "dormancy_max_days" => 14,
    "referral_propensity_threshold" => 0.6,

    # Conversion funnel
    "bux_balance_gaming_nudge" => 500,
    "articles_before_nudge" => 5,
    "games_before_rogue_nudge" => 5,
    "loss_streak_rogue_offer" => 3,
    "win_streak_celebration" => 3,
    "big_win_multiplier" => 10,

    # Rate limits
    "default_max_emails_per_day" => 3,
    "global_max_per_hour" => 8,

    # Triggers enabled
    "trigger_bux_milestone_enabled" => true,
    "trigger_reading_streak_enabled" => true,
    "trigger_hub_recommendation_enabled" => true,
    "trigger_dormancy_enabled" => true,
    "trigger_referral_opportunity_enabled" => true,

    # Custom event rules (JSON list)
    "custom_rules" => [
      %{
        "event_type" => "x_connected",
        "action" => "notification",
        "title" => "X Account Connected!",
        "body" => "You earned 500 BUX for connecting your X account!",
        "channel" => "in_app",
        "notification_type" => "reward",
        "bux_bonus" => 500,
        "source" => "permanent"
      },
      %{
        "event_type" => "wallet_connected",
        "action" => "notification",
        "title" => "Wallet Connected!",
        "body" => "You earned 500 BUX for connecting your wallet!",
        "channel" => "in_app",
        "notification_type" => "reward",
        "bux_bonus" => 500,
        "source" => "permanent"
      },
      %{
        "event_type" => "phone_verified",
        "action" => "notification",
        "title" => "Phone Verified!",
        "body" => "You earned 500 BUX for verifying your phone!",
        "channel" => "in_app",
        "notification_type" => "reward",
        "bux_bonus" => 500,
        "source" => "permanent"
      }
    ]
  }

  # ============ Public API ============

  @doc """
  Get a config value by key. Returns the cached value or falls back to default.
  """
  def get(key, default \\ nil) when is_binary(key) or is_atom(key) do
    key = to_string(key)
    config = get_cached_config()
    Map.get(config, key, default || Map.get(@defaults, key))
  end

  @doc """
  Put a config value. Writes to DB and invalidates ETS cache.
  """
  def put(key, value, updated_by \\ "system") when is_binary(key) or is_atom(key) do
    key = to_string(key)
    config = get_db_config()
    new_config = Map.put(config, key, value)
    upsert_config(new_config, updated_by)
    invalidate_cache()
    :ok
  end

  @doc """
  Put multiple config values at once.
  """
  def put_many(changes, updated_by \\ "system") when is_map(changes) do
    config = get_db_config()
    string_changes = Map.new(changes, fn {k, v} -> {to_string(k), v} end)
    new_config = Map.merge(config, string_changes)
    upsert_config(new_config, updated_by)
    invalidate_cache()
    :ok
  end

  @doc """
  Get the full config map (cached).
  """
  def get_all do
    get_cached_config()
  end

  @doc """
  Returns the default configuration map.
  """
  def defaults, do: @defaults

  @doc """
  Seed default config values if the table is empty.
  Called on application start.
  """
  def seed_defaults do
    ensure_ets_table()
    case get_db_row() do
      nil ->
        upsert_config(@defaults, "system")
        Logger.info("[SystemConfig] Seeded default configuration")
      _row ->
        :ok
    end
  end

  @doc """
  Force invalidate the ETS cache.
  """
  def invalidate_cache do
    ensure_ets_table()
    :ets.delete(@ets_table, :config)
    :ok
  rescue
    ArgumentError -> :ok
  end

  # ============ ETS Cache ============

  defp get_cached_config do
    ensure_ets_table()

    case :ets.lookup(@ets_table, :config) do
      [{:config, config, cached_at}] ->
        if System.monotonic_time(:millisecond) - cached_at < @cache_ttl_ms do
          config
        else
          refresh_cache()
        end
      [] ->
        refresh_cache()
    end
  end

  defp refresh_cache do
    config = get_db_config()
    merged = Map.merge(@defaults, config)
    :ets.insert(@ets_table, {:config, merged, System.monotonic_time(:millisecond)})
    merged
  rescue
    ArgumentError ->
      # ETS table doesn't exist yet
      Map.merge(@defaults, get_db_config())
  end

  defp ensure_ets_table do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])
      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  # ============ Database ============

  defp get_db_config do
    case get_db_row() do
      nil -> %{}
      row -> row.config || %{}
    end
  rescue
    _ -> %{}
  end

  defp get_db_row do
    from(c in "system_config",
      select: %{id: c.id, config: c.config, updated_by: c.updated_by},
      limit: 1
    )
    |> Repo.one()
  rescue
    _ -> nil
  end

  defp upsert_config(config, updated_by) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    case get_db_row() do
      nil ->
        Repo.insert_all("system_config", [
          %{config: config, updated_by: updated_by, inserted_at: now, updated_at: now}
        ])

      row ->
        from(c in "system_config", where: c.id == ^row.id)
        |> Repo.update_all(set: [config: config, updated_by: updated_by, updated_at: now])
    end
  end
end
