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
// sessionStorage key: survives the same-tab OAuth redirect, clears on tab close.
// Set before navigating to Web3Auth; read on return to know which provider
// button the user tapped (pushed back to LiveView as `provider`).
const REDIRECT_PROVIDER_KEY = "blockster_web3auth_redirect_provider"

function isMobileUA() {
  try {
    if (navigator.userAgentData?.mobile === true) return true
  } catch (_) {}
  const ua = (navigator.userAgent || "").toLowerCase()
  return /mobi|android|iphone|ipad|ipod|opera mini|iemobile/.test(ua)
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
      // Redirect return takes precedence over silent reconnect — this is
      // the post-OAuth path where we need to mint a server session cookie.
      this._completeRedirectReturn(pendingRedirectProvider).catch((e) => {
        console.warn("[Web3Auth] redirect return failed:", e?.message || e)
        this.pushEvent("web3auth_error", { error: friendlyWeb3AuthError(e) })
      })
    } else if (hadSession && this._clientId) {
      // Silent init — if the session rehydrates, install the signer but do
      // NOT push wallet_authenticated (the user already has a session cookie).
      this._silentReconnect().catch((e) => {
        console.warn("[Web3Auth] silent reconnect failed:", e?.message || e)
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
    try {
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
      // the provider so `mounted` can finish the login on return.
      if (isMobileUA()) {
        try { sessionStorage.setItem(REDIRECT_PROVIDER_KEY, provider) } catch (_) {}
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
        this.pushEvent("web3auth_error", { error: "connectTo returned null" })
        return
      }

      await this._completeLogin(provider)
    } catch (e) {
      // If we stashed a redirect provider but `connectTo` then threw, clear
      // the hint so a future page mount doesn't try to complete a login that
      // never happened.
      try { sessionStorage.removeItem(REDIRECT_PROVIDER_KEY) } catch (_) {}
      console.error("[Web3Auth] login failed", e)
      this.pushEvent("web3auth_error", { error: friendlyWeb3AuthError(e) })
    }
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

  // Custom JWT login — used by the in-app email OTP flow + future Telegram
  // flow. The server has already validated the user's identity (OTP or
  // bot callback) and signed a JWT; we just hand it to Web3Auth's CUSTOM
  // connector which derives the MPC wallet deterministically from the JWT
  // `sub` + verifier id. No Web3Auth popup ceremony, no captcha.
  async _startJwtLogin({ provider, id_token, verifier_id, verifier_id_field }) {
    try {
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

      this._provider = await this._connectWithRetry(
        WALLET_CONNECTORS.AUTH,
        loginParams,
      )
      if (!this._provider) {
        this.pushEvent("web3auth_error", { error: "connectTo returned null" })
        return
      }

      await this._completeLogin(provider)
    } catch (e) {
      console.error("[Web3Auth] jwt login failed", e)
      this.pushEvent("web3auth_error", { error: friendlyWeb3AuthError(e) })
    }
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

      await this._ensureTelegramScript()

      // Telegram.Login.auth opens a popup window pointed at oauth.telegram.org.
      // It returns a payload (id, first_name, username, photo_url, auth_date,
      // hash) on success or `false` if the user cancels / the popup is blocked.
      const data = await new Promise((resolve) => {
        try {
          window.Telegram.Login.auth(
            { bot_id: this._telegramBotId, request_access: "write" },
            (payload) => resolve(payload || null),
          )
        } catch (e) {
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
    try { localStorage.removeItem(STORAGE_KEY) } catch (_) {}
    clearWeb3AuthSigner()
    this._provider = null
    this._pubkey = null
    if (this._web3auth) {
      try { await this._web3auth.logout() } catch (_) {}
    }
  },

  // ── Keypair + signer ─────────────────────────────────────────

  async _fetchKeypair() {
    if (!this._provider) return null
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
    if (!raw) return null
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
