/**
 * CfLiveCycle — JS hook for coin flip live widgets.
 *
 * Cycles through the last 10 settled games with 5-second intervals.
 * Game data is passed as a JSON data attribute and updated via LiveView patches.
 * The hook handles DOM updates client-side to avoid server round-trips on each tick.
 *
 * Data attributes on the hook element:
 *   data-games — JSON array of formatted game objects
 */
export const CfLiveCycle = {
  mounted() {
    this.games = JSON.parse(this.el.dataset.games || '[]');
    this.index = 0;
    this.startCycle();
  },

  updated() {
    // LiveView pushed new data (e.g. from PubSub bet_settled)
    const newGames = JSON.parse(this.el.dataset.games || '[]');
    if (JSON.stringify(newGames) !== JSON.stringify(this.games)) {
      this.games = newGames;
      // If current index is out of bounds, reset
      if (this.index >= this.games.length) {
        this.index = 0;
      }
    }
  },

  startCycle() {
    this.timer = setInterval(() => {
      if (this.games.length <= 1) return;
      this.index = (this.index + 1) % this.games.length;
      this.renderGame(this.games[this.index]);
    }, 5000);
  },

  renderGame(game) {
    if (!game) return;

    const body = this.el.querySelector('[data-cf-live-body]');
    if (!body) return;

    // Add a subtle crossfade
    body.style.transition = 'opacity 0.3s ease';
    body.style.opacity = '0';

    setTimeout(() => {
      // Update status
      this.updateStatus(body, game);
      // Update chips
      this.updateChips(body, game);
      // Update stats
      this.updateStats(body, game);
      // Update wallet in footer
      this.updateFooter(game);

      body.style.opacity = '1';
    }, 300);
  },

  updateStatus(body, game) {
    const status = body.querySelector('[class*="status--"]');
    if (status) {
      status.className = status.className.replace(/status--\w+/, game.won ? 'status--win' : 'status--loss');
      status.textContent = game.won ? 'Winner' : 'House Wins';
    }
  },

  updateChips(body, _game) {
    // Chips are rendered server-side and updated via LiveView patches
    // The crossfade provides visual feedback during cycling
  },

  updateStats(body, _game) {
    // Stats are rendered server-side
  },

  updateFooter(game) {
    const wallet = this.el.querySelector('[class*="hook-wallet"]');
    if (wallet) {
      wallet.textContent = game.wallet_short || '...';
    }
  },

  destroyed() {
    if (this.timer) clearInterval(this.timer);
  }
};
