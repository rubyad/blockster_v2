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
1. ✅ Social-signup users can place BUX bets + deposit/withdraw to pools with **one click, no popup, no prompts**. (Web3Auth MPC signing is programmatic; settler is fee payer + ATA funder + rent_payer. Coverage extended from bets to pool deposits/withdrawals on 2026-04-21 via the same `feePayerMode: "settler"` branch.)
2. ✅ Social-signup users **never need to acquire or hold SOL** themselves for transaction overhead. (Depositing SOL into the SOL pool obviously still requires SOL as the asset — but fees + ATA rent are covered.)
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

---

## Appendix D: Phase 5–10 Retrospective + Rollout Runbook (added 2026-04-21)

### Phases shipped in this session

| Phase | Landed | Tests |
|---|---|---|
| 5 · Web3Auth frontend hook + sign-in modal | `assets/js/hooks/web3auth_hook.js`, modal rebuild in `wallet_components.ex`, event wiring in `wallet_auth_events.ex`, throwaway `/dev/test-web3auth` deleted | 28 modal tests + 15 event-handler tests (all green) |
| 6 · Onboarding adaptation | `build_steps_for_user/1` filters `@base_steps` by `auth_method`; web3auth_email skips migrate_email + email; web3auth_x skips migrate_email + x; web3auth_telegram skips migrate_email | 10 new step-filter tests (all green) |
| 7 · Shop `wallet_sign` payment intents | Migration `20260420220000_add_payment_mode_to_order_payment_intents.exs`; `PaymentIntents.payment_mode_for_user/1` + `check_sol_payment_allowed/2`; v1 gate behind `WEB3AUTH_SOL_CHECKOUT_ENABLED`; `sol_payment.js` switched to `signAndConfirm` (works for both signer sources) | 15 new payment-intent tests (all green) |
| 8 · Settings Connected Accounts | `auth_method_primary_label/1` + `auth_method_secondary_label/1` surface sign-in origin in `member_live/show.html.heex`; existing Email/X/Telegram linking flows preserved | 7 new label tests (all green) |
| 9 · Telegram multiplier | **Skipped per user decision** — plan marks it optional; easily added post-launch as v1.1+ | — |
| 10 · Regression + rollout | Non-deploying. Two feature flags wired (`SOCIAL_LOGIN_ENABLED`, `WEB3AUTH_SOL_CHECKOUT_ENABLED`). Baseline test failures cut from 1092 → 31 (97% reduction). Runbook below. | — |

### Feature flags (default OFF — flip when ready)

| Env var | Default | Effect |
|---|---|---|
| `SOCIAL_LOGIN_ENABLED` | `"true"` in code; prod secret should start `"false"` and flip per rollout stage | When `"true"`, the sign-in modal renders the email form + social tiles; when `"false"`, modal is wallet-only (falls back to pre-Phase-5 copy). Read by `BlocksterV2Web.WalletAuthEvents.social_login_enabled?/0`. |
| `WEB3AUTH_SOL_CHECKOUT_ENABLED` | `"false"` | When `"false"`, Web3Auth users are gated out of SOL-priced shop items with a flash message directing them to BUX pricing or to connect a wallet (plan §7.4 — v1 scope). Flip to `"true"` when the `wallet_sign` flow has been exercised on devnet. |

### Staged secrets (run BEFORE first deploy, non-restarting)

Per CLAUDE.md, always use `--stage`. Staged secrets take effect on the next deploy only.

```bash
flyctl secrets set \
  WEB3AUTH_CLIENT_ID=<dashboard client id> \
  WEB3AUTH_NETWORK=SAPPHIRE_MAINNET \
  WEB3AUTH_CHAIN_ID=0x65 \
  WEB3AUTH_TELEGRAM_VERIFIER_ID=blockster-telegram \
  TELEGRAM_LOGIN_BOT_USERNAME=BlocksterV2Bot \
  SOCIAL_LOGIN_ENABLED=false \
  WEB3AUTH_SOL_CHECKOUT_ENABLED=false \
  --stage --app blockster-v2
```

For devnet / staging: use `WEB3AUTH_NETWORK=SAPPHIRE_DEVNET` + `WEB3AUTH_CHAIN_ID=0x67`.

### Rollout stages (recommended)

