defmodule BlocksterV2Web.DesignSystem.PostCardTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "post_card/1" do
    test "renders the title, image, hub badge, author, read time, and BUX reward" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.post_card
          href="/the-quiet-revolution"
          image="https://example.com/img.jpg"
          hub_name="Moonpay"
          hub_color="#7D00FF"
          title="The quiet revolution of on-chain liquidity pools"
          author="Marcus Verren"
          read_minutes={8}
          bux_reward={45}
        />
        """)

      assert html =~ "ds-post-card"
      assert html =~ ~s(href="/the-quiet-revolution")
      assert html =~ "https://example.com/img.jpg"
      assert html =~ "Moonpay"
      assert html =~ "background-color: #7D00FF"
      assert html =~ "The quiet revolution of on-chain liquidity pools"
      assert html =~ "Marcus Verren"
      assert html =~ "8 min"
      assert html =~ "+45"
    end

    test "renders without optional hub, author, read_minutes, and bux_reward" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.post_card
          href="/x"
          image="https://example.com/img.jpg"
          title="Just a title"
        />
        """)

      assert html =~ "Just a title"
      refute html =~ "Moonpay"
      refute html =~ "+45"
    end

    test "title is line-clamped to 3 lines" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.post_card href="/x" image="https://example.com/img.jpg" title="Hi" />
        """)

      assert html =~ "line-clamp-3"
    end

    test "image is loaded lazily" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.post_card href="/x" image="https://example.com/img.jpg" title="Hi" />
        """)

      assert html =~ ~s(loading="lazy")
    end

    test "BUX reward accepts a string instead of integer" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.post_card
          href="/x"
          image="https://example.com/img.jpg"
          title="Hi"
          bux_reward="Earn 35"
        />
        """)

      assert html =~ "Earn 35"
    end
  end
end
