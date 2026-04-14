/**
 * RtChartWidget — shared hook for rt_chart_landscape, rt_chart_portrait,
 * and rt_full_card.
 *
 * Initializes a TradingView lightweight-charts Area series inside a
 * `[data-role="rt-chart-canvas"]` element (rendered by the Elixir
 * component with `phx-update="ignore"` so morphdom leaves the canvas
 * alone). The Area series is re-colored green/red based on
 * `data-change-pct` at mount.
 *
 * Server → client events:
 *   · widget:rt_chart:update     { bot_id, tf, points }
 *       — fresh series for the currently displayed {bot_id, tf}
 *   · widget:<banner_id>:select  { bot_id, tf, points }
 *       — WidgetSelector picked a new subject for this banner; swap
 *         the header text + chart data without a LiveView re-render
 *
 * Client → server events:
 *   · switch_timeframe { banner_id, tf } — dispatched from a tf-pill
 *     click. Host LV can choose to handle or ignore (currently Phase 4
 *     leaves auto-selection in charge; clicks update the local UI only).
 *
 * Visual polish (price/H-L flash, "updated X ago") is intentionally
 * absent — the Phase 5+ skyscraper pattern of driving polish from the
 * `updated/0` callback doesn't apply here because the canvas subtree is
 * frozen.
 */

import { createChart, AreaSeries } from "lightweight-charts";

const GREEN = "#22C55E";
const RED = "#EF4444";
const TOP_GREEN = "rgba(34,197,94,0.22)";
const TOP_RED = "rgba(239,68,68,0.22)";
const TRANSPARENT = "rgba(0,0,0,0)";
const TEXT = "#6B7280";
const BORDER = "rgba(255,255,255,0.06)";
const GRID = "rgba(255,255,255,0.03)";

function parseChange(raw) {
  if (raw == null || raw === "") return null;
  const n = parseFloat(raw);
  return Number.isFinite(n) ? n : null;
}

function chartColors(changePct) {
  const up = changePct == null ? true : changePct >= 0;
  return {
    lineColor: up ? GREEN : RED,
    topColor: up ? TOP_GREEN : TOP_RED,
  };
}

