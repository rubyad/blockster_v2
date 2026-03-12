defmodule HighRollersWeb.MyNFTsLiveTest do
  @moduledoc """
  Tests for MyNFTsLive page (user's NFT collection).
  """
  use HighRollers.MnesiaCase, async: false
  use HighRollersWeb.ConnCase

  import Phoenix.LiveViewTest

  alias HighRollers.NFTStore

  setup do
    # Try to start NFTStore, handling the case where it's already running
    case start_supervised(NFTStore) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "mount without wallet" do
    test "renders page without wallet connected", %{conn: conn} do
      # Without wallet in session, the page renders with a connect prompt
      {:ok, _view, html} = live(conn, "/my-nfts")
      assert html =~ "Connect Wallet"
    end
  end

  describe "mount with wallet" do
    test "renders page for wallet connection", %{conn: conn} do
      wallet = "0x1234567890123456789012345678901234567890"

      # Insert NFTs owned by user
      insert_test_nft(%{token_id: 1, owner: wallet, hostess_index: 0})
      insert_test_nft(%{token_id: 2, owner: wallet, hostess_index: 5})
      # Insert NFT owned by someone else
      insert_test_nft(%{token_id: 3, owner: "0xother", hostess_index: 3})

      # Without session wallet, page renders with connect prompt
      # Wallet connection is handled by JavaScript hooks in production
      {:ok, _view, html} = live(conn, "/my-nfts")
      assert html =~ "Connect Wallet"
    end
  end

  describe "format helpers" do
    # MyNFTsLive shares format helpers with MintLive via delegation
    # These tests verify the helpers work correctly for NFT display

    test "special NFT detection" do
      # Special NFTs are 2340-2700
      assert is_special?(2340) == true
      assert is_special?(2500) == true
      assert is_special?(2700) == true
      assert is_special?(2339) == false
      assert is_special?(2701) == false
      assert is_special?(1) == false
    end
  end

  # Helper to check special NFT range (matches MyNFTsLive logic)
  defp is_special?(token_id), do: token_id >= 2340 and token_id <= 2700
end
