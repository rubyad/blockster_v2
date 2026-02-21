// NotificationToast Hook
// Auto-dismisses toast notification after 5 seconds.
// Pauses timer on hover, resumes with 3 seconds on mouse leave.
export const NotificationToastHook = {
  mounted() {
    this.startTimer(5000)

    this.el.addEventListener("mouseenter", () => {
      clearTimeout(this.timer)
      // Pause the progress bar animation
      const bar = this.el.querySelector(".animate-shrink-width")
      if (bar) bar.style.animationPlayState = "paused"
    })

    this.el.addEventListener("mouseleave", () => {
      // Resume with shorter timeout
      this.startTimer(3000)
      const bar = this.el.querySelector(".animate-shrink-width")
      if (bar) {
        bar.style.animationPlayState = "running"
        bar.style.animationDuration = "3s"
      }
    })
  },

  startTimer(ms) {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.pushEvent("dismiss_toast", {})
    }, ms)
  },

  destroyed() {
    clearTimeout(this.timer)
  }
}
