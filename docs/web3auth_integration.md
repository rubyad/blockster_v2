# Web3Auth Integration Reference

Canonical technical reference for Web3Auth v10 Modal + Solana in Blockster V2. Derived from the Phase 0 prototype (2026-04-20, `/dev/test-web3auth`).

**Scope:** client-side SDK integration. For backend JWT verification, see `lib/blockster_v2/auth/web3auth_signing.ex` (our Telegram JWT issuer) and the forthcoming Phase 3 `Auth.Web3Auth` module (verifier for Web3Auth-issued tokens).

---

## Quick facts

- **SDK:** `@web3auth/modal` v10.x (not `@web3auth/no-modal`; modal includes the no-modal core via subclassing).
- **Network:** `SAPPHIRE_DEVNET` for dev/staging, `SAPPHIRE_MAINNET` for prod (switch via `web3AuthNetwork` constructor option).
- **Chain:** Solana via `chainNamespace: "solana"`. After login, Web3Auth's AUTH connector returns a **`ws-embed`** provider (Web3Auth wallet services iframe) — NOT the `SolanaPrivateKeyProvider` from `@web3auth/solana-provider`. This distinction is load-bearing for everything below.

---

## 1. Chain ID convention (NOT what the docs imply)

`ws-embed` uses its own Solana chainId constants — different from the `0x1/0x2/0x3` most docs and tutorials show:

| Network | ws-embed chainId |
|---|---|
| Solana Mainnet | `0x65` |
| Solana Testnet | `0x66` |
| **Solana Devnet** | **`0x67`** |

