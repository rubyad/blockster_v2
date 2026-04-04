/**
 * PriceChart — LP price chart using TradingView lightweight-charts
 *
 * Renders an area chart on a dark background showing LP token price history.
 * Uses brand lime (#CAFC00) for the line with a gradient fill.
 *
 * Events from LiveView:
 * - "chart_data" { points: [{ time, value }] } → set full dataset
 * - "chart_update" { time, value } → append single point
 *
 * Events to LiveView:
 * - "request_chart_data" { timeframe } → request data for timeframe
 * - "set_chart_timeframe" { timeframe } → change timeframe
 */

import { createChart, ColorType, LineStyle, AreaSeries } from "lightweight-charts";

export const PriceChart = {
  mounted() {
    this.chart = null;
    this.series = null;
    this.resizeObserver = null;

    this.initChart();

    // Listen for data pushes from server
    this.handleEvent("chart_data", ({ points }) => {
      if (this.series && points && points.length > 0) {
        this.series.setData(points);
        this.chart.timeScale().fitContent();
      }
    });

    this.handleEvent("chart_update", (point) => {
      if (this.series && point) {
        this.series.update(point);
      }
    });

    // Request initial data
    this.pushEvent("request_chart_data", { timeframe: "24H" });
  },

  initChart() {
    const container = this.el;

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
        mode: 0, // Normal
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

    // Responsive resize
    this.resizeObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect;
        if (width > 0 && height > 0) {
          this.chart.applyOptions({ width, height });
        }
      }
    });
    this.resizeObserver.observe(container);
  },

  destroyed() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
    }
    if (this.chart) {
      this.chart.remove();
      this.chart = null;
    }
  },
};
