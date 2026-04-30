# Web3Auth SFA Mobile Migration Plan

**Status:** Draft — pending Phase 0 results
**Date:** 2026-04-29
**Author:** Claude + Adam
**SDK swap:** `@web3auth/modal@10.15` (current, iframe-based) → `@web3auth/single-factor-auth` / `@toruslabs/customauth` (target, pure HTTPS, no iframe)
**Scope:** mobile login first, desktop conditional on Phase 0 outcome

---

## 0. Executive Summary

Web3Auth social login (email OTP, Telegram, X, Google, Apple) launched 2026-04-28 alongside Solana mainnet. Desktop works. **iOS Safari mobile is broken at the MPC handshake step** for all five flows. Root cause confirmed in source: iOS Safari ITP blocks cross-origin iframes from accessing their own first-party storage. `@web3auth/modal` runs the `Auth` instance in `SDK_MODE.IFRAME`, embedding `web3auth.io` as a hidden iframe. The MPC share lives in web3auth.io's storage. The iframe can't read it under ITP.

Switching to `@web3auth/no-modal` does NOT fix this — verified by reading the source: both SDKs hard-code `sdkMode: SDK_MODE.IFRAME` in `AuthConnector` and route `connectWithJwtLogin` exclusively through `postLoginInitiatedMessage`, which throws in non-IFRAME mode. Plus `@web3auth/ws-embed` injects its own iframe at `embed.js:167` regardless of which SDK loads it.

**`@web3auth/single-factor-auth` (SFA) is iframe-free.** It's a thin wrapper over `@toruslabs/customauth` (already in our `node_modules` as a transitive dep). It hits Torus DKG nodes via pure HTTPS, no iframe, no postMessage, no service worker required (`{skipSw: true, skipInit: true}`). For the same `(verifier, sub)` tuple, it should derive the same secp256k1 DKG output as modal — but the **ed25519 derivation path** differs subtly between SDKs and could produce a different Solana pubkey. That's the single open risk.

This plan ships SFA on mobile first, parallel to the working desktop modal path. Phase 0 (admin-only parity test) confirms whether SFA-derived pubkeys match modal-derived pubkeys for existing users. Phase 1 ships mobile SFA at 100% immediately because the current mobile flow is fully broken — gradual rollout buys nothing. Phase 2 is conditional: if Phase 0 confirmed parity, leave desktop on modal indefinitely (or migrate later for bundle savings). If Phase 0 reported mismatch, cut desktop over to SFA too — existing users (few — launched yesterday) get new pubkeys on next sign-in, reclaim flow merges legacy → new wallet via existing `Accounts.reclaim_legacy_via_web3auth/3`.

---

## 1. Architecture Decisions

### 1.1 Why SFA over alternative fixes

Three alternatives considered and rejected:

- **`@web3auth/no-modal`**: same iframe issue. Both SDKs share `AuthConnector` which hard-codes `sdkMode: SDK_MODE.IFRAME` (`assets/node_modules/@web3auth/no-modal/dist/lib.cjs/connectors/auth-connector/authConnector.js:88`). The DEFAULT-mode redirect path inside `Auth.login()` exists but is dead code from the connector's perspective.
- **`@web3auth/mpc-core-kit`**: bigger SDK swap, different signing semantics, almost certainly produces different Solana pubkeys (different MPC layer entirely).
- **Server-side proxy**: route Web3Auth calls through our backend to bypass ITP. Violates Web3Auth's threat model — we'd see user secrets transit our server. Rejected.

SFA wins because:
- Already in our dep tree as `@toruslabs/customauth@21.3.2` (transitive of `@web3auth/auth@10.15`). Zero new direct deps if we use customauth directly.
- Pure HTTPS. No iframe, no postMessage, no service worker.
- Same Sapphire Mainnet endpoints (`@toruslabs/constants/dist/lib.cjs/constants.js:12`).
- Same Torus DKG share retrieval (`@toruslabs/torus.js/dist/lib.cjs/torus.js:76` `Torus.retrieveShares`).
- Same verifier identifiers (`blockster-email`, `blockster-telegram`) — no Web3Auth dashboard reconfig.
- Server-side touches: zero. Same JWT signer, same refresh endpoint, same email OTP store, same Telegram callback, same reclaim function.

### 1.2 The pubkey-parity question

Two ed25519 derivation paths exist in the SDK universe:

- **Path A — `getED25519Key(secp_privkey)`**: derives ed25519 seed via SHA-512 + clamp (`assets/node_modules/@web3auth/auth/dist/lib.cjs/ed25519/utils.js:7-30`).
- **Path B — Torus `keyType: ED25519`**: fetches an ed25519 seed from a metadata server via `decryptSeedData(...)` (`@toruslabs/torus.js/dist/lib.cjs/helpers/nodeUtils.js:736-743`).

