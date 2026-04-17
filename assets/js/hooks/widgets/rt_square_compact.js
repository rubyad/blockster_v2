/**
 * RtSquareCompactWidget — 200 × 200 single-bot tile with a mini
 * sparkline chart.
 *
 * Uses the same TradingView lightweight-charts Area series as
 * RtChartWidget but with a compact config (no grid, no price scale,
 * no time axis) so the sparkline reads like a trending line. Seeded
 * from a `<script data-role="rt-square-seed">` blob under the canvas
 * so the first paint isn't empty.
 */

import { createChart, AreaSeries } from "lightweight-charts";

const GREEN = "#22C55E";
const RED = "#EF4444";
const TOP_GREEN = "rgba(34,197,94,0.28)";
const TOP_RED = "rgba(239,68,68,0.28)";
const TRANSPARENT = "rgba(0,0,0,0)";

function parseChange(raw) {
  if (raw == null || raw === "") return null;
  const n = parseFloat(raw);
  return Number.isFinite(n) ? n : null;
}

function colors(changePct) {
  const up = changePct == null ? true : changePct >= 0;
  return {
    lineColor: up ? GREEN : RED,
    topColor: up ? TOP_GREEN : TOP_RED,
  };
}

export const RtSquareCompactWidget = {
  mounted() {
    this.canvas = this.el.querySelector('[data-role="rt-square-canvas"]');
    this.bannerId = this.el.dataset.bannerId;
    this.botId = this.el.dataset.botId || null;
    this.tf = this.el.dataset.tf || null;
    this.changePct = parseChange(this.el.dataset.changePct);

    if (!this.canvas) {
      return;
    }

    this._initChart();
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

  _wireWidgetClick() {
    this._clickHandler = (e) => {
      if (e.defaultPrevented) return;
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

  _initChart() {
    const { lineColor, topColor } = colors(this.changePct);
    const rect = this.canvas.getBoundingClientRect();
    const width = rect.width > 0 ? rect.width : this.canvas.clientWidth || 176;
    const height = rect.height > 0 ? rect.height : this.canvas.clientHeight || 60;

    try {
      this.chart = createChart(this.canvas, {
        width,
        height,
        layout: {
          background: { type: "solid", color: "transparent" },
          textColor: "rgba(0,0,0,0)",
          fontSize: 1,
        },
        grid: {
          vertLines: { visible: false },
          horzLines: { visible: false },
        },
        rightPriceScale: { visible: false },
        leftPriceScale: { visible: false },
        timeScale: { visible: false },
        handleScroll: false,
        handleScale: false,
        crosshair: { vertLine: { visible: false }, horzLine: { visible: false } },
      });

      this.series = this.chart.addSeries(AreaSeries, {
        lineColor,
        topColor,
        bottomColor: TRANSPARENT,
        lineWidth: 2,
        priceLineVisible: false,
        lastValueVisible: false,
      });

      this.series.priceScale().applyOptions({
        scaleMargins: { top: 0.05, bottom: 0.05 },
      });

      const seedEl = this.el.querySelector('[data-role="rt-square-seed"]');
      if (seedEl && seedEl.textContent) {
        try {
          const seed = JSON.parse(seedEl.textContent);
          if (Array.isArray(seed) && seed.length > 0) {
            this._setData(seed);
          }
        } catch (_e) {
          // best-effort
        }
      }
    } catch (e) {
      console.error("[RtSquareCompactWidget] chart init failed:", e);
    }
  },

  _setData(points) {
    if (!this.series || !Array.isArray(points)) return;
    const cleaned = points
      .map((p) => {
        const time = p.time ?? p["time"];
        const value = p.value ?? p["value"];
        if (time == null || value == null) return null;
        return { time, value: Number(value) };
      })
      .filter(Boolean);
    if (cleaned.length === 0) return;

    const firstVal = cleaned[0].value;
    const lastVal = cleaned[cleaned.length - 1].value;
    if (Number.isFinite(firstVal) && Number.isFinite(lastVal) && firstVal !== 0) {
      const pct = ((lastVal - firstVal) / firstVal) * 100;
      const { lineColor, topColor } = colors(pct);
      try {
        this.series.applyOptions({ lineColor, topColor, bottomColor: TRANSPARENT });
      } catch (_e) {
        // ignore
      }
    }

    try {
      this.series.setData(cleaned);
      if (this.chart && this.chart.timeScale) {
        this.chart.timeScale().fitContent();
      }
    } catch (e) {
      console.error("[RtSquareCompactWidget] setData failed:", e);
    }
  },
};
