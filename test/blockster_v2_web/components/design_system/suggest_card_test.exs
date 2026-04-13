defmodule BlocksterV2Web.Components.DesignSystem.SuggestCardTest do
  use BlocksterV2Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2Web.DesignSystem

  describe "suggest_card" do
    test "renders with all fields" do
      html =
        render_component(&DesignSystem.suggest_card/1, %{
          href: "/test-article",
          image: "https://example.com/img.jpg",
          hub_name: "Moonpay",
          hub_color: "#7D00FF",
          title: "Why on-chain settlement won the argument",
          author: "Lena Park",
          read_minutes: 5,
          bux_reward: 35
        })

      assert html =~ "test-article"
      assert html =~ "example.com/img.jpg"
      assert html =~ "Moonpay"
      assert html =~ "#7D00FF"
      assert html =~ "Why on-chain settlement won the argument"
      assert html =~ "Lena Park"
      assert html =~ "5 min"
      assert html =~ "35"
    end

    test "renders without optional fields" do
      html =
        render_component(&DesignSystem.suggest_card/1, %{
          href: "/minimal",
          title: "Minimal card"
        })

      assert html =~ "Minimal card"
      assert html =~ "/minimal"
      # No hub badge
      refute html =~ "Moonpay"
      # No author
      refute html =~ "Lena"
    end

    test "renders hub badge with custom color" do
      html =
        render_component(&DesignSystem.suggest_card/1, %{
          href: "/test",
          title: "Test",
          hub_name: "Solana",
          hub_color: "#00FFA3"
        })

      assert html =~ "Solana"
      assert html =~ "#00FFA3"
    end

    test "renders BUX reward badge" do
      html =
        render_component(&DesignSystem.suggest_card/1, %{
          href: "/test",
          title: "Test",
          bux_reward: 100
        })

      assert html =~ "100"
      assert html =~ "bg-[#CAFC00]"
    end

    test "has hover effect classes" do
      html =
        render_component(&DesignSystem.suggest_card/1, %{
          href: "/test",
          title: "Test"
        })

      assert html =~ "hover:-translate-y-0.5"
      assert html =~ "hover:shadow"
    end

    test "links to the provided href" do
      html =
        render_component(&DesignSystem.suggest_card/1, %{
          href: "/my-article-slug",
          title: "Test"
        })

      assert html =~ ~s|href="/my-article-slug"|
    end
  end
end
