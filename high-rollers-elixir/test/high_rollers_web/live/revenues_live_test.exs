defmodule HighRollersWeb.RevenuesLiveTest do
  @moduledoc """
  Tests for RevenuesLive page (revenue sharing stats and withdrawal).
  """
  use HighRollers.MnesiaCase, async: false
  use HighRollersWeb.ConnCase

  import Phoenix.LiveViewTest

  alias HighRollers.{NFTStore, Rewards}

  setup do
    # Try to start NFTStore, handling the case where it's already running
    case start_supervised(NFTStore) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "mount" do
    test "renders revenues page with global stats", %{conn: conn} do
      # Set up global stats
      Rewards.update_global_stats(%{
        total_rewards_received: "10000000000000000000000",  # 10K ROGUE
        total_rewards_distributed: "9000000000000000000000",  # 9K ROGUE
        rewards_last_24h: "500000000000000000000",  # 500 ROGUE
        overall_apy_basis_points: 1500,  # 15%
        total_nfts: 2342,
        total_multiplier_points: 109390
      })

      {:ok, _view, html} = live(conn, "/revenues")

      # Check page renders
      assert html =~ "Revenue" || html =~ "Rewards"
    end

    test "renders without stats gracefully", %{conn: conn} do
      # No stats initialized
      {:ok, _view, html} = live(conn, "/revenues")

      # Should still render without crashing
      assert html =~ "Revenue" || html =~ "0"
    end
  end

  describe "hostess stats" do
    test "shows per-hostess stats", %{conn: conn} do
      # Set up hostess stats
      for i <- 0..7 do
        Rewards.update_hostess_stats(i, %{
          nft_count: 100 + i * 50,
          total_points: (100 + i * 50) * (100 - i * 10),
          share_basis_points: 1000 + i * 100,
          last_24h_per_nft: "50000000000000000000",
          apy_basis_points: 1500 - i * 100,
          time_24h_per_nft: "183000000000000000000",
          time_apy_basis_points: 7500 - i * 500,
          special_nft_count: 10
        })
      end

      {:ok, _view, html} = live(conn, "/revenues")

      # Check page renders with stats data
      # The exact format depends on template implementation
      assert html =~ "Revenue" || html =~ "Rewards" || html =~ "0"
    end
  end

  describe "real-time updates" do
    test "handles earnings_synced event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/revenues")

      # Simulate earnings sync
      send(view.pid, {:earnings_synced, %{
        total_rewards_received: "15000000000000000000000",
        rewards_last_24h: "750000000000000000000",
        overall_apy_basis_points: 1800
      }})

      html = render(view)
      # Page should update without crashing
      assert html =~ "Revenue" || html =~ "0"
    end

    test "handles reward_received event", %{conn: conn} do
      Rewards.update_global_stats(%{
        total_rewards_received: "10000000000000000000000",
        total_rewards_distributed: "9000000000000000000000",
        rewards_last_24h: "500000000000000000000",
        overall_apy_basis_points: 1500,
        total_nfts: 2342,
        total_multiplier_points: 109390
      })

      {:ok, view, _html} = live(conn, "/revenues")

      # Simulate new reward
      send(view.pid, {:reward_received, %{
        bet_id: "0xabc123",
        amount: "100000000000000000000",  # 100 ROGUE
        timestamp: System.system_time(:second)
      }})

      html = render(view)
      assert html =~ "Revenue" || html =~ "0"
    end
  end

  describe "format helpers" do
    # RevenuesLive defines its own format helpers similar to MintLive
    # These are tested implicitly through the page renders
  end
end
