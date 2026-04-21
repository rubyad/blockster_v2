// Unified signing interface for Solana transactions + messages.
//
// The source (wallet-standard, web3auth) installs itself on login and clears
// on disconnect. Consumers call `window.__signer.signTransaction(...)` or
// `signMessage(...)` without caring which source they got.
//
// Post-Phase-1 (settler-as-rent_payer), the settler partially-signs txs
// before returning them to the client. Consumers MUST use `signTransaction`
// + `sendRawTransaction` (not `signAndSendTransaction`) so the wallet layers
// its signature on top of existing ones without nuking them.
//
// Interface:
//   window.__signer = {
//     pubkey: string,                             // base58 Solana pubkey
//     source: "wallet-standard" | "web3auth",
//     signMessage(bytes: Uint8Array)              → Uint8Array (ed25519 sig)
//     signTransaction(txBytes: Uint8Array)        → Uint8Array (fully-signed tx)
//     signAndSendTransaction(txBytes, opts?)      → { signature: Uint8Array }
//     disconnect()                                → void
//   }

export function getSigner() {
  return typeof window !== "undefined" ? window.__signer || null : null
}

// Block until a signer is available (or timeout). Used by hooks that mount
// before wallet connect completes and want to race safely.
export async function waitForSigner(timeoutMs = 5000) {
  if (typeof window === "undefined") return null
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (window.__signer) return window.__signer
    await new Promise((r) => setTimeout(r, 50))
  }
  return window.__signer || null
}

// Install the Wallet Standard adapter. Called from solana_wallet.js on
// successful connect / silent reconnect. The adapter closes over the wallet
// + account objects so we don't re-query features on every sign.
export function installWalletStandardSigner({ wallet, account, chain }) {
  if (typeof window === "undefined") return

  const pickFeature = (name) => {
    const feature = wallet.features?.[name]
    if (!feature) {
      throw new Error(
        `wallet "${wallet.name}" does not support ${name} — update your wallet or use a different one`,
      )
    }
    return feature
  }

  window.__signer = {
    pubkey: account.address,
    source: "wallet-standard",
    wallet, // kept for legacy debugging; do not rely on this in app code

    async signMessage(bytes) {
      const feature = pickFeature("solana:signMessage")
      const result = await feature.signMessage({ account, message: bytes })
      return result[0].signature
    },

    async signTransaction(txBytes) {
      const feature = pickFeature("solana:signTransaction")
      const result = await feature.signTransaction({
        account,
        transaction: txBytes,
        chain,
      })
      return result[0].signedTransaction
    },

    async signAndSendTransaction(txBytes, opts = {}) {
      const feature = pickFeature("solana:signAndSendTransaction")
      const [{ signature }] = await feature.signAndSendTransaction({
        account,
        transaction: txBytes,
        chain: opts.chain || chain,
      })
      return { signature }
    },

    async disconnect() {
      const feature = wallet.features?.["standard:disconnect"]
      if (feature) {
        try {
          await feature.disconnect()
        } catch (_) {}
      }
    },
  }
}

export function clearSigner() {
  if (typeof window !== "undefined") window.__signer = null
}

// Shared confirmation poller. Previously duplicated in coin_flip_solana.js —
// now single source. Uses `getSignatureStatuses` as mandated by CLAUDE.md
// (never `confirmTransaction` which relies on websockets).
export async function pollForConfirmation(
  connection,
  signature,
  { timeoutMs = 60000, intervalMs = 400 } = {},
) {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) {
    const response = await connection.getSignatureStatuses([signature])
    const status = response?.value?.[0]
    if (status) {
      if (status.err) {
        throw new Error(
          `Transaction failed on-chain: ${JSON.stringify(status.err)}`,
        )
      }
      if (
        status.confirmationStatus === "confirmed" ||
        status.confirmationStatus === "finalized"
      ) {
        return signature
      }
    }
    await new Promise((r) => setTimeout(r, intervalMs))
  }
  throw new Error("Transaction confirmation timed out. Refresh and try again.")
}

// Convenience: decode a base64-encoded tx (which is how the settler ships
// unsigned/partially-signed txs to the client) into raw bytes.
export function decodeBase64Tx(base64) {
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))
}

// Sign a tx, submit it, poll for confirmation. Returns the base58 signature.
//
// Why this is more complex than it looks:
//   * Wallet Standard's `solana:signAndSendTransaction` appears to silently
//     strip pre-applied partial sigs from accounts the wallet doesn't
//     control (Phantom observed), returning "Unexpected error". Our
//     settler-as-rent_payer txs rely on a pre-applied sig so that path is
//     unusable.
//   * `solana:signTransaction` works, BUT Phantom (at least) ALSO submits
//     the tx internally during signing. A naive `sendRawTransaction`
//     afterwards trips "Transaction has already been processed".
//   * So we: sign → read signature 0 from the returned bytes → check if the
//     tx is already in-flight → only submit ourselves if it's not.
//   * Any submission error whose message doesn't indicate a duplicate is
//     re-raised so callers see real problems.
export async function signAndConfirm(signer, connection, txBytes) {
  const [{ Transaction }, bs58Mod] = await Promise.all([
    import("@solana/web3.js"),
    import("bs58"),
  ])
  const bs58 = bs58Mod.default

  const signedBytes = await signer.signTransaction(txBytes)

  // Decode the signed tx to read signature 0 (the fee-payer sig, i.e. the
  // canonical tx signature).
  const signedTx = Transaction.from(signedBytes)
  if (!signedTx.signature || signedTx.signature.length !== 64) {
    throw new Error(
      "Signed transaction has no fee-payer signature — wallet may have rejected it",
    )
  }
  const sig = bs58.encode(signedTx.signature)

  // Check if the wallet already submitted. Phantom does this; Solflare may
  // or may not; Backpack behavior observed elsewhere. Best to look first.
  let alreadyInFlight = false
  try {
    const status = await connection.getSignatureStatus(sig, {
      searchTransactionHistory: false,
    })
    if (status?.value) alreadyInFlight = true
  } catch (_) {
    // If the status lookup fails, proceed to submit — worst case we trip
    // the duplicate-handling path below.
  }

  if (!alreadyInFlight) {
    try {
      await connection.sendRawTransaction(signedBytes, {
        skipPreflight: true, // preflight would simulate the already-submitted tx and fail
        maxRetries: 5,
      })
    } catch (err) {
      const msg = err?.message || String(err)
      const duplicate =
        /already been processed/i.test(msg) ||
        /already in flight/i.test(msg) ||
        /AlreadyProcessed/i.test(msg)

      if (!duplicate) {
        // Real failure — re-raise so the caller's error surfaces accurately.
        throw err
      }
      // Duplicate: the wallet submitted it first, we'll poll for confirmation.
    }
  }

  await pollForConfirmation(connection, sig)
  return sig
}
