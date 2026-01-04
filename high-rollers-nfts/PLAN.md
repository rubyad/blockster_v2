# High Rollers NFT Minting App - Implementation Plan

## Overview

A standalone Node.js application for the Rogue High Rollers NFT collection on Arbitrum One. Users connect their wallet (MetaMask, Coinbase Wallet, or others) via ethers.js, mint NFTs for 0.32 ETH, and see real-time updates of their minted NFT type (determined by Chainlink VRF).

**Key Value Proposition**: High Rollers NFTs earn a share of every winning bet on the platform - passive income forever.

## Smart Contract Details

- **Contract Address**: `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD`
- **Network**: Arbitrum One (Chain ID: 42161)
- **Current Price**: 0.32 ETH (320000000000000000 wei)
- **Contract Max Supply**: 10,000 NFTs (hardcoded in contract)
- **App Max Supply**: 2,700 NFTs (we stop minting after this)
- **Currently Minted**: 2,339 NFTs
- **Remaining to Mint**: 361 NFTs (2700 - 2339)

## NFT Types (8 Hostesses) with Rarity & Multipliers

| Index | Name | Rarity | Multiplier | Actual Count | Actual % |
|-------|------|--------|------------|--------------|----------|
| 0 | Penelope Fatale | 0.5% | **100x** | **9** | 0.38% |
| 1 | Mia Siren | 1.0% | **90x** | **21** | 0.90% |
| 2 | Cleo Enchante | 3.5% | **80x** | **113** | 4.83% |
| 3 | Sophia Spark | 7.5% | **70x** | **149** | 6.37% |
| 4 | Luna Mirage | 12.5% | **60x** | **274** | 11.71% |
| 5 | Aurora Seductra | 25.0% | **50x** | **580** | 24.80% |
| 6 | Scarlett Ember | 25.0% | **40x** | **577** | 24.67% |
| 7 | Vivienne Allure | 25.0% | **30x** | **616** | 26.34% |

**How Rarity Works**: Chainlink VRF generates a random number to determine NFT type at mint time
**Multiplier**: Revenue share weight - higher multiplier = larger share of the revenue pool

**Total Minted**: 2,339 NFTs

**Note**: First 1060 NFTs were airdrops to Digitex holders (may have different distribution than random mints).

## Affiliate System

- **Tier 1 Affiliate**: 20% of mint price (0.064 ETH per mint)
- **Tier 2 Affiliate**: 5% of mint price (0.016 ETH per mint)
- **Default Affiliate**: `0xb91b270212F0F7504ECBa6Ff1d9c1f58DfcEEa14`

### Affiliate Link System

Users can share referral links in the format:
```
https://highrollers.app/?ref=0xAFFILIATE_WALLET_ADDRESS
```

When a visitor clicks this link:
1. The `ref` parameter is stored in localStorage
2. Before minting, the app calls `linkAffiliate(buyer, affiliate)` on the contract
3. The affiliate is automatically assigned and receives commission on each mint

---

## Architecture

```
high-rollers-nfts/
├── server/
│   ├── index.js              # Express server entry point
│   ├── config.js             # Network & contract configuration
│   ├── services/
│   │   ├── contract.js       # Contract interaction service
│   │   ├── eventListener.js  # Event listening & processing with fallback
│   │   ├── dataSync.js       # Polling & data synchronization
│   │   └── database.js       # SQLite for caching data
│   └── routes/
│       ├── api.js            # REST API endpoints
│       └── websocket.js      # WebSocket for real-time updates
├── public/
│   ├── index.html            # Main HTML page with tab navigation
│   ├── css/
│   │   └── styles.css        # Styling (Tailwind CSS)
│   └── js/
│       ├── app.js            # Main application logic + routing
│       ├── wallet.js         # MetaMask-specific wallet connection
│       ├── mint.js           # Minting functionality with fallback polling
│       ├── affiliate.js      # Affiliate tracking & referral links
│       └── ui.js             # UI updates & rendering
├── assets/
│   └── images/               # NFT images (8 types)
├── package.json
├── .env.example
└── README.md
```

---

## UI Navigation System

The app uses a **tab-based navigation** system. Users click tabs to switch between different views:

### Navigation Tabs

| Tab | Route | Description |
|-----|-------|-------------|
| **Mint** | `/` or `/mint` | Main minting interface with countdown to 2700 |
| **Gallery** | `/gallery` | All 8 NFT types with mint counts |
| **Sales** | `/sales` | Live sales table with real-time updates |
| **Affiliates** | `/affiliates` | Affiliate earnings table & user's referral link |
| **My NFTs** | `/my-nfts` | User's owned NFTs (requires wallet connection) |

### Tab Navigation HTML Structure

```html
<!-- Navigation Tabs -->
<nav class="bg-gray-800 border-b border-gray-700">
  <div class="container mx-auto flex">
    <button data-tab="mint" class="tab-btn active px-6 py-4 text-purple-400 border-b-2 border-purple-400 cursor-pointer">
      Mint
    </button>
    <button data-tab="gallery" class="tab-btn px-6 py-4 text-gray-400 hover:text-white cursor-pointer">
      Gallery
    </button>
    <button data-tab="sales" class="tab-btn px-6 py-4 text-gray-400 hover:text-white cursor-pointer">
      Live Sales
    </button>
    <button data-tab="affiliates" class="tab-btn px-6 py-4 text-gray-400 hover:text-white cursor-pointer">
      Affiliates
    </button>
    <button data-tab="my-nfts" class="tab-btn px-6 py-4 text-gray-400 hover:text-white cursor-pointer hidden" id="my-nfts-tab">
      My NFTs
    </button>
  </div>
</nav>

<!-- Tab Content Panels -->
<div id="tab-mint" class="tab-panel"><!-- Mint UI --></div>
<div id="tab-gallery" class="tab-panel hidden"><!-- Gallery UI --></div>
<div id="tab-sales" class="tab-panel hidden"><!-- Sales Table --></div>
<div id="tab-affiliates" class="tab-panel hidden"><!-- Affiliate UI --></div>
<div id="tab-my-nfts" class="tab-panel hidden"><!-- My NFTs Grid --></div>
```

### Tab Switching JavaScript

```javascript
class TabManager {
  constructor() {
    this.tabs = document.querySelectorAll('.tab-btn');
    this.panels = document.querySelectorAll('.tab-panel');
    this.init();
  }

  init() {
    this.tabs.forEach(tab => {
      tab.addEventListener('click', () => this.switchTab(tab.dataset.tab));
    });

    // Handle URL routing
    this.handleRoute();
    window.addEventListener('popstate', () => this.handleRoute());
  }

  switchTab(tabName) {
    // Update URL without reload
    history.pushState({}, '', `/${tabName === 'mint' ? '' : tabName}`);

    // Update tab styles
    this.tabs.forEach(tab => {
      const isActive = tab.dataset.tab === tabName;
      tab.classList.toggle('text-purple-400', isActive);
      tab.classList.toggle('border-b-2', isActive);
      tab.classList.toggle('border-purple-400', isActive);
      tab.classList.toggle('text-gray-400', !isActive);
    });

    // Show/hide panels
    this.panels.forEach(panel => {
      panel.classList.toggle('hidden', panel.id !== `tab-${tabName}`);
    });

    // Trigger data load for the tab
    this.onTabChange(tabName);
  }

  handleRoute() {
    const path = window.location.pathname.slice(1) || 'mint';
    this.switchTab(path);
  }

  onTabChange(tabName) {
    switch (tabName) {
      case 'sales':
        app.loadSales();
        break;
      case 'affiliates':
        app.loadAffiliateData();
        break;
      case 'my-nfts':
        app.loadMyNFTs();
        break;
      case 'gallery':
        app.loadHostessCounts();
        break;
    }
  }
}
```

---

## Phase 1: Project Setup & Configuration

### 1.1 Initialize Project

```bash
mkdir high-rollers-nfts
cd high-rollers-nfts
npm init -y
npm install express ethers cors dotenv better-sqlite3 ws
npm install -D nodemon
```

### 1.2 Configuration File (`server/config.js`)

