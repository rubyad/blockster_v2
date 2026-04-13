defmodule BlocksterV2Web.WalletComponentsTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest

  alias BlocksterV2Web.WalletComponents

  # ── wallet_selector_modal/1 · State 1 (Wallet Selection) ──────────

  describe "wallet_selector_modal/1 · wallet selection state" do
    test "does NOT render when show is false" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={false}
          detected_wallets={[]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      refute html =~ "Connect a Solana wallet"
      refute html =~ "wallet-modal-backdrop"
    end

    test "renders modal when show is true" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      assert html =~ "wallet-modal-backdrop"
      assert html =~ "Connect a Solana wallet"
    end

    test "renders SIGN IN eyebrow" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      assert html =~ "Sign in"
    end

    test "renders close button with hide_wallet_selector event" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      assert html =~ ~s(phx-click="hide_wallet_selector")
    end

    test "renders all three wallets from registry" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      assert html =~ "Phantom"
      assert html =~ "Solflare"
      assert html =~ "Backpack"
    end

    test "detected wallet shows Detected badge and Connect button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[%{"name" => "Phantom"}]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      assert html =~ "Detected"
      assert html =~ ~s(phx-click="select_wallet")
      assert html =~ ~s(phx-value-name="Phantom")
    end

    test "undetected wallet shows Install badge and Get link" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[%{"name" => "Phantom"}]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      # Backpack is not in detected list
      assert html =~ "Install"
      assert html =~ "Get"
    end

    test "wallet taglines render" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      assert html =~ "The friendly crypto wallet"
      assert html =~ "most secure wallet"
      assert html =~ "home for your xNFTs"
    end

    test "renders What's a wallet link in footer" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      assert html =~ "What" and html =~ "a wallet?"
    end

    test "renders Terms and Privacy Policy links" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      assert html =~ "Terms"
      assert html =~ "Privacy Policy"
    end

    test "renders subtitle text about security" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      assert html =~ "seed phrase or private keys"
    end

    test "renders Blockster icon in header" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={true}
          detected_wallets={[]}
          connecting={false}
          connecting_wallet_name={nil}
        />
        """)

      assert html =~ "blockster-icon.png"
    end
  end

  # ── wallet_selector_modal/1 · State 2 (Connecting) ──────────────

  describe "wallet_selector_modal/1 · connecting state" do
    test "renders connecting UI when connecting with wallet name" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={false}
          detected_wallets={[%{"name" => "Phantom"}]}
          connecting={true}
          connecting_wallet_name="Phantom"
        />
        """)

      assert html =~ "wallet-modal-backdrop"
      assert html =~ "Opening Phantom"
    end

    test "renders big wallet badge with spinner" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={false}
          detected_wallets={[%{"name" => "Phantom"}]}
          connecting={true}
          connecting_wallet_name="Phantom"
        />
        """)

      # Spinning ring SVG
      assert html =~ "animate-spin"
      # Progress shimmer
      assert html =~ "wallet-progress-shimmer"
    end

    test "renders status steps" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={false}
          detected_wallets={[%{"name" => "Phantom"}]}
          connecting={true}
          connecting_wallet_name="Phantom"
        />
        """)

      assert html =~ "Wallet detected"
      assert html =~ "Awaiting signature"
      assert html =~ "Verify and sign in"
    end

    test "renders approve text with wallet name" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={false}
          detected_wallets={[%{"name" => "Solflare"}]}
          connecting={true}
          connecting_wallet_name="Solflare"
        />
        """)

      assert html =~ "Opening Solflare"
      assert html =~ "Approve the connection in your Solflare popup"
    end

    test "does not render connecting state without wallet name" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={false}
          detected_wallets={[]}
          connecting={true}
          connecting_wallet_name={nil}
        />
        """)

      refute html =~ "Opening"
      refute html =~ "wallet-modal-backdrop"
    end

    test "renders close button in connecting state" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.wallet_selector_modal
          show={false}
          detected_wallets={[%{"name" => "Phantom"}]}
          connecting={true}
          connecting_wallet_name="Phantom"
        />
        """)

      assert html =~ ~s(phx-click="hide_wallet_selector")
    end
  end

  # ── connect_button/1 ────────────────────────────────────────────

  describe "connect_button/1" do
    test "renders Connect Wallet when disconnected" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.connect_button wallet_address={nil} connecting={false} />
        """)

      assert html =~ "Connect Wallet"
      assert html =~ ~s(phx-click="show_wallet_selector")
    end

    test "renders Connecting... when connecting" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.connect_button wallet_address={nil} connecting={true} />
        """)

      assert html =~ "Connecting..."
    end

    test "renders truncated address when connected" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.connect_button wallet_address="7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX" connecting={false} />
        """)

      assert html =~ "7CuR...mxVX"
    end

    test "renders SOL balance when connected with balance" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <WalletComponents.connect_button wallet_address="7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX" connecting={false} sol_balance={1.5} />
        """)

      assert html =~ "1.5 SOL"
    end
  end
end
