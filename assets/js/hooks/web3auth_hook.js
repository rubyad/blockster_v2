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

    this._web3auth = null
    this._provider = null
    this._pubkey = null
    this._initPromise = null
    this._sdkModules = null

    this.handleEvent("start_web3auth_login", (payload) => this._startLogin(payload))
    this.handleEvent("start_web3auth_jwt_login", (payload) => this._startJwtLogin(payload))
    this.handleEvent("request_disconnect", () => this._logout())

    // Auto-reconnect if the last session flagged "logged in"
    const hadSession = (() => {
      try {
        return localStorage.getItem(STORAGE_KEY) === "1"
      } catch (_) {
        return false
      }
    })()
    if (hadSession && this._clientId) {
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

      this._web3auth = new Web3AuthCtor({
        clientId: this._clientId,
        web3AuthNetwork: networkKey,
        storageType: "local",
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
      }

      const loginParams = await this._loginParamsFor(provider, email_hint, AUTH_CONNECTION)
      if (!loginParams) return

      this._provider = await this._web3auth.connectTo(
        WALLET_CONNECTORS.AUTH,
        loginParams,
      )
      if (!this._provider) {
        this.pushEvent("web3auth_error", { error: "connectTo returned null" })
        return
      }

      await this._completeLogin(provider)
    } catch (e) {
      console.error("[Web3Auth] login failed", e)
      this.pushEvent("web3auth_error", { error: e?.message || "Login failed" })
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
      case "apple":
        return { authConnection: AUTH_CONNECTION.APPLE }
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
      }

      const loginParams = {
        authConnection: AUTH_CONNECTION.CUSTOM,
        authConnectionId: verifier_id || "blockster-email",
        extraLoginOptions: {
          id_token,
          verifierIdField: verifier_id_field || "sub",
        },
      }

      this._provider = await this._web3auth.connectTo(
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
      this.pushEvent("web3auth_error", { error: e?.message || "Sign-in failed" })
    }
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

// Expose to other modules that might need to distinguish sources — especially
// signer.js's clearSigner() call path from the wallet-standard adapter.
export function clearWeb3AuthSigner() {
  if (typeof window === "undefined") return
  if (window.__signer?.source === "web3auth") {
    window.__signer = null
  }
}
