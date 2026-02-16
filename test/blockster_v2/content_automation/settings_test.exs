defmodule BlocksterV2.ContentAutomation.SettingsTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.ContentAutomation.Settings
  import BlocksterV2.ContentAutomation.Factory

  setup do
    ensure_mnesia_tables()
    Settings.init_cache()

    # Clean up any test keys after each test
    on_exit(fn ->
      for key <- [:test_key, :test_bool, :test_int, :test_overwrite, :paused, :target_queue_size] do
        try do
          :mnesia.dirty_delete(:content_automation_settings, key)
        rescue
          _ -> :ok
        end
      end

      # Clear ETS cache
      try do
        :ets.delete_all_objects(:content_settings_cache)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  describe "get/2 and set/2" do
    test "get returns default when no value has been set" do
      result = Settings.get(:nonexistent_key, "fallback")
      assert result == "fallback"
    end

    test "set then get round-trips correctly for string values" do
      Settings.set(:test_key, "hello world")
      assert Settings.get(:test_key) == "hello world"
    end

    test "set then get round-trips correctly for boolean values" do
      Settings.set(:test_bool, true)
      assert Settings.get(:test_bool) == true

      Settings.set(:test_bool, false)
      assert Settings.get(:test_bool) == false
    end

    test "set then get round-trips correctly for integer values" do
      Settings.set(:test_int, 42)
      assert Settings.get(:test_int) == 42
    end

    test "set overwrites previous value" do
      Settings.set(:test_overwrite, "first")
      assert Settings.get(:test_overwrite) == "first"

      Settings.set(:test_overwrite, "second")
      assert Settings.get(:test_overwrite) == "second"
    end

    test "get with explicit default returns that default when no value set" do
      result = Settings.get(:never_set_key, 999)
      assert result == 999
    end
  end

  describe "paused?/0" do
    test "returns false by default" do
      refute Settings.paused?()
    end

    test "returns true after set(:paused, true)" do
      Settings.set(:paused, true)
      assert Settings.paused?()
    end

    test "returns false after set(:paused, false)" do
      Settings.set(:paused, true)
      assert Settings.paused?()

      Settings.set(:paused, false)
      refute Settings.paused?()
    end
  end

  describe "defaults" do
    test "target_queue_size defaults to 20" do
      assert Settings.get(:target_queue_size) == 20
    end
  end
end
