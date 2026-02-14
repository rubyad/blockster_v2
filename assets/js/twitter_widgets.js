export const TwitterWidgets = {
  mounted() {
    this.loaded = false;
    this.loadWidgets();
  },

  updated() {
    // Re-process any unrendered tweet blockquotes after LiveView re-renders
    const hasUnprocessedTweet = this.el.querySelector('blockquote.twitter-tweet');
    if (hasUnprocessedTweet) {
      this.loaded = false;
      this.loadWidgets();
    }
  },

  loadWidgets() {
    // Prevent multiple loads
    if (this.loaded) return;

    // Wait for Twitter widgets library to load, then process tweet embeds
    if (typeof window.twttr !== "undefined" && window.twttr.widgets) {
      // Check if there's actually a tweet to embed
      const blockquote = this.el.querySelector('blockquote.twitter-tweet');
      if (!blockquote) return;

      this.loaded = true;

      // Load widgets
      window.twttr.widgets.load(this.el).then(() => {
        // Widget loaded successfully
      }).catch((error) => {
        console.error("Error loading Twitter widgets:", error);
        this.loaded = false; // Allow retry on error
      });
    } else {
      setTimeout(() => this.loadWidgets(), 100);
    }
  }
};