```javascript
module.exports = {
  // Arbitrum One
  CHAIN_ID: 42161,
  CHAIN_NAME: 'Arbitrum One',
  RPC_URL: process.env.ARBITRUM_RPC_URL || 'https://snowy-little-cloud.arbitrum-mainnet.quiknode.pro/f4051c078b1e168f278c0780d1d12b817152c84d',

  // Contract
  CONTRACT_ADDRESS: '0x7176d2edd83aD037bd94b7eE717bd9F661F560DD',
  MINT_PRICE: '320000000000000000', // 0.32 ETH in wei

  // Supply limits
  CONTRACT_MAX_SUPPLY: 10000,  // Hardcoded in contract
  APP_MAX_SUPPLY: 2700,        // We stop minting at this number

  // NFT Types with ImageKit URLs
  HOSTESSES: [
    { index: 0, name: 'Penelope Fatale', rarity: '0.5%', multiplier: 100, image: 'https://ik.imagekit.io/blockster/penelope.jpg' },
    { index: 1, name: 'Mia Siren', rarity: '1%', multiplier: 90, image: 'https://ik.imagekit.io/blockster/mia.jpg' },
    { index: 2, name: 'Cleo Enchante', rarity: '3.5%', multiplier: 80, image: 'https://ik.imagekit.io/blockster/cleo.jpg' },
    { index: 3, name: 'Sophia Spark', rarity: '7.5%', multiplier: 70, image: 'https://ik.imagekit.io/blockster/sophia.jpg' },
    { index: 4, name: 'Luna Mirage', rarity: '12.5%', multiplier: 60, image: 'https://ik.imagekit.io/blockster/luna.jpg' },
    { index: 5, name: 'Aurora Seductra', rarity: '25%', multiplier: 50, image: 'https://ik.imagekit.io/blockster/aurora.jpg' },
    { index: 6, name: 'Scarlett Ember', rarity: '25%', multiplier: 40, image: 'https://ik.imagekit.io/blockster/scarlett.jpg' },
    { index: 7, name: 'Vivienne Allure', rarity: '25%', multiplier: 30, image: 'https://ik.imagekit.io/blockster/vivienne.jpg' }
  ],

  // Affiliate percentages
  TIER1_PERCENTAGE: 20, // 20% = 1/5
  TIER2_PERCENTAGE: 5,  // 5% = 1/20

  // Polling intervals
  POLL_INTERVAL_MS: 30000,        // 30 seconds for general sync
  MINT_POLL_INTERVAL_MS: 5000,    // 5 seconds for pending mints (fallback)

  // Server
  PORT: process.env.PORT || 3001
};
```

### 1.3 Contract ABI (Minimal Required)

```javascript
const CONTRACT_ABI = [
  // Read functions
  'function totalSupply() view returns (uint256)',
  'function getCurrentPrice() view returns (uint256)',
  'function getMaxSupply() view returns (uint256)',
  'function ownerOf(uint256 tokenId) view returns (address)',
  'function s_tokenIdToHostess(uint256 tokenId) view returns (uint256)',
  'function getHostessByTokenId(uint256 tokenId) view returns (string)',
  'function getTokenIdsByWallet(address buyer) view returns (uint256[])',
  'function getBuyerInfo(address buyer) view returns (uint256 nftCount, uint256 spent, address affiliate, address affiliate2, uint256[] tokenIds)',
  'function getAffiliateInfo(address affiliate) view returns (uint256 buyerCount, uint256 referreeCount, uint256 referredAffiliatesCount, uint256 totalSpent, uint256 earnings, uint256 balance, address[] buyers, address[] referrees, address[] referredAffiliates, uint256[] tokenIds)',
  'function getAffiliate2Info(address affiliate) view returns (uint256 buyerCount2, uint256 referreeCount2, uint256 referredAffiliatesCount, uint256 totalSpent2, uint256 earnings2, uint256 balance, address[] buyers2, address[] referrees2, address[] referredAffiliates, uint256[] tokenIds2)',
  'function getTotalSalesVolume() view returns (uint256)',
  'function getTotalAffiliatesBalance() view returns (uint256)',
  'function s_requestIdToSender(uint256 requestId) view returns (address)',

  // Write functions
  'function requestNFT() payable returns (uint256 requestId)',
  'function linkAffiliate(address buyer, address affiliate) returns (address)',

  // Events
  'event NFTRequested(uint256 requestId, address sender, uint256 currentPrice, uint256 tokenId)',
  'event NFTMinted(uint256 requestId, address recipient, uint256 currentPrice, uint256 tokenId, uint8 hostess, address affiliate, address affiliate2)',
  'event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)'
];
```

---

## Multi-Wallet Support with Logos

### Supported Wallets

| Wallet | Logo | Detection Flag |
|--------|------|----------------|
| MetaMask | `/images/wallets/metamask.svg` | `isMetaMask && !isCoinbaseWallet` |
| Coinbase Wallet | `/images/wallets/coinbase.svg` | `isCoinbaseWallet` |
| Rabby | `/images/wallets/rabby.svg` | `isRabby` |
| Trust Wallet | `/images/wallets/trust.svg` | `isTrust` |
| Brave Wallet | `/images/wallets/brave.svg` | `isBraveWallet` |
| WalletConnect | `/images/wallets/walletconnect.svg` | Manual selection |

### Wallet Selection UI

```html
<!-- Wallet Connection Modal -->
<div id="wallet-modal" class="fixed inset-0 bg-black/80 z-50 hidden flex items-center justify-center">
  <div class="bg-gray-800 rounded-xl p-6 max-w-md w-full mx-4">
    <h2 class="text-xl font-bold mb-4">Connect Wallet</h2>
    <p class="text-gray-400 mb-6">Select your preferred wallet to continue</p>

    <div class="space-y-3" id="wallet-options">
      <!-- MetaMask -->
      <button class="wallet-option w-full flex items-center gap-4 p-4 bg-gray-700 hover:bg-gray-600 rounded-lg cursor-pointer" data-wallet="metamask">
        <img src="/images/wallets/metamask.svg" alt="MetaMask" class="w-10 h-10">
        <div class="text-left">
          <p class="font-bold">MetaMask</p>
          <p class="text-sm text-gray-400">Connect using browser extension</p>
        </div>
      </button>

      <!-- Coinbase Wallet -->
      <button class="wallet-option w-full flex items-center gap-4 p-4 bg-gray-700 hover:bg-gray-600 rounded-lg cursor-pointer" data-wallet="coinbase">
        <img src="/images/wallets/coinbase.svg" alt="Coinbase Wallet" class="w-10 h-10">
        <div class="text-left">
          <p class="font-bold">Coinbase Wallet</p>
          <p class="text-sm text-gray-400">Connect using Coinbase Wallet</p>
        </div>
      </button>

      <!-- Rabby -->
      <button class="wallet-option w-full flex items-center gap-4 p-4 bg-gray-700 hover:bg-gray-600 rounded-lg cursor-pointer" data-wallet="rabby">
        <img src="/images/wallets/rabby.svg" alt="Rabby" class="w-10 h-10">
        <div class="text-left">
          <p class="font-bold">Rabby</p>
          <p class="text-sm text-gray-400">The game changing wallet for DeFi</p>
        </div>
      </button>

      <!-- Trust Wallet -->
      <button class="wallet-option w-full flex items-center gap-4 p-4 bg-gray-700 hover:bg-gray-600 rounded-lg cursor-pointer" data-wallet="trust">
        <img src="/images/wallets/trust.svg" alt="Trust Wallet" class="w-10 h-10">
        <div class="text-left">
          <p class="font-bold">Trust Wallet</p>
          <p class="text-sm text-gray-400">Connect using Trust Wallet</p>
        </div>
      </button>
    </div>

    <button id="close-wallet-modal" class="mt-4 w-full py-2 text-gray-400 hover:text-white cursor-pointer">
      Cancel
    </button>
  </div>
</div>
```

### Wallet Service with Multi-Wallet Support

