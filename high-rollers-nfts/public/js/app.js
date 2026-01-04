// High Rollers NFT - Main Application

class HighRollersApp {
  constructor() {
    this.ws = null;
    this.currentTab = 'mint';
    this.stats = null;

    // Pagination state
    this.salesOffset = 0;
    this.salesLoading = false;
    this.salesEnd = false;
    this.salesScrollSetup = false;
    this.affiliatesOffset = 0;
    this.affiliatesLoading = false;
    this.affiliatesEnd = false;
    this.affiliatesScrollSetup = false;
    this.PAGE_SIZE = 50;

    this.init();
  }

  async init() {
    // Set up event listeners
    this.setupTabNavigation();
    this.setupWalletUI();
    this.setupMintUI();
    this.setupAffiliateUI();

    // Connect to WebSocket
    this.connectWebSocket();

    // Load initial data
    await this.loadStats();
    this.renderRarityGrid();

    // Handle initial route
    this.handleRoute();

    // Set up mint service callbacks
    mintService.onMintRequested((data) => this.handleMintRequested(data));
    mintService.onMintComplete((data) => this.handleMintComplete(data));
    mintService.onMintError((error) => this.handleMintError(error));
  }

  // ==================== Tab Navigation ====================

  setupTabNavigation() {
    const tabs = document.querySelectorAll('.tab-btn');

    tabs.forEach(tab => {
      tab.addEventListener('click', () => {
        this.switchTab(tab.dataset.tab);
      });
    });

    // Hero buttons
    document.getElementById('hero-mint-btn')?.addEventListener('click', () => {
      this.switchTab('mint');
      document.getElementById('tab-mint')?.scrollIntoView({ behavior: 'smooth' });
    });

    document.getElementById('hero-gallery-btn')?.addEventListener('click', () => {
      this.switchTab('gallery');
    });

    // Handle browser back/forward
    window.addEventListener('popstate', () => this.handleRoute());
  }

  switchTab(tabName) {
    // Update URL without reload
    const url = tabName === 'mint' ? '/' : `/${tabName}`;
    history.pushState({}, '', url);

    this.currentTab = tabName;

    // Update tab styles
    document.querySelectorAll('.tab-btn').forEach(tab => {
      const isActive = tab.dataset.tab === tabName;
      tab.classList.toggle('text-purple-400', isActive);
      tab.classList.toggle('border-b-2', isActive);
      tab.classList.toggle('border-purple-400', isActive);
      tab.classList.toggle('text-gray-400', !isActive);
    });

    // Show/hide panels
    document.querySelectorAll('.tab-panel').forEach(panel => {
      panel.classList.toggle('hidden', panel.id !== `tab-${tabName}`);
    });

    // Load data for the tab
    this.onTabChange(tabName);
  }

  handleRoute() {
    const path = window.location.pathname.slice(1) || 'mint';
    const validTabs = ['mint', 'gallery', 'sales', 'affiliates', 'my-nfts'];
    const tabName = validTabs.includes(path) ? path : 'mint';
    this.switchTab(tabName);
  }

  onTabChange(tabName) {
    switch (tabName) {
      case 'sales':
        this.loadSales();
        break;
      case 'affiliates':
        this.loadAffiliateData();
        break;
      case 'my-nfts':
        this.loadMyNFTs();
        break;
      case 'gallery':
        this.loadHostessGallery();
        break;
    }
  }

  // ==================== Wallet UI ====================

  setupWalletUI() {
    const connectBtn = document.getElementById('connect-btn');
    const disconnectBtn = document.getElementById('disconnect-btn');
    const walletModal = document.getElementById('wallet-modal');
    const closeModalBtn = document.getElementById('close-wallet-modal');
    const affiliateConnectBtn = document.getElementById('affiliate-connect-btn');

    // Show wallet modal
    connectBtn?.addEventListener('click', () => this.showWalletModal());
    affiliateConnectBtn?.addEventListener('click', () => this.showWalletModal());

    // Close modal
    closeModalBtn?.addEventListener('click', () => this.hideWalletModal());
    walletModal?.addEventListener('click', (e) => {
      if (e.target === walletModal) this.hideWalletModal();
    });

    // Wallet options
    document.querySelectorAll('.wallet-option').forEach(btn => {
      btn.addEventListener('click', () => this.handleWalletSelect(btn.dataset.wallet));
    });

    // Disconnect
    disconnectBtn?.addEventListener('click', () => {
      walletService.disconnect();
      this.updateWalletUI(null);
    });

    // Wallet service callbacks
    walletService.onConnect((address, type) => {
      this.updateWalletUI({ address, type });
    });

    walletService.onDisconnect(() => {
      this.updateWalletUI(null);
    });
  }

