// High Rollers NFT - Wallet Hook for Phoenix LiveView
// Bridges ethers.js wallet operations to LiveView via events
//
// Session Integration:
// - Calls /api/wallet/connect on connection to store in Phoenix session
// - Calls /api/wallet/disconnect on disconnect to clear session
// - Calls /api/wallet/balance on balance updates to sync session
// This eliminates wallet state flash on tab navigation.

import { CONFIG } from '../config.js'

// NOTE: Wallet logos, chain logos, and chain currencies are now server-rendered
// via session data in the layout template. These JS constants are no longer needed.

/**
 * WalletHook - Manages wallet connection and state for LiveView
 *
 * Attach to a container element (typically the wallet section in the layout):
 *   <div phx-hook="WalletHook" id="wallet-section">...</div>
 *
 * Events pushed TO LiveView:
 *   - wallet_connected: { address, type }
 *   - wallet_disconnected: {}
 *   - balance_updated: { balance, chain }
 *
 * Events handled FROM LiveView:
 *   - request_wallet_connect: Opens wallet connection modal/flow
 *   - request_disconnect: Disconnects the wallet
 *   - switch_network: { chain } - Switch to 'arbitrum' or 'rogue'
 */
// Arbitrum pages - mint and affiliates (affiliate withdrawals are on Arbitrum NFT contract)
const ARBITRUM_PAGES = ['/', '/mint', '/affiliates']

function getTargetChainForPath(pathname) {
  return ARBITRUM_PAGES.includes(pathname) ? 'arbitrum' : 'rogue'
}

