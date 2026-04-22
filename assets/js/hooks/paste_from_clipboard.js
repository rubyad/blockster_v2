/**
 * PasteFromClipboard — reads clipboard text and writes it into a target
 * input. Used by the /wallet Send form's "Paste" button so users don't
 * need to focus the address field before pasting.
 *
 * Expects `data-target-id` on the element. The button writes the
 * clipboard contents into the input with that id and fires a `phx-change`
 * so LiveView picks it up.
 */

export const PasteFromClipboard = {
  mounted() {
    this.el.addEventListener("click", async (e) => {
      e.preventDefault();
      const targetId = this.el.dataset.targetId;
      if (!targetId) return;
      const target = document.getElementById(targetId);
      if (!target) return;

      try {
        const text = await navigator.clipboard.readText();
        if (!text) return;
        target.value = text.trim();
        target.dispatchEvent(new Event("input", { bubbles: true }));
        target.focus();
      } catch (err) {
        // Browser may deny clipboard access (http context, user refused,
        // etc). Fall back to focusing the input so the user can paste manually.
        console.warn("[PasteFromClipboard] denied:", err?.message || err);
        target.focus();
      }
    });
  },
};
