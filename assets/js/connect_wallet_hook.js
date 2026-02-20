/**
 * ConnectWalletHook - Handles external wallet connections (MetaMask, Coinbase, WalletConnect, Phantom)
 *
 * This hook manages connection to hardware/browser wallets and integrates with the
 * Blockster smart wallet system. Connected wallets can be used for:
 * - Token transfers between hardware wallet and Blockster smart wallet
 * - Balance reading across multiple chains
 * - Multiplier boosts based on wallet holdings
 */

import { createWallet } from "thirdweb/wallets";

export const ConnectWalletHook = {
  mounted() {
    this.connectedWallet = null;
    this.connectedAccount = null;

    // Auto-reconnect to previously connected wallet on page load
    this.handleEvent("auto_reconnect_wallet", async ({ provider, expected_address }) => {
      try {
        console.log("[ConnectWallet] Auto-reconnecting to:", provider);

        // Create wallet instance
        let wallet = await this.createWalletInstance(provider);

        // Auto-connect silently (won't prompt user if already authorized)
        const account = await wallet.autoConnect({
          client: window.thirdwebClient
        });

        // If autoConnect returns null, wallet is not authorized - silently fail
        if (!account) {
          console.log("[ConnectWallet] Auto-reconnect skipped - wallet not authorized");
          this.pushEvent("wallet_reconnect_failed", {
            provider: provider,
            error: "Not authorized"
          });
          return;
        }

        console.log("[ConnectWallet] Auto-reconnected:", account.address);

        // Verify the address matches what's in database
        if (account.address.toLowerCase() !== expected_address.toLowerCase()) {
          console.warn("[ConnectWallet] Address mismatch! Expected:", expected_address, "Got:", account.address);

          // Disconnect and notify Phoenix
          await wallet.disconnect();
          this.pushEvent("wallet_address_mismatch", {
            expected: expected_address,
            actual: account.address,
            provider: provider
          });
          return;
        }

        // Store wallet and account (both locally and globally for other hooks)
        this.connectedWallet = wallet;
        this.connectedAccount = account;
        window.connectedHardwareWallet = wallet;
        window.connectedHardwareAccount = account;

        // Notify Phoenix that reconnection succeeded
        this.pushEvent("wallet_reconnected", {
          address: account.address,
          provider: provider
        });

        console.log("[ConnectWallet] Auto-reconnect successful");

      } catch (error) {
        console.error("[ConnectWallet] Auto-reconnect failed:", error);

        // If auto-reconnect fails, just silently continue - user can manually reconnect
        // Don't show error to user since this was an automatic background operation
        this.pushEvent("wallet_reconnect_failed", {
          provider: provider,
          error: error.message
        });
      }
    });

    // Listen for wallet connection request from LiveView
    this.handleEvent("connect_wallet", async ({ provider }) => {
      try {
        console.log("[ConnectWallet] Connecting to:", provider);

        // Create wallet instance
        const wallet = await this.createWalletInstance(provider);

        // Connect wallet
        const account = await wallet.connect({
          client: window.thirdwebClient
        });

        // Switch to Rogue Chain (will add network if not present)
        await wallet.switchChain(window.rogueChain);

        this.connectedWallet = wallet;
        this.connectedAccount = account;
        window.connectedHardwareWallet = wallet;
        window.connectedHardwareAccount = account;

        console.log("[ConnectWallet] Connected:", account.address);

        // Setup Rogue Chain network and import ROGUE token on Arbitrum
        await this.setupWalletNetworksAndTokens(wallet, provider);

        // Send wallet address to Phoenix
        this.pushEvent("wallet_connected", {
          address: account.address,
          provider: provider,
          chain_id: window.rogueChain.id
        });

      } catch (error) {
        console.error("[ConnectWallet] Connection failed:", error);

        // Parse user-friendly error message
        let errorMessage = error.message;
        if (error.message.includes("User rejected")) {
          errorMessage = "Connection cancelled by user";
        } else if (error.message.includes("No injected provider")) {
          errorMessage = `${provider} wallet not found. Please install the extension.`;
        }

        this.pushEvent("wallet_connection_error", {
          error: errorMessage,
          provider: provider
        });
      }
    });

    // Disconnect wallet
    this.handleEvent("disconnect_wallet", async () => {
      try {
        if (this.connectedWallet) {
          await this.connectedWallet.disconnect();
          this.connectedWallet = null;
          this.connectedAccount = null;
          window.connectedHardwareWallet = null;
          window.connectedHardwareAccount = null;
        }
        this.pushEvent("wallet_disconnected", {});
      } catch (error) {
        console.error("[ConnectWallet] Disconnect failed:", error);
      }
    });
  },

  /**
   * Create wallet instance based on provider
   */
  async createWalletInstance(provider) {
    let wallet;

    switch(provider) {
      case "metamask":
        wallet = createWallet("io.metamask");
        break;
      case "coinbase":
        wallet = createWallet("com.coinbase.wallet");
        break;
      case "walletconnect":
        wallet = createWallet("walletConnect", {
          projectId: window.WALLETCONNECT_PROJECT_ID // Set in root.html.heex
        });
        break;
      case "phantom":
        // Phantom exposes its EVM provider at window.phantom.ethereum
        // Without this check, Thirdweb falls back to window.ethereum (MetaMask)
        if (!window.phantom?.ethereum) {
          throw new Error("No injected provider found for Phantom. Please install the Phantom browser extension.");
        }
        wallet = createWallet("app.phantom");
        break;
      default:
        throw new Error(`Unknown provider: ${provider}`);
    }

    return wallet;
  },

  /**
   * Setup wallet networks and import tokens
   * - Adds Rogue Chain network if not already present
   * - Imports ROGUE token on Arbitrum One if not already added
   */
  async setupWalletNetworksAndTokens(wallet, provider) {
    try {
      // MetaMask and Coinbase Wallet support wallet_addEthereumChain
      const supportsNetworkManagement = provider === "metamask" || provider === "coinbase";

      if (!supportsNetworkManagement) {
        console.log("[ConnectWallet] Wallet doesn't support network management");
        return;
      }

      // 1. Add Rogue Chain network if not present
      await this.ensureRogueChainNetwork(wallet);

    } catch (error) {
      console.warn("[ConnectWallet] Network/token setup failed (non-critical):", error);
      // Don't fail the connection if network setup fails
    }
  },

  /**
   * Ensure Rogue Chain network is added to the wallet
   */
  async ensureRogueChainNetwork(wallet) {
    try {
      const rogueChainParams = {
        chainId: "0x88CED", // 560013 in hex
        chainName: "Rogue Chain Mainnet",
        nativeCurrency: {
          name: "ROGUE",
          symbol: "ROGUE",
          decimals: 18
        },
        rpcUrls: ["https://rpc.roguechain.io/rpc"],
        blockExplorerUrls: ["https://roguescan.io"]
      };

      // Try to switch to Rogue Chain
      try {
        await wallet.switchChain(window.rogueChain);
        console.log("[ConnectWallet] Rogue Chain already added");
      } catch (switchError) {
        // If switch fails, network doesn't exist - add it
        if (switchError.code === 4902) {
          console.log("[ConnectWallet] Adding Rogue Chain network...");

          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [rogueChainParams]
          });

          console.log("[ConnectWallet] Rogue Chain network added successfully");
        } else {
          throw switchError;
        }
      }
    } catch (error) {
      console.error("[ConnectWallet] Failed to add Rogue Chain network:", error);
      throw error;
    }
  },

  destroyed() {
    // Cleanup if needed
    if (this.connectedWallet) {
      this.connectedWallet.disconnect().catch(console.error);
    }
  }
};
