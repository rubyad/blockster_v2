/**
 * FsSkyscraperWidget — FateSwap live-trade skyscraper widget.
 *
 * Listens for `widget:fs_feed:update` from the WidgetEvents macro and:
 *   · highlights newly-seen trades with the `bw-flash-new` animation
 *   · trims the visible row list back to 20 (server also caps, but
 *     morphdom timing can briefly leave stragglers during transition)
 *
 * The server component re-renders the full trade list on every update
 * (LiveView diff). The hook's job is purely visual — flashing new rows
 * and enforcing the max-row cap. Safe to no-op if the DOM disagrees.
 */

const MAX_ROWS = 20;

export const FsSkyscraperWidget = {
  mounted() {
    this.body = this.el.querySelector('[data-role="fs-skyscraper-body"]');
    this.seenIds = new Set();
    this.snapshotIds();
    this.handleEvent("widget:fs_feed:update", () => this.onUpdate());
  },

  updated() {
    this.body = this.el.querySelector('[data-role="fs-skyscraper-body"]');
    this.flashNewRows();
    this.capRows();
    this.snapshotIds();
  },

  destroyed() {
    this.seenIds = null;
  },

  snapshotIds() {
    if (!this.body || !this.seenIds) return;
    const rows = this.body.querySelectorAll("[data-trade-id]");
    rows.forEach((row) => this.seenIds.add(row.dataset.tradeId));
  },

  flashNewRows() {
    if (!this.body || !this.seenIds) return;
    const rows = this.body.querySelectorAll("[data-trade-id]");
    rows.forEach((row) => {
      if (!this.seenIds.has(row.dataset.tradeId)) {
        row.classList.remove("bw-flash-new");
        void row.offsetWidth;
        row.classList.add("bw-flash-new");
        setTimeout(() => row.classList.remove("bw-flash-new"), 3600);
      }
    });
  },

  capRows() {
    if (!this.body) return;
    const rows = this.body.querySelectorAll("[data-trade-id]");
    if (rows.length <= MAX_ROWS) return;
    for (let i = MAX_ROWS; i < rows.length; i++) {
      rows[i].remove();
    }
  },

  onUpdate() {
    // Server pushes the full list through LiveView diff; the hook work
    // happens in `updated/0` once morphdom finishes.
  },
};