export const RtChartWidget = {
  mounted() {
    this.canvas = this.el.querySelector('[data-role="rt-chart-canvas"]');
    this.bannerId = this.el.dataset.bannerId;
    this.botId = this.el.dataset.botId || null;
    this.tf = this.el.dataset.tf || null;
    this.changePct = parseChange(this.el.dataset.changePct);

    if (!this.canvas) {
      return;
    }

    this._initChart();
    this._wireTfPills();
    this._wireWidgetClick();

    this.handleEvent("widget:rt_chart:update", ({ bot_id, tf, points }) => {
      if (bot_id !== this.botId || tf !== this.tf) return;
      this._setData(points);
    });

    const selectEvent = `widget:${this.bannerId}:select`;
    this.handleEvent(selectEvent, ({ bot_id, tf, points }) => {
      this.botId = bot_id || this.botId;
      this.tf = tf || this.tf;
      this.el.dataset.botId = this.botId || "";
      this.el.dataset.tf = this.tf || "";
      this._setData(points);
      this._setActivePill(this.tf);
    });

    this._resizeObserver = new ResizeObserver(() => {
      if (!this.chart) return;
      const rect = this.canvas.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) {
        this.chart.applyOptions({ width: rect.width, height: rect.height });
      }
    });
    this._resizeObserver.observe(this.canvas);
  },

  destroyed() {
    if (this._resizeObserver) {
      this._resizeObserver.disconnect();
      this._resizeObserver = null;
    }
    if (this._clickHandler) {
      this.el.removeEventListener("click", this._clickHandler);
      this._clickHandler = null;
    }
    if (this.chart) {
      this.chart.remove();
      this.chart = null;
    }
    this.series = null;
  },

  _initChart() {
    const { lineColor, topColor } = chartColors(this.changePct);
    const rect = this.canvas.getBoundingClientRect();
    const width = rect.width > 0 ? rect.width : this.canvas.clientWidth || 400;
    const height = rect.height > 0 ? rect.height : this.canvas.clientHeight || 220;

    try {
      this.chart = createChart(this.canvas, {
        width,
        height,
        layout: {
          background: { type: "solid", color: "transparent" },
          textColor: TEXT,
          fontSize: 10,
          fontFamily: "JetBrains Mono, ui-monospace, monospace",
        },
        grid: {
          vertLines: { color: GRID },
          horzLines: { color: GRID },
        },
        rightPriceScale: {
          borderColor: BORDER,
          scaleMargins: { top: 0.1, bottom: 0.1 },
        },
        timeScale: {
          borderColor: BORDER,
          timeVisible: true,
          secondsVisible: false,
        },
        handleScroll: false,
        handleScale: false,
      });

      this.series = this.chart.addSeries(AreaSeries, {
        lineColor,
        topColor,
        bottomColor: TRANSPARENT,
        lineWidth: 2,
        priceLineVisible: false,
        lastValueVisible: true,
      });

      // Seed with server-rendered points if the HEEx component serialised
      // an initial set into a script tag under the canvas.
      const seedEl = this.el.querySelector('[data-role="rt-chart-seed"]');
      if (seedEl && seedEl.textContent) {
        try {
          const seed = JSON.parse(seedEl.textContent);
          if (Array.isArray(seed) && seed.length > 0) {
            this._setData(seed);
          }
        } catch (_e) {
          // ignore — seed is best-effort
        }
      }
    } catch (e) {
      console.error("[RtChartWidget] chart init failed:", e);
    }
  },

  _setData(points) {
    if (!this.series || !Array.isArray(points)) return;
    // API returns points with string keys ("time"/"value"); lightweight-charts
    // wants either string keys of `time` + `value`, which matches. Coerce
    // atom-ish payloads defensively.
    const cleaned = points
      .map((p) => {
        const time = p.time ?? p["time"];
        const value = p.value ?? p["value"];
        if (time == null || value == null) return null;
        return { time, value: Number(value) };
      })
      .filter(Boolean);
    if (cleaned.length === 0) return;

    // Adjust colors if the displayed pct changed.
    const firstVal = cleaned[0].value;
    const lastVal = cleaned[cleaned.length - 1].value;
    if (Number.isFinite(firstVal) && Number.isFinite(lastVal) && firstVal !== 0) {
      const pct = ((lastVal - firstVal) / firstVal) * 100;
      const { lineColor, topColor } = chartColors(pct);
      try {
        this.series.applyOptions({ lineColor, topColor, bottomColor: TRANSPARENT });
      } catch (_e) {
        // older lightweight-charts releases don't support applyOptions on series — ignore
      }
    }

    try {
      this.series.setData(cleaned);
      if (this.chart && this.chart.timeScale) {
        this.chart.timeScale().fitContent();
      }
    } catch (e) {
      console.error("[RtChartWidget] setData failed:", e);
    }
  },

  _wireWidgetClick() {
    // Outer widget click → push widget_click with structured subject.
    // Phoenix's phx-value-* can only carry flat strings; a {bot_id, tf}
    // map needs to go through a JS-level pushEvent.
    this._clickHandler = (e) => {
      // Ignore clicks inside the tf pills — they handle their own state
      // and will have already stopped propagation.
      if (e.defaultPrevented) return;
      const pillEl = e.target.closest('[data-role="rt-chart-tf"]');
      if (pillEl) return;
      if (!this.bannerId) return;
      this.pushEvent("widget_click", {
        banner_id: this.bannerId,
        subject: this.botId && this.tf
          ? { bot_id: this.botId, tf: this.tf }
          : "rt",
      });
    };
    this.el.addEventListener("click", this._clickHandler);
  },

  _wireTfPills() {
    const pills = this.el.querySelectorAll('[data-role="rt-chart-tf"]');
    pills.forEach((pill) => {
      pill.addEventListener("click", (e) => {
        // Stop propagation so the outer widget-click redirect doesn't fire.
        e.stopPropagation();
        e.preventDefault();
        const tf = pill.dataset.tf;
        if (!tf || tf === this.tf) return;
        this.tf = tf;
        this.el.dataset.tf = tf;
        this._setActivePill(tf);
        if (this.bannerId) {
          this.pushEvent("switch_timeframe", { banner_id: this.bannerId, tf });
        }
      });
    });
  },

  _setActivePill(tf) {
    const pills = this.el.querySelectorAll('[data-role="rt-chart-tf"]');
    pills.forEach((pill) => {
      if (pill.dataset.tf === tf) {
        pill.classList.add("rt-tf--active");
      } else {
        pill.classList.remove("rt-tf--active");
      }
    });
  },
};
