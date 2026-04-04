// SolanaWallet hook — wallet detection, connect, sign, disconnect
// Ported from RogueTrader/FateSwap with Blockster branding

import { getWallets } from "@wallet-standard/app"
import bs58 from "bs58"

const STORAGE_KEY = "blockster_wallet"

export const SolanaWallet = {
  mounted() {
    // Clear legacy EVM localStorage on first load
    try {
      localStorage.removeItem("walletAddress")
      localStorage.removeItem("smartAccountAddress")
    } catch (_) {}

    this._wallets = []
    this._connectedWallet = null
    this._autoReconnectPending = true

    this._discoverWallets()

    this.handleEvent("request_connect", (payload) => this._handleConnect(payload))
    this.handleEvent("request_sign", (payload) => this._handleSign(payload))
    this.handleEvent("request_disconnect", () => this._handleDisconnect())
    this.handleEvent("persist_session", ({ wallet_address }) => this._persistSession(wallet_address))
    this.handleEvent("clear_session", () => this._clearSession())
    this.handleEvent("discover_and_connect", () => this._discoverAndConnect())

    this._onVisibility = () => {
      if (document.visibilityState !== "visible") return
      if (this._connectedWallet && this._connectedAccount) {
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
    if (this._connectedWallet) {
      try {
        const disconnectFeature = this._connectedWallet.features["standard:disconnect"]
        if (disconnectFeature) await disconnectFeature.disconnect()
      } catch (_) {}
    }
    this._connectedWallet = null
    this._connectedAccount = null
    window.__solanaWallet = null
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

      if (account.address !== stored.address) {
        try {
          localStorage.setItem(STORAGE_KEY, JSON.stringify({
            name: wallet.name,
            address: account.address,
          }))
        } catch (_) {}
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

  _persistSession(walletAddress) {
    if (this._connectedWallet) {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify({
          name: this._connectedWallet.name,
          address: walletAddress,
        }))
      } catch (_) {}
    }

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    if (!csrf) return
    fetch("/api/auth/session", {
      method: "POST",
      headers: { "content-type": "application/json", "x-csrf-token": csrf },
      body: JSON.stringify({ wallet_address: walletAddress }),
    }).catch(() => {})
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