```javascript
// public/js/wallet.js

class WalletService {
  constructor() {
    this.provider = null;
    this.signer = null;
    this.address = null;
    this.walletType = null;
    this.onConnectCallbacks = [];
    this.onDisconnectCallbacks = [];

    // Wallet configurations with logos
    this.walletConfigs = {
      metamask: { name: 'MetaMask', logo: '/images/wallets/metamask.svg' },
      coinbase: { name: 'Coinbase Wallet', logo: '/images/wallets/coinbase.svg' },
      rabby: { name: 'Rabby', logo: '/images/wallets/rabby.svg' },
      trust: { name: 'Trust Wallet', logo: '/images/wallets/trust.svg' },
      brave: { name: 'Brave Wallet', logo: '/images/wallets/brave.svg' },
      other: { name: 'Browser Wallet', logo: '/images/wallets/generic.svg' }
    };
  }

  /**
   * Get all available wallets for UI display
   */
  getAvailableWallets() {
    const available = [];
    const ethereum = window.ethereum;

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
    const wallets = this.getAvailableWallets();
    const wallet = wallets.find(w => w.type === walletType);

    if (!wallet) {
      throw new Error(`${walletType} wallet not found. Please install it first.`);
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
    this.walletType = walletType;

    // Set up event listeners
    provider.on('accountsChanged', this.handleAccountsChanged.bind(this));
    provider.on('chainChanged', this.handleChainChanged.bind(this));

    // Trigger callbacks
    this.onConnectCallbacks.forEach(cb => cb(this.address, this.walletType));

    return { address: this.address, type: walletType, logo: wallet.logo };
  }

  async switchToArbitrum(provider) {
    const ARBITRUM_CHAIN_ID = '0xa4b1'; // 42161 in hex

    try {
      await provider.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: ARBITRUM_CHAIN_ID }]
      });
    } catch (error) {
      if (error.code === 4902) {
        await provider.request({
          method: 'wallet_addEthereumChain',
          params: [{
            chainId: ARBITRUM_CHAIN_ID,
            chainName: 'Arbitrum One',
            nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
            rpcUrls: ['https://arb1.arbitrum.io/rpc'],
            blockExplorerUrls: ['https://arbiscan.io']
          }]
        });
      } else {
        throw error;
      }
    }
  }

  handleAccountsChanged(accounts) {
    if (accounts.length === 0) {
      this.disconnect();
    } else {
      this.address = accounts[0];
      this.onConnectCallbacks.forEach(cb => cb(this.address, this.walletType));
    }
  }

  handleChainChanged() {
    window.location.reload();
  }

  disconnect() {
    this.provider = null;
    this.signer = null;
    this.address = null;
    this.walletType = null;
    this.onDisconnectCallbacks.forEach(cb => cb());
  }

  getWalletLogo() {
    return this.walletConfigs[this.walletType]?.logo || this.walletConfigs.other.logo;
  }
}

window.walletService = new WalletService();
```

### Wallet Connection UI Handler

```javascript
// Populate wallet options dynamically
function setupWalletModal() {
  const wallets = walletService.getAvailableWallets();
  const container = document.getElementById('wallet-options');

  // Show/hide wallet options based on availability
  document.querySelectorAll('.wallet-option').forEach(btn => {
    const walletType = btn.dataset.wallet;
    const isAvailable = wallets.some(w => w.type === walletType);

    if (!isAvailable) {
      // Show install link instead
      btn.classList.add('opacity-50');
      btn.querySelector('.text-gray-400').textContent = 'Not installed - Click to install';
    }
  });

  // Handle wallet selection
  document.querySelectorAll('.wallet-option').forEach(btn => {
    btn.addEventListener('click', async () => {
      const walletType = btn.dataset.wallet;
      const isAvailable = wallets.some(w => w.type === walletType);

      if (!isAvailable) {
        // Open install page
        const installUrls = {
          metamask: 'https://metamask.io/download/',
          coinbase: 'https://www.coinbase.com/wallet/downloads',
          rabby: 'https://rabby.io/',
          trust: 'https://trustwallet.com/browser-extension'
        };
        window.open(installUrls[walletType], '_blank');
        return;
      }

      try {
        const result = await walletService.connectWallet(walletType);
        closeWalletModal();
        updateConnectedState(result);
      } catch (error) {
        console.error('Connection failed:', error);
        alert(error.message);
      }
    });
  });
}

function updateConnectedState(result) {
  const connectBtn = document.getElementById('connect-btn');
  const walletInfo = document.getElementById('wallet-info');

  connectBtn.classList.add('hidden');
  walletInfo.classList.remove('hidden');

  document.getElementById('wallet-logo').src = result.logo;
  document.getElementById('wallet-address').textContent =
    `${result.address.slice(0, 6)}...${result.address.slice(-4)}`;
}
```

---

## Event Listener Reliability & Fallback System

### The Problem

WebSocket event listeners can fail due to:
- Network disconnections
- RPC provider issues
- Browser tab going to sleep
- VRF callback delays (can take 1-30+ seconds)

### Solution: Multi-Layer Fallback System

