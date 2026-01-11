// High Rollers NFT - Wallet Service

class WalletService {
  constructor() {
    this.provider = null;
    this.signer = null;
    this.address = null;
    this.walletType = null;
    this.currentChain = 'arbitrum';
    this.rogueBalance = '0';
    this.onConnectCallbacks = [];
    this.onDisconnectCallbacks = [];
    this.onBalanceUpdateCallbacks = [];
    this.autoConnectComplete = false;
    this.autoConnectPromise = null;

    // Wallet configurations with logos
    this.walletConfigs = {
      metamask: { name: 'MetaMask', logo: '/images/wallets/metamask.svg' },
      coinbase: { name: 'Coinbase Wallet', logo: '/images/wallets/coinbase.svg' },
      rabby: { name: 'Rabby', logo: '/images/wallets/rabby.svg' },
      trust: { name: 'Trust Wallet', logo: '/images/wallets/trust.svg' },
      brave: { name: 'Brave Wallet', logo: '/images/wallets/brave.svg' },
      other: { name: 'Browser Wallet', logo: '/images/wallets/generic.svg' }
    };

    // Check for existing connection on page load
    this.autoConnectPromise = this.checkExistingConnection();
  }

  /**
   * Wait for auto-connect to complete before proceeding
   */
  async waitForAutoConnect() {
    if (this.autoConnectComplete) return;
    await this.autoConnectPromise;
  }

  /**
   * Detect if user is on mobile device
   */
  isMobile() {
    return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
  }

  /**
   * Check if we're inside a wallet's in-app browser
   */
  isInWalletBrowser() {
    return !!window.ethereum;
  }

  /**
   * Get deep link URL for opening in MetaMask mobile app
   */
  getMetaMaskDeepLink() {
    // Get current URL with any referral params
    const currentUrl = window.location.href;
    // MetaMask deep link format: metamask://dapp/domain.com/path
    // Using the universal link format which works better on iOS
    return `https://metamask.app.link/dapp/${currentUrl.replace(/^https?:\/\//, '')}`;
  }

  /**
   * Get deep link URL for Coinbase Wallet mobile app
   */
  getCoinbaseDeepLink() {
    const currentUrl = window.location.href;
    return `https://go.cb-w.com/dapp?cb_url=${encodeURIComponent(currentUrl)}`;
  }

  /**
   * Get deep link URL for Trust Wallet mobile app
   */
  getTrustDeepLink() {
    const currentUrl = window.location.href;
    return `https://link.trustwallet.com/open_url?coin_id=60&url=${encodeURIComponent(currentUrl)}`;
  }

  /**
   * Handle mobile wallet connection via deep links
   * Opens the wallet app which will load this site in its in-app browser
   */
  handleMobileConnect(walletType) {
    let deepLink;
    let walletName;

    switch (walletType) {
      case 'metamask':
        deepLink = this.getMetaMaskDeepLink();
        walletName = 'MetaMask';
        break;
      case 'coinbase':
        deepLink = this.getCoinbaseDeepLink();
        walletName = 'Coinbase Wallet';
        break;
      case 'trust':
        deepLink = this.getTrustDeepLink();
        walletName = 'Trust Wallet';
        break;
      default:
        // Default to MetaMask for unknown wallet types on mobile
        deepLink = this.getMetaMaskDeepLink();
        walletName = 'MetaMask';
    }

    // Redirect to wallet app - this will open the wallet's in-app browser
    console.log(`[Wallet] Opening ${walletName} app with deep link:`, deepLink);
    window.location.href = deepLink;

    // Return a pending promise that never resolves (page will redirect)
    // This prevents the UI from showing errors
    return new Promise(() => {});
  }

