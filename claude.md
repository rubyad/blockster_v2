# Blockster V2

Phoenix LiveView web3 content platform — shop, hubs, events, token-based engagement. Migrated from Rogue Chain (EVM) to Solana.

> **Claude instructions**: Keep this file concise (~250 lines). Move detailed narratives into linked docs — do not grow CLAUDE.md.
>
> **When user says "update docs"**: update `docs/solana_build_history.md` (chronological build log), `docs/session_learnings.md` (bug fix narratives), and CLAUDE.md (only for stable patterns or new critical rules).

## Critical Rules

**Git**:
- NEVER add, commit, push, or change branches without explicit user instructions.
- NEVER run `git checkout --`, `git restore`, or `git stash` on a file without first running `git diff` to confirm no pre-existing uncommitted work. These destroy ALL unstaged work irreversibly. To undo only your edits, use targeted Edit calls.

**Security**:
- NEVER read `.env` files — they contain private keys.
- NEVER use public Solana RPCs (`api.devnet.solana.com`, `api.mainnet-beta.solana.com`). Always use the project QuickNode RPC from `contracts/blockster-settler/src/config.ts`.
- NEVER use `solana airdrop` or any devnet faucet — ask the user to fund wallets manually.
- NEVER cache Web3Auth-derived Solana private keys in memory between operations. Fetch via `provider.request({method: "solana_privateKey"})` per sign, use within the call, then `secretKey.fill(0)` in the `finally` block. Never write to localStorage/sessionStorage. See [docs/web3auth_integration.md](docs/web3auth_integration.md) §4 for the pattern.

**Solana transactions** (see [docs/solana_program_deploy.md](docs/solana_program_deploy.md)):
- Use `getSignatureStatuses` polling for confirmation — NEVER `confirmTransaction` (websocket), NEVER manual rebroadcast loops.
- NEVER chain dependent txs back-to-back — state propagation is unreliable even on the same RPC. Trigger dependent txs from user actions.

**Database / Mnesia**:
- NEVER run `mix ecto.reset`, `mix ecto.drop`, or any command that drops the database. Only `mix ecto.migrate` and `mix ecto.rollback` are safe.
- NEVER delete `priv/mnesia/*` directories — unrecoverable user data. No exceptions.
- NEVER truncate tables — production data (products, hubs, users) is manually curated.

**Fly.io secrets**:
- ALWAYS use `--stage`: `flyctl secrets set KEY=VALUE --stage --app blockster-v2`. Without `--stage`, Fly immediately restarts production.

**Tokens**:
- BUX tokens live ON-CHAIN. Mnesia is a cache; on-chain is source of truth. To move BUX out of a user's wallet: `approve()` + `transferFrom()` — NEVER mint as a shortcut.
- Primary wallet field is `wallet_address` (Solana pubkey for new users, EVM EOA for legacy). `smart_wallet_address` is legacy EVM ERC-4337, `nil` for Solana users — NEVER use it for BuxMinter calls.

**AI / dependencies**:
- AI Manager (`ai_manager.ex`) must always use Claude Opus. Never downgrade to Sonnet/Haiku.
- NEVER update Phoenix, LiveView, Ecto, or other core deps without explicit user permission.

**Deploy**:
- NEVER deploy without explicit user instructions. ALL tests must pass (`mix test`, zero failures) before deploy.
- Elixir hot-reloads — do not restart nodes after code fixes. Only restart for supervision tree / config changes.

**CSS debugging**:
- When the user reports a visual/spacing/sizing issue, open DevTools and inspect COMPUTED styles FIRST — before mutating HEEx or adding fixed heights.
- Widgets rendered inside `.prose` articles MUST have `not-prose` on the root — Tailwind Typography injects `:where(img) { margin: 2em 0 }` which silently hijacks embedded components. Applies to every widget in `lib/blockster_v2_web/components/widgets/`.

**Editing docs**: Use `Edit` for targeted changes. Do NOT use `Write` to rewrite entire doc files.

## Tech Stack

- **Backend**: Elixir/Phoenix 1.7+ LiveView, PostgreSQL + Ecto, Mnesia (distributed real-time state)
- **Frontend**: TailwindCSS, TipTap, Solana Wallet Standard
- **Blockchain**: Solana (devnet now, mainnet pending). Legacy EVM (Rogue Chain 560013) preserved on `evm-archive` branch.
- **Deployment**: Fly.io (app: `blockster-v2`)

## Key Directories