```javascript
// server/services/eventListener.js

const { ethers } = require('ethers');
const config = require('../config');

class EventListener {
  constructor(contractService, database, websocketServer) {
    this.contractService = contractService;
    this.db = database;
    this.ws = websocketServer;
    this.provider = new ethers.JsonRpcProvider(config.RPC_URL);
    this.contract = new ethers.Contract(
      config.CONTRACT_ADDRESS,
      config.CONTRACT_ABI,
      this.provider
    );

    // Track pending mints for fallback polling
    this.pendingMints = new Map(); // requestId -> { sender, timestamp, tokenId }
    this.lastKnownSupply = 0;

    // Reconnection state
    this.isConnected = false;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 10;
  }

  start() {
    this.setupEventListeners();
    this.startFallbackPolling();
    this.startHealthCheck();
  }

  setupEventListeners() {
    // Listen for NFTRequested (mint initiated)
    this.contract.on('NFTRequested', async (requestId, sender, price, tokenId, event) => {
      console.log(`[Event] NFTRequested: requestId=${requestId}, sender=${sender}, tokenId=${tokenId}`);

      // Track pending mint for fallback
      this.pendingMints.set(requestId.toString(), {
        sender,
        tokenId: tokenId.toString(),
        price: price.toString(),
        timestamp: Date.now(),
        txHash: event.transactionHash
      });

      this.ws.broadcast({
        type: 'MINT_REQUESTED',
        data: {
          requestId: requestId.toString(),
          sender,
          price: price.toString(),
          tokenId: tokenId.toString(),
          txHash: event.transactionHash
        }
      });
    });

    // Listen for NFTMinted (Chainlink VRF callback complete)
    this.contract.on('NFTMinted', async (requestId, recipient, price, tokenId, hostess, affiliate, affiliate2, event) => {
      this.handleMintComplete(requestId, recipient, price, tokenId, hostess, affiliate, affiliate2, event);
    });

    // Listen for Transfer events
    this.contract.on('Transfer', async (from, to, tokenId, event) => {
      if (from === ethers.ZeroAddress) return;
      this.db.updateNFTOwner(Number(tokenId), to);
      this.ws.broadcast({
        type: 'NFT_TRANSFERRED',
        data: { tokenId: tokenId.toString(), from, to, txHash: event.transactionHash }
      });
    });

    // Handle provider errors
    this.provider.on('error', (error) => {
      console.error('[EventListener] Provider error:', error);
      this.handleDisconnect();
    });

    this.isConnected = true;
    this.reconnectAttempts = 0;
    console.log('[EventListener] Started listening for contract events');
  }

  handleMintComplete(requestId, recipient, price, tokenId, hostess, affiliate, affiliate2, event) {
    console.log(`[Event] NFTMinted: tokenId=${tokenId}, hostess=${hostess}, recipient=${recipient}`);

    const hostessIndex = Number(hostess);
    const hostessName = config.HOSTESSES[hostessIndex]?.name || 'Unknown';
    const priceStr = price.toString();

    // Remove from pending mints
    this.pendingMints.delete(requestId.toString());

    // Calculate affiliate earnings
    const tier1Earnings = (BigInt(priceStr) / 5n).toString();
    const tier2Earnings = (BigInt(priceStr) / 20n).toString();

    // Store in database
    this.db.insertNFT({
      tokenId: Number(tokenId),
      owner: recipient,
      hostessIndex,
      hostessName,
      mintPrice: priceStr,
      mintTxHash: event.transactionHash,
      affiliate,
      affiliate2
    });

    this.db.insertSale({
      tokenId: Number(tokenId),
      buyer: recipient,
      hostessIndex,
      hostessName,
      price: priceStr,
      txHash: event.transactionHash,
      blockNumber: event.blockNumber,
      timestamp: Math.floor(Date.now() / 1000),
      affiliate,
      affiliate2
    });

    // Insert affiliate earnings
    if (affiliate && affiliate !== ethers.ZeroAddress) {
      this.db.insertAffiliateEarning({
        tokenId: Number(tokenId),
        tier: 1,
        affiliate,
        earnings: tier1Earnings,
        txHash: event.transactionHash
      });
    }

    if (affiliate2 && affiliate2 !== ethers.ZeroAddress) {
      this.db.insertAffiliateEarning({
        tokenId: Number(tokenId),
        tier: 2,
        affiliate: affiliate2,
        earnings: tier2Earnings,
        txHash: event.transactionHash
      });
    }

    this.db.incrementHostessCount(hostessIndex);

    // Broadcast to all connected clients
    this.ws.broadcast({
      type: 'NFT_MINTED',
      data: {
        requestId: requestId.toString(),
        recipient,
        tokenId: tokenId.toString(),
        hostessIndex,
        hostessName,
        hostessRarity: config.HOSTESSES[hostessIndex]?.rarity,
        price: priceStr,
        priceETH: ethers.formatEther(price),
        txHash: event.transactionHash,
        affiliate,
        affiliate2,
        tier1Earnings,
        tier2Earnings
      }
    });
  }

  /**
   * FALLBACK POLLING SYSTEM
   * If event listener misses an event, this catches it
   */
  startFallbackPolling() {
    // Poll every 5 seconds for pending mints
    this.fallbackInterval = setInterval(async () => {
      await this.checkPendingMints();
      await this.checkSupplyChanges();
    }, config.MINT_POLL_INTERVAL_MS);

    console.log('[EventListener] Fallback polling started');
  }

  async checkPendingMints() {
    const now = Date.now();

    for (const [requestId, mint] of this.pendingMints) {
      // If pending for more than 60 seconds, check contract directly
      if (now - mint.timestamp > 60000) {
        try {
          // Check if this token has been minted by querying ownership
          const tokenId = parseInt(mint.tokenId);
          const owner = await this.contract.ownerOf(tokenId);

          if (owner && owner !== ethers.ZeroAddress) {
            // NFT was minted but we missed the event
            console.log(`[Fallback] Detected missed mint for tokenId=${tokenId}`);

            const hostessIndex = await this.contract.s_tokenIdToHostess(tokenId);

            // Fetch the mint event from past blocks
            const filter = this.contract.filters.NFTMinted(requestId);
            const events = await this.contract.queryFilter(filter, -1000); // Last 1000 blocks

            if (events.length > 0) {
              const event = events[0];
              this.handleMintComplete(
                requestId,
                event.args.recipient,
                event.args.currentPrice,
                event.args.tokenId,
                event.args.hostess,
                event.args.affiliate,
                event.args.affiliate2,
                event
              );
            } else {
              // Event not found, construct from available data
              this.pendingMints.delete(requestId);
              this.ws.broadcast({
                type: 'NFT_MINTED',
                data: {
                  requestId,
                  recipient: owner,
                  tokenId: tokenId.toString(),
                  hostessIndex: Number(hostessIndex),
                  hostessName: config.HOSTESSES[Number(hostessIndex)]?.name,
                  hostessRarity: config.HOSTESSES[Number(hostessIndex)]?.rarity,
                  price: mint.price,
                  priceETH: ethers.formatEther(mint.price),
                  txHash: mint.txHash,
                  source: 'fallback'
                }
              });
            }
          }
        } catch (error) {
          // Token doesn't exist yet, keep waiting
          if (now - mint.timestamp > 300000) {
            // 5 minutes timeout - remove stale pending mint
            console.log(`[Fallback] Removing stale pending mint: ${requestId}`);
            this.pendingMints.delete(requestId);
          }
        }
      }
    }
  }

  async checkSupplyChanges() {
    try {
      const currentSupply = await this.contractService.getTotalSupply();
      const supply = Number(currentSupply);

      if (supply > this.lastKnownSupply && this.lastKnownSupply > 0) {
        // New NFTs minted that we might have missed
        console.log(`[Fallback] Supply changed: ${this.lastKnownSupply} -> ${supply}`);

        // Fetch recent Transfer events to catch any missed mints
        const filter = this.contract.filters.Transfer(ethers.ZeroAddress);
        const events = await this.contract.queryFilter(filter, -100);

        for (const event of events) {
          const tokenId = Number(event.args.tokenId);
          if (!this.db.nftExists(tokenId)) {
            // Missed this mint, add it now
            const hostessIndex = await this.contract.s_tokenIdToHostess(tokenId);
            this.db.upsertNFT({
              tokenId,
              owner: event.args.to,
              hostessIndex: Number(hostessIndex),
              hostessName: config.HOSTESSES[Number(hostessIndex)]?.name
            });
            this.db.incrementHostessCount(Number(hostessIndex));
          }
        }
      }

      this.lastKnownSupply = supply;
    } catch (error) {
      console.error('[Fallback] Supply check error:', error);
    }
  }

  /**
   * HEALTH CHECK & RECONNECTION
   */
  startHealthCheck() {
    this.healthCheckInterval = setInterval(async () => {
      try {
        await this.provider.getBlockNumber();
        if (!this.isConnected) {
          console.log('[EventListener] Reconnected to provider');
          this.setupEventListeners();
        }
      } catch (error) {
        console.error('[EventListener] Health check failed');
        this.handleDisconnect();
      }
    }, 30000); // Check every 30 seconds
  }

  handleDisconnect() {
    this.isConnected = false;
    this.contract.removeAllListeners();

    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++;
      const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 60000);
      console.log(`[EventListener] Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`);

      setTimeout(() => {
        this.provider = new ethers.JsonRpcProvider(config.RPC_URL);
        this.contract = new ethers.Contract(config.CONTRACT_ADDRESS, config.CONTRACT_ABI, this.provider);
        this.setupEventListeners();
      }, delay);
    } else {
      console.error('[EventListener] Max reconnection attempts reached');
    }
  }

  stop() {
    this.contract.removeAllListeners();
    if (this.fallbackInterval) clearInterval(this.fallbackInterval);
    if (this.healthCheckInterval) clearInterval(this.healthCheckInterval);
    console.log('[EventListener] Stopped');
  }
}

module.exports = EventListener;
```

### Client-Side Fallback Polling

```javascript
// public/js/mint.js - Client-side fallback for detecting mint completion

class MintService {
  constructor(walletService) {
    this.walletService = walletService;
    this.contract = null;
    this.pendingMint = null;
    this.pollInterval = null;
    this.maxPollAttempts = 60;  // 5 minutes at 5-second intervals
    this.pollAttempts = 0;
  }

  async mint() {
    if (!this.contract) {
      await this.initContract();
    }

    const tx = await this.contract.requestNFT({ value: MINT_PRICE });
    console.log('Mint transaction sent:', tx.hash);

    const receipt = await tx.wait();
    console.log('Transaction confirmed:', receipt);

    // Parse the NFTRequested event
    const requestedEvent = receipt.logs.find(log => {
      try {
        const parsed = this.contract.interface.parseLog(log);
        return parsed.name === 'NFTRequested';
      } catch { return false; }
    });

    if (requestedEvent) {
      const parsed = this.contract.interface.parseLog(requestedEvent);
      this.pendingMint = {
        requestId: parsed.args.requestId.toString(),
        tokenId: parsed.args.tokenId.toString(),
        txHash: tx.hash
      };

      // Start fallback polling in case we miss the event
      this.startFallbackPolling();

      this.onMintRequestedCallbacks.forEach(cb => cb({
        requestId: this.pendingMint.requestId,
        tokenId: this.pendingMint.tokenId,
        txHash: tx.hash
      }));
    }

    return tx.hash;
  }

  /**
   * Fallback polling: Check if our NFT was minted even if we miss the event
   */
  startFallbackPolling() {
    this.pollAttempts = 0;

    this.pollInterval = setInterval(async () => {
      this.pollAttempts++;

      if (this.pollAttempts > this.maxPollAttempts) {
        this.stopFallbackPolling();
        console.error('Mint polling timeout - check Arbiscan for status');
        return;
      }

      try {
        // Check if our pending NFT has been minted
        const tokenId = parseInt(this.pendingMint.tokenId);
        const owner = await this.contract.ownerOf(tokenId);

        if (owner && owner.toLowerCase() === this.walletService.address.toLowerCase()) {
          // Our NFT was minted!
          console.log(`[Fallback Poll] NFT ${tokenId} minted successfully`);

          const hostessIndex = await this.contract.s_tokenIdToHostess(tokenId);
          this.handleMintComplete(this.pendingMint.requestId, tokenId, hostessIndex);
          this.stopFallbackPolling();
        }
      } catch (error) {
        // Token doesn't exist yet, keep polling
        console.log(`[Fallback Poll] Attempt ${this.pollAttempts}: waiting for mint...`);
      }
    }, 5000); // Poll every 5 seconds
  }

  stopFallbackPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }

  handleMintComplete(requestId, tokenId, hostessIndex) {
    this.stopFallbackPolling();
    const hostess = HOSTESSES[Number(hostessIndex)];

    this.onMintCompleteCallbacks.forEach(cb => cb({
      requestId: requestId.toString(),
      tokenId: tokenId.toString(),
      hostessIndex: Number(hostessIndex),
      hostessName: hostess.name,
      hostessRarity: hostess.rarity,
      hostessIpfs: hostess.ipfs
    }));

    this.pendingMint = null;
  }
}
```

---

## Affiliate System Implementation