  showWalletModal() {
    document.getElementById('wallet-modal')?.classList.remove('hidden');
  }

  hideWalletModal() {
    document.getElementById('wallet-modal')?.classList.add('hidden');
  }

  async handleWalletSelect(walletType) {
    try {
      const result = await walletService.connectWallet(walletType);
      this.hideWalletModal();
      this.updateWalletUI(result);
      UI.showToast('Wallet connected successfully', 'success');
    } catch (error) {
      console.error('Connection failed:', error);
      UI.showToast(error.message || 'Failed to connect wallet', 'error');
    }
  }

  async updateWalletUI(result) {
    const connectBtn = document.getElementById('connect-btn');
    const walletInfo = document.getElementById('wallet-info');
    const myNftsTab = document.getElementById('my-nfts-tab');
    const affiliateConnectPrompt = document.getElementById('affiliate-connect-prompt');
    const myReferralSection = document.getElementById('my-referral-section');

    if (result) {
      connectBtn?.classList.add('hidden');
      walletInfo?.classList.remove('hidden');
      walletInfo?.classList.add('flex');
      myNftsTab?.classList.remove('hidden');
      affiliateConnectPrompt?.classList.add('hidden');
      myReferralSection?.classList.remove('hidden');

      document.getElementById('wallet-logo').src = walletService.getWalletLogo();
      document.getElementById('wallet-address').textContent = UI.truncateAddress(result.address);

      // Update balance
      const balance = await walletService.getBalance();
      document.getElementById('wallet-balance').textContent = `${parseFloat(balance).toFixed(4)} ETH`;

      // Update affiliate referral link
      document.getElementById('referral-link').value =
        affiliateService.generateReferralLink(result.address);

      // Load affiliate stats
      this.loadMyAffiliateStats();
    } else {
      connectBtn?.classList.remove('hidden');
      walletInfo?.classList.add('hidden');
      walletInfo?.classList.remove('flex');
      myNftsTab?.classList.add('hidden');
      affiliateConnectPrompt?.classList.remove('hidden');
      myReferralSection?.classList.add('hidden');
    }
  }

  // ==================== Mint UI ====================

  setupMintUI() {
    const mintBtn = document.getElementById('mint-btn');
    const myNftsMintBtn = document.getElementById('my-nfts-mint-btn');

    mintBtn?.addEventListener('click', () => this.handleMint());
    myNftsMintBtn?.addEventListener('click', () => {
      this.switchTab('mint');
    });
  }

  async handleMint() {
    if (!walletService.isConnected()) {
      this.showWalletModal();
      return;
    }

    const mintBtn = document.getElementById('mint-btn');
    const mintStatus = document.getElementById('mint-status');
    const mintStatusText = document.getElementById('mint-status-text');

    try {
      mintBtn.disabled = true;
      mintStatus.classList.remove('hidden');
      mintStatusText.textContent = 'Confirm transaction in wallet...';

      await mintService.mint();

      mintStatusText.textContent = 'Waiting for Chainlink VRF to reveal your hostess...';
    } catch (error) {
      console.error('Mint failed:', error);
      mintBtn.disabled = false;
      mintStatus.classList.add('hidden');

      let message = error.reason || error.message || 'Mint failed';
      if (message.includes('insufficient funds')) {
        message = 'Insufficient ETH balance';
      }
      UI.showToast(message, 'error');
    }
  }

  handleMintRequested(data) {
    console.log('Mint requested:', data);
    document.getElementById('mint-status-text').textContent =
      'Waiting for Chainlink VRF to reveal your hostess...';
  }

  handleMintComplete(data) {
    console.log('Mint complete:', data);

    const mintBtn = document.getElementById('mint-btn');
    const mintStatus = document.getElementById('mint-status');
    const mintResult = document.getElementById('mint-result');

    mintBtn.disabled = false;
    mintStatus.classList.add('hidden');
    mintResult.classList.remove('hidden');

    // Update result display
    document.getElementById('minted-image').src =
      ImageKit.getOptimizedUrl(data.hostessImage, 'large');
    document.getElementById('minted-name').textContent = data.hostessName;
    document.getElementById('minted-rarity').textContent = `Rarity: ${data.hostessRarity}`;
    document.getElementById('minted-multiplier').textContent = `${data.hostessMultiplier}x Revenue Multiplier`;
    document.getElementById('minted-token-id').textContent = `Token ID: #${data.tokenId}`;
    document.getElementById('minted-tx-link').href =
      `${CONFIG.EXPLORER_URL}/tx/${data.txHash}`;

    // Refresh stats
    this.loadStats();

    UI.showToast(`You minted ${data.hostessName}!`, 'success');
  }

