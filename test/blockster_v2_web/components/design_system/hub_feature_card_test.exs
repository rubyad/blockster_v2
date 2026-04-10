defmodule BlocksterV2Web.DesignSystem.HubFeatureCardTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "hub_feature_card/1" do
    test "renders the hub name, description, gradient, and stats in horizontal layout" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hub_feature_card
          href="/hub/moonpay"
          name="Moonpay"
          ticker="M"
          primary="#7D00FF"
          secondary="#4A00B8"
          description="The simplest way to buy and sell crypto."
          badge="Sponsor"
          post_count="142"
          follower_count="8.2k"
          bux_paid="340k"
          layout={:horizontal}
        />
        """)

      assert html =~ "ds-hub-feature-card"
      assert html =~ ~s(href="/hub/moonpay")
      assert html =~ "#7D00FF"
      assert html =~ "#4A00B8"
      assert html =~ "Moonpay"
      assert html =~ "The simplest way to buy and sell crypto."
      assert html =~ "Sponsor"
      assert html =~ "142"
      assert html =~ "8.2k"
      assert html =~ "340k"
      assert html =~ "+ Follow Hub"
      assert html =~ "Visit →"
    end

    test "renders vertical layout with stacked stats and full-width button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hub_feature_card
          href="/hub/bitcoin"
          name="Bitcoin"
          ticker="₿"
          primary="#F7931A"
          secondary="#B86811"
          description="The original cryptocurrency."
          post_count="5.6k"
          follower_count="112k"
          bux_paid="3.8M"
          layout={:vertical}
        />
        """)

      assert html =~ "ds-hub-feature-card"
      assert html =~ "Bitcoin"
      # Vertical layout has label-value rows
      assert html =~ "Posts"
      assert html =~ "Followers"
      assert html =~ "BUX paid"
      assert html =~ "5.6k"
      assert html =~ "112k"
      assert html =~ "3.8M"
      # Vertical layout has full-width follow button, no "Visit →"
      assert html =~ "+ Follow Hub"
      refute html =~ "Visit →"
    end

    test "renders badge with lime pulse dot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hub_feature_card
          href="/hub/moonpay"
          name="Moonpay"
          primary="#7D00FF"
          secondary="#4A00B8"
          badge="Sponsor"
        />
        """)

      assert html =~ "Sponsor"
      assert html =~ "pulse-dot"
      assert html =~ "#CAFC00"
    end

    test "renders without badge when not provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hub_feature_card
          href="/hub/bitcoin"
          name="Bitcoin"
          primary="#F7931A"
          secondary="#B86811"
        />
        """)

      assert html =~ "Bitcoin"
      refute html =~ "Sponsor"
      refute html =~ "Trending"
    end

    test "renders logo_url image when provided instead of ticker" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hub_feature_card
          href="/hub/moonpay"
          name="Moonpay"
          logo_url="https://example.com/logo.png"
          primary="#7D00FF"
          secondary="#4A00B8"
        />
        """)

      assert html =~ "https://example.com/logo.png"
    end

    test "falls back to first letter when no ticker or logo_url" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hub_feature_card
          href="/hub/solana"
          name="Solana"
          primary="#00FFA3"
          secondary="#00DC82"
        />
        """)

      assert html =~ "S"
    end

    test "has dot pattern overlay and blur glow" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hub_feature_card
          href="/hub/test"
          name="Test"
          primary="#000"
          secondary="#111"
        />
        """)

      assert html =~ "opacity-15"
      assert html =~ "blur-3xl"
    end

    test "has 320px min-height" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hub_feature_card
          href="/hub/test"
          name="Test"
          primary="#000"
          secondary="#111"
        />
        """)

      assert html =~ "min-height: 320px"
    end
  end
end
