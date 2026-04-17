/**
 * CfDemoCycle — JS hook for coin flip demo widgets.
 *
 * Handles two modes:
 *   1. Landscape (.vw--land): syncs `.cf-panels-left > [data-cf-panel]`
 *      and `.cf-panels-right [data-cf-panel]` — both swap in lockstep.
 *   2. Portrait / sidebar (non-landscape): single set of panels.
 *
 * Uses `data-hidden` attribute toggle (set/removeAttribute) to show/hide
 * panels. CSS handles the visual: `[data-hidden] { display:none }` for
 * landscape, `[data-hidden] { opacity:0; position:absolute; ... }` for
 * portrait. Indicator dots use `[data-cf-dot]`.
 *
 * Duration per panel read from `data-duration` on each panel element
 * (seconds). Falls back to 17s if missing.
 */
export const CfDemoCycle = {
  mounted() {
    const cycler = this.el.querySelector('[data-cf-cycler]') || this.el;
    const isLandscape = cycler.classList.contains('vw--land');

    if (isLandscape) {
      this.leftPanels = cycler.querySelectorAll('.cf-panels-left > [data-cf-panel]');
      const rightContainer = cycler.querySelector('.cf-panels-right');
      this.rightPanels = rightContainer ? rightContainer.querySelectorAll('[data-cf-panel]') : [];
      this.panels = this.leftPanels; // use left for count/index
    } else {
      this.panels = cycler.querySelectorAll('[data-cf-panel]');
      this.leftPanels = null;
      this.rightPanels = null;
    }

    this.dots = cycler.querySelectorAll('[data-cf-dot]');
    this.isLandscape = isLandscape;

    if (!this.panels.length) return;

    // Random start index so adjacent widgets don't sync
    this.index = Math.floor(Math.random() * this.panels.length);
    this.timer = null;
    this.cycle();
  },

  show(idx) {
    if (this.isLandscape) {
      // Sync left + right panels
      this.leftPanels.forEach((p, j) => {
        if (j === idx) p.removeAttribute('data-hidden');
        else p.setAttribute('data-hidden', '');
      });
      if (this.rightPanels) {
        this.rightPanels.forEach((p, j) => {
          if (j === idx) p.removeAttribute('data-hidden');
          else p.setAttribute('data-hidden', '');
        });
      }
    } else {
      // Single panel set
      this.panels.forEach((p, j) => {
        if (j === idx) p.removeAttribute('data-hidden');
        else p.setAttribute('data-hidden', '');
      });
    }

    // Update indicator dots
    this.dots.forEach((d, j) => d.classList.toggle('cf-dot--active', j === idx));
  },

  cycle() {
    this.show(this.index);
    const panel = this.panels[this.index];
    const duration = (parseInt(panel?.dataset?.duration, 10) || 17) * 1000;
    this.timer = setTimeout(() => {
      this.index = (this.index + 1) % this.panels.length;
      this.cycle();
    }, duration);
  },

  destroyed() {
    if (this.timer) clearTimeout(this.timer);
  }
};
