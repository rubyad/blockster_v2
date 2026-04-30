// Web3Auth SFA mobile hook (Phase 1 of the SFA migration).
//
// Replaces the iframe-based modal hook for mobile users. Calls
// @toruslabs/customauth's getTorusKey directly — pure HTTPS, no iframe,
// no ws-embed, no service worker — so iOS Safari ITP does not block
// the MPC handshake. Same Torus DKG nodes + same Sapphire verifiers as
// modal, so SFA derives a deterministic Solana pubkey for any
// (verifier, sub) tuple. (Note: the ed25519 derivation path differs
// between SFA and modal — confirmed mismatch on 2026-04-29 — so existing
// modal-registered users get new pubkeys here. The reclaim flow handles
// that via Accounts.reclaim_legacy_via_web3auth/3.)
//
// Scope (v1): email-OTP custom JWT, Telegram custom JWT (popup +
// redirect + fragment), silent reconnect via /api/auth/web3auth/refresh_jwt.
// OAuth (X / Google / Apple) is NOT handled here — those still go through
// the modal hook. Mobile users on those providers are no worse off than
// today (still broken). Will be addressed in Phase 1.1 via
// customauth.triggerLogin(uxMode: redirect).
//
// Signer surface (window.__signer) MUST stay identical to the modal hook
// so SolPaymentHook / SolanaBuxBurn / signer.js keep working transparently.
// Per-sign we re-fetch the keypair (CLAUDE.md mandate: never cache the
// derived secret across operations). The JWT itself is cached in-memory
// for the hook lifetime — it's a credential, not a key.

import bs58 from "bs58"
import { Transaction, Keypair } from "@solana/web3.js"
import nacl from "@toruslabs/tweetnacl-js"

// Distinct from the modal hook's storage key so the two SDK paths don't
// collide on cross-device sign-in. Modal-signed-in users on a desktop
// session have their own flag; mobile SFA users have theirs.
const STORAGE_KEY = "blockster_web3auth_sfa_session"
const PROVIDER_KEY = "blockster_web3auth_sfa_provider"

// Cache the JWT for the hook lifetime so we don't hit /refresh_jwt on
// every sign. Bound by the JWT's own 10-minute TTL — refresh on demand.
const JWT_TTL_BUFFER_MS = 30_000 // refresh 30s before expiry

// Phase 1.1 soft cache for the derived ed25519 seed. SFA's getTorusKey
// is a ~1s HTTPS round-trip to the Torus DKG cluster — too slow per
// sign for fast-paced flows like coin flip. The cache lets consecutive
// signs reuse the seed without hitting the network. CLAUDE.md was
// updated to allow short-lived in-memory key cache as long as we never
// write to persistent storage. Default 60s, configurable via
// data-key-cache-ttl-ms attribute on the hook root.
const DEFAULT_KEY_CACHE_TTL_MS = 60_000

let _customAuthCtor = null

async function loadCustomAuth() {
  if (_customAuthCtor) return _customAuthCtor
  const mod = await import("@toruslabs/customauth")
  _customAuthCtor = mod.CustomAuth || mod.default || mod
  return _customAuthCtor
}

function isMobileUA() {
  try {
    if (navigator.userAgentData?.mobile === true) return true
  } catch (_) {}
  const ua = (navigator.userAgent || "").toLowerCase()
  if (/mobi|android|iphone|ipad|ipod|opera mini|iemobile/.test(ua)) return true
  // iPadOS 13+ Safari reports a Mac UA. Touch + platform disambiguates.
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

function hexToBytes(hex) {
  const cleaned = hex.replace(/\s+/g, "")
  const stripped = cleaned.startsWith("0x") ? cleaned.slice(2) : cleaned
  const padded = stripped.length % 2 === 1 ? "0" + stripped : stripped
  const out = new Uint8Array(padded.length / 2)
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(padded.slice(i * 2, i * 2 + 2), 16)
  }
  return out
}

function extractPrivKey(result) {
  if (!result) return null
  return (
    result?.finalKeyData?.privKey ||
    result?.privKey ||
    result?.ed25519PrivKey ||
    null
  )
}