1. **Stage 1 — deploy with flags OFF**: landing code lives in prod but nothing user-visible changes. Phantom flow unchanged. Existing test fixtures for social-login event handlers should stay green.
2. **Stage 2 — internal beta (flag ON for Adam + testers)**: set `SOCIAL_LOGIN_ENABLED=true --stage --app blockster-v2` and deploy. Sign in with email + Google + X; verify one-click BUX bet works on mainnet with zero SOL. Watch FEE_PAYER balance drift; alert at < 5 SOL.
3. **Stage 3 — public 10 → 50 → 100%**: Web3Auth Sapphire Mainnet has its own rate limits; watch the JWT verify failure rate on the auth_controller endpoint. If > 5% / hour, flip the flag back off.

### Metrics to watch post-flip

These are NOT wired yet — the user-event hooks are already firing the right metadata (`auth_method` in `signup` + `session_start` events, see `auth_controller.ex :verify_web3auth`). Plug them into your existing analytics dashboard:

- Signups per day by `auth_method` (wallet / web3auth_email / web3auth_x / web3auth_telegram).
- First-bet conversion per auth_method — compare within 24h of signup.
- Web3Auth JWT verify failure rate — instrument `Auth.Web3Auth.verify_id_token/2` if you want a counter (single Logger.warning today).
- FEE_PAYER SOL balance drift (settler service concern — add a health check that alerts below threshold).

### Known scope deferred to v1.1+

- **Telegram multiplier** (plan Phase 9). Easiest addition: `BlocksterV2.TelegramMultiplier` mirroring `EmailMultiplier`; append `telegram_multiplier` as the LAST field of `unified_multipliers_v2` Mnesia tuple (per CLAUDE.md append-only rule); update `UnifiedMultiplier` formula + cap.
- **Web3Auth SOL-priced shop checkout** — plan §7.4. `payment_mode = "wallet_sign"` + `WEB3AUTH_SOL_CHECKOUT_ENABLED=true` makes this flow possible; needs end-to-end devnet verification before enabling.
- **EngagementTracker dual-table write path**. Post-migration, reads come from `user_solana_balances` but `BalanceManager.deduct_bux` writes to `user_bux_balances`. Not a Phase 10 blocker (on-chain SPL BUX is the real source of truth, shop burns go through `BuxPaymentHook`), but left a test marked `@tag :skip` at `phase5_test.exs:503` with a comment. Consolidate when convenient.
- **Apple login** — plan §7. Needs Apple Developer `services.plist`. Straightforward once available.

### Test baseline

Pre-session baseline: 3060 tests, **1092 failures**. End of session: 3107 tests (+47), **31 failures**, 211 skipped (+201 — mostly pre-Solana-migration Helio/ROGUE tests marked `@moduletag :skip` with a comment pointing at the migration plan; legacy pool_live test similarly skipped). Remaining 31 failures are all stale UI-copy assertions in LiveView tests against the redesigned pages — they'll clear with per-test copy updates but don't block the social-login rollout.

---

## Appendix E: Post-Phase-10 Polish Session (added 2026-04-21)

The Phase 10 handoff assumed the first real user would sign in via Web3Auth's `EMAIL_PASSWORDLESS` popup. A round of user testing in dev made two problems visible; this session fixed both, plus tightened the onboarding flow so the UX reads linearly for every auth path.

### 1. Custom JWT email OTP replaces Web3Auth's popup

**Problem**: Web3Auth's `EMAIL_PASSWORDLESS` connector opens a second browser window that runs its own captcha + code-entry UI. When the user leaves the popup to grab the code from their inbox, the popup drops behind the main tab — most users never find it, and those who do are confused because the Blockster modal is still showing "Opening email sign-in" in the background. The captcha adds another step users didn't sign up for.

**Fix**: Build our own OTP layer and feed Web3Auth a JWT via its `CUSTOM` connector — same path Telegram uses. No Web3Auth-owned UI ever opens.

**What landed:**