  handleMintError(error) {
    const mintBtn = document.getElementById('mint-btn');
    const mintStatus = document.getElementById('mint-status');

    mintBtn.disabled = false;
    mintStatus.classList.add('hidden');

    UI.showToast(error.message, 'error');
  }

  // ==================== Stats & Data Loading ====================

  async loadStats() {
    try {
      const response = await fetch(`${CONFIG.API_BASE}/stats`);
      this.stats = await response.json();

      // Update UI
      document.getElementById('total-minted').textContent =
        UI.formatNumber(this.stats.totalMinted);
      document.getElementById('remaining').textContent =
        UI.formatNumber(this.stats.remaining);
      document.getElementById('current-price').textContent =
        `${this.stats.currentPriceETH} ETH`;

      // Update progress bar
      const progress = (this.stats.totalMinted / this.stats.maxSupply) * 100;
      document.getElementById('mint-progress').style.width = `${progress}%`;
      document.getElementById('progress-text').textContent =
        `${UI.formatNumber(this.stats.totalMinted)} / ${UI.formatNumber(this.stats.maxSupply)} minted`;

      // Check if sold out
      if (this.stats.soldOut) {
        document.getElementById('sold-out-message')?.classList.remove('hidden');
        document.getElementById('mint-btn').disabled = true;
      }
    } catch (error) {
      console.error('Failed to load stats:', error);
    }
  }

  renderRarityGrid() {
    const grid = document.getElementById('rarity-grid');
    if (!grid) return;

    grid.innerHTML = CONFIG.HOSTESSES.map(hostess =>
      UI.renderRarityCard(hostess)
    ).join('');
  }

  async loadHostessGallery() {
    const gallery = document.getElementById('hostess-gallery');
    if (!gallery) return;

    // Get counts from stats
    const counts = this.stats?.hostessCounts || {};

    gallery.innerHTML = CONFIG.HOSTESSES.map(hostess =>
      UI.renderHostessCard(hostess, counts[hostess.index] || 0)
    ).join('');
  }

  async loadSales() {
    const tbody = document.getElementById('sales-table-body');
    const loading = document.getElementById('sales-loading');
    const scrollContainer = document.getElementById('sales-scroll-container');

    // Reset pagination state
    this.salesOffset = 0;
    this.salesEnd = false;
    tbody.innerHTML = '';

    try {
      const response = await fetch(`${CONFIG.API_BASE}/sales?limit=${this.PAGE_SIZE}&offset=0`);
      const sales = await response.json();

      loading?.classList.add('hidden');

      if (sales.length === 0) {
        tbody.innerHTML = `
          <tr><td colspan="6" class="p-4 text-center text-gray-400">No sales yet</td></tr>
        `;
        return;
      }

      tbody.innerHTML = sales.map(sale => UI.renderSaleRow(sale)).join('');
      this.salesOffset = sales.length;

      if (sales.length < this.PAGE_SIZE) {
        this.salesEnd = true;
        document.getElementById('sales-end')?.classList.remove('hidden');
      }

      // Set up infinite scroll
      this.setupSalesInfiniteScroll(scrollContainer);
    } catch (error) {
      console.error('Failed to load sales:', error);
      loading.textContent = 'Failed to load sales';
    }
  }

  setupSalesInfiniteScroll(container) {
    if (!container || this.salesScrollSetup) return;
    this.salesScrollSetup = true;

    container.addEventListener('scroll', async () => {
      if (this.salesLoading || this.salesEnd) return;

      const { scrollTop, scrollHeight, clientHeight } = container;
      if (scrollTop + clientHeight >= scrollHeight - 100) {
        await this.loadMoreSales();
      }
    });
  }

  async loadMoreSales() {
    if (this.salesLoading || this.salesEnd) return;

    this.salesLoading = true;
    const loadMore = document.getElementById('sales-load-more');
    loadMore?.classList.remove('hidden');

    try {
      const response = await fetch(`${CONFIG.API_BASE}/sales?limit=${this.PAGE_SIZE}&offset=${this.salesOffset}`);
      const sales = await response.json();

      if (sales.length === 0) {
        this.salesEnd = true;
        document.getElementById('sales-end')?.classList.remove('hidden');
      } else {
        const tbody = document.getElementById('sales-table-body');
        tbody.innerHTML += sales.map(sale => UI.renderSaleRow(sale)).join('');
        this.salesOffset += sales.length;

        if (sales.length < this.PAGE_SIZE) {
          this.salesEnd = true;
          document.getElementById('sales-end')?.classList.remove('hidden');
        }
      }
    } catch (error) {
      console.error('Failed to load more sales:', error);
    } finally {
      this.salesLoading = false;
      loadMore?.classList.add('hidden');
    }
  }

