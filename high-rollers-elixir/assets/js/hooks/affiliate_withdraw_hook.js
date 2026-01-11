// High Rollers NFT - Affiliate Withdraw Hook for Phoenix LiveView
// Handles affiliate withdrawal transactions on Arbitrum

import { CONFIG } from '../config.js'

/**
 * AffiliateWithdrawHook - Handles affiliate earnings withdrawal on Arbitrum
 *
 * Attach to the withdraw button on the Affiliates page:
 *   <button phx-hook="AffiliateWithdrawHook"
 *           id="affiliate-withdraw-btn"
 *           data-balance={@affiliate_stats.balance}>
 *     Withdraw <%= format_eth(@affiliate_stats.balance) %> ETH
 *   </button>
 *
 * Events pushed TO LiveView:
 *   - withdraw_started: { tx_hash }
 *   - withdraw_success: { tx_hash }
 *   - withdraw_error: { error }
 *
 * Note: This hook requires the user to be on Arbitrum network.
 * If on wrong network, it will attempt to switch automatically.
 */
const AffiliateWithdrawHook = {
  mounted() {
    this.withdrawing = false

    this.el.addEventListener('click', async (e) => {
      e.preventDefault()
      await this.withdraw()
    })
  },

  async withdraw() {
    // Prevent double-click
    if (this.withdrawing) {
      console.log('[AffiliateWithdrawHook] Withdrawal already in progress')
      return
    }

    // Check wallet connection
    if (!window.walletHook?.isConnected()) {
      this.pushEvent("withdraw_error", { error: 'Please connect your wallet first' })
      return
    }

    // Check balance
    const balance = this.el.dataset.balance
    if (!balance || balance === '0') {
      this.pushEvent("withdraw_error", { error: 'No balance to withdraw' })
      return
    }

    this.withdrawing = true
    this.el.disabled = true
    // Store original button text and show small inline spinner
    this.originalText = this.el.innerHTML
    this.el.innerHTML = `<span class="inline-flex items-center gap-2"><span class="inline-block w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></span>Withdrawing...</span>`

    try {
      // Ensure we're on Arbitrum
      if (window.walletHook.currentChain !== 'arbitrum') {
        console.log('[AffiliateWithdrawHook] Switching to Arbitrum...')
        await window.walletHook.switchNetwork('arbitrum')
      }

      // Get the NFT contract with signer
      const contract = window.walletHook.getContract()
      if (!contract) {
        throw new Error('Unable to get contract')
      }

      // Call withdrawFromAffiliate on the Arbitrum NFT contract
      const tx = await contract.withdrawFromAffiliate()
      console.log('[AffiliateWithdrawHook] TX sent:', tx.hash)

      // Notify LiveView that withdrawal has started
      this.pushEvent("withdraw_started", { tx_hash: tx.hash })

      // Wait for confirmation
      const receipt = await tx.wait()
      console.log('[AffiliateWithdrawHook] TX confirmed:', receipt)

      // Notify LiveView of success
      this.pushEvent("withdraw_success", { tx_hash: tx.hash })

      // Show success in button with tx link
      this.el.innerHTML = `<span class="inline-flex items-center gap-2">✓ <a href="https://arbiscan.io/tx/${tx.hash}" target="_blank" class="underline">View TX</a></span>`
      this.el.classList.remove('bg-yellow-600', 'hover:bg-yellow-700')
      this.el.classList.add('bg-green-600')

      // Refresh wallet balance in header (user received ETH from withdrawal)
      if (window.walletHook?.pushCurrentBalance) {
        console.log('[AffiliateWithdrawHook] Refreshing wallet balance...')
        await window.walletHook.pushCurrentBalance()
      }

    } catch (error) {
      console.error('[AffiliateWithdrawHook] Error:', error)

      // Parse error message
      let errorMsg = 'Withdrawal failed'
      if (error.code === 'ACTION_REJECTED') {
        errorMsg = 'Transaction rejected by user'
      } else if (error.code === 'INSUFFICIENT_FUNDS') {
        errorMsg = 'Insufficient ETH for gas'
      } else if (error.message?.includes('no balance')) {
        errorMsg = 'No affiliate balance to withdraw'
      } else if (error.message) {
        errorMsg = error.message.substring(0, 100)
      }

      this.pushEvent("withdraw_error", { error: errorMsg })

      // Show error in button and restore after 3 seconds
      this.el.innerHTML = `<span class="text-red-200">✗ Failed</span>`
      this.el.classList.remove('bg-yellow-600', 'hover:bg-yellow-700')
      this.el.classList.add('bg-red-600')

      setTimeout(() => {
        if (this.originalText) {
          this.el.innerHTML = this.originalText
          this.el.classList.remove('bg-red-600')
          this.el.classList.add('bg-yellow-600', 'hover:bg-yellow-700')
        }
      }, 3000)

    } finally {
      this.withdrawing = false
      this.el.disabled = false
    }
  }
}

export default AffiliateWithdrawHook
