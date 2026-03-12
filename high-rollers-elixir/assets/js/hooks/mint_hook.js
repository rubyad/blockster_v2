// High Rollers NFT - Mint Hook for Phoenix LiveView
// Handles NFT minting transaction and VRF waiting state

import { CONFIG } from '../config.js'

/**
 * MintHook - Manages NFT minting for LiveView
 *
 * Attach to the mint button or mint section:
 *   <button phx-hook="MintHook" id="mint-button">Mint NFT</button>
 *
 * Events pushed TO LiveView:
 *   - mint_requested: { request_id, token_id, tx_hash }
 *   - mint_complete: { request_id, token_id, hostess_index, hostess_name, tx_hash }
 *   - mint_error: { error }
 *
 * Events handled FROM LiveView:
 *   - start_mint: Triggers the mint process
 *   - nft_minted: { recipient, token_id, hostess_index } - Server-side notification of mint completion
 */
const MintHook = {
  mounted() {
    this.pendingMint = null
    this.pollInterval = null
    this.maxPollAttempts = 60  // 5 minutes at 5-second intervals
    this.pollAttempts = 0

    this.setupEventHandlers()
  },

  destroyed() {
    this.stopFallbackPolling()
  },

  setupEventHandlers() {
    // Handle mint request from LiveView (e.g., from a phx-click that triggers this)
    this.handleEvent("start_mint", async () => {
      await this.mint()
    })

    // Handle server notification of mint completion (from PubSub broadcast)
    this.handleEvent("nft_minted", (data) => {
      this.handleServerMintEvent(data)
    })

    // Listen for click on the element itself
    this.el.addEventListener('click', async (e) => {
      e.preventDefault()
      await this.mint()
    })
  },

  async mint() {
    // Check wallet connection via global reference
    if (!window.walletHook?.isConnected()) {
      this.pushEvent("mint_error", { error: 'Please connect your wallet first' })
      return
    }

    // Prevent double-mint
    if (this.pendingMint) {
      console.log('[MintHook] Mint already in progress')
      return
    }

    try {
      const contract = window.walletHook.getContract()
      if (!contract) {
        throw new Error('Unable to get contract')
      }

      // Check balance before attempting mint
      const provider = window.walletHook.provider
      const balance = await provider.getBalance(window.walletHook.address)
      const mintPrice = BigInt(CONFIG.MINT_PRICE)

      if (balance < mintPrice) {
        const balanceEth = Number(balance) / 1e18
        throw new Error(`Insufficient ETH balance. You have ${balanceEth.toFixed(4)} ETH but need ${CONFIG.MINT_PRICE_ETH} ETH`)
      }

      // Send mint transaction
      const tx = await contract.requestNFT({
        value: CONFIG.MINT_PRICE
      })

      console.log('[MintHook] Mint transaction sent:', tx.hash)

      // Wait for confirmation
      const receipt = await tx.wait()
      console.log('[MintHook] Transaction confirmed:', receipt)

      // Parse the NFTRequested event from the receipt
      let requestId, tokenId

      for (const log of receipt.logs) {
        try {
          const parsed = contract.interface.parseLog({
            topics: log.topics,
            data: log.data
          })
          if (parsed && parsed.name === 'NFTRequested') {
            requestId = parsed.args[0].toString()
            tokenId = parsed.args[3].toString()
            break
          }
        } catch (e) {
          // Not our event, skip
        }
      }

      if (requestId) {
        this.pendingMint = {
          requestId,
          tokenId,
          txHash: tx.hash,
          timestamp: Date.now()
        }

        // Notify LiveView that mint is requested (waiting for VRF)
        this.pushEvent("mint_requested", {
          request_id: requestId,
          token_id: tokenId,
          tx_hash: tx.hash
        })

        // Start fallback polling in case we miss the server event
        this.startFallbackPolling()
      }

    } catch (error) {
      console.error('[MintHook] Mint error:', error)

      let errorMsg = 'Mint failed'
      if (error.code === 'ACTION_REJECTED') {
        errorMsg = 'Transaction rejected'
      } else if (error.code === 'INSUFFICIENT_FUNDS') {
        errorMsg = 'Insufficient ETH balance'
      } else if (error.message?.includes('Insufficient ETH balance')) {
        // Our custom balance check error - use full message
        errorMsg = error.message
      } else if (error.message?.includes('missing revert data')) {
        // Gas estimation failed - usually insufficient balance or contract issue
        errorMsg = 'Transaction would fail - check your ETH balance'
      } else if (error.message) {
        // Truncate other errors
        errorMsg = error.message.substring(0, 80)
      }

      this.pushEvent("mint_error", { error: errorMsg })
    }
  },

  /**
   * Handle server notification of mint completion (via PubSub/LiveView)
   */
  handleServerMintEvent(data) {
    // Check if this is our mint
    if (this.pendingMint &&
        data.recipient?.toLowerCase() === window.walletHook?.address?.toLowerCase()) {
      this.handleMintComplete(data.request_id || this.pendingMint.requestId, data.token_id, data.hostess_index)
    }
  },

  /**
   * Fallback polling: Check if our NFT was minted even if we miss the server event
   */
  startFallbackPolling() {
    this.pollAttempts = 0

    this.pollInterval = setInterval(async () => {
      this.pollAttempts++

      if (this.pollAttempts > this.maxPollAttempts) {
        this.stopFallbackPolling()
        console.error('[MintHook] Mint polling timeout')
        this.pushEvent("mint_error", { error: 'Mint confirmation timeout - check Arbiscan for status' })
        this.pendingMint = null
        return
      }

      try {
        const tokenId = parseInt(this.pendingMint.tokenId)
        const contract = window.walletHook.getReadOnlyContract()

        const owner = await contract.ownerOf(tokenId)

        if (owner && owner.toLowerCase() === window.walletHook.address.toLowerCase()) {
          // Our NFT was minted!
          console.log(`[MintHook] NFT ${tokenId} minted successfully (via polling)`)

          const hostessIndex = await contract.s_tokenIdToHostess(tokenId)
          this.handleMintComplete(this.pendingMint.requestId, tokenId, Number(hostessIndex))
          this.stopFallbackPolling()
        }
      } catch (error) {
        // Token doesn't exist yet, keep polling
        console.log(`[MintHook] Poll attempt ${this.pollAttempts}: waiting for VRF...`)
      }
    }, 5000) // Poll every 5 seconds
  },

  stopFallbackPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
      this.pollInterval = null
    }
  },

  handleMintComplete(requestId, tokenId, hostessIndex) {
    this.stopFallbackPolling()

    const hostess = CONFIG.HOSTESSES[hostessIndex]

    this.pushEvent("mint_complete", {
      request_id: requestId?.toString(),
      token_id: tokenId?.toString(),
      hostess_index: hostessIndex,
      hostess_name: hostess?.name || 'Unknown',
      hostess_rarity: hostess?.rarity || 'Unknown',
      hostess_multiplier: hostess?.multiplier || 0,
      hostess_image: hostess?.image || '',
      tx_hash: this.pendingMint?.txHash
    })

    this.pendingMint = null
  },

  isMinting() {
    return this.pendingMint !== null
  }
}

export default MintHook
