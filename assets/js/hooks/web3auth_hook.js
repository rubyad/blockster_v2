// Web3Auth hook (Phase 5 of the social login plan).
//
// Owns Web3Auth Modal v10 on the Solana chain. Installs window.__signer on
// login, clears it on disconnect. All UI-initiated login events come from
// wallet_auth_events.ex (start_email_login / start_x_login / etc) → the
// sign-in modal sends `start_web3auth_login` to this hook with a provider key.
//
// Signing pattern (see docs/web3auth_integration.md §4): pull the derived
// ed25519 seed via provider.request({method: "solana_privateKey"}), sign
// LOCALLY with @solana/web3.js, zero the secret buffer in `finally`. Per-op
// fetch, never cached — defense in depth against XSS (CLAUDE.md mandate).
//
// Phantom-style "fee_payer must be the connected wallet" invariant does NOT
// apply here: Web3Auth users sign from an exported key, no wallet-extension
// approval layer. The settler can be fee_payer + rent_payer for true zero-SOL
// UX. The settler's tx-builder decides that based on `fee_payer_mode` param.
//
// Bundle weight: @web3auth/modal is ~7MB. We dynamic-import() on first use so
// unauthenticated pages don't pay the download cost. app.js imports ~5MB
// today; eager Web3Auth inflates to ~12.5MB (Phase 0 observation).

import bs58 from "bs58"
import { Transaction, Keypair } from "@solana/web3.js"
import nacl from "@toruslabs/tweetnacl-js"

const STORAGE_KEY = "blockster_web3auth_session"
// localStorage key: which provider the user originally signed in with
// (twitter / google / email / telegram / etc). Used on silent-reconnect
// failure to tell the server which tile to highlight when prompting the
// user to re-authenticate.
const PROVIDER_KEY = "blockster_web3auth_provider"
// sessionStorage key: survives the same-tab OAuth redirect, clears on tab close.
// Set before navigating to Web3Auth; read on return to know which provider
// button the user tapped (pushed back to LiveView as `provider`).
const REDIRECT_PROVIDER_KEY = "blockster_web3auth_redirect_provider"

function isMobileUA() {
  try {
    if (navigator.userAgentData?.mobile === true) return true
  } catch (_) {}
  const ua = (navigator.userAgent || "").toLowerCase()
  if (/mobi|android|iphone|ipad|ipod|opera mini|iemobile/.test(ua)) return true
  // iPadOS 13+ reports Mac UA in Safari (the "Request Desktop Website"
  // default). The reliable signal is touch + platform — Mac trackpads
  // never report maxTouchPoints > 1; iPad does. Without this branch the
  // popup-mode OAuth flow hangs on iPad because we incorrectly fall to
  // desktop uxMode. Confirmed on prod 2026-04-29: X login modal hung on
  // iPad until isMobileUA was strengthened.
  try {
    if (
      typeof navigator.maxTouchPoints === "number" &&
      navigator.maxTouchPoints > 1 &&
      /Mac/i.test(navigator.platform || "")
    ) {
      return true
    }
  } catch (_) {}
  return false
}

// Detect the format of `solana_privateKey` — Web3Auth has returned hex, base58,
// or base64 across versions. Length + charset disambiguates.
function hexToBytes(hex) {
  const cleaned = hex.replace(/\s+/g, "")
  const out = new Uint8Array(cleaned.length / 2)
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(cleaned.slice(i * 2, i * 2 + 2), 16)
  }
  return out
}

function decodeSecret(raw) {
  if (typeof raw !== "string") raw = String(raw)
  const stripped = raw.startsWith("0x") ? raw.slice(2) : raw
  const HEX = /^[0-9a-fA-F]+$/
  const B58 = /^[1-9A-HJ-NP-Za-km-z]+$/

  if (HEX.test(stripped) && (stripped.length === 64 || stripped.length === 128)) {
    return hexToBytes(stripped)
  }
  if (B58.test(raw)) {
    try {
      const bytes = bs58.decode(raw)
      if (bytes.length === 32 || bytes.length === 64) return bytes
    } catch (_) {}
  }
  try {
    const b64 = raw.replace(/-/g, "+").replace(/_/g, "/")
    const bin = atob(b64)
    const bytes = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
    if (bytes.length === 32 || bytes.length === 64) return bytes
  } catch (_) {}
  return null
}

