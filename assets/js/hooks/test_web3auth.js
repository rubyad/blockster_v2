// THROWAWAY prototype — Phase 0 of social login plan.
// Exercises @web3auth/modal v10 with all 5 login providers on Solana devnet.
// Delete this file (and its LiveView + route) once Phase 5 lands.

import { Web3Auth, WALLET_CONNECTORS, WEB3AUTH_NETWORK } from "@web3auth/modal"
import { AUTH_CONNECTION } from "@web3auth/auth"
import {
  Connection,
  Transaction,
  TransactionInstruction,
  SystemProgram,
  Keypair,
  PublicKey,
} from "@solana/web3.js"
import bs58 from "bs58"
import nacl from "@toruslabs/tweetnacl-js"

function hexToBytes(hex) {
  const cleaned = hex.replace(/\s+/g, "")
  const out = new Uint8Array(cleaned.length / 2)
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(cleaned.slice(i * 2, i * 2 + 2), 16)
  }
  return out
}

// Web3Auth is inconsistent across versions/chains about whether the
// exported Solana key is hex, base58, or base64. Detect by length + charset.
function decodeSecret(raw) {
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

// Web3Auth's ws-embed provider (which the AUTH connector hands us on v10
// for Solana) uses its own chainId convention AND its own RPC method names
// — totally different from @web3auth/solana-provider's SolanaWallet helper.
// - Solana devnet chainId: 0x67 (mainnet 0x65, testnet 0x66)
// - Methods are prefixed `solana_*` (solana_requestAccounts, etc.).
const SOLANA_CHAIN_ID = "0x67"

export const TestWeb3Auth = {
  mounted() {
    this._web3auth = null
    this._provider = null

    this.el.querySelectorAll("[data-provider]").forEach((btn) => {
      btn.addEventListener("click", () => this._login(btn.dataset.provider))
    })

    this.el
      .querySelector("#tw-sign-message")
      ?.addEventListener("click", () => this._signMessage())
    this.el
      .querySelector("#tw-self-transfer")
      ?.addEventListener("click", () => this._selfTransfer())
    this.el
      .querySelector("#tw-two-signer")
      ?.addEventListener("click", () => this._twoSignerTx())
    this.el
      .querySelector("#tw-logout")
      ?.addEventListener("click", () => this._logout())

    this._init().catch((e) => this._log(`init failed: ${e.message}`, "error"))
  },

  async _init() {
    const clientId = this.el.dataset.clientId
    const rpcUrl = this.el.dataset.rpcUrl
    if (!clientId) {
      this._log(
        "Missing WEB3AUTH_CLIENT_ID — paste yours into .env and restart.",
        "error",
      )
      return
    }

    this._web3auth = new Web3Auth({
      clientId,
      web3AuthNetwork: WEB3AUTH_NETWORK.SAPPHIRE_DEVNET,
      storageType: "session",
      chains: [
        {
          chainNamespace: "solana",
          chainId: SOLANA_CHAIN_ID,
          rpcTarget: rpcUrl,
          displayName: "Solana Devnet",
          blockExplorerUrl: "https://explorer.solana.com/?cluster=devnet",
          ticker: "SOL",
          tickerName: "Solana",
          logo: "https://ik.imagekit.io/blockster/blockster-icon.png",
        },
      ],
      defaultChainId: SOLANA_CHAIN_ID,
    })

    await this._web3auth.init()
    this._log("web3auth initialized", "ok")

    // Only claim the session if the provider was actually wired up — a stale
    // "connected" flag without a provider would crash downstream calls.
    if (this._web3auth.connected && this._web3auth.provider) {
      this._provider = this._web3auth.provider
      await this._showAccount()
    }
  },

  async _login(providerKey) {
    if (!this._web3auth) {
      this._log("web3auth not ready", "error")
      return
    }
    this._log(`connecting via ${providerKey}…`)
    try {
      // If a half-initialized session survived, clear it so connectTo can
      // open a fresh popup. "Already connected" errors otherwise.
      if (this._web3auth.connected) {
        try {
          await this._web3auth.logout()
        } catch (_) {}
      }

      const loginParams = this._loginParamsFor(providerKey)
      if (!loginParams) return
      this._provider = await this._web3auth.connectTo(
        WALLET_CONNECTORS.AUTH,
        loginParams,
      )
      if (!this._provider) {
        this._log("connectTo returned null", "error")
        return
      }
      await this._showAccount()
    } catch (e) {
      this._log(`login failed (${providerKey}): ${e.message}`, "error")
    }
  },

  _loginParamsFor(key) {
    switch (key) {
      case "email": {
        // Browsers block popups unless they're opened within the same
        // user-gesture callstack as the click. prompt() breaks that chain,
        // so read the email synchronously from the inline input instead.
        const input = this.el.querySelector("#tw-email-input")
        const email = input ? input.value.trim() : ""
        if (!email) {
          this._log("enter an email in the input first", "error")
          if (input) input.focus()
          return null
        }
        return {
          authConnection: AUTH_CONNECTION.EMAIL_PASSWORDLESS,
          extraLoginOptions: { login_hint: email },
        }
      }
      case "google":
        return { authConnection: AUTH_CONNECTION.GOOGLE }
      case "apple":
        return { authConnection: AUTH_CONNECTION.APPLE }
      case "twitter":
        return { authConnection: AUTH_CONNECTION.TWITTER }
      case "telegram":
        return this._telegramJwtParams()
      default:
        this._log(`unknown provider ${key}`, "error")
        return null
    }
  },

  async _telegramJwtParams() {
    // Telegram is wired through our backend: widget → /api/auth/telegram/verify
    // returns a Blockster-signed JWT → Web3Auth's CUSTOM verifier.
    // Prototype: we expect the user to paste a Telegram Login Widget payload
    // into the prompt (real flow uses the widget embed; that's Phase 5).
    const raw = prompt(
      "Paste Telegram Login Widget JSON (id, auth_date, first_name, hash, etc.):",
    )
    if (!raw) return null
    let telegramPayload
    try {
      telegramPayload = JSON.parse(raw)
    } catch (_) {
      this._log("invalid JSON", "error")
      return null
    }

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    const resp = await fetch("/api/auth/telegram/verify", {
      method: "POST",
      headers: { "content-type": "application/json", "x-csrf-token": csrf },
      body: JSON.stringify(telegramPayload),
    })
    if (!resp.ok) {
      this._log(`telegram verify failed: ${resp.status}`, "error")
      return null
    }
    const { id_token } = await resp.json()
    const verifierId = String(telegramPayload.id)
    return {
      authConnection: AUTH_CONNECTION.CUSTOM,
      authConnectionId: this.el.dataset.telegramVerifierId || "blockster-telegram",
      extraLoginOptions: {
        id_token,
        verifierIdField: "sub",
      },
    }
  },

  async _showAccount() {
    // Pull the key once at login just to derive the pubkey, then throw it
    // away immediately — per-operation signing fetches it again. No caching,
    // no storage. This keeps the attacker exposure window to the few ms
    // each sign holds the key in memory.
    const kp = await this._fetchKeypair()
    if (!kp) return
    this._pubkey = kp.publicKey.toBase58()
    this._log(`connected: ${this._pubkey}`, "ok")
    kp.secretKey.fill(0) // zero the seed+pubkey buffer

    let info = {}
    try {
      info = await this._web3auth.getUserInfo()
      this._log(`userInfo: ${JSON.stringify(info, null, 2)}`, "ok")
    } catch (e) {
      this._log(`getUserInfo failed (benign): ${e.message}`, "error")
    }
    this._setStatus(this._pubkey, info)
  },

  // Fetch the derived Solana key from Web3Auth on demand and return a fresh
  // Keypair. Never cached on the instance; zero the secret when done with it.
  async _fetchKeypair() {
    if (!this._provider) {
      this._log("provider missing", "error")
      return null
    }

    let raw
    try {
      raw = await this._provider.request({ method: "solana_privateKey" })
    } catch (e) {
      try {
        raw = await this._provider.request({ method: "private_key" })
      } catch (e2) {
        this._log(`private key fetch failed: ${e2.message}`, "error")
        return null
      }
    }
    if (!raw) {
      this._log("private key fetch returned empty", "error")
      return null
    }
    if (typeof raw !== "string") raw = String(raw)
    const secret = decodeSecret(raw)
    if (!secret) {
      this._log(
        `unrecognized key format (len=${raw.length}): ${raw.slice(0, 20)}…`,
        "error",
      )
      return null
    }
    try {
      return secret.length === 64
        ? Keypair.fromSecretKey(secret)
        : Keypair.fromSeed(secret)
    } catch (e) {
      this._log(
        `Keypair build failed (bytes=${secret.length}): ${e.message}`,
        "error",
      )
      return null
    }
  },

  _setStatus(pubkey, info) {
    const status = this.el.querySelector("#tw-status")
    if (!status) return
    status.textContent = `pubkey=${pubkey} verifier=${info?.verifier || "?"} email=${info?.email || "-"}`
    this.el.querySelectorAll(".tw-action").forEach((el) => el.removeAttribute("disabled"))
  },

  // With the derived Solana Keypair in hand we just use @solana/web3.js
  // directly — identical pattern to what the production signer hook will
  // do internally for Web3Auth-authenticated users.

  async _signMessage() {
    const kp = await this._fetchKeypair()
    if (!kp) return
    try {
      const msgBytes = new TextEncoder().encode(
        "blockster test sign " + Date.now(),
      )
      const sigBytes = nacl.sign.detached(msgBytes, kp.secretKey)
      this._log(`signMessage OK: ${bs58.encode(sigBytes)}`, "ok")
    } catch (e) {
      this._log(`signMessage failed: ${e.message}`, "error")
    } finally {
      kp.secretKey.fill(0)
    }
  },

  async _selfTransfer() {
    const kp = await this._fetchKeypair()
    if (!kp) return
    try {
      const rpcUrl = this.el.dataset.rpcUrl
      const conn = new Connection(rpcUrl, "confirmed")
      const { blockhash } = await conn.getLatestBlockhash("finalized")
      const tx = new Transaction({
        feePayer: kp.publicKey,
        recentBlockhash: blockhash,
      })
      tx.add(
        SystemProgram.transfer({
          fromPubkey: kp.publicKey,
          toPubkey: kp.publicKey,
          lamports: 1,
        }),
      )
      tx.sign(kp)
      const sig = await conn.sendRawTransaction(tx.serialize())
      this._log(
        `self-transfer submitted: https://explorer.solana.com/tx/${sig}?cluster=devnet`,
        "ok",
      )
    } catch (e) {
      this._log(`self-transfer failed: ${e.message}`, "error")
    } finally {
      kp.secretKey.fill(0)
    }
  },

  // Proves the whole zero-SOL UX: settler is fee payer (pays the ~5k lamport
  // tx fee from its balance), user signs as an instruction signer with ZERO
  // SOL of their own. We use SPL Memo (pure data, no lamport movement) so
  // the user's empty balance doesn't matter — exactly what real bet_place
  // will look like once Phase 1's rent_payer upgrade lands.
  async _twoSignerTx() {
    const kp = await this._fetchKeypair()
    if (!kp) return
    try {
      const rpcUrl = this.el.dataset.rpcUrl
      const conn = new Connection(rpcUrl, "confirmed")
      const settler = Keypair.fromSecretKey(
        bs58.decode(this.el.dataset.settlerSecret),
      )

      const MEMO_PROGRAM_ID = new PublicKey(
        "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr",
      )
      const memoData = Buffer.from(
        `blockster two-signer ${Date.now()}`,
        "utf8",
      )
      const memoIx = new TransactionInstruction({
        programId: MEMO_PROGRAM_ID,
        keys: [{ pubkey: kp.publicKey, isSigner: true, isWritable: false }],
        data: memoData,
      })

      const { blockhash } = await conn.getLatestBlockhash("finalized")
      const tx = new Transaction({
        feePayer: settler.publicKey,
        recentBlockhash: blockhash,
      })
      tx.add(memoIx)

      tx.partialSign(settler)
      tx.partialSign(kp)
      const sig = await conn.sendRawTransaction(tx.serialize())
      this._log(
        `two-signer tx: https://explorer.solana.com/tx/${sig}?cluster=devnet`,
        "ok",
      )
    } catch (e) {
      this._log(`two-signer failed: ${e.message}`, "error")
    } finally {
      kp.secretKey.fill(0)
    }
  },

  async _logout() {
    if (!this._web3auth) return
    try {
      await this._web3auth.logout()
      this._log("logged out", "ok")
      const status = this.el.querySelector("#tw-status")
      if (status) status.textContent = "(disconnected)"
      this.el.querySelectorAll(".tw-action").forEach((el) =>
        el.setAttribute("disabled", "true"),
      )
      this._provider = null
      this._pubkey = null
    } catch (e) {
      this._log(`logout failed: ${e.message}`, "error")
    }
  },

  _log(msg, kind) {
    const out = this.el.querySelector("#tw-log")
    if (!out) return
    const ts = new Date().toISOString().slice(11, 19)
    const color = kind === "error" ? "#c0392b" : kind === "ok" ? "#16a085" : "#333"
    const row = document.createElement("div")
    row.style.color = color
    row.style.whiteSpace = "pre-wrap"
    row.textContent = `[${ts}] ${msg}`
    out.prepend(row)
  },
}
