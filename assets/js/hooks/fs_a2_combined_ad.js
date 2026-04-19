// FateSwap A2 Combined ad driver — ported verbatim from
// /Users/tenmerry/Projects/fateswap/docs/ads/a2_combined_porting_spec.md §5.5.
// Converted from an IIFE targeting `#adA2c` into a Phoenix hook scoped to
// `this.el` so multiple instances can coexist on a single page.
export const FsA2CombinedAd = {
  mounted() {
    const ad = this.el;
    const panels = ad.querySelectorAll(".a-panel");
    const steps = ad.querySelectorAll(".a-step");
    const toks = ad.querySelectorAll('.buy-panel[data-panel="0"] .tok2');
    const buyBtn = ad.querySelector(".a-mode .buy");
    const sellBtn = ad.querySelector(".a-mode .sell");
    const hand = ad.querySelector(".hand");
    const balEl = ad.querySelector("[data-bal]");
    const balVal = balEl && balEl.querySelector(".val");
    const pctBuy = ad.querySelector("[data-pct-a2c-buy]");
    const fateBuy = ad.querySelector("[data-fate-a2c-buy]");
    const pctSell = ad.querySelector("[data-pct-a2c-sell]");
    const fateSell = ad.querySelector("[data-fate-a2c-sell]");

    const POS = {
      buyToggle:   [105, 64],
      sellToggle:  [310, 64],
      usdc:        [48,  184],
      sliderStart: [28,  322],
      sliderEnd:   [200, 322],
      cta:         [208, 378],
      reveal:      [208, 464],
    };

    // 11 stages · FILLED panels (stages 4, 9) linger 4000 ms so the reader
    // can absorb the $ result.
    const DURS = [2000, 2600, 1800, 2600, 4000, /* toSell */ 1800, 2600, 1800, 2600, 4000, /* toBuy */ 1400];
    const TO_SELL = 5;
    const TO_BUY = 10;

    const cur = { x: POS.buyToggle[0], y: POS.buyToggle[1], s: 1 };
    const applyHand = () => {
      hand.style.transform = `translate(${cur.x}px, ${cur.y}px) scale(${cur.s})`;
    };
    const moveHand = (x, y, duration, easing) => {
      hand.style.transition = `transform ${duration}ms ${easing || "cubic-bezier(.35,0,.25,1)"}`;
      cur.x = x; cur.y = y; cur.s = 1;
      applyHand();
    };
    const clickHand = (hold) => {
      hold = hold || 130;
      hand.style.transition = `transform ${hold}ms ease-out`;
      cur.s = 0.82; applyHand();
      this._setTimeouts.push(setTimeout(() => {
        hand.style.transition = `transform ${hold}ms ease-out`;
        cur.s = 1; applyHand();
      }, hold));
    };

    const setActiveMode = (buy) => {
      buyBtn.classList.toggle("active", buy);
      sellBtn.classList.toggle("active", !buy);
    };
    const setSteps = (panelIdx) => {
      const count = panelIdx < 5 ? panelIdx + 1 : panelIdx - 4;
      steps.forEach((s, j) => s.classList.toggle("on", j < count));
    };
    const showPanel = (idx) => {
      panels.forEach((p, j) => p.classList.toggle("show", j === idx));
      setSteps(idx);
    };

    const animateTokenPick = () => {
      toks.forEach((t) => t.classList.remove("pick"));
      this._setTimeouts.push(setTimeout(() => {
        toks[0] && toks[0].classList.add("pick");
      }, 1200));
    };
    const animateNum = (el, from, to, dur, panelIdx) => {
      if (!el) return;
      el.textContent = String(from);
      const start = performance.now();
      const tick = (now) => {
        if (this._destroyed) return;
        const t = Math.min(1, ((now || performance.now()) - start) / dur);
        const eased = 1 - Math.pow(1 - t, 3);
        el.textContent = Math.round(from + (to - from) * eased);
        if (t < 1 && panels[panelIdx].classList.contains("show")) requestAnimationFrame(tick);
        else el.textContent = String(to);
      };
      tick(performance.now());
    };
    const animateCounter = (el, startVal, endVal, dur, panelIdx) => {
      if (!el) return;
      const startT = performance.now();
      const tick = (now) => {
        if (this._destroyed) return;
        const t = Math.min(1, ((now || performance.now()) - startT) / dur);
        const eased = 1 - Math.pow(1 - t, 2.4);
        const jitter = t < 0.75 ? (Math.random() * 10 - 5) * (1 - t) : 0;
        const val = Math.min(endVal, Math.max(0, startVal + (endVal - startVal) * eased + jitter));
        el.textContent = val.toFixed(2);
        if (t < 1 && panels[panelIdx].classList.contains("show")) requestAnimationFrame(tick);
        else el.textContent = endVal.toFixed(2);
      };
      tick(performance.now());
    };
    const animateBalance = (fromV, toV, dur) => {
      if (!balVal) return;
      balEl.classList.remove("popup");
      void balEl.offsetWidth;
      balEl.classList.add("popup");
      const start = performance.now();
      const tick = (now) => {
        if (this._destroyed) return;
        const t = Math.min(1, ((now || performance.now()) - start) / dur);
        const eased = 1 - Math.pow(1 - t, 2.5);
        balVal.textContent = "$" + Math.round(fromV + (toV - fromV) * eased);
        if (t < 1) requestAnimationFrame(tick);
      };
      tick(performance.now());
    };

    const choreograph = (stage) => {
      if (stage === 0) {
        if (balVal) balVal.textContent = "$50";
        this._setTimeouts.push(setTimeout(() => moveHand(POS.usdc[0], POS.usdc[1], 800), 100));
        this._setTimeouts.push(setTimeout(() => clickHand(150), 1050));
        animateTokenPick();
        this._setTimeouts.push(setTimeout(() => moveHand(POS.sliderStart[0], POS.sliderStart[1], 500), DURS[0] - 520));
      } else if (stage === 1) {
        moveHand(POS.sliderEnd[0], POS.sliderEnd[1], 1440, "cubic-bezier(.2,.7,.2,1)");
        animateNum(pctBuy, 1, 50, 1440, 1);
      } else if (stage === 2) {
        this._setTimeouts.push(setTimeout(() => moveHand(POS.cta[0], POS.cta[1], 600), 80));
        this._setTimeouts.push(setTimeout(() => clickHand(150), 800));
      } else if (stage === 3) {
        this._setTimeouts.push(setTimeout(() => moveHand(POS.reveal[0], POS.reveal[1], 600), 100));
        animateCounter(fateBuy, 2.1, 47.83, DURS[3] - 400, 3);
      } else if (stage === 4) {
        this._setTimeouts.push(setTimeout(() => animateBalance(50, 100, 700), 200));
      } else if (stage === 6) {
        moveHand(POS.sliderEnd[0], POS.sliderEnd[1], 1440, "cubic-bezier(.2,.7,.2,1)");
        animateNum(pctSell, 1, 100, 1440, 5);
      } else if (stage === 7) {
        this._setTimeouts.push(setTimeout(() => moveHand(POS.cta[0], POS.cta[1], 600), 80));
        this._setTimeouts.push(setTimeout(() => clickHand(150), 800));
      } else if (stage === 8) {
        this._setTimeouts.push(setTimeout(() => moveHand(POS.reveal[0], POS.reveal[1], 600), 100));
        animateCounter(fateSell, 1.8, 34.21, DURS[8] - 400, 7);
      } else if (stage === 9) {
        this._setTimeouts.push(setTimeout(() => animateBalance(100, 200, 700), 200));
      }
    };

    const runTransition = (toSell, duration, onDone) => {
      panels.forEach((p) => p.classList.remove("show"));
      const target = toSell ? POS.sellToggle : POS.buyToggle;
      const btn = toSell ? sellBtn : buyBtn;
      moveHand(target[0], target[1], 900);
      this._setTimeouts.push(setTimeout(() => {
        clickHand(160);
        setActiveMode(!toSell);
        btn.classList.add("pulse");
        this._setTimeouts.push(setTimeout(() => btn.classList.remove("pulse"), 550));
      }, 950));
      if (toSell) {
        this._setTimeouts.push(setTimeout(() => moveHand(POS.sliderStart[0], POS.sliderStart[1], 450), 1300));
      }
      this._setTimeouts.push(setTimeout(onDone, duration));
    };

    const runStage = (stage) => {
      if (this._destroyed) return;
      if (stage >= DURS.length) stage = 0;
      if (stage === TO_SELL)  { runTransition(true,  DURS[stage], () => runStage(stage + 1)); return; }
      if (stage === TO_BUY)   { runTransition(false, DURS[stage], () => runStage(stage + 1)); return; }

      const panelIdx = stage < TO_SELL ? stage : stage - 1;
      setActiveMode(panelIdx < 5);
      showPanel(panelIdx);
      choreograph(stage);
      this._setTimeouts.push(setTimeout(() => runStage(stage + 1), DURS[stage]));
    };

    // Scale wrapper to container width so the 440×480 ad fits narrower slots.
    const scaleWrap = this.el.parentElement;
    const applyScale = () => {
      if (!scaleWrap) return;
      const w = scaleWrap.clientWidth;
      const scale = Math.min(1, w / 440);
      scaleWrap.style.setProperty("--fs-ad-scale", scale);
    };
    this._destroyed = false;
    this._setTimeouts = [];
    this._resizeObs = new ResizeObserver(applyScale);
    if (scaleWrap) this._resizeObs.observe(scaleWrap);
    applyScale();

    applyHand();
    setActiveMode(true);
    runStage(0);
  },

  destroyed() {
    this._destroyed = true;
    (this._setTimeouts || []).forEach(clearTimeout);
    this._resizeObs && this._resizeObs.disconnect();
  },
};
