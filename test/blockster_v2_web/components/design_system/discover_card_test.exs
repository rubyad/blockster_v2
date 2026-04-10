defmodule BlocksterV2Web.Components.DesignSystem.DiscoverCardTest do
  use BlocksterV2Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2Web.DesignSystem

  describe "discover_card variant=event (stub)" do
    test "renders coming soon placeholder" do
      html =
        render_component(&DesignSystem.discover_card/1, %{
          variant: "event",
          round: nil
        })

      assert html =~ "Event"
      assert html =~ "Coming soon"
      assert html =~ "Stay tuned"
      # Purple dot for events
      assert html =~ "bg-[#7D00FF]"
    end

    test "has no clickable CTA link" do
      html =
        render_component(&DesignSystem.discover_card/1, %{
          variant: "event",
          round: nil
        })

      # Inert — uses <span> not <a> for the button
      refute html =~ "<a "
      refute html =~ "href="
    end
  end

  describe "discover_card variant=sale (stub)" do
    test "renders coming soon placeholder with brand stripe" do
      html =
        render_component(&DesignSystem.discover_card/1, %{
          variant: "sale",
          round: nil
        })

      assert html =~ "Token sale"
      assert html =~ "Coming soon"
      assert html =~ "Stay tuned"
      # Orange dot for token sales
      assert html =~ "bg-[#FF6B35]"
      # Brand stripe gradient
      assert html =~ "from-[#FF6B35]"
    end

    test "has no clickable CTA link" do
      html =
        render_component(&DesignSystem.discover_card/1, %{
          variant: "sale",
          round: nil
        })

      refute html =~ "<a "
      refute html =~ "href="
    end
  end

  describe "discover_card variant=airdrop" do
    test "renders real data when round is provided" do
      round = %{
        round_id: 14,
        total_entries: 2142,
        status: "open"
      }

      html =
        render_component(&DesignSystem.discover_card/1, %{
          variant: "airdrop",
          round: round
        })

      assert html =~ "Airdrop"
      assert html =~ "round 14"
      assert html =~ "Round 14"
      assert html =~ "Open"
      assert html =~ "2,142"
      assert html =~ "Redeem BUX to enter"
      # Lime dot for airdrop
      assert html =~ "bg-[#CAFC00]"
      # Links to /airdrop
      assert html =~ "/airdrop"
    end

    test "renders no-active-round state when round is nil" do
      html =
        render_component(&DesignSystem.discover_card/1, %{
          variant: "airdrop",
          round: nil
        })

      assert html =~ "Airdrop"
      assert html =~ "No active round"
      assert html =~ "View airdrop"
      assert html =~ "/airdrop"
    end

    test "links to /airdrop" do
      html =
        render_component(&DesignSystem.discover_card/1, %{
          variant: "airdrop",
          round: nil
        })

      assert html =~ ~s|href="/airdrop"|
    end
  end
end