Modal/ws-embed handles `solana_privateKey` provider calls inside the auth.web3auth.io iframe — that code is not in our tree, so we cannot determine which path it takes from source alone. SFA caller controls `keyType`. **Path A and Path B almost certainly produce different Solana pubkeys for the same `(verifier, sub)`.**

This is why Phase 0 is non-negotiable. The test costs 1–2 hours and prevents shipping a wallet-incompatible login.

### 1.3 Mobile/desktop split strategy

Desktop modal works today; don't touch it. Mobile gets a new hook (`web3auth_sfa_hook.js`) and a new SDK path. Mount choice happens server-side in `wallet_components.ex` based on UA detection (iOS, Android). Both hooks expose the same `window.__signer` shape, so all downstream code (SolPaymentHook, SolanaBuxBurn, transaction builders, server-side reclaim) is unchanged.

---

## 2. Phase 0 — Parity Test

**Goal:** prove whether `(verifier, sub)` → SFA-derived Solana pubkey matches modal-derived Solana pubkey for an account already registered via desktop modal.

**Effort:** 1–2 hours. Admin-only, no user impact, no risk.

### 2.1 Files to create

1. `assets/js/hooks/web3auth_sfa_test_hook.js` (~80 lines) — minimal hook. Reads `id_token`, `verifier`, `verifier_id` from `data-*` attrs. Calls SFA (`getKey({...})` or `customauth.getTorusKey({...})`). Pushes derived `walletAddress` back via `pushEvent("sfa_derived_pubkey", {address})`.
2. `lib/blockster_v2_web/live/admin/web3auth_sfa_test_live.ex` (~120 lines) — admin LiveView with form: pick user by id or email, server mints test JWT via existing `BlocksterV2.Auth.Web3AuthSigning.sign_id_token/2` for that user's Web3Auth `sub` claim, render hook with JWT in data attrs, receive derived pubkey, compare to `user.wallet_address`, render match/mismatch.
3. `lib/blockster_v2_web/live/admin/web3auth_sfa_test_live.html.heex` — minimal admin UI. No design polish required.

### 2.2 Files to modify

1. `assets/package.json` — add `@web3auth/single-factor-auth` (run `npm view @web3auth/single-factor-auth peerDependencies` first to pick version compatible with `@web3auth/auth@10.15`). If alignment is messy, fall back to using `@toruslabs/customauth@21.3.2` directly (already in `node_modules` — zero new deps).
2. `assets/js/app.js` — register `Web3AuthSfaTest` hook.
3. `lib/blockster_v2_web/router.ex` — add `/admin/web3auth_sfa_test` under existing admin scope.

### 2.3 Test protocol

Run the parity test against 5–10 real accounts spanning the verifier set:
- 3 email accounts (`blockster-email` verifier).
- 2 Telegram accounts (`blockster-telegram` verifier).
- 1 X, 1 Google, 1 Apple (built-in OAuth verifiers, owned by Web3Auth).

