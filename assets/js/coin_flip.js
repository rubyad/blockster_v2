// CoinFlip Hook for BUX Booster
// Handles continuous coin spinning until backend reveals result
// Listens for reveal_result event to stop spinning and show final result
export const CoinFlip = {
  mounted() {
    this.currentFlipId = this.el.id;
    this.flipCompleted = false;
    this.resultRevealed = false;
    this.animationStartTime = Date.now();

    requestAnimationFrame(() => {
      this.coinEl = this.el.querySelector('.coin');
      if (!this.coinEl) return;

      const flipIndex = parseInt(this.el.dataset.flipIndex || '1');

      // First flip: continuous spin until reveal_result event
      // Subsequent flips: result comes via reveal_result event too
      this.coinEl.classList.remove('animate-flip-heads', 'animate-flip-tails');
      this.coinEl.classList.add('animate-flip-continuous');
      this.animationStartTime = Date.now();
    });

    // Listen for reveal_result event from backend (only sent after bet confirmed)
    this.handleEvent("reveal_result", ({ flip_index, result }) => {
      this.resultRevealed = true;
      this.pendingResult = result;

      if (!this.coinEl) {
        this.coinEl = this.el.querySelector('.coin');
      }

      if (this.coinEl) {
        const switchAnimation = () => {
          const finalAnimation = this.pendingResult === 'heads' ? 'animate-flip-heads' : 'animate-flip-tails';
          this.coinEl.classList.remove('animate-flip-continuous', 'animate-flip-heads', 'animate-flip-tails');
          this.coinEl.classList.add(finalAnimation);
          this.coinEl.removeEventListener('animationiteration', switchAnimation);
        };

        this.coinEl.addEventListener('animationiteration', switchAnimation);
      }

      // Wait for final animation to complete (3 seconds)
      setTimeout(() => {
        if (!this.flipCompleted && this.el.id === this.currentFlipId) {
          this.flipCompleted = true;
          this.pushEvent('flip_complete', {});
        }
      }, 3000);
    });
  },

  updated() {
    if (this.el.id !== this.currentFlipId) {
      this.currentFlipId = this.el.id;
      this.flipCompleted = false;
      this.resultRevealed = false;

      requestAnimationFrame(() => {
        this.coinEl = this.el.querySelector('.coin');
        if (this.coinEl) {
          // Always start with continuous spin — result comes via reveal_result event
          this.coinEl.classList.remove('animate-flip-heads', 'animate-flip-tails');
          this.coinEl.classList.add('animate-flip-continuous');
        }
      });
    }
  }
};