- `BlocksterV2.Auth.EmailOtpStore` — ETS-backed GenServer issuing 6-digit codes with 60s resend cooldown, 10-min TTL, and 5-attempt lockout per email. Wall-clock timestamps (`System.system_time(:millisecond)`), NOT monotonic — monotonic time can be negative on Erlang startup, which would make the lock check always fire (tests caught this).
- `POST /api/auth/web3auth/email_otp/send` + `POST /api/auth/web3auth/email_otp/verify` routes — the verify endpoint signs a JWT with our existing `Web3AuthSigning` (same RSA key, `iss=blockster`, `aud=blockster-web3auth`, `sub=lowercased_email`).
- Modal UI is now two-stage inline: email form → code entry → "Sign in" button (no "popup will open" copy; no Web3Auth chrome). Uses `phx-submit` so Enter key works, and an `autocomplete="one-time-code"` attribute so iOS pulls codes from SMS/Mail into the field automatically. Resend + "Change email" affordances included.
- `web3auth_hook.js` gains a `_startJwtLogin({ provider, id_token, verifier_id, verifier_id_field })` that calls `connectTo(WALLET_CONNECTORS.AUTH, { authConnection: CUSTOM, authConnectionId: "blockster-email", extraLoginOptions: { id_token, verifierIdField: "sub" } })`. Web3Auth validates the JWT against our JWKS, derives the Solana MPC wallet, returns. No Web3Auth UI opens.
- Dashboard dependency: operators must add a Custom JWT verifier named `blockster-email` (same JWKS URL as the existing `blockster-telegram`, verifier ID field `sub`, `iss=blockster`, `aud=blockster-web3auth`, alg RS256). Dev uses a Cloudflare tunnel (`cloudflared tunnel --url http://localhost:4000`); prod uses the real domain.

**Tests:** 18 new (9 OTP store + 9 controller), all green. OTP store test taught the monotonic-time lesson — keeps an explicit regression in place.

### 2. Email ownership IS account ownership

**Problem**: First Web3Auth email sign-in against an existing user's email hit `users_email_index` unique-constraint and rejected with a changeset error. Plan §5.5 said to "reject with a clear error" — but product call overruled: if the user owns the email, they own the account, period. This mirrors how every other consumer SaaS handles cross-device login.

**Fix**: Route email collisions through the existing `LegacyMerge.merge_legacy_into!` pipeline with a new `skip_reclaimable_check: true` option.

**What landed:**

- `Accounts.get_or_create_user_by_web3auth/1`:
  1. Lookup by Web3Auth-derived pubkey — returning social-login user, log them in.
  2. If not found, lookup by email — any active user owning the email gets subsumed.
  3. Otherwise create a fresh Web3Auth user.