Using `0x3` (which appears in Web3Auth's public Solana docs) routes the AUTH connector down paths that aren't fully initialized for Solana and causes `requestAccounts` to fail with "Method not found" or the provider to come back null.

**Source:** `node_modules/@web3auth/ws-embed/dist/lib.cjs/types/constants.d.ts → SOLANA_CHAIN_IDS`.

---

## 2. RPC method names

ws-embed's provider implements Solana RPC via **prefixed method names**, not the bare names that `@web3auth/solana-provider`'s `SolanaWallet` helper uses:

| What you want | ws-embed method |
|---|---|
| Get connected pubkey | `solana_requestAccounts` |
| Sign raw message | `solana_signMessage` |
| Sign transaction only | `solana_signTransaction` |
| Sign + broadcast | `solana_sendTransaction` |
| Export derived privkey | `solana_privateKey` |
| Export derived pubkey | `solana_publicKey` |

**Source:** `node_modules/@web3auth/ws-embed/dist/lib.cjs/types/constants.d.ts → SOLANA_METHOD_TYPES`.

---

## 3. What NOT to do

### ❌ Don't use `SolanaWallet` from `@web3auth/solana-provider`

Its `requestAccounts()` calls `provider.request({ method: "requestAccounts" })` (bare, no prefix). ws-embed doesn't recognize that — returns "Method not found". The helper is built for `SolanaPrivateKeyProvider`, which is a **different, mutually-exclusive** integration path.

### ❌ Don't pass `privateKeyProvider: new SolanaPrivateKeyProvider(...)` to the `Web3Auth` constructor for Solana

v10's AUTH connector's `init()` respects that flag and skips ws-embed initialization, but its `connect()` path unconditionally tries `wsEmbedInstance.loginWithSessionId()` for `chainNamespace: "solana"`. Result: null deref at first login attempt. The two paths don't compose.

### ❌ Don't call `prompt()` / `alert()` before `web3auth.connectTo()`

Web3Auth opens a popup inside `connectTo()`. `prompt()` breaks the browser's user-gesture chain, so the popup gets blocked with `"popup window is blocked"`. Use inline form inputs (`<input type="email">`) so the click handler → `connectTo()` sequence stays synchronous from the browser's perspective.

### ❌ Don't rely on `Buffer` / `process` being defined in the browser

Web3Auth's transitive deps (`@toruslabs/eccrypto`, etc.) reference Node globals directly. Esbuild doesn't auto-polyfill. Create `assets/js/polyfills.js`:

```js
import { Buffer } from "buffer"
import process from "process"
const g = typeof globalThis !== "undefined" ? globalThis : window
if (typeof g.Buffer === "undefined") g.Buffer = Buffer
if (typeof g.process === "undefined") g.process = process
if (typeof g.global === "undefined") g.global = g
```

…and make it the **first** import in `app.js`. Top-level assignments directly in `app.js` don't work because ES imports hoist — Web3Auth's chain initializes before inline top-level code runs.

### ⚠️ Don't trust `getUserInfo()` to succeed on Solana-only sessions

Web3Auth v10's `getUserInfo()` routes through an internal Ethereum controller that polls EVM blocks. On a Solana-only chain config it throws `Method not found` on the post-login polling loop. The JWT (`idToken`), email, and verifier fields are still populated — just wrap `getUserInfo()` in try/catch and treat failures as benign. See the prototype hook's `_showAccount()` for the pattern.

---

## 4. The signing pattern we use

**Pull the derived private key on demand, sign locally, zero the buffer.** Validated in Phase 0; the production Phase 5 hook follows the same shape.

```js
async function fetchKeypair(provider) {
  const raw = await provider.request({ method: "solana_privateKey" })
  const secret = decodeSecret(raw) // handles hex / base58 / base64
  return secret.length === 64
    ? Keypair.fromSecretKey(secret)
    : Keypair.fromSeed(secret)
}

async function signSomething(provider, payload) {
  const kp = await fetchKeypair(provider)
  try {
    return doWork(kp, payload)
  } finally {
    kp.secretKey.fill(0) // zero the buffer — best-effort, not a security guarantee
  }
}
```

### Why we pull the key instead of using iframe signing

Pragmatism: ws-embed's `solana_signMessage` / `solana_signTransaction` have fragile param shapes that varied under Phase 0 experimentation ("Invalid message 'data': undefined", "Reached end of buffer", "MessageController: key does not exist" all hit us with slightly different payload formats). The iframe also cannot satisfy the Phase 1 UX guarantee (one-click bets, no popups) because its confirmation layer gates tx signing.

Key-export + local signing sidesteps all of it. Magic Eden, Drift, and several other Solana apps use this exact pattern with Web3Auth.

### Why we fetch per-operation instead of caching

Defense in depth against XSS. The key is only in memory for the few ms of each sign call. Caching would leave it sitting in a closure for the whole session. Neither approach protects against full-page compromise — if JS runs in our origin, it can call either the cached key OR call `provider.request({method: "solana_privateKey"})` itself — but per-op fetch keeps the window tighter. User (Adam) requested this pattern explicitly.

**Implementation note on the return format:** `solana_privateKey` has returned the 32-byte seed as hex (64 chars), base58 (43-44 chars), or base64 across our observations. Always run through format detection — see `test_web3auth.js → decodeSecret`.

---

## 5. Login parameter shapes per provider

All via `web3auth.connectTo(WALLET_CONNECTORS.AUTH, loginParams)`:

| Provider | loginParams |
|---|---|
| Email passwordless | `{ authConnection: AUTH_CONNECTION.EMAIL_PASSWORDLESS, extraLoginOptions: { login_hint: email } }` |
| Google | `{ authConnection: AUTH_CONNECTION.GOOGLE }` |
| Apple | `{ authConnection: AUTH_CONNECTION.APPLE }` (requires Apple Developer `services.plist` in the dashboard) |
| X (Twitter) | `{ authConnection: AUTH_CONNECTION.TWITTER }` |
| Telegram (custom JWT) | `{ authConnection: AUTH_CONNECTION.CUSTOM, authConnectionId: <dashboard verifier name>, extraLoginOptions: { id_token, verifierIdField: "sub" } }` |

Imports:
```js
import { WALLET_CONNECTORS } from "@web3auth/modal"
import { AUTH_CONNECTION } from "@web3auth/auth"
```

---

## 6. Web3Auth's ID token format (for backend verification)

After login, `web3auth.getUserInfo()` returns `{ idToken, email, name, verifier, authConnection, oAuthAccessToken, ... }`. The `idToken` is a JWT:

- **Algorithm:** ES256 (ECDSA P-256).
- **Issuer:** `https://api-auth.web3auth.io` (Sapphire Devnet and Sapphire Mainnet share the same issuer).
- **JWKS endpoint:** `https://api-auth.web3auth.io/jwks` — fetch + cache for Phase 3 backend verification.
- **Audience (`aud`):** matches our `WEB3AUTH_CLIENT_ID`.
- **Claims of interest:** `email`, `name`, `verifier`, `verifierId`, `authConnection`, `userId`, `aggregateVerifier`, `wallets` (array of per-curve pubkeys including the ed25519 one for Solana), `iat`, `exp`, `nonce`.

**Important:** this is distinct from our own Telegram-JWT JWKS at `/.well-known/jwks.json` (RS256, issuer `blockster`), which Web3Auth's dashboard verifier consumes to validate Telegram logins. Two JWKS flows in opposite directions:

- **Web3Auth → us:** Phase 3 backend fetches `api-auth.web3auth.io/jwks` to verify session tokens clients pass in.
- **Us → Web3Auth:** Web3Auth's Custom JWT connector fetches our `/.well-known/jwks.json` to verify the Telegram JWTs we issue.

---

## 7. Dashboard setup (confirmed working)

Sapphire Devnet project (https://dashboard.web3auth.io/):

1. **Create project** — pick "Plug and Play" type, Sapphire Devnet network.
2. **Add Solana chain** — via "Chains" section. The dashboard infers the chainId from the namespace; we don't have to type `0x67` there.
3. **Whitelist URLs** — `http://localhost:4000` for dev, `https://blockster.com` for prod.
4. **Connections** — enable Email Passwordless, Google, X (Twitter). Apple optional (needs Apple Developer config). These are usually on by default.
5. **Custom JWT connection for Telegram** (optional, can defer to production):
   - Verifier name: `blockster-telegram` (this is the string for `WEB3AUTH_TELEGRAM_VERIFIER_ID` env var).
   - JWKS endpoint: `https://<our-domain>/.well-known/jwks.json`. Localhost URLs are rejected by Web3Auth's "validate endpoint" check — use a Cloudflare tunnel (`cloudflared tunnel --url http://localhost:4000`) in dev.
   - JWT verifier ID field: `sub`
   - `aud`: `blockster-web3auth`
   - `iss`: `blockster`
   - Algorithm: `RS256`

After saving, the dashboard assigns a canonical Verifier ID. It's usually just the verifier name, but if the dashboard shows something else (like `w3a-<hash>`), use that exact string in `WEB3AUTH_TELEGRAM_VERIFIER_ID`.

---

## 8. Deterministic wallet derivation per identity

Each social identity produces a **stable, deterministic Solana pubkey** — same login → same pubkey, every time. Per the Phase 0 prototype:

| Identity | Pubkey |
|---|---|
| Email: `adam@blockster.com` | `FUWYT33RLgmCtGsSHvtv2avKLpDFovFDQSnuGjN5wDyP` |
| Google: `fukthecftc@gmail.com` | `9JvwWzS92SoJR3SPkJiNW1ZsQgkWAYRgryHcobfFeZXx` |
| X: `@adam_todd` (user id 1831802560593661952) | `DWY2b8csW3zMnLAso9Aijw7JEuDAGSshnBhrCCKKN5Ua` |

Implication: one user, multiple identities = **multiple wallets**. Our plan treats them as separate accounts (per `lib/blockster_v2/accounts/user.ex:auth_method`). v2 may add linking; v1 does not.

---

## 9. Browser storage + session semantics

- `storageType: "session"` (constructor option) is recommended during development — clears Web3Auth state on tab close, avoiding stale "Already connected" rehydration errors. Prod can use `"local"` for persistent SSO-style sessions, but must coordinate with our own session cookie lifecycle so the two don't drift.
- Before calling `connectTo()`, always check `web3auth.connected` and call `web3auth.logout()` if true. Skipping this step throws `WalletLoginError: Already connected`.
- On `init()`, rehydration only succeeds if `web3auth.connected === true` AND `web3auth.provider !== null`. A session that rehydrated with a null provider crashes `requestAccounts` — check both before acting.

---

## 10. Known rough edges

- **"Method not found" spam in the console** — Web3Auth's Ethereum controller polls EVM blocks even on Solana-only sessions. Harmless, but noisy. No known workaround short of forking ws-embed.
- **403 on `api-wallet.web3auth.io/user?fetchTx=false`** — post-login wallet sync endpoint, EVM-oriented. Does not block Solana functionality. Harmless.
- **SDK bundle size** — ~7MB compressed, inflates `app.js` from ~5MB to ~12.5MB. Phase 5 will lazy-load the Web3Auth hook to cut the default bundle weight; don't eagerly import on every page.
- **Popup blocking on first login** — covered above (§3). First-time users may still need to allow popups for our origin in Chrome's address bar.

---

## 11. Wallet Standard quirks (confirmed empirically against Phantom 2026-04-20)

These aren't Web3Auth-specific — they apply to any multi-signer Solana flow through Wallet Standard wallets. Came up during Phase 4 rent_payer rollout; documenting here because Phase 5+ will keep hitting them.

### Phantom's `signAndSendTransaction` strips foreign partial signatures

If you hand Phantom a tx that has a pre-applied signature from an account Phantom doesn't control (e.g., settler partial-signing as rent_payer), Phantom calls the RPC's `signAndSendTransaction` with a re-serialized tx that drops those sigs. Chain rejects with signature verification failure. Phantom surfaces this as "Unexpected error" rather than the underlying RPC error, which makes it near-impossible to diagnose without reading the actual tx bytes.

**Use `signTransaction` instead** for any multi-signer tx.

### Phantom's `signTransaction` silently submits the tx

Violates Wallet Standard spec (which says sign-only) but is observable empirically. After `signTransaction` returns, the tx is already on chain. A naive follow-up `sendRawTransaction` trips "Transaction has already been processed".

**Handle in client code:** check `getSignatureStatus` on the extracted sig before submitting yourself. OR attempt `sendRawTransaction` with `skipPreflight: true` and swallow specific duplicate-submission error strings (`/already been processed/i`, `/already in flight/i`, `/AlreadyProcessed/i`). `assets/js/hooks/signer.js → signAndConfirm` does this.

### Phantom rejects txs where fee_payer is NOT the connected wallet

Even with pre-applied signatures from the true fee_payer, Phantom's security/UX model assumes "you pay the fee." If `tx.feePayer !== wallet.account`, Phantom returns "Unexpected error" at sign time without surfacing a useful reason.

**Implication:** you can't deliver zero-SOL UX to a Wallet Standard user by having the settler pay the fee. The user must have enough SOL to cover ~5000 lamports priority fee. This is the structural reason Phase 5 Web3Auth users get a different signing path (local sign from exported key) — Web3Auth doesn't have this UX invariant.

### Anchor account order = wire order. Always.

When you add a new account to an Anchor struct (e.g., `rent_payer` in Phase 1), the TypeScript tx-builder must insert it at the EXACT same position. Anchor reads accounts positionally, not by name. Wrong position → the account you intended as `rent_payer` arrives in the position expecting `game_registry` → ownership check fails (system-owned wallet vs bankroll-owned state account) → `Custom(3007) AccountOwnedByWrongProgram`.

When adding accounts to existing instructions: `grep` the TS tx-builder, make sure every position matches the Rust struct top-to-bottom.

## 12. File-level implementation map

| Path | Role |
|---|---|
| `assets/js/polyfills.js` | Node-global shims (Buffer, process, global). Must be first import. |
| `assets/js/hooks/test_web3auth.js` | **Throwaway** Phase 0 prototype hook — reference implementation. Removed once Phase 5 ships. |
| `assets/js/hooks/web3auth_hook.js` | **Not yet created** (Phase 5). Production hook, registers `window.__signer`. |
| `assets/js/hooks/signer.js` | **Not yet created** (Phase 2). Unified signer interface abstracting wallet-standard vs Web3Auth. |
| `lib/blockster_v2/auth/web3auth_signing.ex` | Our JWT issuer for Telegram (RS256, JWKS at `/.well-known/jwks.json`). |
| `lib/blockster_v2/auth/web3auth.ex` | **Not yet created** (Phase 3). Verifier for Web3Auth-issued ID tokens (ES256, JWKS fetched from `api-auth.web3auth.io/jwks`). |
| `lib/blockster_v2_web/controllers/auth_controller.ex` | `POST /api/auth/telegram/verify`, `GET /.well-known/jwks.json`, Phase 3 adds `POST /api/auth/web3auth/session`. |
| `lib/blockster_v2_web/live/test_web3auth_live.ex` | **Throwaway** Phase 0 test page, removed post-Phase-5. |