### Affiliate Link Handling (`public/js/affiliate.js`)

```javascript
class AffiliateService {
  constructor() {
    this.STORAGE_KEY = 'high_rollers_affiliate';
    this.init();
  }

  init() {
    // Check URL for referral parameter
    const urlParams = new URLSearchParams(window.location.search);
    const refAddress = urlParams.get('ref');

    if (refAddress && this.isValidAddress(refAddress)) {
      this.setAffiliate(refAddress);
      // Clean URL without losing other params
      urlParams.delete('ref');
      const newUrl = window.location.pathname + (urlParams.toString() ? '?' + urlParams : '');
      history.replaceState({}, '', newUrl);
    }
  }

  isValidAddress(address) {
    return /^0x[a-fA-F0-9]{40}$/.test(address);
  }

  setAffiliate(address) {
    localStorage.setItem(this.STORAGE_KEY, address.toLowerCase());
    console.log(`[Affiliate] Set affiliate to: ${address}`);
  }

  getAffiliate() {
    return localStorage.getItem(this.STORAGE_KEY);
  }

  clearAffiliate() {
    localStorage.removeItem(this.STORAGE_KEY);
  }

  /**
   * Generate referral link for current user
   */
  generateReferralLink(walletAddress) {
    const baseUrl = window.location.origin;
    return `${baseUrl}/?ref=${walletAddress}`;
  }

  /**
   * Copy referral link to clipboard
   */
  async copyReferralLink(walletAddress) {
    const link = this.generateReferralLink(walletAddress);
    try {
      await navigator.clipboard.writeText(link);
      return true;
    } catch (error) {
      // Fallback for older browsers
      const textarea = document.createElement('textarea');
      textarea.value = link;
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
      return true;
    }
  }
}

window.affiliateService = new AffiliateService();
```

### Affiliate Tab UI

```html
<!-- Affiliate Tab Content -->
<div id="tab-affiliates" class="tab-panel hidden">
  <div class="container mx-auto p-6">
    <!-- User's Referral Link Section (only shown when wallet connected) -->
    <section id="my-referral-section" class="mb-8 bg-gray-800 p-6 rounded-lg hidden">
      <h2 class="text-xl font-bold mb-4">Your Referral Link</h2>
      <p class="text-gray-400 mb-4">Share this link to earn 20% commission on every mint!</p>

      <div class="flex items-center gap-4">
        <input
          type="text"
          id="referral-link"
          readonly
          class="flex-1 bg-gray-700 text-white px-4 py-3 rounded-lg"
          value=""
        />
        <button
          id="copy-referral-btn"
          class="bg-purple-600 hover:bg-purple-700 px-6 py-3 rounded-lg cursor-pointer"
        >
          Copy Link
        </button>
      </div>

      <div id="copy-success" class="hidden mt-2 text-green-400">
        ✓ Link copied to clipboard!
      </div>

      <!-- User's Affiliate Stats -->
      <div class="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="bg-gray-700 p-4 rounded-lg">
          <h4 class="text-gray-400 text-sm">Total Earned (Tier 1)</h4>
          <p id="my-tier1-earnings" class="text-xl font-bold text-green-400">0 ETH</p>
        </div>
        <div class="bg-gray-700 p-4 rounded-lg">
          <h4 class="text-gray-400 text-sm">Total Earned (Tier 2)</h4>
          <p id="my-tier2-earnings" class="text-xl font-bold text-blue-400">0 ETH</p>
        </div>
        <div class="bg-gray-700 p-4 rounded-lg">
          <h4 class="text-gray-400 text-sm">Withdrawable Balance</h4>
          <p id="my-affiliate-balance" class="text-xl font-bold text-yellow-400">0 ETH</p>
          <button id="withdraw-btn" class="mt-2 bg-yellow-600 hover:bg-yellow-700 px-4 py-2 rounded text-sm cursor-pointer">
            Withdraw
          </button>
        </div>
      </div>

      <!-- Referral breakdown -->
      <div class="mt-6">
        <h4 class="font-bold mb-2">Your Referrals</h4>
        <div class="bg-gray-700 rounded-lg p-4 max-h-64 overflow-y-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-gray-400">
                <th class="text-left pb-2">Buyer</th>
                <th class="text-left pb-2">NFTs</th>
                <th class="text-left pb-2">Your Earnings</th>
              </tr>
            </thead>
            <tbody id="my-referrals-table">
              <!-- Populated by JavaScript -->
            </tbody>
          </table>
        </div>
      </div>
    </section>

    <!-- Global Affiliate Earnings Table -->
    <section class="mb-8">
      <h2 class="text-xl font-bold mb-4">All Affiliate Earnings</h2>
      <div class="bg-gray-800 rounded-lg overflow-hidden">
        <table class="w-full">
          <thead class="bg-gray-700">
            <tr>
              <th class="p-3 text-left">Token ID</th>
              <th class="p-3 text-left">Tier</th>
              <th class="p-3 text-left">Affiliate</th>
              <th class="p-3 text-left">Earnings</th>
            </tr>
          </thead>
          <tbody id="affiliate-table-body">
            <!-- Populated by JavaScript -->
          </tbody>
        </table>
      </div>
    </section>
  </div>
</div>
```

### Affiliate UI JavaScript

```javascript
// In app.js

async loadAffiliateData() {
  // Load global affiliate earnings
  await this.loadAffiliateEarnings();

  // If wallet connected, load user's affiliate stats
  if (walletService.address) {
    await this.loadMyAffiliateStats();
    this.setupReferralLink();
  }
}

setupReferralLink() {
  const section = document.getElementById('my-referral-section');
  const linkInput = document.getElementById('referral-link');
  const copyBtn = document.getElementById('copy-referral-btn');
  const copySuccess = document.getElementById('copy-success');

  section.classList.remove('hidden');

  const referralLink = affiliateService.generateReferralLink(walletService.address);
  linkInput.value = referralLink;

  copyBtn.addEventListener('click', async () => {
    await affiliateService.copyReferralLink(walletService.address);
    copySuccess.classList.remove('hidden');
    setTimeout(() => copySuccess.classList.add('hidden'), 3000);
  });
}

async loadMyAffiliateStats() {
  try {
    const response = await fetch(`/api/affiliates/${walletService.address}`);
    const data = await response.json();

    document.getElementById('my-tier1-earnings').textContent =
      `${this.formatETH(data.tier1.earnings)} ETH`;
    document.getElementById('my-tier2-earnings').textContent =
      `${this.formatETH(data.tier2.earnings)} ETH`;
    document.getElementById('my-affiliate-balance').textContent =
      `${this.formatETH(data.tier1.balance)} ETH`;

    // Render referrals table
    const tbody = document.getElementById('my-referrals-table');
    tbody.innerHTML = data.earningsPerNFT.map(e => `
      <tr class="border-t border-gray-600">
        <td class="py-2">${this.truncateAddress(e.buyer_address)}</td>
        <td class="py-2">#${e.token_id}</td>
        <td class="py-2 text-green-400">${this.formatETH(e.earnings)} ETH</td>
      </tr>
    `).join('');
  } catch (error) {
    console.error('Failed to load affiliate stats:', error);
  }
}
```

---

## API Routes (Updated)

```javascript
// server/routes/api.js

module.exports = (db, contractService, config) => {
  // Get collection stats with app-specific max supply
  router.get('/stats', async (req, res) => {
    try {
      const totalSupply = await contractService.getTotalSupply();
      const currentPrice = await contractService.getCurrentPrice();
      const hostessCounts = db.getAllHostessCounts();

      const minted = Number(totalSupply);
      const remaining = config.APP_MAX_SUPPLY - minted;

      res.json({
        totalSupply: totalSupply.toString(),
        totalMinted: minted,
        maxSupply: config.APP_MAX_SUPPLY,  // Use app limit, not contract limit
        remaining: Math.max(0, remaining),
        currentPrice: currentPrice.toString(),
        currentPriceETH: '0.32',
        hostessCounts,
        soldOut: minted >= config.APP_MAX_SUPPLY
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Link affiliate before mint
  router.post('/link-affiliate', async (req, res) => {
    try {
      const { buyer, affiliate } = req.body;

      if (!buyer || !affiliate) {
        return res.status(400).json({ error: 'Missing buyer or affiliate address' });
      }

      // This would require a server-side wallet with affiliateLinker role
      // For now, return success - actual linking happens on-chain
      res.json({ success: true, affiliate });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // ... rest of routes
};
```

---

