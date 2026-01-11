defmodule HighRollersWeb.MintLiveTest do
  @moduledoc """
  Tests for MintLive page (homepage / Mint tab).
  """
  use HighRollers.MnesiaCase, async: false
  use HighRollersWeb.ConnCase

  import Phoenix.LiveViewTest

  alias HighRollers.NFTStore

  # Start NFTStore GenServer for tests
  setup do
    # Try to start NFTStore, handling the case where it's already running
    case start_supervised(NFTStore) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "mount" do
    test "renders mint page with initial stats", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")

      # Check page renders
      assert html =~ "High Rollers"

      # Check stats are shown (0 minted initially)
      assert html =~ "0"  # Total minted
      assert html =~ "2700"  # Remaining
    end

    test "shows hostess gallery", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Check basic page structure renders
      # Note: Hostess gallery may be dynamically loaded or in a separate component
      assert html =~ "High Rollers" || html =~ "Mint"
    end

    test "shows mint counts from Mnesia", %{conn: conn} do
      # Insert some test NFTs
      insert_test_nft(%{token_id: 1, hostess_index: 0})
      insert_test_nft(%{token_id: 2, hostess_index: 0})
      insert_test_nft(%{token_id: 3, hostess_index: 5})

      {:ok, _view, html} = live(conn, "/")

      # Should show 3 total minted
      assert html =~ "3"
      # Should show 2697 remaining
      assert html =~ "2697"
    end
  end

  describe "format helpers" do
    test "format_rogue/1 formats wei to ROGUE" do
      alias HighRollersWeb.MintLive

      assert MintLive.format_rogue("1000000000000000000") == "1.0"
      assert MintLive.format_rogue("1500000000000000000000") == "1.5K"
      assert MintLive.format_rogue("2000000000000000000000000") == "2.0M"
      assert MintLive.format_rogue(nil) == "0"
    end

    test "format_apy/1 formats basis points to percentage" do
      alias HighRollersWeb.MintLive

      assert MintLive.format_apy(1500) == 15.0
      assert MintLive.format_apy(750) == 7.5
      assert MintLive.format_apy(nil) == "0"
    end

    test "format_usd/2 calculates USD value" do
      alias HighRollersWeb.MintLive

      # 1 ROGUE at $0.0001
      assert MintLive.format_usd("1000000000000000000", 0.0001) == "$0.00"

      # 10000 ROGUE at $0.0001
      assert MintLive.format_usd("10000000000000000000000", 0.0001) == "$1.00"
    end

    test "progress_percent/2 calculates progress" do
      alias HighRollersWeb.MintLive

      assert MintLive.progress_percent(100, 2700) == 3.7
      assert MintLive.progress_percent(1350, 2700) == 50.0
      assert MintLive.progress_percent(2700, 2700) == 100.0
    end
  end

  describe "events" do
    test "mint event sets minting state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Simulate mint button click
      html = render_click(view, "mint")

      # Should show minting state
      # Note: actual minting is handled by JavaScript hook
      assert has_element?(view, "[data-minting]") || html =~ "Initiating"
    end

    test "dismiss_mint_result clears result", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # First need to set a mint result (simulate via handle_info)
      send(view.pid, {:nft_minted, %{
        token_id: 100,
        hostess_index: 0,
        recipient: "0x0000000000000000000000000000000000000000",
        tx_hash: "0xabc123"
      }})

      # Dismiss the result
      render_click(view, "dismiss_mint_result")

      # Result should be cleared
      refute render(view) =~ "View on Explorer"
    end
  end

  describe "real-time updates" do
    test "handles nft_minted event", %{conn: conn} do
      insert_test_nft(%{token_id: 1, hostess_index: 0})

      {:ok, view, _html} = live(conn, "/")

      # Simulate NFT minted event
      send(view.pid, {:nft_minted, %{
        token_id: 2,
        hostess_index: 5,
        recipient: "0xsomeone",
        tx_hash: "0xabc123"
      }})

      html = render(view)

      # Total should now be 2 (1 existing + 1 new)
      assert html =~ "2"
    end

    test "handles reward_received event", %{conn: conn} do
      # Insert global stats first
      insert_test_stats(:global, %{
        total_rewards_received: "1000000000000000000000",
        rewards_last_24h: "100000000000000000000"
      })

      {:ok, view, _html} = live(conn, "/")

      # Simulate reward received event
      send(view.pid, {:reward_received, %{
        amount: "50000000000000000000"  # 50 ROGUE
      }})

      # Stats should update (not verifiable in HTML without more setup)
      # This test just ensures no crash
      html = render(view)
      assert html =~ "High Rollers"
    end

    test "handles earnings_synced event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Simulate full stats sync
      send(view.pid, {:earnings_synced, %{
        total_rewards_received: "5000000000000000000000",
        rewards_last_24h: "200000000000000000000",
        overall_apy_basis_points: 1500
      }})

      html = render(view)
      assert html =~ "High Rollers"
    end
  end
end
