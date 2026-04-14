/**
 * FsTickerWidget — FateSwap horizontal ticker.
 *
 * The marquee scroll is pure CSS. The hook only listens for the
 * `widget:fs_feed:update` event as a sanity hook; the server
 * re-renders the row list via the LiveView diff, so there's no
 * DOM mutation to perform here.
 *
 * We briefly apply `bw-flash-new` to brand-new trade IDs (not in the
 * previously-seen set) so the eye tracks new fills as they slide in.
 */

export const FsTickerWidget = {
  mounted() {
    this.seenIds = new Set();
    this._refreshSeen();
    this.handleEvent("widget:fs_feed:update", () => {
      // Server re-renders via diff; flash new entries on the next updated/0.
    });
  },

  updated() {
    this._flashNew();
    this._refreshSeen();
  },

  destroyed() {
    this.seenIds = null;
  },

  _refreshSeen() {
    if (!this.el || !this.seenIds) return;
    const items = this.el.querySelectorAll('[data-role="fs-ticker-item"]');
    items.forEach((el) => {
      const id = el.dataset.tradeId;
      if (id) this.seenIds.add(id);
    });
  },

  _flashNew() {
    if (!this.el || !this.seenIds) return;
    const items = this.el.querySelectorAll('[data-role="fs-ticker-item"]');
    items.forEach((el) => {
      const id = el.dataset.tradeId;
      if (!id || this.seenIds.has(id)) return;
      el.classList.remove("bw-flash-new");
      void el.offsetWidth;
      el.classList.add("bw-flash-new");
      setTimeout(() => el.classList.remove("bw-flash-new"), 3000);
    });
  },
};
