// CoinFlip Hook for BUX Booster
// Notifies server when coin flip animation completes
// The CSS animation handles the correct ending rotation based on the class
export const CoinFlip = {
  mounted() {
    this.currentFlipId = this.el.id;
    this.flipCompleted = false;
    this.startTimer();
  },

  updated() {
    // Check if the element ID changed (meaning a new flip)
    if (this.el.id !== this.currentFlipId) {
      this.currentFlipId = this.el.id;
      this.flipCompleted = false;
      this.startTimer();
    }
  },

  startTimer() {
    // The CSS animation is 3 seconds - notify server when complete
    setTimeout(() => {
      if (!this.flipCompleted && this.el.id === this.currentFlipId) {
        this.flipCompleted = true;
        this.pushEvent('flip_complete', {});
      }
    }, 3000);
  }
};
