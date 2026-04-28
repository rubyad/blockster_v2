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
 * subsequent page mount, this hook reads localStorage; if a pending OTP
 * exists and is within the 10-min server-side TTL, we push
 * `restore_email_otp_state` to the LV which re-opens the modal in
 * enter-code stage. On verify success or modal cancel the LV pushes
 * `phx:clear_email_otp_state` to wipe localStorage.
 */

const STORAGE_KEY = "blockster:email_otp_pending";
const TTL_MS = 10 * 60 * 1000;

export const EmailOtpResume = {
  mounted() {
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
      this.pushEvent("restore_email_otp_state", { email });
    } catch (err) {
      console.warn("[EmailOtpResume] restore failed:", err);
      try {
        localStorage.removeItem(STORAGE_KEY);
      } catch {}
    }
  },
};