export const Web3Auth = {
  async mounted() {
    this._clientId = this.el.dataset.clientId || ""
    this._rpcUrl = this.el.dataset.rpcUrl || ""
    this._chainId = this.el.dataset.chainId || "0x67" // devnet default per integration doc
    this._network = this.el.dataset.network || "SAPPHIRE_DEVNET"
    this._telegramVerifierId = this.el.dataset.telegramVerifierId || ""
    this._telegramBotUsername = this.el.dataset.telegramBotUsername || ""
    this._telegramBotId = this.el.dataset.telegramBotId || ""

    this._web3auth = null
    this._provider = null
    this._pubkey = null
    this._initPromise = null
    this._sdkModules = null
    this._telegramScriptPromise = null

    this.handleEvent("start_web3auth_login", (payload) => this._startLogin(payload))
    this.handleEvent("start_web3auth_jwt_login", (payload) => this._startJwtLogin(payload))
    this.handleEvent("start_telegram_widget", () => this._startTelegramLogin())
    this.handleEvent("request_disconnect", () => this._logout())

    // Telegram redirect-mode return: if the URL has ?telegram_login=1, we
    // just landed back from oauth.telegram.org via the mobile redirect flow.
    // Pull the JWT the server stashed in session and complete the Web3Auth
    // login. See `auth_controller.ex:telegram_callback/2` and the mobile
    // branch in `_startTelegramLogin` below.
    const telegramLoginReturn = (() => {
      try {
        const params = new URLSearchParams(window.location.search)
        return params.has("telegram_login") || params.has("telegram_login_error")
      } catch (_) {
        return false
      }
    })()

    if (telegramLoginReturn) {
      this._completeTelegramRedirectReturn().catch((e) => {
        console.warn("[Web3Auth] Telegram redirect return failed:", e?.message || e)
        this.pushEvent("web3auth_error", {
          error: friendlyWeb3AuthError(e) || "Telegram login failed",
        })
      })
    }

    // Telegram fragment-mode return — fallback for when oauth.telegram.org
    // doesn't honor `return_to` and instead drops the auth payload into the
    // URL fragment as `#tgAuthResult=<base64-json>`. This happens on iOS
    // Safari where the popup-mode postMessage transport falls back to a
    // hash-based handoff. Without this branch, the user lands back with the
    // fragment in the URL but our flow never runs and the modal stays open
    // showing "No pending Telegram login". Decode the base64 payload, POST
    // to /api/auth/telegram/verify (same HMAC-validation as the popup flow),
    // then hand the JWT to _startJwtLogin like the redirect path.
    const tgFragment = (() => {
      try {
        const hash = window.location.hash || ""
        if (!hash.startsWith("#tgAuthResult=")) return null
        const b64 = hash.slice("#tgAuthResult=".length)
        // Strip the fragment immediately so a refresh / back-nav doesn't replay.
        try {
          const url = new URL(window.location.href)
          url.hash = ""
          window.history.replaceState({}, "", url.toString())
        } catch (_) {}
        return b64
      } catch (_) {
        return null
      }
    })()

    if (tgFragment) {
      this._completeTelegramFragmentReturn(tgFragment).catch((e) => {
        console.warn("[Web3Auth] Telegram fragment return failed:", e?.message || e)
        this.pushEvent("web3auth_error", {
          error: friendlyWeb3AuthError(e) || "Telegram login failed",
        })
      })
    }

    // Redirect-mode return: if we stashed a provider in sessionStorage
    // before navigating to the OAuth window, we're landing back here after
    // Web3Auth finished the login and navigated back. Complete the flow.
    const pendingRedirectProvider = (() => {
      try {
        const v = sessionStorage.getItem(REDIRECT_PROVIDER_KEY)
        if (v) sessionStorage.removeItem(REDIRECT_PROVIDER_KEY)
        return v
      } catch (_) {
        return null
      }
    })()

    // Auto-reconnect if the last session flagged "logged in"
    const hadSession = (() => {
      try {
        return localStorage.getItem(STORAGE_KEY) === "1"
      } catch (_) {
        return false
      }
    })()

    if (pendingRedirectProvider && this._clientId) {
      // Tell the LV to show the modal in connecting state IMMEDIATELY,
      // before we await Web3Auth init/settle (which can take up to 8s on
      // mobile). Without this, the user sees no modal during the resume
      // window — looking like the login "disappeared" — and only sees it
      // again when MPC completes or errors. UX symptom on iPad X login:
      // "modal appears, disappears, appears" — the disappearance was the
      // resume window with no modal showing.
      this.pushEvent("web3auth_resume_in_progress", {
        provider: pendingRedirectProvider,
      })

      // Redirect return takes precedence over silent reconnect — this is
      // the post-OAuth path where we need to mint a server session cookie.
      this._completeRedirectReturn(pendingRedirectProvider).catch((e) => {
        console.warn("[Web3Auth] redirect return failed:", e?.message || e)
        this.pushEvent("web3auth_error", { error: friendlyWeb3AuthError(e) })
      })
    } else if (hadSession && this._clientId) {
      // Silent init — if the session rehydrates, install the signer but do
      // NOT push wallet_authenticated (the user already has a session cookie).
      //
      // Wrapped in a 3s Promise.race timeout. Without it, `_waitForConnectorSettle`
      // inside silent-reconnect can stall indefinitely on a stuck Web3Auth state
      // machine — and because `mounted()` runs on EVERY LV reconnect (not just
      // first page load), an unstable LV socket stacks up overlapping reconnect
      // promises that wedge the hook. The timeout guarantees `.finally()` fires
      // and the Reconnect pill becomes available within a bounded window. The
      // background reconnect promise may still resolve later and install the
      // signer; that's a benign no-op if the user has already moved on.
      const SILENT_RECONNECT_TIMEOUT_MS = 3000
      const reconnectTimeout = new Promise((_, reject) =>
        setTimeout(
          () => reject(new Error("silent reconnect timed out")),
          SILENT_RECONNECT_TIMEOUT_MS,
        ),
      )
      Promise.race([this._silentReconnect(), reconnectTimeout])
        .catch((e) => {
          console.warn("[Web3Auth] silent reconnect failed:", e?.message || e)
        })
        .finally(() => {
          // If neither the fast path nor the slow path produced a signer,
          // the user's Web3Auth session has aged out. We can't silently
          // re-derive the wallet (OAuth users have their MPC wallet keyed
          // to the OAuth provider, which requires a fresh popup). Notify
          // LiveView so it can render the Reconnect pill.
          if (!window.__signer) {
            let provider = null
            try { provider = localStorage.getItem(PROVIDER_KEY) } catch (_) {}
            this.pushEvent("web3auth_reauth_required", { provider: provider || "" })
          }
        })
    }
  },

  destroyed() {
    this._web3auth = null
    this._provider = null
  },

  // ── SDK loading (lazy) ────────────────────────────────────────

  async _ensureSdk() {
    if (this._sdkModules) return this._sdkModules
    const [modal, auth] = await Promise.all([
      import("@web3auth/modal"),
      import("@web3auth/auth"),
    ])
    this._sdkModules = {
      Web3AuthCtor: modal.Web3Auth,
      WALLET_CONNECTORS: modal.WALLET_CONNECTORS,
      WEB3AUTH_NETWORK: modal.WEB3AUTH_NETWORK,
      AUTH_CONNECTION: auth.AUTH_CONNECTION,
    }
    return this._sdkModules
  },

  async _ensureInit() {
    if (this._initPromise) return this._initPromise
    this._initPromise = (async () => {
      if (!this._clientId) {
        throw new Error("WEB3AUTH_CLIENT_ID not configured")
      }
      if (!this._rpcUrl) {
        // Web3Auth.init() does `new URL(rpcTarget)` — empty throws "Invalid URL".
        // Surface the real reason early instead of letting it propagate from
        // deep inside the SDK.
        throw new Error("SOLANA_RPC_URL not configured — set it in .env or fly secrets")
      }
      const { Web3AuthCtor, WEB3AUTH_NETWORK } = await this._ensureSdk()
      const networkKey = this._network in WEB3AUTH_NETWORK
        ? WEB3AUTH_NETWORK[this._network]
        : WEB3AUTH_NETWORK.SAPPHIRE_DEVNET

      // Mobile browsers (iOS Safari, Android Chrome, in-app webviews) can't
      // reliably hold an OAuth popup open: iOS throttles background tabs and
      // closes them, in-app browsers block popups entirely, and the async
      // `await` gap between user tap and `window.open` severs the user
      // gesture chain. Switch to redirect mode on mobile — the SDK does a
      // full-page navigation to auth.web3auth.io instead of a popup, and we
      // rehydrate on return via `_completeRedirectReturn`.
      const uxMode = isMobileUA() ? "redirect" : "popup"

      this._web3auth = new Web3AuthCtor({
        clientId: this._clientId,
        web3AuthNetwork: networkKey,
        storageType: "local",
        uiConfig: { uxMode },
        chains: [
          {
            chainNamespace: "solana",
            chainId: this._chainId,
            rpcTarget: this._rpcUrl,
            displayName: this._chainId === "0x65" ? "Solana Mainnet" : "Solana Devnet",
            blockExplorerUrl:
              this._chainId === "0x65"
                ? "https://explorer.solana.com/"
                : "https://explorer.solana.com/?cluster=devnet",
            ticker: "SOL",
            tickerName: "Solana",
            logo: "https://ik.imagekit.io/blockster/blockster-icon.png",
          },
        ],
        defaultChainId: this._chainId,
      })

      await this._web3auth.init()
    })()
    return this._initPromise
  },

  // ── Login ────────────────────────────────────────────────────

  async _startLogin({ provider, email_hint }) {
    // 60s overall timeout — same defense as _startJwtLogin. On iOS Safari
    // an OAuth popup can be blocked OR the redirect-mode navigation might
    // never fire if the SDK is in a stuck state, leaving the user staring
    // at "Opening X" forever.
    const LOGIN_TIMEOUT_MS = 60_000
    let timeoutId
    const timeoutPromise = new Promise((_, reject) => {
      timeoutId = setTimeout(() => {
        reject(new Error(
          "Sign-in did not complete within 60 seconds. " +
            "Try Safari directly (not an in-app browser) or a different login method."
        ))
      }, LOGIN_TIMEOUT_MS)
    })

    try {
      await Promise.race([
        this._doLogin({ provider, email_hint }),
        timeoutPromise,
      ])
    } catch (e) {
      try { sessionStorage.removeItem(REDIRECT_PROVIDER_KEY) } catch (_) {}
      console.error("[Web3Auth] login failed", e)
      this.pushEvent("web3auth_error", { error: friendlyWeb3AuthError(e) })
    } finally {
      if (timeoutId) clearTimeout(timeoutId)
    }
  },

  async _doLogin({ provider, email_hint }) {
    await this._ensureInit()
    const { WALLET_CONNECTORS, AUTH_CONNECTION } = this._sdkModules

    // Stale session → clear before re-connecting
    if (this._web3auth.connected) {
      try { await this._web3auth.logout() } catch (_) {}
      await this._waitForConnectorSettle(2000)
    }

    const loginParams = await this._loginParamsFor(provider, email_hint, AUTH_CONNECTION)
    if (!loginParams) return

    // Mobile redirect flow: the SDK will navigate the whole page to
    // auth.web3auth.io and never return control to this promise. Stash
    // the provider so `mounted` can finish the login on return. Set
    // uxMode + redirectUrl per-call to force redirect mode (constructor
    // uxMode is unreliable for some flows in @web3auth/no-modal v10 —
    // see the matching note in _doJwtLogin).
    if (isMobileUA()) {
      try { sessionStorage.setItem(REDIRECT_PROVIDER_KEY, provider) } catch (_) {}
      loginParams.uxMode = "redirect"
      loginParams.redirectUrl = window.location.origin + "/"
    }

    // Web3Auth.init() resolves BEFORE its internal connector rehydrate
    // finishes — the connect runs inside a fire-and-forget event listener
    // for CONNECTORS_UPDATED. Calling connectTo before the state machine
    // settles throws "Wallet connector is not ready yet". _connectWithRetry
    // waits for settle + retries the retriable transient states.
    this._provider = await this._connectWithRetry(
      WALLET_CONNECTORS.AUTH,
      loginParams,
    )
    if (!this._provider) {
      // In redirect mode, connectTo returns null on its way out — the
      // browser is already navigating. Don't surface that as an error.
      if (isMobileUA()) return
      throw new Error("connectTo returned null")
    }

    await this._completeLogin(provider)
  },

  // Called from `mounted` when we detect a pending redirect return
  // (sessionStorage hint set before the OAuth navigation). The SDK's
  // `init()` auto-connects when it finds an OAuth callback `sessionId`
  // under `uxMode: "redirect"`, so after settle we just need to derive
  // the keypair and push the authenticated event to mint a server cookie.
  async _completeRedirectReturn(provider) {
    try {
      await this._ensureInit()
      const { status } = await this._waitForConnectorSettle(8000)

      if (status === "connected" && this._web3auth.connected && this._web3auth.provider) {
        this._provider = this._web3auth.provider
        await this._completeLogin(provider)
      } else {
        this.pushEvent("web3auth_error", {
          error: "Sign-in did not complete after redirect. Please try again.",
        })
      }
    } catch (e) {
      console.error("[Web3Auth] redirect-return completion failed", e)
      this.pushEvent("web3auth_error", { error: friendlyWeb3AuthError(e) })
    }
  },

  // Telegram redirect-mode return — runs from `mounted()` when the URL has
  // `?telegram_login=1`. The server placed the Custom JWT directly in the
  // URL fragment (`#tg_jwt=<base64>`) so we don't need a session cookie,
  // a Mnesia stash, or a fetch round-trip. Fragments are never sent to
  // servers, so this is privacy-equivalent to the previous session stash.
  // ?telegram_login_error=<code> takes the same path but surfaces the code
  // as an error to the LV instead.
  async _completeTelegramRedirectReturn() {
    // Read params + fragment BEFORE stripping the URL.
    const errorParam = (() => {
      try {
        return new URLSearchParams(window.location.search).get(
          "telegram_login_error",
        )
      } catch (_) {
        return null
      }
    })()

    const fragmentJwt = (() => {
      try {
        const hash = window.location.hash || ""
        const match = hash.match(/#tg_jwt=([A-Za-z0-9_-]+)/)
        if (!match) return null
        // Decode base64-url back to the JWT string.
        let b64 = match[1].replace(/-/g, "+").replace(/_/g, "/")
        while (b64.length % 4) b64 += "="
        return atob(b64)
      } catch (_) {
        return null
      }
    })()

    // Strip URL flag + fragment so a refresh doesn't replay.
    try {
      const url = new URL(window.location.href)
      url.searchParams.delete("telegram_login")
      url.searchParams.delete("telegram_login_error")
      url.hash = ""
      window.history.replaceState({}, "", url.toString())
    } catch (_) {}

    if (errorParam) {
      this.pushEvent("web3auth_error", {
        error: `Telegram login failed: ${errorParam}`,
      })
      return
    }

    if (!fragmentJwt) {
      // Fallback path — older deploys may still use the session-stashed JWT.
      // Try the legacy pending_jwt endpoint once before giving up.
      try {
        const res = await fetch("/api/auth/telegram/pending_jwt", {
          method: "GET",
          credentials: "same-origin",
        })
        const json = await res.json().catch(() => ({}))
        if (res.ok && json?.success && json?.id_token) {
          await this._startJwtLogin({
            provider: "telegram",
            id_token: json.id_token,
            verifier_id: this._telegramVerifierId,
            verifier_id_field: "sub",
          })
          return
        }
      } catch (_) {}

      this.pushEvent("web3auth_error", {
        error: "Telegram login state was not found",
      })
      return
    }

    await this._startJwtLogin({
      provider: "telegram",
      id_token: fragmentJwt,
      verifier_id: this._telegramVerifierId,
      verifier_id_field: "sub",
    })
  },

  // Telegram fragment-mode return — see `mounted()` for why this exists.
  // The fragment payload is base64-encoded JSON of the same shape the
  // Telegram Login Widget would push via postMessage:
  //   { id, first_name, username, photo_url, auth_date, hash }
  // We POST that to /api/auth/telegram/verify which HMAC-validates and
  // returns a Custom JWT, then hand to _startJwtLogin.
  async _completeTelegramFragmentReturn(b64) {
    let payload
    try {
      // base64 in fragments is sometimes URL-safe, sometimes not — try both.
      let decoded
      try {
        decoded = atob(b64)
      } catch (_) {
        decoded = atob(b64.replace(/-/g, "+").replace(/_/g, "/"))
      }
      payload = JSON.parse(decoded)
    } catch (e) {
      this.pushEvent("web3auth_error", {
        error: "Telegram returned malformed auth payload (fragment).",
      })
      return
    }

    if (!payload || !payload.id || !payload.hash) {
      this.pushEvent("web3auth_error", {
        error: "Telegram auth payload missing required fields.",
      })
      return
    }

    const csrf =
      document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""

    const res = await fetch("/api/auth/telegram/verify", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "content-type": "application/json",
        "x-csrf-token": csrf,
      },
      body: JSON.stringify(payload),
    })

    const json = await res.json().catch(() => ({}))
    if (!res.ok || !json?.success || !json?.id_token) {
      this.pushEvent("web3auth_error", {
        error: json?.error || "Telegram verify failed",
      })
      return
    }

    await this._startJwtLogin({
      provider: "telegram",
      id_token: json.id_token,
      verifier_id: this._telegramVerifierId,
      verifier_id_field: "sub",
    })
  },

  async _loginParamsFor(provider, emailHint, AUTH_CONNECTION) {
    switch (provider) {
      case "email":
        // DEPRECATED path — kept in case the server ever falls back to
        // Web3Auth's own passwordless flow. Production email sign-in goes
        // through `_startJwtLogin` via the CUSTOM JWT connector so the user
        // never leaves the Blockster modal (no captcha popup, no hidden
        // code-entry window behind the main tab).
        if (!emailHint) {
          this.pushEvent("web3auth_error", { error: "Email required" })
          return null
        }
        return {
          authConnection: AUTH_CONNECTION.EMAIL_PASSWORDLESS,
          extraLoginOptions: { login_hint: emailHint },
        }
      case "google":
        return { authConnection: AUTH_CONNECTION.GOOGLE }
      case "twitter":
        return { authConnection: AUTH_CONNECTION.TWITTER }
      case "telegram": {
        // Custom JWT flow — requires a Telegram widget payload the server
        // signed into a Blockster JWT. The modal's Telegram button fires a
        // separate event chain that ends with `start_web3auth_login` when
        // the JWT is ready. This branch only runs when we already have one.
        return null
      }
      default:
        this.pushEvent("web3auth_error", { error: `Unknown provider: ${provider}` })
        return null
    }
  },

  // Custom JWT login — used by the in-app email OTP flow + Telegram redirect
  // flow. The server has already validated the user's identity (OTP or bot
  // callback) and signed a JWT; we just hand it to Web3Auth's CUSTOM
  // connector which derives the MPC wallet deterministically from the JWT
  // `sub` + verifier id. No Web3Auth popup ceremony, no captcha.
  //
  // Mobile note: when the Web3Auth instance is constructed with
  // `uxMode: "redirect"` (always on mobile, see `_ensureInit`), `connectTo`
  // navigates the page to auth.web3auth.io for the MPC handshake even for
  // CUSTOM JWT flows — it doesn't `await` resolve in-page. We MUST set
  // `REDIRECT_PROVIDER_KEY` in sessionStorage before that nav so `mounted()`
  // on return knows to call `_completeRedirectReturn` and resume.
  // Without this, email-OTP / Telegram users on mobile complete the JWT
  // step server-side, click submit, the page navigates to web3auth.io,
  // navigates back, and the modal hangs because no resume handler ran.
  async _startJwtLogin({ provider, id_token, verifier_id, verifier_id_field }) {
    // 60s overall timeout: Web3Auth's CUSTOM JWT flow does in-page iframe
    // MPC regardless of uxMode (uxMode only governs OAuth login redirect).
    // On iOS Safari with ITP, the cross-origin iframe gets storage-blocked
    // and MPC hangs SILENTLY — connectTo never resolves and the user sits
    // on the "signing you in" modal forever. The timeout bounds that hang
    // and surfaces an error so the modal closes and the user can retry.
    const JWT_LOGIN_TIMEOUT_MS = 60_000
    let timeoutId
    const timeoutPromise = new Promise((_, reject) => {
      timeoutId = setTimeout(() => {
        reject(new Error(
          "Sign-in did not complete within 60 seconds. " +
            "This typically means your browser blocked the secure key " +
            "derivation. Try Safari (not an in-app browser) or a different " +
            "login method."
        ))
      }, JWT_LOGIN_TIMEOUT_MS)
    })

    try {
      await Promise.race([
        this._doJwtLogin({ provider, id_token, verifier_id, verifier_id_field }),
        timeoutPromise,
      ])
    } catch (e) {
      console.error("[Web3Auth] jwt login failed", e)
      try { sessionStorage.removeItem(REDIRECT_PROVIDER_KEY) } catch (_) {}
      this.pushEvent("web3auth_error", { error: friendlyWeb3AuthError(e) })
    } finally {
      if (timeoutId) clearTimeout(timeoutId)
    }
  },

  async _doJwtLogin({ provider, id_token, verifier_id, verifier_id_field }) {
    await this._ensureInit()
    const { WALLET_CONNECTORS, AUTH_CONNECTION } = this._sdkModules

    if (this._web3auth.connected) {
      try { await this._web3auth.logout() } catch (_) {}
      await this._waitForConnectorSettle(2000)
    }

    const loginParams = {
      authConnection: AUTH_CONNECTION.CUSTOM,
      authConnectionId: verifier_id || "blockster-email",
      extraLoginOptions: {
        id_token,
        verifierIdField: verifier_id_field || "sub",
      },
    }

    // Force the redirect flow PER-CALL on mobile. The constructor's
    // `uiConfig.uxMode` is meant to govern this but the CUSTOM JWT path
    // in @web3auth/no-modal v10 sometimes still does in-page iframe MPC
    // — which iOS Safari ITP blocks, leaving connectTo to hang forever
    // (60s timeout fires with the "browser blocked secure key derivation"
    // message). Setting uxMode + redirectUrl directly in LoginParams
    // forces the SDK to navigate the WHOLE page to web3auth.io for the
    // MPC ceremony (no iframe → no ITP block) and then redirect back.
    if (isMobileUA()) {
      try { sessionStorage.setItem(REDIRECT_PROVIDER_KEY, provider) } catch (_) {}
      loginParams.uxMode = "redirect"
      loginParams.redirectUrl = window.location.origin + "/"
    }

    this._provider = await this._connectWithRetry(
      WALLET_CONNECTORS.AUTH,
      loginParams,
    )
    if (!this._provider) {
      // In redirect mode, connectTo returns null on its way out — the
      // browser is already navigating. Don't surface that as an error;
      // the resume happens via _completeRedirectReturn on return.
      if (isMobileUA()) return
      throw new Error("connectTo returned null")
    }

    // connectTo resolved without redirecting (in-page MPC iframe path
    // — possible on desktop, or some mobile browsers that don't navigate).
    // Clear the redirect marker so a future page mount doesn't try to
    // resume a flow that already completed in this tab.
    try { sessionStorage.removeItem(REDIRECT_PROVIDER_KEY) } catch (_) {}

    await this._completeLogin(provider)
  },

  // Telegram social login — three-step flow:
  //   (1) Load Telegram's login widget script + open the popup via
  //       Telegram.Login.auth(...). User approves in their Telegram client.
  //   (2) POST the widget payload to /api/auth/telegram/verify which
  //       HMAC-validates it with our bot token and signs a Blockster RS256
  //       JWT (verifier `blockster-telegram`, sub = telegram user id).
  //   (3) Hand the JWT to Web3Auth's CUSTOM connector via _startJwtLogin.
  //       MPC derives the user's Solana pubkey from {sub, verifier}.
  //
  // Prereq: BotFather `/setdomain blockster.com` (and the dev tunnel
  // hostname for staging) — Telegram refuses to render the widget for
  // origins not registered against the bot.
  async _startTelegramLogin() {
    try {
      if (!this._telegramBotId) {
        this.pushEvent("web3auth_error", {
          error:
            "Telegram bot not configured (BLOCKSTER_V2_BOT_TOKEN missing or malformed)",
        })
        return
      }
      if (!this._telegramVerifierId) {
        this.pushEvent("web3auth_error", {
          error: "WEB3AUTH_TELEGRAM_VERIFIER_ID is not set",
        })
        return
      }

      // Mobile path: redirect-based flow. iOS Safari + many Android in-app
      // browsers block popups OR open them as a separate tab where
      // postMessage can't reach the parent — so the popup-based
      // Telegram.Login.auth() callback never fires and the user can't
      // dismiss the stuck Telegram window. The redirect flow navigates
      // the whole page to oauth.telegram.org, the user approves in their
      // installed Telegram app, then Telegram redirects back to our
      // /api/auth/telegram/callback which stashes the JWT in session and
      // bounces to /?telegram_login=1. Mounted() above detects the
      // return-flag and calls _completeTelegramRedirectReturn to finish
      // the login.
      if (isMobileUA()) {
        const origin = window.location.origin
        const returnTo = `${origin}/api/auth/telegram/callback`
        const url =
          `https://oauth.telegram.org/auth?bot_id=${encodeURIComponent(this._telegramBotId)}` +
          `&origin=${encodeURIComponent(origin)}` +
          `&request_access=write` +
          `&return_to=${encodeURIComponent(returnTo)}`
        window.location.href = url
        return
      }

      await this._ensureTelegramScript()

      // Telegram.Login.auth opens a popup window pointed at oauth.telegram.org.
      // It returns a payload (id, first_name, username, photo_url, auth_date,
      // hash) on success or `false` if the user cancels / the popup is blocked.
      //
      // Mobile gotcha: iOS Safari + many Android in-app browsers block the
      // popup (or open it in a separate tab where parent.postMessage never
      // reaches us). Without a timeout, the Promise below hangs forever and
      // the user has no way to dismiss the stuck Telegram window — page
      // refresh is the only recovery. 60s timeout below at least frees the
      // LV state so the user can retry or pick a different method. Proper
      // fix needs Telegram's redirect-mode flow (data-auth-url widget +
      // server callback endpoint) — see TODO in this hook + memory file
      // `project_telegram_mobile_redirect.md` (when filed).
      const TELEGRAM_AUTH_TIMEOUT_MS = 60_000
      const data = await new Promise((resolve) => {
        const timeoutId = setTimeout(() => {
          console.warn("[Web3Auth] Telegram.Login.auth timed out (mobile popup blocked?)")
          resolve(null)
        }, TELEGRAM_AUTH_TIMEOUT_MS)

        try {
          window.Telegram.Login.auth(
            { bot_id: this._telegramBotId, request_access: "write" },
            (payload) => {
              clearTimeout(timeoutId)
              resolve(payload || null)
            },
          )
        } catch (e) {
          clearTimeout(timeoutId)
          console.error("[Web3Auth] Telegram.Login.auth threw:", e)
          resolve(null)
        }
      })

      if (!data) {
        this.pushEvent("web3auth_error", {
          error: "Telegram login was cancelled or the popup was blocked",
        })
        return
      }

      // POST to our verify endpoint. CSRF token comes from the meta tag
      // Phoenix ships in root.html.heex.
      const csrf =
        document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""

      const res = await fetch("/api/auth/telegram/verify", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": csrf,
        },
        body: JSON.stringify(data),
      })

      const json = await res.json().catch(() => ({}))

      if (!res.ok || !json?.success || !json?.id_token) {
        this.pushEvent("web3auth_error", {
          error: json?.error || "Telegram verify failed",
        })
        return
      }

      // Hand off to the same Custom JWT path the email OTP flow uses.
      await this._startJwtLogin({
        provider: "telegram",
        id_token: json.id_token,
        verifier_id: this._telegramVerifierId,
        verifier_id_field: "sub",
      })
    } catch (e) {
      console.error("[Web3Auth] Telegram login failed", e)
      this.pushEvent("web3auth_error", { error: friendlyWeb3AuthError(e) })
    }
  },

  // Lazy-load Telegram's widget script. Cached as a promise so concurrent
  // _startTelegramLogin calls share the same load. Idempotent across the
  // lifetime of the page (script tag, once loaded, stays).
  _ensureTelegramScript() {
    if (this._telegramScriptPromise) return this._telegramScriptPromise
    if (window.Telegram && window.Telegram.Login) {
      this._telegramScriptPromise = Promise.resolve()
      return this._telegramScriptPromise
    }

    this._telegramScriptPromise = new Promise((resolve, reject) => {
      const existing = document.querySelector(
        'script[src^="https://telegram.org/js/telegram-widget"]',
      )
      if (existing) {
        if (window.Telegram && window.Telegram.Login) return resolve()
        existing.addEventListener("load", () => resolve(), { once: true })
        existing.addEventListener("error", () => reject(new Error("Telegram widget script failed to load")), { once: true })
        return
      }

      const script = document.createElement("script")
      script.src = "https://telegram.org/js/telegram-widget.js?22"
      script.async = true
      script.onload = () => resolve()
      script.onerror = () => reject(new Error("Telegram widget script failed to load"))
      document.head.appendChild(script)
    })

    return this._telegramScriptPromise
  },

  async _completeLogin(provider) {
    // Derive pubkey + read userInfo (ID token, claims).
    const kp = await this._fetchKeypair()
    if (!kp) return
    this._pubkey = kp.publicKey.toBase58()
    kp.secretKey.fill(0)

    // userInfo is flaky on Solana-only sessions (Web3Auth polls an EVM
    // controller internally). Wrap in try/catch — idToken still comes back.
    let info = {}
    try {
      info = await this._web3auth.getUserInfo()
    } catch (e) {
      console.warn("[Web3Auth] getUserInfo failed (benign):", e?.message || e)
    }

    const idToken = info?.idToken || ""
    if (!idToken) {
      this.pushEvent("web3auth_error", { error: "Missing idToken in userInfo" })
      return
    }

    // Install the signer BEFORE pushing authenticated event — the server's
    // wallet_authenticated handler may immediately try to place a bet.
    this._installSigner()

    try {
      localStorage.setItem(STORAGE_KEY, "1")
      if (provider) localStorage.setItem(PROVIDER_KEY, provider)
    } catch (_) {}

    this.pushEvent("web3auth_authenticated", {
      provider: provider,
      wallet_address: this._pubkey,
      id_token: idToken,
      verifier: info?.verifier || "",
      auth_connection: info?.authConnection || "",
      email: info?.email || null,
      name: info?.name || null,
      profile_image: info?.profileImage || null,
      user_id: info?.userId || null,
    })
  },

  async _silentReconnect() {
    await this._ensureInit()

    // Wait for the AuthConnector to exit its transient `connecting` /
    // `disconnecting` / `not_ready` states. Top-level Web3Auth.init()
    // resolves before its internal rehydrate-connect finishes — the
    // connect runs inside a fire-and-forget `CONNECTORS_UPDATED` event
    // listener. Calling connectTo while that's still in flight raises
    // "Already connecting".
    const { status } = await this._waitForConnectorSettle()

    // `connected` — rehydrate succeeded. Try the fast path, but verify the
    // provider actually has `solana_privateKey` registered. CUSTOM JWT
    // rehydration via init produces a skeleton ws-embed provider where
    // that method isn't wired up (it's only registered during the full
    // connectTo MPC handshake). We can't distinguish from state alone.
    if (status === "connected" && this._web3auth.connected && this._web3auth.provider) {
      this._provider = this._web3auth.provider
      const kp = await this._fetchKeypairSilent()
      if (kp) {
        this._pubkey = kp.publicKey.toBase58()
        kp.secretKey.fill(0)
        this._installSigner()
        return
      }
      // Rehydrated provider is a skeleton — logout to flip status back to
      // READY, then fall through to the slow path.
      this._provider = null
      try { await this._web3auth.logout() } catch (_) {}
      await this._waitForConnectorSettle(2000)
    }

    // Slow path — ask our server to issue a fresh JWT for the current
    // signed-in user (session cookie is the proof of identity), then hand
    // it to Web3Auth's CUSTOM connector. The full `connectTo` handshake
    // registers `solana_privateKey` on the provider; MPC derives the SAME
    // pubkey as the original login because (verifier_id, sub) is unchanged.
    await this._refreshViaServerJwt()
  },

  // Like `_fetchKeypair` but suppresses the `web3auth_error` push on
  // "Method not found" — that error is expected for the rehydrated-but-
  // incomplete provider, and the caller handles it by falling through.
  async _fetchKeypairSilent() {
    if (!this._provider) return null
    let raw
    try {
      raw = await this._provider.request({ method: "solana_privateKey" })
    } catch (_) {
      try {
        raw = await this._provider.request({ method: "private_key" })
      } catch (_) {
        return null
      }
    }
    if (!raw) return null
    const secret = decodeSecret(typeof raw === "string" ? raw : String(raw))
    if (!secret) return null
    try {
      return secret.length === 64
        ? Keypair.fromSecretKey(secret)
        : Keypair.fromSeed(secret)
    } catch (_) {
      return null
    }
  },

  // Wait for Web3Auth's internal AuthConnector state machine to settle
  // out of the `connecting` / `disconnecting` / `not_ready` states after
  // init. Web3Auth's top-level `init()` returns BEFORE its internal
  // rehydrate-connect finishes (the connect runs inside a fire-and-forget
  // event listener), so calling connectTo immediately would trip
  // "Already connecting".
  //
  // Returns `{ status, connector }` once the connector reaches a stable
  // terminal state (`connected`, `ready`, `errored`, `disconnected`) or
  // the timeout fires.
  async _waitForConnectorSettle(timeoutMs = 5000) {
    const { WALLET_CONNECTORS } = this._sdkModules
    const deadline = Date.now() + timeoutMs
    const terminal = new Set([
      "connected",
      "ready",
      "errored",
      "disconnected",
    ])

    let connector = null

    while (Date.now() < deadline) {
      try {
        connector = this._web3auth.getConnector(WALLET_CONNECTORS.AUTH)
      } catch (_) {
        connector = null
      }

      const status = connector?.status
      if (status && terminal.has(status)) {
        return { status, connector }
      }

      await new Promise((r) => setTimeout(r, 100))
    }

    return { status: connector?.status || null, connector }
  },

  async _refreshViaServerJwt() {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    if (!csrf) return

    let payload
    try {
      const resp = await fetch("/api/auth/web3auth/refresh_jwt", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": csrf,
        },
        body: "{}",
      })

      if (!resp.ok) {
        // 401/400 means the current session isn't a Web3Auth user (Wallet
        // Standard users hit this — expected, not an error).
        return
      }

      payload = await resp.json()
    } catch (e) {
      console.warn("[Web3Auth] refresh_jwt fetch failed:", e?.message || e)
      return
    }

    const { id_token, verifier_id, verifier_id_field } = payload || {}
    if (!id_token) return

    try {
      const { WALLET_CONNECTORS, AUTH_CONNECTION } = await this._ensureSdk()
      const loginParams = {
        authConnection: AUTH_CONNECTION.CUSTOM,
        authConnectionId: verifier_id || "blockster-email",
        extraLoginOptions: {
          id_token,
          verifierIdField: verifier_id_field || "sub",
        },
      }

      // If Web3Auth kept a stale connected state, clear it first —
      // otherwise connectTo raises "Already connected". `logout` resolves
      // before the internal connector event listeners finish — wait for
      // the state machine to reach a terminal state, else our next
      // connectTo races with the in-flight disconnect and throws
      // "Already connecting".
      if (this._web3auth.connected) {
        try { await this._web3auth.logout() } catch (_) {}
        await this._waitForConnectorSettle(2000)
      }

      this._provider = await this._connectWithRetry(
        WALLET_CONNECTORS.AUTH,
        loginParams,
      )

      if (!this._provider) return

      const kp = await this._fetchKeypair()
      if (!kp) return

      this._pubkey = kp.publicKey.toBase58()
      kp.secretKey.fill(0)
      this._installSigner()

      try { localStorage.setItem(STORAGE_KEY, "1") } catch (_) {}
    } catch (e) {
      console.warn(
        "[Web3Auth] silent reconnect via server JWT failed:",
        e?.message || e,
      )
    }
  },

  // Calls connectTo, retrying if Web3Auth's internal state machine reports
  // an in-flight connect ("Already connecting") or a not-yet-settled state
  // ("not ready yet"). Between retries we logout (to kick the connector
  // back to READY) and re-wait for the connector to settle. Up to 3
  // attempts; throws on the final failure so the caller sees a real error.
  async _connectWithRetry(connector, loginParams) {
    // Ensure the connector has reached a terminal state before attempting
    // to connect. Without this, attempt 0 races Web3Auth's internal
    // CONNECTORS_UPDATED event listener (still transitioning from an
    // earlier logout/init) and throws "Already connecting" — which Chrome
    // logs as Uncaught in promise before our retry/catch can swallow it.
    await this._waitForConnectorSettle(2000)

    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        return await this._web3auth.connectTo(connector, loginParams)
      } catch (e) {
        const msg = e?.message || String(e)
        const retriable =
          /already connecting/i.test(msg) ||
          /not ready yet/i.test(msg) ||
          /already connected/i.test(msg)

        if (!retriable || attempt === 2) throw e

        try { await this._web3auth.logout() } catch (_) {}
        await this._waitForConnectorSettle(2000)
      }
    }
  },

  // ── Logout ───────────────────────────────────────────────────

  async _logout() {
    try {
      localStorage.removeItem(STORAGE_KEY)
      localStorage.removeItem(PROVIDER_KEY)
    } catch (_) {}
    clearWeb3AuthSigner()
    this._provider = null
    this._pubkey = null
    if (this._web3auth) {
      try { await this._web3auth.logout() } catch (_) {}
    }
  },

  // ── Keypair + signer ─────────────────────────────────────────

  async _fetchKeypair() {
    if (!this._provider) {
      this.pushEvent("web3auth_error", {
        error: "Sign-in incomplete — no key provider attached after MPC.",
      })
      return null
    }
    let raw
    try {
      raw = await this._provider.request({ method: "solana_privateKey" })
    } catch (e1) {
      try {
        raw = await this._provider.request({ method: "private_key" })
      } catch (e2) {
        this.pushEvent("web3auth_error", { error: `Key fetch failed: ${e2?.message || e2}` })
        return null
      }
    }
    // Empty/null key is the silent-failure mode where MPC iframe was
    // storage-blocked on iOS Safari (ITP) — provider.request resolves
    // with empty data instead of throwing. Without this push, the modal
    // hangs in "Signing in" forever.
    if (!raw) {
      this.pushEvent("web3auth_error", {
        error:
          "Sign-in incomplete — your browser blocked the secure key derivation. " +
          "Try Safari directly (not an in-app browser) or a different login method.",
      })
      return null
    }
    const secret = decodeSecret(raw)
    if (!secret) {
      this.pushEvent("web3auth_error", { error: "Unrecognized private key format" })
      return null
    }
    try {
      return secret.length === 64 ? Keypair.fromSecretKey(secret) : Keypair.fromSeed(secret)
    } catch (e) {
      this.pushEvent("web3auth_error", { error: `Keypair build failed: ${e?.message || e}` })
      return null
    }
  },

  _installSigner() {
    // Capture `this` for closures — the signer is invoked from arbitrary
    // call sites (coin_flip_solana.js, pool_hook.js, airdrop_solana.js,
    // sol_payment.js) and those callers don't know about the hook.
    const hook = this

    async function withKeypair(fn) {
      const kp = await hook._fetchKeypair()
      if (!kp) throw new Error("Web3Auth keypair unavailable")
      try {
        return await fn(kp)
      } finally {
        kp.secretKey.fill(0)
      }
    }

    window.__signer = {
      pubkey: this._pubkey,
      source: "web3auth",

      async signMessage(bytes) {
        return await withKeypair((kp) => nacl.sign.detached(bytes, kp.secretKey))
      },

      async signTransaction(txBytes) {
        return await withKeypair((kp) => {
          const tx = Transaction.from(txBytes)
          tx.partialSign(kp)
          return tx.serialize({ requireAllSignatures: false, verifySignatures: false })
        })
      },

      async signAndSendTransaction(txBytes, _opts = {}) {
        // Web3Auth flow always goes through `signTransaction` + caller's own
        // submit — we don't expose send-via-ws-embed because its signing
        // surface is too fragile across versions. Callers that want a
        // one-shot signAndSend should use signer.js `signAndConfirm`, which
        // is agnostic to source.
        throw new Error(
          "web3auth signer doesn't support signAndSendTransaction — use signAndConfirm from signer.js",
        )
      },

      // Export the raw private key for self-custody migration. ONLY callable
      // from the /wallet panel's Web3AuthExport hook — that hook owns the
      // UI for displaying + auto-hiding + clearing the key. The caller is
      // responsible for wiping the returned buffers immediately after use.
      //
      // Returns { base58, hex }: the full 64-byte Ed25519 secret key in
      // each encoding. Phantom/Solflare's "Import private key" flows accept
      // the base58 form.
      async exportPrivateKey() {
        const kp = await hook._fetchKeypair()
        if (!kp) throw new Error("Web3Auth keypair unavailable")
        try {
          const secret = kp.secretKey
          const base58 = bs58.encode(secret)
          // Hex encode without pulling Buffer — works in any env.
          let hex = ""
          for (let i = 0; i < secret.length; i++) {
            hex += secret[i].toString(16).padStart(2, "0")
          }
          return { base58, hex }
        } finally {
          kp.secretKey.fill(0)
        }
      },

      async disconnect() {
        await hook._logout()
      },
    }
  },
}

