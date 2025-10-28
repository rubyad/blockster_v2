export const TwitterWidgets = {
  mounted() {
    this.loadWidgets();
  },

  updated() {
    this.loadWidgets();
  },

  loadWidgets() {
    // Wait for Twitter widgets library to load, then process tweet embeds
    if (typeof twttr !== "undefined" && twttr.widgets) {
      console.log("Loading Twitter widgets in content...");
      twttr.widgets.load(this.el);
    } else {
      console.log("Twitter widgets not ready, retrying...");
      setTimeout(() => this.loadWidgets(), 100);
    }
  }
};
