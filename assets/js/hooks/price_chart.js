/**
 * PriceChart — LP price chart using TradingView lightweight-charts
 *
 * Renders an area chart on a dark background showing LP token price history.
 * Uses brand lime (#CAFC00) for the line with a gradient fill.
 *
 * Events from LiveView:
 * - "chart_data" { data: [{ time, value }] } → set full dataset
 * - "chart_update" { time, value } → append single point
 *
 * Events to LiveView:
 * - "request_chart_data" {} → request data for current timeframe
 */

import { createChart, ColorType, LineStyle, AreaSeries } from "lightweight-charts";

export const PriceChart = {
  mounted() {
    this.chart = null;
    this.series = null;
    this.resizeObserver = null;
    this._resizeTimer = null;

    requestAnimationFrame(() => this._initChart());

    // Listen for bulk data pushes (timeframe change or initial load)
    this.handleEvent("chart_data", ({ data }) => {
      try {
        if (data && data.length > 0) {
          this.series.setData(data);
          this.chart.timeScale().fitContent();
          const emptyMsg = this.el.querySelector(".chart-empty-state");
          if (emptyMsg) emptyMsg.remove();
        } else {
          this.series.setData([]);
          this._showEmptyState();
        }
      } catch (e) {
        console.error("[PriceChart] setData error:", e);
      }
    });

    // Listen for incremental real-time updates
    this.handleEvent("chart_update", (point) => {
      try {
        if (point && point.time && point.value !== undefined) {
          this.series.update(point);
        }
      } catch (e) {
        console.error("[PriceChart] update error:", e);
      }
    });

    // Request initial data
    this.pushEvent("request_chart_data", {});
  },

  _initChart() {
    const container = this.el;
    const width = container.clientWidth;

    if (width === 0) {
      setTimeout(() => this._initChart(), 100);
      return;
    }

    try {
      this.chart = createChart(container, {
        layout: {
          background: { type: ColorType.Solid, color: "#111827" },
          textColor: "#9CA3AF",
          fontFamily: "system-ui, -apple-system, sans-serif",
          fontSize: 11,
        },
        grid: {
          vertLines: { color: "rgba(31, 41, 55, 0.3)" },
          horzLines: { color: "rgba(31, 41, 55, 0.3)" },
        },
        crosshair: {
          mode: 0,
          vertLine: {
            width: 1,
            color: "rgba(202, 252, 0, 0.3)",
            style: LineStyle.Dashed,
            labelBackgroundColor: "#1F2937",
          },
          horzLine: {
            width: 1,
            color: "rgba(202, 252, 0, 0.3)",
            style: LineStyle.Dashed,
            labelBackgroundColor: "#1F2937",
          },
        },
        rightPriceScale: {
          borderColor: "rgba(31, 41, 55, 0.5)",
          scaleMargins: { top: 0.15, bottom: 0.1 },
        },
        timeScale: {
          borderColor: "rgba(31, 41, 55, 0.5)",
          timeVisible: true,
          secondsVisible: false,
        },
        handleScroll: { mouseWheel: true, pressedMouseMove: true },
        handleScale: { mouseWheel: true, pinch: true },
      });

      this.series = this.chart.addSeries(AreaSeries, {
        lineColor: "#CAFC00",
        lineWidth: 2,
        topColor: "rgba(202, 252, 0, 0.28)",
        bottomColor: "rgba(202, 252, 0, 0.02)",
        crosshairMarkerBackgroundColor: "#CAFC00",
        crosshairMarkerBorderColor: "#111827",
        crosshairMarkerBorderWidth: 2,
        crosshairMarkerRadius: 4,
        priceFormat: { type: "price", precision: 6, minMove: 0.000001 },
      });
    } catch (e) {
      console.error("[PriceChart] failed to create chart:", e);
      return;
    }

    // Debounced responsive resize
    this.resizeObserver = new ResizeObserver((entries) => {
      clearTimeout(this._resizeTimer);
      this._resizeTimer = setTimeout(() => {
        const { width } = entries[0].contentRect;
        if (width > 0 && this.chart) {
          this.chart.applyOptions({ width });
        }
      }, 100);
    });
    this.resizeObserver.observe(container);

    // Set initial size
    const rect = container.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0) {
      this.chart.applyOptions({ width: rect.width, height: rect.height });
    }
  },

  _showEmptyState() {
    if (this.el.querySelector(".chart-empty-state")) return;
    const msg = document.createElement("div");
    msg.className = "chart-empty-state";
    msg.style.cssText =
      "position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:#6B7280;font-size:14px;pointer-events:none;";
    msg.textContent = "Price history will appear after first sync";
    this.el.style.position = "relative";
    this.el.appendChild(msg);
  },

  destroyed() {
    clearTimeout(this._resizeTimer);
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
    }
    if (this.chart) {
      this.chart.remove();
      this.chart = null;
    }
  },
};
