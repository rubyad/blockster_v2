// CoinFlip Hook for Coin Flip game
// Handles continuous coin spinning until backend reveals result
// Flip 1: instant stop (result revealed immediately after bet confirmation)
// Flips 2+: smooth deceleration animation (result is already known)
export const CoinFlip = {
  mounted() {
    this.currentFlipId = this.el.id;
    this.flipCompleted = false;
    // Guard against the reveal_result handler racing ahead of this mounted()
    // callback on flips 2+. When the server fires :reveal_flip_result right
    // after :next_flip patches in the new element, the push_event can arrive
    // before our rAF runs — meaning the reveal handler sets the deceleration
    // class, and then our rAF stomps on it with animate-flip-continuous.
    this.revealHandled = false;

    requestAnimationFrame(() => {
      this.coinEl = this.el.querySelector('.coin');
      if (!this.coinEl) return;
      // Bail: reveal already ran and applied the deceleration animation.
      if (this.revealHandled) return;

      this.coinEl.classList.remove('animate-flip-heads', 'animate-flip-tails');
      this.coinEl.classList.add('animate-flip-continuous');
    });

    // Listen for reveal_result event from backend
    this.handleEvent("reveal_result", ({ flip_index, result }) => {
      this.revealHandled = true;
      if (!this.coinEl) {
        this.coinEl = this.el.querySelector('.coin');
      }
      if (!this.coinEl) return;

      if (flip_index === 0) {
        // First flip: find next 0° crossing (coin does 7 rotations in 3s cycle,
        // passes through 0° every 3000/7 ≈ 429ms — max wait ~430ms)
        const CYCLE_MS = 3000;
        const ROTATIONS = 7;
        const MS_PER_ROTATION = CYCLE_MS / ROTATIONS;
        const animations = this.coinEl.getAnimations();
        let msUntilZero = 0;

        if (animations.length > 0) {
          const elapsed = animations[0].currentTime % CYCLE_MS;
          const intoRotation = elapsed % MS_PER_ROTATION;
          msUntilZero = MS_PER_ROTATION - intoRotation;
          if (msUntilZero < 30) msUntilZero += MS_PER_ROTATION; // avoid near-zero timing
        }

        setTimeout(() => {
          if (!this.coinEl) return;
          this.coinEl.classList.remove('animate-flip-continuous', 'animate-flip-heads', 'animate-flip-tails');
          this.coinEl.style.transform = '';
          void this.coinEl.offsetWidth;
          const finalClass = result === 'heads' ? 'animate-flip-heads' : 'animate-flip-tails';
          this.coinEl.classList.add(finalClass);

          setTimeout(() => {
            if (!this.flipCompleted && this.el.id === this.currentFlipId) {
              this.flipCompleted = true;
              this.pushEvent('flip_complete', {});
            }
          }, 3000);
        }, msUntilZero);
      } else {
        // Subsequent flips: play deceleration animation directly (no continuous spin)
        this.coinEl.classList.remove('animate-flip-continuous', 'animate-flip-heads', 'animate-flip-tails');
        this.coinEl.style.transform = '';

        // Force reflow so the animation restarts cleanly
        void this.coinEl.offsetWidth;

        const finalClass = result === 'heads' ? 'animate-flip-heads' : 'animate-flip-tails';
        this.coinEl.classList.add(finalClass);

        // Signal complete when deceleration finishes (3s animation)
        setTimeout(() => {
          if (!this.flipCompleted && this.el.id === this.currentFlipId) {
            this.flipCompleted = true;
            this.pushEvent('flip_complete', {});
          }
        }, 3000);
      }
    });
  },

  updated() {
    if (this.el.id !== this.currentFlipId) {
      this.currentFlipId = this.el.id;
      this.flipCompleted = false;
      // New flip id means a new flip — reset the race guard so the next
      // reveal_result can re-apply the deceleration class cleanly.
      this.revealHandled = false;

      requestAnimationFrame(() => {
        this.coinEl = this.el.querySelector('.coin');
        if (!this.coinEl) return;
        if (this.revealHandled) return;

        this.coinEl.style.transform = '';
        this.coinEl.classList.remove('animate-flip-heads', 'animate-flip-tails');
        this.coinEl.classList.add('animate-flip-continuous');
      });
    }
  }
};
