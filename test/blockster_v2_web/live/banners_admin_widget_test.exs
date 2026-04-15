defmodule BlocksterV2Web.BannersAdminWidgetTest do
  @moduledoc """
  Exercises the Phase 6 widget-aware additions to the admin LiveView.

  Full LiveView session testing requires an admin-flagged user + the
  SearchHook + UserAuth + AdminAuth pipeline, so here we cover the
  public helpers and the Banner changeset contract that the LV relies
  on. Form-level integration is validated via the compiled template.
  """
  use ExUnit.Case, async: true

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.BannersAdminLive

  describe "widget_family/1 dispatch" do
    test "rt self-selecting widgets land in :rt_self" do
      for t <- ~w(rt_chart_landscape rt_chart_portrait rt_full_card rt_square_compact rt_sidebar_tile) do
        assert BannersAdminLive.widget_family(t) == :rt_self, "expected #{t} → :rt_self"
      end
    end

    test "fs self-selecting widgets land in :fs_self" do
      for t <- ~w(fs_hero_portrait fs_hero_landscape fs_square_compact fs_sidebar_tile) do
        assert BannersAdminLive.widget_family(t) == :fs_self, "expected #{t} → :fs_self"
      end
    end

    test "non-self-selecting rt widgets land in :rt_all" do
      for t <- ~w(rt_skyscraper rt_ticker rt_leaderboard_inline) do
        assert BannersAdminLive.widget_family(t) == :rt_all
      end
    end

    test "non-self-selecting fs widgets land in :fs_all" do
      for t <- ~w(fs_skyscraper fs_ticker) do
        assert BannersAdminLive.widget_family(t) == :fs_all
      end
    end

    test "unknown / nil / empty → :none" do
      assert BannersAdminLive.widget_family("") == :none
      assert BannersAdminLive.widget_family(nil) == :none
      assert BannersAdminLive.widget_family("not_a_widget") == :none
    end
  end

  describe "Banner changeset with widget attrs" do
    test "accepts widget_type + widget_config for a self-selecting widget" do
      cs =
        Banner.changeset(%Banner{}, %{
          name: "admin test",
          placement: "sidebar_right",
          widget_type: "rt_chart_landscape",
          widget_config: %{"selection" => "biggest_gainer"}
        })

      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :widget_type) == "rt_chart_landscape"
      assert Ecto.Changeset.get_change(cs, :widget_config) == %{"selection" => "biggest_gainer"}
    end

    test "accepts fixed-mode widget_config with bot_id + timeframe" do
      cs =
        Banner.changeset(%Banner{}, %{
          name: "admin test fixed",
          placement: "article_inline_1",
          widget_type: "rt_chart_portrait",
          widget_config: %{"selection" => "fixed", "bot_id" => "kronos", "timeframe" => "7d"}
        })

      assert cs.valid?
    end

    test "accepts fs order_id fixed config" do
      cs =
        Banner.changeset(%Banner{}, %{
          name: "admin test fs fixed",
          placement: "article_inline_2",
          widget_type: "fs_hero_portrait",
          widget_config: %{"selection" => "fixed", "order_id" => "ord-abcd"}
        })

      assert cs.valid?
    end

    test "rejects unknown widget_type (mis-typed admin submission)" do
      cs =
        Banner.changeset(%Banner{}, %{
          name: "admin bogus",
          placement: "sidebar_right",
          widget_type: "totally_fake"
        })

      refute cs.valid?
      assert {:widget_type, _} = List.keyfind(cs.errors, :widget_type, 0)
    end

    test "nil widget_type is allowed (legacy image ads keep working)" do
      cs =
        Banner.changeset(%Banner{}, %{
          name: "plain ad",
          placement: "sidebar_right",
          image_url: "https://example.com/ad.png",
          widget_type: nil
        })

      assert cs.valid?
    end

    test "widget_config defaults to empty map when widget_type present" do
      cs =
        Banner.changeset(%Banner{}, %{
          name: "no config",
          placement: "homepage_top_desktop",
          widget_type: "rt_ticker"
        })

      assert cs.valid?
      # Default from schema
      assert Ecto.Changeset.get_field(cs, :widget_config) == %{}
    end
  end
end