  /**
   * Get all available wallets for UI display
   * On mobile without window.ethereum, returns wallets that support deep linking
   */
  getAvailableWallets() {
    const available = [];
    const ethereum = window.ethereum;

    // On mobile without a wallet browser, show wallets with deep link support
    if (!ethereum && this.isMobile()) {
      available.push({
        type: 'metamask',
        ...this.walletConfigs.metamask,
        provider: null,
        isMobileDeepLink: true
      });
      available.push({
        type: 'coinbase',
        ...this.walletConfigs.coinbase,
        provider: null,
        isMobileDeepLink: true
      });
      available.push({
        type: 'trust',
        ...this.walletConfigs.trust,
        provider: null,
        isMobileDeepLink: true
      });
      return available;
    }

    if (!ethereum) return available;

    // Check for multiple providers
    if (ethereum.providers?.length) {
      for (const provider of ethereum.providers) {
        if (provider.isMetaMask && !provider.isCoinbaseWallet) {
          available.push({ type: 'metamask', ...this.walletConfigs.metamask, provider });
        }
        if (provider.isCoinbaseWallet) {
          available.push({ type: 'coinbase', ...this.walletConfigs.coinbase, provider });
        }
        if (provider.isRabby) {
          available.push({ type: 'rabby', ...this.walletConfigs.rabby, provider });
        }
      }
    } else {
      // Single provider
      if (ethereum.isMetaMask && !ethereum.isCoinbaseWallet) {
        available.push({ type: 'metamask', ...this.walletConfigs.metamask, provider: ethereum });
      } else if (ethereum.isCoinbaseWallet) {
        available.push({ type: 'coinbase', ...this.walletConfigs.coinbase, provider: ethereum });
      } else if (ethereum.isRabby) {
        available.push({ type: 'rabby', ...this.walletConfigs.rabby, provider: ethereum });
      } else if (ethereum.isTrust) {
        available.push({ type: 'trust', ...this.walletConfigs.trust, provider: ethereum });
      } else if (ethereum.isBraveWallet) {
        available.push({ type: 'brave', ...this.walletConfigs.brave, provider: ethereum });
      } else {
        available.push({ type: 'other', ...this.walletConfigs.other, provider: ethereum });
      }
    }

    return available;
  }

  /**
   * Connect to a specific wallet type
   */
  async connectWallet(walletType) {
    // Handle mobile deep linking when no wallet provider is available
    if (this.isMobile() && !this.isInWalletBrowser()) {
      return this.handleMobileConnect(walletType);
    }

    const wallets = this.getAvailableWallets();
    const wallet = wallets.find(w => w.type === walletType) || wallets[0];

    if (!wallet) {
      // On desktop, suggest installing a wallet
      throw new Error('No wallet found. Please install MetaMask or another Web3 wallet.');
    }

    const provider = wallet.provider;

    // Request account access
    const accounts = await provider.request({ method: 'eth_requestAccounts' });

    if (accounts.length === 0) {
      throw new Error('No accounts found');
    }

    // Switch to Arbitrum
    await this.switchToArbitrum(provider);

    // Create ethers provider
    this.provider = new ethers.BrowserProvider(provider);
    this.signer = await this.provider.getSigner();
    this.address = await this.signer.getAddress();
    this.walletType = wallet.type;

    // Set up event listeners
    provider.on('accountsChanged', this.handleAccountsChanged.bind(this));
    provider.on('chainChanged', this.handleChainChanged.bind(this));

    // Store connection state
    localStorage.setItem('walletConnected', 'true');
    localStorage.setItem('walletType', wallet.type);

    // Link buyer to affiliate permanently in the database
    // This ensures the first referrer always gets credit
    if (window.affiliateService) {
      await window.affiliateService.linkBuyerToAffiliate(this.address);
    }

    // Trigger callbacks
    this.onConnectCallbacks.forEach(cb => cb(this.address, this.walletType));

    return { address: this.address, type: wallet.type, logo: wallet.logo };
  }