- `lib/blockster_v2/` — core business logic
- `lib/blockster_v2_web/live/` — LiveView modules
- `assets/js/` — LiveView JS hooks
- `priv/repo/migrations/` — Ecto migrations
- `contracts/blockster-bankroll/` — Anchor: dual-vault bankroll (SOL + BUX)
- `contracts/blockster-airdrop/` — Anchor: multi-round airdrop
- `contracts/blockster-settler/` — Node.js service: mint, bet settlement, pool/airdrop tx builders
- `contracts/legacy-evm/` — legacy Solidity contracts (EVM, preserved)
- `docs/` — feature/plan/runbook docs

## Branding

- **Brand Color** `#CAFC00` — accent ONLY (small dots, icon backgrounds, subtle borders). NEVER as text, button background, or random-green substitute.
- **Buttons/tabs**: `bg-gray-900 text-white` (dark) or `bg-gray-100 text-gray-900` (light).
- **Logo**: `https://ik.imagekit.io/blockster/blockster-icon.png` via `lightning_icon/1`. Full asset set: [docs/brand_assets.md](docs/brand_assets.md).
- **Icons**: Heroicons solid, pattern `w-16 h-16 bg-[#CAFC00] rounded-xl` + `w-8 h-8 text-black`.

## Running Locally

```bash
WIDGETS_ENABLED=true bin/dev   # settler + 2 Elixir nodes (full cluster) — DEFAULT, always use this
bin/dev single                 # single node, no cluster (discouraged)
bin/dev settler                # settler only
```

**ALWAYS prefix `bin/dev` with `WIDGETS_ENABLED=true`** when starting local. Widgets are off by default, but the dev workflow assumes they're on — starting without it ships a degraded UI.

| Service | Port | Purpose |
|---------|------|---------|
| Settler | 3000 | Solana minter/settler (BUX mint, bet settlement, airdrop, pool txs) |
| Node 1 | 4000 | Main Phoenix app |
| Node 2 | 4001 | Cluster peer (Mnesia replication, GlobalSingleton failover) |

**Prereqs** (first time only): `cd contracts/blockster-settler && npm install`, verify `contracts/blockster-settler/keypairs/mint-authority.json` exists, run `mix ecto.migrate`.

**Dev env**: Settler auth bypassed (`SETTLER_API_SECRET=dev-secret`), BuxMinter defaults to `http://localhost:3000`, Solana = devnet (QuickNode), libcluster auto-discovers `node1`/`node2`.

**Real-time widgets**: `WIDGETS_ENABLED=true` is the dev default (see above). One-time seed:
```bash
mix run priv/repo/seeds_widget_banners.exs
```

## Deployment

```bash
git push origin <branch> && flyctl deploy --app blockster-v2
```

## Development Guidelines

### UI/UX
- Always add `cursor-pointer` to clickable elements.
- Fonts: `font-haas_medium_65`, `font-haas_roman_55`.
- Prefer Tailwind utilities over arbitrary hex.
- Style content links: `[&_a]:text-blue-500 [&_a]:no-underline [&_a:hover]:underline`.

### LiveView Patterns

**Async API calls** — always `start_async`, extract values before the closure:
```elixir
user_id = socket.assigns.current_user.id
start_async(socket, :fetch_data, fn -> fetch_data(user_id) end)
```

**HTTP timeouts** — always configure: `Req.get(url, receive_timeout: 30_000)` or `:httpc.request(..., [{:timeout, 10_000}, {:connect_timeout, 5_000}], [])`.

**Double mount**: LiveView mounts twice. Use `connected?(socket)` for side effects.

**Never silently discard `Repo.insert`/`Repo.update`** — pattern-match and log on failure, especially when the write backs notification rows or reward records.

Detailed patterns (modal backdrop click-outside, sticky banners on animated headers, etc.): [docs/session_learnings.md](docs/session_learnings.md).

### Mnesia
- Always use dirty operations (`dirty_read`, `dirty_write`, etc.).
- Concurrent updates: route writes through a dedicated GenServer.
- Schema changes: add fields to END only, create a migration function, scale to 1 server before deploying.
- Full table reference: [docs/mnesia_tables.md](docs/mnesia_tables.md).

### GenServer Global Registration
- `BlocksterV2.GlobalSingleton` for cluster-wide singletons — handles rolling-deploy conflicts.
- **Global**: `MnesiaInitializer`, `PriceTracker`, `BuxBoosterBetSettler`, `TimeTracker`, `BotCoordinator`, `LpPriceTracker`, `CoinFlipBetSettler`.
- **Local**: `HubLogoCache` (local ETS).

