# Social Login + Embedded Wallet Plan (Web3Auth)

**Status:** Draft — pending review
**Date:** 2026-04-20
**Author:** Claude + Adam
**Provider decision:** Web3Auth (`@web3auth/modal` v10, non-React path via `connectTo`)

---

## 0. Executive Summary

Add email / X / Telegram login as the **primary** sign-in option, keeping the existing wallet-connect flow as a **secondary** option. Users who sign in with social get a Web3Auth embedded Solana wallet they never see — signing is programmatic (no popup per action). Users who connect Phantom keep their current flow but see a popup per tx (as today).

Blockster sponsors transaction fees AND on-chain rent for *everyone* via a dual mechanism:
1. **Tx fees:** settler is the fee-payer on every multi-signer tx.
2. **PDA rent:** Anchor program is upgraded (V1 — Phase 1) to accept an optional `rent_payer` signer. Settler becomes rent_payer for `bet_order` PDA creation. `settle_bet` and `reclaim_expired` close the PDA with `close = rent_payer`, returning rent to settler.

**No starter fund, no standing SOL in user wallets.** This eliminates the Sybil-attack vector — a fake account has nothing to drain, and Blockster pays only the marginal rent per bet, which is fully recovered on settlement. Effective net cost per bet to Blockster: ~5,000 lamports (~$0.0005) priority fee only.

Onboarding adapts:
- Email signup → email step skipped (already verified via Web3Auth).
- X signup → X multiplier pre-populated from the Web3Auth-provided OAuth handle; email step optional.
- Telegram signup → `telegram_user_id` pre-populated; email step optional.
- Wallet signup → unchanged (current onboarding).

A wallet user can later add email in settings to unlock the email multiplier (0.5x → 2.0x). A social user can later export their embedded wallet to Phantom if they want self-custody.

**UX guarantees, confirmed against code:**
1. ✅ Social-signup users can place BUX bets with **one click, no popup, no prompts**. (Web3Auth MPC signing is programmatic; settler is fee payer; settler is rent_payer.)
2. ✅ Social-signup users **never need to acquire or hold SOL** themselves. Period.
3. ⚠️ Phantom users still see one popup per tx — this is a wallet-extension constraint. Mitigated by messaging "Sign in with email for one-click betting."

**All UI work (login modal, onboarding screens, settings "Connected accounts" section, any new components) MUST be done via the `/frontend-design:frontend-design` skill** — per CLAUDE.md and user directive. No generic AI aesthetics.

**Every phase ships with its own tests.** Tests are not a separate phase; each phase's exit criteria include the tests added for that phase. A consolidated regression pass happens in Phase 10, but the unit + integration tests for each component land *with* that component.

---

## 1. Architecture Decisions

### 1.1 Provider: Web3Auth (`@web3auth/modal` v10)

