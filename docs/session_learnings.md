# Session Learnings Archive

Historical bug fixes, feature implementations, and debugging notes moved from CLAUDE.md to reduce system prompt size. These are preserved for reference but rarely needed in day-to-day development.

For active reference material, see the main [CLAUDE.md](../CLAUDE.md).

---

## Table of Contents
- [Broadcast inside `Repo.transaction` races the commit — subscribers see pre-commit state](#broadcast-inside-repotransaction-races-the-commit--subscribers-see-pre-commit-state-2026-04-24)
- [Idempotent post-paid processing via the `fulfillment_notified_at` stamp](#idempotent-post-paid-processing-via-the-fulfillment_notified_at-stamp-2026-04-24)
- [Web3Auth mobile popup fails silently — switch to `uxMode: "redirect"` + sessionStorage hint](#web3auth-mobile-popup-fails-silently--switch-to-uxmode-redirect--sessionstorage-hint-2026-04-24)
- [`auth_method` funneling obscures downstream display — keep provider identity distinct](#auth_method-funneling-obscures-downstream-display--keep-provider-identity-distinct-2026-04-24)
- [Settler `getSignaturesForAddress` lags balance — record buyer-side tx sig as authoritative](#settler-getsignaturesforaddress-lags-balance--record-buyer-side-tx-sig-as-authoritative-2026-04-24)
- [Hand-rolling SPL `BurnChecked` avoids `@solana/spl-token` bundle bloat](#hand-rolling-spl-burnchecked-avoids-solanaspl-token-bundle-bloat-2026-04-24)
- [Pool cost-basis bug — `|> assign(…)` inside render/1 does NOT touch the socket](#pool-cost-basis-bug--assign--inside-render1-does-not-touch-the-socket-2026-04-22)
- [CF-01 InvalidServerSeed — on-chain commitment race, NOT Mnesia overwrite](#cf-01-invalidserverseed-on-chain-commitment-race-not-mnesia-seed-overwrite-2026-04-22)
- [Migrations aren't on the `mix test` compile path — extract logic to `lib/`](#migrations-arent-on-the-mix-test-compile-path--extract-logic-to-lib-2026-04-22)
- [Test-assertion gotchas from Phase 1 + 2](#test-assertion-gotchas-from-phase-1--2)
- [Mnesia index idempotency via runtime add_table_index](#mnesia-index-idempotency-via-runtime-add_table_index-2026-04-22)
- [Tailwind Typography img Margins Hijacked a Widget Header — Check Computed Styles First](#tailwind-typography-img-margins-hijacked-a-widget-header--check-computed-styles-first-apr-2026)
- [Coin Flip Widgets: Copy Mocks Verbatim — Never Rebuild From Scratch](#coin-flip-widgets-copy-mocks-verbatim--never-rebuild-from-scratch-apr-2026)
- [Notification.@valid_types Silent Validation Failure Swallowed Reward Records](#notificationvalid_types-silent-validation-failure-swallowed-reward-records-apr-2026)
- [LiveView Modal Backdrop: Use phx-click-away, NOT phx-click + stop_propagation](#liveview-modal-backdrop-use-phx-click-away-not-phx-click--stop_propagation-apr-2026)
- [Sticky Banners and Animated-Height Headers: Make the Banner a Child of the Header](#sticky-banners-and-animated-height-headers-make-the-banner-a-child-of-the-header-apr-2026)
- [Legacy Account Reclaim — LegacyMerge Implementation Gotchas](#legacy-account-reclaim--legacymerge-implementation-gotchas-apr-2026)
- [Solana RPC State Propagation: Never Chain Dependent Txs Back-to-Back](#solana-rpc-state-propagation-never-chain-dependent-txs-back-to-back-apr-2026)
- [Solana Tx Reliability: Priority Fees + Confirmation Recovery](#solana-tx-reliability-priority-fees--confirmation-recovery-apr-2026)
- [Payout Rounding: Float.round vs On-Chain Integer Truncation](#payout-rounding-floatround-vs-on-chain-integer-truncation-apr-2026)
- [LP Price Chart History Implementation](#lp-price-chart-history-implementation-apr-2026)
- [Solana Wallet Field Migration Bug](#solana-wallet-field-migration-bug-apr-2026)
- [Bot Wallet Solana Migration](#bot-wallet-solana-migration-apr-2026)
- [Non-Blocking Fingerprint Verification](#non-blocking-fingerprint-verification-mar-2026)
- [FateSwap Solana Wallet Tab](#fateswap-solana-wallet-tab-mar-2026)
- [Number Formatting in Templates](#number-formatting-in-templates)
- [Product Variants](#product-variants)
- [X Share Success State](#x-share-success-state)
- [Tailwind Typography Plugin](#tailwind-typography-plugin)
- [Libcluster Configuration](#libcluster-configuration-dev-only)
- [Upgradeable Smart Contract Storage Layout](#upgradeable-smart-contract-storage-layout---critical)
- [Account Abstraction Performance Optimizations](#account-abstraction-performance-optimizations-dec-2024)
- [BUX Booster Smart Contract Upgrades (V3-V7)](#bux-booster-smart-contract-upgrades-dec-2024)
- [BUX Booster Balance Update After Settlement](#bux-booster-balance-update-after-settlement-dec-2024)
- [Multi-Flip Coin Reveal Bug](#multi-flip-coin-reveal-bug-dec-2024)
- [House Balance & Max Bet Display](#house-balance--max-bet-display-dec-2025)
- [Infinite Scroll for Scrollable Divs](#infinite-scroll-for-scrollable-divs-dec-2024)
- [Mnesia Pagination Pattern](#mnesia-pagination-pattern-dec-2024)
- [Recent Games Table Implementation](#recent-games-table-implementation-dec-2024)
- [Unauthenticated User Access to BUX Booster](#unauthenticated-user-access-to-bux-booster-dec-2024)
- [Recent Games Table Live Update on Settlement](#recent-games-table-live-update-on-settlement-dec-2024)
- [Aggregate Balance ROGUE Exclusion Fix](#aggregate-balance-rogue-exclusion-fix-dec-2024)
- [Provably Fair Verification Fix](#provably-fair-verification-fix-dec-30-2024)
- [Contract V4 Upgrade](#contract-v4-upgrade---removed-server-seed-verification-dec-30-2024)
- [ROGUE Betting Integration Bug Fixes](#rogue-betting-integration---bug-fixes-and-improvements-dec-30-2024)
- [BetSettler Bug Fix & Stale Bet Cleanup](#betsettler-bug-fix--stale-bet-cleanup-dec-30-2024)
- [BetSettler Premature Settlement Bug](#betsettler-premature-settlement-bug-dec-31-2024)
- [Token Price Tracker](#token-price-tracker-dec-31-2024)
- [Contract Error Handling](#contract-error-handling-dec-31-2024)
- [GlobalSingleton for Safe Rolling Deploys](#globalsingleton-for-safe-rolling-deploys-jan-2-2026)
- [NFT Revenue Sharing System](#nft-revenue-sharing-system-jan-5-2026)
- [BuxBooster Performance Fixes](#buxbooster-performance-fixes-jan-29-2026)
- [BuxBooster Stats Module](#buxbosterstats-module-feb-3-2026)
- [BuxBooster Player Index](#buxbooster-player-index-feb-3-2026)
- [BuxBooster Stats Cache](#buxbooster-stats-cache-feb-3-2026)
- [BuxBooster Admin Stats Dashboard](#buxbooster-admin-stats-dashboard-feb-3-2026)
- [AirdropVault V2 Upgrade](#airdropvault-v2-upgrade--client-side-deposits-feb-28-2026)
- [NFTRewarder V6 & RPC Batching](#nftrewarder-v6--rpc-batching-mar-2026)
- [Engagement Tracker Silent Failure — `#post-content` Selector Miss After Redesign](#engagement-tracker-silent-failure--post-content-selector-miss-after-redesign-apr-2026)

---

## Broadcast inside `Repo.transaction` races the commit — subscribers see pre-commit state (2026-04-24)

**Symptom**: user completes a shop SOL payment, JS confirms on-chain, server-side `PaymentIntentWatcher` fires, `mark_funded/3` flips order to `paid`, PubSub broadcast fires, LV receives `{:order_updated, order}` — but LV's handler re-reads the order and sees `status != "paid"`, skips the step transition. User has to refresh to see the confirmation page.

**Root cause**: `PaymentIntents.mark_funded/3` called `broadcast_order(order)` **inside** its `Repo.transaction` block. PubSub delivery is async but `Phoenix.PubSub.broadcast/3` fires immediately on send — the subscriber's process may be scheduled + run its handler before the enclosing transaction has committed. When the handler does `Orders.get_order(updated_order.id)` on a **different DB connection** (one not participating in the uncommitted transaction), that connection reads the pre-update state. Net effect: broadcast delivered, subscriber handled, but the DB read inside the subscriber returned stale data.

**Why balance refresh still worked and obscured the diagnosis**: the balance refresh path (`refresh_token_balances_async/1`) fired in a spawned `Task` that started later, after the transaction had committed — so the Task's DB reads saw the post-commit state. User saw balance drop (convinced payment landed) but confirmation page still stuck on the pending step.

**Fix**: broadcast outside the transaction.

```elixir
# BAD — broadcast can fire before commit
Repo.transaction(fn ->
  {:ok, updated} = intent |> PaymentIntent.funded_changeset(attrs) |> Repo.update()
  {:ok, order} = mark_order_paid(intent.order_id)
  broadcast_order(order)
  updated
end)

# GOOD — broadcast after commit
case Repo.transaction(fn ->
       {:ok, updated} = intent |> PaymentIntent.funded_changeset(attrs) |> Repo.update()
       {:ok, order} = mark_order_paid(intent.order_id)
       {updated, order}
     end) do
  {:ok, {updated, order}} ->
    broadcast_order(order)
    {:ok, updated}

  {:error, _} = err ->
    err
end
```

**Reusable rule**: when broadcasting database state changes via PubSub, the broadcast always comes **after** the transaction returns, never from inside the `Repo.transaction` closure. Subscribers on different connections cannot see uncommitted writes, and there's no universal primitive to defer a broadcast until after commit (Ecto's `after_action` operates inside the same transaction, not after).

**Belt + suspenders fallback** that also landed: `checkout_live/index.ex` now schedules `:poll_intent_status` every 1.5s after `sol_payment_submitted`. Each tick re-runs the watcher and also reads the order directly — if we observe `status == "paid"` locally (even without receiving the broadcast), we transition to confirmation. Closes the window for genuinely-dropped broadcasts (network flake, LV remount race) too.

**Files**: `lib/blockster_v2/payment_intents.ex:113-131`, `lib/blockster_v2_web/live/checkout_live/index.ex:handle_info(:poll_intent_status, ...)`.

---

## Idempotent post-paid processing via the `fulfillment_notified_at` stamp (2026-04-24)

**Symptom**: user completed a SOL payment, landed on the confirmation page, but their cart wasn't cleared. Went back to shop, added a new product, checkout showed the old product + the new one. Emails were also missing.

**Root cause**: `Orders.process_paid_order/1` does a lot of side effects — `Cart.clear_cart`, `notify_order_status_change` (in-app notification), `Fulfillment.notify` (emails + Telegram + customer confirmation), `create_affiliate_payouts`, `UserEvents.track("purchase_complete")`. It was only called from one path: `handle_info({:order_updated, _})` when the LV saw `status == "paid"`. If that handler skipped the paid branch (the commit race above) or was never received (LV wasn't subscribed yet / process dead), **none of the side effects ran**. Order was marked paid in the DB but was a "paid-in-name-only" row.

**Fix (two-part)**:

1. **Idempotency guard on `process_paid_order/1`** — gate every side effect behind an `if order.fulfillment_notified_at` check. The stamp is set at the end of `Fulfillment.notify/1` (the last thing to run). If set, early-return `:already_processed`.

   ```elixir
   def process_paid_order(%Order{} = order) do
     order = get_order(order.id)

     if order.fulfillment_notified_at do
       :already_processed
     else
       Cart.clear_cart(order.user_id)
       Cart.broadcast_cart_update(order.user_id)
       notify_order_status_change(order)
       Task.start(fn -> Fulfillment.notify(order) end)
       if order.referrer_id, do: create_affiliate_payouts(order)
       UserEvents.track(order.user_id, "purchase_complete", %{...})
       :ok
     end
   end
   ```

2. **Mount-time recovery** in `checkout_live/index.ex` — when landing on a paid order with no stamp, fire `process_paid_order/1` inline. Safe because of the idempotency guard above; catches any historic casualty the first time the user reloads the checkout URL.

   ```elixir
   if order.status == "paid" and is_nil(order.fulfillment_notified_at) do
     Orders.process_paid_order(order)
   end
   ```

**Reusable pattern**: for any subsystem that fires multiple side effects on a one-time event (checkout, signup, claim), pick one "last thing to run" as the stamp and gate the whole block on it. Good stamps are timestamp fields that (a) are set inside the block (so they reflect actual completion), (b) are nil before first run, and (c) already exist in the schema for another reason (here: fulfillment tracking). This lets you call the block from multiple places — PubSub handlers, mount-time recovery, manual admin triggers — without worrying about double-firing.

**Files**: `lib/blockster_v2/orders.ex:185-218`, `lib/blockster_v2_web/live/checkout_live/index.ex:83-87`.

---

## Web3Auth mobile popup fails silently — switch to `uxMode: "redirect"` + sessionStorage hint (2026-04-24)

**Symptom**: user taps X/Google/Apple tile on mobile, gets "Sign-in window closed before completing" error. Desktop works fine. Retrying doesn't help.

**Root cause** (three compounding problems):

1. **Mobile browsers throttle background tabs**: iOS Safari suspends background tabs aggressively, which closes any OAuth popup the moment the user switches to it. The popup "closes before completing" from Web3Auth's perspective.
2. **Popups are blocked after `await`**: our `_startLogin` handler did `await this._ensureInit()` before calling `web3auth.connectTo(...)`. Mobile Chrome treats `window.open` calls after an `await` as programmatic (no user gesture), and blocks them. Desktop is more permissive.
3. **In-app webviews (Telegram, Twitter in-app)**: popups are just unsupported entirely.

**Fix**: switch `uxMode` to `"redirect"` on mobile. Redirect does a full-page navigation to `auth.web3auth.io` instead of opening a popup — user signs in on provider → Web3Auth redirects back → our SDK auto-connects on `init()` when it finds the OAuth callback session.

```js
const isMobile = /mobi|android|iphone|ipad|ipod/i.test(navigator.userAgent.toLowerCase())
  || navigator.userAgentData?.mobile === true

this._web3auth = new Web3AuthCtor({
  clientId, web3AuthNetwork, storageType: "local",
  uiConfig: { uxMode: isMobile ? "redirect" : "popup" },
  chains: [...]
})
```

**Completing the login on return**: `mounted()` isn't called with any LV-side memory across the redirect — the page reloaded. To know which provider the user had tapped (for the `web3auth_authenticated` payload), stash it pre-redirect:

```js
// Before connectTo
if (isMobile) sessionStorage.setItem(REDIRECT_PROVIDER_KEY, provider)

// In mounted(), before the existing hadSession branch
const pendingRedirectProvider = (() => {
  try {
    const v = sessionStorage.getItem(REDIRECT_PROVIDER_KEY)
    if (v) sessionStorage.removeItem(REDIRECT_PROVIDER_KEY)
    return v
  } catch (_) { return null }
})()

if (pendingRedirectProvider && this._clientId) {
  this._completeRedirectReturn(pendingRedirectProvider).catch(...)
}
```

`_completeRedirectReturn/1` runs `_ensureInit()` → `_waitForConnectorSettle()`. Under `uxMode: "redirect"`, the SDK's connector auto-`connect()`s when it finds an OAuth `sessionId` in storage, so settle resolves as `"connected"`. We then fire `_completeLogin(provider)` which pushes `web3auth_authenticated` (identical to the popup path's end state).

**Dashboard dependency (easy to miss)**: Web3Auth dashboard → project → **Whitelisted URLs** must include the exact origin the browser lands on after OAuth. For dev through Cloudflare quick-tunnel, that's the current `trycloudflare.com` hostname — and it rotates every `cloudflared` restart. Named tunnel or deployed test domain recommended for stable dev.

**Files**: `assets/js/hooks/web3auth_hook.js:_ensureInit`, `:_completeRedirectReturn`, `:mounted`.

---

## `auth_method` funneling obscures downstream display — keep provider identity distinct (2026-04-24)

**Symptom**: user signs in with Google, but the user dropdown says "Email Login" instead of "Google".

**Root cause**: `Accounts.auth_method_for_provider/1` had deliberately mapped Google and Apple sign-ins to `"web3auth_email"` (even though the schema `@valid_auth_methods` was later extended to accept `"web3auth_google"` / `"web3auth_apple"`). Reasoning per the old comment: the `put_email_verified/3` helper only flipped `email_verified=true` for `web3auth_email`, so funneling Google/Apple through it reused that logic.

Side effect nobody tested: `ds_auth_source_label/1` maps each auth_method to a display string. `"web3auth_email"` → "Email Login". So Google users legitimately showed as "Email Login" in the dropdown because that's what was in the DB.

**Fix**: each provider gets its own auth_method value, plus a shared predicate for "is verified-email-bearing":

```elixir
defp auth_method_for_provider("google"), do: "web3auth_google"
defp auth_method_for_provider("apple"), do: "web3auth_apple"
defp auth_method_for_provider("email"), do: "web3auth_email"
# ... etc

# Shared predicate — used by put_email_verified + heal-patch + any other consumer
defp verified_email_auth_method?("web3auth_email"), do: true
defp verified_email_auth_method?("web3auth_google"), do: true
defp verified_email_auth_method?("web3auth_apple"), do: true
defp verified_email_auth_method?(_), do: false
```

**Reusable rule**: never funnel distinct identities through a single auth_method value for the sake of reusing a side-effect. The auth_method field has multiple downstream readers (display label, analytics, verifiers, multiplier math). Factor the shared behavior into a predicate; let each identity carry its true value.

**Auto-heal**: `Accounts.maybe_update_web3auth_fields/2` re-derives `auth_method` on every login, so pre-fix rows (where Google users were stored as `web3auth_email`) heal automatically on their next Google sign-in. No backfill migration needed.

**Files**: `lib/blockster_v2/accounts.ex:auth_method_for_provider/1`, `verified_email_auth_method?/1`, `lib/blockster_v2/accounts/user.ex:put_email_verified/3`.

---

## Settler `getSignaturesForAddress` lags balance — record buyer-side tx sig as authoritative (2026-04-24)

**Symptom**: shop order confirmation page shows no "SOL payment tx" link even though the payment landed and the order is marked paid.

**Root cause**: `PaymentIntentWatcher.check_one/1` (server-side, runs on every watcher tick) calls the settler's `GET /intents/:pubkey` endpoint to ask "is this intent funded?". Settler implementation (`contracts/blockster-settler/src/services/payment-intent-service.ts:getPaymentIntentStatus`) does:

```ts
const balance = await connection.getBalance(pubkey, "confirmed"); // fast
const funded = balance >= expectedLamports;
if (funded) {
  const sigs = await connection.getSignaturesForAddress(pubkey, { limit: 1 }); // best-effort
  if (sigs[0]) fundedTxSig = sigs[0].signature;
}
return { balance_lamports, funded, funded_tx_sig };
```

RPC nodes index `getBalance` fast (it hits account state directly) but `getSignaturesForAddress` uses a tx-history indexer that lags behind by a second or two. If the watcher tick fires in that window, `funded=true` + `funded_tx_sig=null`. `PaymentIntents.mark_funded/3` stored the null. Order was paid with no tx reference.

**Fix**: use the buyer-side sig as authoritative. The JS hook (`signAndConfirm` in `signer.js`) already polls `getSignatureStatuses` and confirms the tx **before** pushing `sol_payment_submitted` to the server. So we already have the canonical sig on the client. Record it immediately on the intent row, and make `mark_funded/3` coalesce instead of clobber:

```elixir
# New fn — persist sig right after the buyer submits, no status change
def record_submitted_tx_sig(intent_id, tx_sig) when is_binary(tx_sig) and tx_sig != "" do
  case Repo.get(PaymentIntent, intent_id) do
    nil -> {:error, :not_found}
    intent ->
      intent
      |> Ecto.Changeset.change(%{funded_tx_sig: tx_sig})
      |> Repo.update()
  end
end

# In mark_funded — coalesce rather than overwrite
resolved_sig = tx_sig || intent.funded_tx_sig   # <-- the critical line

attrs = %{
  status: "funded",
  funded_tx_sig: resolved_sig,
  ...
}
```

**LV handler** fires the record call right when `sol_payment_submitted` arrives:

```elixir
def handle_event("sol_payment_submitted", %{"signature" => sig}, socket) do
  if intent = socket.assigns[:payment_intent] do
    Task.start(fn -> PaymentIntents.record_submitted_tx_sig(intent.id, sig) end)
  end
  # ... also trigger watcher inline + schedule fallback poll
end
```

**Reusable pattern**: when a two-party system (client + server) both have access to the same canonical data, and one side's view lags the other's, record the eager side's view first and have the lagging side coalesce its update. Don't let the lagging side overwrite with null.

**Files**: `lib/blockster_v2/payment_intents.ex:record_submitted_tx_sig/2`, `mark_funded/3`, `lib/blockster_v2_web/live/checkout_live/index.ex:handle_event("sol_payment_submitted", ...)`.

---

## Hand-rolling SPL `BurnChecked` avoids `@solana/spl-token` bundle bloat (2026-04-24)

**Context**: replaced the dead EVM-era `BuxPaymentHook` with a working Solana burn for the shop checkout BUX discount step. Needed an SPL `BurnChecked` instruction. The obvious path was adding `@solana/spl-token` as a dep and calling `createBurnCheckedInstruction()`. But `@solana/spl-token` + its transitive deps add ~2MB to the bundle, which is noticeable on the already-heavy social login + wallet flows.

**Observation**: `BurnChecked` is a trivial instruction — 10 bytes of data, 3 accounts. And we already have `@solana/web3.js` in the bundle (for `Transaction`, `PublicKey`, etc). Hand-rolling the instruction costs ~30 lines, no new deps:

```js
import { PublicKey, TransactionInstruction } from "@solana/web3.js"

const TOKEN_PROGRAM_ID = new PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
const ASSOCIATED_TOKEN_PROGRAM_ID = new PublicKey("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")

// ATA derivation — PDA of [owner, token_program, mint] under ATA program.
// Matches what spl-token's getAssociatedTokenAddress computes.
function deriveAta(owner, mint) {
  const [ata] = PublicKey.findProgramAddressSync(
    [owner.toBuffer(), TOKEN_PROGRAM_ID.toBuffer(), mint.toBuffer()],
    ASSOCIATED_TOKEN_PROGRAM_ID,
  )
  return ata
}

// BurnChecked instruction data layout (10 bytes):
//   [0]   discriminator = 15 (BurnChecked)
//   [1-8] amount as u64 little-endian
//   [9]   decimals as u8
// Accounts (per SPL Token spec):
//   [0] writable source_ata
//   [1] writable mint
//   [2] signer  owner
function buildBurnCheckedIx({ ata, mint, owner, amountRaw, decimals }) {
  const data = new Uint8Array(10)
  data[0] = 15
  const view = new DataView(data.buffer)
  // BigInt → two u32 writes (DataView.setBigUint64 isn't universal; explicit lo/hi is safest).
  const lo = Number(amountRaw & 0xffffffffn)
  const hi = Number((amountRaw >> 32n) & 0xffffffffn)
  view.setUint32(1, lo, true)
  view.setUint32(5, hi, true)
  data[9] = decimals

  return new TransactionInstruction({
    programId: TOKEN_PROGRAM_ID,
    keys: [
      { pubkey: ata, isSigner: false, isWritable: true },
      { pubkey: mint, isSigner: false, isWritable: true },
      { pubkey: owner, isSigner: true, isWritable: false },
    ],
    data: data,
  })
}
```

**Rule of thumb**: before adding a Solana dep for a single instruction, check if the instruction layout is simple (≤20 bytes of data, ≤5 accounts) and whether the primitives you need (`PublicKey`, `TransactionInstruction`, PDA derivation) are already in your bundle. If yes, hand-rolling is smaller and has zero risk of dep-version drift. If the dep offers meaningful primitives beyond one instruction (e.g. token metadata helpers, account parsers), the dep may still be worth it.

**Files**: `assets/js/hooks/solana_bux_burn.js`.

---

## Engagement Tracker Silent Failure — `#post-content` Selector Miss After Redesign (Apr 2026)

**Symptom**: After the article-page redesign shipped, users reported that reaching the bottom of an article no longer paid BUX (for logged-in users) and no longer showed the "you earned X BUX — connect to claim" modal (for anonymous users). Both device classes affected. No server errors. No JS exceptions. The LiveView handler for `article-read` and `show-anonymous-claim` was never called — server logs were silent.

**Root cause**: `assets/js/engagement_tracker.js` line 65 looked for the article container with `document.getElementById("post-content")` — singular. The legacy template used that id; the redesigned article template chunks content into `#post-content-1`, `#post-content-2`, `#post-content-3`, `#post-content-4` for ad insertions at the 1/3, 1/2, and 2/3 marks. Result:

- `this.articleEl` → `null`
- `trackScroll()` early-returned every tick: `if (!this.articleEl || this.isPaused) return;`
- `scrollDepth` stayed at 0, `isEndReached` never flipped
- Neither `sendReadEvent` nor the anonymous `pushEvent("show-anonymous-claim", ...)` ever fired
- `localStorage.pending_claim_read_<postId>` was never written, so even post-signup reclaim was dead

Silent failure mode — no console error, no telemetry. The anonymous-claim retrieval chain (`app.js:667` connect_params → `member_live/show.ex:946 process_pending_claims/2`) was intact the whole time. It just never got any data.

**Fix** (`assets/js/engagement_tracker.js`):

```js
// Match either legacy singular id or any suffixed chunk
this.articleEl =
  document.getElementById("post-content") ||
  document.querySelector("[id^='post-content-']");
```

Scroll depth calc rewritten to use `#article-end-marker` as the true article bottom — otherwise the first chunk's height would misreport 100% after the user scrolls past one section:

```js
const articleTop = this.articleEl.getBoundingClientRect().top + window.scrollY;
const articleBottom = this.endMarkerEl
  ? this.endMarkerEl.getBoundingClientRect().top + window.scrollY
  : articleTop + this.articleEl.getBoundingClientRect().height;
const articleHeight = Math.max(1, articleBottom - articleTop);
```

Added a belt-and-suspenders completion trigger: if `scrollDepth >= 95 && timeSpent >= minReadTime` and the 200px end-marker check hasn't fired yet, dispatch `sendReadEvent` anyway. Catches mobile where dynamic chrome (URL bar collapse) shifts the end-marker's bottom-of-viewport check.

**Takeaways**:
1. **Layout-level ID changes silently break JS hooks that use fixed selectors.** When refactoring a template, grep the entire codebase for `getElementById("<the-id>")` AND `[id^="<prefix>"]` before committing — not just the current file.
2. **Early returns in scroll handlers are invisible failures.** No throw, no console warning when `articleEl` is null — `trackScroll` just silently noops. Next time, at least `console.warn("EngagementTracker: articleEl not found")` so a DevTools check surfaces the problem.
3. **Claim-retrieval chains fail gracefully when they're never invoked.** Anonymous claim worked perfectly in unit tests, but production had zero items in `pending_claim_read_*` localStorage for the affected weeks. A passive monitoring check ("are we still seeing article-read events at expected rate?") would've caught this in under a day.
4. **Redesign-stage work deserves a dedicated "core flow still works" checklist**, not just visual QA. Wallet connect → read article → see BUX → refresh → see persisted BUX. Click through once manually before calling a redesign done.

---

## Tailwind Typography img Margins Hijacked a Widget Header — Check Computed Styles First (Apr 2026)

**Problem**: The `rt_full_card` widget (and any RT widget rendered inline in an article) had a massively tall header. The ROGUE logo appeared ~45px tall even though the `<img>` had `class="h-[22px]"`, and the "TRADER" subtitle sat far below the logo with a big gap. User correctly diagnosed it in 3 seconds via DevTools: **the logo `<img>` had 32px top and bottom margins**. I spent over an hour mutating HEEx structure, swapping `<span>` for `<div>`, switching absolute positioning to flex column, adding `outline` debug colors, forcing fixed header heights, rewriting TRADER as bright yellow-on-red — none of which was the problem.

**Root cause**: The widget is rendered inside an article that uses Tailwind Typography's `.prose` class. Typography adds `:where(img):not([class~="not-prose"]) { margin-top: 2em; margin-bottom: 2em; }` — at a 16px base font, that's exactly 32px top/bottom margin on every `<img>` in the subtree, including the widget's logo. The widget's local CSS had no chance of overriding a typography-level rule scoped to the article container.

**The fix**: Add `not-prose` class to every widget root. Applied to all 19 widgets (`rt_full_card`, `rt_skyscraper`, `rt_chart_landscape`, `rt_chart_portrait`, `rt_sidebar_tile`, `rt_square_compact`, `rt_leaderboard_inline`, `rt_ticker`, `fs_skyscraper`, `fs_hero_landscape`, `fs_hero_portrait`, `fs_sidebar_tile`, `fs_square_compact`, `fs_ticker`, `cf_sidebar_tile`, `cf_sidebar_demo`, `cf_portrait`, `cf_portrait_demo`, `cf_inline_landscape`, `cf_inline_landscape_demo`) on the outermost `class="..."`. This opts the entire widget subtree out of typography styling.

**Rules for next time** (hard-learned):
1. **When a CSS issue is reported, open DevTools and inspect computed styles on the affected element FIRST.** Not "look at the HEEx," not "try a different layout approach" — look at the actual browser-computed `margin`, `padding`, `height`, `width`. If the computed margin is 32px and your CSS says 0, something in an ancestor is injecting it. That's the clue. Every other path wastes time.
2. **When a widget lives inside an article (`.prose` container), escape typography styling with `not-prose` on the widget root.** Tailwind Typography applies defaults (margins on `img`, `p`, `blockquote`, list styles, etc.) that will silently hijack any embedded component.
3. **Symptoms of this exact bug to recognize immediately**: images much larger than their constrained `h-[]` / `height:` style; weird vertical gaps between stacked elements inside articles; anything that "looks fine in the mock file but wrong on the article page" when the only difference is the `.prose` ancestor.
4. **Don't blame Phoenix live-reload, Tailwind JIT, or browser cache before checking the computed styles.** I went down all three paths in this session. The bug wasn't in the pipeline — it was in the CSS cascade.

**Where the typography rule lives**: auto-generated from `@tailwindcss/typography` plugin; shows up in `priv/static/assets/css/app.css` as `:where(img):not(:where([class~="not-prose"],[class~="not-prose"] *)) { margin-top: 2em; margin-bottom: 2em; }`. Multiple occurrences (different prose size variants: prose-sm, prose-base, prose-lg) — all share the same `not-prose` opt-out.

---

## Coin Flip Widgets: Copy Mocks Verbatim — Never Rebuild From Scratch (Apr 2026)

**Problem**: The coin flip widget plan specified 25 HTML mock files as the "exact visual spec." Instead of copying the mock HTML/CSS directly into the HEEx components, I rebuilt everything from scratch — invented new class hierarchies (`.cf-land__`, `.cf-port__`), wrote CSS from memory with wrong values (padding, font-size, spacing all different from mocks), generated panel HTML dynamically with loops instead of copying the static markup, and used generic animations instead of the per-panel scoped keyframes (`.p0`–`.p8`) from the mocks. The result looked nothing like the mocks.

**What went wrong, in order**:
1. **Invented new class names instead of using the mock's** — the landscape mock uses `.vw`, `.v-head`, `.bd`, `.bm`, `.d-face`, `.v-chip`. I wrote `.cf-land__head`, `.cf-land__brand-wordmark`, `.cf-chip--lg`. Completely different CSS that had to be rewritten.
2. **Generated HTML dynamically with EEx loops** — the mock has 9 hardcoded panels with exact HTML for each difficulty. I tried to generate them from `CfHelpers.demo_configs()` with loops. This produced different HTML structure, different class usage, and broke the per-panel CSS animation scoping.
3. **Wrote CSS values from memory** — sidebar mock has `padding: 6px 12px 4px`, `margin-top: 2px`, `font-size: 8px`, `height: 24px`. I wrote `padding: 11px 12px 8px`, `margin-top: 12px`, `font-size: 8.5px`, `height: 26px`. Every value was wrong by just enough to break the 200×340 layout.
4. **Sidebar demo: added 9-panel cycling that doesn't exist in the mock** — the mock is a single Win All 3 flips animation (18s CSS loop, no JS). I invented a 9-panel cycling system with CfDemoCycle hook. Completely wrong.
5. **Missing animation keyframes** — the sidebar mock has ~20 `@keyframes` rules for the 18s animation. I didn't add any of them. The coin didn't spin, results didn't reveal, winner didn't appear.
6. **CSS selector scoping wrong** — landscape/portrait use `.bw-widget.cfd` (both classes on same element, no space). I wrote `.bw-widget .cfd` (descendant selector, with space). All styles silently failed to apply.

**The fix**: Literally copy-paste the mock's HTML into HEEx templates and the mock's CSS into `widgets.css`. No interpretation, no generation, no loops. The mocks ARE the code.

**Additional issues discovered after mock copy** (CSS context differences between standalone mock and LiveView/Tailwind context):
- `display:inline-flex` gets blockified to `display:flex` inside flex column parents → children stretched to fill height. Fix: explicit `height` + `flex:none` on `.v-winner-amount` and `.v-card-val`.
- `position:absolute` children trapped by intermediate `position:relative` parents (`.v-winner` inside `.v-coin-area`). Fix: `position:static` on landscape `.v-coin-area`.
- `phx-update="ignore"` required on demo widget roots — without it, LiveView re-renders reset the JS cycling timer, causing difficulty levels to jump randomly.

**Rules for next time**:
1. **When a working mock exists, the component's job is to serve that mock's HTML — nothing else.** Don't abstract, don't loop, don't generate. Copy it.
2. **The mock's CSS class names are the ones you use.** Don't rename `.vw` to `.cf-land`, don't rename `.bd` to `.bw-display`. Use what the mock uses.
3. **The mock's CSS values are the ones you use.** Don't write `padding: 11px` when the mock says `padding: 6px`. Open the mock, copy the number.
4. **If the mock has per-component scoped keyframes, they go in the CSS file verbatim.** Don't try to generate them. Copy them.
5. **Test in the browser by comparing side-by-side with the mock file.** Open `file:///path/to/mock.html` in one tab and `localhost:4000/article` in another. They should look identical.
6. **After embedding mock CSS in a LiveView context, check for flex blockification issues.** The mock runs in a clean HTML context. LiveView templates render inside flex/grid parents that can stretch inline-flex children.

---

## Notification.@valid_types Silent Validation Failure Swallowed Reward Records (Apr 2026)

User reported: *"I earned 500 BUX for verifying my phone but nothing displays in my Activity tab"*. The BUX really did show up in their wallet, but no notification record existed for it. Took ~20 minutes to track down because the failure was completely silent.

### What the flow was supposed to do

1. `PhoneVerification.verify_code/2` succeeds
2. `UserEvents.track(user_id, "phone_verified", ...)` fires
3. `Notifications.EventProcessor` (a `GlobalSingleton` GenServer subscribed to the `"user_events"` PubSub topic) receives the event
4. `evaluate_custom_rules/3` looks up the `phone_verified` rule from `SystemConfig`
5. `execute_rule_action_inner/6` creates a `Notification` record AND calls `credit_bux/2` to mint the BUX
6. The Activity tab on `/member/:slug` reads notifications via `Notifications.list_notification_activities/1` and renders them as activity rows

### Why it failed

The custom rule defined in `system_config.ex:73-81` sets `notification_type: "reward"`:

```elixir
%{
  "event_type" => "phone_verified",
  "action" => "notification",
  "title" => "Phone Verified!",
  "body" => "You earned 500 BUX for verifying your phone!",
  "channel" => "in_app",
  "notification_type" => "reward",
  "bux_bonus" => 500,
  "source" => "permanent"
}
```

But `Notification.changeset/2` does:

```elixir
@valid_types ~w(new_article hub_post hub_event ... bux_earned referral_reward
                ... promo_reward)
|> validate_inclusion(:type, @valid_types)
```

`"reward"` was **NOT** in `@valid_types`. There were similar names (`bux_earned`, `referral_reward`, `promo_reward`, `daily_bonus`) but never just plain `"reward"`. The changeset failed validation. And `execute_rule_action_inner/6` looked like this:

```elixir
if channel in ["in_app", "both", "all"] do
  Notifications.create_notification(user_id, %{
    type: rule["notification_type"] || "special_offer",
    ...
  })
end

# BUX crediting (formula-resolved)
if is_number(bux_bonus) and bux_bonus > 0 do
  credit_bux(user_id, bux_bonus)
end
```

The result of `create_notification` was never pattern-matched. The function returned `{:error, %Ecto.Changeset{...}}` and Elixir threw it on the floor. Code kept going. `credit_bux` ran. BUX got minted. No notification record. No log message.

### Triple impact

- `phone_verified` rewards never showed up in the activity tab
- Same bug affected `x_connected` and `wallet_connected` rules — both use `notification_type: "reward"`
- Future rules that pick a non-whitelisted type would silently fail the same way

### Fix

Three layers:

1. **Add `"reward"` to `@valid_types`** in `notification.ex`. This is the actual root cause.
2. **Stop silently discarding `Notifications.create_notification` failures** — wrap the call in a `case` and log changeset errors via `Logger.error(...)`. Pattern:
   ```elixir
   case Notifications.create_notification(user_id, attrs) do
     {:ok, _notification} -> :ok
     {:error, changeset} ->
       Logger.error(
         "[EventProcessor] Failed to create notification for user #{user_id}, " <>
           "rule event=#{event_type} type=#{inspect(rule["notification_type"])}: " <>
           inspect(changeset.errors)
       )
   end
   ```
3. **Backfill missing notification rows** for users who already hit the bug. The dedup_key prevents the rule from firing again on retry, so the only way to recover is to insert the row manually. Pattern:
   ```elixir
   Notifications.create_notification(user_id, %{
     type: "reward",
     category: "engagement",
     title: "Phone Verified!",
     body: "You earned 500 BUX for verifying your phone!",
     metadata: %{"dedup_key" => "custom_rule:phone_verified", "bux_bonus" => 500}
   })
   ```

### General lessons

- **Never discard `Repo.insert` / `Repo.update` results.** If the call has side effects you care about (a notification row that backs an activity feed, a reward log entry, etc.), pattern-match the return and at least log on failure. `case Repo.insert(...) do ... end` is one extra line and saves hours of debugging later.
- **Whitelists and the things that feed them have to live in the same place** or there has to be a cross-check. The `@valid_types` whitelist on `Notification` and the `notification_type` field on every custom rule in `SystemConfig.@defaults` are conceptually coupled but were defined in different files with no validation between them. Adding a single `notification_type` to a custom rule could (and did) silently break the whole reward path. Possible mitigations:
  1. Validate every default rule against `@valid_types` at app startup
  2. Have the custom rules engine fall back to a guaranteed-valid type when the configured one is invalid
  3. Just have one source of truth (the rule's `notification_type` IS the schema's type, not a separate vocabulary)
- **For long-running event-driven systems, "the BUX is real but the activity is missing" is a real failure mode and you should test for it.** Easy regression test: set up a custom rule, fire the event, assert that BOTH the BUX balance went up AND a `Notification` row exists with the expected `dedup_key` in metadata.

---

## LiveView Modal Backdrop: Use phx-click-away, NOT phx-click + stop_propagation (Apr 2026)

User reported: *"I entered phone number and it correctly sent code to my phone but the modal disappeared so I have nowhere to enter it"*.

### The bug

`PhoneVerificationModalComponent` (and `EmailVerificationModalComponent`) was structured like:

```html
<div class="fixed inset-0 ..." phx-click="close_modal" phx-target={@myself}>
  <div class="bg-white ..." phx-click="stop_propagation" phx-target={@myself}>
    <form phx-submit="submit_phone" phx-target={@myself}>
      <button type="submit">Send Code</button>
      ...
```

The intent: clicks on the backdrop close the modal; clicks on the inner content are absorbed by a `stop_propagation` no-op handler so they don't bubble to the backdrop.

The problem: **`phx-click="stop_propagation"` is just a normal event handler that returns `{:noreply, socket}`. It does NOT call DOM `e.stopPropagation()`.** Phoenix LiveView wires up the click listener but doesn't actually stop the underlying browser event from bubbling — at least not reliably for clicks that originate from a `<button type="submit">` inside a `<form phx-submit="...">`.

What happened on submit:
1. Browser fires the button click
2. Form submit fires → `phx-submit` event sent to server → SMS sent
3. The same click bubbles up the DOM → reaches the backdrop's `phx-click="close_modal"` → ALSO sent to server
4. Server processes both events: `submit_phone` succeeds (so the modal *should* transition to the code-entry step) AND `close_modal` fires (which sets `show_phone_modal = false` on the parent LiveView)
5. The parent re-renders without the modal → it disappears

So the SMS was real (the user did get a code), but the UI was gone before they could enter it.

### The fix

Replace the manual backdrop click handler with `phx-click-away`, which is the canonical LiveView pattern for "fire when clicking outside this element":

```html
<div class="fixed inset-0 ...">                                    <!-- backdrop, no handler -->
  <div class="bg-white ..." phx-click-away="close_modal" phx-target={@myself}>
    <form phx-submit="submit_phone" phx-target={@myself}>
      <button type="submit">Send Code</button>
```

`phx-click-away` only fires for clicks that land OUTSIDE the element. Clicks INSIDE — including `<button type="submit">` clicks that bubble through the form — never trigger it. No `stopPropagation` gymnastics needed. The dead `stop_propagation` no-op handler can be deleted.

### Lessons

- **`phx-click="stop_propagation"` (or any other no-op event handler) does NOT actually stop DOM event propagation.** It's just an Elixir function that returns `{:noreply, socket}`. The browser keeps bubbling the underlying click event to ancestors with their own `phx-click` handlers. If you need both an inner action AND an outer "click outside to close" behavior, use `phx-click-away` on the inner, not `phx-click` on the outer.
- **Modals that have a form inside are extra fragile** because submit-button clicks bubble independently of the form submit. If you have any `phx-click` on a parent of the form, audit it.
- **Same bug, multiple components**: when you find a backdrop bug in one modal, grep for `phx-click="close_modal"` (or whatever the event name is) across the codebase. We had identical bugs in `phone_verification_modal_component` and `email_verification_modal_component`.

---

## Sticky Banners and Animated-Height Headers: Make the Banner a Child of the Header (Apr 2026)

User wanted a thin lime *"Why Earn BUX?"* announcement bar stuck flush against the bottom of the global header. The global header has a JS-driven collapse-on-scroll animation (logo row hides, header shrinks from ~170px to ~96px). Burned a few iterations before landing on the right approach.

### Failed approaches

1. **Sticky banner inside `profile-main` with `mt-16 lg:mt-24` and `sticky top-16 lg:top-24`**. Looked snug visually... until I noticed the layout's `site_header` already provides an `h-14 lg:h-24` spacer to clear the fixed header. So I was double-clearing — adding ~120-192px of empty space before page content instead of ~56-96px.

2. **Removed the `mt`, kept sticky `top-14 lg:top-24` to match the spacer**. Banner was now flush at the bottom of the spacer (y=56 mobile, y=96 desktop). **But** the actual desktop header is ~170px tall in its initial (full logo) state and only collapses to ~96px on scroll. So at scroll=0 the banner was hidden behind the bottom 74px of the full header. As the user scrolled and the header animated to its collapsed state, the banner appeared with a transient gap. User complained: *"now its not visible until you scroll and top logo area disappears and then you can see the banner with a gap above it"*.

The fundamental problem: **sticky positioning uses a static `top:` value. A header that animates its height between two states doesn't have a single number you can target.** No matter what `top:` you pick, you'll be wrong in one of the two states.

### The right approach: make the banner a child of the same fixed container as the header

Add the banner inside the existing `<div id="site-header" class="fixed top-0 ...">` wrapper as the LAST child. That way:

- The banner is part of the same fixed element as the header
- When the header collapses, the banner moves up with it (because they share a position context)
- It's always flush against the bottom edge of the header in BOTH states
- No `position: sticky`, no `top:` math, no JS to keep them in sync

Implementation:

1. Add `attr :show_why_earn_bux, :boolean, default: false` to the `site_header/1` function component in `layouts.ex`.
2. Inside the function, render the banner as the last child of the fixed container, conditional on `@show_why_earn_bux`.
3. Bump the spacer (the second top-level element returned by `site_header/1` that pushes page content down) when the banner is shown — `h-14 lg:h-24` → `h-[88px] lg:h-[128px]` (adds ~32px of spacer height to account for the banner).
4. In `app.html.heex`, pass `show_why_earn_bux={assigns[:show_why_earn_bux] || false}` from socket assigns through to `site_header`.
5. In each LiveView that wants the banner, set `assign(:show_why_earn_bux, true)` in `mount/3`.

Pages that don't set the assign default to `false` and get no banner — no spacer change either, so existing layouts are unaffected.

### Lessons

- **Anything that needs to stay flush against the bottom of an animated-height header has to be a child of the same fixed container as the header.** Trying to track it from outside with `position: sticky` + a static `top:` offset never works because the offset is constant while the header height changes.
- **When debugging "banner has a gap" complaints on a fixed header, check whether the layout has an existing spacer to clear the header.** Adding your own `pt-*` or `mt-*` on top of an existing spacer is the most common cause of doubled spacing.
- **The page's `pt-*` clearance is for the COLLAPSED header height, not the full one.** Original page content is *intentionally* hidden behind the bottom portion of the full header at scroll=0; the collapse animation is what reveals it. Don't try to "fix" this by adding more padding — you'll break the collapse pattern.

---

## Legacy Account Reclaim — LegacyMerge Implementation Gotchas (Apr 2026)

Implementing `BlocksterV2.Migration.LegacyMerge` (the all-or-nothing email-triggered merge from a legacy EVM-auth user into a new Solana-auth user) surfaced several non-obvious issues. Full design at `docs/legacy_account_reclaim_plan.md`, build log at `docs/solana_build_history.md`.

### Originals must be captured BEFORE deactivation

The merge transaction runs in this order: (1) deactivate legacy → (2) mint BUX → (3) transfer username → (4) X → (5) Telegram → (6) phone → ... The deactivation step is FIRST so it can free unique slots (`email`, `username`, `slug`, `telegram_user_id`, `locked_x_user_id`) before subsequent steps try to take them on the new user. But that means by the time step 3 runs, the in-memory `legacy_user` struct returned by `Repo.update!` has placeholders/nils — we need the ORIGINAL values to copy onto the new user.

Solution: capture an `originals` map at the start of `do_merge/2` BEFORE calling `deactivate_legacy_user`, and pass it through to every transfer step:

```elixir
originals = %{
  email: legacy_user.email,
  username: legacy_user.username,
  slug: legacy_user.slug,
  telegram_user_id: legacy_user.telegram_user_id,
  telegram_username: legacy_user.telegram_username,
  telegram_connected_at: legacy_user.telegram_connected_at,
  telegram_group_joined_at: legacy_user.telegram_group_joined_at,
  locked_x_user_id: legacy_user.locked_x_user_id,
  referrer_id: legacy_user.referrer_id,
  referred_at: legacy_user.referred_at
}
```

The first attempt used a `Process.put(:legacy_merge_pre_deactivation_telegram, ...)` hack — never do that. Pass state through function arguments.

### `locked_x_user_id` has its own unique constraint — null it in deactivate

`users.locked_x_user_id` is a unique field. If you try to copy it from legacy → new in the X transfer step without first nulling it on legacy, you get `users_locked_x_user_id_index` constraint violation. The fix: include `locked_x_user_id: nil` in the `deactivate_legacy_user` change set, alongside the email/username/slug/telegram nulling.

### `Ecto.Changeset.change/2` works on fields not in the cast list

`User.changeset/2` does not include `locked_x_user_id` in the cast list (it's set by `Social.upsert_x_connection` via a direct `Ecto.Changeset.change/2`). When writing tests that need to set `locked_x_user_id` on a freshly inserted user, going through `User.changeset(attrs)` will silently drop the value. You must use `Ecto.Changeset.change(%{locked_x_user_id: ...}) |> Repo.update()` directly.

### Configurable BUX minter for tests via `Application.compile_env`

`LegacyMerge.merge_legacy_into!/2` calls `BuxMinter.mint_bux/5` to mint legacy BUX onto the new Solana wallet, and rolls back the entire transaction if the mint fails. Testing both the success path AND the rollback path requires faking `BuxMinter`. Pattern:

```elixir
@bux_minter Application.compile_env(:blockster_v2, :bux_minter, BlocksterV2.BuxMinter)
# ... later ...
@bux_minter.mint_bux(wallet_address, amount, user_id, nil, :legacy_migration)
```

In `config/test.exs`: `config :blockster_v2, :bux_minter, BlocksterV2.BuxMinterStub`. The stub (in `test/support/bux_minter_stub.ex`) is a process-dictionary-backed module with `set_response/1` and `calls/0` so each test can simulate success or failure independently.

`Application.compile_env` (not `Application.get_env`) is required because the swap must happen at compile time — `LegacyMerge` references `@bux_minter` directly in function bodies. The first `mix test` after wiring the stub via `compile_env` requires `MIX_ENV=test mix compile --force` so the new value gets baked in.

### Swoosh test adapter delivers `{:email, _}` to the spawning process

`EmailVerification.send_verification_code` spawns a Task to deliver the email asynchronously. When that Task is started from inside a LiveView's event handler, the Swoosh test adapter sends a `{:email, %Swoosh.Email{}}` message back to the spawner — which is the LiveView. Without a matching `handle_info` clause, the LiveView crashes with `FunctionClauseError`. Fix: add a swallow clause:

```elixir
@impl true
def handle_info({:email, _swoosh_email}, socket), do: {:noreply, socket}
```

### `EmailVerification.verify_code` return shape change is a breaking API change

I changed the return from `{:ok, user}` to `{:ok, user, %{merged: bool, summary: map}}` so callers can render the merge result. Every existing call site (`OnboardingLive.Index.submit_email_code`, `EmailVerificationModalComponent.submit_code`) had to be updated to pattern-match on the 3-tuple. Plus `send_verification_code` now writes to `pending_email` not `email`, so callers reading `updated_user.email` for the success message had to switch to `updated_user.pending_email || updated_user.email`. Easy to miss.

### `find_legacy_user_for_email` MUST filter `is_active = true`

The new helper that detects whether a verified email matches a legacy user uses:

```elixir
from u in User,
  where: u.email == ^email,
  where: u.id != ^current_user_id,
  where: u.is_active == true,
  limit: 1
```

The `is_active = true` filter is critical: after a merge, the legacy user has `is_active = false` AND `email = nil` (deactivation nulls the email column). But if you forget the filter and a legacy user somehow has `is_active = false` while still holding the email (e.g., manual SQL state), `find_legacy_user_for_email` would find them, then `LegacyMerge.merge_legacy_into!` would fail with `:legacy_already_deactivated`, and `verify_code` would return `{:error, {:merge_failed, :legacy_already_deactivated}}` — confusing for the user. Filter at the source.

### Phone reclaim transfers the row at SEND time, not VERIFY time

The original plan said "transfer the phone_verifications row at verify_code time". But the existing `send_verification_code` flow inserts a new `phone_verifications` row immediately, which would fail the unique constraint if a legacy/inactive user already owns the phone number. Two options: (a) insert at verify time only, (b) transfer the legacy row at send time. I went with (b) — when `check_phone_reclaimable/2` returns `:phone_reclaimable`, `send_verification_code` UPDATEs the existing legacy row in place: `user_id = new_user_id`, `verified = false`, `attempts = 1`, new `verification_sid`. Then `verify_code` works as today, finds the row by user_id, and marks it verified.

The risk with (b) is that if the new user fails to verify, the row is now on the new user — the legacy user has lost the phone. But the legacy user is INACTIVE so it's fine. This approach also lets the user retry without inserting/deleting rows on each attempt.

### `next_unfilled_step/2` skip-completed-steps logic must run at every step transition

After a merge fires (whether at `migrate_email` or at the regular `email` step in the "I'm new" path), the user's state has changed: they suddenly have a username, phone, email, X connection, etc. The next onboarding step button should fast-forward past anything the merge already filled. This means the skip logic can't be tied to the migrate branch only — it needs to fire at every step transition for any user. Implemented as a public `next_unfilled_step(user, current_step)` helper that walks `@steps` from `current_step + 1` and returns the first step where `step_unfilled?(step, user)` is `true`.

Skip rules per the plan:
- `welcome` / `migrate_email` → never the answer (always skipped, since they're entry points)
- `redeem` → never skipped (informational, useful for returning users — even though "everyone connected" cases would technically skip everything else)
- `profile` → skip if `username` set
- `phone` → skip if `phone_verified`
- `email` → skip if `email_verified`
- `x` → skip if an `x_connections` Mnesia row exists for the user
- `complete` → never skipped

### Don't filter `is_active` in `Repo.get_by(User, locked_x_user_id: ...)` for X reclaim

The X reclaim logic in `Social.reclaim_x_account_if_needed/2` looks up the user that currently holds `locked_x_user_id`. If you filter `is_active = true` here, you'll never find the deactivated legacy user → reclaim never fires → unique constraint violation when the new user tries to take the lock. The reclaim path needs to find users in BOTH states (active = block, inactive = reclaim). Same pattern in the Telegram webhook handler.

`BlocksterV2.Accounts.get_user_by_*` functions are the public interface where `is_active` filtering belongs. Reclaim helpers go directly through `Repo.get_by` (or equivalent) so they can see deactivated rows.

### Test diff between baseline and new run is tricky with randomized output

Comparing `mix test` failures across two runs (with vs without changes) seems straightforward but is tripped up by:
- ExUnit randomizes test order, so failure numbers (`1)`, `2)`, ...) shuffle between runs.
- `git stash` doesn't stash untracked files by default — your new test files still run during a "baseline" comparison run. They'll fail (because the new lib code is stashed), inflating the baseline failure count for files you haven't touched.

The reliable check: run a focused subset (`mix test test/blockster_v2/shop test/blockster_v2/notifications`) with and without changes, compare the totals. Or use the `comm` trick after stripping the leading numbers: `awk -F') ' '{print $2}' file | sort -u`. Either way, don't trust raw failure counts.

---

## Number Formatting in Templates
Use `:erlang.float_to_binary/2` to avoid scientific notation in number inputs:
```elixir
value={:erlang.float_to_binary(@tokens_to_redeem / 1, decimals: 2)}
```

## Product Variants
- Sizes come from `option1` field on variants, colors from `option2`
- No fallback defaults - if a product has no variants, sizes/colors lists are empty

## X Share Success State
After a successful retweet, check `@share_reward` to show success UI in `post_live/show.html.heex`.

## Tailwind Typography Plugin
- Required for `prose` class to style HTML content
- Installed via npm: `@tailwindcss/typography`
- Enabled in app.css: `@plugin "@tailwindcss/typography";`

## Libcluster Configuration (Dev Only)
Added December 2024. Uses Epmd strategy for dev-only automatic cluster discovery. Configured in `config/dev.exs`. Production uses DNSCluster unchanged.

## Upgradeable Smart Contract Storage Layout - CRITICAL

When upgrading UUPS or Transparent proxy contracts:
1. **NEVER change the order of state variables**
2. **NEVER remove state variables**
3. **ONLY add new variables at the END**
4. **Inline array initialization doesn't work with proxies** - Use `reinitializer(N)` functions

**Stack Too Deep Errors**: NEVER enable `viaIR: true`. Instead use helper functions, cache struct fields, split events.

## Account Abstraction Performance Optimizations (Dec 2024)

- Batch transactions don't work (state changes don't propagate between calls)
- Infinite Approval + Caching: ~3.5s savings on repeat bets
- Sequential Transactions with Receipt Waiting: current approach
- Optimistic UI Updates: deduct balance immediately, sync after settlement
- NEVER use `Process.sleep()` after async operations
- Use PubSub broadcasts for cross-LiveView updates

See [docs/AA_PERFORMANCE_OPTIMIZATIONS.md](AA_PERFORMANCE_OPTIMIZATIONS.md).

## BUX Booster Smart Contract Upgrades (Dec 2024)

**Proxy Address**: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` (UUPS)

**Upgrade Process**:
```bash
cd contracts/bux-booster-game
npx hardhat compile
npx hardhat run scripts/force-import.js --network rogueMainnet
npx hardhat run scripts/upgrade-manual.js --network rogueMainnet
npx hardhat run scripts/init-vN.js --network rogueMainnet
npx hardhat run scripts/verify-upgrade.js --network rogueMainnet
```

**V3**: Server calculates results, sends to contract. CommitmentHash as betId.
**V4**: Removed on-chain server seed verification for player transparency.
**V5**: Added ROGUE native token betting via ROGUEBankroll.
**V6**: Added referral reward system (1% of losing BUX bets).
**V7**: Separated BUX-only stats tracking (buxPlayerStats, buxAccounting).

See [docs/contract_upgrades.md](contract_upgrades.md) for full details.

## BUX Booster Balance Update After Settlement (Dec 2024)

When using `attach_hook` with `{:halt, ...}`, the hook intercepts the message and prevents it from reaching the LiveView's `handle_info`. Update all needed assigns in the hook handler.

## Multi-Flip Coin Reveal Bug (Dec 2024)

Must schedule `Process.send_after(self(), :reveal_flip_result, 3000)` in `:next_flip` handler, not just on initial bet confirmation.

## House Balance & Max Bet Display (Dec 2025)

Max Bet Formula: `base_max_bet = house_balance * 0.001`, scaled by `20000 / multiplier_bp`. All fetches async via `start_async`. See [docs/bux_minter.md](bux_minter.md).

## Infinite Scroll for Scrollable Divs (Dec 2024)

IntersectionObserver `root` option: `null` = window scroll, `this.el` = element scroll. Must attach/cleanup scroll listener to correct target.

## Mnesia Pagination Pattern (Dec 2024)

Use `Enum.drop(offset) |> Enum.take(limit)` for Mnesia pagination. Track offset in socket assigns.

## Recent Games Table Implementation (Dec 2024)

Nonce as bet ID, transaction links with `?tab=logs`, sticky header with `sticky top-0 bg-white z-10`. Ensure `phx-hook="InfiniteScroll"` is on the scrollable div itself.

## Unauthenticated User Access to BUX Booster (Dec 2024)

Non-logged-in users can interact with full UI. Guard all `current_user.id` access with nil check. "Place Bet" redirects to `/login`. See [docs/bux_booster_onchain.md](bux_booster_onchain.md).

## Recent Games Table Live Update on Settlement (Dec 2024)

Added `load_recent_games()` to `:settlement_complete` handler so settled bets appear immediately.

## Aggregate Balance ROGUE Exclusion Fix (Dec 2024)

When calculating aggregate balance, exclude both `"aggregate"` and `"ROGUE"` keys. ROGUE is native gas token, not part of BUX economy.

## Provably Fair Verification Fix (Dec 30, 2024)

Fixed three issues: template deriving results from byte values (not stored results), client seed using user_id (not wallet_address), commitment hash using hex string (not binary). Old games before fix cannot be externally verified.

## Contract V4 Upgrade - Removed Server Seed Verification (Dec 30, 2024)

Removed `sha256(abi.encodePacked(serverSeed)) != bet.commitmentHash` check. Server is trusted source (V3 model). Allows player verification with standard SHA256 tools. See [docs/v4_upgrade_summary.md](v4_upgrade_summary.md).

## ROGUE Betting Integration - Bug Fixes and Improvements (Dec 30, 2024)

1. **ROGUE Balance Not Updating**: Added broadcast after `update_user_rogue_balance()`
2. **Out of Gas**: Set explicit `gas: 500000n` for ROGUE bets (ROGUEBankroll external call)
3. **ROGUE Payouts Not Sent**: BUX Minter now detects `token == address(0)` and calls `settleBetROGUE()`
4. **ABI Mismatch**: Solidity auto-generated getters exclude dynamic arrays (`uint8[] predictions`)
5. **ROGUEBankroll V6**: Added accounting system
6. **ROGUEBankroll V9**: Added per-difficulty stats (`getBuxBoosterPlayerStats`)
7. **BuxBoosterBetSettler**: Auto-settles stuck bets every minute

See [docs/ROGUE_BETTING_INTEGRATION_PLAN.md](ROGUE_BETTING_INTEGRATION_PLAN.md).

## BetSettler Bug Fix & Stale Bet Cleanup (Dec 30, 2024)

Fixed BetSettler calling wrong function. Cleaned up 9 stale orphaned bets.

**bux_booster_onchain_games Table Schema** (22 fields):
| Index | Field | Description |
|-------|-------|-------------|
| 0 | table name | :bux_booster_onchain_games |
| 1 | game_id | UUID |
| 2 | user_id | Integer |
| 3 | wallet_address | Hex string |
| 4 | server_seed | 64-char hex |
| 5 | commitment_hash | 0x-prefixed |
| 6 | nonce | Integer |
| 7 | status | :pending/:committed/:placed/:settled/:expired |
| 8-16 | bet details | bet_id, token, amount, difficulty, predictions, bytes, results, won, payout |
| 17-19 | tx hashes | commitment_tx, bet_tx, settlement_tx |
| 20-21 | timestamps | created_at, settled_at (Unix ms) |

Match pattern tuple size MUST exactly match table arity (22 elements).

## BetSettler Premature Settlement Bug (Dec 31, 2024)

Reused game sessions kept original `created_at`, making BetSettler think bet was "stuck". Fix: update `created_at` to NOW in `on_bet_placed()`.

## Token Price Tracker (Dec 31, 2024)

PriceTracker GenServer polls CoinGecko every 10 min for 41 tokens. Stores in Mnesia `token_prices` table. Broadcasts via PubSub topic `token_prices`. See [docs/ROGUE_PRICE_DISPLAY_PLAN.md](ROGUE_PRICE_DISPLAY_PLAN.md).

## Contract Error Handling (Dec 31, 2024)

Error signatures mapped in `assets/js/bux_booster_onchain.js` (`CONTRACT_ERROR_MESSAGES`). Key errors: `0xf2c2fd8b` BetAmountTooLow, `0x54f3089e` BetAmountTooHigh, `0x05d09e5f` BetAlreadySettled, `0x469bfa91` BetNotFound.

## GlobalSingleton for Safe Rolling Deploys (Jan 2, 2026)

Custom conflict resolver keeps existing process, rejects new one. Uses distributed `Process.alive?` via RPC. Applied to MnesiaInitializer, PriceTracker, BuxBoosterBetSettler, TimeTracker. See [docs/mnesia_setup.md](mnesia_setup.md).

## NFT Revenue Sharing System (Jan 5, 2026)

NFTRewarder at `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594` (Rogue Chain). 0.2% of losing ROGUE bets distributed to 2,341 NFT holders weighted by multiplier (30x-100x). Backend services in high-rollers-nfts. See [high-rollers-nfts/docs/nft_revenues.md](../high-rollers-nfts/docs/nft_revenues.md).

## BuxBooster Performance Fixes (Jan 29, 2026)

1. Added HTTP timeouts to `:httpc.request()` calls
2. Made `load_recent_games()` async in mount
3. Fixed socket copying in `start_async` (extract assigns before async)

Result: page load 30s → <2s.

## BuxBoosterStats Module (Feb 3, 2026)

Backend module at `lib/blockster_v2/bux_booster_stats.ex`. Direct JSON-RPC calls to BuxBoosterGame and ROGUEBankroll contracts. See [docs/bux_booster_stats.md](bux_booster_stats.md).

## BuxBooster Player Index (Feb 3, 2026)

Indexes players by scanning BetPlaced/BuxBoosterBetPlaced events. Mnesia table `:bux_booster_players`. Incremental updates every 5 min. See [docs/bux_booster_stats.md](bux_booster_stats.md).

## BuxBooster Stats Cache (Feb 3, 2026)

ETS cache at `:bux_booster_stats_cache`. TTLs: global 5min, house 5min, player 1min.

## BuxBooster Admin Stats Dashboard (Feb 3, 2026)

Routes: `/admin/stats`, `/admin/stats/players`, `/admin/stats/players/:address`. Protected by AdminAuth. See [docs/bux_booster_stats.md](bux_booster_stats.md).

## Mnesia Stale Node Fix - CRITICAL (Feb 16, 2026)

### The Problem
After the content automation deploy (v292/v293), Mnesia on node 865d lost all table replicas. Every table showed `storage=unknown, local=false`. The `token_prices` table was crashing with `{:aborted, {:no_exists, ...}}`.

### Root Cause
On Fly.io, each deploy creates machines with new internal IPs, which means new Erlang node names. When a node is replaced, the OLD node name stays in the Mnesia schema's `disc_copies` list as a stale reference. When a new node tries to `add_table_copy(table, node(), :disc_copies)`, Mnesia runs a schema merge across ALL nodes in `db_nodes` — including the dead one. The dead node "has no disc" so the merge fails with `{:combine_error, table, "has no disc", dead_node}`. This also prevents `change_table_copy_type(:schema, node(), :disc_copies)`, leaving the schema as `ram_copies` — which then causes ALL subsequent `add_table_copy` calls to fail.

### Diagnosis
```
# On broken node:
:mnesia.table_info(:schema, :storage_type)  # => :ram_copies (should be :disc_copies)
:mnesia.system_info(:db_nodes)              # => includes dead node name
:mnesia.system_info(:running_db_nodes)      # => does NOT include dead node
:mnesia.table_info(:token_prices, :storage_type)  # => :unknown
```

### Manual Fix Applied
1. Backed up all Mnesia data: `:mnesia.dump_to_textfile('/data/mnesia_backup_20260216.txt')` on healthy node (17817). Also downloaded to local machine at `mnesia_backup_20260216.txt`.
2. Removed stale node from schema on healthy node: `:mnesia.del_table_copy(:schema, stale_node)` — this only removes the reference, does NOT touch data.
3. Deleted corrupted Mnesia directory on broken node (865d) — it had zero usable data anyway (all tables `storage=unknown`).
4. Restarted broken node — it joined the cluster fresh, got `disc_copies` for all 29 tables.
5. Verified: 38,787 records, exact match on both nodes.

### Code Fix (mnesia_initializer.ex)
Added `cleanup_stale_nodes/0` function that runs BEFORE `ensure_schema_disc_copies/0` in all three cluster join paths (`safe_join_preserving_local_data`, `join_cluster_fresh`, `use_local_data_and_retry_cluster`).

```elixir
defp cleanup_stale_nodes do
  db_nodes = :mnesia.system_info(:db_nodes)
  running = :mnesia.system_info(:running_db_nodes)
  stale = db_nodes -- running
  # For each stale node: :mnesia.del_table_copy(:schema, stale_node)
end
```

**Why it's safe:** Only removes nodes in `db_nodes` but NOT in `running_db_nodes`. A live node is always in `running_db_nodes`. On Fly.io, old node names (with old IPs) will never come back.

### Recovery (if code fix causes issues)
1. Restore backup: `:mnesia.load_textfile('/data/mnesia_backup_20260216.txt')` on any node
2. Local backup at: `mnesia_backup_20260216.txt` in project root
3. Or revert the code change — the `cleanup_stale_nodes` and `ensure_schema_disc_copies` functions are additive; removing them restores old behavior

### Key Lesson
The MnesiaInitializer already handled node name changes for the PRIMARY node path (`migrate_from_old_node`), but NOT for the JOINING node path. The gap existed since the MnesiaInitializer was written but only triggered when a deploy happened to create the right conditions (stale node + joining node path).

## AirdropVault V2 Upgrade — Client-Side Deposits (Feb 28, 2026)

### Problem
AirdropVault V1 only had `depositFor()` as `onlyOwner`, meaning deposits required the vault admin (BUX Minter backend) to execute. This created an unnecessary server-side dependency for what should be a direct user→contract interaction.

### Solution
Created AirdropVaultV2 inheriting from V1, adding a public `deposit(externalWallet, amount)` function. The user's smart wallet calls `BUX.approve()` + `vault.deposit()` entirely client-side — no minter backend needed for deposits.

### Key Details
- **V2 contract**: `contracts/bux-booster-game/contracts/AirdropVaultV2.sol` — inherits V1, adds `deposit()` using `msg.sender` as blocksterWallet
- **JS hook**: `assets/js/hooks/airdrop_deposit.js` — `needsApproval()` + `executeApprove()` + `executeDeposit()` (same pattern as BuxBooster's `bux_booster_onchain.js`)
- **LiveView flow**: `redeem_bux` → pushes `airdrop_deposit` to JS hook → hook does on-chain tx → pushes `airdrop_deposit_complete` back → LiveView records entry in Postgres
- **Deploy script**: `contracts/bux-booster-game/scripts/upgrade-airdrop-vault-v2.js`
- **`using SafeERC20 for IERC20`**: Must be declared in V2 even though V1 has it — Solidity `using` directives don't automatically apply to child contract functions
- **Mock conflict**: Deleted `contracts/mocks/AirdropVaultV2.sol` (test mock) because it had the same contract name as the real V2

### Settler GenServer
`lib/blockster_v2/airdrop/settler.ex` — GlobalSingleton that auto-settles rounds:
- On startup: recovers state from DB (handles restarts)
- On `create_round`: schedules timer for `end_time`
- On timer: close round (on-chain or RPC fallback) → draw winners → register prizes on Arbitrum
- Uses `Process.send_after` for precise scheduling (not polling)

### Test Fixes
Many airdrop tests were failing because `Airdrop.redeem_bux` calls `deduct_user_token_balance` in Mnesia, but tests never set up a Mnesia balance. Fixed by adding `setup_mnesia` + `set_bux_balance` helpers to both `airdrop_live_test.exs` and `airdrop_integration_test.exs`. Also updated prize amount assertions from old values ($250/$150/$100/$50) to current test pool ($0.65/$0.40/$0.35/$0.12).

---

## NFTRewarder V6 & RPC Batching (Mar 2026)

### Problem
Two background processes in `high-rollers-elixir` made individual RPC calls per NFT, burning ~29,000 Arbitrum RPC calls/hour (QuickNode) and ~21,600 Rogue Chain calls/hour:
- **OwnershipReconciler**: `ownerOf(tokenId)` × 2,414 NFTs every 5 min
- **EarningsSyncer**: `timeRewardInfo(tokenId)` × ~361 special NFTs every 60 sec

### Solution: Two-Pronged Approach

**Arbitrum**: Multicall3 (canonical at `0xcA11bde05977b3631167028862bE2a173976CA11`) wraps N `ownerOf` calls into 1 `eth_call`.

**Rogue Chain**: Upgraded NFTRewarder to V6 with native batch view functions (Multicall3 is NOT on Rogue Chain).

### NFTRewarder V6 Contract Changes
- Added `getBatchTimeRewardRaw(uint256[])` — returns 3 parallel uint256 arrays (startTimes, lastClaimTimes, totalClaimeds)
- Added `getBatchNFTOwners(uint256[])` — returns address array from nftMetadata mapping
- Both are read-only view functions, zero state risk
- **Implementation**: `0xC2Fb3A92C785aF4DB22D58FD8714C43B3063F3B1`
- **Upgrade tx**: `0xed2b7aeeca1e02610d042b4f2d7abb206bf6e4d358c6f351d0e444b8e1899db2`

### Elixir Implementation (high-rollers-elixir)

| File | Change |
|------|--------|
| `lib/high_rollers/contracts/multicall3.ex` | New module — Multicall3 ABI encoding/decoding, aggregate3, aggregate3_batched |
| `lib/high_rollers/contracts/nft_contract.ex` | Added `get_batch_owners/1` via Multicall3 |
| `lib/high_rollers/contracts/nft_rewarder.ex` | Added `get_batch_time_reward_raw/1` and `get_batch_nft_owners/1` |
| `lib/high_rollers/ownership_reconciler.ex` | Refactored `reconcile_batch` to use batch owners; added `maybe_update_rewarder_batch` |
| `lib/high_rollers/earnings_syncer.ex` | Refactored `sync_time_reward_claim_times` to use batch time reward queries |

### Expected Impact

| Process | Before | After (50/batch) | Reduction |
|---------|-------:|------------------:|----------:|
| OwnershipReconciler (Arbitrum) | 2,414 calls/cycle | 49 | 98% |
| EarningsSyncer time rewards (Rogue) | ~361 calls/cycle | 8 | 98% |
| **Hourly total (Arbitrum)** | **~29,000** | **~588** | **98%** |

### Key Learnings
- Rogue Chain RPC intermittently returns 500 on large contract deploys — retry after a few minutes
- Multicall3 ABI encoding requires careful offset calculations for dynamic types (Call3 contains `bytes callData`)
- Old per-NFT functions kept as fallbacks — `reconcile_single_nft/1`, `sync_single_time_reward/1`, `get_owner_of/1`, `get_time_reward_raw/1`

---

## Solana RPC State Propagation: Never Chain Dependent Txs Back-to-Back (Apr 2026)

**Problem**: Coin flip bets were failing with `NonceMismatch` on `PlaceBetSol` even though the on-chain `PlayerState` showed correct values (`nonce`, `pending_nonce`, and `pending_commitment` all matched). The error occurred intermittently, especially on rapid consecutive games.

**Root cause**: Solana RPC state propagation lag between dependent transactions. The flow was:
1. `settle_bet` tx confirms (modifies `PlayerState.nonce`, closes `BetOrder`)
2. Immediately after, `submit_commitment` tx confirms (modifies `PlayerState.pending_nonce`, `PlayerState.pending_commitment`)
3. Player places next bet → wallet sends `place_bet` tx
4. Wallet's RPC (Phantom/Backpack use their own RPCs like Triton) hasn't seen both state changes yet
5. `place_bet` simulation fails because it reads stale `PlayerState`

The critical insight: even the **settler's own QuickNode RPC** showed correct state via `getAccountInfo`, but `simulateTransaction` on the same RPC returned `NonceMismatch`. The simulation engine may resolve to a different slot than `getAccountInfo`, especially when `replaceRecentBlockhash: true` is used.

**What we tried (and failed)**:
- 2s Process.sleep after `submit_commitment` — still failed
- 4s Process.sleep — still failed
- Preflight simulation on settler RPC before returning tx — confirmed NonceMismatch but didn't fix it
- JS retry loop (3 retries, 2s apart) — all 3 attempts failed over 6 seconds

**Fix**: Removed the `pre_init_next_game` pattern that submitted the next commitment immediately after settlement. Instead, `submit_commitment` now only happens when the player clicks "Play Again" (triggers `init_game` async). The natural UI delay (player picking predictions, choosing bet amount) gives all RPCs time to propagate state from the previous settlement + commitment.

**Rule**: On Solana, NEVER chain dependent transactions back-to-back and expect the next operation to see updated state immediately — even on the same RPC endpoint. If tx B reads state modified by tx A, ensure there is meaningful time (user interaction, explicit delay, or a fresh user action trigger) between A's confirmation and B's submission. This applies to ALL Solana code: settler services, client-side JS, scripts.

**Also fixed in this session**:
- `calculate_max_bet`: was using `net_lamports * 10 / 10000` (0.1%) instead of `net_lamports * 100 / 10000` (1%) — max bet was 10x too low
- Play Again button now hidden until `settlement_status == :settled`
- Token icons (SOL/BUX) and capitalized labels restored in game history table
- Expired bet reclaim banner and `reclaim_stuck_bet` handler added

---

## Solana Tx Reliability: Priority Fees + Confirmation Recovery (Apr 2026)

**Symptom**: Settler txs (commitments and settlements) frequently timing out on devnet. Bets would show results but settlement got stuck. After 3-4 bets, game init would block.

**Investigation path**: Initially assumed devnet RPC congestion. User correctly pushed back — bet placements (via wallet) worked fine while settlements (via settler) failed. The difference: wallets have their own well-provisioned RPC; the settler was using QuickNode devnet with no priority fees.

**Root causes found (in order)**:
1. **No priority fees** — all settler and user-signed txs had zero compute unit price. Devnet validators routinely drop zero-fee txs.
2. **Default preflight used "finalized" commitment** — added ~15s latency before the tx was even sent to the leader.
3. **No rebroadcasting** — if a leader dropped the tx, it was never resent.
4. **Deprecated confirmation API** — `confirmTransaction(sig, "confirmed")` has a blanket 30s timeout with no blockhash expiry awareness.
5. **Txs landing but confirmation missed** — the most insidious issue. The tx would land on-chain during the rebroadcast window, but `confirmTransaction` would time out. On retry, the settler rebuilt the SAME instruction with a fresh blockhash — but the bet_order PDA was already closed by the first (successful) tx, so attempt 2 failed with `AccountNotInitialized`.

**Fix**: `sendSettlerTx` in rpc-client.ts — builds fresh blockhash per attempt, rebroadcasts every 2s, and critically: after blockhash expiry, checks `getSignatureStatus` on the original signature before retrying. If the tx landed ("Tx landed despite timeout"), returns success instead of retrying with a stale instruction.

**Key learning**: On Solana, "transaction not confirmed" ≠ "transaction failed." Always check signature status before retrying write operations that modify/close accounts.

---

## Payout Rounding: Float.round vs On-Chain Integer Truncation (Apr 2026)

**Symptom**: `PayoutExceedsMax` error during settlement when betting near max bet. Also, wallet simulation revert when clicking the max bet button.

**Root cause**: Elixir's `Float.round(bet * multiplier / 10000, decimals)` can round UP, producing a value 1-2 lamports above what the on-chain Rust program computes with integer division (which always truncates DOWN).

Example: bet = 0.123456789 SOL, multiplier = 10200 BPS
- **Rust**: `(123456789 * 10200) / 10000 = 125,925,924` lamports (truncated)
- **Elixir Float.round**: `0.125926` → 125,926,000 lamports (**exceeds by 76 lamports**)

**Two locations affected**:
1. `calculate_payout` in coin_flip_game.ex — payout sent to settle_bet exceeded on-chain max_payout
2. `calculate_max_bet` in coin_flip_live.ex — max bet displayed to user exceeded on-chain per-difficulty limit. Had an additional subtlety: on-chain does TWO integer divisions (base then max_bet), each truncating. Single float operation skips the intermediate truncation.

**Fix**: Both functions now replicate on-chain integer math exactly — convert to lamports, use `div` for each step, convert back. Verified with test: old = 125,926,000 (exceeds), new = 125,925,924 (matches Rust exactly).

---

## LP Price Chart History Implementation (Apr 2026)

Ported FateSwap's LP price chart approach to Blockster pool pages. Key decisions and learnings:

**Architecture choice**: FateSwap uses ETS ordered_set (in-memory, fast range queries) + PostgreSQL (persistence). Blockster uses Mnesia ordered_set which serves both roles (in-memory + persistent). The `dirty_index_read` on `:vault_type` secondary index returns all records for a vault, then filters in Elixir — acceptable at current scale (~1 record/min = ~43k/month).

**Downsampling**: Copied FateSwap's exact approach — group by time bucket (`div(timestamp, interval)`), take last point per bucket. Timeframes: 1H=60s, 24H=5min, 7D=30min, 30D=2hr, All=1day. Added a guard to skip downsampling when <500 raw points — without this, a fresh chart with only minutes of data gets collapsed to 1-2 points on the 24H view.

**Real-time chart updates on settlement**: FateSwap computes LP price incrementally from settlement data (vault_delta = amount - payout - fees). Blockster instead fetches fresh pool stats from the settler HTTP endpoint after each settlement — simpler, one extra HTTP call to localhost, acceptable latency. The `LpPriceHistory.record/3` accepts `force: true` to bypass the 60s throttle for settlement-triggered updates.

**PubSub chain**: `CoinFlipGame.settle_game` → broadcasts `{:bet_settled, vault_type}` on `"pool:settlements"` → `LpPriceTracker` receives, fetches stats, records price → broadcasts `{:chart_point, point}` on `"pool_chart:#{vault_type}"` → `PoolDetailLive` receives, pushes `"chart_update"` to JS → `series.update(point)`.

**JS changes**: Event key changed from `points` to `data` to match FateSwap. Added deferred init with `requestAnimationFrame` + retry if container width=0 (race condition on mount). Debounced resize observer (100ms).

**Restart required**: LpPriceTracker GenServer must restart to subscribe to the new `"pool:settlements"` PubSub topic (subscription happens in `:registered` handler, not hot-reloadable).

---

## Solana Wallet Field Migration Bug (Apr 2026)

**Problem**: BUX tokens were never minted for Solana users despite engagement tracking recording rewards correctly. Users earned BUX from reading but balance stayed at 0.

**Root cause (3 bugs)**:
1. **Wrong wallet field** (main cause): All mint/sync calls across the codebase used `smart_wallet_address` (EVM ERC-4337 smart wallet), which is nil for Solana users. Solana users' wallet lives in `wallet_address`. Since the field was nil, the `if wallet && wallet != ""` guard failed and minting was silently skipped.

2. **Wrong response key**: The Solana settler service returns `{ "signature": "..." }` in mint responses, but Elixir code pattern-matched on `"transactionHash"` (EVM format). This caused pool deductions, video engagement updates, and `:mint_completed` messages to silently skip even if a mint somehow succeeded.

3. **`and` vs `&&` operator**: Line 568 in `show.ex` used `wallet && wallet != "" and recorded_bux > 0`. When `wallet` is nil, `wallet && wallet != ""` short-circuits to `nil`, then `nil and ...` raises `BadBooleanError` because `and` requires strict booleans. Fixed by using `&&` throughout.

**Files fixed (wallet field — `smart_wallet_address` → `wallet_address`)**:
- `post_live/show.ex` — article read, video watch, X share minting (3 locations)
- `referrals.ex` — referee signup bonus, referrer reward lookup and mint
- `telegram_bot/promo_engine.ex` — promo BUX credits
- `admin_live.ex` — admin send BUX/ROGUE
- `share_reward_processor.ex` — share reward processing
- `event_processor.ex` — AI notification BUX credits
- `checkout_live/index.ex` — post-checkout balance sync
- `orders.ex` — buyer wallet, affiliate payout minting, affiliate earning recording
- `notification_live/referrals.ex` — referral link URL

**Files fixed (response key — `"transactionHash"` → `"signature"`)**:
- `post_live/show.ex` — article read and video watch mint responses
- `referrals.ex` — referrer reward mint response
- `share_reward_processor.ex` — share reward mint response
- `admin_live.ex` — admin send BUX response
- `member_live/show.ex` — claim read/video reward responses
- `orders.ex` — affiliate payout tx hash (`"txHash"` → `"signature"`)

**Key lesson**: When migrating from EVM to Solana, the wallet field name changes (`smart_wallet_address` → `wallet_address`) and API response keys change (`transactionHash` → `signature`). A global search for the old field/key names should be part of any chain migration checklist.

**Note**: `smart_wallet_address` references in schema definitions, account creation, auth controllers, admin display templates, bot system, and DB queries were intentionally left as-is — those are either EVM-specific code paths, display-only, or schema fields that must match the DB column.

---

## Bot Wallet Solana Migration (Apr 2026)

**Problem**: The bot system wasn't covered by the April wallet field migration above. The 1000 read-to-earn bots had real EVM ed25519 keypairs (`wallet_address` = `0x...`, generated by `WalletCrypto.generate_keypair/0` using secp256k1 + keccak256) but `BotCoordinator.process_mint_job/1` and `build_bot_cache/1` were reading `smart_wallet_address` (a random 0x hex placeholder). After Phase 3 rewrote `BuxMinter` to call the Solana settler, every bot mint silently failed: the placeholder hex strings can't be decoded as base58 ed25519 pubkeys, so the settler `/mint` endpoint rejected them.

**Root cause**: Two distinct issues stacked on top of each other:
1. **Wrong field**: Bot coordinator used `smart_wallet_address` instead of `wallet_address` (the same trap as the main wallet field bug, but the bot system was missed in that pass).
2. **Wrong key format**: Even after fixing #1, the bot wallets in `wallet_address` were EVM 0x addresses, not Solana base58 pubkeys. The settler still couldn't accept them.

**Solution**:
- New `BlocksterV2.BotSystem.SolanaWalletCrypto` module generates ed25519 keypairs via `:crypto.generate_key(:eddsa, :ed25519)`. Pubkey gets base58-encoded (32 bytes → Solana address); secret gets concatenated as `seed(32) || pubkey(32)` and base58-encoded (the standard Solana 64-byte secret key format compatible with `@solana/web3.js`'s `Keypair.fromSecretKey()`).
- `BotSetup.create_bot/1` switched from `WalletCrypto.generate_keypair/0` (EVM) to `SolanaWalletCrypto.generate_keypair/0`. `smart_wallet_address` still gets a random 0x placeholder because `User.email_registration_changeset/1` requires it (legacy schema field) — but the bot system never reads it.
- New `BotSetup.rotate_to_solana_keypairs/0` (replaces the old `backfill_keypairs/0`): finds every bot whose `wallet_address` is not a 32-byte base58 string, generates a fresh ed25519 keypair, updates `wallet_address` + `bot_private_key` in PG, and deletes the bot's row from `user_solana_balances` Mnesia (the cached SOL/BUX belonged to the now-orphaned EVM wallet). Idempotent — second call returns `{:ok, 0}`.
- `BotCoordinator.handle_info(:initialize, ...)` calls `rotate_to_solana_keypairs/0` after `get_all_bot_ids/0` and **before** `build_bot_cache/1`. This means the very first cache built on first deploy uses the rotated wallets — no race window where the cache holds stale EVM addresses.
- `build_bot_cache/1`, `get_bot_cache_entry/1`, and `process_mint_job/1` all switched from `smart_wallet_address` → `wallet_address`.

**Cost on production deploy**: ~2 SOL one-time to the settler authority for the ATA creation surge as the rate-limited bot mint queue (one mint per 500 ms) creates Associated Token Accounts for the 1000 rotated bots. Documented in `docs/solana_mainnet_deployment.md` Step 1 (bumped recommended authority funding from 1 SOL → 3 SOL) and Step 8 (verification commands).

**Key lesson**: When migrating bot/automated user wallets between chains, cache invalidation matters in two places — Postgres (the source of truth) AND any read-side caches (Mnesia balance rows, in-memory bot caches in GenServers). If the rotation runs before the GenServer cache is built, no race exists. If you rotate after, in-flight mint jobs will use stale addresses until the cache is rebuilt. Order of operations in `:initialize` is load-bearing.

**Files**: `solana_wallet_crypto.ex` (new), `bot_setup.ex`, `bot_coordinator.ex`. Tests: `solana_wallet_crypto_test.exs` (10 new), 3 new rotation tests in `bot_setup_test.exs`, ~16 cache-shape swaps in `bot_coordinator_test.exs`. Full breakdown in `docs/solana_build_history.md` § "Bot Wallet Solana Migration (2026-04-07)".

---

## Non-Blocking Fingerprint Verification (Mar 2026)

**Problem**: Users on Safari, Firefox, Brave, or with ad blockers got a hard block error ("Unable to verify device. Please use Chrome or Edge browser to sign up.") during signup because FingerprintJS Pro couldn't load or execute.

**Root cause**: The client-side JS in `home_hooks.js` required a successful fingerprint before proceeding with wallet connection and signup. If `getFingerprint()` returned null (FingerprintJS blocked), the user was stopped with an alert and could not sign up at all.

**Fix (Mar 25, 2026)**:
- **Client-side** (`assets/js/home_hooks.js`): Removed hard block — fingerprint failure now logs a warning and proceeds. Used optional chaining (`fingerprintData?.visitorId`) for safe property access when sending null to server.
- **Server-side** (`lib/blockster_v2/accounts.ex`): Made `fingerprint_id` and `fingerprint_confidence` optional in `authenticate_email_with_fingerprint`. When no fingerprint data is provided, all device verification is skipped and signup proceeds normally.
- **Config** (`config/runtime.exs`): Added `:test` to `skip_fingerprint_check` environments so test env skips FingerprintJS HTTP calls like dev does.
- **Refactored skip logic**: `SKIP_FINGERPRINT_CHECK` now only skips the HTTP call to FingerprintJS API — fingerprint DB operations (conflict detection, device tracking) still run when fingerprint data is present.

**Result**: All browsers can sign up. Anti-sybil protection still applies when FingerprintJS works (Chrome, Edge, no ad blockers). Users whose browsers block FingerprintJS sign up without device tracking.

**Also fixed**: 71 pre-existing test failures across shop (order.total_amount → total_paid), notifications (missing category validation/filtering, stale defaults), referrals (reward amounts 100→500), and telegram (env check ordering).

---

## FateSwap Solana Wallet Tab (Mar 2026)

Added a new "FateSwap" tab to the High Rollers site that lets NFT holders register their Solana wallet address for cross-chain revenue sharing from FateSwap.io.

### Mnesia Schema: Separate Table vs Field Addition
Adding a field to an existing Mnesia table (`hr_users`) is problematic:
- Existing records on disk have N elements; new schema expects N+1
- `mnesia:transform_table/3` can fail with `:bad_type` if disc_copies and schema mismatch
- `dirty_write` of records with extra fields fails if table definition hasn't been updated

**Solution**: Use a separate Mnesia table (`hr_solana_wallets`) for new data. Zero migration risk, no schema conflicts.

### MnesiaCase Test Infrastructure Fix
LiveView tests using both `MnesiaCase` + `ConnCase` were failing (16 tests) because `MnesiaCase.setup` called `:mnesia.stop()` which crashed the supervision tree (MnesiaInitializer → cascade → Endpoint dies → ETS table gone).

**Fix**: `MnesiaCase` now detects if the application is running and uses non-destructive setup — `mnesia:clear_table` instead of stop/restart. This preserves the supervision tree while still isolating test data.

### Sales Module Bug Fixes
- `get_sales/2` was filtering on `mint_price` instead of `mint_tx_hash` — unminted NFTs with default price passed the filter
- Sorting was by `token_id` desc instead of `created_at` desc — pagination tests expected chronological order
- `format_eth/1` used `decimals: 3` instead of `decimals: 6`

### Solana Transaction Confirmation — Websockets vs Polling (2026-04-05)

**Problem**: The settler's `sendSettlerTx` and client-side `coin_flip_solana.js` used Solana web3.js `confirmTransaction` which relies on websocket subscriptions internally. This caused:
1. Second bet settlement consistently slower than first — concurrent `sendSettlerTx` calls (commitment + settlement) created competing websocket subscriptions and rebroadcast `setInterval` loops on the same shared `Connection` object
2. Unreliable on devnet — websocket connections drop, delay, or miss notifications
3. Unnecessary complexity — rebroadcast every 2s, 3-attempt blockhash retry loops, signature status checks on expiry

**Root cause**: In EVM, `tx.wait()` uses simple HTTP polling (`eth_getTransactionReceipt`). The Solana code was doing something fundamentally different — websocket subscriptions + manual rebroadcasting — which is fragile and creates contention when multiple txs are in flight.

**Fix**: Replaced all confirmation with `getSignatureStatuses` polling — the Solana equivalent of `tx.wait()`:
- `rpc-client.ts`: new `waitForConfirmation()` polls every 2s, 60s timeout. `sendSettlerTx` simplified to single send + poll. Removed `getBlockhashWithExpiry`, rebroadcast intervals, multi-attempt retry logic
- `airdrop-service.ts`: 4 functions switched from `confirmTransaction` to `waitForConfirmation`
- `coin_flip_solana.js`: new `pollForConfirmation()` replaces `confirmTransaction` for bet placement and reclaim

**Key insight**: `sendRawTransaction` with `maxRetries: 5` already tells the RPC node to handle delivery retries. Application-level rebroadcasting on top of that is redundant and creates RPC contention.

### Ad System — Luxury Templates + Banner Bug Hunt (2026-04-15)

Big session adding a luxury-vertical ad template family (watches → cars → jets) to the existing template-based banner system. Plus several latent bugs surfaced.

**New templates** in `lib/blockster_v2_web/components/design_system.ex`:
- `luxury_watch` — full inline editorial card (image-driven height, brand · model · reference · live SOL price)
- `luxury_watch_compact_full` — narrower variant, image-driven height (no crop)
- `luxury_watch_skyscraper` — 200px sidebar tile
- `luxury_watch_banner` — full-width horizontal leaderboard
- `luxury_watch_split` — split layout (info left, white watch panel right)
- `luxury_car` — landscape hero + year/model headline + spec row + live SOL price
- `luxury_car_skyscraper` — 200px sidebar
- `luxury_car_banner` — full-width horizontal
- `jet_card_compact` — narrower jet card with cropped jet image (replaced removed `jet_card` full-size)
- `jet_card_skyscraper` — 200px sidebar

All luxury templates share live SOL pricing helpers (`luxury_watch_price_sol/1`, `luxury_watch_format_usd/1`) that read from `BlocksterV2.PriceTracker.get_price("SOL")` Mnesia cache (refreshed every minute). USD is stored in `params["price_usd"]`; SOL converts at render time.

Admin form (`/admin/banners`) extended with all new templates in dropdown + per-template `@template_params` lists. Added `@enum_params` map for select-dropdown fields (currently only `image_fit` for the portrait template).

**Bug 1: `Enum.random` in templates re-rolls on every re-render.** Both `show.html.heex` (8 slots) and `index.html.heex` (2 slots) used `<% banner = Enum.random(@list) %>` inline. LiveView re-evaluates this on every diff. With widget pollers broadcasting on PubSub every 3-60s, the random pick churned constantly — users saw the ad swap mid-view (especially noticeable on hover). **Fix**: pre-pick at mount via new `random_or_nil/1` helper, assign as `*_pick` socket assigns, templates use the frozen pick.

**Bug 2: Widget shell CSS scope was a descendant selector.** `.bw-widget .bw-shell { background: var(--bw-bg) }` — but every widget root had both classes on the SAME element (`<div class="bw-widget bw-shell">`). The descendant selector never matched, widgets rendered transparent against whatever parent bg they landed on. Symptom: all widgets blended into the white page bg. **Fix**: changed selectors to `.bw-widget.bw-shell, .bw-widget .bw-shell` (and same for `.bw-card`, `.bw-shell-bg-grid`) to handle both same-element + descendant cases.

**Bug 3: Tailwind dev watcher + arbitrary classes.** When the running `bin/dev` was started before new files were added, Tailwind v4's JIT didn't pick up the arbitrary classes in those new files (`w-[200px]`, `h-[320px]`, etc.). Symptom: widgets rendered at intrinsic content size with NO width constraints — token logos became giant circles, sidebar tiles wrapped weirdly. **Fix**: `mix assets.build` regenerated CSS from scratch. The watcher works once it sees new files; the issue is files added after watcher startup. Recommended: restart `bin/dev` after adding new component files.

**Bug 4: Hardcoded discover cards in article left sidebar.** `show.html.heex` had ~120 lines of inline EVENT/TOKEN-SALE/AIRDROP cards that the new design no longer needs. Removed them; the sidebar now renders only widget banners (with the "Sponsored" header). One test had to be flipped from asserting the old copy to asserting the absence (refute).

**Bug 5: Silent admin form failure.** Creating a portrait-template banner in `/admin/banners` did nothing visible when validation failed. The form only displayed errors for `:name` and `:placement` — every other field's error was swallowed. **Fix**: added a top-of-form red error summary listing all changeset errors when `@form.source.action != nil`. Inline `image_url` error display added under the upload field. Banner Image label now shows `*` + "required for template ads" / "ignored for widget banners" depending on whether a Widget Type is selected.

**Bug 6: Image fit defaults to `cover` on portrait template.** The portrait template used `class="w-full h-full object-cover"` which crops images that don't match the 4:3 aspect. **Fix**: added `image_fit` enum param (`cover` / `contain` / `scale-down`) — a select dropdown in the admin (first use of the new `@enum_params` system). Added `image_bg_color` param for the bars when using `contain`/`scale-down`.

**Bug 7: Removed redundant placement options.** `play_sidebar_left/right`, `airdrop_sidebar_left/right` (legacy — new design has no sidebars on /play or /airdrop), and `homepage_inline_desktop`/`homepage_inline_mobile` (redundant with `homepage_inline`). Dropped from admin dropdown but kept in `@valid_placements` whitelist for legacy banner-row compat. Migrated active banner #32 from `homepage_inline_desktop` → `homepage_inline` and updated seed script.

**Bug 8: Homepage top banner template-based ads bypassed `ad_banner` dispatcher.** `index.html.heex` had a manual `<a><img>` fallback for non-widget banners at `homepage_top_*`, which meant template-based ads (like the new luxury_car_banner) rendered as raw images. **Fix**: replaced both branches with `BlocksterV2Web.WidgetComponents.widget_or_ad` which dispatches widget-or-template correctly.

**Image hosting workflow** for luxury ads:
1. Download source image (curl)
2. Pad watch images to ~270×380 with sips (`sips -p H W --padColor FFFFFF`); crop car/jet images to remove dealer-overlay strips with `sips -c H W --cropOffset 0 0`
3. Upload to S3 via `ExAws.S3.put_object(bucket, key, binary, content_type: ..., acl: :public_read)` to `ads/<dealer-slug>/<ts>-<hex>-<filename>`
4. Reference at `https://ik.imagekit.io/blockster/<key>` (ImageKit serves from the S3 bucket as origin)
5. Update banner row's `image_url` + `params["image_url"]`

**Seed file**: `priv/repo/seeds_luxury_ads.exs` creates all 15 luxury banners on production. Idempotent on `name`. Same pattern as `seeds_widget_banners.exs`. Run manually via `mix run priv/repo/seeds_luxury_ads.exs` or via Fly: `flyctl ssh console --app blockster-v2 -C "/app/bin/blockster_v2 eval 'Code.eval_file(...)'"`.

**Templates removed during this session** (accumulated cruft):
- `luxury_watch_compact` — image cropped at fixed 280px height; replaced by `luxury_watch_compact_full`
- `jet_card` — 720px-wide full version; replaced by `jet_card_compact` (560px) per user preference
- Banner #39 (green portrait Day-Date), #41 (compact Day-Date), #43+#44 (Lambo homepage banner pre-feedback) — deleted from DB
- 17 inactive `FateSwap*` legacy image banner rows — deleted

---

## Web3Auth Custom JWT replaces EMAIL_PASSWORDLESS popup (2026-04-21)

**Why**: Web3Auth's `EMAIL_PASSWORDLESS` connector opens a separate popup window running Web3Auth's own captcha + code-entry UI. When the user leaves the popup to grab the code from their inbox, the popup drops behind the main tab. Users never find it, or find it and can't sign in because the code field is stuck in the popup.

**Fix**: own the OTP flow + hand Web3Auth a signed JWT via its `CUSTOM` connector. Same architecture as the existing Telegram path.

**Flow**:
1. Modal email → `POST /api/auth/web3auth/email_otp/send` → `EmailOtpStore.send_otp/1` (ETS, 60s cooldown, 10-min TTL, 5-attempt lockout) + async Mailer.
2. Inline code entry → `POST /api/auth/web3auth/email_otp/verify` → `EmailOtpStore.verify_otp/2` + `Web3AuthSigning.sign_id_token(%{sub: email, email: email, email_verified: true})`.
3. `start_web3auth_jwt_login` pushed to JS hook → `connectTo(AUTH, { authConnection: CUSTOM, authConnectionId: "blockster-email", extraLoginOptions: { id_token, verifierIdField: "sub" } })`.
4. Web3Auth validates JWT against our JWKS → derives MPC wallet. No popup opens.
5. `web3auth_authenticated` pushed back → server mints session.

**Dashboard requirement**: add a Custom JWT verifier `blockster-email` (JWKS at our `/.well-known/jwks.json`, verifier ID field `sub`, iss `blockster`, aud `blockster-web3auth`, RS256). Dev uses Cloudflare tunnel because Web3Auth rejects localhost JWKS URLs.

**Google/Apple/X still use Web3Auth's OAuth popup** — OAuth providers require a redirect window, unavoidable. Those popups are quick, not captcha+code.

**Rule**: if a third-party auth SDK handles the credential step in its own popup/iframe, you'll hit the popup-behind-main-window problem. Don't ship it. Every provider that exposes a "custom JWT" connector is preferable when you already run your own auth.

---

## EmailOtpStore lock check falsely triggered by monotonic clock (2026-04-21)

Initially used `System.monotonic_time(:millisecond)` for `created_at_ms`, `expires_at_ms`, `locked_until_ms`. On Erlang/OTP 26 on macOS the monotonic clock starts around `-576460751000` (negative, huge magnitude). With `now = -576460751000` and `locked_until = 0` (the sentinel for "unlocked"), `0 > -576460751000` = `true` → every fresh record looked locked. Tests caught it instantly: `left: {:error, :invalid_code}, right: {:error, {:locked, 576460750}}`.

**Fix**: `System.system_time(:millisecond)` everywhere in this module. Wall-clock ms from Unix epoch, always positive, sentinels like `0` safely mean "unset".

**Rule**: `System.monotonic_time/1` is for measuring DURATIONS only (always non-decreasing, arbitrary origin often negative). For anything that compares against sentinel values or absolute timestamps, use `System.system_time/1`. Don't mix.

---

## Email ownership = account ownership → wallet replacement on social login (2026-04-21)

**Original plan**: plan §5.5 said reject same-email collisions with a clear error pointing to the existing account's sign-in method.

**Reality**: product overruled — every consumer SaaS treats email-plus-OTP as proof of ownership. If you own the email you own the account. We merge; we don't reject.

**Post-merge semantics**:
- `wallet_address` REPLACED with Web3Auth-derived Solana pubkey
- `smart_wallet_address` NULLed (was EVM ERC-4337; Solana-native users have it nil)
- `auth_method` → `"web3auth_email"`
- `email` promoted from legacy row
- Legacy BUX snapshot minted to new Solana wallet via settler (`BuxMinter.mint_bux(wallet, amount, user_id, nil, :legacy_migration)`)
- Legacy row: `is_active: false`, `merged_into_user_id: <new_id>`

**Infrastructure change**: `LegacyMerge.merge_legacy_into!/2` grew to `/3` with an opts list. `skip_reclaimable_check: true` bypasses the `reclaimable_holder?/1` defense-in-depth check that the legacy `EmailVerification.verify_code` path still honors.

**Accepted attack vector**: if an attacker has access to the target's email AND can receive the OTP, they take over the account. This isn't new — every consumer SaaS is vulnerable equally. Hardening (wallet sig from already-linked wallet as 2FA) is v1.1+.

---

## auth_method_for must branch on verifier name for CUSTOM connector (2026-04-21)

Web3Auth reports `authConnection: "custom"` for ANY Custom JWT verifier login — Telegram, email, or any future custom provider. `Accounts.auth_method_for/1` originally mapped `"custom"` directly to `"web3auth_telegram"`, so every email sign-in got misclassified.

**Fix**: for the `"custom"` branch, look at the `verifier` claim. `verifier` containing `"email"` → `"web3auth_email"`, `"telegram"` → `"web3auth_telegram"`. `String.contains?/2` matches both bare names and `aggregateVerifier`-wrapped forms.

**Rule**: when multiple identity providers share a single `authConnection` value, you need a secondary discriminator (usually the verifier name). Don't collapse them in the mapping.

---

## Onboarding skip links must resolve through the user's filtered step list (2026-04-21)

**Symptom**: a Web3Auth email user on the phone step clicked "Skip for now" → got bounced back to welcome. Infinite loop.

**Root cause**: `<.link patch={~p"/onboarding/email"}>` was hardcoded. Web3Auth email users have `email` filtered out of `@steps`. `handle_params` for a step not in `@steps` redirects to welcome.

**Fix**: `next_step_in_flow(current_step, steps)` helper returns the next step in the user's filtered list, or `"complete"`. Each skip link gets a `skip_to` assign computed at render time.

**Rule**: any UI that navigates within a dynamically-filtered list must derive its targets from the list at render time, not from hardcoded assumptions.

---

## Elixir strict vs lax boolean operators in HEEx conditions (2026-04-21)

```heex
<%= if @show or (@connecting and (@connecting_wallet_name or @connecting_provider)) do %>
```

Compiled but crashed at runtime: `BadBooleanError: expected a boolean on left-side of "or", got: "Phantom"`. Elixir's `and` / `or` are STRICT boolean operators — strings are truthy in Elixir logic but rejected here.

**Fix**: use `&&` / `||` for truthy/falsy semantics with any type:

```heex
<%= if @show || (@connecting && (@connecting_wallet_name || @connecting_provider)) do %>
```

**Rule**: in HEEx / Elixir code where operands could be strings, maps, structs, etc., use `&&` / `||`. Reserve `and` / `or` for guard clauses, Ecto query ops, explicit booleans.

---

## Stale browser bundle after JS hook changes (2026-04-21)

Added `_startJwtLogin` method to `web3auth_hook.js`; browser threw `this._startJwtLogin is not a function`. The method was in both the source and the compiled bundle (verified via grep) — browser cache was serving a pre-change version.

**Fix**: hard-refresh (⌘⇧R) bypasses cache. `mix assets.build` forces an esbuild rerun when the watcher hasn't caught up.

**Rule**: LiveView's hot-reload patches HTML but doesn't re-pull assets. Hard-refresh after adding methods/fields to hook objects is non-negotiable.

---

## Session wallet vs derived pubkey correlation (2026-04-21)

Web3Auth hook pushed `web3auth_session_persisted` with `wallet_address = <JWT-derived pubkey>`. For the email-collision reclaim case the server merged into a different wallet. LiveView's `wallet_authenticated` handle_info looked up user by the derived pubkey, got nil, didn't update the header. UI stayed in "Connect wallet" state despite the session cookie being live.

**Fix**: `_persistWeb3AuthSession` reads the server's canonical `user.wallet_address` from the `/api/auth/web3auth/session` response and pushes THAT through the event. The LiveView handler accepts `pending_wallet_auth` matching either the derived pubkey OR the canonical session wallet.

**Rule**: when a server response can disagree with a client-side computed value, the server wins. Propagate server values through downstream events, not client guesses.

---

## Web3Auth `init()` throws on empty rpcTarget (2026-04-21)

`Web3Auth.init()` calls `new URL(chain.rpcTarget)` on every chain. Empty string throws browser URL construction error. Web3Auth surfaces this as opaque `Please provide a valid rpcTarget in chains for chain 0x67`.

**Fix**: `wallet_auth_events.ex :web3auth_config` falls back to our QuickNode devnet URL when `SOLANA_RPC_URL` is empty. Prod still needs the env var explicitly (the fallback is a dev-only convenience, not prod safety).

**Rule**: when a third-party SDK validates config at init time with opaque errors, add your own eager guard that fails with a readable message first.

---

## `@moduletag :skip` must come AFTER `use ExUnit.Case` (2026-04-21)

Adding `@moduletag :skip` to the top of a test module, BEFORE `use BlocksterV2.DataCase`, compile-errors with:

```
** (RuntimeError) you must set @tag, @describetag, and @moduletag after the call to "use ExUnit.Case"
```

ExUnit's `Case` module needs its macro to run first so the tag registry is in place.

**Fix**: put the tag after `use`:

```elixir
defmodule MyTest do
  use BlocksterV2.DataCase, async: false
  @moduletag :skip
```

**Rule**: test-module setup order matters. `use ... Case` first, then tag attributes, then code.

---

## Web3Auth silent reconnect — you cannot trust `init()` returning (2026-04-21)

**Symptom**: After Web3Auth email OTP sign-in, navigating to `/play` logged `WalletInitializationError: Wallet is not ready yet, Already connecting` OR `JsonRpcError: Method not found` from `provider.request({method: "solana_privateKey"})`. `window.__signer` never installed; user couldn't place a bet despite being signed in at the session level.

**Do not guess**: I initially patched symptoms by adding sleeps / `waitForSigner` retries. User: "no same error, you're just stabbing at things revert that back and figure out what the problem actually is and let me know dont make any code changes." Reverted, then read `node_modules/@web3auth/no-modal/dist/lib.esm/` source.

**Root cause**: Web3Auth's top-level `init()` resolves BEFORE the internal `CONNECTORS_UPDATED` event fires. That event runs `setupConnector` → `connector.init` → `connector.connect` — the actual rehydrate from `storageType: "local"`. So:
1. `init()` returns; caller thinks ready.
2. Internal connector status is still `CONNECTING` (async rehydrate in flight).
3. Caller runs `provider.request({method: "solana_privateKey"})` → the provider is a skeleton at this point → throws `Method not found`.
4. Fallback runs `connectTo(AUTH, ...)` → hits `checkConnectionRequirements` → throws `Wallet is not ready yet, Already connecting` because status === `CONNECTING`.

The SDK exposes an internal state machine via `getConnector(WALLET_CONNECTORS.AUTH).status` with values `NOT_READY / READY / CONNECTING / CONNECTED / DISCONNECTED / ERRORED`. Only terminal states (not `CONNECTING`) are safe to act on.

**Fix pattern** (`assets/js/hooks/web3auth_hook.js`):
1. `_waitForConnectorSettle()` — poll `getConnector(AUTH).status` until terminal. Never before that.
2. Fast path: try `provider.request({method: "solana_privateKey"})`. If rehydrate worked, `__signer` installs with zero user interaction.
3. Slow path: `POST /api/auth/web3auth/refresh_jwt` to get a fresh id_token (signed by our `Web3AuthSigning`), then `connectTo(AUTH, { authConnection: CUSTOM, authConnectionId: <verifier>, extraLoginOptions: { id_token, verifierIdField: "sub" } })` with retry on "Already connecting" errors.

**Rule**: when an SDK has state that can't be settled synchronously, read its state machine — don't layer sleeps, don't guess "it should be ready by now". Sleeps race; state machines are deterministic.

**Sub-rule**: when a user tells you to stop guessing, **stop guessing**. Open the SDK source, trace the actual control flow, then write the fix.

---

## feePayerMode: "settler" makes Web3Auth bets truly zero-SOL (2026-04-21)

Phase 1 added `rent_payer: settler` to the Anchor program so users don't need to fund PDA rent. But `feePayer` stayed `= player` because Wallet Standard wallets (Phantom, Solflare) reject multi-signer txs where they're not fee_payer — it's a UX invariant those wallets enforce.

Result: Web3Auth users (who sign locally from an exported key, not via a wallet extension) still needed ~0.000005 SOL for the signature fee. A user arriving via email OTP lands on a fresh MPC-derived wallet with 0 SOL — first bet fails with "insufficient funds" before the program even sees the tx.

**Fix**: conditional fee payer by auth method.

- `bankroll-service.ts buildPlaceBetTx` takes `feePayerMode: "player" | "settler"`:
  - `"settler"` → `tx.feePayer = settler.publicKey`; settler partial-signs both rent_payer AND fee_payer slots.
  - `"player"` → Phase-1 behavior (player fee_payer, settler rent_payer only).
- `BuxMinter.fee_payer_mode_for_user/1` returns `"settler"` for `auth_method` starting with `"web3auth_"`, else `"player"`.
- `CoinFlipLive` calls `BuxMinter.build_place_bet_tx(..., fee_payer_mode: BuxMinter.fee_payer_mode_for_user(current_user))`.

**Why safe for Web3Auth users**: they sign locally — no Wallet Standard invariant to honor. The extra signature cost lands on the settler's operational SOL balance (already funded for Phase 1's rent_payer role).

**Why unsafe as a global default**: Phantom/Solflare/Backpack reject. Always route through `fee_payer_mode_for_user/1`; never default `"settler"` on the settler side.

---

## Zero-SOL pool deposits/withdrawals for Web3Auth users (2026-04-21 late evening)

Same pattern as bets, missed on the first pass. User reported: Web3Auth email wallet with 0 SOL tries to deposit BUX, tx hangs silently. `buildPlaceBetTx` had `feePayerMode` but the four pool builders (`buildDepositSolTx`, `buildDepositBuxTx`, `buildWithdrawSolTx`, `buildWithdrawBuxTx`) still hardcoded `feePayer: player`. With `skipPreflight: true`, the underfunded tx never hits a clean rejection — it enters the mempool, never lands, and `getSignatureStatuses` times out after 60s. UI renders a generic timeout that looks like a hang.

**Fix**: extend the same pattern to all four pool builders + both `pool_hook` Elixir entry points.

- `bankroll-service.ts`: 4 builders now accept `feePayerMode`. Deposit variants additionally swap the pre-ix ATA funder (`createAssociatedTokenAccountInstruction` first arg) to settler when in settler mode — otherwise the 0-SOL user can't open their first bSOL/bBUX ATA and the pre-ix fails before the deposit ix runs.
- `routes/pool.ts`: `feePayerMode` plumbed through all 4 endpoints; shared `parseFeePayerMode` helper collapses unknown values to `"player"`.
- `BuxMinter.build_deposit_tx/4` + `build_withdraw_tx/4`: backward-compatible optional opts with `:fee_payer_mode`.
- `PoolDetailLive` + `PoolLive`: resolve via `fee_payer_mode_for_user(current_user)` and pass through.

**Why no program upgrade** (despite `init_if_needed` with `payer = depositor` on the LP-token ATA): the tx builder pre-creates the ATA in a separate instruction *before* the deposit ix runs. `init_if_needed` then sees the account exists and skips init entirely — the `payer = depositor` constraint never evaluates. Withdraws have no init anywhere.

**Key takeaway**: when adding a cross-cutting UX guarantee ("zero SOL for social users"), enumerate EVERY user-signed tx builder upfront — not just the first one the failing report names. Grep for `feePayer: player` across all services, not just the one you're editing. The coin-flip fix was right on its own terms but incomplete as a product promise.

---

## Coin flip profit display subtracted the stake twice (2026-04-21 very late)

**Symptom**: user bets 10 BUX on "win all 2 flips" (3.96× multiplier), wins → UI says `+ 19.60 BUX` but recent-games table correctly says `+ 29.60 BUX`.

**Cause**: `@current_bet` was doing double duty. At bet-placement it's the real stake; during `:next_flip` it gets doubled (`socket.assigns.current_bet * 2`) to animate the "stake at risk rolls into next flip" effect for `:win_all` mode. The win/loss result banners calculated profit as `@payout - @current_bet`. After flip 1 wins, `current_bet = 20`, so for a 10-stake 39.60-payout win you get `39.60 − 20 = 19.60`.

**Fix**: snapshot the unmodified stake into a new `@placed_stake` assign at bet-placement time (alongside `current_bet: bet_amount`). The four result-UI sites (win banner profit, loss banner amount, "House contributed" sub-line, loss description "Your stake of X") read `@placed_stake`. `current_bet` keeps its role in the active-flip animation (lines 539/544/916/931 — "stake at risk" displays).

**Key takeaway**: when an animation variable shares a name with the canonical value it started from, think hard about every read-site before reusing it for UI that runs AFTER the animation. Either a dedicated snapshot (the fix here) or rename the animation variable (`current_bet` → `stake_at_risk`) — just don't let display code guess which temporal state the variable is in.

---

## Internal code names leak into user-facing text (2026-04-21 very late)

**Symptom**: loss recap on coin flip result page said *"LP holders earn from your loss, just as you would earn from theirs if you held bSOL"* — even when the user had just bet BUX.

**Cause**: two bugs in the same copy block. Internal mint-derivation names (`bSOL`, `bBUX`) — the names by which Anchor / Mnesia / TypeScript reference the LP tokens — leaked into user-facing prose. AND the sentence was hardcoded to "bSOL" regardless of which token was bet.

CLAUDE.md explicitly calls out the convention: *"LP tokens `bSOL` / `bBUX` (displayed as SOL-LP / BUX-LP)."* Mint derivations stay `bSOL`/`bBUX`, UI displays `SOL-LP`/`BUX-LP`.

**Fix**: `<%= @selected_token %>-LP` in the template (renders as `SOL-LP` or `BUX-LP`). Also routed the CTA to the matching vault (`/pool/sol` vs `/pool/bux`), not the index.

**Key takeaway**: before writing UI copy that names a token or asset, grep for where else the same entity is named in user-facing text — you'll find the project's convention. If the convention says the UI name differs from the code name, don't let the code name win just because it's what you were staring at in the editor.

---

## Web3Auth `_silentReconnect` race at mount was producing noisy Uncaught errors (2026-04-21 very late)

**Symptom**: console showed `WalletInitializationError: Wallet is not ready yet, Already connecting` on pool pages. The error IS caught (retry loop + upstream `.catch`), but Chrome logs the first rejection before the async catch handler runs on the microtask queue — looks uncaught to a reader.

**Cause**: `_connectWithRetry` never waited for Web3Auth's connector to settle BEFORE attempt 0. The SDK runs rehydration inside a `CONNECTORS_UPDATED` event listener that keeps the connector in `connecting` state for hundreds of ms after init. Our retry depended on a catch-and-retry inside the loop, so attempt 0 always threw "Already connecting" on cold loads before the loop recovered. Chrome surfaced the first throw loudly.

Additionally: `_refreshViaServerJwt` calls `await this._web3auth.logout()` when there's a stale connected state, then immediately `connectTo`. `logout` resolves before its internal state listeners finish updating — so the next connectTo again races the transition.

**Fix** (`assets/js/hooks/web3auth_hook.js`):
- `_connectWithRetry`: added `await this._waitForConnectorSettle(2000)` BEFORE the loop, so attempt 0 lands on a terminal state (`ready` / `disconnected` / `connected`).
- `_refreshViaServerJwt`: added `await this._waitForConnectorSettle(2000)` AFTER the pre-connect `logout()`.

Belt-and-suspenders — either one might suffice in isolation but both defend the entry points.

**Key takeaway**: "caught but noisy" still counts as a bug. A retry loop that catches every attempt 0 failure is working as designed from the code's POV, but the browser console tells a different story. When a known race condition throws loudly enough that Chrome considers it unhandled (even briefly), fix the race — don't just rely on the handler.

---

## Average Cost Basis for pool LP positions (2026-04-21 very late)

Pool detail page had placeholder `—` for Cost Basis and Unrealized P/L forever. Implemented with Average Cost Basis (ACB) accounting — the simplest model that gives intuitive numbers across deposits, partial withdraws, and full-exit-then-redeposit cycles.

**State** stored in new Mnesia `:user_pool_positions` keyed `{user_id, vault_type}`:
- `total_cost` — running basis in underlying token
- `total_lp` — locally tracked LP balance (mirrors on-chain)
- `realized_gain` — lifetime gains from withdrawals

**Deposit** of `amount` at `lp_price`: `total_cost += amount`, `total_lp += amount/lp_price`.

**Withdraw** of `lp_burned` at `lp_price`: proportionally remove cost (`cost_removed = lp_burned × total_cost/total_lp`), accumulate `realized_gain += (lp_burned × lp_price) − cost_removed`, subtract both from totals. Clamp to exact zero on full withdraw (floating-point residuals otherwise leave `total_lp = 1.2e-15`).

**Pre-existing LP holders** (who deposited before this module shipped): `seed_if_missing` on first render sets `total_cost = current_lp × current_lp_price`. Not a true basis — it's a "from here forward" baseline. P/L shows ~0 initially, gets real on the next tx. Pragmatic choice to avoid indefinite dashes.

**Why ACB over FIFO/LIFO**: FIFO/LIFO needs per-lot tracking (each deposit stored with its price, withdrawals eat lots). More accurate for tax reporting, overkill for a glance-at-it in-UI metric. Uniswap/Curve use ACB-style presentation.

**Why `socket.assigns.lp_price` at tx-confirm time** (not on-chain price at landing slot): sub-second divergence between sign time and land time is close enough for a display metric. Reading actual vault state at a specific slot would require an extra settler call per confirmation — not worth the complexity for a display number.

**Files**:
- `lib/blockster_v2/pool_positions.ex` — new module (get/2, record_deposit/4, record_withdraw/4, seed_if_missing/4, summary/4)
- `lib/blockster_v2/mnesia_initializer.ex` — new `:user_pool_positions` table schema
- `lib/blockster_v2_web/live/pool_detail_live.ex` — `tx_confirmed` dispatches, `render/1` seeds + summarizes, 3 format helpers (`format_cost_basis/2`, `format_pnl/2`, `pnl_color/1`)

**Key takeaway**: placeholder dashes in a live UI are worse than nothing — users see a slot they expect to be filled and treat it as broken. If a field can't be computed yet, either hide it entirely or ship the simplest-possible version. ACB with a seeded baseline is a simple-possible that's truthful within one transaction.

---

## Pool page readability: data tiles don't belong on bright gradient hero cards (2026-04-21 very late)

**Symptom**: user couldn't read numbers on the pool cards. Stat tiles used `bg-black/20` (SOL) or `bg-black/[0.12]` (BUX) — barely distinguishable from the bright gradient base. Labels at `text-white/50–60` opacity washed out entirely on `#00FFA3` / `#CAFC00`.

**Fix**: converted all data tiles to `bg-white/95 ring-black/5 shadow-sm` with `text-[#141414]` values + `text-neutral-500` labels. Gradient keeps the hero zone (logo + big LP price + sparkline); data sits on white cards floating over it — same layering pattern Phantom/Backpack/DefiLlama use. Accent profit numbers unified to `text-[#15803d]` (emerald) for clean contrast on white.

**Key takeaway**: translucent tiles + low-opacity text over a high-saturation gradient is a default design choice that reads well in Figma mockups (gradient area has modest color variance) but falls apart in-product when the gradient spans actual screen-scale luminance differences. When the base is bright-and-saturated, data should sit on a high-contrast surface, not a tinted window into the gradient.

---

## Client Solana hooks must use QuickNode, not `api.devnet.solana.com` (2026-04-21)

**Symptom**: pool deposit tx signed and confirmed on-chain, but the UI spun indefinitely. Console showed a cascade of `POST https://api.devnet.solana.com/ 429 (Too Many Requests)` with exponential backoff retries.

**Cause**: `pool_hook.js`, `airdrop_solana.js`, `coin_flip_solana.js` all hardcoded `const DEVNET_RPC = "https://api.devnet.solana.com"`. CLAUDE.md has a critical rule forbidding public RPCs — `signAndConfirm`'s `getSignatureStatuses` poll loop (~800ms cadence) rate-limits to 429 within a handful of ticks.

**Fix**: all four client hooks (including `sol_payment.js` which already did this) now use:

```js
const RPC_URL =
  window.__SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/...";
```

Prod wires `window.__SOLANA_RPC_URL` to the mainnet endpoint.

**Rule**: when adding a critical rule to CLAUDE.md, IMMEDIATELY grep the codebase for the forbidden pattern. The rule is only as good as the sweep that goes with it. Lesson learned the hard way.

---

## Balance broadcasts must fire after Mnesia writes, not rely on the poll (2026-04-21)

User: "BUX balance was updating correctly after a win or loss, it just wasn't updating quickly enough to show the new balance minus the stake."

**Cause**: `EngagementTracker.update_user_solana_bux_balance/3` and `update_user_sol_balance/3` wrote the new balance to Mnesia but didn't broadcast to LiveView subscribers. The header only updated on the next `BuxBalanceHook` poll tick, which could be many seconds away — so placing a bet left the header showing pre-stake balance for an uncomfortably long window.

**Fix**: both functions now call `BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update(wallet_address, %{bux: ..., sol: ...})` after the dirty_write. The LiveView picks up the broadcast and patches the header in place — sync is instantaneous.

**Rule**: any write to balance state must co-locate with its broadcast. Relying on downstream polls to catch up is a latency footgun users see immediately.

---

## Pool cost-basis bug: `|> assign(…)` inside `render/1` does NOT touch the socket (2026-04-22)

**Symptom**: partial pool withdraw showed a phantom "unrealized loss" — Cost basis stayed at the full original deposit while Current value shrank to the remaining LP's worth. Audit screenshot: `Cost basis: 1.0008, Current value: 0.4887, Unrealized P/L: − 0.5121` after a 50% withdraw that actually returned 0.51 SOL to wallet.

**What I assumed first**: the ACB math in `PoolPositions.record_withdraw/4` was wrong. Spent time reading the math. Math was correct.

**Actual cause**: `record_withdraw` was never being called. `tx_confirmed/3` had a guard `if is_number(lp_price) and lp_price > 0`, reading from `socket.assigns[:lp_price]`. That assign was ALWAYS nil at event time.

Why nil: `pool_detail_live.ex render/1` computed `lp_price` from `assigns.pool_stats` and wrote `|> assign(lp_price: lp_price)` inside the function-component assigns pipeline. That `assign` updates the LOCAL assigns map passed to the `~H` template — it does NOT reach `socket.assigns` outside of render. So the guard in `handle_event("tx_confirmed", …)` read nil, silently skipped the `record_withdraw` call, and Mnesia's cost-basis row never updated. LP balance refresh happened normally on the next tick, so the render produced "full cost / half the LP / phantom loss".

**Fix** (`af403b1`): one line. `handle_async(:fetch_pool_stats, {:ok, {:ok, stats}}, socket)` now also assigns `lp_price` to the socket. render/1 still recomputes locally (kept for early-mount tolerance). tx_confirmed now sees a real number.

**Rule**: function-component `|> assign(…)` inside `render/1` is a LOCAL map mutation, not a socket assign. Before setting anything there, ask "does any handler outside render read this from socket.assigns?" If yes, the assign has to live somewhere the socket actually carries — a mount, a handle_event, a handle_info, or a handle_async.

---

## CF-01 InvalidServerSeed: on-chain commitment race, NOT Mnesia seed overwrite (2026-04-22)

**Symptom**: rapid coin flip bets intermittently failed settlement with Anchor error `InvalidServerSeed (0x178a)`. Bet SOL stuck in the bankroll until the 5-min reclaim window fired; `CoinFlipBetSettler` spammed `0x178a` retries every 60s forever.

**What the audit hypothesised**: Mnesia's `:coin_flip_games` table getting overwritten when two bets fired close together — two rows for the same `{user_id, nonce}` key with different seeds, settler reads the wrong one.

**What was actually happening**: `:coin_flip_games` is keyed by a unique `game_id` per call — rows can't clobber. The race lives on the on-chain program:

- `submit_commitment.rs:59` stores the commitment hash in `player_state.pending_commitment`. This is a **single field per player**, not per-nonce.
- `place_bet_sol.rs:144` copies `bet_order.commitment_hash = player_state.pending_commitment` and clears the field to zero at line 152.
- Trigger: two `submit_commitment(player, nonce_N, …)` calls before the first `place_bet(player, nonce_N)` lands on-chain. The second commit SILENTLY overwrites the first's hash. The original user's place_bet then stamps the NEW commit into its bet_order. Settler submits `settle_bet(seed_for_first_commit)` against a bet_order now containing `hash(second_seed)` → `InvalidServerSeed`.
- Practical triggers: multi-tab `/play`, mid-signing reconnect, rapid reclaim-then-new-bet. A single-tab single-flow user doesn't hit it. A multi-tab user does.

**Fix strategy** (PR 2a, commits `3036481` → `31f54aa` + settler `fa6551a`):
1. Program stays untouched (audit Don't-do list: no program upgrade for CF-01).
2. **Settler-side** pre-submit guard fetches the bet_order from chain, computes `SHA256(server_seed)`, and returns structured HTTP 409 `commitment_mismatch` if it doesn't match. Catches the mismatch before burning a tx fee.
3. **Elixir-side** recovery: when settler returns 409, look up a SIBLING game in Mnesia whose stored commitment_hash matches what's on chain, and resettle with THAT game's seed. New `:commitment_hash` index on `:coin_flip_games`. If no matching seed exists locally, park the bet as `:manual_review` — the background settler stops retrying, the UI surfaces a "needs manual review" CTA, and PR 2b's dead-letter queue handles admin surfacing.

**Lesson** — don't trust audit root-cause hypotheses at face value. Read the on-chain code. The Mnesia theory was tempting (table names line up), but 30 minutes with `place_bet_sol.rs` made the race obvious. If the prescribed fix still works against the real cause (it does — SHA256 lookup is commitment-content-addressed regardless of which race produced the mismatch), ship it; if not, escalate to the user.

**Additional rule from this session**: when a `-0x178a` error fires repeatedly in a settler loop, the bet fee is unrecoverable until the 5-min reclaim window — users see "retrying forever" but the money is actually gone for that duration. Any terminal-class classifier (see PR 2b SettlerRetry) MUST dead-letter fast; the retry loop was amplifying the impact, not fixing it.

---

## Migrations aren't on the `mix test` compile path — extract logic to `lib/` (2026-04-22)

**Symptom**: `apply(BlocksterV2.Repo.Migrations.BackfillWinnerSolanaAddresses, :up, [])` inside a test raised `UndefinedFunctionError: function … is undefined (module … is not available)`. `mix compile` succeeded; `mix ecto.migrate` found the module; `mix test` did not.

**Cause**: migration files in `priv/repo/migrations/` are loaded by Ecto only when `mix ecto.migrate` runs. They're NOT added to the `mix compile` path. So any test that tries to invoke a migration module directly fails to find it.

**Fix**: extract migration logic into `lib/blockster_v2/airdrop/winner_address_backfill.ex` (a regular compile-path module). Migration wrapper becomes:

```elixir
defmodule BlocksterV2.Repo.Migrations.BackfillWinnerSolanaAddresses do
  use Ecto.Migration

  def up, do: BlocksterV2.Airdrop.WinnerAddressBackfill.run(repo())
  def down, do: :ok
end
```

Tests call `WinnerAddressBackfill.run(Repo)` directly; behaviour is identical in prod and test.

**Rule**: any data migration worth testing has its logic in `lib/`, not in the migration file. The migration wrapper is five lines. Testability is non-optional for data migrations — they mutate and can't be rolled back cleanly; unit coverage is the last line of defence.

---

## Test-assertion gotchas from Phase 1 + 2

Three patterns that cost debug cycles and should never cost them again:

1. **HEEx `disabled={true}` renders the bare `disabled` attribute**, not `disabled="disabled"`. `html =~ ~s(disabled="disabled")` always fails. Assert on the companion `cursor-not-allowed` class or tooltip copy instead — OR use `element("button[disabled]")` in a LiveView test.
2. **IEEE-754 slop: `0.051 - 0.05 = 9.999999999999994e-4`, not exactly `0.001`.** `assert x == 0.001` fails in ways that look like a logic bug but aren't. Use `assert_in_delta x, 0.001, 1.0e-9` for any multi-step float arithmetic.
3. **Wrapping `phx-keyup` in a `<form phx-change="…">` requires a second handler clause.** The keyup payload is `%{"value" => v}`, the form-change payload is `%{"<input-name>" => v}`. Crashed `update_amount` in POOL-01 until both clauses existed.

**Meta-rule**: anything that looks like "the test is lying" usually means there's a subtle encoding / precision / payload-shape difference. Don't loosen the assertion until you've confirmed the semantics.

---

## Mnesia index idempotency via runtime `add_table_index` (2026-04-22)

Adding an index to an existing Mnesia table at deploy time is a footgun — `mix ecto.migrate` doesn't touch Mnesia, and writing a bespoke migration per index bloats the initializer. `reconcile_indexes/2` in `mnesia_initializer.ex` now idempotently adds any declared-but-missing index via `:mnesia.add_table_index/2`, keyed off `:mnesia.table_info(table, :index)`.

**Why it matters**: PR 2a needed `:commitment_hash` indexed on `:coin_flip_games` for the CF-01 recovery lookup. Existing live tables wouldn't pick up a new index from the table-definition block — it only applies on fresh creation. Running this reconciler on every boot makes adding an Mnesia index a one-line change.

**Guardrail**: wrapped in `rescue`/`catch` so a transient Mnesia error during reconcile doesn't crash boot. Worst case, the index isn't added yet and queries fall back to `dirty_match_object` (slower but correct).

---

## Coin Flip `BetTooLarge` (6016) — float round-trip lamport drift (2026-04-24)

**Symptom**: User hit `BetTooLarge` (Anchor custom error 6016) when clicking MAX on a 3-flip win-one (1.13×) bet. Lower multipliers (1.98×) accepted the same MAX just fine. Typing `1.04` manually worked, `1.05` (MAX value) failed. Off by ~1-3 lamports.

**Root cause**: the bet amount crosses 6 steps of float arithmetic between Elixir and chain. Each conversion introduces ≤1 lamport of drift; at low multipliers (1.98×) the `base * 20000 / 19800` ratio is ~1.01× and absorbs it, but at 1.13× the ratio is ~1.77× and the error compounds enough to push the amount 1-3 lamports *over* the chain's integer max.

The chain re-computes `max_bet = (vault_lamports - rent - liability) * max_bet_bps / 10000 * 20000 / multiplier_bps` in exact u128 integers at tx time. The client was off by up to 3 lamports on the same formula because:

1. Settler reads `vault.lamports()` (u64), converts to SOL float, subtracts `totalLiability` (also a float) — float precision loss (~1 lamport).
2. JSON encodes to Elixir.
3. Elixir does `trunc(house_balance * 1.0e9)` — `59.3 * 1e9` in IEEE-754 is `59299999999.99…` not `59300000000`.
4. Elixir computes max in integer lamports (safe).
5. Elixir divides back to SOL float: `max_bet_lamports / 1.0e9` — another float trip.
6. JS settler does `Math.floor(amount * 1e9)` — yet another round.

**Fix**: haircut the client's `calculate_max_bet` by **10 lamports** in `lib/blockster_v2_web/live/coin_flip_live.ex:2490-2513`. Invisible to the player (≈ $0.000002 on SOL at current prices) but absorbs any 1-3 lamport drift.

```elixir
max(0, max_bet_lamports - 10) / 1.0e9
```

**Why not just integer-math end-to-end**: the settler's `buildPlaceBetTx` accepts `amount: number` (JS float), and the settler itself round-trips balances through float in `getPoolStats`. Switching to bigint/string end-to-end is the proper fix but touches the settler API, client hook, and multiple LV sites. 10-lamport buffer is the pragmatic win until that refactor.

**Why 1.98× wasn't affected**: `* 20000 / 19800` ≈ `× 1.01`. Even with 3 lamports of pre-error, the result is within the chain's max. `* 20000 / 11300` ≈ `× 1.77` amplifies the same drift by 77%, crossing the threshold.

---

## Pool index sticky search bar ate half the mobile viewport — pills had to go (2026-04-24)

The `/hubs` page had a sticky search bar at `top-[88px]` with a search input PLUS a wrapping row of category chip buttons (≥10 pills on a 68-hub dataset). On mobile, that sticky strip took ~180 px of the 844 px viewport — over 20% — and the first hub card rendered *underneath* it thanks to the sticky overlay, making the page look broken.

**Fix**: removed the category chip row entirely from `hub_live/index.html.heex:146-157`. Kept the search bar + desktop-only "Sort by Most followed" hint. The sticky strip dropped to ~60 px.

**The actual lesson**: wrap-capable rows of N+ pills are hostile to sticky positioning. Either (a) move pills *below* the sticky element into the scrolling region, (b) collapse them into a dropdown/sheet on mobile, or (c) drop them. A horizontally-scrolling single row (`flex overflow-x-auto scrollbar-hide`) is fine; wrapping rows of 3-4+ are not.

---

## `position: sticky` gets trapped by `overflow-x-hidden` ancestor (2026-04-24)

The site header (`ds-header bg-white sticky top-0 z-30`) stopped sticking on `/wallet` even though it stuck on every other page. The wallet template wrapped everything — including the header — in:

```heex
<div class="ds-wallet-root min-h-screen bg-[#FAFAF9] relative overflow-x-hidden">
  <BlocksterV2Web.DesignSystem.header ... />
  ...
</div>
```

Any `overflow: hidden/auto/scroll` on an ancestor (including `overflow-x-hidden`) turns the nearest scrollable ancestor into the sticky containing block. The header was "sticky" inside a 0-height slot at the top of the wrapper — effectively static.

**Fix**: move `<.header />` OUT of the wrapper.

```heex
<BlocksterV2Web.DesignSystem.header ... />
<div class="ds-wallet-root min-h-screen bg-[#FAFAF9] relative overflow-x-hidden">
  ...
</div>
```

**Meta**: if a sticky element stops sticking, the first thing to check is whether an ancestor has `overflow-x-*` or `overflow-y-*`. Tailwind's `overflow-x-clip` does NOT trap sticky (it's a different box-model property) — prefer that if you just need to kill horizontal overflow without breaking sticky children.

---

## `element.scrollLeft = X` silently fails; use `element.scrollTo({left})` (2026-04-24)

Writing `container.scrollLeft = 140` and reading back `container.scrollLeft` returned `0` on the /play difficulty grid (flex container with `-mx-4 px-4 overflow-x-auto` inside a rounded card). Calling `container.scrollTo({ left: 140, behavior: "instant" })` on the same element worked and the value stuck. Observed in Chromium; MDN doesn't document the failure case.

The `ScrollToCenter` hook in `assets/js/app.js` was also racing LiveView's initial diff storm — the hook fires on `mounted()` via `requestAnimationFrame`, but LV emits 3-5 patches during the first second of mount that reset the container's scroll position. A single deferred call wasn't enough.

**Fix pattern for scroll-centering in LV hooks**:

```js
_center(smooth) {
  if (container.scrollWidth <= container.clientWidth) return;
  const selected = container.querySelector('[data-selected="true"]');
  if (!selected) return;
  const target = /* ... compute ... */;
  if (typeof container.scrollTo === "function") {
    container.scrollTo({ left: target, behavior: smooth ? "smooth" : "instant" });
  } else {
    container.scrollLeft = target;
  }
},
mounted() {
  // Retry schedule beats LV's initial diff storm. Cheaper than rigging up
  // a "fully mounted" signal and invisible to the user.
  [0, 120, 300, 600, 1200].forEach(t => setTimeout(() => this._center(false), t));
},
updated() {
  requestAnimationFrame(() => this._center(true));
}
```

**Takeaways**:
1. Never trust `element.scrollLeft = x` on a flex container with asymmetric padding — prefer `scrollTo()`.
2. LV hooks that need to position scroll on initial render must retry through the first 1-2 seconds.

---

## Send SPL/LP tokens: createAssociatedTokenAccountIdempotent + transferChecked (2026-04-24)

`/wallet` now lets a Web3Auth user send BUX, SOL-LP, and BUX-LP in addition to SOL. The JS hook (`assets/js/hooks/web3auth_withdraw.js`) builds a two-instruction transaction for SPL transfers:

1. **`createAssociatedTokenAccountIdempotent`** (ATA program discriminator `1`) for the recipient's ATA. Safe no-op if the ATA already exists; pays ~0.002 SOL rent from the sender if it doesn't. Always included so we skip a separate `getAccountInfo` round-trip that would race with someone else funding the ATA first.
2. **`transferChecked`** (Token program discriminator `12`) with the mint's decimals as a guard against display/scale mismatch.

**Why not `@solana/spl-token`**: the app already hand-rolls SPL instructions in `solana_bux_burn.js` to avoid the ~30 KB bundle hit. The two helpers (`deriveAta`, `buildTransferCheckedIx`, `buildCreateAtaIdempotentIx`) total ~50 lines — cheaper than the library import.

**Pre-flight guards** in `_signToken`:
- Destination pubkey parses.
- Destination isn't an already-initialized token account (footgun: sending SPL to an ATA owner-address mismatches silently burn).
- Source ATA exists and has balance ≥ amount.
- Sender has ≥ 0.001 SOL for tx fees.

**Backend flow** mirrors the SOL send — `wallet_live/index.ex` has token-aware `select_send_token`, `set_send_max`, `validate_send`, `review_send`, and `confirm_send`. `confirm_send` branches: SOL → `web3auth_withdraw_sign`, SPL → `web3auth_withdraw_token_sign` with `{to, amount, token, mint, decimals}` payload. `@send_form.token` carries the active token across the form lifecycle.

**Mint addresses** (devnet, same shape on mainnet once deployed):
- BUX: `7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX`
- bSOL (SOL-LP): `4ppR9BUEKbu5LdtQze8C6ksnKzgeDquucEuQCck38StJ`
- bBUX (BUX-LP): `CGNFj29F67BJhFmE3eJ2tCkb8ZwbQQ4Fd1xFynMCDMrX`

All three use 9 decimals.

