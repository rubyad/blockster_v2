/**
 * PriceService - Polls price APIs for ROGUE/USD and ETH/USD prices every 10 minutes
 *
 * Architecture:
 * - Server tries Blockster API first (which polls CoinGecko every 10 min)
 * - Falls back to CoinGecko direct if Blockster API unavailable
 * - Both ROGUE and ETH prices cached in memory with timestamps
 * - ETH price used for NFT value calculation (0.32 ETH mint price)
 * - WebSocket broadcasts price updates to all connected clients
 * - API endpoint exposes prices to frontend
 */

class PriceService {
  constructor(websocketServer, config) {
    this.ws = websocketServer;
    this.config = config;

    // ROGUE price data
    this.roguePrice = 0;
    this.rogueUsd24hChange = 0;

    // ETH price data (for NFT value calculation)
    this.ethPrice = 0;
    this.ethUsd24hChange = 0;

    this.lastUpdated = 0;
    this.pollIntervalMs = 10 * 60 * 1000;  // 10 minutes (matches Blockster's CoinGecko poll interval)
    this.pollInterval = null;

    // Blockster's price API (uses PriceTracker which polls CoinGecko)
    this.blocksterApiBase = config.BLOCKSTER_API_URL || 'https://blockster-v2.fly.dev/api/prices';

    // CoinGecko direct API (fallback)
    this.coingeckoApiUrl = 'https://api.coingecko.com/api/v3/simple/price';
    this.rogueCoingeckoId = 'rogue';  // CoinGecko ID for ROGUE
  }

  async start() {
    // Fetch immediately on startup
    await this.fetchPrices();

    // Then poll every 10 minutes
    this.pollInterval = setInterval(async () => {
      await this.fetchPrices();
    }, this.pollIntervalMs);

    console.log('[PriceService] Started (polling Blockster API every 10 min)');
  }

  async fetchPrices() {
    try {
      // Try Blockster API first
      const success = await this.fetchFromBlockster();
      if (!success) {
        // Fall back to CoinGecko direct
        await this.fetchFromCoinGecko();
      }

      // Broadcast to all connected clients
      if (this.ws && this.lastUpdated > 0) {
        this.ws.broadcast({
          type: 'PRICE_UPDATE',
          data: this.getPrices()
        });
      }

    } catch (error) {
      console.error('[PriceService] Failed to fetch prices:', error.message);
      // Keep using last known prices - don't reset to 0
    }
  }

  async fetchFromBlockster() {
    try {
      // Fetch ROGUE and ETH prices in parallel
      const [rogueRes, ethRes] = await Promise.all([
        fetch(`${this.blocksterApiBase}/ROGUE`, {
          headers: { 'Accept': 'application/json' },
          signal: AbortSignal.timeout(10000)
        }),
        fetch(`${this.blocksterApiBase}/ETH`, {
          headers: { 'Accept': 'application/json' },
          signal: AbortSignal.timeout(10000)
        })
      ]);

      if (!rogueRes.ok || !ethRes.ok) {
        return false;  // Fall back to CoinGecko
      }

      const rogueData = await rogueRes.json();
      const ethData = await ethRes.json();

      this.roguePrice = rogueData.usd_price || 0;
      this.rogueUsd24hChange = rogueData.usd_24h_change || 0;
      this.ethPrice = ethData.usd_price || 0;
      this.ethUsd24hChange = ethData.usd_24h_change || 0;
      this.lastUpdated = Date.now();

      console.log(`[PriceService] Blockster: ROGUE: $${this.roguePrice} (${this.formatChange(this.rogueUsd24hChange)}), ETH: $${this.ethPrice} (${this.formatChange(this.ethUsd24hChange)})`);
      return true;

    } catch (error) {
      console.log('[PriceService] Blockster API unavailable, falling back to CoinGecko');
      return false;
    }
  }

  async fetchFromCoinGecko() {
    try {
      // Fetch both ROGUE and ETH from CoinGecko in one call
      const url = `${this.coingeckoApiUrl}?ids=${this.rogueCoingeckoId},ethereum&vs_currencies=usd&include_24hr_change=true`;
      const res = await fetch(url, {
        headers: { 'Accept': 'application/json' },
        signal: AbortSignal.timeout(10000)
      });

      if (!res.ok) {
        throw new Error(`CoinGecko HTTP ${res.status}`);
      }

      const data = await res.json();

      // ROGUE data
      if (data[this.rogueCoingeckoId]) {
        this.roguePrice = data[this.rogueCoingeckoId].usd || 0;
        this.rogueUsd24hChange = data[this.rogueCoingeckoId].usd_24h_change || 0;
      }

      // ETH data
      if (data.ethereum) {
        this.ethPrice = data.ethereum.usd || 0;
        this.ethUsd24hChange = data.ethereum.usd_24h_change || 0;
      }

      this.lastUpdated = Date.now();

      console.log(`[PriceService] CoinGecko: ROGUE: $${this.roguePrice} (${this.formatChange(this.rogueUsd24hChange)}), ETH: $${this.ethPrice} (${this.formatChange(this.ethUsd24hChange)})`);

    } catch (error) {
      console.error('[PriceService] CoinGecko fetch failed:', error.message);
    }
  }

  formatChange(change) {
    const sign = change >= 0 ? '+' : '';
    return `${sign}${change.toFixed(2)}%`;
  }

  getPrices() {
    return {
      rogue: {
        symbol: 'ROGUE',
        usdPrice: this.roguePrice,
        usd24hChange: this.rogueUsd24hChange
      },
      eth: {
        symbol: 'ETH',
        usdPrice: this.ethPrice,
        usd24hChange: this.ethUsd24hChange
      },
      lastUpdated: this.lastUpdated
    };
  }

  /**
   * Get NFT value in ROGUE based on 0.32 ETH mint price
   * @returns {number} NFT value in ROGUE
   */
  getNftValueInRogue() {
    if (!this.ethPrice || !this.roguePrice) return 0;
    const nftValueUsd = 0.32 * this.ethPrice;  // 0.32 ETH mint price
    return nftValueUsd / this.roguePrice;
  }

  /**
   * Get NFT value in USD based on 0.32 ETH mint price
   * @returns {number} NFT value in USD
   */
  getNftValueInUsd() {
    if (!this.ethPrice) return 0;
    return 0.32 * this.ethPrice;
  }

  /**
   * Format ROGUE amount to USD string
   * @param {number} rogueAmount - Amount in ROGUE
   * @returns {string} Formatted USD string (e.g., "$1.23", "$1.2k", "$1.2M")
   */
  formatUsd(rogueAmount) {
    if (!this.roguePrice || rogueAmount === 0) return '$0.00';

    const usd = rogueAmount * this.roguePrice;

    if (usd >= 1_000_000) {
      return `$${(usd / 1_000_000).toFixed(2)}M`;
    } else if (usd >= 1_000) {
      return `$${(usd / 1_000).toFixed(2)}k`;
    } else if (usd >= 0.01) {
      return `$${usd.toFixed(2)}`;
    } else if (usd > 0) {
      return '<$0.01';
    }
    return '$0.00';
  }

  stop() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
    console.log('[PriceService] Stopped');
  }
}

module.exports = PriceService;