  async loadMyNFTs() {
    if (!walletService.isConnected()) {
      this.switchTab('mint');
      return;
    }

    const grid = document.getElementById('my-nfts-grid');
    const loading = document.getElementById('my-nfts-loading');
    const empty = document.getElementById('my-nfts-empty');

    loading?.classList.remove('hidden');
    empty?.classList.add('hidden');
    grid.innerHTML = '';

    try {
      const response = await fetch(`${CONFIG.API_BASE}/nfts/${walletService.address}`);
      const nfts = await response.json();

      loading?.classList.add('hidden');

      if (nfts.length === 0) {
        empty?.classList.remove('hidden');
        return;
      }

      grid.innerHTML = nfts.map(nft => UI.renderNFTCard(nft)).join('');
    } catch (error) {
      console.error('Failed to load NFTs:', error);
      loading.textContent = 'Failed to load NFTs';
    }
  }

  // ==================== Affiliate UI ====================

  setupAffiliateUI() {
    const copyBtn = document.getElementById('copy-referral-btn');
    const withdrawBtn = document.getElementById('withdraw-btn');

    copyBtn?.addEventListener('click', async () => {
      if (walletService.isConnected()) {
        await affiliateService.copyReferralLink(walletService.address);
        document.getElementById('copy-success')?.classList.remove('hidden');
        setTimeout(() => {
          document.getElementById('copy-success')?.classList.add('hidden');
        }, 3000);
      }
    });

    withdrawBtn?.addEventListener('click', () => this.handleWithdraw());
  }

  async loadAffiliateData() {
    await this.loadAffiliateEarnings();

    if (walletService.isConnected()) {
      await this.loadMyAffiliateStats();
    }
  }

  async loadAffiliateEarnings() {
    const tbody = document.getElementById('affiliate-table-body');
    const scrollContainer = document.getElementById('affiliates-scroll-container');

    // Reset pagination state
    this.affiliatesOffset = 0;
    this.affiliatesEnd = false;
    tbody.innerHTML = '';

    try {
      const response = await fetch(`${CONFIG.API_BASE}/affiliates?limit=${this.PAGE_SIZE}&offset=0`);
      const earnings = await response.json();

      if (earnings.length === 0) {
        tbody.innerHTML = `
          <tr><td colspan="4" class="p-4 text-center text-gray-400">No affiliate earnings yet</td></tr>
        `;
        return;
      }

      tbody.innerHTML = earnings.map(e => UI.renderAffiliateRow(e)).join('');
      this.affiliatesOffset = earnings.length;

      if (earnings.length < this.PAGE_SIZE) {
        this.affiliatesEnd = true;
        document.getElementById('affiliates-end')?.classList.remove('hidden');
      }

      // Set up infinite scroll
      this.setupAffiliatesInfiniteScroll(scrollContainer);
    } catch (error) {
      console.error('Failed to load affiliate earnings:', error);
    }
  }

  setupAffiliatesInfiniteScroll(container) {
    if (!container || this.affiliatesScrollSetup) return;
    this.affiliatesScrollSetup = true;

    container.addEventListener('scroll', async () => {
      if (this.affiliatesLoading || this.affiliatesEnd) return;

      const { scrollTop, scrollHeight, clientHeight } = container;
      if (scrollTop + clientHeight >= scrollHeight - 100) {
        await this.loadMoreAffiliates();
      }
    });
  }

  async loadMoreAffiliates() {
    if (this.affiliatesLoading || this.affiliatesEnd) return;

    this.affiliatesLoading = true;
    const loadMore = document.getElementById('affiliates-load-more');
    loadMore?.classList.remove('hidden');

    try {
      const response = await fetch(`${CONFIG.API_BASE}/affiliates?limit=${this.PAGE_SIZE}&offset=${this.affiliatesOffset}`);
      const earnings = await response.json();

      if (earnings.length === 0) {
        this.affiliatesEnd = true;
        document.getElementById('affiliates-end')?.classList.remove('hidden');
      } else {
        const tbody = document.getElementById('affiliate-table-body');
        tbody.innerHTML += earnings.map(e => UI.renderAffiliateRow(e)).join('');
        this.affiliatesOffset += earnings.length;

        if (earnings.length < this.PAGE_SIZE) {
          this.affiliatesEnd = true;
          document.getElementById('affiliates-end')?.classList.remove('hidden');
        }
      }
    } catch (error) {
      console.error('Failed to load more affiliate earnings:', error);
    } finally {
      this.affiliatesLoading = false;
      loadMore?.classList.add('hidden');
    }
  }

