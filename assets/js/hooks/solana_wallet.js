// SolanaWallet hook — wallet detection, connect, sign, disconnect
// Ported from RogueTrader/FateSwap with Blockster branding

import { getWallets } from "@wallet-standard/app"
import bs58 from "bs58"
import {
  installWalletStandardSigner,
  clearSigner,
} from "./signer.js"

const STORAGE_KEY = "blockster_wallet"
const CHAIN = "solana:devnet" // TODO wire to window.BLOCKSTER_CHAIN in Phase 5

export const SolanaWallet = {
  mounted() {
    // Clear legacy EVM localStorage on first load
    try {
      localStorage.removeItem("walletAddress")
      localStorage.removeItem("smartAccountAddress")
    } catch (_) {}

    this._wallets = []
    this._connectedWallet = null
    this._connectedAccount = null
    this._unsubscribeAccountChange = null
    this._autoReconnectPending = true

    this._discoverWallets()

    this.handleEvent("request_connect", (payload) => this._handleConnect(payload))
    this.handleEvent("request_sign", (payload) => this._handleSign(payload))
    this.handleEvent("request_disconnect", () => this._handleDisconnect())
    this.handleEvent("persist_session", ({ wallet_address }) => this._persistSession(wallet_address))
    this.handleEvent("persist_web3auth_session", (payload) => this._persistWeb3AuthSession(payload))
    this.handleEvent("clear_session", () => this._clearSession())
    this.handleEvent("discover_and_connect", () => this._discoverAndConnect())

    this._onVisibility = () => {
      if (document.visibilityState !== "visible") return
      if (this._connectedWallet && this._connectedAccount) {
        // Re-query the wallet's CURRENT account before pushing reconnect.
        // The user may have switched accounts in their wallet extension while
        // the tab was hidden.
        const currentAccount = this._currentWalletAccount()
        if (!currentAccount) {
          // Wallet revoked authorization while tab was hidden
          this._handleExternalDisconnect()
          return
        }
        if (currentAccount.address !== this._connectedAccount.address) {
          this._handleAccountChange(currentAccount)
          return
        }
        this.pushEvent("wallet_reconnected", {
          pubkey: this._connectedAccount.address,
          wallet_name: this._connectedWallet.name,
        })
      } else {
        this._tryAutoReconnect()
      }
    }
    document.addEventListener("visibilitychange", this._onVisibility)
  },

  reconnected() {
    if (this._connectedWallet && this._connectedAccount) {
      // Mirror the visibilitychange logic — re-query the wallet for its
      // current account in case the user switched accounts while the
      // WebSocket was disconnected.
      const currentAccount = this._currentWalletAccount()
      if (!currentAccount) {
        this._handleExternalDisconnect()
        return
      }
      if (currentAccount.address !== this._connectedAccount.address) {
        this._handleAccountChange(currentAccount)
        return
      }
      this.pushEvent("wallet_reconnected", {
        pubkey: this._connectedAccount.address,
        wallet_name: this._connectedWallet.name,
      })
    } else {
      this._tryAutoReconnect()
    }
  },

  destroyed() {
    if (this._unsubscribe) this._unsubscribe()
    if (this._unsubscribeAccountChange) {
      try { this._unsubscribeAccountChange() } catch (_) {}
      this._unsubscribeAccountChange = null
    }
    if (this._onVisibility) document.removeEventListener("visibilitychange", this._onVisibility)
    this._connectedWallet = null
    this._connectedAccount = null
    window.__solanaWallet = null
  },

  _discoverWallets() {
    try {
      const { get, on } = getWallets()
      const solanaWallets = this._filterSolanaWallets(get())
      this._wallets = solanaWallets
      this._pushWallets()

      this._unsubscribe = on("register", () => {
        const updated = this._filterSolanaWallets(get())
        this._wallets = updated
        this._pushWallets()
      })
    } catch (e) {
      console.error("SolanaWallet: failed to discover wallets", e)
      this.pushEvent("wallets_detected", { wallets: [] })
    }
  },

  _filterSolanaWallets(allWallets) {
    // EVM wallets register solana:signMessage via Snaps but aren't real Solana wallets
    const evmBlocklist = ["metamask", "rabby", "coinbase wallet", "rainbow"]
    return allWallets.filter(w => {
      if (!w.features) return false
      if (!(w.features["solana:signMessage"] || w.features["standard:connect"])) return false
      if (evmBlocklist.includes(w.name.toLowerCase())) return false
      return true
    })
  },

  _pushWallets() {
    const seen = new Set()
    const walletInfos = []
    for (const w of this._wallets) {
      if (!seen.has(w.name)) {
        seen.add(w.name)
        walletInfos.push({ name: w.name, icon: w.icon, detected: true })
      }
    }
    this.pushEvent("wallets_detected", { wallets: walletInfos })

    if (this._autoReconnectPending) {
      this._autoReconnectPending = false
      this._tryAutoReconnect()
    }
  },

  async _handleConnect({ wallet_name }) {
    const wallet = this._wallets.find(w => w.name === wallet_name)
    if (!wallet) {
      this.pushEvent("wallet_error", { error: `Wallet "${wallet_name}" not found` })
      return
    }

    try {
      const connectFeature = wallet.features["standard:connect"]
      const result = await connectFeature.connect()
      const account = result.accounts[0]
      if (!account) {
        this.pushEvent("wallet_error", { error: "No accounts returned" })
        return
      }

      this._connectedWallet = wallet
      this._connectedAccount = account
      window.__solanaWallet = wallet
      installWalletStandardSigner({ wallet, account, chain: CHAIN })
      this._subscribeWalletEvents(wallet)

      // Do NOT write localStorage here — wait for persist_session (after SIWS verification)
      this.pushEvent("wallet_connected", {
        pubkey: account.address,
        wallet_name: wallet.name,
      })
    } catch (e) {
      console.error("SolanaWallet: connect failed", e)
      this.pushEvent("wallet_error", { error: e.message || "Connection rejected" })
    }
  },

  // Subscribe to the wallet's `standard:events` so we get notified when the
  // user switches accounts inside the wallet extension (Phantom etc.) or when
  // they revoke authorization. The wallet emits a `change` event with the
  // properties that changed (accounts, chains, features).
  _subscribeWalletEvents(wallet) {
    if (this._unsubscribeAccountChange) {
      try { this._unsubscribeAccountChange() } catch (_) {}
      this._unsubscribeAccountChange = null
    }

    const eventsFeature = wallet.features?.["standard:events"]
    if (!eventsFeature || typeof eventsFeature.on !== "function") return

    try {
      this._unsubscribeAccountChange = eventsFeature.on("change", (props) => {
        // Only react to account changes — ignore chain/feature changes
        if (!props || !("accounts" in props)) return

        const newAccount = (props.accounts || [])[0]
        if (!newAccount) {
          // Wallet revoked all accounts → user disconnected from extension
          this._handleExternalDisconnect()
          return
        }

        if (!this._connectedAccount || newAccount.address !== this._connectedAccount.address) {
          this._handleAccountChange(newAccount)
        }
      })
    } catch (e) {
      console.warn("SolanaWallet: failed to subscribe to wallet events", e)
    }
  },

  // Helper: read the wallet's current first account directly from the wallet
  // object (used by the visibilitychange path to detect background switches)
  _currentWalletAccount() {
    if (!this._connectedWallet) return null
    try {
      const accounts = this._connectedWallet.accounts || []
      return accounts[0] || null
    } catch (_) {
      return null
    }
  },

  // User switched accounts inside their wallet extension. Treat this as a
  // fresh sign-in for the new pubkey: clear the stale session, update local
  // state, and push wallet_connected so the server kicks off a new SIWS.
  _handleAccountChange(newAccount) {
    this._connectedAccount = newAccount
    // Re-install the signer against the new account so downstream calls
    // sign with the correct key.
    installWalletStandardSigner({
      wallet: this._connectedWallet,
      account: newAccount,
      chain: CHAIN,
    })
    try {
      // Stale localStorage points at the old pubkey — wipe it so a refresh
      // doesn't auto-reconnect to the wrong account
      localStorage.removeItem(STORAGE_KEY)
    } catch (_) {}
    // Tell server to clear its session for the previous wallet
    this._clearSession()
    // Then start a fresh SIWS for the new account
    this.pushEvent("wallet_connected", {
      pubkey: newAccount.address,
      wallet_name: this._connectedWallet.name,
    })
  },

  // Wallet extension revoked authorization while we still thought we were
  // connected. Mirror a normal disconnect on both client and server.
  _handleExternalDisconnect() {
    this._connectedWallet = null
    this._connectedAccount = null
    window.__solanaWallet = null
    clearSigner()
    if (this._unsubscribeAccountChange) {
      try { this._unsubscribeAccountChange() } catch (_) {}
      this._unsubscribeAccountChange = null
    }
    try { localStorage.removeItem(STORAGE_KEY) } catch (_) {}
    this._clearSession()
    this.pushEvent("wallet_disconnected", {})
  },

  async _handleSign({ message, nonce }) {
    if (!this._connectedWallet) {
      this.pushEvent("wallet_error", { error: "No wallet connected" })
      return
    }

    try {
      const signFeature = this._connectedWallet.features["solana:signMessage"]
      const encodedMessage = new TextEncoder().encode(message)
      const result = await signFeature.signMessage({ message: encodedMessage, account: this._connectedAccount })
      const signatureBytes = result[0].signature
      const signatureB58 = bs58.encode(signatureBytes)

      this.pushEvent("signature_submitted", {
        signature: signatureB58,
        nonce: nonce,
      })
    } catch (e) {
      console.error("SolanaWallet: sign failed", e)
      this.pushEvent("wallet_error", { error: e.message || "Signing rejected" })
    }
  },

  async _handleDisconnect() {
    if (this._unsubscribeAccountChange) {
      try { this._unsubscribeAccountChange() } catch (_) {}
      this._unsubscribeAccountChange = null
    }
    if (this._connectedWallet) {
      try {
        const disconnectFeature = this._connectedWallet.features["standard:disconnect"]
        if (disconnectFeature) await disconnectFeature.disconnect()
      } catch (_) {}
    }
    this._connectedWallet = null
    this._connectedAccount = null
    window.__solanaWallet = null
    clearSigner()
    try { localStorage.removeItem(STORAGE_KEY) } catch (_) {}
    this.pushEvent("wallet_disconnected", {})
  },

  async _tryAutoReconnect() {
    let stored
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (!raw) return
      stored = JSON.parse(raw)
    } catch (_) { return }
    if (!stored?.name) return

    const wallet = this._wallets.find(w => w.name === stored.name)
    if (!wallet) return

    try {
      const connectFeature = wallet.features["standard:connect"]
      const result = await connectFeature.connect({ silent: true })
      const account = result.accounts[0]
      if (!account) return

      this._connectedWallet = wallet
      this._connectedAccount = account
      window.__solanaWallet = wallet
      installWalletStandardSigner({ wallet, account, chain: CHAIN })
      this._subscribeWalletEvents(wallet)

      if (account.address !== stored.address) {
        // User switched accounts in the wallet between page loads — treat as a
        // fresh sign-in (force SIWS for the new pubkey) instead of silent
        // reconnect, which would otherwise leave the server session pointing
        // at the previous wallet.
        try { localStorage.removeItem(STORAGE_KEY) } catch (_) {}
        this._clearSession()
        this.pushEvent("wallet_connected", {
          pubkey: account.address,
          wallet_name: wallet.name,
        })
        return
      }

      this.pushEvent("wallet_reconnected", {
        pubkey: account.address,
        wallet_name: wallet.name,
      })
    } catch (_) {
      try { localStorage.removeItem(STORAGE_KEY) } catch (_) {}
    }
  },

  async _discoverAndConnect() {
    try {
      const { get } = getWallets()
      const wallets = this._filterSolanaWallets(get())
      this._wallets = wallets
      this._pushWallets()

      if (wallets.length === 1) {
        await this._handleConnect({ wallet_name: wallets[0].name })
      } else {
        this.pushEvent("open_wallet_modal", {})
      }
    } catch (e) {
      this.pushEvent("wallet_error", { error: "Failed to detect wallets" })
    }
  },

  // Mirror of _persistSession for the Web3Auth path. The SolanaWallet hook
  // owns this handler (not the Web3Auth hook) so the existing
  // session_persisted chain in wallet_auth_events stays unified — one
  // hook responsible for all session cookie writes, no split-brain.
  async _persistWeb3AuthSession({ wallet_address, id_token, provider }) {
    let isNewUser = false
    // When the server matches by email into an existing user (legacy EVM
    // reclaim, or an active Solana user who linked email earlier), the
    // session ends up keyed on a DIFFERENT wallet than the Web3Auth-derived
    // pubkey. The UI + LiveView assigns must use the server's canonical
    // wallet_address — that's what has the BUX balances, stats, etc.
    let sessionWallet = wallet_address
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    if (csrf && id_token && wallet_address) {
      try {
        const resp = await fetch("/api/auth/web3auth/session", {
          method: "POST",
          headers: { "content-type": "application/json", "x-csrf-token": csrf },
          // Include provider so the server can set the correct auth_method.
          // Web3Auth's JWT does NOT carry an `authConnection` claim — the
          // server can't reliably infer twitter/google/email from claims
          // alone, so it defaults to "web3auth_email" and mislabels non-email
          // logins. The client knows the provider exactly; trust it.
          body: JSON.stringify({ wallet_address, id_token, provider }),
        })
        if (resp.ok) {
          const json = await resp.json()
          isNewUser = !!json.is_new_user
          const serverWallet = json?.user?.wallet_address
          if (typeof serverWallet === "string" && serverWallet !== "") {
            sessionWallet = serverWallet
          }
        } else {
          const body = await resp.text().catch(() => "")
          this.pushEvent("web3auth_error", {
            error: `Server rejected session (${resp.status}): ${body.slice(0, 120)}`,
          })
          return
        }
      } catch (e) {
        this.pushEvent("web3auth_error", { error: `Network error: ${e?.message || e}` })
        return
      }
    }

    // Post-merge the server's canonical wallet_address should always match
    // the Web3Auth-derived pubkey (the reclaim flow rewrites wallet_address
    // to the new Solana pubkey), so no signer mismatch to worry about.
    // Defensive check: if somehow they differ, log so it's traceable.
    if (sessionWallet !== wallet_address) {
      console.warn(
        "[Web3Auth] Session wallet (" + sessionWallet + ") differs from derived " +
          "pubkey (" + wallet_address + "). Using session wallet for UI."
      )
    }

    this.pushEvent("web3auth_session_persisted", {
      wallet_address: sessionWallet,
      derived_pubkey: wallet_address,
      is_new_user: isNewUser,
      provider: provider || "email",
    })
  },

  async _persistSession(walletAddress) {
    if (this._connectedWallet) {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify({
          name: this._connectedWallet.name,
          address: walletAddress,
        }))
      } catch (_) {}
    }

    let isNewUser = false
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    if (csrf) {
      try {
        // AWAIT the fetch so the session cookie is guaranteed to be set
        // before the server fires `:wallet_authenticated` (which may
        // push_navigate to a new live_session). Otherwise the next page
        // load races the cookie write and current_user comes back nil.
        const resp = await fetch("/api/auth/session", {
          method: "POST",
          headers: { "content-type": "application/json", "x-csrf-token": csrf },
          body: JSON.stringify({ wallet_address: walletAddress }),
        })
        if (resp.ok) {
          const json = await resp.json()
          isNewUser = !!json.is_new_user
        }
      } catch (_) {}
    }
    this.pushEvent("session_persisted", { wallet_address: walletAddress, is_new_user: isNewUser })
  },

  _clearSession() {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    if (!csrf) return
    fetch("/api/auth/session", {
      method: "DELETE",
      headers: { "x-csrf-token": csrf },
    }).catch(() => {})
  },
}
