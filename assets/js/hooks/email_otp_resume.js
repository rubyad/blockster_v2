/**
 * EmailOtpResume — restores the email-OTP entry modal across page loads /
 * mobile app switches.
 *
 * Mobile sign-in flow problem: user enters email, server sends OTP, user
 * switches to their email app to read the code, switches back — but the
 * LiveView socket has disconnected, mount runs fresh, modal state is lost.
 * User has to start over.
 *
 * Fix: when the OTP-entry stage opens, the LV pushes `phx:save_email_otp_state`
 * with the email; we save `{email, savedAt}` to localStorage. On any
 * subsequent page mount — AND on every visibilitychange that brings the
 * tab back to the foreground — this hook reads localStorage; if a pending
 * OTP exists and is within the 10-min server-side TTL, we push
 * `restore_email_otp_state` to the LV which re-opens the modal in
 * enter-code stage. On verify success or modal cancel the LV pushes
 * `phx:clear_email_otp_state` to wipe localStorage.
 *
 * The visibilitychange listener matters because on iOS Safari (and many
 * Android browsers) switching apps does NOT reload the tab — the LV
 * socket reconnects on visibility resume but `mounted()` already ran on
 * the first paint, so without this listener the saved state is never
 * re-checked when the user comes back from their email app.
 */

const STORAGE_KEY = "blockster:email_otp_pending";
const TTL_MS = 10 * 60 * 1000;
const OVERLAY_TIMEOUT_MS = 2_500;

export const EmailOtpResume = {
  mounted() {
    this._onVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        this.tryRestore();
      }
    };
    document.addEventListener("visibilitychange", this._onVisibilityChange);

    // Server pushes this once the restore handler has reopened the
    // modal in :enter_code stage — that's our signal that the LV is
    // back in sync, so the overlay can come down.
    this.handleEvent("email_otp_restored", () => this._hideOverlay());
    this.handleEvent("clear_email_otp_state", () => this._hideOverlay());

    this.tryRestore();
  },

  destroyed() {
    if (this._onVisibilityChange) {
      document.removeEventListener("visibilitychange", this._onVisibilityChange);
      this._onVisibilityChange = null;
    }
    if (this._retryTimerId) {
      clearTimeout(this._retryTimerId);
      this._retryTimerId = null;
    }
    this._hideOverlay();
  },

  tryRestore() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return;
      const { email, savedAt } = JSON.parse(raw);
      if (!email) {
        localStorage.removeItem(STORAGE_KEY);
        return;
      }
      if (typeof savedAt !== "number" || Date.now() - savedAt > TTL_MS) {
        localStorage.removeItem(STORAGE_KEY);
        return;
      }
      // Bridge the LV-reconnect gap: a fresh LV process renders the
      // default-assigns version of the page (modal closed) before our
      // restore_email_otp_state event lands and reopens it. The
      // overlay sits on top of everything so the user sees a calm
      // continuation instead of a "modal disappears + reappears" flash
      // when they return from their email app on iOS Safari.
      this._showOverlay();

      this._restoreCount = 0;
      this._scheduleRestore(email);
    } catch (err) {
      console.warn("[EmailOtpResume] restore failed:", err);
      try {
        localStorage.removeItem(STORAGE_KEY);
      } catch {}
    }
  },

  _scheduleRestore(email) {
    this.pushEvent("restore_email_otp_state", { email });
    this._restoreCount = (this._restoreCount || 0) + 1;
    if (this._restoreCount >= 3) return;
    if (this._retryTimerId) clearTimeout(this._retryTimerId);
    const delay = this._restoreCount === 1 ? 250 : 1000 * this._restoreCount;
    this._retryTimerId = setTimeout(() => {
      this._scheduleRestore(email);
    }, delay);
  },

  _showOverlay() {
    if (this._overlayShown) return;
    document.body.classList.add("email-otp-resuming");
    this._overlayShown = true;
    // Hard cap: if the LV restore never lands (network drop, LV
    // process gone), don't strand the user behind a frozen white
    // screen. Drop the overlay regardless after 2.5s — better to
    // briefly see the closed-modal state than a stuck loading panel.
    if (this._overlayTimeout) clearTimeout(this._overlayTimeout);
    this._overlayTimeout = setTimeout(() => {
      this._hideOverlay();
    }, OVERLAY_TIMEOUT_MS);
  },

  _hideOverlay() {
    if (!this._overlayShown) return;
    document.body.classList.remove("email-otp-resuming");
    this._overlayShown = false;
    if (this._overlayTimeout) {
      clearTimeout(this._overlayTimeout);
      this._overlayTimeout = null;
    }
  },
};