### Smart Contract Upgrades (UUPS, legacy EVM)
- NEVER change order or remove state variables — only append at END.
- NEVER enable `viaIR: true` — use helper functions for stack-too-deep.
- All contracts must be **flattened** (inline OpenZeppelin) for single-file verification on RogueScan/Arbiscan. Never use `import "@openzeppelin/..."`.

## Solana Migration

All 12 phases complete. Migrated from Rogue Chain (EVM) to Solana.

- **Plan + phase details**: [docs/solana_migration_plan.md](docs/solana_migration_plan.md)
- **All addresses / PDAs / program IDs**: [docs/addresses.md](docs/addresses.md)
- **Build history**: [docs/solana_build_history.md](docs/solana_build_history.md)
- **Mainnet deployment runbook**: [docs/solana_mainnet_deployment.md](docs/solana_mainnet_deployment.md)
- **Program deploy runbook (authorities, buffer recovery, tx confirmation rules)**: [docs/solana_program_deploy.md](docs/solana_program_deploy.md)

**Key facts**:
- Bankroll + Airdrop programs live on devnet, fully initialized. Coin Flip registered as `game_id=1`.
- Upgrade authority = settler keypair (`6b4n...`). Deploy fee payer = CLI wallet (`49aN...`).
- Settler service (`contracts/blockster-settler/`) replaces the legacy `bux-minter.fly.dev` for all Solana ops.
- Multi-vault: SOL + BUX, LP tokens `bSOL` / `bBUX` (displayed as SOL-LP / BUX-LP).
- Auth: SIWS via Wallet Standard OR Web3Auth social login (email/X/Google/Apple/Telegram) — see Social Login section below.
- User model has `is_active`, `legacy_email`, `pending_email`, `merged_into_user_id` for legacy account reclaim.
- Multiplier v2: `overall = x * phone * sol * email`, capped at 200x. Stored in `unified_multipliers_v2`.

## Social Login (Web3Auth)

All 10 phases complete — see [docs/social_login_plan.md](docs/social_login_plan.md) + Appendices D + E for session narratives, [docs/web3auth_integration.md](docs/web3auth_integration.md) for technical reference.

**Key facts**:
- One feature flag gates the rollout: `SOCIAL_LOGIN_ENABLED` (master switch, default off in prod). Web3Auth users check out SOL the same way Wallet Standard users do (`payment_mode_for_user/1` returns `"wallet_sign"`; `SolPaymentHook` handles both signer sources via `signAndConfirm`).
- Sign-in modal: email input + X/Google/Apple/Telegram tile grid + existing Phantom/Solflare/Backpack wallet list. Invoke `/frontend-design:frontend-design` for any modal changes per CLAUDE.md.
- **Email flow runs through a Custom JWT, NOT Web3Auth's EMAIL_PASSWORDLESS popup**. In-app OTP (two-stage inline entry) → `Auth.EmailOtpStore` (ETS) → `Auth.Web3AuthSigning.sign_id_token` → `connectTo(AUTH, { authConnection: CUSTOM, authConnectionId: "blockster-email", extraLoginOptions: {id_token, verifierIdField: "sub"} })`. No popup, no captcha. See docs/social_login_plan.md Appendix E for the "why".
- Telegram flow: same Custom JWT infrastructure, verifier `blockster-telegram`. Widget embed wires to `POST /api/auth/telegram/verify`.
- Google/Apple/X: still use Web3Auth's OAuth popup (provider-owned, unavoidable). Those popups are quick, not captcha+code.
- **Email ownership = account ownership**: when a Web3Auth email sign-in matches an existing user by email, `Accounts.reclaim_legacy_via_web3auth/3` creates a new user with the Web3Auth-derived Solana wallet, runs `LegacyMerge.merge_legacy_into!` with `skip_reclaimable_check: true`, and merges: legacy BUX minted to new wallet via settler, username/X/Telegram/phone/content/referrals/fingerprints transferred, old row deactivated. Returning users skip onboarding. This replaces legacy wallet_address wholesale.
- `wallet_address` is ALWAYS the primary wallet. For a Web3Auth sign-in that subsumes an existing user, this means the Web3Auth-derived Solana pubkey REPLACES whatever was there (EVM EOA or old Phantom wallet).
- `smart_wallet_address` is legacy EVM ERC-4337 only. NULL for all Web3Auth users and new Solana users.
- **Signing pattern for Web3Auth**: `provider.request({method: "solana_privateKey"})` on every call → `Keypair.fromSecretKey` → sign → `secretKey.fill(0)` in `finally`. NEVER cache the key. See `assets/js/hooks/web3auth_hook.js`.
- **Web3Auth chain IDs are ws-embed-specific**: `0x65` mainnet, `0x66` testnet, `0x67` devnet. NOT the `0x1/0x2/0x3` from the public docs.
- Web3Auth methods are `solana_*` prefixed (`solana_requestAccounts`, `solana_signMessage`, etc.). Bare names fail.
- Buffer/process polyfills (`assets/js/polyfills.js`) MUST be the first import in `app.js`. Web3Auth's transitive deps reference Node globals directly.
- Onboarding: single "Get started" CTA. The old "I have an existing account" branch + `migrate_email` step were retired — legacy reclaim now happens server-side during Web3Auth email sign-in, not as an onboarding step.