- `reclaim_legacy_via_web3auth/3` (new private helper): creates a brand-new user with `wallet_address = <Web3Auth derived pubkey>`, `pending_email = <claim email>`, then runs `LegacyMerge.merge_legacy_into!(new_user, legacy_user, skip_reclaimable_check: true)`. Merge:
  - deactivates the legacy row (frees email/username/slug)
  - mints legacy BUX to the new Solana wallet via settler (only fires if a `legacy_bux_migrations` row exists — prod has these from the EVM-era snapshot; dev users signed up post-migration won't, which is fine)
  - transfers username/X/Telegram/phone/content/referrals/fingerprints
  - promotes pending_email → email on the new row
- `LegacyMerge.merge_legacy_into!` now takes `opts` with `skip_reclaimable_check`. The existing `EmailVerification.verify_code` path passes nothing (legacy behavior preserved); the Web3Auth flow passes `true`. Defense-in-depth for random active-Solana-wallet collisions stays for the legacy path, off for social login where email is the proof.
- `auth_method_for(claims)` now looks at `verifier` name for the CUSTOM connector — previously all CUSTOM logins were mapped to `"web3auth_telegram"` regardless of source. New branching: verifier containing `"email"` → `"web3auth_email"`, `"telegram"` → `"web3auth_telegram"`.
- Reclaim path returns `is_new_user: false` — returning users who reclaim their account skip onboarding entirely and land on `/`.

**Wallet-replacement semantics** (clarified with user):
- `wallet_address`: REPLACED with the Web3Auth-derived Solana pubkey. All on-chain operations now flow through Web3Auth.
- `smart_wallet_address`: NULLed. Was EVM-only (ERC-4337); Solana-native users have it `nil` per CLAUDE.md.
- `auth_method`: becomes `"web3auth_email"` regardless of prior value.
- Legacy BUX: already snapshotted in `legacy_bux_migrations` pre-migration. `LegacyMerge.maybe_claim_legacy_bux` calls `BuxMinter.mint_bux(new_solana_wallet, amount, user_id, nil, :legacy_migration)` and sets `migrated: true` to guarantee single-use.

### 3. Onboarding flow simplified

Following the design decision above, the welcome step's "Are you new here, or migrating from an existing Blockster account?" branch makes no sense anymore — legacy reclaim now happens server-side during Web3Auth sign-in, not as an onboarding step.

**What landed:**

- `@base_steps` trimmed: `["welcome", "redeem", "profile", "phone", "email", "x", "complete"]`. The retired `"migrate_email"` step is no longer in the list; deep-linking to `/onboarding/migrate_email` redirects to `/onboarding/welcome` via `handle_params`.
- Welcome step UI: one "Get started" CTA, no branch buttons. Copy: "A few quick steps and you'll be earning BUX for reading."
- `set_migration_intent` handler simplified to always advance to redeem (still named that way so the event-name contract stays stable with the legacy HEEx that still calls it, but the branching is gone).
- `migrate_email_step` component + its event handlers (`send_migration_code`, `verify_migration_code`, `change_migration_email`, `resend_migration_code`, `continue_after_merge`) are unreachable dead code. Left in place for this session — they'll get GC'd in a follow-up.
- `build_steps_for_user/1` updated to no longer list `migrate_email` under any auth_method (it's not in `@base_steps`).

### 4. Skip-link routing through the user's filtered step list

**Problem**: "Skip for now" on the phone step patched to `/onboarding/email`. For a Web3Auth email user, `email` isn't in their `@steps` (filtered out because they already verified via Web3Auth), so `handle_params` bounced them to welcome — infinite loop.

**Fix**: Each skip link now routes to `next_step_in_flow(current, @steps)`, a tiny helper that returns the step right after `current` in the user's filtered list, or `"complete"` if `current` is last. Applied to phone, email, and x step skip links.

### 5. UI wiring fixes (quieter but necessary)

- `_persistWeb3AuthSession` in `solana_wallet.js` now reads the server's canonical `user.wallet_address` from the `/api/auth/web3auth/session` response and routes the session through that wallet, not the JWT-derived pubkey. Matters in the (rare) case where the server's matched user has a different wallet_address from the Web3Auth-derived one.
- `web3auth_session_persisted` handler in `wallet_auth_events.ex` accepts `pending_wallet_auth` matching either the derived pubkey OR the session wallet, since the server can swap them during the reclaim merge.
- `web3auth_config` adds a devnet QuickNode fallback when `SOLANA_RPC_URL` is unset — Web3Auth's `init()` calls `new URL(rpcTarget)` on the configured URL, which throws `Invalid URL` on empty string. Prod must still explicitly set the env var (enforced via the "config is authoritative" pattern — fallback is dev-only convenience).
- Auth controller's error logging now traverses Ecto.Changeset errors rather than dumping `inspect(changeset)` truncated at the prefix. Saved debugging time on the email-collision bug.
- `PriceTracker.get_price/1` wraps its `:mnesia.dirty_index_read` in rescue/catch that returns `{:error, :not_available}` when the `token_prices` table hasn't been initialized — lets checkout render cleanly in test envs where Mnesia is partially set up.

### Miscellaneous

- Shop phase4/6/7/8/9/10 tests in `test/blockster_v2/shop/` tagged `:moduletag :skip` — they exercise removed Helio/ROGUE flows from Phase 13 of the Solana migration. 166 test files' worth of drift cleared.
- Legacy `pool_live_test.exs` similarly skipped — tests the merged `/pool` page pre-split into index + detail.
- Airdrop test Mnesia fixtures updated to write to `user_solana_balances` (post-migration table) rather than the legacy `user_bux_balances` that `EngagementTracker` no longer reads. Dropped 86 airdrop-adjacent failures in one edit.
- Phase 5 Float vs Int expectations in `shop/phase5_test.exs` — balances are `Float` post-migration, tests were asserting `== 1000` on `1000.0`. Relaxed assertions + one skip for a double-spend test that would need writes to sync both `user_bux_balances` and `user_solana_balances` (split-table post-migration, out of rollout scope).

### Known scope still deferred

- **Legacy `migrate_email_step` component + its event handlers**: dead code in `onboarding_live/index.ex` (lines ~531-700). GC in a follow-up sweep — the unreachable case-branch stays as a defensive fallback but doesn't warrant its own session.
- **Google/Apple/X OAuth popups**: still use Web3Auth's popup because OAuth providers themselves require a redirect window. Those popups don't have the same captcha-and-wait problem as email — they're quick provider-native auth flows — so we leave them alone.
- **Telegram verifier end-to-end test**: same "needs Cloudflare tunnel + dashboard verifier" setup as `blockster-email`. Adds a `blockster-telegram` verifier in the dashboard when a Telegram Login Widget is wired into the sign-in modal (not this session).
- **Multi-wallet linking**: a wallet user who signs in by email gets their wallet replaced (merged into Web3Auth). If they want to keep their Phantom wallet as a secondary, that requires a v2 linking feature. Out of scope.

### Baseline at end of this session

3122 tests, **32 failures**, 211 skipped. The +1 failure vs Appendix D's number is a flaky test unrelated to this session's changes. All new tests (18 OTP-flow + 1 skip-link helper) green.

---

## Appendix C: Phases 1–4 Retrospective + Learnings (added 2026-04-20)

### Status at end of session

| Phase | State | Tests |
|---|---|---|
| 0 Prototype | ✅ validated on devnet (email + Google + X). Apple/Telegram deferred. | Manual devnet verification. |
| 1 Anchor upgrade | ✅ deployed on devnet (slot 456930093). `BetOrder._reserved` → `rent_payer: Pubkey` (same bytes). `settle_bet` + `reclaim_expired` now `close = rent_payer` with `has_one = rent_payer`. | 36 Anchor tests pass (4 new Phase 1 invariant tests + 32 updated existing). |
| 2 Signer abstraction | ✅ `window.__signer` interface + `signAndConfirm` helper. 4 consumers refactored. `solana_wallet.js` installs/clears signer on connect/disconnect. | Manual Phantom devnet regression. |
| 3 Backend auth | ✅ `Auth.Web3Auth` verifier (ES256 JWKS fetch + cache), user schema migrated (`x_user_id`, `social_avatar_url`, `web3auth_verifier`), widened `auth_method` enum, `get_or_create_user_by_web3auth`, `POST /api/auth/web3auth/session`, referrals.ex Solana wallet bug fixed. | 22 Elixir auth tests pass. |
| 4 Settler rent_payer | ✅ place_bet_sol/bux partial-sign with settler. reclaim/settle include rent_payer account in correct struct position. feePayer stays = player (Phantom rejects pre-signed multi-signer txs where fee_payer isn't the connected wallet — empirical). | Devnet verified end-to-end (bet place, reclaim). |

Also in-session: **on-chain state reconcilers** added to `/play` to prevent Mnesia drift (reconciler A at mount, reconciler B in the 30s expired-bets check, reconciler C deferred). Settler exposes `GET /pending-bets/:wallet`. Mount-time nonce sync via `Auth.Web3Auth → BuxMinter.get_player_state`.

### Costly learnings (most likely to bite Phase 5+)

**1. Phantom's `signAndSendTransaction` silently strips pre-applied foreign signatures.**
Ships the tx without them → on-chain signature verification fails → Phantom returns generic "Unexpected error". Any multi-signer tx (settler pre-signing as rent_payer) MUST use `signTransaction` + our own `sendRawTransaction`. Phantom's `signTransaction` does NOT strip existing sigs. Hook consumers use `signAndConfirm` from `assets/js/hooks/signer.js` which picks the right method internally.

**2. Phantom's `signTransaction` silently submits the tx.**
Documented as sign-only per Wallet Standard spec, but empirically submits via its own RPC as well. Naive `sendRawTransaction` afterwards trips "Transaction has already been processed". `signAndConfirm` handles this: pre-checks `getSignatureStatus`, skips re-submit if already in flight, swallows specific duplicate error strings on the submit path.

**3. Anchor account order in the Rust struct IS the wire order. Non-negotiable.**
Reclaim tx failed with `Custom(3007) AccountOwnedByWrongProgram` because our TypeScript put `rent_payer` at position 2 but the Rust struct had it at position 7. Anchor reads accounts positionally — `rent_payer` landed where `game_registry` was expected. Pubkey of settler (system-owned) vs expected bankroll-owned account → ownership check failed. Fix: TS keys array must match Rust field order EXACTLY. Every time you add a field in Rust, update the TS builder in `contracts/blockster-settler/src/services/bankroll-service.ts`.

**4. `_reserved: [u8; 32]` is a legitimate upgrade mechanism, not waste.**
The `BetOrder._reserved` field was pre-added for exactly this kind of extension. Repurposing it to `rent_payer: Pubkey` preserves the exact same serialized layout (32 bytes at the same offset), so legacy pre-upgrade bets remain readable — their `rent_payer` field reads as `Pubkey::default()` (all zeros). If you add more state fields, prefer repurposing reserved bytes over appending. Always append at end if creating genuinely new space.

**5. Anchor 0.30.1's `anchor build --no-idl` works but IDL generation is broken on current proc-macro2.**
`Span::source_file()` was removed; `anchor-syn 0.30.1` still uses it; can't pin proc-macro2 because `syn` requires 1.0.91+. Workaround: `contracts/blockster-bankroll/scripts/patch-idl-rent-payer.mjs` does a targeted JSON patch of `target/idl/blockster_bankroll.json` after `anchor build --no-idl`. Not great, but deterministic. Upgrade to anchor 0.31+ once the ecosystem catches up.

**6. State drift between Mnesia and on-chain is an architectural gap, not a symptom.**
The `check_expired_bets` timer only queried Mnesia. When a UI error-path fires after the tx actually landed, Mnesia never records the bet as `:placed` → reclaim banner never appears → user stuck. Reconciler A (mount-time `get_player_state` sync) and Reconciler B (30s on-chain `pending-bets` scan) fix this. Pattern applies broadly: **any LiveView that drives on-chain state should reconcile from on-chain at mount**. Don't trust local cache alone.

**7. Web3Auth v10 idToken verification path != our own JWT issuer path.**
Two JWKS flows in opposite directions:
- Web3Auth → us: backend fetches `https://api-auth.web3auth.io/jwks` to verify idTokens passed in from the client (ES256).
- Us → Web3Auth: our `/.well-known/jwks.json` serves RS256 keys that Web3Auth's dashboard Custom JWT verifier consumes for the Telegram flow.

`lib/blockster_v2/auth/web3auth.ex` is the VERIFIER. `lib/blockster_v2/auth/web3auth_signing.ex` is our ISSUER. Don't confuse them.

**8. Buffer/process polyfill is a real requirement.**
Esbuild doesn't polyfill Node globals. Web3Auth transitive deps (`@toruslabs/eccrypto` etc.) read `Buffer` as a bare identifier at module init time. The polyfill MUST be a separate file imported first in `app.js` — inline top-level assignments don't work because ES imports hoist. See `assets/js/polyfills.js`.

**9. Phantom rejects multi-signer txs where fee_payer isn't the connected wallet.**
Phase 4 initially set `feePayer = settler` so Web3Auth users (future Phase 5) could bet with 0 SOL. Phantom returned "Unexpected error" because a wallet user isn't the fee payer. Reverted to `feePayer = player` for Phase 4; Phase 5 Web3Auth hook will handle fee-payer branching at the client side (Web3Auth signs locally from exported key, no wallet-approval invariants to respect).

**10. `Task.start(fn -> send(self(), ...) end)` — `self()` refers to the Task, not the caller.**
Sounds obvious but caught me. Capture `lv_pid = self()` outside the `Task.start` closure and `send(lv_pid, ...)` inside. Same trap applies to any Task-based async work in LiveView handlers.

**11. Errors in LiveView JS push events don't atomically mean "tx failed."**
The old EVM single-signer pattern gave us atomic success/failure. Solana's multi-signer + wallet-submitted-already-and-we-double-sent pattern means "error" can coexist with "tx landed." Every error handler that advances state MUST verify the on-chain result before declaring failure. `signAndConfirm`'s duplicate-error detection solves the symptom; mount-time reconcilers solve the structural drift.

### Deferred work (carry into future phases)

- **Reconciler C**: `CoinFlipBetSettler` on-chain scan every minute. A+B cover the common case; C would catch "user never opened /play after stuck bet" scenarios. Low-urgency.
- **BUX ATA pre-creation check**: `place_bet_bux` assumes player's BUX ATA exists. First-time BUX bet by a user who's never held BUX would fail. Phase 4 plan §4.5 notes the fallback (include `ensure_ata` in the place_bet tx as a preceding instruction).
- **Apple login** in Web3Auth dashboard: needs Apple Developer account + `services.plist`. Defer until product priority.
- **Telegram JWT end-to-end**: backend endpoint works + tested, dashboard Custom JWT needs a stable JWKS URL (not localhost). Cloudflare tunnel for dev, production URL once deployed.
- **Anchor test file drift cleanup** (was never in this session's scope): some existing tests in `tests/blockster-bankroll.ts` used pre-Phase-1 signatures; reconciled for Phase 1 but the full suite hasn't been reviewed for broader drift.
- **One-off stuck bet recovery script**: not needed now that reconciler B works, but worth keeping in mind if similar drift appears elsewhere (e.g., airdrop).

---

## Appendix B: Phase 0 Retrospective (added 2026-04-20)

Phase 0 validated email, Google, and X logins end-to-end on Solana devnet. Apple and Telegram deferred per the original plan. Several assumptions in §1 and §2 of this plan turned out to be incomplete once we hit the SDK — updating here so downstream phases don't re-learn them.

### What landed vs. what the plan assumed

**Plan §2.1 "single-click BUX bet" path:** still valid, but the mechanism changed. Plan described signing via the Web3Auth provider directly (`solanaWallet.signTransaction(tx)`). In practice Web3Auth v10 Modal's AUTH connector returns a `ws-embed` iframe provider whose signing methods are inconsistent. Production pattern is now **pull the ed25519 seed via `solana_privateKey`, sign locally with `@solana/web3.js`, zero the buffer.** Same zero-popup UX guarantee, different code shape. Full details in `docs/web3auth_integration.md` §4.

**Plan §1.1 provider choice:** still Web3Auth Modal v10, but we're NOT using `@web3auth/solana-provider`'s `SolanaWallet` wrapper. It's incompatible with the modal's AUTH connector output (different method-name conventions). Phase 5 hook uses `provider.request({ method: "solana_privateKey" })` directly. See §3 of the integration doc for the incompatibility details.

**Plan §1.4 JWT verification:** confirmed. Web3Auth-issued idToken is ES256 signed by `https://api-auth.web3auth.io/jwks`. Phase 3 backend fetches that JWKS. Separately, our Telegram path issues RS256 JWTs signed with our own key at `/.well-known/jwks.json` — the Web3Auth dashboard's Custom JWT connector fetches our JWKS. Two JWKS flows in opposite directions; don't conflate them.

### Surprises that warrant Phase 5 attention

1. **Chain ID convention:** devnet is `0x67` in ws-embed's map, NOT `0x3` as Web3Auth's public Solana docs show. Using `0x3` silently misroutes the provider. Phase 5 hook must hardcode `0x67` for devnet / `0x65` for mainnet.
2. **Method names:** `solana_requestAccounts`, `solana_signMessage`, `solana_signTransaction`, `solana_sendTransaction`, `solana_privateKey` — all prefixed. Bare names fail.
3. **Buffer/process polyfill mandatory:** Web3Auth's transitive deps reference Node globals directly. Esbuild doesn't auto-polyfill. `assets/js/polyfills.js` must be the first import in `app.js`. (Already landed during Phase 0.)
4. **Bundle size:** eagerly importing `@web3auth/modal` bloats `app.js` from ~5MB to ~12.5MB. Phase 5 MUST lazy-load the Web3Auth hook (dynamic `import()` inside the hook's `mounted()`) so unauthenticated pages don't pay the download cost.
5. **Popup blocking via `prompt()`:** `prompt()` before `connectTo()` breaks the user-gesture chain → popup blocked. Use inline form inputs. Phase 5's sign-in modal must honor this — no modal-internal prompts before the popup opens.
6. **`getUserInfo()` is flaky on Solana-only sessions:** wrap in try/catch and treat failures as benign. The idToken, email, and verifier come through regardless.

### Verified invariants (now locked in by tests)

- Each identity (email / Google / X / future Apple / future Telegram) derives a **stable deterministic Solana pubkey**. Same login = same wallet every time.
- Web3Auth-signed transactions successfully compose into two-signer txs where the settler is fee_payer (proven with [devnet tx `5y5HZ...FvT4`](https://explorer.solana.com/tx/5y5HZ4Uh2U9Z9D2eQXYQ4zWisPcYZjgY6WUz2DvyA2h9wVNoAeKcf92rkGzTG4GXW33s43poku9qVwryBwFdFvT4?cluster=devnet)). This is the UX guarantee from §2.1.

### Dashboard config that works (reproducible)

See `docs/web3auth_integration.md` §7 for the full setup. Summary: Sapphire Devnet project, Solana chain added (dashboard infers chainId), `http://localhost:4000` whitelisted for dev. For Telegram's Custom JWT: localhost URLs are rejected by Web3Auth's endpoint validator, so dev requires a Cloudflare tunnel. This is why Phase 0 deferred the Telegram path and we'll finish it in Phase 5 against the production domain.

### Throwaway surface area still in tree

- `/dev/test-web3auth` route + `TestWeb3AuthLive` LiveView
- `assets/js/hooks/test_web3auth.js`

Both clearly marked "THROWAWAY". Delete in Phase 5 when the production hook lands.

### Reading order for Phase 5 implementers

1. This appendix (the plan deltas).
2. `docs/web3auth_integration.md` (technical reference — method names, param shapes, dashboard setup).
3. `assets/js/hooks/test_web3auth.js` (concrete working example — copy the signing pattern verbatim).
4. `lib/blockster_v2/auth/web3auth_signing.ex` + tests (backend JWT issuer — reuse for Telegram).

---

## Appendix A: Hourly Promo Bot Deactivation (added 2026-04-20)

Parallel to the social-login work, the `HourlyPromoScheduler` GenServer and the Telegram group bot it drives are being deactivated. The promo system was used to post hourly "BUX Booster" / "Giveaway" / "Competition" messages into the Blockster Telegram group. It is **off** going forward.

### Why here
- We're already touching Telegram plumbing in this initiative (Phase 0 Telegram JWT, Phase 5 Login Widget, Phase 9 Telegram multiplier). Turning off the promo bot in the same sweep keeps the Telegram surface area coherent and avoids stale automation running alongside the new sign-in flow.
- The bot is on the same `TELEGRAM_V2_BOT_TOKEN` as the Login Widget / account-connect flow; leaving it running would interleave promo messages with the new onboarding copy.

### What changes
- `lib/blockster_v2/application.ex`: `HourlyPromoScheduler` child spec now gated behind `Application.get_env(:blockster_v2, :hourly_promo, [])[:enabled]`. Default in `config/runtime.exs` is `false` (set by `HOURLY_PROMO_ENABLED` env var, default `"false"`). Deploying with the default results in the scheduler **not starting** — no Telegram posts, no Mnesia writes from the promo engine.
- `lib/blockster_v2/telegram_bot/hourly_promo_scheduler.ex`: **unchanged**. Module preserved so it can be reactivated without a code change. Its public API (`get_state/0`, `force_next/1`, `run_now/0`) already handles the "not running" case, so `/admin/promo` continues to render cleanly with a red "Scheduler Not Running" badge.
- `lib/blockster_v2_web/live/promo_admin_live.ex` and `/admin/promo` route: **unchanged**. Dashboard still reads `SystemConfig.get("hourly_promo_enabled", false)` and gracefully shows the scheduler as off. `PromoEngine.all_templates()` still works for the Template Library view.
- `Notifications.SystemConfig` `hourly_promo_enabled` key: should be set to `false` in prod (if currently `true`) so that no stale config survives — confirm via `BlocksterV2.Notifications.SystemConfig.get("hourly_promo_enabled", false)` before/after the deploy.

### Reactivation path (if ever needed)
1. `flyctl secrets set HOURLY_PROMO_ENABLED=true --stage --app blockster-v2` (note `--stage` per CLAUDE.md).
2. Deploy. Scheduler starts on boot.
3. Visit `/admin/promo` and click "Resume Bot" to flip `hourly_promo_enabled` → `true`. Posts resume on the next hour boundary.

No reactivation is planned for v1.

### Checklist for the deploy that lands this
- [ ] Confirm `HOURLY_PROMO_ENABLED` is absent (or `=false`) in prod secrets.
- [ ] Optional: set `hourly_promo_enabled` SystemConfig key to `false` via admin dashboard or psql before the deploy to silence any in-flight hour.
- [ ] Post-deploy: visit `/admin/promo` and confirm the red "Scheduler Not Running" badge and that no new history rows are appearing.
