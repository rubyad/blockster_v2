defmodule BlocksterV2Web.DesignSystem.HubBannerTest do
  @moduledoc """
  Tests for the `<.hub_banner />` design system component.

  Variant C hero: full-bleed brand-color gradient with identity block,
  stats, follow CTA, and live activity widget placeholder.
  """

  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  defp make_hub(overrides \\ %{}) do
    Map.merge(%{
      name: "Moonpay",
      slug: "moonpay",
      description: "Buy and sell crypto with ease.",
      logo_url: "https://example.com/logo.png",
      color_primary: "#7D00FF",
      color_secondary: "#4A00B8",
      token: "MOON",
      website_url: "https://moonpay.com",
      twitter_url: "https://x.com/moonpay",
      telegram_url: "https://t.me/moonpay",
      discord_url: "https://discord.gg/moonpay",
      instagram_url: nil,
      linkedin_url: nil,
      tiktok_url: nil,
      reddit_url: nil,
      youtube_url: nil
    }, overrides)
  end

  describe "hub_banner/1" do
    test "renders with ds-hub-banner marker class" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={142} follower_count={8217} />
      """)

      assert html =~ "ds-hub-banner"
    end

    test "renders hub name as heading" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} />
      """)

      assert html =~ "Moonpay"
    end

    test "renders hub description" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} />
      """)

      assert html =~ "Buy and sell crypto with ease."
    end

    test "renders brand color gradient" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} />
      """)

      assert html =~ "#7D00FF"
      assert html =~ "#4A00B8"
    end

    test "renders hub logo when logo_url is present" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} />
      """)

      assert html =~ "https://example.com/logo.png"
    end

    test "renders token initial when no logo_url" do
      assigns = %{hub: make_hub(%{logo_url: nil, token: "TH"})}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} />
      """)

      # Token initial rendered as fallback (no logo)
      assert html =~ ~r/text-\[24px\].*font-bold.*T/s
    end

    test "renders stats row with post count and follower count" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={142} follower_count={8217} />
      """)

      assert html =~ "142"
      assert html =~ "8.2k"
      assert html =~ "Posts"
      assert html =~ "Followers"
    end

    test "renders Follow Hub button when not following" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} user_follows_hub={false} />
      """)

      assert html =~ "Follow Hub"
      assert html =~ "toggle_follow"
    end

    test "renders Following button when following" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} user_follows_hub={true} />
      """)

      assert html =~ "Following"
      assert html =~ "toggle_follow"
    end

    test "renders social icons when URLs are present" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} />
      """)

      assert html =~ "https://moonpay.com"
      assert html =~ "https://x.com/moonpay"
    end

    test "hides social icons when URLs are nil" do
      assigns = %{hub: make_hub(%{website_url: nil, twitter_url: nil, telegram_url: nil, discord_url: nil})}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} />
      """)

      refute html =~ "moonpay.com"
    end

    test "renders breadcrumb with Hubs link" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} />
      """)

      assert html =~ "/hubs"
      assert html =~ "Hubs"
    end

    test "renders live activity widget placeholder" do
      assigns = %{hub: make_hub()}

      html = rendered_to_string(~H"""
      <.hub_banner hub={@hub} post_count={0} follower_count={0} />
      """)

      assert html =~ "Latest Activity"
    end
  end
end