  async switchToArbitrum(provider) {
    provider = provider || window.ethereum;
    if (!provider) return;

    try {
      await provider.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CONFIG.CHAIN_ID_HEX }]
      });
    } catch (error) {
      // 4902 = chain not added to wallet, need to add it first
      if (error.code === 4902) {
        await provider.request({
          method: 'wallet_addEthereumChain',
          params: [{
            chainId: CONFIG.CHAIN_ID_HEX,
            chainName: 'Arbitrum One',
            nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
            rpcUrls: [CONFIG.RPC_URL],
            blockExplorerUrls: [CONFIG.EXPLORER_URL]
          }]
        });
      } else if (error.code === 4001) {
        // User rejected the switch - that's okay, don't throw
        console.log('User rejected network switch to Arbitrum');
        return;
      } else if (error.code === -32002) {
        // Request already pending in wallet
        console.log('Network switch request already pending');
        return;
      } else {
        throw error;
      }
    }

    // Update provider after switch
    if (this.address) {
      this.provider = new ethers.BrowserProvider(provider);
      this.signer = await this.provider.getSigner();
    }
    this.currentChain = 'arbitrum';
  }

  async switchToRogueChain(provider) {
    provider = provider || window.ethereum;
    if (!provider) return;

    try {
      await provider.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CONFIG.ROGUE_CHAIN_ID_HEX }]
      });
    } catch (error) {
      // 4902 = chain not added to wallet, need to add it first
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
        });
      } else if (error.code === 4001) {
        // User rejected the switch - that's okay, don't throw
        console.log('User rejected network switch to Rogue Chain');
        return;
      } else if (error.code === -32002) {
        // Request already pending in wallet
        console.log('Network switch request already pending');
        return;
      } else {
        throw error;
      }
    }

    // Update provider after switch
    if (this.address) {
      this.provider = new ethers.BrowserProvider(provider);
      this.signer = await this.provider.getSigner();
    }
    this.currentChain = 'rogue';
  }

  async switchNetwork(targetChain) {
    if (!window.ethereum || !this.address) return;

    if (targetChain === 'arbitrum') {
      await this.switchToArbitrum();
    } else if (targetChain === 'rogue') {
      await this.switchToRogueChain();
    }
  }

  getCurrentChain() {
    return this.currentChain || 'arbitrum';
  }

  async checkExistingConnection() {
    const wasConnected = localStorage.getItem('walletConnected') === 'true';
    const walletType = localStorage.getItem('walletType');

    if (wasConnected && window.ethereum) {
      try {
        const accounts = await window.ethereum.request({ method: 'eth_accounts' });
        if (accounts.length > 0) {
          await this.connectWallet(walletType || 'metamask');
        } else {
          // User disconnected from MetaMask - clear stale localStorage
          console.log('[Wallet] No accounts available - user disconnected from MetaMask');
          localStorage.removeItem('walletConnected');
          localStorage.removeItem('walletType');
          // Trigger disconnect callbacks to update UI
          this.onDisconnectCallbacks.forEach(cb => cb());
        }
      } catch (error) {
        console.log('Auto-connect failed:', error);
        localStorage.removeItem('walletConnected');
        localStorage.removeItem('walletType');
      }
    }

    // Mark auto-connect as complete so app can proceed with routing
    this.autoConnectComplete = true;
  }

  handleAccountsChanged(accounts) {
    if (accounts.length === 0) {
      this.disconnect();
    } else {
      this.address = accounts[0];
      this.onConnectCallbacks.forEach(cb => cb(this.address, this.walletType));
    }
  }

  handleChainChanged(chainId) {
    // Update current chain based on chainId
    const chainIdHex = typeof chainId === 'string' ? chainId : `0x${chainId.toString(16)}`;
    if (chainIdHex.toLowerCase() === CONFIG.CHAIN_ID_HEX.toLowerCase()) {
      this.currentChain = 'arbitrum';
    } else if (chainIdHex.toLowerCase() === CONFIG.ROGUE_CHAIN_ID_HEX.toLowerCase()) {
      this.currentChain = 'rogue';
    }
    // Notify listeners of balance update (chain changed means balance display may change)
    this.onBalanceUpdateCallbacks.forEach(cb => cb());
  }

  disconnect() {
    this.provider = null;
    this.signer = null;
    this.address = null;
    this.walletType = null;
    this.currentChain = 'arbitrum';
    this.rogueBalance = '0';
    localStorage.removeItem('walletConnected');
    localStorage.removeItem('walletType');
    this.onDisconnectCallbacks.forEach(cb => cb());
  }

  getWalletLogo() {
    return this.walletConfigs[this.walletType]?.logo || this.walletConfigs.other.logo;
  }

  onConnect(callback) {
    this.onConnectCallbacks.push(callback);
    // If already connected, call immediately
    if (this.address) {
      callback(this.address, this.walletType);
    }
  }

  onDisconnect(callback) {
    this.onDisconnectCallbacks.push(callback);
  }

  onBalanceUpdate(callback) {
    this.onBalanceUpdateCallbacks.push(callback);
  }

  isConnected() {
    return !!this.address;
  }

  async getBalance() {
    if (!this.provider || !this.address) return '0';
    const balance = await this.provider.getBalance(this.address);
    return ethers.formatEther(balance);
  }

  async getROGUEBalance() {
    if (!this.address) return '0';
    try {
      // Use Rogue Chain RPC directly to get balance
      const rogueProvider = new ethers.JsonRpcProvider(CONFIG.ROGUE_RPC_URL);
      const balance = await rogueProvider.getBalance(this.address);
      this.rogueBalance = ethers.formatEther(balance);
      return this.rogueBalance;
    } catch (error) {
      console.error('Failed to get ROGUE balance:', error);
      return '0';
    }
  }

  async refreshROGUEBalance() {
    const balance = await this.getROGUEBalance();
    this.onBalanceUpdateCallbacks.forEach(cb => cb());
    return balance;
  }

  getContract() {
    if (!this.signer) return null;
    return new ethers.Contract(CONFIG.CONTRACT_ADDRESS, CONFIG.CONTRACT_ABI, this.signer);
  }

  getReadOnlyContract() {
    const provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
    return new ethers.Contract(CONFIG.CONTRACT_ADDRESS, CONFIG.CONTRACT_ABI, provider);
  }

  truncateAddress(address) {
    if (!address) return '';
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  }
}

// Global wallet service instance
window.walletService = new WalletService();
