// High Rollers NFT - Affiliate Balance Hook for Phoenix LiveView
// Fetches affiliate balance from Arbitrum NFT contract and pushes to LiveView

import { CONFIG } from '../config.js'

/**
 * AffiliateBalanceHook - Reads affiliate balance from NFT contract
 *
 * Attach to a container element on the Affiliates page:
 *   <div phx-hook="AffiliateBalance" id="affiliate-balance-container"></div>
 *
 * Events pushed TO LiveView:
 *   - affiliate_balance_fetched: { balance: "wei_string" }
 *   - affiliate_balance_error: { error: "message" }
 *
 * Events received FROM LiveView:
 *   - refresh_affiliate_balance: triggers a re-fetch from contract
 */
const AffiliateBalanceHook = {
  mounted() {
    console.log('[AffiliateBalanceHook] Mounted')

    // Listen for refresh requests from LiveView (e.g., after a mint)
    this.handleEvent("refresh_affiliate_balance", () => {
      console.log('[AffiliateBalanceHook] Refresh requested')
      this.fetchBalance()
    })

    // Fetch initial balance after a short delay to ensure wallet is connected
    setTimeout(() => this.fetchBalance(), 500)
  },

  async fetchBalance() {
    // Check wallet connection
    if (!window.walletHook?.isConnected()) {
      console.log('[AffiliateBalanceHook] Wallet not connected')
      return
    }

    const address = window.walletHook.address
    if (!address) {
      console.log('[AffiliateBalanceHook] No wallet address')
      return
    }

    try {
      // Use a read-only provider for Arbitrum (doesn't require user to be on Arbitrum)
      const provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL)
      const contract = new ethers.Contract(
        CONFIG.CONTRACT_ADDRESS,
        CONFIG.CONTRACT_ABI,
        provider
      )

      // Call getAffiliateInfo(address) - returns tuple with balance at index 5
      // returns (buyerCount, referreeCount, referredAffiliatesCount, totalSpent, earnings, balance, ...)
      const info = await contract.getAffiliateInfo(address)
      const balance = info[5].toString() // balance is at index 5

      console.log('[AffiliateBalanceHook] Fetched balance:', balance)

      // Push to LiveView
      this.pushEvent("affiliate_balance_fetched", { balance })

    } catch (error) {
      console.error('[AffiliateBalanceHook] Error fetching balance:', error)
      this.pushEvent("affiliate_balance_error", { error: error.message })
    }
  }
}

export default AffiliateBalanceHook