## Updated Frontend HTML with Tab Navigation

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Rogue High Rollers NFT - Real-Time Revenue Sharing</title>
  <meta name="description" content="High Rollers NFTs earn a share of every winning bet. Mint your NFT now and start earning passive income forever.">
  <script src="https://cdn.tailwindcss.com"></script>
  <script src="https://cdn.jsdelivr.net/npm/ethers@6.9.0/dist/ethers.umd.min.js"></script>
  <style>
    .tab-panel { display: none; }
    .tab-panel.active { display: block; }
  </style>
</head>
<body class="bg-gray-900 text-white min-h-screen">
  <div id="app">
    <!-- Header -->
    <header class="bg-gray-800 p-4 flex justify-between items-center">
      <h1 class="text-2xl font-bold text-purple-400">Rogue High Rollers</h1>
      <div id="wallet-section">
        <button id="connect-btn" class="bg-purple-600 hover:bg-purple-700 px-6 py-2 rounded-lg cursor-pointer">
          Connect Wallet
        </button>
        <div id="wallet-info" class="items-center gap-4" style="display: none;">
          <img id="wallet-logo" src="" alt="" class="w-6 h-6">
          <span id="wallet-address" class="text-gray-300"></span>
          <span id="wallet-balance" class="text-green-400"></span>
        </div>
      </div>
    </header>

    <!-- HERO BANNER -->
    <section class="relative h-96 overflow-hidden">
      <!-- Background Image -->
      <div class="absolute inset-0">
        <img
          src="https://ik.imagekit.io/blockster/tr:w-1400,h-800,fo-top/girl-in-casino-2.jpg"
          alt="High Rollers Casino"
          class="w-full h-full object-cover"
        >
        <div class="absolute inset-0 bg-gradient-to-r from-gray-900 via-gray-900/80 to-transparent"></div>
      </div>

      <!-- Hero Content -->
      <div class="relative container mx-auto px-6 h-full flex items-center">
        <div class="max-w-xl">
          <h1 class="text-5xl font-bold mb-4">
            Rogue High Rollers NFTs
          </h1>
          <p class="text-2xl text-purple-400 font-bold mb-4">
            Real-Time Revenue Sharing
          </p>
          <p class="text-lg text-gray-300 mb-8">
            High Rollers NFTs earn a share of every winning bet - mint your NFT now and start earning passive income forever.
          </p>
          <div class="flex gap-4">
            <a href="#mint" class="bg-gradient-to-r from-purple-600 to-pink-600 hover:from-purple-700 hover:to-pink-700 px-8 py-3 rounded-lg text-lg font-bold cursor-pointer">
              Mint Now - 0.32 ETH
            </a>
            <a href="#gallery" class="border border-purple-500 hover:bg-purple-500/20 px-8 py-3 rounded-lg text-lg font-bold cursor-pointer">
              View Collection
            </a>
          </div>
        </div>
      </div>
    </section>

    <!-- Navigation Tabs -->
    <nav class="bg-gray-800 border-b border-gray-700 sticky top-0 z-40">
      <div class="container mx-auto flex overflow-x-auto">
        <button data-tab="mint" class="tab-btn px-6 py-4 text-purple-400 border-b-2 border-purple-400 cursor-pointer whitespace-nowrap">
          Mint
        </button>
        <button data-tab="gallery" class="tab-btn px-6 py-4 text-gray-400 hover:text-white cursor-pointer whitespace-nowrap">
          Gallery
        </button>
        <button data-tab="sales" class="tab-btn px-6 py-4 text-gray-400 hover:text-white cursor-pointer whitespace-nowrap">
          Live Sales
        </button>
        <button data-tab="affiliates" class="tab-btn px-6 py-4 text-gray-400 hover:text-white cursor-pointer whitespace-nowrap">
          Affiliates
        </button>
        <button data-tab="my-nfts" class="tab-btn px-6 py-4 text-gray-400 hover:text-white cursor-pointer whitespace-nowrap" id="my-nfts-tab" style="display: none;">
          My NFTs
        </button>
      </div>
    </nav>

    <!-- Tab Content -->
    <main>
      <!-- MINT TAB -->
      <div id="tab-mint" class="tab-panel active">
        <div class="container mx-auto p-6">
          <!-- Stats Section -->
          <section class="mb-8 grid grid-cols-1 md:grid-cols-4 gap-4">
            <div class="bg-gray-800 p-4 rounded-lg">
              <h3 class="text-gray-400 text-sm">Total Minted</h3>
              <p id="total-minted" class="text-2xl font-bold">-</p>
            </div>
            <div class="bg-gray-800 p-4 rounded-lg">
              <h3 class="text-gray-400 text-sm">Remaining</h3>
              <p id="remaining" class="text-2xl font-bold text-yellow-400">-</p>
            </div>
            <div class="bg-gray-800 p-4 rounded-lg">
              <h3 class="text-gray-400 text-sm">Current Price</h3>
              <p id="current-price" class="text-2xl font-bold">0.32 ETH</p>
            </div>
            <div class="bg-gray-800 p-4 rounded-lg">
              <h3 class="text-gray-400 text-sm">Max Supply</h3>
              <p class="text-2xl font-bold">2,700</p>
            </div>
          </section>

          <!-- Progress Bar -->
          <section class="mb-8">
            <div class="bg-gray-700 rounded-full h-4 overflow-hidden">
              <div id="mint-progress" class="bg-gradient-to-r from-purple-600 to-pink-600 h-full transition-all duration-500" style="width: 0%"></div>
            </div>
            <p class="text-center text-gray-400 mt-2">
              <span id="progress-text">0 / 2,700 minted</span>
            </p>
          </section>

          <!-- Mint Section -->
          <section class="mb-8 bg-gray-800 p-6 rounded-lg">
            <h2 class="text-xl font-bold mb-4">Mint Your High Roller</h2>

            <!-- Sold Out Message -->
            <div id="sold-out-message" class="hidden bg-red-900/50 border border-red-500 p-4 rounded-lg mb-4">
              <p class="text-red-400 font-bold">🎰 SOLD OUT!</p>
              <p class="text-gray-400">All 2,700 High Rollers have been minted.</p>
            </div>

            <div class="flex items-center gap-4">
              <button id="mint-btn" class="bg-gradient-to-r from-purple-600 to-pink-600 hover:from-purple-700 hover:to-pink-700 px-8 py-3 rounded-lg text-lg font-bold cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed">
                Mint for 0.32 ETH
              </button>
              <div id="mint-status" class="text-gray-400 hidden">
                <span class="animate-pulse">⏳</span>
                <span id="mint-status-text"></span>
              </div>
            </div>

            <!-- Mint Result -->
            <div id="mint-result" class="hidden mt-6 p-4 bg-gray-700 rounded-lg">
              <h3 class="text-lg font-bold mb-2">🎉 You Minted:</h3>
              <div class="flex items-center gap-4">
                <img id="minted-image" src="" alt="" class="w-32 h-32 rounded-lg">
                <div>
                  <p id="minted-name" class="text-xl font-bold text-purple-400"></p>
                  <p id="minted-rarity" class="text-gray-400"></p>
                  <p id="minted-token-id" class="text-sm text-gray-500"></p>
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>

      <!-- GALLERY TAB -->
      <div id="tab-gallery" class="tab-panel">
        <div class="container mx-auto p-6">
          <h2 class="text-xl font-bold mb-4">Collection Gallery</h2>
          <p class="text-gray-400 mb-6">8 unique High Roller hostesses, each with different rarity</p>
          <div id="hostess-gallery" class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <!-- Populated by JavaScript -->
          </div>
        </div>
      </div>

      <!-- SALES TAB -->
      <div id="tab-sales" class="tab-panel">
        <div class="container mx-auto p-6">
          <h2 class="text-xl font-bold mb-4">Live Sales</h2>
          <p class="text-gray-400 mb-6">Real-time feed of all High Roller mints</p>
          <div class="bg-gray-800 rounded-lg overflow-hidden">
            <table class="w-full">
              <thead class="bg-gray-700">
                <tr>
                  <th class="p-3 text-left">Token ID</th>
                  <th class="p-3 text-left">Type</th>
                  <th class="p-3 text-left">Buyer</th>
                  <th class="p-3 text-left">Price</th>
                  <th class="p-3 text-left">Time</th>
                  <th class="p-3 text-left">TX</th>
                </tr>
              </thead>
              <tbody id="sales-table-body">
                <!-- Populated by JavaScript -->
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- AFFILIATES TAB -->
      <div id="tab-affiliates" class="tab-panel">
        <!-- Content from Affiliate Tab UI section above -->
      </div>

      <!-- MY NFTS TAB -->
      <div id="tab-my-nfts" class="tab-panel">
        <div class="container mx-auto p-6">
          <h2 class="text-xl font-bold mb-4">My High Rollers</h2>
          <div id="my-nfts-grid" class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4">
            <!-- Populated by JavaScript -->
          </div>
        </div>
      </div>
    </main>
  </div>

  <script src="/js/wallet.js"></script>
  <script src="/js/affiliate.js"></script>
  <script src="/js/mint.js"></script>
  <script src="/js/ui.js"></script>
  <script src="/js/app.js"></script>
