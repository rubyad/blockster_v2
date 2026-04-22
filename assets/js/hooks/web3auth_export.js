/**
 * Web3AuthExport — orchestrates the private-key reveal UI on /wallet.
 *
 * Security invariants (do not relax without review):
 *   1. The private key NEVER leaves the browser. No fetch, no pushEvent,
 *      no localStorage, no console.log of the key.
 *   2. The key is held in hook-local state ONLY during the 30-second
 *      reveal window. On any of: explicit hide, tab blur, page unload,
 *      navigation, or hook unmount — the cached bytes are zeroed and
 *      the DOM nodes cleared.
 *   3. The hook reads window.__signer.exportPrivateKey() which itself
 *      zeroes the underlying keypair buffer in its finally block. The
 *      strings it returns (base58, hex) still live in JS memory; we
 *      overwrite the string references when clearing but we cannot
 *      deterministically wipe strings in JS. Belt-and-suspenders: limit
 *      exposure window, do not transmit.
 *   4. The "Hover to reveal" affordance on the mono code block is a
 *      shoulder-surfing deterrent, not a security boundary.
 *
 * LiveView event contract:
 *   pushed from LV → JS:
 *     * web3auth_export_reveal     { format }
 *     * web3auth_export_set_format { format }
 *     * web3auth_export_hide       {}
 *   pushed from JS → LV:
 *     * export_reveal_error        { error }   — failure to fetch the key
 *     * export_reauth_completed    {}          — fired when reveal succeeds,
 *                                                 for audit log
 */

import { getSigner } from "./signer.js";

