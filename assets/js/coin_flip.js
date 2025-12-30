// CoinFlip Hook for BUX Booster
// Handles continuous coin spinning until backend reveals result
// Listens for reveal_result event to stop spinning and show final result
export const CoinFlip = {
  mounted() {
    console.log('[CoinFlip] Hook mounted, ID:', this.el.id);
    this.currentFlipId = this.el.id;
    this.flipCompleted = false;
    this.resultRevealed = false;
    this.animationStartTime = Date.now(); // Track when continuous animation started

    // Use requestAnimationFrame to ensure DOM is fully rendered
    requestAnimationFrame(() => {
      // Find the coin element
      this.coinEl = this.el.querySelector('.coin');
      if (!this.coinEl) {
        console.error('[CoinFlip] Could not find .coin element');
        return;
      }

      console.log('[CoinFlip] Found coin element, starting continuous spin');
      // Get the result from data attribute
      this.result = this.el.dataset.result;

      // Start with continuous spinning animation
      this.coinEl.className = 'coin w-full h-full absolute animate-flip-continuous';
      this.animationStartTime = Date.now(); // Update start time after applying animation
      console.log('[CoinFlip] Applied class:', this.coinEl.className);
    });

    // Listen for reveal_result event from backend
    this.handleEvent("reveal_result", ({ flip_index, result }) => {
      console.log(`[CoinFlip] Revealing result for flip ${flip_index}: ${result}`);

      // Mark result as revealed
      this.resultRevealed = true;
      this.pendingResult = result;

      if (!this.coinEl) {
        this.coinEl = this.el.querySelector('.coin');
      }

      if (this.coinEl) {
        // Listen for the next animationiteration event (when animation completes one loop and reaches 0deg)
        const switchAnimation = () => {
          const finalAnimation = this.pendingResult === 'heads' ? 'animate-flip-heads' : 'animate-flip-tails';
          this.coinEl.className = `coin w-full h-full absolute ${finalAnimation}`;
          console.log('[CoinFlip] Switched to final animation:', finalAnimation, 'at 0deg');
          this.coinEl.removeEventListener('animationiteration', switchAnimation);
        };

        this.coinEl.addEventListener('animationiteration', switchAnimation);
        console.log('[CoinFlip] Waiting for next animation loop completion (0deg position)');
      }

      // Wait for final animation to complete (3 seconds for result to settle with gradual slowdown)
      setTimeout(() => {
        if (!this.flipCompleted && this.el.id === this.currentFlipId) {
          this.flipCompleted = true;
          this.pushEvent('flip_complete', {});
        }
      }, 3000);
    });
  },

  updated() {
    console.log('[CoinFlip] Hook updated, current ID:', this.el.id, 'previous ID:', this.currentFlipId);

    // Check if the element ID changed (meaning a new flip)
    if (this.el.id !== this.currentFlipId) {
      this.currentFlipId = this.el.id;
      this.flipCompleted = false;
      this.resultRevealed = false;

      // Use requestAnimationFrame to ensure DOM is fully rendered
      requestAnimationFrame(() => {
        // Reset coin element reference
        this.coinEl = this.el.querySelector('.coin');
        if (this.coinEl) {
          this.result = this.el.dataset.result;
          // Start with continuous spinning for new flip
          this.coinEl.className = 'coin w-full h-full absolute animate-flip-continuous';
          console.log('[CoinFlip] Updated - applied continuous spin class');
        }
      });
    }
  }
};
