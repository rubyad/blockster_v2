/**
 * RtTickerWidget — RogueTrader horizontal ticker.
 *
 * The marquee scroll is pure CSS (`.bw-marquee-track` + `@keyframes
 * bw-marquee-scroll`). The hook's only job is visual polish: flash
 * bid/ask cells green/red when the server re-renders the rows with
 * different prices.
 *
 * Server → client events:
 *   · widget:rt_bots:update { bots } — sent by WidgetEvents on every
 *     RogueTraderBotsTracker poll. The server also re-renders the row
 *     list via the LiveView diff; the hook caches previous prices in
 *     `mounted/0` + `updated/0` and flashes the deltas.
 *
 * There's no push-event-driven re-render here — the DOM is always
 * fresh from LiveView. Doubling up with JS writes would fight the
 * diff.
 */

export const RtTickerWidget = {
  mounted() {
    this.priceCache = new Map();
    this._cachePrices();
    this.handleEvent("widget:rt_bots:update", () => {
      // Server re-renders via diff; nothing to mutate here.
    });
  },

  updated() {
    this._flashChangedPrices();
    this._cachePrices();
  },

  destroyed() {
    this.priceCache = null;
  },

  _cachePrices() {
    if (!this.el) return;
    // The track is duplicated (set 1 + set 2) for the seamless loop —
    // we only need to cache one row per bot, since both sets get the
    // same prices. Use the first occurrence.
    const items = this.el.querySelectorAll('[data-role="rt-ticker-item"]');
    items.forEach((el) => {
      const id = el.dataset.botId;
      if (!id || this.priceCache.has(id)) return;
      const bid = el.querySelector('[data-role="bid"]')?.textContent?.trim();
      const ask = el.querySelector('[data-role="ask"]')?.textContent?.trim();
      this.priceCache.set(id, { bid, ask });
    });
  },

  _flashChangedPrices() {
    if (!this.el || !this.priceCache) return;
    const items = this.el.querySelectorAll('[data-role="rt-ticker-item"]');
    const seen = new Set();
    items.forEach((el) => {
      const id = el.dataset.botId;
      if (!id || seen.has(id)) return;
      seen.add(id);
      const prev = this.priceCache.get(id);
      if (!prev) return;

      const bidEl = el.querySelector('[data-role="bid"]');
      const askEl = el.querySelector('[data-role="ask"]');
      if (bidEl) this._maybeFlash(bidEl, prev.bid, bidEl.textContent.trim());
      if (askEl) this._maybeFlash(askEl, prev.ask, askEl.textContent.trim());
    });
    // Repeat on the second (duplicate) set so both halves flash together.
    const dupes = this.el.querySelectorAll('[data-role="rt-ticker-item"]');
    dupes.forEach((el) => {
      const id = el.dataset.botId;
      const prev = this.priceCache.get(id);
      if (!prev) return;
      const bidEl = el.querySelector('[data-role="bid"]');
      const askEl = el.querySelector('[data-role="ask"]');
      if (bidEl) this._maybeFlash(bidEl, prev.bid, bidEl.textContent.trim());
      if (askEl) this._maybeFlash(askEl, prev.ask, askEl.textContent.trim());
    });
  },

  _maybeFlash(el, prev, next) {
    if (prev == null || prev === next) return;
    const up = parseFloat(next) > parseFloat(prev);
    const cls = up ? "bw-flash-up" : "bw-flash-down";
    el.classList.remove("bw-flash-up", "bw-flash-down");
    void el.offsetWidth;
    el.classList.add(cls);
    setTimeout(() => el.classList.remove(cls), 2400);
  },
};
