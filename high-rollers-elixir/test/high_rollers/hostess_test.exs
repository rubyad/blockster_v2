defmodule HighRollers.HostessTest do
  @moduledoc """
  Tests for Hostess static data module.
  Pure functions - no Mnesia required (except all_with_counts).
  """
  use ExUnit.Case, async: true

  alias HighRollers.Hostess

  describe "all/0" do
    test "returns all 8 hostesses" do
      hostesses = Hostess.all()
      assert length(hostesses) == 8
    end

    test "hostesses are in correct order by index" do
      hostesses = Hostess.all()
      assert Enum.at(hostesses, 0).name == "Penelope Fatale"
      assert Enum.at(hostesses, 7).name == "Vivienne Allure"
    end

    test "each hostess has required fields" do
      hostesses = Hostess.all()

      for hostess <- hostesses do
        assert Map.has_key?(hostess, :index)
        assert Map.has_key?(hostess, :name)
        assert Map.has_key?(hostess, :rarity)
        assert Map.has_key?(hostess, :multiplier)
        assert Map.has_key?(hostess, :image)
        assert Map.has_key?(hostess, :description)
      end
    end
  end

  describe "get/1" do
    test "returns hostess by index" do
      hostess = Hostess.get(0)
      assert hostess.name == "Penelope Fatale"
      assert hostess.multiplier == 100

      hostess = Hostess.get(7)
      assert hostess.name == "Vivienne Allure"
      assert hostess.multiplier == 30
    end

    test "returns nil for invalid index" do
      assert Hostess.get(8) == nil
      assert Hostess.get(-1) == nil
      assert Hostess.get(100) == nil
    end
  end

  describe "multiplier/1" do
    test "returns correct multiplier for each hostess" do
      assert Hostess.multiplier(0) == 100  # Penelope
      assert Hostess.multiplier(1) == 90   # Mia
      assert Hostess.multiplier(2) == 80   # Cleo
      assert Hostess.multiplier(3) == 70   # Sophia
      assert Hostess.multiplier(4) == 60   # Luna
      assert Hostess.multiplier(5) == 50   # Aurora
      assert Hostess.multiplier(6) == 40   # Scarlett
      assert Hostess.multiplier(7) == 30   # Vivienne
    end

    test "returns default 30 for invalid index" do
      assert Hostess.multiplier(8) == 30
      assert Hostess.multiplier(-1) == 30
    end
  end

  describe "name/1" do
    test "returns correct name for each hostess" do
      assert Hostess.name(0) == "Penelope Fatale"
      assert Hostess.name(1) == "Mia Siren"
      assert Hostess.name(2) == "Cleo Enchante"
      assert Hostess.name(3) == "Sophia Spark"
      assert Hostess.name(4) == "Luna Mirage"
      assert Hostess.name(5) == "Aurora Seductra"
      assert Hostess.name(6) == "Scarlett Ember"
      assert Hostess.name(7) == "Vivienne Allure"
    end

    test "returns 'Unknown' for invalid index" do
      assert Hostess.name(8) == "Unknown"
      assert Hostess.name(-1) == "Unknown"
    end
  end

  describe "multipliers/0" do
    test "returns list of all multipliers in order" do
      assert Hostess.multipliers() == [100, 90, 80, 70, 60, 50, 40, 30]
    end
  end

  describe "image/1" do
    test "returns ImageKit URL for valid index" do
      image = Hostess.image(0)
      assert image =~ "ik.imagekit.io"
      assert image =~ "penelope"
    end

    test "returns nil for invalid index" do
      assert Hostess.image(8) == nil
    end
  end

  describe "thumbnail/1" do
    test "returns ImageKit thumbnail URL with transforms" do
      thumbnail = Hostess.thumbnail(0)
      assert thumbnail =~ "ik.imagekit.io"
      assert thumbnail =~ "tr=w-128,h-128"
    end

    test "returns nil for invalid index" do
      assert Hostess.thumbnail(8) == nil
    end
  end

  describe "hostess data integrity" do
    test "multipliers sum correctly" do
      # Used for calculating total multiplier points
      total = Hostess.all() |> Enum.map(& &1.multiplier) |> Enum.sum()
      assert total == 100 + 90 + 80 + 70 + 60 + 50 + 40 + 30
      assert total == 520
    end

    test "rarities are strings ending with %" do
      for hostess <- Hostess.all() do
        assert is_binary(hostess.rarity)
        assert String.ends_with?(hostess.rarity, "%")
      end
    end

    test "indices are 0-7 and unique" do
      indices = Hostess.all() |> Enum.map(& &1.index)
      assert indices == [0, 1, 2, 3, 4, 5, 6, 7]
    end
  end
end
