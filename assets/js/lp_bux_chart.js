import { createChart, CandlestickSeries } from 'lightweight-charts';

export const LPBuxChart = {
  mounted() {
    this.initChart();

    // Handle initial candle data from LiveView
    this.handleEvent("set_candles", ({ candles }) => {
      if (!this.candleSeries) return;

      const data = candles.map(c => ({
        time: c.time,
        open: c.open,
        high: c.high,
        low: c.low,
        close: c.close,
      }));
      this.candleSeries.setData(data);
      this.chart.timeScale().fitContent();
    });

    // Handle real-time candle updates via PubSub
    this.handleEvent("update_candle", ({ candle }) => {
      if (!this.candleSeries || !candle) return;

      this.candleSeries.update({
        time: candle.time || candle.timestamp,
        open: candle.open,
        high: candle.high,
        low: candle.low,
        close: candle.close,
      });
    });

    // Responsive resize
    this.resizeObserver = new ResizeObserver(entries => {
      if (!this.chart) return;
      const { width } = entries[0].contentRect;
      this.chart.applyOptions({ width });
    });
    this.resizeObserver.observe(this.el);
  },

  initChart() {
    this.chart = createChart(this.el, {
      width: this.el.clientWidth,
      height: 400,
      layout: {
        background: { color: '#18181b' },
        textColor: '#a1a1aa',
        fontFamily: "'Neue Haas Grotesk Display Pro 55 Roman', system-ui, sans-serif",
      },
      grid: {
        vertLines: { color: '#27272a' },
        horzLines: { color: '#27272a' },
      },
      crosshair: {
        mode: 0,
        vertLine: { color: '#52525b', labelBackgroundColor: '#3f3f46' },
        horzLine: { color: '#52525b', labelBackgroundColor: '#3f3f46' },
      },
      timeScale: {
        timeVisible: true,
        secondsVisible: false,
        borderColor: '#3f3f46',
      },
      rightPriceScale: {
        borderColor: '#3f3f46',
        scaleMargins: { top: 0.1, bottom: 0.1 },
      },
      handleScroll: { mouseWheel: true, pressedMouseMove: true },
      handleScale: { mouseWheel: true, pinch: true },
    });

    this.candleSeries = this.chart.addSeries(CandlestickSeries, {
      upColor: '#CAFC00',
      downColor: '#ef4444',
      borderUpColor: '#CAFC00',
      borderDownColor: '#ef4444',
      wickUpColor: '#CAFC00',
      wickDownColor: '#ef4444',
    });
  },

  destroyed() {
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.chart) this.chart.remove();
    this.chart = null;
    this.candleSeries = null;
  }
};