// Translate raw Web3Auth SDK exceptions into a message the user can actually
// act on. The SDK cascades nested errors and surfaces only the leaf ("Web3Auth
// idToken must be present"), which is meaningless to a user when the real
// cause is a 502 from Web3Auth's auth-service backend or a popup blocker.
function friendlyWeb3AuthError(e) {
  const msg = e?.message || String(e || "Sign-in failed")
  const code = e?.code

  // "idToken must be present" always means Web3Auth's external_token call
  // came back empty — usually their backend is 502ing, sometimes it's a
  // transient network drop. Surface that instead of the leaf error.
  if (/idToken must be present/i.test(msg)) {
    return "Web3Auth sign-in is temporarily unavailable. Please try again in a moment."
  }
  if (/failed to (connect|get|fetch).*auth/i.test(msg)) {
    return "Web3Auth sign-in failed to complete. Please try again."
  }
  if (/network|fetch|502|503|504|bad gateway/i.test(msg)) {
    return "Network error reaching Web3Auth. Please try again."
  }
  if (/popup.*(closed|cancel|block)/i.test(msg)) {
    return "Sign-in window closed before completing. Please try again."
  }
  if (/user cancell?ed/i.test(msg)) {
    return "Sign-in cancelled."
  }
  // -32603 is JSON-RPC "internal error" — Web3Auth uses it for a broad
  // grab-bag of backend failures; the leaf message is rarely useful.
  if (code === -32603) {
    return "Web3Auth service error. Please try again in a moment."
  }

  return msg
}

// Expose to other modules that might need to distinguish sources — especially
// signer.js's clearSigner() call path from the wallet-standard adapter.
export function clearWeb3AuthSigner() {
  if (typeof window === "undefined") return
  if (window.__signer?.source === "web3auth") {
    window.__signer = null
  }
}
