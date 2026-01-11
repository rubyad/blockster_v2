// High Rollers NFT - Copy to Clipboard Hook for Phoenix LiveView
// Handles copying text (like referral links) to clipboard

/**
 * CopyToClipboardHook - Copies text to clipboard on click
 *
 * Usage:
 *   <button phx-hook="CopyToClipboardHook"
 *           id="copy-referral-link"
 *           data-copy-text={@referral_link}>
 *     Copy Link
 *   </button>
 *
 * Or with a selector to copy from another element:
 *   <button phx-hook="CopyToClipboardHook"
 *           id="copy-address"
 *           data-copy-selector="#wallet-address">
 *     Copy
 *   </button>
 *
 * Data attributes:
 *   - data-copy-text: The text to copy (takes priority)
 *   - data-copy-selector: CSS selector for element whose text content to copy
 *
 * Events pushed TO LiveView:
 *   - copy_success: { text }
 *   - copy_error: { error }
 *
 * UI feedback:
 *   - Adds 'copied' class for 2 seconds after successful copy
 *   - Changes element text to "Copied!" temporarily (if data-show-feedback="true")
 */
const CopyToClipboardHook = {
  mounted() {
    this.originalText = this.el.textContent
    this.feedbackTimeout = null

    this.el.addEventListener('click', async (e) => {
      e.preventDefault()
      await this.copyToClipboard()
    })
  },

  destroyed() {
    if (this.feedbackTimeout) {
      clearTimeout(this.feedbackTimeout)
    }
  },

  async copyToClipboard() {
    let text = this.getTextToCopy()

    if (!text) {
      this.pushEvent("copy_error", { error: 'No text to copy' })
      return
    }

    try {
      await navigator.clipboard.writeText(text)

      console.log('[CopyToClipboardHook] Copied:', text)

      // Show feedback
      this.showCopiedFeedback()

      // Notify LiveView
      this.pushEvent("copy_success", { text })

    } catch (error) {
      console.error('[CopyToClipboardHook] Copy failed:', error)

      // Fallback for older browsers
      try {
        this.fallbackCopy(text)
        this.showCopiedFeedback()
        this.pushEvent("copy_success", { text })
      } catch (fallbackError) {
        this.pushEvent("copy_error", { error: 'Failed to copy to clipboard' })
      }
    }
  },

  getTextToCopy() {
    // Priority 1: data-copy-text attribute
    if (this.el.dataset.copyText) {
      return this.el.dataset.copyText
    }

    // Priority 2: data-copy-selector - get text from another element
    if (this.el.dataset.copySelector) {
      const targetEl = document.querySelector(this.el.dataset.copySelector)
      if (targetEl) {
        return targetEl.textContent || targetEl.value
      }
    }

    // Priority 3: Text content of the element itself (if it's an input)
    if (this.el.tagName === 'INPUT' || this.el.tagName === 'TEXTAREA') {
      return this.el.value
    }

    return null
  },

  showCopiedFeedback() {
    // Add 'copied' class for styling
    this.el.classList.add('copied')

    // Optionally change text
    if (this.el.dataset.showFeedback === 'true') {
      this.el.textContent = 'Copied!'
    }

    // Clear any existing timeout
    if (this.feedbackTimeout) {
      clearTimeout(this.feedbackTimeout)
    }

    // Reset after 2 seconds
    this.feedbackTimeout = setTimeout(() => {
      this.el.classList.remove('copied')
      if (this.el.dataset.showFeedback === 'true') {
        this.el.textContent = this.originalText
      }
    }, 2000)
  },

  fallbackCopy(text) {
    // Fallback for browsers that don't support navigator.clipboard
    const textarea = document.createElement('textarea')
    textarea.value = text
    textarea.style.position = 'fixed'
    textarea.style.left = '-9999px'
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand('copy')
    document.body.removeChild(textarea)
  }
}

export default CopyToClipboardHook