</body>
</html>
```

---

## Phase 5: Deployment

### 5.1 Environment Variables

```env
# .env
PORT=3001
ARBITRUM_RPC_URL=https://snowy-little-cloud.arbitrum-mainnet.quiknode.pro/f4051c078b1e168f278c0780d1d12b817152c84d
```

### 5.2 Package.json Scripts

```json
{
  "name": "high-rollers-nfts",
  "scripts": {
    "start": "node server/index.js",
    "dev": "nodemon server/index.js",
    "analyze": "node scripts/analyze-distribution.js"
  }
}
```

### 5.3 Fly.io Deployment

```bash
# Initialize Fly app (Frankfurt region - nearest to Austria)
flyctl launch --name high-rollers-nfts --region fra

# Create volume for SQLite in Frankfurt
flyctl volumes create data --size 1 --region fra

# Deploy
flyctl deploy
```

**fly.toml**:
```toml
app = "high-rollers-nfts"
primary_region = "fra"  # Frankfurt, Germany (nearest to Austria)

[build]
  builder = "heroku/buildpacks:20"

[env]
  PORT = "8080"

[http_service]
  internal_port = 8080
  force_https = true

[mounts]
  source = "data"
  destination = "/data"
```

---

## Implementation Checklist

### Phase 1: Setup
- [ ] Create project directory structure
- [ ] Initialize npm project
- [ ] Install dependencies
- [ ] Create configuration file with APP_MAX_SUPPLY = 2700
- [ ] Define contract ABI

### Phase 2: Server
- [ ] Implement SQLite database schema
- [ ] Create ContractService
- [ ] Create EventListener with fallback polling
- [ ] Create DataSyncService
- [ ] Implement API routes with remaining count
- [ ] Set up WebSocket server
- [ ] Create main server entry point

### Phase 3: Frontend
- [ ] Create HTML structure with tab navigation
- [ ] Implement MetaMask-specific wallet detection
- [ ] Implement minting functionality with fallback polling
- [ ] Implement affiliate link tracking
- [ ] Create UI manager with tab switching
- [ ] Create affiliate tab with referral link
- [ ] Main app initialization
- [ ] Real-time updates via WebSocket

### Phase 4: Testing
- [ ] Test MetaMask detection vs other wallets
- [ ] Test affiliate link flow
- [ ] Test event listener fallback
- [ ] Test sold out state at 2700
- [ ] Run distribution analysis script

### Phase 5: Deployment
- [ ] Set up environment variables
- [ ] Test locally
- [ ] Deploy to Fly.io
- [ ] Verify all functionality

---

## Security Considerations

1. **No Private Keys**: Server only reads from contract, never writes
2. **User Transactions**: All minting done via user's MetaMask
3. **Rate Limiting**: Implement rate limiting on API endpoints
4. **Input Validation**: Validate all user inputs
5. **CORS**: Configure appropriate CORS settings for production
6. **Affiliate Validation**: Validate affiliate addresses before storing

## Performance Optimizations

1. **Caching**: SQLite caches all NFT data locally
2. **Batch Queries**: Fetch NFT data in batches of 50-100
3. **WebSocket**: Real-time updates without polling
4. **Pagination**: All list endpoints support pagination
5. **Indexing**: Database indexes on frequently queried columns
6. **Fallback Polling**: Ensures reliability without excessive polling
7. **ImageKit**: Optimized image delivery with automatic resizing

---

## ImageKit Image Optimization

All NFT images are served through ImageKit for optimized delivery with automatic resizing.

### Base Image URLs

```javascript
// NFT Images stored in ImageKit
const NFT_IMAGES = {
  0: 'https://ik.imagekit.io/blockster/penelope.jpg',  // Penelope Fatale
  1: 'https://ik.imagekit.io/blockster/mia.jpg',       // Mia Siren
  2: 'https://ik.imagekit.io/blockster/cleo.jpg',      // Cleo Enchante
  3: 'https://ik.imagekit.io/blockster/sophia.jpg',    // Sophia Spark
  4: 'https://ik.imagekit.io/blockster/luna.jpg',      // Luna Mirage
  5: 'https://ik.imagekit.io/blockster/aurora.jpg',    // Aurora Seductra
  6: 'https://ik.imagekit.io/blockster/scarlett.jpg',  // Scarlett Ember
  7: 'https://ik.imagekit.io/blockster/vivienne.jpg'   // Vivienne Allure
};
```

### ImageKit Transform Helper

```javascript
// public/js/imagekit.js

// Image size transforms for ImageKit
const IMAGE_TRANSFORMS = {
  thumbnail: 'tr:w-48,h-48',     // Table rows (48x48)
  card: 'tr:w-200,h-200',        // Gallery cards (200x200)
  large: 'tr:w-400,h-400',       // Mint result, detail view
  banner: 'tr:w-1400,h-800'      // Hero banner
};

// Get optimized image URL with ImageKit transforms
function getOptimizedImageUrl(baseUrl, size = 'card') {
  const transform = IMAGE_TRANSFORMS[size] || IMAGE_TRANSFORMS.card;

  // Insert transform after domain: https://ik.imagekit.io/blockster/tr:w-48,h-48/penelope.jpg
  return baseUrl.replace(
    'https://ik.imagekit.io/blockster/',
    `https://ik.imagekit.io/blockster/${transform}/`
  );
}

// Get hostess image by index with optional size transform
function getHostessImageUrl(hostessIndex, size = 'card') {
  const hostess = HOSTESSES[hostessIndex];
  if (!hostess) return null;
  return getOptimizedImageUrl(hostess.image, size);
}

// Examples:
// getHostessImageUrl(0, 'thumbnail') => https://ik.imagekit.io/blockster/tr:w-48,h-48/penelope.jpg
// getHostessImageUrl(0, 'banner')    => https://ik.imagekit.io/blockster/tr:w-1400,h-600/penelope.jpg
```

### Usage in Tables (with Thumbnails)

```javascript
// Render sales table row with thumbnail
function renderSaleRow(sale) {
  const thumbnailUrl = getHostessImageUrl(sale.hostessIndex, 'thumbnail');

  return `
    <tr class="border-b border-gray-700 hover:bg-gray-750">
      <td class="p-3">
        <div class="flex items-center gap-3">
          <img src="${thumbnailUrl}" alt="${sale.hostessName}" class="w-10 h-10 rounded">
          <span>#${sale.tokenId}</span>
        </div>
      </td>
      <td class="p-3">
        <div class="flex items-center gap-2">
          <span>${sale.hostessName}</span>
          <span class="text-xs px-2 py-0.5 rounded bg-purple-900 text-purple-300">${sale.multiplier}x</span>
        </div>
      </td>
      <td class="p-3">${truncateAddress(sale.buyer)}</td>
      <td class="p-3">${sale.priceETH} ETH</td>
      <td class="p-3">${formatTime(sale.timestamp)}</td>
      <td class="p-3">
        <a href="https://arbiscan.io/tx/${sale.txHash}" target="_blank" class="text-purple-400 hover:underline cursor-pointer">
          View
        </a>
      </td>
    </tr>
  `;
}

// Render affiliate earnings row with thumbnail
function renderAffiliateRow(earning) {
  const thumbnailUrl = getHostessImageUrl(earning.hostessIndex, 'thumbnail');

  return `
    <tr class="border-b border-gray-700">
      <td class="p-3">
        <div class="flex items-center gap-3">
          <img src="${thumbnailUrl}" alt="${earning.hostessName}" class="w-10 h-10 rounded">
          <span>#${earning.tokenId}</span>
        </div>
      </td>
      <td class="p-3">
        <span class="px-2 py-1 rounded ${earning.tier === 1 ? 'bg-green-900 text-green-400' : 'bg-blue-900 text-blue-400'}">
          Tier ${earning.tier}
        </span>
      </td>
      <td class="p-3">${truncateAddress(earning.affiliate)}</td>
      <td class="p-3 text-green-400">${formatETH(earning.earnings)} ETH</td>
    </tr>
  `;
}
```

---

## NFT Owner Polling (Keep Data Fresh)

The app continuously polls the contract to keep NFT ownership data up to date.

### Owner Sync Service

```javascript
// server/services/ownerSync.js