const WalletHook = {
  mounted() {
    // Initialize wallet state
    this.provider = null
    this.signer = null
    this.address = null
    this.walletType = null
    this.currentChain = getTargetChainForPath(window.location.pathname)
    this.autoConnectComplete = false
    this.connectionInProgress = false  // Lock to prevent duplicate connection requests

    // EIP-6963: Store discovered wallet providers (avoids window.ethereum hijacking)
    this.eip6963Providers = new Map()
    this.setupEIP6963()

    // Set up event listeners from LiveView
    this.setupLiveViewEventHandlers()

    // Set up disconnect button click handler
    this.setupDisconnectButton()

    // Set up wallet modal option click handlers
    this.setupWalletModalOptions()

    // Listen for LiveView navigation to switch chains when URL changes
    this.setupNavigationListener()

    // Check for existing connection on mount (delayed to allow EIP-6963 discovery)
    setTimeout(() => this.checkExistingConnection(), 100)
  },

  // ===== EIP-6963: Multi Injected Provider Discovery =====
  // This avoids the window.ethereum hijacking problem where Coinbase/other wallets
  // override MetaMask. Each wallet announces itself independently.

  setupEIP6963() {
    // Listen for wallet announcements
    this.eip6963Handler = (event) => {
      const { info, provider } = event.detail
      console.log('[WalletHook] EIP-6963 wallet announced:', info.name, info.rdns)
      this.eip6963Providers.set(info.rdns, { info, provider })
    }
    window.addEventListener('eip6963:announceProvider', this.eip6963Handler)

    // Request wallets to announce themselves
    window.dispatchEvent(new Event('eip6963:requestProvider'))
  },

  getEIP6963Provider(walletType) {
    // Map our wallet types to EIP-6963 rdns identifiers
    const rdnsMap = {
      'metamask': 'io.metamask',
      'coinbase': 'com.coinbase.wallet',
      'rabby': 'io.rabby',
      'trust': 'com.trustwallet.app',
      'brave': 'com.brave.wallet',
      'okx': 'com.okex.wallet',
      'rainbow': 'me.rainbow',
      'zerion': 'io.zerion.wallet'
    }

    const rdns = rdnsMap[walletType]
    if (rdns && this.eip6963Providers.has(rdns)) {
      const { provider, info } = this.eip6963Providers.get(rdns)
      console.log('[WalletHook] Using EIP-6963 provider for', walletType, ':', info.name)
      return provider
    }

    // Also check for partial matches (some wallets use different rdns)
    for (const [key, { provider, info }] of this.eip6963Providers) {
      if (key.toLowerCase().includes(walletType.toLowerCase()) ||
          info.name.toLowerCase().includes(walletType.toLowerCase())) {
        console.log('[WalletHook] Using EIP-6963 provider (partial match):', info.name)
        return provider
      }
    }

    return null
  },

  setupDisconnectButton() {
    const disconnectBtn = document.getElementById('disconnect-btn')
    if (disconnectBtn) {
      this.handleDisconnectClick = () => this.disconnect()
      disconnectBtn.addEventListener('click', this.handleDisconnectClick)
    }
  },

  setupWalletModalOptions() {
    // Set up click handlers for wallet options in the modal
    const walletOptions = document.querySelectorAll('.wallet-option')
    this.walletOptionHandlers = []

    walletOptions.forEach(option => {
      const walletType = option.dataset.wallet
      const handler = async () => {
        try {
          await this.connectWallet(walletType)
          // Hide the modal after successful connection
          const modal = document.getElementById('wallet-modal')
          if (modal) {
            modal.classList.add('hidden')
            modal.classList.remove('flex')
          }
        } catch (error) {
          console.error('[WalletHook] Connection failed:', error)
        }
      }
      option.addEventListener('click', handler)
      this.walletOptionHandlers.push({ element: option, handler })
    })
  },

  setupNavigationListener() {
    // Listen for LiveView navigation completion to switch chains
    // phx:page-loading-stop fires after LiveView finishes navigating
    this.navigationHandler = async () => {
      const targetChain = getTargetChainForPath(window.location.pathname)

      console.log(`[WalletHook] Navigation: path=${window.location.pathname}, target=${targetChain}, current=${this.currentChain}, address=${this.address}`)

      if (!this.address) return // Not connected, nothing to do

      // Only switch if we're on the wrong chain
      if (this.currentChain !== targetChain) {
        console.log(`[WalletHook] Switching chain: ${this.currentChain} -> ${targetChain}`)
        await this.switchNetwork(targetChain)
        // Get balance and sync to session + push to LiveView in one go
        const balance = await this.getCurrentBalance()
        await this.syncToSession({
          address: this.address,
          type: this.walletType,
          chain: this.currentChain,
          balance: balance
        })
        // Push to LiveView (no separate session update needed - syncToSession already did it)
        this.pushEvent("balance_updated", { balance, chain: this.currentChain })
      }
      // If chain didn't change, no need to refresh - balance is still valid
    }
    window.addEventListener('phx:page-loading-stop', this.navigationHandler)
  },

  destroyed() {
    // Clean up wallet option listeners
    if (this.walletOptionHandlers) {
      this.walletOptionHandlers.forEach(({ element, handler }) => {
        element.removeEventListener('click', handler)
      })
    }

    // Clean up disconnect button listener
    const disconnectBtn = document.getElementById('disconnect-btn')
    if (disconnectBtn && this.handleDisconnectClick) {
      disconnectBtn.removeEventListener('click', this.handleDisconnectClick)
    }

    // Clean up navigation listener
    if (this.navigationHandler) {
      window.removeEventListener('phx:page-loading-stop', this.navigationHandler)
    }

    // Clean up EIP-6963 listener
    if (this.eip6963Handler) {
      window.removeEventListener('eip6963:announceProvider', this.eip6963Handler)
    }

    // Clean up event listeners
    if (window.ethereum) {
      window.ethereum.removeListener('accountsChanged', this.handleAccountsChanged)
      window.ethereum.removeListener('chainChanged', this.handleChainChanged)
    }
  },

  setupLiveViewEventHandlers() {
    // Handle wallet connect request from LiveView
    this.handleEvent("request_wallet_connect", async ({ wallet_type }) => {
      try {
        await this.connectWallet(wallet_type || 'metamask')
      } catch (error) {
        console.error('[WalletHook] Connection failed:', error)
        // Could push an error event here if needed
      }
    })

    // Handle disconnect request from LiveView
    this.handleEvent("request_disconnect", () => {
      this.disconnect()
    })

    // Handle network switch request from LiveView
    this.handleEvent("switch_network", async ({ chain }) => {
      await this.switchNetwork(chain)
    })

    // Handle balance refresh request
    this.handleEvent("refresh_balance", async () => {
      console.log('[WalletHook] refresh_balance event received')
      await this.pushCurrentBalance()
    })
  },

  // ===== Connection Methods =====

  async checkExistingConnection() {
    // Prevent duplicate connection checks
    if (this.connectionInProgress) {
      console.log('[WalletHook] Connection already in progress, skipping auto-connect check')
      return
    }

    if (!window.ethereum) {
      this.autoConnectComplete = true
      return
    }

    const walletType = localStorage.getItem('walletType')

    // If no walletType in localStorage, user explicitly disconnected - don't auto-reconnect
    if (!walletType) {
      this.autoConnectComplete = true
      return
    }

    try {
      // MetaMask is the source of truth - always check it
      const accounts = await window.ethereum.request({ method: 'eth_accounts' })

      if (accounts.length > 0) {
        // Connected - set up JS state silently (session already has correct data)
        // connectWallet already calls syncToSession internally, so we don't need to call it again
        await this.connectWallet(walletType, true, true)

        // After wallet is connected, switch to correct chain for current page
        const targetChain = getTargetChainForPath(window.location.pathname)
        if (this.currentChain !== targetChain) {
          console.log(`[WalletHook] Post-connect chain switch: ${this.currentChain} -> ${targetChain}`)
          await this.switchNetwork(targetChain)
          // After chain switch, update session with new chain's balance
          const balance = await this.getCurrentBalance()
          await this.syncToSession({
            address: this.address,
            type: this.walletType,
            chain: this.currentChain,
            balance: balance
          })
        }

        // Push balance update to LiveView (session was already synced in connectWallet or chain switch above)
        try {
          const balance = await this.getCurrentBalance()
          this.pushEvent("balance_updated", { balance, chain: this.currentChain })
        } catch (error) {
          console.log('[WalletHook] Could not push balance - LiveView not connected')
        }
      } else {
        // Not connected - if we have a walletType in localStorage, session might be stale
        if (walletType) {
          localStorage.removeItem('walletType')
          await this.clearSession()
          window.location.reload()
          return
        }
      }
    } catch (error) {
      console.log('[WalletHook] Auto-connect failed:', error)
      localStorage.removeItem('walletType')
    }

    this.autoConnectComplete = true
  },

  async connectWallet(walletType, skipRequest = false, skipLiveViewPush = false) {
    // Prevent duplicate connection requests
    if (this.connectionInProgress) {
      console.log('[WalletHook] Connection already in progress, skipping duplicate request')
      return
    }
    this.connectionInProgress = true

    try {
      return await this._doConnectWallet(walletType, skipRequest, skipLiveViewPush)
    } finally {
      this.connectionInProgress = false
    }
  },

  async _doConnectWallet(walletType, skipRequest = false, skipLiveViewPush = false) {
    // Handle mobile deep linking when no wallet provider is available
    if (this.isMobile() && !window.ethereum) {
      return this.handleMobileConnect(walletType)
    }

    if (!window.ethereum && this.eip6963Providers.size === 0) {
      throw new Error('No wallet found. Please install MetaMask or another Web3 wallet.')
    }

    // Try EIP-6963 first (modern, avoids hijacking issues)
    let provider = this.getEIP6963Provider(walletType)
    let resolvedWalletType = walletType

    if (provider) {
      console.log('[WalletHook] connectWallet: Using EIP-6963 provider for', walletType)
    } else {
      // Fall back to legacy window.ethereum detection
      const wallets = this.getAvailableWallets()
      const wallet = wallets.find(w => w.type === walletType) || wallets[0]

      console.log('[WalletHook] connectWallet (legacy fallback):', {
        requestedType: walletType,
        availableWallets: wallets.map(w => w.type),
        selectedWallet: wallet?.type,
        selectedProvider: wallet?.provider ? {
          isMetaMask: wallet.provider.isMetaMask,
          isCoinbaseWallet: wallet.provider.isCoinbaseWallet,
          isRabby: wallet.provider.isRabby
        } : null
      })

      if (!wallet) {
        throw new Error('No wallet found')
      }

      provider = wallet.provider
      resolvedWalletType = wallet.type
    }

    // Request account access (unless we're doing silent reconnect)
    let accounts
    if (skipRequest) {
      accounts = await provider.request({ method: 'eth_accounts' })
    } else {
      accounts = await provider.request({ method: 'eth_requestAccounts' })
    }

    if (accounts.length === 0) {
      throw new Error('No accounts found')
    }

    // Determine target chain based on current page
    const targetChain = getTargetChainForPath(window.location.pathname)

    // Only switch chains on fresh connect, not silent reconnect
    // Silent reconnect happens after page load - navigation handler will switch chains
    if (!skipLiveViewPush) {
      const currentChainId = await provider.request({ method: 'eth_chainId' })
      const isOnArbitrum = currentChainId.toLowerCase() === CONFIG.CHAIN_ID_HEX.toLowerCase()
      const isOnRogue = currentChainId.toLowerCase() === CONFIG.ROGUE_CHAIN_ID_HEX.toLowerCase()

      if (targetChain === 'arbitrum' && !isOnArbitrum) {
        await this.switchToArbitrum(provider)
      } else if (targetChain === 'rogue' && !isOnRogue) {
        await this.switchToRogueChain(provider)
      } else {
        this.currentChain = targetChain
      }
    } else {
      // Silent reconnect - just read current chain from MetaMask
      const currentChainId = await provider.request({ method: 'eth_chainId' })
      if (currentChainId.toLowerCase() === CONFIG.CHAIN_ID_HEX.toLowerCase()) {
        this.currentChain = 'arbitrum'
      } else if (currentChainId.toLowerCase() === CONFIG.ROGUE_CHAIN_ID_HEX.toLowerCase()) {
        this.currentChain = 'rogue'
      }
    }

    // Create ethers provider
    this.provider = new ethers.BrowserProvider(provider)
    this.signer = await this.provider.getSigner()
    this.address = await this.signer.getAddress()
    this.walletType = resolvedWalletType

    // Set up event listeners
    this.handleAccountsChanged = this.handleAccountsChanged.bind(this)
    this.handleChainChanged = this.handleChainChanged.bind(this)
    provider.on('accountsChanged', this.handleAccountsChanged)
    provider.on('chainChanged', this.handleChainChanged)

    // Only store wallet type for reconnection
    localStorage.setItem('walletType', resolvedWalletType)

    // Get initial balance
    const balance = await this.getCurrentBalance()

    // Store in Phoenix session for cross-tab persistence (no flash on navigation)
    await this.syncToSession({
      address: this.address,
      type: resolvedWalletType,
      chain: this.currentChain,
      balance: balance
    })

    // Check for referral link and link affiliate if present (fresh connect only)
    if (!skipLiveViewPush) {
      await this.checkAndLinkAffiliate()
    }

    // If this is a fresh connect (not silent reconnect), reload page so server
    // renders connected state from session cookie. LiveView WebSocket doesn't
    // see session changes until a full HTTP request.
    if (!skipLiveViewPush) {
      console.log('[WalletHook] Fresh connect - reloading page for session sync')
      window.location.reload()
      return { address: this.address, type: resolvedWalletType }
    }

    console.log('[WalletHook] Connected (silent reconnect):', this.address)

    return { address: this.address, type: resolvedWalletType }
  },

  async disconnect() {
    this.provider = null
    this.signer = null
    this.address = null
    this.walletType = null

    this.clearLocalStorage()

    // Remove event listeners
    if (window.ethereum) {
      window.ethereum.removeListener('accountsChanged', this.handleAccountsChanged)
      window.ethereum.removeListener('chainChanged', this.handleChainChanged)
    }

    // Clear session and reload page to get fresh state
    await this.clearSession()
    window.location.reload()
  },

  clearLocalStorage() {
    localStorage.removeItem('walletType')
  },

  // ===== Network Switching =====

  async switchNetwork(targetChain) {
    if (!window.ethereum || !this.address) return

    if (targetChain === 'arbitrum') {
      await this.switchToArbitrum()
    } else if (targetChain === 'rogue') {
      await this.switchToRogueChain()
    }
  },

  async switchToArbitrum(provider) {
    provider = provider || window.ethereum
    if (!provider) return

    try {
      await provider.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CONFIG.CHAIN_ID_HEX }]
      })
    } catch (error) {
      if (error.code === 4902) {
        // Chain not added - add it first
        await provider.request({
          method: 'wallet_addEthereumChain',
          params: [{
            chainId: CONFIG.CHAIN_ID_HEX,
            chainName: 'Arbitrum One',
            nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
            rpcUrls: [CONFIG.RPC_URL],
            blockExplorerUrls: [CONFIG.EXPLORER_URL]
          }]
        })
      } else if (error.code === 4001 || error.code === -32002) {
        // User rejected or request pending - don't throw
        return
      } else {
        throw error
      }
    }

    // Update provider after switch
    if (this.address) {
      this.provider = new ethers.BrowserProvider(provider)
      this.signer = await this.provider.getSigner()
    }
    this.currentChain = 'arbitrum'
  },

  async switchToRogueChain(provider) {
    provider = provider || window.ethereum
    if (!provider) return

    try {
      await provider.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CONFIG.ROGUE_CHAIN_ID_HEX }]
      })
    } catch (error) {
      if (error.code === 4902) {
        await provider.request({
          method: 'wallet_addEthereumChain',
          params: [{
            chainId: CONFIG.ROGUE_CHAIN_ID_HEX,
            chainName: CONFIG.ROGUE_CHAIN_NAME,
            nativeCurrency: CONFIG.ROGUE_CURRENCY,
            rpcUrls: [CONFIG.ROGUE_RPC_URL],
            blockExplorerUrls: [CONFIG.ROGUE_EXPLORER_URL]
          }]
        })
      } else if (error.code === 4001 || error.code === -32002) {
        return
      } else {
        throw error
      }
    }

    if (this.address) {
      this.provider = new ethers.BrowserProvider(provider)
      this.signer = await this.provider.getSigner()
    }
    this.currentChain = 'rogue'
  },

  // ===== Event Handlers =====

  handleAccountsChanged(accounts) {
    if (accounts.length === 0) {
      this.disconnect()
    } else {
      const newAddress = accounts[0]
      this.address = newAddress
      localStorage.setItem('walletAddress', newAddress.toLowerCase())

      // Push updated wallet to LiveView
      this.pushEvent("wallet_connected", {
        address: newAddress,
        type: this.walletType
      })

      // Refresh balance
      this.pushCurrentBalance()
    }
  },

  handleChainChanged(chainId) {
    const chainIdHex = typeof chainId === 'string' ? chainId : `0x${chainId.toString(16)}`

    if (chainIdHex.toLowerCase() === CONFIG.CHAIN_ID_HEX.toLowerCase()) {
      this.currentChain = 'arbitrum'
    } else if (chainIdHex.toLowerCase() === CONFIG.ROGUE_CHAIN_ID_HEX.toLowerCase()) {
      this.currentChain = 'rogue'
    }

    // Push chain change to LiveView - template handles logo/currency display
    this.pushEvent("wallet_chain_changed", { chain: this.currentChain })

    // Note: Don't call pushCurrentBalance() here - our navigation/connection code
    // already handles balance updates after chain switches to avoid duplicate API calls
  },

  // ===== Balance =====

  async getCurrentBalance() {
    try {
      if (this.currentChain === 'rogue' || !this.provider) {
        // Get ROGUE balance
        const rogueProvider = new ethers.JsonRpcProvider(CONFIG.ROGUE_RPC_URL)
        const balanceWei = await rogueProvider.getBalance(this.address)
        return ethers.formatEther(balanceWei)
      } else {
        // Get ETH balance on Arbitrum
        const balanceWei = await this.provider.getBalance(this.address)
        return ethers.formatEther(balanceWei)
      }
    } catch (error) {
      console.error('[WalletHook] getCurrentBalance failed:', error)
      return '0'
    }
  },

  async pushCurrentBalance() {
    try {
      const balance = await this.getCurrentBalance()
      const chain = this.currentChain

      console.log('[WalletHook] pushCurrentBalance:', { balance, chain, address: this.address })

      // Push event to LiveView first (immediate UI update)
      this.pushEvent("balance_updated", { balance, chain })

      // Then update Phoenix session (for page reloads)
      this.updateSessionBalance(balance, chain)
    } catch (error) {
      console.error('[WalletHook] Balance fetch failed:', error)
    }
  },

  // ===== Affiliate Linking =====

  async checkAndLinkAffiliate() {
    // Check for ref parameter in URL
    const urlParams = new URLSearchParams(window.location.search)
    const affiliate = urlParams.get('ref')

    if (!affiliate || !this.address) return

    // Validate affiliate address format
    if (!/^0x[a-fA-F0-9]{40}$/.test(affiliate)) {
      console.log('[WalletHook] Invalid affiliate address format:', affiliate)
      return
    }

    // Don't self-refer
    if (affiliate.toLowerCase() === this.address.toLowerCase()) {
      console.log('[WalletHook] Cannot self-refer')
      return
    }

    try {
      console.log('[WalletHook] Linking affiliate:', affiliate, 'for buyer:', this.address)
      const response = await fetch('/api/link-affiliate', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-csrf-token': this.getCsrfToken()
        },
        body: JSON.stringify({
          buyer: this.address,
          affiliate: affiliate
        })
      })

      const result = await response.json()
      if (result.success) {
        console.log('[WalletHook] Affiliate linked:', result)
      } else {
        console.log('[WalletHook] Affiliate link failed:', result.error)
      }
    } catch (error) {
      console.error('[WalletHook] Affiliate link error:', error)
    }
  },

  // ===== Session API Methods =====

  getCsrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
  },

  async syncToSession({ address, type, chain, balance }) {
    // Prevent duplicate sync requests within 500ms
    const now = Date.now()
    if (this.lastSyncTime && (now - this.lastSyncTime) < 500) {
      console.log('[WalletHook] Skipping duplicate sync request (debounced)')
      return
    }
    this.lastSyncTime = now

    try {
      console.log('[WalletHook] Syncing to session:', { address, chain })
      await fetch('/api/wallet/connect', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-csrf-token': this.getCsrfToken()
        },
        body: JSON.stringify({ address, type, chain, balance })
      })
    } catch (error) {
      console.error('[WalletHook] Session sync failed:', error)
    }
  },

  async clearSession() {
    try {
      await fetch('/api/wallet/disconnect', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-csrf-token': this.getCsrfToken()
        }
      })
    } catch (error) {
      console.error('[WalletHook] Session clear failed:', error)
    }
  },

  async updateSessionBalance(balance, chain) {
    try {
      await fetch('/api/wallet/balance', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-csrf-token': this.getCsrfToken()
        },
        body: JSON.stringify({ balance, chain })
      })
    } catch (error) {
      console.error('[WalletHook] Session balance update failed:', error)
    }
  },

  // ===== Utility Methods =====

  isMobile() {
    return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent)
  },

  handleMobileConnect(walletType) {
    // Deep link to wallet apps on mobile
    const currentUrl = window.location.href
    let deepLink

    switch (walletType) {
      case 'metamask':
        deepLink = `https://metamask.app.link/dapp/${currentUrl.replace(/^https?:\/\//, '')}`
        break
      case 'coinbase':
        deepLink = `https://go.cb-w.com/dapp?cb_url=${encodeURIComponent(currentUrl)}`
        break
      case 'trust':
        deepLink = `https://link.trustwallet.com/open_url?coin_id=60&url=${encodeURIComponent(currentUrl)}`
        break
      default:
        deepLink = `https://metamask.app.link/dapp/${currentUrl.replace(/^https?:\/\//, '')}`
    }

    window.location.href = deepLink
    return new Promise(() => {}) // Never resolves - page will redirect
  },

  getAvailableWallets() {
    const available = []
    const ethereum = window.ethereum

    // Debug logging for wallet detection issues
    console.log('[WalletHook] getAvailableWallets debug:', {
      ethereum: !!ethereum,
      isMetaMask: ethereum?.isMetaMask,
      isCoinbaseWallet: ethereum?.isCoinbaseWallet,
      isRabby: ethereum?.isRabby,
      isTrust: ethereum?.isTrust,
      isBraveWallet: ethereum?.isBraveWallet,
      providersCount: ethereum?.providers?.length,
      providers: ethereum?.providers?.map(p => ({
        isMetaMask: p.isMetaMask,
        isCoinbaseWallet: p.isCoinbaseWallet,
        isRabby: p.isRabby,
        isTrust: p.isTrust
      })),
      eip6963Providers: Array.from(this.eip6963Providers.entries()).map(([rdns, { info }]) => ({
        rdns,
        name: info.name,
        uuid: info.uuid
      }))
    })

    if (!ethereum && this.isMobile()) {
      // Return wallets with deep link support for mobile
      return [
        { type: 'metamask', provider: null, isMobileDeepLink: true },
        { type: 'coinbase', provider: null, isMobileDeepLink: true },
        { type: 'trust', provider: null, isMobileDeepLink: true }
      ]
    }

    if (!ethereum) return available

    // Check for multiple providers
    if (ethereum.providers?.length) {
      for (const provider of ethereum.providers) {
        if (provider.isMetaMask && !provider.isCoinbaseWallet) {
          available.push({ type: 'metamask', provider })
        }
        if (provider.isCoinbaseWallet) {
          available.push({ type: 'coinbase', provider })
        }
        if (provider.isRabby) {
          available.push({ type: 'rabby', provider })
        }
      }
    } else {
      // Single provider
      if (ethereum.isMetaMask && !ethereum.isCoinbaseWallet) {
        available.push({ type: 'metamask', provider: ethereum })
      } else if (ethereum.isCoinbaseWallet) {
        available.push({ type: 'coinbase', provider: ethereum })
      } else if (ethereum.isRabby) {
        available.push({ type: 'rabby', provider: ethereum })
      } else if (ethereum.isTrust) {
        available.push({ type: 'trust', provider: ethereum })
      } else if (ethereum.isBraveWallet) {
        available.push({ type: 'brave', provider: ethereum })
      } else {
        available.push({ type: 'other', provider: ethereum })
      }
    }

    return available
  },

  // ===== Contract Access (for other hooks) =====

  getContract() {
    if (!this.signer) return null
    return new ethers.Contract(CONFIG.CONTRACT_ADDRESS, CONFIG.CONTRACT_ABI, this.signer)
  },

  getReadOnlyContract() {
    const provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL)
    return new ethers.Contract(CONFIG.CONTRACT_ADDRESS, CONFIG.CONTRACT_ABI, provider)
  },

  isConnected() {
    return !!this.address
  }
}

// Export the hook and also expose wallet instance globally for other hooks
export default WalletHook

// Expose a global reference so other hooks can access wallet state
window.walletHook = null
const OriginalMounted = WalletHook.mounted
WalletHook.mounted = function() {
  window.walletHook = this
  OriginalMounted.call(this)
}