export const Web3AuthExport = {
  mounted() {
    this._cachedKey = null; // { base58, hex }; only live during reveal

    this.handleEvent("web3auth_export_reveal", ({ format }) =>
      this._reveal(format),
    );
    this.handleEvent("web3auth_export_set_format", ({ format }) =>
      this._switchFormat(format),
    );
    this.handleEvent("web3auth_export_hide", () => this._clear());

    // Defense-in-depth: clear on tab blur / nav away / unload
    this._onBlur = () => this._clear();
    this._onVisibility = () => {
      if (document.visibilityState === "hidden") this._clear();
    };
    this._onUnload = () => this._clear();

    window.addEventListener("blur", this._onBlur);
    document.addEventListener("visibilitychange", this._onVisibility);
    window.addEventListener("beforeunload", this._onUnload);
    window.addEventListener("pagehide", this._onUnload);
  },

  destroyed() {
    this._clear();
    window.removeEventListener("blur", this._onBlur);
    document.removeEventListener("visibilitychange", this._onVisibility);
    window.removeEventListener("beforeunload", this._onUnload);
    window.removeEventListener("pagehide", this._onUnload);
  },

  async _reveal(format) {
    try {
      const signer = getSigner();
      if (!signer) {
        this.pushEvent("export_reveal_error", {
          error: "No wallet session — please sign in again.",
        });
        return;
      }
      if (signer.source !== "web3auth") {
        this.pushEvent("export_reveal_error", {
          error:
            "Export is only available for social-login wallets. External wallets (Phantom/Solflare/Backpack) manage their own keys.",
        });
        return;
      }
      if (typeof signer.exportPrivateKey !== "function") {
        this.pushEvent("export_reveal_error", {
          error: "Your session is outdated. Refresh the page and try again.",
        });
        return;
      }

      // Fetch once; cache locally for format switching within the 30s window.
      const raw = await signer.exportPrivateKey();
      if (!raw || !raw.base58) {
        this.pushEvent("export_reveal_error", {
          error: "Key fetch failed — try hiding and re-opening.",
        });
        return;
      }

      this._cachedKey = raw;
      this._render(format || "base58");

      // Tell the LV a successful reveal happened — server logs an audit event.
      this.pushEvent("export_reauth_completed", {});
    } catch (err) {
      console.error("[Web3AuthExport] reveal failed:", err?.message || err);
      this._clear();
      this.pushEvent("export_reveal_error", {
        error: err?.message || "Unable to export key",
      });
    }
  },

  _switchFormat(format) {
    if (this._cachedKey) this._render(format);
  },

  _render(format) {
    const mono = document.getElementById("export-key-mono");
    const qr = document.getElementById("export-key-qr");

    if (format === "qr") {
      this._renderQr(qr);
      if (mono) mono.textContent = "";
    } else if (format === "hex") {
      if (mono) mono.textContent = this._cachedKey.hex;
      if (qr) qr.innerHTML = "";
    } else {
      // base58 (default — Phantom / Solflare "Import private key" format)
      if (mono) mono.textContent = this._cachedKey.base58;
      if (qr) qr.innerHTML = "";
    }

    // Wire the copy button (idempotent — replaces listener per render)
    const copyBtn = document.getElementById("copy-private-key");
    if (copyBtn) {
      copyBtn.onclick = () => this._copyToClipboard(copyBtn, format);
    }
  },

  _renderQr(container) {
    if (!container) return;
    if (!this._cachedKey) {
      container.innerHTML = "";
      return;
    }

    // Lazy-load the QR library on first use — saves ~30KB for users who
    // never hit the QR tab. qrcode-generator has no deps and is 10KB min.
    this._ensureQrLib()
      .then((qrcode) => {
        if (!this._cachedKey) return; // cleared while loading
        try {
          const qr = qrcode(0, "L"); // type 0 = auto size, L = 7% error correction
          qr.addData(this._cachedKey.base58);
          qr.make();
          // Render as SVG: tight integration, no canvas taint issues.
          container.innerHTML = qr.createSvgTag({
            cellSize: 4,
            margin: 1,
            scalable: true,
          });
          const svg = container.querySelector("svg");
          if (svg) {
            svg.setAttribute("width", "100%");
            svg.setAttribute("height", "100%");
            svg.style.color = "#141414";
          }
        } catch (e) {
          console.error("[Web3AuthExport] QR render failed:", e);
          container.innerHTML =
            '<div class="text-[10px] font-mono text-neutral-500 p-2 text-center">QR rendering unavailable — use Base58</div>';
        }
      })
      .catch(() => {
        container.innerHTML =
          '<div class="text-[10px] font-mono text-neutral-500 p-2 text-center">QR library unavailable</div>';
      });
  },

  async _ensureQrLib() {
    if (this._qrcodeLib) return this._qrcodeLib;
    // Dynamic import. If qrcode-generator is not yet installed, the rejected
    // promise falls through to the catch branch in _renderQr which shows a
    // fallback message. This lets the rest of the export flow ship before
    // we land the npm dep.
    const mod = await import("qrcode-generator");
    this._qrcodeLib = mod.default || mod;
    return this._qrcodeLib;
  },

  async _copyToClipboard(btn, format) {
    if (!this._cachedKey) return;
    const text =
      format === "hex" ? this._cachedKey.hex : this._cachedKey.base58;
    try {
      await navigator.clipboard.writeText(text);
      // Swap icons: default → check for 1.5s
      const def = btn.querySelector(".copy-icon-default");
      const ok = btn.querySelector(".copy-icon");
      if (def && ok) {
        def.classList.add("hidden");
        ok.classList.remove("hidden");
        setTimeout(() => {
          def.classList.remove("hidden");
          ok.classList.add("hidden");
        }, 1500);
      }
    } catch (e) {
      console.error("[Web3AuthExport] clipboard copy failed:", e);
    }
  },

  _clear() {
    // Wipe cache
    if (this._cachedKey) {
      // Overwrite string fields with junk so the old references can be GC'd
      this._cachedKey.base58 = "";
      this._cachedKey.hex = "";
      this._cachedKey = null;
    }

    // Clear DOM
    const mono = document.getElementById("export-key-mono");
    const qr = document.getElementById("export-key-qr");
    if (mono) mono.textContent = "";
    if (qr) qr.innerHTML = "";

    // Attempt to clear any clipboard we may have written to. This can only
    // succeed while the document has focus; it's a best-effort.
    if (
      document.hasFocus() &&
      navigator.clipboard &&
      typeof navigator.clipboard.writeText === "function"
    ) {
      navigator.clipboard.writeText("").catch(() => {});
    }
  },
};