class OwnerSyncService {
  constructor(db, contractService, config) {
    this.db = db;
    this.contractService = contractService;
    this.config = config;
    this.isRunning = false;
    this.lastSyncedTokenId = 0;
  }

  start() {
    if (this.isRunning) return;
    this.isRunning = true;

    // Full sync every 5 minutes
    this.fullSyncInterval = setInterval(() => {
      this.syncAllOwners();
    }, 5 * 60 * 1000);

    // Quick check for new mints every 30 seconds
    this.quickSyncInterval = setInterval(() => {
      this.syncRecentMints();
    }, 30 * 1000);

    // Initial sync on startup
    this.syncAllOwners();

    console.log('[OwnerSync] Started owner polling service');
  }

  /**
   * Full sync: Update all NFT owners in batches
   * Runs every 5 minutes to catch any missed transfers
   */
  async syncAllOwners() {
    try {
      const totalSupply = await this.contractService.getTotalSupply();
      const total = Number(totalSupply);

      console.log(`[OwnerSync] Starting full sync of ${total} NFTs`);

      const batchSize = 50;
      for (let i = 1; i <= total; i += batchSize) {
        const batch = [];
        for (let j = i; j < Math.min(i + batchSize, total + 1); j++) {
          batch.push(j);
        }

        // Fetch owners in parallel
        const owners = await Promise.all(
          batch.map(tokenId => this.contractService.getOwnerOf(tokenId))
        );

        // Update database
        batch.forEach((tokenId, index) => {
          if (owners[index]) {
            this.db.updateNFTOwner(tokenId, owners[index]);
          }
        });

        // Rate limiting delay
        await this.sleep(100);
      }

      console.log(`[OwnerSync] Full sync complete: ${total} NFTs updated`);
    } catch (error) {
      console.error('[OwnerSync] Full sync failed:', error);
    }
  }

  /**
   * Quick sync: Only check for new mints since last check
   * Runs every 30 seconds
   */
  async syncRecentMints() {
    try {
      const totalSupply = await this.contractService.getTotalSupply();
      const total = Number(totalSupply);

      if (total > this.lastSyncedTokenId) {
        console.log(`[OwnerSync] New mints detected: ${this.lastSyncedTokenId} -> ${total}`);

        // Sync new tokens
        for (let tokenId = this.lastSyncedTokenId + 1; tokenId <= total; tokenId++) {
          const owner = await this.contractService.getOwnerOf(tokenId);
          const hostessIndex = await this.contractService.getHostessIndex(tokenId);

          this.db.upsertNFT({
            tokenId,
            owner,
            hostessIndex: Number(hostessIndex),
            hostessName: this.config.HOSTESSES[Number(hostessIndex)]?.name
          });
        }

        this.lastSyncedTokenId = total;
      }
    } catch (error) {
      console.error('[OwnerSync] Quick sync failed:', error);
    }
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  stop() {
    this.isRunning = false;
    if (this.fullSyncInterval) clearInterval(this.fullSyncInterval);
    if (this.quickSyncInterval) clearInterval(this.quickSyncInterval);
    console.log('[OwnerSync] Stopped');
  }
}

module.exports = OwnerSyncService;
```

### Database Schema Update

```sql
-- Add last_synced column to track when each NFT was last verified
ALTER TABLE nfts ADD COLUMN last_owner_sync INTEGER DEFAULT 0;

-- Index for efficient queries
CREATE INDEX idx_nfts_last_sync ON nfts(last_owner_sync);
```

---

## Affiliate Withdrawal UI

Affiliates can withdraw their earned commissions directly from the app.

### Contract ABI (Withdrawal Function)

```javascript
// Add to CONTRACT_ABI
'function withdrawAffiliateBalance() external'
```

### Withdrawal UI Component

```html
<!-- In Affiliates Tab -->
<div class="bg-gray-700 p-4 rounded-lg">
  <h4 class="text-gray-400 text-sm">Withdrawable Balance</h4>
  <p id="my-affiliate-balance" class="text-2xl font-bold text-yellow-400">0 ETH</p>

  <button
    id="withdraw-btn"
    class="mt-3 w-full bg-gradient-to-r from-yellow-600 to-orange-600 hover:from-yellow-700 hover:to-orange-700 py-3 rounded-lg font-bold cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
    disabled
  >
    Withdraw Earnings
  </button>

  <div id="withdraw-status" class="hidden mt-2 text-sm">
    <span class="animate-pulse">⏳</span>
    <span id="withdraw-status-text"></span>
  </div>

  <div id="withdraw-success" class="hidden mt-2 text-green-400 text-sm">
    ✓ Withdrawal successful!
    <a id="withdraw-tx-link" href="" target="_blank" class="underline cursor-pointer">View transaction</a>
  </div>
</div>
```

### Withdrawal JavaScript

```javascript
// public/js/affiliate.js

class AffiliateService {
  // ... existing code ...

  async withdrawEarnings() {
    if (!walletService.signer) {
      throw new Error('Please connect your wallet first');
    }

    const contract = new ethers.Contract(
      CONTRACT_ADDRESS,
      ['function withdrawAffiliateBalance() external'],
      walletService.signer
    );

    // Check balance first
    const balance = await this.getWithdrawableBalance();
    if (BigInt(balance) === 0n) {
      throw new Error('No balance to withdraw');
    }

    // Execute withdrawal
    const tx = await contract.withdrawAffiliateBalance();

    return {
      txHash: tx.hash,
      wait: () => tx.wait()
    };
  }

  async getWithdrawableBalance() {
    const response = await fetch(`/api/affiliates/${walletService.address}`);
    const data = await response.json();
    return data.tier1.balance;  // Balance is stored in tier1
  }
}

// UI Handler
document.getElementById('withdraw-btn').addEventListener('click', async () => {
  const btn = document.getElementById('withdraw-btn');
  const status = document.getElementById('withdraw-status');
  const statusText = document.getElementById('withdraw-status-text');
  const success = document.getElementById('withdraw-success');

  try {
    btn.disabled = true;
    status.classList.remove('hidden');
    statusText.textContent = 'Preparing transaction...';

    const result = await affiliateService.withdrawEarnings();

    statusText.textContent = 'Waiting for confirmation...';

    await result.wait();

    // Update UI
    status.classList.add('hidden');
    success.classList.remove('hidden');
    document.getElementById('withdraw-tx-link').href = `https://arbiscan.io/tx/${result.txHash}`;

    // Refresh balance
    await app.loadMyAffiliateStats();

    // Update database via API
    await fetch('/api/affiliates/withdrawal', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        address: walletService.address,
        txHash: result.txHash
      })
    });

  } catch (error) {
    console.error('Withdrawal failed:', error);
    status.classList.add('hidden');
    alert(error.message);
  } finally {
    btn.disabled = false;
  }
});

// Enable/disable withdraw button based on balance
async function updateWithdrawButton() {
  const balance = await affiliateService.getWithdrawableBalance();
  const btn = document.getElementById('withdraw-btn');

  if (BigInt(balance) > 0n) {
    btn.disabled = false;
    btn.textContent = `Withdraw ${formatETH(balance)} ETH`;
  } else {
    btn.disabled = true;
    btn.textContent = 'No Balance to Withdraw';
  }
}
```

### API Route for Withdrawal Tracking

```javascript
// server/routes/api.js

// Record withdrawal in database
router.post('/affiliates/withdrawal', async (req, res) => {
  try {
    const { address, txHash } = req.body;

    if (!address || !txHash) {
      return res.status(400).json({ error: 'Missing address or txHash' });
    }

    // Record the withdrawal
    db.recordWithdrawal({
      address: address.toLowerCase(),
      txHash,
      timestamp: Math.floor(Date.now() / 1000)
    });

    // Reset the balance in our local tracking
    db.resetAffiliateBalance(address.toLowerCase());

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
```

---

## NFT Distribution Analysis (Queried Jan 3, 2026)

| Type | Expected % | Actual Count | Actual % |
|------|------------|--------------|----------|
| Penelope Fatale | 0.5% | 9 | 0.38% |
| Mia Siren | 1.0% | 21 | 0.90% |
| Cleo Enchante | 3.5% | 113 | 4.83% |
| Sophia Spark | 7.5% | 149 | 6.37% |
| Luna Mirage | 12.5% | 274 | 11.71% |
| Aurora Seductra | 25.0% | 580 | 24.80% |
| Scarlett Ember | 25.0% | 577 | 24.67% |
| Vivienne Allure | 25.0% | 616 | 26.34% |
| **Total** | - | **2,339** | 100% |
