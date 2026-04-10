defmodule BlocksterV2Web.DesignPreviewLiveTest do
  @moduledoc """
  Smoke test for the dev-only design system preview LiveView.

  Verifies the page mounts and renders every Wave 0 component without
  blowing up. The component-by-component DOM assertions live in the
  per-component test files in `test/blockster_v2_web/components/design_system/`.
  """

  use BlocksterV2Web.ConnCase
  import Phoenix.LiveViewTest

  describe "GET /dev/design-preview" do
    test "renders the dev preview page with every Wave 0 component", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dev/design-preview")

      # Title and frame
      assert html =~ "design preview"
      assert html =~ "The 11 Wave 0 components"

      # Components present (one anchor each)
      assert html =~ "ds-logo"
      assert html =~ "ds-eyebrow"
      assert html =~ "ds-chip"
      assert html =~ "ds-author-avatar"
      assert html =~ "ds-profile-avatar"
      assert html =~ "ds-why-earn-bux"
      assert html =~ "ds-header"
      assert html =~ "ds-footer"
      assert html =~ "ds-page-hero"
      assert html =~ "ds-stat-card"
      assert html =~ "ds-post-card"
    end

    test "renders both header variants on the same page (logged-in + anonymous)", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dev/design-preview")

      # Logged-in variant: BUX pill, profile avatar, fake user MV
      assert html =~ "12,450"
      assert html =~ ~r/>\s*MV\s*</

      # Anonymous variant: Connect Wallet button (rendered in section 10)
      assert html =~ "Connect Wallet"
    end

    test "loads JetBrains Mono via Google Fonts so mono numerics render correctly", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dev/design-preview")

      assert html =~ "JetBrains+Mono"
    end
  end
end
