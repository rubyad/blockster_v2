/**
 * FsHeroWidget — shared hook for fs_hero_portrait + fs_hero_landscape.
 *
 * Listens for `widget:<banner_id>:select` from the `WidgetEvents`
 * macro. The LiveView emits this whenever `WidgetSelector` picks a
 * different order id for this banner. The payload carries the full
 * order map alongside the id.
 *
 * The server ALSO re-renders the body via the LiveView diff (an
 * `:order_override` assign pushed through the dispatcher), so this
 * hook's job is visual only: drop a `bw-fs-hero-fade` class on the
 * body to replay the cross-fade animation, and update the click
 * subject + `data-order-id` so the next widget-wide click goes to the
 * fresh order's share page.
 */

export const FsHeroWidget = {
  mounted() {
    this.bannerId = this.el.dataset.bannerId;

    const selectEvent = `widget:${this.bannerId}:select`;
    this.handleEvent(selectEvent, ({ order_id, order }) => {
      this._applySelection(order_id, order);
    });
  },

  updated() {
    // Re-trigger the fade if the order id changed.
    const body = this.el.querySelector('[data-role="fs-hero-body"]');
    if (!body) return;
    const orderId = this.el.dataset.orderId;
    if (this._lastFadedOrderId !== orderId) {
      this._replayFade(body);
      this._lastFadedOrderId = orderId;
    }
  },

  destroyed() {
    this._lastFadedOrderId = null;
  },

  _applySelection(orderId, _order) {
    if (!orderId) return;
    // Update the subject so the next click lands on the fresh order.
    this.el.dataset.orderId = orderId;
    this.el.setAttribute("phx-value-subject", orderId);

    const body = this.el.querySelector('[data-role="fs-hero-body"]');
    if (body) this._replayFade(body);
  },

  _replayFade(body) {
    body.classList.remove("bw-fs-hero-fade");
    void body.offsetWidth;
    body.classList.add("bw-fs-hero-fade");
  },
};
