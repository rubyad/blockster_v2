/**
 * RtLeaderboardWidget — RogueTrader inline top-10 leaderboard.
 *
 * Per Decision #7 exception, rows route individually to `/bot/:slug`
 * rather than the project homepage. `phx-value-*` can only carry flat
 * strings, but `ClickRouter` treats arbitrary binaries as order IDs
 * (→ fateswap.io). So we push `widget_click` from JS with a nested
 * `{bot_id, tf: "7d"}` subject — the `WidgetEvents` macro normalises
 * that tuple back and `ClickRouter` routes to `/bot/:bot_id`.
 *
 * Server → client events:
 *   · widget:rt_bots:update { bots } — LiveView diff re-renders rows.
 *     The hook caches the previous rank order in `mounted/0` and runs
 *     a simple FLIP slide on rank changes in `updated/0`.
 */

export const RtLeaderboardWidget = {
  mounted() {
    this.bannerId = this.el.dataset.bannerId;
    this.prevRanks = new Map();
    this._captureRanks();
    this._wireRows();
    this.handleEvent("widget:rt_bots:update", () => {
      // Server re-renders via diff; rank-change FLIP happens in updated/0.
    });
  },

  updated() {
    this._animateRankDeltas();
    this._wireRows();
    this._captureRanks();
  },

  destroyed() {
    if (this._unbindRows) this._unbindRows();
    this.prevRanks = null;
  },

  _wireRows() {
    // Remove previous listeners so re-renders don't double-bind.
    if (this._unbindRows) this._unbindRows();
    const rows = this.el.querySelectorAll('[data-role="rt-lb-row"]');
    const handlers = [];
    rows.forEach((row) => {
      const onClick = (e) => {
        e.stopPropagation();
        const botId = row.dataset.botId;
        if (!botId || !this.bannerId) return;
        this.pushEvent("widget_click", {
          banner_id: this.bannerId,
          subject: { bot_id: botId, tf: "7d" },
        });
      };
      row.addEventListener("click", onClick);
      handlers.push([row, onClick]);
    });
    this._unbindRows = () => {
      handlers.forEach(([row, h]) => row.removeEventListener("click", h));
    };
  },

  _captureRanks() {
    this.prevRanks = new Map();
    const rows = this.el.querySelectorAll('[data-role="rt-lb-row"]');
    rows.forEach((row, idx) => {
      const id = row.dataset.botId;
      if (id) this.prevRanks.set(id, { idx, y: row.getBoundingClientRect().top });
    });
  },

  _animateRankDeltas() {
    if (!this.prevRanks || this.prevRanks.size === 0) return;
    const rows = this.el.querySelectorAll('[data-role="rt-lb-row"]');
    rows.forEach((row, idx) => {
      const id = row.dataset.botId;
      if (!id) return;
      const prev = this.prevRanks.get(id);
      if (!prev) return;
      if (prev.idx === idx) return;
      // FLIP slide: start from previous Y offset, animate back to 0.
      const newY = row.getBoundingClientRect().top;
      const dy = prev.y - newY;
      if (Math.abs(dy) < 1) return;
      row.style.transition = "none";
      row.style.transform = `translateY(${dy}px)`;
      void row.offsetWidth;
      row.style.transition = "transform 320ms cubic-bezier(0.22, 0.8, 0.32, 1)";
      row.style.transform = "translateY(0)";
      setTimeout(() => {
        row.style.transition = "";
        row.style.transform = "";
      }, 360);
    });
  },
};