  async loadMyAffiliateStats() {
    if (!walletService.isConnected()) return;

    try {
      const response = await fetch(`${CONFIG.API_BASE}/affiliates/${walletService.address}`);
      const data = await response.json();

      document.getElementById('my-tier1-earnings').textContent =
        `${UI.formatETH(data.tier1.earnings)} ETH`;
      document.getElementById('my-tier2-earnings').textContent =
        `${UI.formatETH(data.tier2.earnings)} ETH`;
      document.getElementById('my-affiliate-balance').textContent =
        `${UI.formatETH(data.tier1.balance)} ETH`;

      // Enable/disable withdraw button
      const withdrawBtn = document.getElementById('withdraw-btn');
      const hasBalance = BigInt(data.tier1.balance || '0') > 0n;
      withdrawBtn.disabled = !hasBalance;

      // Render referrals table
      const tbody = document.getElementById('my-referrals-table');
      if (data.earningsPerNFT.length === 0) {
        tbody.innerHTML = `
          <tr><td colspan="3" class="py-2 text-gray-400">No referrals yet</td></tr>
        `;
      } else {
        tbody.innerHTML = data.earningsPerNFT.map(e => `
          <tr class="border-t border-gray-600">
            <td class="py-2">${UI.truncateAddress(e.buyer_address)}</td>
            <td class="py-2">#${e.token_id}</td>
            <td class="py-2 text-green-400">${UI.formatETH(e.earnings)} ETH</td>
          </tr>
        `).join('');
      }
    } catch (error) {
      console.error('Failed to load affiliate stats:', error);
    }
  }

  async handleWithdraw() {
    const withdrawBtn = document.getElementById('withdraw-btn');

    try {
      withdrawBtn.disabled = true;
      withdrawBtn.textContent = 'Withdrawing...';

      const result = await affiliateService.withdrawEarnings();

      UI.showToast('Withdrawal transaction sent', 'info');

      await result.wait();

      UI.showToast('Withdrawal successful!', 'success');

      // Refresh stats
      await this.loadMyAffiliateStats();
    } catch (error) {
      console.error('Withdrawal failed:', error);
      UI.showToast(error.message || 'Withdrawal failed', 'error');
    } finally {
      withdrawBtn.disabled = false;
      withdrawBtn.textContent = 'Withdraw';
    }
  }

  // ==================== WebSocket ====================

  connectWebSocket() {
    try {
      this.ws = new WebSocket(CONFIG.WS_URL);

      this.ws.onopen = () => {
        console.log('[WebSocket] Connected');
      };

      this.ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data);
          this.handleWebSocketMessage(message);
        } catch (error) {
          console.error('[WebSocket] Failed to parse message:', error);
        }
      };

      this.ws.onclose = () => {
        console.log('[WebSocket] Disconnected, reconnecting in 5s...');
        setTimeout(() => this.connectWebSocket(), 5000);
      };

      this.ws.onerror = (error) => {
        console.error('[WebSocket] Error:', error);
      };
    } catch (error) {
      console.error('[WebSocket] Failed to connect:', error);
    }
  }

  handleWebSocketMessage(message) {
    console.log('[WebSocket] Message:', message.type);

    switch (message.type) {
      case 'NFT_MINTED':
        // Check if this is our mint
        mintService.handleWebSocketMintEvent(message.data);

        // Refresh stats
        this.loadStats();

        // If on sales tab, prepend new sale
        if (this.currentTab === 'sales') {
          const tbody = document.getElementById('sales-table-body');
          const newRow = UI.renderSaleRow({
            token_id: message.data.tokenId,
            hostess_index: message.data.hostessIndex,
            hostess_name: message.data.hostessName,
            buyer: message.data.recipient,
            price: message.data.price,
            priceETH: message.data.priceETH,
            tx_hash: message.data.txHash,
            timestamp: Math.floor(Date.now() / 1000)
          });
          tbody.insertAdjacentHTML('afterbegin', newRow);
        }
        break;

      case 'MINT_REQUESTED':
        // Could show a "pending mint" indicator
        break;

      case 'NFT_TRANSFERRED':
        // Could update ownership display
        break;
    }
  }
}

// Initialize app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.app = new HighRollersApp();
});
