/**
 * Balance Fetcher Hook
 *
 * Fetches token balances from hardware wallets across multiple chains:
 * - ETH (Ethereum Mainnet + Arbitrum)
 * - ROGUE (Rogue Chain native + Arbitrum ERC-20)
 * - USDC, USDT, ARB (Ethereum + Arbitrum ERC-20)
 */

export const BalanceFetcherHook = {
  mounted() {
    // Store the current address for refresh
    this.currentAddress = null;

    this.handleEvent("fetch_hardware_wallet_balances", async ({ address }) => {
      this.currentAddress = address;
      await this.fetchBalances(address);
    });

    // Listen for refresh request after transfer
    this.handleEvent("refresh_balances_after_transfer", async () => {
      if (this.currentAddress) {
        console.log("[BalanceFetcher] Refreshing balances after transfer");
        await this.fetchBalances(this.currentAddress);
      }
    });
  },

  async fetchBalances(address) {
      try {
        console.log("[BalanceFetcher] Fetching balances for:", address);

        // Import chain objects
        const { ethereum, arbitrum } = await import("thirdweb/chains");

        // Fetch all balances in parallel
        const [
          ethMainnetBalance,
          ethArbitrumBalance,
          rogueNativeBalance,
          rogueArbitrumBalance,
          usdcEthBalance,
          usdcArbBalance,
          usdtEthBalance,
          usdtArbBalance,
          arbArbBalance
        ] = await Promise.all([
          // Native tokens
          this.getNativeBalance(address, ethereum),
          this.getNativeBalance(address, arbitrum),
          this.getNativeBalance(address, window.rogueChain),

          // ROGUE ERC-20 on Arbitrum
          this.getROGUEArbitrumBalance(address),

          // USDC (ERC-20)
          this.getTokenBalance(address, "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", 1, 6),     // USDC Ethereum
          this.getTokenBalance(address, "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", 42161, 6), // USDC Arbitrum

          // USDT (ERC-20)
          this.getTokenBalance(address, "0xdAC17F958D2ee523a2206206994597C13D831ec7", 1, 6),     // USDT Ethereum
          this.getTokenBalance(address, "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", 42161, 6), // USDT Arbitrum

          // ARB (ERC-20 on Arbitrum only)
          this.getTokenBalance(address, "0x912CE59144191C1204E64559FE8253a0e49E6548", 42161, 18)  // ARB Arbitrum
        ]);

        console.log("[BalanceFetcher] Balances fetched:", {
          eth_mainnet: ethMainnetBalance,
          eth_arbitrum: ethArbitrumBalance,
          eth_combined: ethMainnetBalance + ethArbitrumBalance,
          rogue_native: rogueNativeBalance,
          rogue_arbitrum: rogueArbitrumBalance,
          usdc_eth: usdcEthBalance,
          usdc_arb: usdcArbBalance,
          usdt_eth: usdtEthBalance,
          usdt_arb: usdtArbBalance,
          arb_arb: arbArbBalance
        });

        // Send to Phoenix - will be stored in Mnesia hardware_wallet_balances table
        this.pushEvent("hardware_wallet_balances_fetched", {
          balances: [
            // ETH balances (native on both chains)
            {symbol: "ETH", chain_id: 1, balance: ethMainnetBalance, address: null, decimals: 18},
            {symbol: "ETH", chain_id: 42161, balance: ethArbitrumBalance, address: null, decimals: 18},

            // ROGUE balances
            {symbol: "ROGUE", chain_id: 560013, balance: rogueNativeBalance, address: null, decimals: 18},
            {symbol: "ROGUE", chain_id: 42161, balance: rogueArbitrumBalance, address: "0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd", decimals: 18},

            // USDC balances (ERC-20 on both chains)
            {symbol: "USDC", chain_id: 1, balance: usdcEthBalance, address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", decimals: 6},
            {symbol: "USDC", chain_id: 42161, balance: usdcArbBalance, address: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", decimals: 6},

            // USDT balances (ERC-20 on both chains)
            {symbol: "USDT", chain_id: 1, balance: usdtEthBalance, address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", decimals: 6},
            {symbol: "USDT", chain_id: 42161, balance: usdtArbBalance, address: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", decimals: 6},

            // ARB balance (ERC-20 on Arbitrum only)
            {symbol: "ARB", chain_id: 42161, balance: arbArbBalance, address: "0x912CE59144191C1204E64559FE8253a0e49E6548", decimals: 18}
          ]
        });

      } catch (error) {
        console.error("[BalanceFetcher] Fetch failed:", error);
        this.pushEvent("balance_fetch_error", {
          error: error.message || "Failed to fetch balances"
        });
      }
  },

  /**
   * Get native token balance (ETH, ROGUE, etc.)
   */
  async getNativeBalance(address, chain) {
    const { getRpcClient } = await import("thirdweb/rpc");

    const rpcRequest = getRpcClient({
      client: window.thirdwebClient,
      chain
    });

    const balanceWei = await rpcRequest({
      method: "eth_getBalance",
      params: [address, "latest"]
    });

    return Number(balanceWei) / 1e18;
  },

  /**
   * Get ROGUE balance on Arbitrum (ERC-20)
   */
  async getROGUEArbitrumBalance(address) {
    const ROGUE_ARBITRUM = "0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd";
    return this.getTokenBalance(address, ROGUE_ARBITRUM, 42161, 18);
  },

  /**
   * Generic ERC-20 token balance fetcher
   * @param {string} address - Wallet address
   * @param {string} tokenAddress - Token contract address
   * @param {number} chainId - Chain ID (1 = Ethereum, 42161 = Arbitrum)
   * @param {number} decimals - Token decimals (6 for USDC/USDT, 18 for most others)
   */
  async getTokenBalance(address, tokenAddress, chainId, decimals) {
    try {
      const { getContract, readContract } = await import("thirdweb");

      // Get chain object
      let chain;
      if (chainId === 1) {
        const { ethereum } = await import("thirdweb/chains");
        chain = ethereum;
      } else if (chainId === 42161) {
        const { arbitrum } = await import("thirdweb/chains");
        chain = arbitrum;
      } else {
        console.warn(`[BalanceFetcher] Unsupported chain ID: ${chainId}`);
        return 0;
      }

      const contract = getContract({
        client: window.thirdwebClient,
        address: tokenAddress,
        chain
      });

      // Read balance
      const balanceWei = await readContract({
        contract,
        method: "function balanceOf(address) view returns (uint256)",
        params: [address]
      });

      // Convert to human-readable format
      const balance = Number(balanceWei) / Math.pow(10, decimals);
      return balance;
    } catch (error) {
      console.error(`[BalanceFetcher] Failed to fetch ${tokenAddress} on chain ${chainId}:`, error);
      return 0;
    }
  }
};