For each account, the test page should display: `expected (current wallet_address)`, `derived (SFA-computed pubkey)`, `MATCH` or `MISMATCH`, plus the `keyType` flag used (we'll try `keyType: "ed25519"` first; if Torus rejects, try secp256k1 + Path A SHA-512 derivation in browser).

Record each result inline in this doc under §6 Results.

### 2.4 Decision gate

- **All match (every account, every verifier):** Phase 1 ships with confidence. Existing modal users will sign in seamlessly on mobile via SFA — same pubkey, same row, same on-chain assets.
- **Any mismatch:** Phase 1 still ships (current mobile is fully broken — partial fix is strictly better than no fix), but Phase 2 cleanup includes desktop cutover to SFA. Existing modal users get new pubkeys on next sign-in. Reclaim flow merges old → new via `Accounts.reclaim_legacy_via_web3auth/3` (already implemented for Web3Auth-vs-legacy-EVM users; the same merge function handles Web3Auth-modal-vs-Web3Auth-SFA pubkey replacements transparently).

---

## 3. Phase 1 — Mobile SFA Hook (ship at 100%)

**Goal:** working mobile sign-in via email OTP, Telegram, X, Google, Apple. iOS Safari and Android Chrome both succeed.

**Effort:** 4–6 hours including real-device testing.

**Rollout:** straight to 100% of mobile traffic. The current mobile flow is fully broken; gradual rollout adds zero safety and delays the fix. Feature-flag exists for emergency rollback only.

### 3.1 Files to create

1. **`assets/js/hooks/web3auth_sfa_hook.js`** (~350 lines, vs ~1300 in current modal hook). Functions:
   - `mounted()` — read data attrs (`clientId`, `web3authNetwork`, `chainId`, `rpcTarget`, `telegramBotId`, etc.), set up event listeners. Same shape as current hook.
   - `_initSfa()` — instantiate SFA singleton with `{clientId, web3AuthNetwork: "sapphire_mainnet", chainConfig: {chainNamespace: "solana", chainId, rpcTarget}}`. Pass `{skipSw: true, skipInit: true}` to `init()`. No iframe, no ws-embed, no service worker.
   - `_doSfaLogin(verifier, verifierId, idToken)` — call `sfa.getKey({verifier, verifierId, idToken})`. Receive `ed25519PrivKey`. Build `Keypair.fromSecretKey(...)`. Call `_installSigner(keypair)`. Push `web3auth_login_success` event with `wallet_address`.
   - `_handleEmailOtp` — same two-stage form as current hook. On submit, fetch JWT from `/api/auth/email_otp/verify` (existing), call `_doSfaLogin("blockster-email", sub, jwt)`.
   - `_handleTelegramRedirectReturn` — same redirect-mode pattern as current hook. Receives JWT via `GET /api/auth/telegram/pending_jwt` (existing one-shot endpoint), calls `_doSfaLogin("blockster-telegram", sub, jwt)`.
   - `_handleOAuth(provider)` — call SFA's `triggerLogin({verifier, typeOfLogin, clientId, customState, uxMode: "redirect"})`. Top-level navigation to provider, returns to our domain with JWT in URL hash.
   - `_completeOAuthRedirectReturn()` — on mount, check URL hash for SFA's redirect-result format (`#sessionId=...` or whatever `triggerLogin` returns), parse, complete login.
   - `_silentReconnect()` — if `localStorage["blockster_web3auth_sfa_session"]` is set, GET `/api/auth/web3auth/refresh_jwt` (existing endpoint), call `_doSfaLogin`. No SDK-level session to rehydrate (SFA is stateless per-call).
   - `_installSigner(keypair)` — **identical to current hook.** Same `window.__signer.signAndConfirm`, `signTransaction`, `signMessage` interface. Each signer call invokes `_fetchKeypairForSign` to get the secret bytes, signs, then `secretKey.fill(0)` in `finally`.
   - `_fetchKeypairForSign(idToken)` — calls `sfa.getKey(...)` per-sign by default (~1s per call due to Torus DKG round-trip). For latency-sensitive flows (coin flip), §3.7 layers a short-lived in-memory seed cache on top.
   - `_clearSession()` — `localStorage.removeItem("blockster_web3auth_sfa_session")`. No SDK logout call (SFA has no session state).

### 3.2 Files to modify

1. **`assets/js/app.js`** — register `Web3AuthSfa` hook alongside existing `Web3Auth`.
2. **`lib/blockster_v2_web/components/wallet_components.ex`** — branch on `is_mobile?`:
   - Mobile: render `phx-hook="Web3AuthSfa"`, `id="web3auth-sfa"`.
   - Desktop: render `phx-hook="Web3Auth"`, `id="web3auth"` (current behavior).
   - Same `data-*` attrs pass through to either hook.
   - `is_mobile?` derived from `Plug.Conn` user-agent in mount: iOS (iPhone, iPad with iPadOS), Android. Pass into LiveView via `socket.assigns`.
3. **`lib/blockster_v2_web/live/wallet_auth_events.ex`** — verify event names emitted by new hook match existing handlers. Should — same `web3auth_login_success`, `web3auth_login_error`, `web3auth_reauth_required`. Read-only check; no diff expected.
4. **`assets/js/hooks/sol_payment.js`** — read-only verify it depends on `window.__signer` only, not on a Web3Auth-specific API. Confirms downstream code is hook-agnostic.

### 3.3 Server-side touches

**Zero.** Verified in source research:
- `lib/blockster_v2/auth/web3_auth_signing.ex` — same RS256 JWT, same claims (`sub`, `aud`, `exp`, etc.).
- `lib/blockster_v2_web/controllers/auth_controller.ex` `/api/auth/web3auth/refresh_jwt` — same response shape.
- `BlocksterV2.Auth.EmailOtpStore` (ETS) — unchanged.
- `/api/auth/telegram/callback` and `/api/auth/telegram/pending_jwt` — unchanged.
- `BlocksterV2.Accounts.reclaim_legacy_via_web3auth/3` — unchanged.
- Sapphire dashboard verifiers `blockster-email`, `blockster-telegram` — no reconfig required.

### 3.4 Feature flag

`WEB3AUTH_USE_SFA` Fly secret on `blockster-v2`:
- Unset / `"true"` / `"1"`: mobile uses SFA hook (default after this ships).
- `"false"` / `"0"`: mobile falls back to modal hook (emergency rollback only).

Read live in `wallet_components.ex` on every mount. Hot reloads — no deploy needed to flip.

### 3.5 Testing protocol (before merge to main)

**Real-device tests** (not simulator):
- iPhone Safari, ITP fully on (default). Run all five flows: email, Telegram, X, Google, Apple. Each must:
  1. Complete sign-in.
  2. Land on home page with wallet pubkey visible.
  3. Sign one shop checkout SOL transfer end-to-end.
- iPhone in-app browsers: Twitter, Telegram (these have stricter restrictions than Safari proper).
- Android Chrome: same five flows.
- Desktop Chrome: verify `Web3Auth` (modal) hook still mounts. No regression.
- Desktop Safari: same.
- Phantom / Solflare / Backpack on both desktop and mobile: verify Wallet Standard untouched.

**Existing modal-registered user signs in via mobile SFA:**
- If Phase 0 reported parity match: same `wallet_address` row hit, normal sign-in.
- If Phase 0 reported parity mismatch: reclaim flow triggers, new user row created, legacy merged via `LegacyMerge.merge_legacy_into!`.

### 3.6 Rollback

Flip `WEB3AUTH_USE_SFA=false` Fly secret (`flyctl secrets set WEB3AUTH_USE_SFA=false --stage --app blockster-v2`, then deploy). Mobile reverts to modal on next page load.

Not applicable if Phase 0 reported parity mismatch and Phase 2 has migrated desktop too — at that point modal is gone from the bundle.

### 3.7 Performance: soft cache for fast signing (Phase 1.1, deferred)

Phase 1 (current) re-derives the keypair on every sign — `customauth.getTorusKey(...)` HTTPS round-trip to ~5 Torus DKG nodes per call, ~800–1500ms latency. Acceptable for one-shot flows (shop checkout, pool deposit/withdraw, airdrop claim, BUX burn) where the user is already in a "submitting…" UI. **Felt for coin flip betting**, where every bet is a sign and a 1s pause-per-bet hurts UX.

Phase 1.1 layers a short-lived in-memory seed cache on top of the per-sign fetch. Sketch:

- After a successful `_fetchKeypair`, store the 32-byte ed25519 seed in a closure-scoped variable (NOT in localStorage / sessionStorage / IndexedDB).
- TTL: 30–60 seconds, default 60_000 ms (configurable via `data-key-cache-ttl-ms` attribute on the hook root).
- Subsequent signs within the window: derive `Keypair.fromSeed(cached)` locally, sign, zero the keypair's secretKey. The cached seed itself stays.
- On TTL expiry: zero the cached seed, next sign re-derives via Torus.
- On logout / hook destroyed: zero the cached seed immediately.
- Modal hook is unaffected — `provider.request({method: "solana_privateKey"})` is already fast, no caching layer needed there.

**Security trade-off.** The previous strict-per-sign rule was XSS defense in depth — limit the window an attacker with code execution can exfiltrate the secret. With a 60s cache, an XSS attacker can grab the cached seed during the window, but they could already have waited one user-initiated sign cycle to exfiltrate via the per-sign path. The protection delta is modest. The load-bearing rule remains: **never write keys to persistent storage.** That's where XSS damage compounds (key survives reload, attacker has unlimited time).

CLAUDE.md updated 2026-04-29 to reflect this — the strict "never cache" bullet is replaced with "never write to localStorage/sessionStorage; short-lived in-memory cache OK".

Effort: ~15 LOC in `web3auth_sfa_hook.js`. Zero server-side. Implement when (a) we get user feedback that mobile coin flip feels slow, OR (b) before any other latency-sensitive feature ships on mobile.

---

## 4. Phase 2 — Conditional Cleanup

### 4.1 If Phase 0 reported parity match (every account, every verifier)

**Optional desktop migration:** can migrate desktop to SFA later for bundle savings (~5MB by dropping `@web3auth/modal`, `@web3auth/no-modal`, `@web3auth/ws-embed`). Defer until/unless bundle becomes a priority. No urgency — desktop modal works fine.

### 4.2 If Phase 0 reported parity mismatch

**Cut desktop over to SFA after Phase 1 is verified working on real mobile devices.**

- Decision: collapse to single SDK, single hook, all users on SFA.
- Existing modal users: next sign-in derives new pubkey via SFA → reclaim flow creates new user row, merges legacy (BUX, multipliers, X handle, Telegram ID, phone, content, referrals, fingerprints) into new wallet via `Accounts.reclaim_legacy_via_web3auth/3` + `LegacyMerge.merge_legacy_into!`.
- BUX migration is on-chain via settler (existing pattern, exercised by social-login launch).
- Risk: if a user signs in on multiple devices mid-cutover, ensure email-keyed merge handles ping-pong gracefully. Watch `LegacyMerge` logs for 24 hours post-cutover; investigate any double-merges or merge-into-merged-row scenarios.

### 4.3 Cleanup tasks (after either path)

- Remove `WEB3AUTH_USE_SFA` flag and the dual-hook branch in `wallet_components.ex` once mobile has been on SFA for 7+ days with no regression.
- Drop `@web3auth/modal`, `@web3auth/no-modal`, `@web3auth/ws-embed` from `package.json` if and only if §4.2 path was taken (or §4.1 was deferred and is now in flight).
- Delete `assets/js/hooks/web3auth_hook.js` (modal hook) once unused.
- Update `docs/web3auth_integration.md` with the new signing pattern (`sfa.getKey` per call instead of `provider.request({method: "solana_privateKey"})`).
- Update `CLAUDE.md` Social Login section: replace modal references with SFA.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| SFA derives different ed25519 pubkey than modal | Phase 0 catches this. Acceptable outcome given launch was 2026-04-28. |
| SFA peer-dep version doesn't align with `@web3auth/auth@10.15` | Use `@toruslabs/customauth@21.3.2` directly (already installed transitively). Zero new deps. |
| `keyType: "ed25519"` not supported on existing dashboard verifier | Phase 0 catches. Fall back to secp256k1 retrieval + Path A (SHA-512) derivation in browser. |
| Two hooks both write `window.__signer` | Server-side mount picks exactly one; never both — UA-keyed branch in `wallet_components.ex`. |
| `localStorage` key collision between SDKs | Distinct keys: `blockster_web3auth_session` (modal) vs `blockster_web3auth_sfa_session` (SFA). |
| Bundle size for users who don't need SFA | Dynamic-import SFA inside hook. Loads only if hook mounts (i.e., only on mobile). |
| iOS PWA / in-app browser quirks | Test on iOS Safari, iOS Chrome (WKWebView), Twitter in-app, Telegram in-app explicitly. |
| Telegram redirect callback breaks mid-cutover | Server-side flow is unchanged; only the client SDK call after JWT receipt differs. Low risk. |

---

## 6. Phase 0 Results

*To be filled in after the parity test runs.*

| Account | Verifier | Expected pubkey | Derived (SFA) | Match? | keyType | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |

---

## 7. Open Questions

1. Does `keyType: "ed25519"` work on Sapphire Mainnet for `blockster-email` / `blockster-telegram` verifiers without dashboard reconfig? Verifiers were created during social-login launch with curve auto-detect; behavior under explicit `keyType: ed25519` is undocumented for our specific config.
2. Latest published `@web3auth/single-factor-auth` version compatible with `@web3auth/auth@10.15`. Run `npm view @web3auth/single-factor-auth peerDependencies` before adding.
3. Does Telegram in-app browser's WebView have storage restrictions strict enough to break SFA's `localStorage` session flag? (HTTPS-only flow should work, but worth one direct test on a real Telegram in-app session.)

---

## 8. Success Criteria

1. iOS Safari user signs in via email OTP, completes `_doSfaLogin`, sees their wallet pubkey, and signs one shop checkout end-to-end. **No iframe-storage error, no 60s timeout, no "browser blocked secure key derivation" message.**
2. Same for Telegram, X, Google, Apple flows on iOS Safari.
3. Same for Android Chrome.
4. Desktop sign-in (all five flows + Wallet Standard) unaffected — same as 2026-04-28 baseline.
5. No server-side errors. No `LegacyMerge` failures. No reclaim loop bugs.
6. Phase 0 results documented in §6 above.

---

## 9. Related Docs

- `docs/social_login_plan.md` — original Web3Auth integration plan, Appendix E for the email-OTP-via-Custom-JWT rationale.
- `docs/web3auth_integration.md` — current technical reference (will need §4 updated once SFA ships).
- `docs/session_learnings.md` — "Web3Auth OAuth reauth — pill, not modal" pattern (still relevant — SFA reauth UX is the same pill).
- `docs/solana_mainnet_deployment.md` — mainnet runbook, includes Web3Auth Sapphire client ID provisioning.
- `CLAUDE.md` — Social Login section.