## Coin Flip (Solana)

- Route: `/play` → `CoinFlipLive`.
- Game logic: `lib/blockster_v2/coin_flip_game.ex`. Settler: `coin_flip_bet_settler.ex` (GlobalSingleton, minute loop).
- JS hook: `assets/js/coin_flip_solana.js` (Wallet Standard, optimistic flow).
- Payout/max-bet math: MUST use `trunc`/`div` (not `Float.round`) to match on-chain integer truncation.
- Nonce managed from Mnesia for instant init; on-chain fallback only on `NonceMismatch`.
- Settlement is fire-and-forget (`spawn`) — next bet does not wait for previous settlement.
- Reclaim expired bets: 30s banner on `/play` checks for placed bets older than 5 min; user signs `reclaim_expired`.
- Old EVM game preserved (`bux_booster_onchain.ex`, `BuxBoosterLive`) but unrouted.

## Pool / LP System

- Routes: `/pool` (`PoolIndexLive`), `/pool/sol`, `/pool/bux` (`PoolDetailLive`).
- Pool JS hook: `assets/js/hooks/pool_hook.js` (deposit/withdraw signing).
- LP prices: `LpPriceTracker` (GlobalSingleton, 60s poll) + `LpPriceHistory` (Mnesia, per-timeframe downsampling). Real-time chart updates via PubSub on `{:bet_settled, vault_type}`.
- Cost basis / P/L: `BlocksterV2.PoolPositions` + Mnesia `:user_pool_positions` (ACB accounting). Updated on every confirmed deposit/withdraw; pre-existing holders seeded with `cost = lp × current_lp_price` on first render.

## Shop / Checkout (SOL-direct)

