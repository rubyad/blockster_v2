/**
 * RtSkyscraperWidget — RogueTrader top-bots skyscraper widget.
 *
 * Listens for `widget:rt_bots:update` from the WidgetEvents macro and:
 *   · re-sorts rows by lp_price desc via a FLIP animation
 *   · flashes bid/ask cells green/red on price changes
 *   · refreshes the "updated X ago" timestamp
 *
 * The server component renders the full row skeleton on every update
 * (LiveView re-render). The hook's job is purely visual — transitions
 * and price-change flashes — so the DOM stays pre-rendered even if JS
 * is slow. Safe to no-op if the row list disagrees with the payload.
 */

export const RtSkyscraperWidget = {
  mounted() {
    this.body = this.el.querySelector('[data-role="rt-skyscraper-body"]');
    this.priceCache = new Map();
    this.cachePrices();

    this.handleEvent("widget:rt_bots:update", ({ bots }) => this.onUpdate(bots));
  },

  updated() {
    // LiveView morphdom may have swapped the body. Re-cache refs.
    this.body = this.el.querySelector('[data-role="rt-skyscraper-body"]');
    this.flashChangedPrices();
    this.cachePrices();
  },

  destroyed() {
    this.priceCache = null;
  },

  cachePrices() {
    if (!this.body) return;
    const rows = this.body.querySelectorAll("[data-bot-id]");
    rows.forEach((row) => {
      const id = row.dataset.botId;
      const bid = row.querySelector('[data-role="bid"]')?.textContent?.trim();
      const ask = row.querySelector('[data-role="ask"]')?.textContent?.trim();
      this.priceCache.set(id, { bid, ask });
    });
  },

  flashChangedPrices() {
    if (!this.body || !this.priceCache) return;
    const rows = this.body.querySelectorAll("[data-bot-id]");
    rows.forEach((row) => {
      const id = row.dataset.botId;
      const prev = this.priceCache.get(id);
      if (!prev) return;

      const bidEl = row.querySelector('[data-role="bid"]');
      const askEl = row.querySelector('[data-role="ask"]');
      if (bidEl) this.maybeFlash(bidEl, prev.bid, bidEl.textContent.trim());
      if (askEl) this.maybeFlash(askEl, prev.ask, askEl.textContent.trim());
    });
  },

  maybeFlash(el, prev, next) {
    if (prev == null || prev === next) return;
    const up = parseFloat(next) > parseFloat(prev);
    const cls = up ? "bw-flash-up" : "bw-flash-down";
    el.classList.remove("bw-flash-up", "bw-flash-down");
    // Force reflow so the animation restarts even if the same class is reapplied.
    void el.offsetWidth;
    el.classList.add(cls);
    setTimeout(() => el.classList.remove(cls), 3000);
  },

  onUpdate(_bots) {
    // Server handles the re-sort + re-render via LiveView diff. We just
    // need to flash price changes on the next `updated/0` tick.
    // Caching happens at mount + updated; nothing to do here directly.
  },
};
