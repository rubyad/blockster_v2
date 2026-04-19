// FateSwap C · Kinetic Hero ad driver — ported verbatim from
// /Users/tenmerry/Projects/fateswap/docs/ads/a2_combined_porting_spec.md §14.
// Converted from an IIFE targeting `#adC` into a Phoenix hook scoped to
// `this.el` so multiple instances can coexist on a single page.
export const FsKineticAd = {
  mounted() {
    const ad = this.el;
    const fate = ad.querySelector("[data-fate-c]");
    const hero = ad.querySelector("[data-hero-c]");
    const trackFill = ad.querySelector(".c-track .fill");
    const CYCLE = 13000;
    const HERO_START = 0.06 * CYCLE, HERO_END = 0.22 * CYCLE;
    const FATE_START = 0.30 * CYCLE, FATE_END = 0.50 * CYCLE;
    // FILLED overlay lifecycle (mirrors the cFilled keyframes). The bar
    // stays at its landing value (47.83%) while the overlay is on-screen,
    // then collapses back to 0 in lockstep with the overlay's exit.
    const FILL_FADE_START = 0.88 * CYCLE, FILL_FADE_END = 0.96 * CYCLE;
    const FATE_TARGET = 47.83;

    this._destroyed = false;
    const tick = (now) => {
      if (this._destroyed) return;
      const t = now % CYCLE;
      if (hero) {
        if (t < HERO_START) hero.textContent = "0";
        else if (t < HERO_END) {
          const f = (t - HERO_START) / (HERO_END - HERO_START);
          const eased = 1 - Math.pow(1 - f, 3);
          hero.textContent = Math.round(eased * 50);
        } else hero.textContent = "50";
      }
      // Fate counter + slider width share the same eased progress so they
      // move in lockstep. User's complaint was the bar lagged the counter
      // by ~2s — driving both from one RAF fixes that.
      let fateEased = 0;
      if (t < FATE_START) fateEased = 0;
      else if (t < FATE_END) {
        const f = (t - FATE_START) / (FATE_END - FATE_START);
        fateEased = 1 - Math.pow(1 - f, 2.4);
      } else fateEased = 1;

      if (fate) {
        if (t < FATE_START) fate.textContent = "00.00";
        else if (t < FATE_END) {
          const f = (t - FATE_START) / (FATE_END - FATE_START);
          const jitter = f < 0.8 ? (Math.random() * 8 - 4) * (1 - f) : 0;
          const v = Math.min(FATE_TARGET, Math.max(0, fateEased * FATE_TARGET + jitter));
          fate.textContent = v.toFixed(2);
        } else fate.textContent = FATE_TARGET.toFixed(2);
      }

      if (trackFill) {
        let width;
        if (t < FATE_START) width = 0;
        else if (t < FATE_END) width = fateEased * FATE_TARGET;
        else if (t < FILL_FADE_START) width = FATE_TARGET;
        else if (t < FILL_FADE_END) {
          const f = (t - FILL_FADE_START) / (FILL_FADE_END - FILL_FADE_START);
          width = FATE_TARGET * (1 - f);
        } else width = 0;
        trackFill.style.width = width + "%";
      }

      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);

    // Scale wrapper to container width so the 440×640 ad fits narrower slots.
    const scaleWrap = this.el.parentElement;
    const applyScale = () => {
      if (!scaleWrap) return;
      const w = scaleWrap.clientWidth;
      const scale = Math.min(1, w / 440);
      scaleWrap.style.setProperty("--fs-ad-scale", scale);
    };
    this._resizeObs = new ResizeObserver(applyScale);
    if (scaleWrap) this._resizeObs.observe(scaleWrap);
    applyScale();
  },

  destroyed() {
    this._destroyed = true;
    this._resizeObs && this._resizeObs.disconnect();
  },
};