- Routes: `/shop` (`ShopLive.Index`), `/shop/:slug` (`ShopLive.Show`), `/cart` (`CartLive.Index`), `/checkout/:order_id` (`CheckoutLive.Index`).
- **SOL-FIRST RULE (applies everywhere money moves — shop pages, cart, checkout, order-confirmation emails, receipts, admin views):** Prices stored in USD; always display SOL primary + USD secondary. Use `BlocksterV2Web.ShopComponents.sol_usd_dual` for line items and totals, `BlocksterV2Web.ShopComponents.product_price_block` for product-card prices. Direct formatters: `BlocksterV2.Shop.Pricing.format_sol_precise/1` (4 decimals for payment surfaces) + `format_usd/1`. Rate from `PriceTracker.get_price("SOL")` live, or `payment_intent.quoted_sol_usd_rate` when viewing a past order (lock the rate so rate drift doesn't misrepresent what was paid). **Do not show USD-only numbers in any user-facing shop surface.**
- Payment flow (Phase 5b): buyer pays remaining `subtotal + shipping − bux_discount` as a single SOL transfer from their connected wallet to a **unique ephemeral address per order**. No Helio, no Stripe, no external processor.
  - Settler HKDF-derives the ephemeral keypair from `(PAYMENT_INTENT_SEED, order_id)` — stateless, no per-order key storage. Rotating the seed invalidates every unswept intent.
  - `order_payment_intents` table holds pubkey + `expected_lamports` + status (`pending → funded → swept | expired | failed`) + 15-min `expires_at`.
  - `PaymentIntentWatcher` (GlobalSingleton, 10s tick) polls settler `GET /intents/:pubkey` → on funded flips order → `paid`, broadcasts `{:order_updated, order}` on `order:<id>` → watcher sweeps next tick to `SOL_TREASURY_ADDRESS` (fee paid by `MINT_AUTHORITY`).
  - Checkout JS hook: `assets/js/hooks/sol_payment.js` — builds `SystemProgram.transfer`, signs via Wallet Standard `signAndSendTransaction`.
- BUX discount: still optional, burns on-chain via `SolanaBuxBurn` JS hook (`assets/js/hooks/solana_bux_burn.js`) before the SOL payment step. Hand-rolls an SPL `BurnChecked` instruction client-side, signs via `window.__signer` + `signAndConfirm` (polls `getSignatureStatuses`). Works for both Wallet Standard and Web3Auth. The old `BuxPaymentHook` (EVM/Thirdweb) at `assets/js/hooks/bux_payment.js` is a dead stub — don't revive.
- Per-product `bux_max_discount` cap (0/nil = uncapped = 100% discount allowed — known footgun, set explicit caps per product or change the fallback in `shop_live/show.ex`).
- Settler env vars (required for prod): `PAYMENT_INTENT_SEED`, `SOL_TREASURY_ADDRESS`. Dev defaults exist. Full deploy runbook: [`docs/solana_mainnet_deployment.md`](docs/solana_mainnet_deployment.md) Step 5.

## Ad Banners

- System: `lib/blockster_v2/ads.ex`, schema `ads/banner.ex`, components in `design_system.ex` via `<.ad_banner banner={banner} />`.
- Templates: `follow_bar`, `dark_gradient`, `portrait`, `split_card`, `image` (legacy).
- Placements: `sidebar`, `mobile`, `homepage_inline`, `article_inline_1/2/3`.
- `sort_order` controls display sequence; `sanitize_ad_params` strips empty strings to `nil`.
- All ad links open `target="_blank" rel="noopener"`.
- Admin: `/admin/banners`. Reference: [docs/ad_banners_system.md](docs/ad_banners_system.md), [docs/luxury_ad_templates.md](docs/luxury_ad_templates.md).

## Bot Reader System

1000 bot accounts simulate reading with real on-chain BUX minting. Feature flag: `BOT_SYSTEM_ENABLED=true`. Auto-rotates legacy EVM wallets to Solana keypairs on boot (idempotent). Bot mints use `wallet_address`. Full docs: [docs/bot_reader_system.md](docs/bot_reader_system.md).

## Security

- **Provably-fair server seed**: NEVER display for unsettled games — verify `status == :settled` first.
- **Fingerprint anti-sybil**: non-blocking (signup proceeds if FingerprintJS fails). Dev/test skips the HTTP call; `SKIP_FINGERPRINT_CHECK` env var skips server verification but fingerprint DB ops still run when data is present.

## Engagement Tracking

`bux = (engagement_score / 10) * base_reward * multiplier`. Time score 0-6, depth score 0-3, base 1. Bot detection: <3 scroll events, >5000 px/s scroll, >300 wpm reading.

## Services & Routes

| Service | URL | Role |
|---------|-----|------|
| Main App | `https://blockster.com` | Phoenix LiveView |
| Settler (Solana) | `https://blockster-settler.fly.dev` (prod deploy pending) | BUX mint, bet settlement, airdrop txs, shop payment intents |
| Legacy BUX Minter (EVM) | `https://bux-minter.fly.dev` | Scheduled for shutdown post-migration; settler replaced it |

**Telegram**: [Group](https://t.me/+7bIzOyrYBEc3OTdh), [Bot](https://t.me/BlocksterV2Bot). `t.me/blockster` is NOT ours — never use it.

**Common routes**: `/hub/:slug`, `/shop/:slug`, `/:slug` (post), `/member/:slug`, `/play`, `/pool`, `/pool/sol`, `/pool/bux`, `/admin/stats`, `/admin/stats/players`, `/admin/stats/players/:address`.

## Admin Operations

SSH snippets (query user by wallet, mint BUX, clear phone verification, etc.): [docs/admin_operations.md](docs/admin_operations.md).

## Performance

- Route images through ImageKit (`w500_h500`, `w800_h800`, etc.).
- Above-fold: `fetchpriority="high" loading="eager"`. Below-fold: `loading="lazy"`.
- Swiper bundled via npm, not CDN.
- Preconnect: `ik.imagekit.io`, `fonts.googleapis.com`, `fonts.gstatic.com`.

---

*Historical bug-fix narratives and contract upgrade tx hashes: [docs/session_learnings.md](docs/session_learnings.md).*