Chosen because:
- Vanilla JS SDK, no React dependency — drops into `assets/js/hooks/` next to existing hooks.
- Custom UI supported via `connectTo()` — we build our own login modal consistent with `wallet_components.ex`.
- First-class Solana support via Solana Private Key Provider.
- Email passwordless + Google/Apple/Discord/**X (Twitter)** built-in.
- **Telegram supported via Custom JWT Auth** (we verify Telegram Login Widget server-side, issue a JWT, pass it to Web3Auth).
- MPC key model — user keys exist even if Web3Auth goes down (export flow).

**NOT chosen:** Privy (React-only), Dynamic (React-only), Thirdweb (Solana support is server-only, no client embedded wallet), Magic (not investigated — fallback option if Web3Auth blocks).

### 1.2 Fee Model: Settler-as-Fee-Payer + Settler-as-Rent-Payer (all V1)

- **Tx fee:** Settler pays via multi-signer tx (settler = fee payer, user = instruction authority). Zero SOL required from user for fees.
- **PDA rent** (`bet_order`, ATAs, airdrop claim records):
  - Anchor program is upgraded (Phase 1) to accept optional `rent_payer: Signer` on all `init`-using instructions.
  - When `rent_payer` is provided, constraint becomes `payer = rent_payer` instead of `payer = player`.
  - `rent_payer` pubkey is validated against `game_registry.settler` in the handler to prevent griefing.
  - `settle_bet` and `reclaim_expired` are updated to `close = rent_payer`, returning rent to settler on settlement.
  - ATA creation for a user's BUX account on first bet: settler pre-creates the ATA via the existing mint flow or a separate `ensure_bux_ata` endpoint. Rent paid by settler, recovered only if user ever closes their ATA (effectively permanent, but ATA rent is ~0.002 SOL and is a one-time per-user cost).

**Per-bet cost to Blockster on steady state:** ~5,000 lamports priority fee. Rent cycles through settler → PDA → settler with no permanent outflow.

**No Sybil drain vector:** a fake account holds zero SOL at all times. Creating 10,000 fake accounts costs Blockster nothing (no tx is submitted unless the fake account plays, and if they play, that's real engagement we want).

### 1.3 Identity Model

**One user row per identity. Never merge implicitly.** (Explicit merge only via admin tool.)

| Auth path | `auth_method` | `wallet_address` | `email` | `email_verified` | Social fields |
|---|---|---|---|---|---|
| Wallet Standard (Phantom) | `"wallet"` | Phantom pubkey | `nil` | `false` | `nil` |
| Web3Auth email | `"web3auth_email"` | Embedded pubkey | from Web3Auth | `true` | `nil` |
| Web3Auth X | `"web3auth_x"` | Embedded pubkey | `nil` (or if provided) | if provided | `x_handle`, `x_user_id` |
| Web3Auth Telegram | `"web3auth_telegram"` | Embedded pubkey | `nil` | `false` | `telegram_user_id`, `telegram_username` |

**All four paths share the same `wallet_address` field** — embedded wallets are real Solana pubkeys. Downstream (BUX balance, bets, multipliers, referrals) is identity-agnostic.

### 1.4 SIWS vs. JWT Verification

- **Wallet Standard path:** keeps SIWS (current flow unchanged).
- **Web3Auth path:** verifies Web3Auth's ID token (JWT, signed by their JWKS). **No SIWS needed** — the JWT proves both wallet ownership and auth-method identity. Adds `Joken` + JWKS fetching to the backend.

### 1.5 Secondary Wallet Connections (out of scope for v1)

A Web3Auth user may later want to connect Phantom as an additional self-custodial wallet, or a wallet user may want to link a Web3Auth email account. For v1 we treat these as separate accounts — no linking. Users who want to consolidate can use the existing legacy-email reclaim flow (`merged_into_user_id`). Revisit in v2.

---

## 2. Critical UX Verification

### 2.1 "Single-click BUX bet, no popup, no SOL" — confirmed path (post-Phase-1 upgrade)

| Step | What happens | UI? | SOL needed from user? |
|---|---|---|---|
| User clicks "Place Bet" | LiveView pushes `sign_place_bet` event with unsigned tx from settler | — | — |
| Settler has already built tx with `feePayer = settler_pubkey` and partially signed. Tx includes settler as `rent_payer` for the `bet_order` PDA init. | — | — | — |
| `coin_flip_solana.js` calls `window.__signer.signTransaction(tx)` | Signer adapter routes to Web3Auth | **NO popup** (MPC is programmatic) | **Zero SOL** — settler pays fee and rent |
| Client submits signed tx to RPC via `sendRawTransaction` | — | — | — |
| `getSignatureStatuses` polls to confirmed | ~1s | Spinner only | — |
| `bet_confirmed` event fires to LiveView | — | Bet shows on board | — |

**Total elapsed: ~1s from click to confirmed.** Identical to current Phantom flow minus the signature popup.

### 2.2 Rent accounting (post-Phase-1 upgrade)

- Upgraded `place_bet_sol/bux` constraint: `init, payer = rent_payer, space = BetOrder::LEN` where `rent_payer` is validated against `game_registry.settler`.
- `settle_bet`: `close = rent_payer` — rent returns to settler when bet is settled (on win, loss, or tie).
- `reclaim_expired`: same — `close = rent_payer` returns rent to settler when user reclaims.
- Net effect: rent cycles through settler's account. **Per-bet rent outflow = 0 at steady state.** Only priority-fee cost remains.
- ATAs for BUX: created by settler once per user on first play, funded via a settler `ensure_ata` path. One-time ~0.002 SOL per user, not reclaimed unless user closes ATA (rare).

**Verification step (Phase 0):** inspect current `settle_bet.rs` and `reclaim_expired.rs` to confirm the close pattern. If they currently `close = player`, we're switching to `close = rent_payer`. If they don't close at all, we add the close constraint.

### 2.3 Phantom fallback UX

Phantom users see the standard Wallet Standard popup per tx (today's behavior). No change. They're on the secondary path. The first-run experience on `/play` will include a subtle hint: "Tip: sign in with email for one-click betting." Don't be pushy — crypto-native users will ignore social login anyway.

---

## 3. Phases

Phases are sized for continuous AI-assisted work. Each phase lists implementation + tests + QA steps. Tests ship *with* the phase, not after.

### Phase 0: Prep + Prototype (~1 hour setup + ~2 hours prototyping)

**Goal:** Validate Web3Auth with a throwaway test page before committing to the full rewrite. Confirm all five login paths work on devnet before touching production code.

- **0.1** Create a Web3Auth project at dashboard.web3auth.io; configure Solana network, email + Google + Apple + X connectors; add `localhost:4000` redirect.
- **0.2** `npm install @web3auth/modal @web3auth/solana-provider` in `assets/`.
- **0.3** Add throwaway route `/test-web3auth` rendering a static page with "Sign in with Email / X / Telegram / Google / Apple" buttons.
- **0.4** Wire `connectTo(WALLET_ADAPTERS.AUTH, { loginProvider, extraLoginOptions })` for each provider via raw JS (no React).
- **0.5** Verify: email OTP flow → derive Solana pubkey → sign a message → sign+send a self-transfer on devnet.
- **0.6** Verify: two-signer tx works. Settler builds tx with `feePayer = settler_pubkey`, `partialSign`, returns base64; Web3Auth signs as player; submit. Confirm on devnet.
- **0.7** Verify each connector: Google, Apple, X, email. Log the returned `userInfo` structure for each to document what data we get.
- **0.8** **Telegram prototype (Custom JWT path):**
  - Add Telegram Login Widget to test page.
  - Backend endpoint `/api/auth/telegram/verify` validates Telegram HMAC-SHA256 hash.
  - Issues JWT signed with `BLOCKSTER_TELEGRAM_JWT_SECRET`, `sub = telegram_user_id`.
  - Register JWT verifier in Web3Auth dashboard (JWKS endpoint on Phoenix side).
  - Frontend calls `connectTo(WALLET_ADAPTERS.AUTH, { loginProvider: "jwt", extraLoginOptions: { id_token, verifierIdField: "sub" } })`.
  - Confirm Solana pubkey is deterministic for same telegram_user_id.
- **0.9** Inspect `settle_bet.rs` and `reclaim_expired.rs` on-chain source to confirm Phase 1 assumptions about close patterns.

**Tests (this phase):** Manual devnet verification only. The throwaway route is disposable.

**Exit criteria:** All five login paths (email, Google, Apple, X, Telegram) produce deterministic Solana pubkeys and can sign two-signer devnet txs. Prototype code is removed or clearly marked as throwaway.

**Risk mitigation:** If Telegram JWT is rough, ship v1 without Telegram and add as v1.1 (rare).

---

### Phase 1: Anchor Program Upgrade — Settler as Rent Payer (~2 hours)

**Goal:** Eliminate the player-rent requirement on-chain. Settler pays rent, settler reclaims rent on settlement. No user SOL ever required.

**This is V1, not deferred. It is the only way to make "zero SOL" real without Sybil exposure.**

**1.1** Modify `contracts/blockster-bankroll/programs/blockster-bankroll/src/instructions/place_bet_sol.rs` and `place_bet_bux.rs`:
- Add `rent_payer: Signer<'info>` (required; no longer optional — simpler).
- Change `init, payer = player, space = ...` to `init, payer = rent_payer, space = ...` on the `bet_order` account.
- Add handler-side check: `require!(ctx.accounts.rent_payer.key() == game_registry.settler, BankrollError::InvalidRentPayer)`.
- Keep `player: Signer<'info>` as-is — player still signs the instruction to authorize their bet.

**1.2** Modify `settle_bet.rs`:
- Add `rent_payer: SystemAccount<'info>` (matches the rent payer from placement — must verify against `bet_order.rent_payer` stored at placement).
- Add `close = rent_payer` constraint on the `bet_order` account — rent flows back to settler on settlement.
- Store `rent_payer` pubkey in `BetOrder` state struct at placement (new field, appended — see on-chain upgrade rules).

**1.3** Modify `reclaim_expired.rs`:
- Same `close = rent_payer` pattern. If settler is rent_payer, settler gets the rent back when user reclaims.
- User still signs the reclaim tx (they're authorizing it).

**1.4** `BetOrder` state struct: add `rent_payer: Pubkey` field at END (per CLAUDE.md append-only rule). Bump `BetOrder::LEN` accordingly.

**1.5** Check `contracts/blockster-airdrop/programs/*` for parallel PDA init patterns. If airdrop `claim_airdrop` has `init, payer = player`, apply the same rent-payer pattern.

**1.6** Compile: `cd contracts/blockster-bankroll && anchor build`.

**1.7** Deploy upgrade to devnet via the established upgrade path (see `docs/solana_program_deploy.md`):
- Buffer write, upgrade command, verify program data slot, confirm new IDL.
- Settler keypair is upgrade authority (per addresses.md).

**1.8** Update `contracts/blockster-bankroll/target/idl/*.json` and the generated TS bindings used by the settler.

**Tests (this phase):**
- `contracts/blockster-bankroll/tests/place_bet.ts` (Anchor test harness): place bet with settler as rent_payer → verify rent deducted from settler → settle bet → verify rent returned to settler.
- `contracts/blockster-bankroll/tests/reclaim_expired.ts`: place bet → wait timeout → reclaim → verify rent returned to settler.
- `contracts/blockster-bankroll/tests/invalid_rent_payer.ts`: try passing a random pubkey as rent_payer → expect `InvalidRentPayer` error.
- Manual devnet: do one real bet end-to-end, inspect tx on Solana Explorer, verify lamport flows.

**Exit criteria:** Upgraded program on devnet, Anchor tests pass, manual bet cycle verified on-chain with settler balance unchanged net of priority fee.

---

### Phase 2: Signer Abstraction (~1–2 hours)

**Goal:** Decouple the 5 signing call sites from the concrete Wallet Standard API. No user-visible change.

**2.1** Create `assets/js/hooks/signer.js` exporting a `window.__signer` interface:
```js
window.__signer = {
  pubkey: string,
  source: "wallet-standard" | "web3auth",
  signMessage(bytes) → Uint8Array,
  signTransaction(txBytes) → Uint8Array,
  signAndSendTransaction(txBytes, { chain }) → { signature },
  disconnect(),
}
```

**2.2** Port `solana_wallet.js` to expose itself via `window.__signer` (adapter shape). Keep legacy `window.__solanaWallet` as an alias during migration, deleted at end of Phase 4.

**2.3** Refactor the 5 consumers to route through `window.__signer`:
- `assets/js/coin_flip_solana.js` (place_bet, reclaim).
- `assets/js/hooks/pool_hook.js` (deposit/withdraw × sol/bux).
- `assets/js/hooks/airdrop_solana.js`.
- `assets/js/hooks/sol_payment.js`.

**2.4** Since Phase 1 made these multi-signer txs, switch from `signAndSendTransaction` → `signTransaction` + explicit `connection.sendRawTransaction()`. The signer interface needs both methods; Wallet Standard exposes `solana:signTransaction` feature which all target wallets support.

**Tests (this phase):**
- Manual regression on devnet for each of the 4 flows using Phantom: bet, reclaim, pool deposit+withdraw × sol+bux, airdrop claim, shop SOL payment. Bit-identical behavior expected.
- Add a JS unit test file `assets/test/signer.test.js` (if testing infra exists; otherwise skip and rely on manual regression) covering the adapter contract.

**Exit criteria:** Existing Phantom users see zero change; all 5 flows work against the upgraded program from Phase 1.

---

### Phase 3: Backend — Web3Auth Verification + User Model (~3–4 hours)

**Goal:** Elixir verifies Web3Auth ID tokens and creates users correctly.

**3.1** Add deps to `mix.exs`:
- `{:joken, "~> 2.6"}` — JWT library
- `{:joken_jwks, "~> 1.7"}` — JWKS fetch + cache
Run `mix deps.get`.

**3.2** Create `lib/blockster_v2/auth/web3auth.ex`:
- `verify_id_token(id_token, expected_wallet_pubkey)` → `{:ok, claims} | {:error, reason}`.
  - Fetch JWKS from `https://api-auth.web3auth.io/jwks`, cache in ETS for 1 hour.
  - Validate RS256 signature, `aud` matches WEB3AUTH_CLIENT_ID, `iss`, `exp`, `iat`.
  - Extract `wallets[].public_key` and confirm matches `expected_wallet_pubkey`.
  - Extract `verifier`, `email`, `name`, `profileImage`, `oAuthAccessToken` etc.
  - Return normalized claims map.

**3.3** Extend `lib/blockster_v2/accounts/user.ex`:
- Widen `auth_method` enum: `["wallet", "email", "web3auth_email", "web3auth_x", "web3auth_telegram"]`.
- New migration `priv/repo/migrations/20260420_*_add_web3auth_fields_to_users.exs`:
  - `x_user_id` (string, unique) — OAuth subject from Twitter/X.
  - `social_avatar_url` (string) — from social provider.
  - `web3auth_verifier` (string).
- Do NOT change existing `telegram_user_id`, `telegram_username`.

**3.4** `lib/blockster_v2/accounts.ex`:
- `get_or_create_user_by_web3auth(claims, opts)`:
  - Lookup by `wallet_address`.
  - If verifier = `email_passwordless` → set `email`, `email_verified = true`.
  - If verifier = `twitter` → set `x_user_id`, `x_handle`.
  - If verifier = `custom-telegram` → set `telegram_user_id`, `telegram_username`, `telegram_connected_at`.
  - Set `auth_method` accordingly.
  - Dispatch to the same session-creation helper as the wallet path.
- `link_email_to_user(user_id, email, code)` — for the settings "add email" flow.

**3.5** Fix `lib/blockster_v2/referrals.ex` referrer lookup:
- Currently searches `smart_wallet_address` (legacy EVM) — broken for Solana users.
- Change to `wallet_address` for Solana referrers, keep `smart_wallet_address` as legacy fallback.

**3.6** Controller endpoints in `lib/blockster_v2_web/controllers/auth_controller.ex`:
- `POST /api/auth/web3auth/session`: body `{ wallet_address, id_token }` → verify token → `get_or_create_user_by_web3auth` → set session cookie → return `{ is_new_user, auth_method }`.
- `POST /api/auth/telegram/verify`: validate Telegram hash, issue Blockster JWT, return `{ id_token }`.
- `GET /.well-known/jwks.json`: expose Phoenix's JWKS for Web3Auth's Custom JWT verifier.

**3.7** Update `router.ex` with the three new routes.

**Tests (this phase):**
- `test/blockster_v2/auth/web3auth_test.exs`: mock JWKS responses, verify valid token, reject expired, reject wrong aud, reject wallet mismatch.
- `test/blockster_v2/accounts_test.exs`: exercise `get_or_create_user_by_web3auth` for each verifier; assert correct fields populated.
- `test/blockster_v2_web/controllers/auth_controller_test.exs`: test each new endpoint with valid + invalid inputs.
- `test/blockster_v2/referrals_test.exs`: confirm the lookup fix works for Solana wallet_address.
- Run `mix test` — all existing tests must pass.

**Exit criteria:** All three Web3Auth verifiers pass integration tests end-to-end. Referrals test suite green. Zero failures in `mix test`.

---

### Phase 4: Settler — Fee Payer + Rent Payer Rollout (~2 hours)

**Goal:** Settler includes itself as fee_payer AND rent_payer on every relevant tx.

**Context:** Phase 1 upgraded the Anchor program. Phase 2 made the JS side tolerate multi-signer. This phase wires the settler to actually produce those multi-signer txs.

**4.1** Modify `contracts/blockster-settler/src/services/bankroll-service.ts`:
- `buildPlaceBetSolTx` / `buildPlaceBetBuxTx`: set `tx.feePayer = FEE_PAYER.publicKey`, add `rent_payer` account (= settler pubkey), `partialSign(FEE_PAYER)`, return base64.
- Same for `buildDepositSolTx`, `buildWithdrawSolTx`, `buildDepositBuxTx`, `buildWithdrawBuxTx`, `buildClaimAirdropTx`, `buildReclaimExpiredTx`.

**4.2** Decision (from §5): dedicated `FEE_PAYER` keypair vs. reusing `MINT_AUTHORITY`:
- **Default to dedicated `FEE_PAYER` keypair.** Key hygiene: compromise of fee_payer doesn't affect mint authority.
- Add `FEE_PAYER_KEYPAIR_PATH` to `config.ts`, load keypair at service boot, expose `FEE_PAYER` constant.
- Top-up mechanism: weekly or balance-triggered transfer from a treasury wallet. Document in `docs/solana_program_deploy.md`.

**4.3** Priority fees: existing `computeBudgetIxs` must account for the settler paying. Recalibrate if needed.

**4.4** `ensure_bux_ata` endpoint: if a user's BUX ATA doesn't exist, settler creates it (settler pays rent). Check existing mint flow — this may already happen in `buxMint` path.

**4.5** ATA for the player within `place_bet_bux` — currently `token::authority = player`. ATA must exist before the bet. Options:
- (a) Settler pre-creates on first BUX mint (probably already the case — confirm in mint flow).
- (b) Include an `ensure_ata` instruction in the `place_bet_bux` tx as a preceding instruction. Cleanest; single tx.

**Tests (this phase):**
- `contracts/blockster-settler/tests/bankroll-service.test.ts` (or equivalent): unit tests for tx building; assert `tx.feePayer` and rent_payer account are correct.
- Devnet: place 10 bets back-to-back, verify settler SOL balance is net unchanged (fees paid, rent cycles).
- Monitor `FEE_PAYER` balance — must not drift more than priority-fee cost per bet.

**Exit criteria:** All settler endpoints return properly-formed two-signer txs. Devnet balance math confirms rent recovery.

---

### Phase 5: Frontend Web3Auth Hook + Login UI (~3–5 hours)

**Goal:** Build the email/social login UX with `/frontend-design:frontend-design`.

**5.1** **`/frontend-design:frontend-design` — MANDATORY for this phase.** Per CLAUDE.md + user directive, all modal/UI work goes through this skill to avoid generic AI aesthetics. Invoke it for:
- The new sign-in modal (`wallet_components.ex` connect modal rebuild).
- The Telegram Login Widget embed styling.
- Any "Continue with X" / "Continue with Google" / email input components.

**5.2** New hook `assets/js/hooks/web3auth_hook.js`:
- Initializes `Web3Auth` with Solana chain config from `window.BLOCKSTER_CHAIN`.
- Registers `window.__signer` adapter for Web3Auth:
  - `signMessage`: `solanaWallet.signMessage(bytes)`.
  - `signTransaction`: `solanaWallet.signTransaction(tx)`.
  - `signAndSendTransaction`: compose signTransaction + RPC + poll.
- Handles LiveView events:
  - `start_web3auth_login` with `{ provider, email_hint? }` → calls `connectTo()`.
  - `request_disconnect` → `web3auth.logout()`, clears `__signer`.
  - On successful auth → pushes `web3auth_authenticated` with `{ wallet_address, id_token, verifier, email, x_handle, telegram_user_id, avatar_url }`.
- Auto-reconnect on page load: silent connect if localStorage flag set.
- Visibility / reconnected handlers mirror `solana_wallet.js`.

**5.3** Extend `lib/blockster_v2_web/live/wallet_auth_events.ex`:
- `start_email_login` → `push_event("start_web3auth_login", %{provider: "email_passwordless", email_hint: params["email"]})`.
- `start_x_login` → `push_event("start_web3auth_login", %{provider: "twitter"})`.
- `start_telegram_login` → render Telegram Login Widget, on callback POST `/api/auth/telegram/verify`, then push `start_web3auth_login` with the JWT as id_token.
- `web3auth_authenticated` → client-initiated fetch to `/api/auth/web3auth/session`, then send `:wallet_authenticated`.
- `:wallet_authenticated` hook extended: web3auth `is_new` users go to `/onboarding`; onboarding auto-skips steps based on `auth_method`.

**5.4** Rebuild `lib/blockster_v2_web/components/wallet_components.ex` sign-in modal (invoke `/frontend-design:frontend-design`):

Layout outline (designer produces the actual visual):
- **Primary section (top):** "Sign in with email" — inline email input + Continue button.
- **Secondary primary:** Continue with X, Continue with Telegram, Continue with Google, Continue with Apple buttons.
- **Divider:** "or connect wallet"
- **Tertiary section:** existing Phantom / Solflare / Backpack Wallet Standard list.
- **Footer microcopy:** "Blockster never sees your seed phrase or private keys."
- **Mobile adaptation:** email + social on top, deeplinks to wallet browsers below.

**5.5** Telegram Login Widget integration:
- Server-side render `<script async src="https://telegram.org/js/telegram-widget.js?22" data-telegram-login="<BOT>" data-size="large" data-onauth="onTelegramAuth(user)" data-request-access="write"></script>`.
- `onTelegramAuth` pushes LiveView event with Telegram payload.
- Server verifies, returns JWT, frontend starts Web3Auth login.

**5.6** Copy: terse, direct. "We'll send a code." / "Connect your X account." / "One tap with Telegram." No marketing fluff.

**Tests (this phase):**
- `test/blockster_v2_web/live/wallet_connect_test.exs`: integration test rendering the modal, assert all buttons present for logged-out user.
- `test/blockster_v2_web/live/wallet_auth_events_test.exs`: test each `start_*_login` event emits the expected push_event payload.
- Browser smoke: manual on Chrome + Safari (desktop), Safari (iOS), Chrome (Android). One full login cycle per provider.
- Regression: existing Phantom connect still works.

**Exit criteria:** User on desktop Chrome can sign in with email, X, Telegram, Google, Apple, Phantom — all six produce a valid session cookie and land on `/onboarding` (new) or `/` (returning). UI matches `/frontend-design:frontend-design` output (no generic aesthetic).

---

### Phase 6: Onboarding Adaptation (~2 hours)

**Goal:** Skip steps redundant given the auth method. Invoke `/frontend-design:frontend-design` for the updated completion summary + any new screens.

**6.1** **`/frontend-design:frontend-design` — use for updated onboarding UI.** Specifically:
- The condensed flow for Web3Auth users (fewer steps).
- The "completion summary" screen that now shows connected identities + "Add more" buttons.
- Pre-populated states (e.g., email already verified badge).

**6.2** Extend `lib/blockster_v2_web/live/onboarding_live/index.ex`:
- On mount, inspect `current_user.auth_method` and filter `@steps`:
  - `"web3auth_email"`: remove `"email"` step.
  - `"web3auth_x"`: remove `"x"` step; pre-populate X score via `UnifiedMultiplier.update_x_multiplier(user_id, user.x_user_id)`.
  - `"web3auth_telegram"`: pre-check telegram_group_joined_at.
  - `"wallet"`: unchanged.
- Remove `"migrate_email"` step for any `web3auth_*` auth_method.

**6.3** Completion summary lists connected identities with "Add" buttons for missing ones (each launches the relevant linking flow in settings).

**Tests (this phase):**
- `test/blockster_v2_web/live/onboarding_live_test.exs`: new test cases per auth_method, asserting correct step subset rendered.
- Browser: manual walkthrough of each flow.

**Exit criteria:** A Web3Auth email user reaches `/` from `/onboarding` in under 60 seconds with a 3-step flow.

---

### Phase 7: Shop / Payment-Intents for Embedded-Wallet Users (~2 hours)

**Goal:** Shop checkout works for social users without manual SOL transfers. Invoke `/frontend-design:frontend-design` for any new checkout UI.

**7.1** **`/frontend-design:frontend-design` — use for any UI changes** (new "Pay" button variant, new checkout screen state).

**7.2** Extend `payment_intents`:
- Migration: add `payment_mode: "manual" | "wallet_sign"` field to `order_payment_intents` table.
- For Web3Auth users, default to `wallet_sign` — settler builds transfer tx with fee_payer = settler, user as transfer authority, amount = quoted lamports → ephemeral pubkey.
- `sol_payment.js` handles `payment_mode === "wallet_sign"` via `window.__signer.signTransaction(tx)` + submit.
- Manual mode retained for legacy users and wallet users who prefer it.

**7.3** BUX-priced shop items: straightforward — user signs SPL transfer, settler pays tx fee. No SOL concerns.

**7.4** SOL-priced shop items for Web3Auth users:
- **v1 scope:** require BUX pricing for Web3Auth users, or route through Helio fiat on-ramp.
- **Decision:** gate SOL-priced items to wallet users in v1 (one-line check at checkout). Revisit Helio for Web3Auth in v1.1.

**Tests (this phase):**
- `test/blockster_v2/payment_intents_test.exs`: new test cases for `wallet_sign` mode.
- `test/blockster_v2_web/live/shop_test.exs`: assert the correct payment flow is presented for each auth_method.

**Exit criteria:** A Web3Auth user can buy a BUX-priced shop item with one click. SOL items gracefully route wallet-only users.

---

### Phase 8: Settings — Connected Accounts Linking (~2 hours)

**Goal:** Wallet users can add email/X/Telegram; Web3Auth users can link additional social accounts. All UI via `/frontend-design:frontend-design`.

**8.1** **`/frontend-design:frontend-design` — use for the "Connected accounts" section.**

**8.2** Build/extend `lib/blockster_v2_web/live/settings_live*`:
- Section "Connected accounts":
  - Email: masked + Remove (if verified); "Add email" → existing `EmailVerification` OTP flow (NOT a new Web3Auth account).
  - X: existing `x_auth_controller.ex` OAuth flow.
  - Telegram: existing `telegram_connect_token` flow.
  - Wallet: primary pubkey, non-editable.

**8.3** When a wallet user adds email → multiplier refreshes reactively (LiveView push).

**Tests (this phase):**
- `test/blockster_v2_web/live/settings_live_test.exs`: each link/unlink path for each identity, assert user record updated and multiplier recomputed.

**Exit criteria:** A wallet user adds email in settings → multiplier goes from 0.5x → 2.0x immediately in UI.

---

### Phase 9 (OPTIONAL): Telegram Multiplier (~1 hour)

Skip unless product calls it. If shipped:

**9.1** Add `lib/blockster_v2/telegram_multiplier.ex` (pattern after `email_multiplier.ex`):
- 1.0x if not connected; 1.3x if `telegram_user_id`; 1.5x if `telegram_group_joined_at`.

**9.2** Update `UnifiedMultiplier`:
- Formula: `x * phone * sol * email * telegram`, capped at 300x (or keep 200x per product).
- Append `telegram_multiplier` to `unified_multipliers_v2` Mnesia tuple at END (per CLAUDE.md).

**9.3** One-off migration task to recompute all users' multipliers.

**Tests (this phase):**
- `test/blockster_v2/telegram_multiplier_test.exs`: each tier value.
- `test/blockster_v2/unified_multiplier_test.exs`: formula includes new term; cap enforced.

---

### Phase 10: Final Regression + Rollout (~1–2 hours coding + ongoing monitoring)

**10.1** Cross-cutting regression test:
- Every existing `mix test` → zero failures.
- Manual smoke on all 6 login paths (email, X, Telegram, Google, Apple, Phantom) × desktop+mobile.

**10.2** Env vars / secrets (via `flyctl secrets set --stage` per CLAUDE.md):
- `WEB3AUTH_CLIENT_ID`, `WEB3AUTH_VERIFIER_EMAIL`, `WEB3AUTH_VERIFIER_X`, `WEB3AUTH_VERIFIER_TELEGRAM`
- `BLOCKSTER_TELEGRAM_JWT_SECRET`
- `FEE_PAYER_KEYPAIR_PATH`
- `SOCIAL_LOGIN_ENABLED` (default false for staged rollout)

**10.3** Feature flag rollout:
- Flag off in prod initially. Enable for beta testers.
- 10% → 50% → 100% gradual ramp.
- Wallet Standard flow unchanged end-to-end (defense in depth).

**10.4** Monitoring additions:
- Metric: signups by `auth_method` per day.
- Metric: FEE_PAYER balance drift per day (should be ~0 at steady state, slightly negative by priority fee cost).
- Metric: Web3Auth JWT verification failure rate.
- Metric: new-user → first-bet conversion per auth_method.
- Alert: FEE_PAYER SOL < 5 SOL (needs top-up).
- Alert: Web3Auth JWT failure rate > 5% / hour.

**Tests (this phase):**
- Run full `mix test` suite. Zero failures.
- Run contracts test suite. Zero failures.
- Manual end-to-end per login path.

**Exit criteria:** 100% flag rollout for 1 week, no regressions, first-bet conversion > 60% for social signups.

---

## 4. Affected Features — Complete Audit

### 4.1 Authentication
- `assets/js/hooks/solana_wallet.js` — keep, becomes one of two signer sources.
- `lib/blockster_v2_web/live/wallet_auth_events.ex` — extended with `start_*_login` and `web3auth_authenticated` events.
- `lib/blockster_v2_web/controllers/auth_controller.ex` — new endpoints `/api/auth/web3auth/session`, `/api/auth/telegram/verify`.
- `lib/blockster_v2/auth/solana_auth.ex` — unchanged. SIWS still used for wallet path.
- `lib/blockster_v2/auth/nonce_store.ex` — unchanged.
- `lib/blockster_v2/auth/web3auth.ex` — **NEW** (JWT verification).

### 4.2 User model
- `lib/blockster_v2/accounts/user.ex` — widen `auth_method` enum; add `x_user_id`, `social_avatar_url`, `web3auth_verifier`.
- New migration `20260420_*_add_web3auth_fields_to_users.exs`.
- `lib/blockster_v2/accounts.ex` — new `get_or_create_user_by_web3auth/2`, `link_email_to_user/3`.

### 4.3 Onboarding
- `lib/blockster_v2_web/live/onboarding_live/index.ex` — dynamic step list based on `auth_method`.
- `lib/blockster_v2_web/live/onboarding_live/*.html.heex` — skip rendering email step for Web3Auth email users, etc.

### 4.4 Multipliers
- `lib/blockster_v2/unified_multiplier.ex` — update `update_x_multiplier` trigger on user creation (for Web3Auth X users).
- `lib/blockster_v2/email_multiplier.ex` — no change.
- **(Optional, Phase 9)** `lib/blockster_v2/telegram_multiplier.ex` — NEW module.
- `lib/blockster_v2/mnesia_initializer.ex` — (Phase 9) add telegram_multiplier column to `unified_multipliers_v2`.

### 4.5 Settler (fee payer)
- `contracts/blockster-settler/src/services/bankroll-service.ts` — all `buildXTx` functions set `feePayer = MINT_AUTHORITY.publicKey` and `partialSign`.
- `contracts/blockster-settler/src/services/payment-intent-service.ts` — add `buildTransferFromUserTx` for wallet-sign checkout.
- `contracts/blockster-settler/src/routes/build-tx.ts` — return partially-signed txs.
- `contracts/blockster-settler/src/routes/fund.ts` — **NEW** route for starter-fund endpoint.
- `contracts/blockster-settler/src/routes/payment-intents.ts` — add `payment_mode` support.
- `contracts/blockster-settler/src/config.ts` — verify `MINT_AUTHORITY` keypair is the right signer for fees (or use a dedicated `FEE_PAYER` keypair — arguably safer for key hygiene). **Decision point — see §5 Open Questions.**

### 4.6 Signing call sites (5 JS files)
- `assets/js/coin_flip_solana.js` — migrate to partially-signed tx pattern; replace `signAndSendTransaction` with `signTransaction` + manual submit.
- `assets/js/hooks/pool_hook.js` — same migration.
- `assets/js/hooks/airdrop_solana.js` — same migration.
- `assets/js/hooks/sol_payment.js` — same migration.
- **Additionally:** `assets/js/connect_wallet_hook.js`, `assets/js/wallet_transfer.js` — inspect for any direct wallet calls that bypass `__signer`.

### 4.7 Anchor programs
- `contracts/blockster-bankroll/programs/blockster-bankroll/src/instructions/*.rs` — **V1: no change required.** V2 (Phase 8): add optional `rent_payer` to `place_bet_*`, `settle_bet` (close constraint).
- `contracts/blockster-airdrop/programs/*/src/instructions/*.rs` — check `claim_airdrop` for rent-payer issues (likely same pattern).

### 4.8 Shop / Payment Intents
- `lib/blockster_v2/payment_intents.ex` — add `payment_mode` field.
- `lib/blockster_v2/orders/payment_intent.ex` — migration to add `payment_mode`.
- `lib/blockster_v2/payment_intent_watcher.ex` — unchanged (just detects inbound funding).
- Shop LiveViews — new "Pay with one click" button for wallet-sign mode.

### 4.9 Referrals
- `lib/blockster_v2/referrals.ex` — **BUG FIX needed regardless:** change referrer lookup from `smart_wallet_address` to `wallet_address` for Solana users (audit §9). Do this as part of Phase 2 — it's a prerequisite.

### 4.10 Fingerprint anti-sybil
- `lib/blockster_v2/accounts.ex.authenticate_email_with_fingerprint` — extend to accept Web3Auth users with optional fingerprint. Reuse the `user_fingerprints` table.
- Fingerprint conflict logic: if a Web3Auth email user signs up with a fingerprint that already belongs to a wallet user, block. Same logic as today.
- **Decision:** should fingerprint be REQUIRED for Web3Auth social signups? (Wallet signups don't check today.) Recommend: run it but don't block on failure (like today's wallet path). Reconsider if abuse emerges.

### 4.11 Bot system
- `lib/blockster_v2/bot_system/*` — NO changes. Bots stay on their server-generated keypairs, never touch Web3Auth.
- Bots' `auth_method` stays `"wallet"`.

### 4.12 Settings
- New "Connected accounts" section.
- Email linking for wallet users uses existing `EmailVerification` (no Web3Auth dependency).
- X/Telegram linking reuses existing OAuth / bot flows.

### 4.13 Admin
- `/admin/stats/players` — extend to search by email, x_handle, telegram_user_id (not just wallet).
- Player detail page — show `auth_method`, `web3auth_verifier`, `email`, `x_handle`, `telegram_username`.

### 4.14 Balance / PubSub
- `lib/blockster_v2/bux_minter.ex` — no change. Keyed by user_id + wallet_address.
- PubSub topics `"user:#{user_id}"` — no change.
- **Caveat:** if a user has multiple wallets (Phase 7+), `sync_user_balances_async` must know which wallet to sync. Current code assumes one wallet per user. This is fine for v1 (no multi-wallet linking).

### 4.15 Newsletter
- Existing newsletter flow (`lib/blockster_v2/newsletter.ex`, new migration `20260419_create_newsletter_subscriptions.exs`) — integrate with onboarding email step. If user already has a verified email from Web3Auth, offer an opt-in checkbox during onboarding's "profile" step.

### 4.16 Announcement banner / Member pages / Hub Live / Post Live
- No changes required. These read `current_user` which is populated identically regardless of auth method.

### 4.17 UserEvents
- Add `auth_method` metadata to `signup` and `session_start` events (already partially present, extend).
- New event: `email_added` when a wallet user links an email in settings.

### 4.18 Engagement Tracking
- `lib/blockster_v2/engagement_tracker.ex` — no change. Keyed by user_id.

### 4.19 AI Manager / Content Automation
- No changes required.

---

## 5. Open Questions / Decisions Required

1. **Dedicated fee-payer keypair vs. reusing `MINT_AUTHORITY`?** Default: dedicated `FEE_PAYER_KEYPAIR` for key hygiene. Top up weekly from a treasury wallet. (Decided; documented in Phase 4.)

2. **Phantom popup mitigation?** Could build session-key delegation. Complex. Defer to v2. Advertise email login for one-click betting.

3. **Telegram multiplier now or later?** Optional Phase 9. Not blocking v1.

4. **Required vs. optional fingerprint for Web3Auth email signups?** Optional (same as today's wallet path). Revisit if abuse emerges.

5. **Handle the "same email, different auth_method" collision?** v1: reject the second attempt with a clear error pointing to the existing account's sign-in method. Merge flow is v2+ if users complain.

6. **Mainnet rollout?** Gate social login by `BLOCKSTER_CHAIN` env var. Devnet enables first; mainnet follows after observing cost math on real traffic.

7. **Legal / KYC implications of Web3Auth MPC model?** Technically non-custodial; regulators may disagree. Brief legal check before mainnet. Not a v1 blocker.

8. **Analytics / attribution?** Track auth_method → retention. Add to existing analytics dashboard in Phase 10.

9. **Homepage hero "Connect Wallet" CTA?** Rename to "Sign in / Sign up". Product call.

10. **Program upgrade deploy authority:** Upgrade authority is the settler keypair (`6b4n...` per addresses.md). Confirm it has sufficient SOL and access before Phase 1 deploy.

---

## 6. Timeline Estimate

Sized for continuous AI-assisted work, one phase at a time, with user available for QA between phases.

| Phase | Effort | Depends on |
|---|---|---|
| 0. Prep + Prototype | ~1h setup + ~2h prototyping | — |
| 1. Anchor program upgrade (rent_payer) | ~2h | 0 (verified on-chain assumptions) |
| 2. Signer abstraction | ~1–2h | 1 (multi-signer becomes the new norm) |
| 3. Backend auth + user model | ~3–4h | 0 (Web3Auth project set up) |
| 4. Settler fee-payer + rent-payer wiring | ~2h | 1 + 2 |
| 5. Frontend Web3Auth hook + login UI | ~3–5h | 2 + 3 (+ `/frontend-design:frontend-design`) |
| 6. Onboarding adaptation | ~2h | 3 + 5 (+ `/frontend-design:frontend-design`) |
| 7. Shop / payment-intents | ~2h | 4 (+ `/frontend-design:frontend-design`) |
| 8. Settings / linking | ~2h | 3 (+ `/frontend-design:frontend-design`) |
| 9. Telegram multiplier (optional) | ~1h | 3 |
| 10. Final regression + rollout | ~1–2h coding + monitoring | all |

**Total critical path (Phases 0–8 + 10):** ~18–24 hours of focused work. Realistically **1–2 focused days** of continuous AI-assisted coding + user QA between phases + external setup (Web3Auth dashboard, Fly.io secrets, Telegram bot registration).

**Slowest single step:** Anchor program deploy + verification on devnet (~30–60 min for compile + buffer + upgrade + IDL publish). Not parallelizable with other work since it blocks Phase 4.

**External dependencies (time outside coding):**
- Web3Auth dashboard setup + verifier registration: ~30 min (user task; can be done during Phase 0 prototyping).
- Telegram bot registration: ~15 min.
- Fly.io staging deploy + secret staging: ~15 min.
- Manual UX QA across 6 login paths × desktop/mobile: ~1–2 hours.

---

## 7. Out of Scope (explicitly)

- Apple Pay / Google Pay as funding methods.
- Fiat on-ramp for new users (Helio exists for shop; not integrated into signup flow for v1).
- Account merging between wallet and Web3Auth users.
- Session-key delegation for Phantom users.
- Multi-wallet linking (one user = one primary wallet in v1).
- Mobile native app — out of scope; web PWA serves all mobile traffic.
- EVM-era users (legacy `auth_method = "email"` with Thirdweb smart wallets) — existing migration flow handles them. Not revisited here.

---

## 8. Quick-Reference File Changes

**New files:**
- `lib/blockster_v2/auth/web3auth.ex`
- `assets/js/hooks/signer.js`
- `assets/js/hooks/web3auth_hook.js`
- `priv/repo/migrations/20260420_*_add_web3auth_fields_to_users.exs`
- `priv/repo/migrations/20260420_*_add_payment_mode_to_payment_intents.exs`
- `priv/repo/migrations/20260420_*_add_rent_payer_to_bet_orders.exs` (if/as needed for any read-side tracking)
- `test/blockster_v2/auth/web3auth_test.exs`
- `test/blockster_v2/telegram_multiplier_test.exs` (if Phase 9)
- `contracts/blockster-bankroll/tests/place_bet_rent_payer.ts`
- `contracts/blockster-bankroll/tests/reclaim_rent_payer.ts`

**Modified files (high-touch):**
- `lib/blockster_v2/accounts.ex`
- `lib/blockster_v2/accounts/user.ex`
- `lib/blockster_v2/referrals.ex` (referrer lookup fix — Phase 3)
- `lib/blockster_v2_web/live/wallet_auth_events.ex`
- `lib/blockster_v2_web/controllers/auth_controller.ex`
- `lib/blockster_v2_web/components/wallet_components.ex` (via `/frontend-design:frontend-design`)
- `lib/blockster_v2_web/live/onboarding_live/index.ex` (via `/frontend-design:frontend-design`)
- `lib/blockster_v2_web/live/settings_live*` (via `/frontend-design:frontend-design`)
- `lib/blockster_v2_web/router.ex`
- `assets/js/coin_flip_solana.js` (partial-sign migration — Phase 2)
- `assets/js/hooks/pool_hook.js` (partial-sign migration — Phase 2)
- `assets/js/hooks/airdrop_solana.js` (partial-sign migration — Phase 2)
- `assets/js/hooks/sol_payment.js` (partial-sign migration — Phase 2)
- `assets/js/hooks/solana_wallet.js` (expose via `__signer` — Phase 2)
- `contracts/blockster-settler/src/services/bankroll-service.ts` (fee_payer + rent_payer — Phase 4)
- `contracts/blockster-settler/src/services/payment-intent-service.ts` (wallet_sign mode — Phase 7)
- `contracts/blockster-settler/src/routes/build-tx.ts`
- `contracts/blockster-settler/src/routes/payment-intents.ts`
- `contracts/blockster-settler/src/config.ts` (add FEE_PAYER keypair)
- `mix.exs` (Joken + Joken.JWKS deps)

**On-chain (Phase 1 — V1, NOT deferred):**
- `contracts/blockster-bankroll/programs/blockster-bankroll/src/instructions/place_bet_sol.rs` (add `rent_payer`)
- `contracts/blockster-bankroll/programs/blockster-bankroll/src/instructions/place_bet_bux.rs` (add `rent_payer`)
- `contracts/blockster-bankroll/programs/blockster-bankroll/src/instructions/settle_bet.rs` (`close = rent_payer`)
- `contracts/blockster-bankroll/programs/blockster-bankroll/src/instructions/reclaim_expired.rs` (`close = rent_payer`)
- `contracts/blockster-bankroll/programs/blockster-bankroll/src/state/bet_order.rs` (append `rent_payer: Pubkey`)
- `contracts/blockster-airdrop/programs/*` (same pattern where applicable)

---

*End of plan. Review + decide on the open questions in §5 before starting Phase 0.*
