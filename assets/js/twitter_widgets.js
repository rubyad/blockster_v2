export const TwitterWidgets = {
  mounted() {
    console.log("TwitterWidgets hook mounted");
    this.loadWidgets();
  },

  updated() {
    console.log("TwitterWidgets hook updated");
    this.loadWidgets();
  },

  loadWidgets() {
    // Wait for Twitter widgets library to load, then process tweet embeds
    if (typeof window.twttr !== "undefined" && window.twttr.widgets) {
      console.log("Loading Twitter widgets in content...", this.el);

      // Load widgets and log the result
      window.twttr.widgets.load(this.el).then(() => {
        console.log("Twitter widgets loaded successfully");
      }).catch((error) => {
        console.error("Error loading Twitter widgets:", error);
      });
    } else {
      console.log("Twitter widgets not ready, retrying in 100ms...");
      setTimeout(() => this.loadWidgets(), 100);
    }
  }
};
