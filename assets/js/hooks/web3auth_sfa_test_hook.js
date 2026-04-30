// Phase 0 parity test hook for the Web3Auth SFA mobile migration.
//
// Reads JWT + verifier config from data attributes, calls
// @toruslabs/customauth's getTorusKey (the SFA-equivalent entrypoint —
// pure HTTPS, no iframe, no ws-embed, no service worker), derives the
// Solana pubkey, and pushes it back to the LiveView for comparison
// against the user's stored wallet_address.
//
// See docs/web3auth_sfa_migration.md for the full plan and decision gate.

import { Keypair } from "@solana/web3.js";

let _customAuthCtor = null;

async function loadCustomAuth() {
  if (_customAuthCtor) return _customAuthCtor;
  const mod = await import("@toruslabs/customauth");
  _customAuthCtor = mod.CustomAuth || mod.default || mod;
  return _customAuthCtor;
}

function hexToBytes(hex) {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  const padded = clean.length % 2 === 1 ? "0" + clean : clean;
  const out = new Uint8Array(padded.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(padded.substring(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function deriveKeypair(privKeyHex) {
  const bytes = hexToBytes(privKeyHex);
  if (bytes.length === 32) return Keypair.fromSeed(bytes);
  if (bytes.length === 64) return Keypair.fromSecretKey(bytes);
  throw new Error(`Unexpected privKey byte length: ${bytes.length}`);
}

function extractPrivKey(result) {
  if (!result) return null;
  return (
    result?.finalKeyData?.privKey ||
    result?.privKey ||
    result?.ed25519PrivKey ||
    null
  );
}

export const Web3AuthSfaTest = {
  mounted() {
    this._lastIdToken = null;
    this.runTest();
  },

  updated() {
    this.runTest();
  },

  destroyed() {
    this._lastIdToken = null;
  },

  async runTest() {
    const idToken = this.el.dataset.idToken;
    const verifier = this.el.dataset.verifier;
    const verifierId = this.el.dataset.verifierId;
    const clientId = this.el.dataset.clientId;
    const network = this.el.dataset.network || "sapphire_mainnet";

    if (!idToken || !verifier || !verifierId || !clientId) return;
    if (this._lastIdToken === idToken) return;
    this._lastIdToken = idToken;

    let keypairBytes = null;
    try {
      const CustomAuth = await loadCustomAuth();

      const customAuth = new CustomAuth({
        baseUrl: window.location.origin,
        network,
        web3AuthClientId: clientId,
        keyType: "ed25519",
        enableLogging: false,
      });

      await customAuth.init({ skipSw: true, skipInit: true });

      const result = await customAuth.getTorusKey({
        authConnectionId: verifier,
        userId: verifierId,
        idToken,
      });

      const privKeyHex = extractPrivKey(result);

      if (!privKeyHex) {
        const sample = (() => {
          try {
            return JSON.stringify(Object.keys(result || {}));
          } catch (_) {
            return "<unavailable>";
          }
        })();
        this.pushEvent("sfa_derived_pubkey", {
          error: `No privKey in result. Top-level keys: ${sample}`,
        });
        return;
      }

      const keypair = deriveKeypair(privKeyHex);
      keypairBytes = keypair.secretKey;
      const address = keypair.publicKey.toBase58();
      this.pushEvent("sfa_derived_pubkey", { address });
    } catch (err) {
      const msg = err?.message || String(err);
      this.pushEvent("sfa_derived_pubkey", { error: msg });
    } finally {
      if (keypairBytes && typeof keypairBytes.fill === "function") {
        try {
          keypairBytes.fill(0);
        } catch (_) {
          /* ignore */
        }
      }
    }
  },
};
