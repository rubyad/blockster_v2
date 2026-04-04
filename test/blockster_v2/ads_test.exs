defmodule BlocksterV2.AdsTest do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Ads
  alias BlocksterV2.Ads.Banner

  # ============================================================================
  # Helpers
  # ============================================================================

  @valid_attrs %{
    name: "Test Banner",
    image_url: "https://example.com/banner.png",
    link_url: "https://example.com",
    placement: "sidebar_left",
    dimensions: "300x250"
  }

  defp banner_fixture(attrs \\ %{}) do
    {:ok, banner} =
      attrs
      |> Enum.into(@valid_attrs)
      |> Ads.create_banner()

    banner
  end

  # ============================================================================
  # CRUD Tests
  # ============================================================================

  describe "create_banner/1" do
    test "creates a banner with valid attrs" do
      assert {:ok, %Banner{} = banner} = Ads.create_banner(@valid_attrs)
      assert banner.name == "Test Banner"
      assert banner.placement == "sidebar_left"
      assert banner.image_url == "https://example.com/banner.png"
      assert banner.link_url == "https://example.com"
      assert banner.dimensions == "300x250"
      assert banner.is_active == true
      assert banner.impressions == 0
      assert banner.clicks == 0
    end

    test "fails without required name" do
      assert {:error, changeset} = Ads.create_banner(%{placement: "sidebar_left"})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails without required placement" do
      assert {:error, changeset} = Ads.create_banner(%{name: "Banner"})
      assert %{placement: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails with invalid placement" do
      attrs = Map.put(@valid_attrs, :placement, "invalid_spot")
      assert {:error, changeset} = Ads.create_banner(attrs)
      assert %{placement: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts all valid placements" do
      placements = ~w(sidebar_left sidebar_right mobile_top mobile_mid mobile_bottom)

      for {placement, idx} <- Enum.with_index(placements) do
        attrs = %{@valid_attrs | name: "Banner #{idx}", placement: placement}
        assert {:ok, %Banner{placement: ^placement}} = Ads.create_banner(attrs)
      end
    end
  end

  describe "get_banner!/1" do
    test "returns the banner with the given id" do
      banner = banner_fixture()
      assert Ads.get_banner!(banner.id) == banner
    end

    test "raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Ads.get_banner!(-1)
      end
    end
  end

  describe "update_banner/2" do
    test "updates a banner with valid attrs" do
      banner = banner_fixture()
      assert {:ok, updated} = Ads.update_banner(banner, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "fails with invalid placement" do
      banner = banner_fixture()
      assert {:error, changeset} = Ads.update_banner(banner, %{placement: "bad"})
      assert %{placement: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "delete_banner/1" do
    test "deletes a banner" do
      banner = banner_fixture()
      assert {:ok, %Banner{}} = Ads.delete_banner(banner)
      assert_raise Ecto.NoResultsError, fn -> Ads.get_banner!(banner.id) end
    end
  end

  # ============================================================================
  # Listing Tests
  # ============================================================================

  describe "list_banners/0" do
    test "returns all banners ordered by name" do
      b1 = banner_fixture(%{name: "Zebra Banner"})
      b2 = banner_fixture(%{name: "Alpha Banner"})

      banners = Ads.list_banners()
      assert length(banners) == 2
      assert hd(banners).id == b2.id
      assert List.last(banners).id == b1.id
    end

    test "returns empty list when no banners exist" do
      assert Ads.list_banners() == []
    end
  end

  describe "list_active_banners/0" do
    test "returns only active banners" do
      _inactive = banner_fixture(%{name: "Inactive", is_active: false})
      active = banner_fixture(%{name: "Active", is_active: true})

      banners = Ads.list_active_banners()
      assert length(banners) == 1
      assert hd(banners).id == active.id
    end
  end

  describe "list_active_banners_by_placement/1" do
    test "returns active banners for a specific placement" do
      banner_fixture(%{name: "Left 1", placement: "sidebar_left"})
      banner_fixture(%{name: "Right 1", placement: "sidebar_right"})
      banner_fixture(%{name: "Left Inactive", placement: "sidebar_left", is_active: false})

      banners = Ads.list_active_banners_by_placement("sidebar_left")
      assert length(banners) == 1
      assert hd(banners).name == "Left 1"
    end

    test "returns empty list when no active banners for placement" do
      banner_fixture(%{name: "Right Only", placement: "sidebar_right"})

      assert Ads.list_active_banners_by_placement("sidebar_left") == []
    end
  end

  # ============================================================================
  # Impression / Click Incrementing
  # ============================================================================

  describe "increment_impressions/1" do
    test "atomically increments impressions count" do
      banner = banner_fixture()
      assert banner.impressions == 0

      {:ok, updated} = Ads.increment_impressions(banner)
      assert updated.impressions == 1

      {:ok, updated2} = Ads.increment_impressions(updated)
      assert updated2.impressions == 2
    end
  end

  describe "increment_clicks/1" do
    test "atomically increments clicks count" do
      banner = banner_fixture()
      assert banner.clicks == 0

      {:ok, updated} = Ads.increment_clicks(banner)
      assert updated.clicks == 1

      {:ok, updated2} = Ads.increment_clicks(updated)
      assert updated2.clicks == 2
    end
  end

  # ============================================================================
  # Toggle Active
  # ============================================================================

  describe "toggle_active/1" do
    test "deactivates an active banner" do
      banner = banner_fixture(%{is_active: true})
      assert {:ok, toggled} = Ads.toggle_active(banner)
      assert toggled.is_active == false
    end

    test "activates an inactive banner" do
      banner = banner_fixture(%{is_active: false})
      assert {:ok, toggled} = Ads.toggle_active(banner)
      assert toggled.is_active == true
    end
  end
end