function decodeJwtExp(jwt) {
  try {
    const parts = jwt.split(".")
    if (parts.length !== 3) return null
    let payloadB64 = parts[1].replace(/-/g, "+").replace(/_/g, "/")
    while (payloadB64.length % 4) payloadB64 += "="
    const payload = JSON.parse(atob(payloadB64))
    if (typeof payload.exp === "number") return payload.exp * 1000
    return null
  } catch (_) {
    return null
  }
}

function jwtIsFresh(jwt) {
  const expMs = decodeJwtExp(jwt)
  if (!expMs) return false
  return expMs - Date.now() > JWT_TTL_BUFFER_MS
}

export const Web3AuthSfa = {
  async mounted() {
    // Phase 2 (2026-04-30): SFA owns ALL UAs (desktop + mobile). The
    // modal hook is now inert on every device — Chrome's third-party
    // cookie restrictions broke its iframe MPC handshake the same way
    // iOS Safari ITP did, and rather than maintain two SDK paths we
    // unify on customauth's pure-HTTPS getTorusKey. Existing modal
    // users get new pubkeys on next sign-in via the email reclaim
    // flow (Accounts.reclaim_legacy_via_web3auth/3).

    this._clientId = this.el.dataset.clientId || ""
    this._rpcUrl = this.el.dataset.rpcUrl || ""
    this._chainId = this.el.dataset.chainId || "0x65"
    // The data-network attribute carries the Web3Auth enum KEY (e.g.
    // "SAPPHIRE_MAINNET") — the modal hook does an SDK enum lookup. Customauth /
    // torus.js expect the lowercase string value ("sapphire_mainnet") directly,
    // so lowercase the attr before handing it to the SFA SDK. Without this,
    // torus.js throws "Invalid network" at the first getTorusKey call.
    this._network = (this.el.dataset.network || "sapphire_mainnet").toLowerCase()
    this._telegramVerifierId = this.el.dataset.telegramVerifierId || ""
    this._telegramBotId = this.el.dataset.telegramBotId || ""
    this._keyCacheTtlMs =
      parseInt(this.el.dataset.keyCacheTtlMs, 10) || DEFAULT_KEY_CACHE_TTL_MS

    this._customAuth = null
    this._pubkey = null
    this._cachedJwt = null
    this._cachedVerifier = null
    this._cachedVerifierId = null
    this._cachedSeed = null
    this._cachedSeedExpiresAt = 0

    if (!this._clientId) {
      // Social login disabled or env not configured. Stay quiet.
      return
    }

    this.handleEvent("start_web3auth_jwt_login", (payload) =>
      this._handleStartJwtLogin(payload),
    )
    this.handleEvent("start_telegram_widget", () => this._handleStartTelegramLogin())
    this.handleEvent("request_disconnect", () => this._logout())

    // Mobile owns ALL Web3Auth flows here — modal hook short-circuits on
    // mobile so it can't race with us. start_web3auth_login is OAuth-only
    // in practice (provider in {google, twitter, apple}); we don't yet
    // implement it via customauth.triggerLogin (Phase 1.1). Surface a
    // clear error so the button doesn't silently fail.
    this.handleEvent("start_web3auth_login", (payload) => {
      const provider = payload?.provider
      this.pushEvent("web3auth_error", {
        error:
          provider && provider !== "email" && provider !== "telegram"
            ? `Sign-in with ${provider} isn't supported on mobile yet. Please use email or Telegram.`
            : "Mobile sign-in temporarily unavailable for this provider.",
      })
    })

    // Mount-time Telegram return — same fragment + query-param contract as
    // the modal hook. Called whether or not we just signed in.
    const telegramFlag = (() => {
      try {
        const p = new URLSearchParams(window.location.search)
        return p.has("telegram_login") || p.has("telegram_login_error")
      } catch (_) {
        return false
      }
    })()

    if (telegramFlag) {
      this._completeTelegramRedirectReturn().catch((e) => {
        console.warn("[Web3AuthSfa] Telegram return failed:", e?.message || e)
        this.pushEvent("web3auth_error", {
          error: e?.message || "Telegram login failed",
        })
      })
    }

    // Silent reconnect: returning user with a saved session flag.
    const hadSession = (() => {
      try {
        return localStorage.getItem(STORAGE_KEY) === "1"
      } catch (_) {
        return false
      }
    })()

    if (hadSession && !telegramFlag) {
      // Run silent reconnect in the background — don't block mount.
      this._silentReconnect().catch((e) => {
        console.warn("[Web3AuthSfa] silent reconnect failed:", e?.message || e)
      })
    }
  },

  destroyed() {
    // Don't clear window.__signer here — the LV may reconnect and remount;
    // signer continuity is what lets in-flight tx flows survive a socket
    // hiccup. Modal hook follows the same pattern.
  },

  async _ensureSdk() {
    if (this._customAuth) return this._customAuth
    const CustomAuth = await loadCustomAuth()
    this._customAuth = new CustomAuth({
      baseUrl: window.location.origin,
      network: this._network,
      web3AuthClientId: this._clientId,
      keyType: "ed25519",
      enableLogging: false,
    })
    // skipInit + skipSw + skipPrefetch keep init() out of any browser-only
    // code paths (service-worker fetch, redirect-uri prefetch). The internal
    // storageHelper.init() still runs but is HTTPS-based.
    await this._customAuth.init({
      skipSw: true,
      skipInit: true,
      skipPrefetch: true,
    })
    return this._customAuth
  },

  // ── Login entry points ────────────────────────────────────────

  async _handleStartJwtLogin({ provider, id_token, verifier_id, verifier_id_field }) {
    try {
      await this._doSfaLogin({
        provider: provider || "email",
        id_token,
        verifier: verifier_id || "blockster-email",
        verifier_id_field: verifier_id_field || "sub",
      })
    } catch (e) {
      this.pushEvent("web3auth_error", {
        error: e?.message || "Sign-in failed",
      })
    }
  },

  async _handleStartTelegramLogin() {
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

    // Mobile path — top-level navigation to oauth.telegram.org. Server's
    // /api/auth/telegram/callback HMAC-validates and bounces back with the
    // JWT in the URL fragment. Mounted() picks it up next page load.
    const origin = window.location.origin
    const returnTo = `${origin}/api/auth/telegram/callback`
    const url =
      `https://oauth.telegram.org/auth?bot_id=${encodeURIComponent(this._telegramBotId)}` +
      `&origin=${encodeURIComponent(origin)}` +
      `&request_access=write` +
      `&return_to=${encodeURIComponent(returnTo)}`

    try {
      sessionStorage.setItem(PROVIDER_KEY, "telegram")
    } catch (_) {}
    window.location.href = url
  },

  async _completeTelegramRedirectReturn() {
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

    let jwt = fragmentJwt
    if (!jwt) {
      // Legacy fallback — server-side stash via session cookie.
      try {
        const res = await fetch("/api/auth/telegram/pending_jwt", {
          method: "GET",
          credentials: "same-origin",
        })
        const json = await res.json().catch(() => ({}))
        if (res.ok && json?.success && json?.id_token) jwt = json.id_token
      } catch (_) {}
    }

    if (!jwt) {
      this.pushEvent("web3auth_error", {
        error: "Telegram login state was not found",
      })
      return
    }

    await this._doSfaLogin({
      provider: "telegram",
      id_token: jwt,
      verifier: this._telegramVerifierId,
      verifier_id_field: "sub",
    })
  },

  // ── Core SFA derivation + signer install ──────────────────────

  // Derives the Solana pubkey for the (verifier, sub) tuple via SFA, then
  // installs the signer and tells the LiveView the user is authenticated.
  // The verifier_id (Web3Auth's term for the user's stable identifier
  // within the verifier) is read from the JWT's `sub` claim — same field
  // production's modal flow uses, same MPC derivation cluster on Sapphire,
  // just delivered via direct HTTPS instead of the iframe-postMessage path.
  async _doSfaLogin({ provider, id_token, verifier, verifier_id_field }) {
    if (!id_token) {
      this.pushEvent("web3auth_error", { error: "Missing id_token" })
      return
    }

    const sub = subFromJwt(id_token, verifier_id_field || "sub")
    if (!sub) {
      this.pushEvent("web3auth_error", {
        error: "JWT missing required identifier claim",
      })
      return
    }

    const ca = await this._ensureSdk()

    let result
    try {
      result = await ca.getTorusKey({
        authConnectionId: verifier,
        userId: sub,
        idToken: id_token,
      })
    } catch (e) {
      this.pushEvent("web3auth_error", {
        error: e?.message || "Key derivation failed",
      })
      return
    }

    const privKeyHex = extractPrivKey(result)
    if (!privKeyHex) {
      this.pushEvent("web3auth_error", {
        error: "Key derivation returned no private key",
      })
      return
    }

    const seedBytes = hexToBytes(privKeyHex)
    let kp
    try {
      kp =
        seedBytes.length === 64
          ? Keypair.fromSecretKey(seedBytes)
          : Keypair.fromSeed(seedBytes)
    } catch (e) {
      this.pushEvent("web3auth_error", {
        error: `Keypair build failed: ${e?.message || e}`,
      })
      return
    }

    this._pubkey = kp.publicKey.toBase58()
    try {
      kp.secretKey.fill(0)
    } catch (_) {}

    // Cache the JWT + verifier params so per-sign re-derivation skips the
    // /refresh_jwt round-trip while the JWT is still fresh.
    this._cachedJwt = id_token
    this._cachedVerifier = verifier
    this._cachedVerifierId = sub

    // Cache the seed bytes for fast subsequent signs (Phase 1.1). We
    // keep our own copy because seedBytes is a local that other callers
    // may zero out. Zeroed on TTL expiry, on sign-out, and on logout.
    this._cacheSeed(seedBytes)

    this._installSigner()

    try {
      localStorage.setItem(STORAGE_KEY, "1")
      if (provider) localStorage.setItem(PROVIDER_KEY, provider)
    } catch (_) {}

    this.pushEvent("web3auth_authenticated", {
      provider: provider || null,
      wallet_address: this._pubkey,
      id_token,
      verifier,
      auth_connection: provider || null,
      email: null,
      name: null,
      profile_image: null,
      user_id: sub,
    })
  },

  async _silentReconnect() {
    // Mint a fresh JWT from /refresh_jwt (the server knows we're a Web3Auth
    // user because the session cookie is present), then run SFA derivation
    // exactly like a fresh login. Same MPC, same pubkey for the same
    // (verifier, sub) — server-side identity is unchanged.
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
        // 401/400 — current session isn't a Web3Auth user (Wallet Standard
        // user, or no session). Not an error.
        return
      }
      payload = await resp.json()
    } catch (e) {
      console.warn("[Web3AuthSfa] refresh_jwt fetch failed:", e?.message || e)
      return
    }

    const { id_token, verifier_id, verifier_id_field } = payload || {}
    if (!id_token) return

    let provider = null
    try {
      provider = localStorage.getItem(PROVIDER_KEY)
    } catch (_) {}

    await this._doSfaLogin({
      provider,
      id_token,
      verifier: verifier_id || "blockster-email",
      verifier_id_field: verifier_id_field || "sub",
    })
  },

  // ── Per-sign keypair fetch ────────────────────────────────────

  async _fetchKeypair() {
    // Phase 1.1 fast path: if we have a fresh cached seed, derive the
    // Keypair locally. The Torus DKG round-trip (~1s) is skipped for up
    // to TTL_MS after the last derive — long enough to make consecutive
    // signs (coin flip bursts, multi-step pool flows) feel native.
    if (this._cachedSeed && Date.now() < this._cachedSeedExpiresAt) {
      return this._keypairFromBytes(this._cachedSeed)
    }
    if (this._cachedSeed) {
      // Past TTL — zero the stale copy before re-deriving.
      this._zeroCachedSeed()
    }

    let jwt = this._cachedJwt
    if (!jwt || !jwtIsFresh(jwt)) {
      jwt = await this._refreshCachedJwt()
      if (!jwt) {
        this.pushEvent("web3auth_error", {
          error: "Sign-in required — JWT expired and refresh failed",
        })
        return null
      }
    }

    const ca = await this._ensureSdk()
    let result
    try {
      result = await ca.getTorusKey({
        authConnectionId: this._cachedVerifier,
        userId: this._cachedVerifierId,
        idToken: jwt,
      })
    } catch (e) {
      this.pushEvent("web3auth_error", {
        error: `Key derivation failed: ${e?.message || e}`,
      })
      return null
    }

    const privKeyHex = extractPrivKey(result)
    if (!privKeyHex) {
      this.pushEvent("web3auth_error", { error: "Empty private key from SFA" })
      return null
    }

    const bytes = hexToBytes(privKeyHex)
    this._cacheSeed(bytes)
    return this._keypairFromBytes(bytes)
  },

  _keypairFromBytes(bytes) {
    try {
      return bytes.length === 64
        ? Keypair.fromSecretKey(bytes)
        : Keypair.fromSeed(bytes)
    } catch (e) {
      this.pushEvent("web3auth_error", {
        error: `Keypair build failed: ${e?.message || e}`,
      })
      return null
    }
  },

  _cacheSeed(bytes) {
    // Defensive copy — bytes may be zeroed by the caller after the
    // current sign completes. Our cache must outlive that.
    this._cachedSeed = new Uint8Array(bytes)
    this._cachedSeedExpiresAt = Date.now() + this._keyCacheTtlMs
  },

  _zeroCachedSeed() {
    if (this._cachedSeed) {
      try {
        this._cachedSeed.fill(0)
      } catch (_) {}
      this._cachedSeed = null
    }
    this._cachedSeedExpiresAt = 0
  },

  async _refreshCachedJwt() {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    if (!csrf) return null
    try {
      const resp = await fetch("/api/auth/web3auth/refresh_jwt", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": csrf,
        },
        body: "{}",
      })
      if (!resp.ok) return null
      const json = await resp.json()
      if (!json?.id_token) return null
      this._cachedJwt = json.id_token
      this._cachedVerifier = json.verifier_id || this._cachedVerifier
      // verifier_id_field == "sub" — recompute sub from the new JWT.
      const sub = subFromJwt(json.id_token, json.verifier_id_field || "sub")
      if (sub) this._cachedVerifierId = sub
      return json.id_token
    } catch (_) {
      return null
    }
  },

  _installSigner() {
    const hook = this

    async function withKeypair(fn) {
      const kp = await hook._fetchKeypair()
      if (!kp) throw new Error("Web3Auth SFA keypair unavailable")
      try {
        return await fn(kp)
      } finally {
        try {
          kp.secretKey.fill(0)
        } catch (_) {}
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
          return tx.serialize({
            requireAllSignatures: false,
            verifySignatures: false,
          })
        })
      },

      async signAndSendTransaction(_txBytes, _opts = {}) {
        throw new Error(
          "web3auth (SFA) signer doesn't support signAndSendTransaction — use signAndConfirm from signer.js",
        )
      },

      async exportPrivateKey() {
        const kp = await hook._fetchKeypair()
        if (!kp) throw new Error("Web3Auth SFA keypair unavailable")
        try {
          const secret = kp.secretKey
          const base58 = bs58.encode(secret)
          let hex = ""
          for (let i = 0; i < secret.length; i++) {
            hex += secret[i].toString(16).padStart(2, "0")
          }
          return { base58, hex }
        } finally {
          try {
            kp.secretKey.fill(0)
          } catch (_) {}
        }
      },

      async disconnect() {
        await hook._logout()
      },
    }
  },

  async _logout() {
    this._pubkey = null
    this._cachedJwt = null
    this._cachedVerifier = null
    this._cachedVerifierId = null
    this._zeroCachedSeed()
    try {
      localStorage.removeItem(STORAGE_KEY)
      localStorage.removeItem(PROVIDER_KEY)
    } catch (_) {}
    if (window.__signer?.source === "web3auth") {
      window.__signer = null
    }
  },
}

function subFromJwt(jwt, field) {
  try {
    const parts = jwt.split(".")
    if (parts.length !== 3) return null
    let b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/")
    while (b64.length % 4) b64 += "="
    const claims = JSON.parse(atob(b64))
    const v = claims?.[field || "sub"]
    return typeof v === "string" && v.length > 0 ? v : null
  } catch (_) {
    return null
  }
}

export function clearWeb3AuthSfaSigner() {
  if (typeof window === "undefined") return
  if (window.__signer?.source === "web3auth") {
    window.__signer = null
  }
}
