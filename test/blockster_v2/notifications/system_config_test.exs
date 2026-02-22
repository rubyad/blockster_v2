defmodule BlocksterV2.Notifications.SystemConfigTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Notifications.SystemConfig

  setup do
    # Clear any existing config
    BlocksterV2.Repo.delete_all("system_config")
    SystemConfig.invalidate_cache()
    :ok
  end

  describe "defaults/0" do
    test "returns default config map with expected keys" do
      defaults = SystemConfig.defaults()
      assert is_map(defaults)
      assert defaults["referrer_signup_bux"] == 500
      assert defaults["referee_signup_bux"] == 250
      assert defaults["phone_verify_bux"] == 100
      assert defaults["bux_milestones"] == [1_000, 5_000, 10_000, 25_000, 50_000, 100_000]
      assert defaults["reading_streak_days"] == [3, 7, 14, 30]
      assert defaults["custom_rules"] == []
    end
  end

  describe "get/2" do
    test "returns default value when DB is empty" do
      assert SystemConfig.get("referrer_signup_bux") == 500
      assert SystemConfig.get("referee_signup_bux") == 250
    end

    test "returns explicit default when key not found" do
      assert SystemConfig.get("nonexistent_key", 42) == 42
    end

    test "returns stored value after put" do
      SystemConfig.put("referrer_signup_bux", 1000, "test")
      assert SystemConfig.get("referrer_signup_bux") == 1000
    end

    test "works with atom keys" do
      assert SystemConfig.get(:referrer_signup_bux) == 500
    end
  end

  describe "put/3" do
    test "stores and retrieves a value" do
      :ok = SystemConfig.put("referee_signup_bux", 500, "admin")
      assert SystemConfig.get("referee_signup_bux") == 500
    end

    test "overwrites existing value" do
      SystemConfig.put("referrer_signup_bux", 750, "ai_manager")
      assert SystemConfig.get("referrer_signup_bux") == 750

      SystemConfig.put("referrer_signup_bux", 1000, "admin")
      assert SystemConfig.get("referrer_signup_bux") == 1000
    end

    test "works with atom keys" do
      :ok = SystemConfig.put(:referrer_signup_bux, 999, "test")
      assert SystemConfig.get("referrer_signup_bux") == 999
    end
  end

  describe "put_many/2" do
    test "stores multiple values at once" do
      :ok = SystemConfig.put_many(%{
        "referrer_signup_bux" => 1000,
        "referee_signup_bux" => 500,
        "phone_verify_bux" => 200
      }, "ai_manager")

      assert SystemConfig.get("referrer_signup_bux") == 1000
      assert SystemConfig.get("referee_signup_bux") == 500
      assert SystemConfig.get("phone_verify_bux") == 200
    end
  end

  describe "get_all/0" do
    test "returns merged defaults + stored config" do
      SystemConfig.put("referrer_signup_bux", 999, "test")
      all = SystemConfig.get_all()

      assert is_map(all)
      assert all["referrer_signup_bux"] == 999
      # Defaults still present
      assert all["referee_signup_bux"] == 250
      assert all["reading_streak_days"] == [3, 7, 14, 30]
    end
  end

  describe "seed_defaults/0" do
    test "seeds when table is empty" do
      SystemConfig.seed_defaults()
      all = SystemConfig.get_all()
      assert all["referrer_signup_bux"] == 500
    end

    test "does not overwrite existing config" do
      SystemConfig.put("referrer_signup_bux", 999, "test")
      SystemConfig.seed_defaults()
      assert SystemConfig.get("referrer_signup_bux") == 999
    end
  end

  describe "invalidate_cache/0" do
    test "cache is invalidated and re-fetched from DB" do
      SystemConfig.put("referrer_signup_bux", 777, "test")
      assert SystemConfig.get("referrer_signup_bux") == 777

      # Directly update DB (bypassing cache)
      import Ecto.Query
      from(c in "system_config")
      |> BlocksterV2.Repo.update_all(set: [
        config: %{"referrer_signup_bux" => 888}
      ])

      # Still cached
      assert SystemConfig.get("referrer_signup_bux") == 777

      # After invalidation, fresh read
      SystemConfig.invalidate_cache()
      assert SystemConfig.get("referrer_signup_bux") == 888
    end
  end
end
