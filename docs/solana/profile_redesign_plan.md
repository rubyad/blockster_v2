# Profile · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/member_live/show.ex` |
| Template | `lib/blockster_v2_web/live/member_live/show.html.heex` |
| Route(s) | `/member/:slug` (moved from `:default` to `:redesign` live_session) |
| Mock file | `docs/solana/profile_mock.html` |
| Bucket | **A** — pure visual refresh |
| Wave | 2 |

**Note**: `/profile` is a GET controller route (`PageController.profile_redirect`) that redirects to `/member/:slug?tab=settings`. It stays as-is — only the LiveView route moves.

## Mock structure (top to bottom)

| # | Section | Description | Status |
|---|---|---|---|
| 1 | **Profile hero** | 12-col grid: identity left (96px avatar + eyebrow "Your profile" + Active badge + 44-52px name + @slug + profile URL + wallet address + copy + Solscan link + member since), quick actions right (Edit profile dark btn, Settings outline btn, Logout icon btn, verification status pills: X/Phone/SOL/Email) | REAL |
| 2 | **Three stat cards** | BUX Balance (lime icon, value + "≈ $X redeemable", footer "Today + N BUX"), BUX Multiplier (dark icon with lime bolt, Nx value, footer "Verify email + Nx boost"), SOL Balance (Solana gradient icon, value, footer "SOL multiplier Nx") | REAL |
| 3 | **Email verification banner** | Conditional: amber gradient card with verify-ring icon, "One thing left" eyebrow, CTA "Verify email →", copy about 2× multiplier boost | REAL (conditional on email_verified) |
| 4 | **Multiplier breakdown** | White card with header (eyebrow + section-title + total pill), 4-col grid (X / Phone / SOL / Email multipliers with progress bars), formula footer | REAL |
| 5 | **Sticky tab nav** | 5 tabs: Activity (count) / Following (count) / Refer (count) / Rewards (count) / Settings. Lime active underline. Frosted glass bg at top:84px | REAL |
| 6 | **Activity tab** | Period filter chips (24H/7D/30D/ALL) + total earned headline, activity table with rows: date, activity icon+description+hub badge, reward amount + tx link. "Load more" footer | REAL |
| 7 | **Following tab** | Eyebrow "Hubs you follow · N of total", title, "Browse all hubs" dark CTA, 4-col hub cards grid with unfollow X buttons + "N new posts" + BUX earned badge + "Discover more" dashed card at end | REAL |
| 8 | **Refer tab** | Referral link card (copyable URL, earn description, 2×2 stats: Total/Verified/BUX/SOL), referral earnings table (Type badge / From avatar+name / Amount / Time / TX) with infinite scroll | REAL |
| 9 | **Rewards tab** | NEW tab: lifetime total card (64px value + 12-month sparkline bars) left, source breakdown card (Reading/X shares/Referrals/Verification bonuses/Coin Flip wins with progress bars) right, pending claims banner | STUB (data partially available) |
| 10 | **Settings tab** | 12-col: Account details card 7-col (Username editable / Profile URL / Wallet + Solscan / Email with verify status / Auth method / Member since), Connected accounts 5-col (X / Telegram / Phone) + Danger zone card (Export / Disconnect / Deactivate) | REAL (except Export and Deactivate are STUB) |

## Visual components consumed

- `<DesignSystem.header />` ✓ existing (Wave 0)
- `<DesignSystem.footer />` ✓ existing (Wave 0)
- `<DesignSystem.eyebrow />` ✓ existing (Wave 0)
- `<DesignSystem.chip />` ✓ existing (Wave 0)
- `<DesignSystem.profile_avatar />` ✓ existing (Wave 0)
- `<DesignSystem.author_avatar />` ✓ existing (Wave 0) — used for referral earnings "From" column
- `<DesignSystem.stat_card />` ✓ existing (Wave 0) — used for 3 hero stat cards
- `<DesignSystem.hub_card />` ✓ existing (Wave 1) — **not used** for Following tab (those cards have unfollow buttons + different layout)
- No other new design_system components needed — remaining sections (multiplier breakdown, activity table, referral table, rewards breakdown, settings, following hub cards) are all **page-specific** since they're only used on this page.

## Data dependencies

### ✓ Existing — already in production, no work needed

**Profile identity:**
- `@member` — `Accounts.get_user_by_slug_or_address(slug)` (name, slug, wallet_address, inserted_at)
- `@current_user` — from UserAuth on_mount
- `@is_own_profile` — `current_user.id == member.id`
- `@is_new_user` — account age < 5 minutes

**Stat cards:**
- `@token_balances` — from `EngagementTracker.get_user_token_balances/1` (BUX balance)
- `@overall_multiplier`, `@x_multiplier`, `@phone_multiplier`, `@sol_multiplier`, `@email_multiplier` — from `UnifiedMultiplier.get_user_multipliers/1`
- SOL balance — from `EngagementTracker.get_user_sol_balance/1`

**Multiplier breakdown:**
- `@unified_multipliers` — `UnifiedMultiplier.get_user_multipliers/1`
- `@x_score`, `@x_connection` — from `Social.get_x_connection_for_user/1`
- `@member.phone_verified`, `@member.email_verified`

**Activity tab:**
- `@activities`, `@all_activities` — from `load_member_activities/1` (Mnesia reads + X shares + notifications)
- `@total_bux` — sum of filtered activities
- `@time_period` — filter state ("24h"/"7d"/"30d"/"all")

**Following tab:**
- `@followed_hubs` — `Blog.get_user_followed_hubs_enriched/1`

**Refer tab:**
- `@referral_link` — generated from wallet_address
- `@referral_stats` — `Referrals.get_referrer_stats/1`
- `@referrals` — `Referrals.list_referrals/2`
- `@referral_earnings` — `Referrals.list_referral_earnings/3`

**Settings tab:**
- `@x_connection` — `Social.get_x_connection_for_user/1`
- `@telegram_connected`, `@telegram_username` — from user record
- `@editing_username`, `@username_form` — edit state
- `@connected_wallet` — `Wallets.get_connected_wallet/1`
- `@wallet_balances` — `Wallets.get_user_balances/1`
- `@recent_transfers` — `Wallets.list_user_transfers/1`

**Verification modals:**
- `@show_phone_modal`, `@show_email_modal` — modal visibility flags

**PubSub:**
- `"referral:#{member.id}"` — real-time referral earnings

### ⚠ Stubbed in v1

- **Rewards tab — Coin Flip wins total**: requires aggregating from `coin_flip_games` Mnesia table. For v1, show "—" or 0 if no aggregation function exists. Will be computed from Mnesia in a follow-up.
- **Rewards tab — 12-month sparkline**: requires monthly BUX aggregation. For v1, render empty/placeholder bars. Real data in a follow-up.
- **Rewards tab — Pending claims**: the existing code processes pending anonymous claims but doesn't track "pending settlement" status. For v1, hide this section. Show when a settlement tracking system exists.
- **Settings — Export account data**: inert button, no backend. Shows a flash "Coming soon" on click.
- **Settings — Deactivate account**: inert button, no backend. Shows a flash "Coming soon" on click.
- **Activity tab — Hub follow activity row**: the mock shows "Followed Moonpay Hub" rows. The existing activity loader doesn't include follow events. For v1, these won't appear (no data source). Add when activity tracking for follows is built.

### ✗ New — must be added for this page to ship

- **New tab: "rewards"** — add to `switch_tab` handler's accepted values. Compute reward breakdown from existing activity data.
- **Verification status badges in hero** — compute from `@member.email_verified`, `@member.phone_verified`, `@x_connection`, SOL balance > 0. These are all existing assigns, just displayed differently.

## Handlers to preserve

All existing handlers from `MemberLive.Show`:

**Tab management:**
- `handle_event("switch_tab", %{"tab" => tab}, ...)` — add "rewards" to accepted values
- `handle_event("switch_tab_select", ...)` — mobile dropdown

**Multiplier dropdown:**
- `handle_event("toggle_multiplier_dropdown", ...)` — **removed from new design** (multiplier breakdown is now always-visible card, not a dropdown). Handler kept for backwards compat but may be dead code.
- `handle_event("close_multiplier_dropdown", ...)` — same

**Hub management:**
- `handle_event("unfollow_hub", %{"hub-id" => id}, ...)` — Following tab

**Username editing:**
- `handle_event("edit_username", ...)` — Settings tab
- `handle_event("cancel_edit_username", ...)` — Settings tab
- `handle_event("update_username_form", ...)` — Settings tab typing
- `handle_event("save_username", ...)` — Settings tab submit

**Telegram:**
- `handle_event("connect_telegram", ...)` — Settings tab, redirects to bot

**Verification modals:**
- `handle_event("open_phone_verification", ...)` — opens phone modal
- `handle_event("open_email_verification", ...)` — opens email modal

**Wallet connection (Settings tab — legacy hardware wallet):**
- `handle_event("connect_" <> provider, ...)` — metamask/coinbase/walletconnect/phantom
- `handle_event("wallet_connected", ...)` — saves wallet
- `handle_event("wallet_connection_error", ...)` — flash error
- `handle_event("disconnect_wallet", ...)` — removes wallet
- `handle_event("wallet_disconnected", ...)` — confirmation
- `handle_event("wallet_reconnected", ...)` — auto-reconnect
- `handle_event("wallet_reconnect_failed", ...)` — silent fail
- `handle_event("wallet_address_mismatch", ...)` — detects address change

**Wallet balances:**
- `handle_event("copy_address", ...)` — flash
- `handle_event("refresh_balances", ...)` — triggers JS balance fetch
- `handle_event("hardware_wallet_balances_fetched", ...)` — stores in Mnesia
- `handle_event("balance_fetch_error", ...)` — flash

**Transfers:**
- `handle_event("initiate_transfer_to_blockster", ...)` — validates + pushes to JS
- `handle_event("initiate_transfer_from_blockster", ...)` — validates + pushes to JS
- `handle_event("transfer_submitted", ...)` — creates record
- `handle_event("transfer_confirmed", ...)` — confirms + refreshes
- `handle_event("transfer_error", ...)` — logs + flash

**Activity time period:**
- `handle_event("set_time_period", %{"period" => period}, ...)` — filters activities

**Referral:**
- `handle_event("copy_referral_link", ...)` — pushes copy_to_clipboard
- `handle_event("load_more_earnings", ...)` — paginated infinite scroll

**PubSub handle_info:**
- `{:referral_earning, earning}` — real-time referral earnings
- `{:close_phone_verification_modal}` — from modal component
- `{:close_email_verification_modal}` — from modal component
- `{:refresh_user_data}` — reloads member + multipliers
- `{:redirect_to_home}` — navigation push
- `{:countdown_tick, seconds}` — countdown timer
- `:refresh_hardware_balances` — pushes balance refresh to JS
- `:refresh_blockster_balance` — syncs Solana balances

**JS hooks used:**
- `CopyToClipboard` — wallet address, referral link, profile URL
- `ClaimCleanup` — auto-hide new user claim banner
- `InfiniteScroll` — referral earnings table

**Live components:**
- `PhoneVerificationModalComponent` — phone verification modal
- `EmailVerificationModalComponent` — email verification modal

## Tests required

### Component tests

No new design_system components — no new component test files needed.

### LiveView tests

- `test/blockster_v2_web/live/member_live/show_test.exs` — **NEW** file (no existing test)
  - Page renders for logged-in user (own profile)
  - Anonymous user redirected (security check)
  - Profile hero renders: name, slug, wallet address
  - Three stat cards render (BUX balance, multiplier, SOL balance)
  - Multiplier breakdown card renders with 4 multiplier columns
  - Tab navigation renders 5 tabs (Activity/Following/Refer/Rewards/Settings)
  - Activity tab: renders activity table, period filter chips
  - Following tab: renders followed hub cards, "Browse all hubs" link
  - Refer tab: renders referral link, stats grid
  - Settings tab: renders account details, connected accounts
  - Switching tabs works (switch_tab event)
  - Design system header and footer present
  - Verification banner renders when email unverified
  - Verification banner hidden when email verified

### Manual checks

- Page renders logged in
- Page renders anonymous (redirects to home)
- Profile hero shows correct user data
- Stat cards show BUX, multiplier, SOL
- Multiplier breakdown shows correct values
- Verification banner conditional display
- Tab switching works (all 5 tabs)
- Activity table renders with time period filter
- Following tab shows hub cards with unfollow
- Refer tab copy link works
- Settings tab edit username works
- `mix test` zero new failures vs baseline

## Per-page commit message

`redesign(profile): identity hero + stat cards + multiplier breakdown + 5-tab nav + rewards tab`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|
| Rewards tab sparkline | Empty/static bars | Real monthly BUX aggregation | Analytics release |
| Rewards tab Coin Flip wins | 0 or — | Real aggregation from coin_flip_games Mnesia | Analytics release |
| Rewards tab pending claims | Hidden | Real settlement tracking | Settlement tracking release |
| Settings — Export account data | Flash "Coming soon" on click | Real data export | Account management release |
| Settings — Deactivate account | Flash "Coming soon" on click | Real deactivation flow | Account management release |

## Open items

None — all resolved during build.

## User feedback applied (same session)

- All inactive/unverified multiplier boxes get amber bg + greyed number + muted bar (not just email)
- BUX Multiplier stat card: literal `×` character (not `&times;` entity)
- Multiplier base values corrected: X=1×, Phone=0.5×, Email=0.5×
- BUX Balance footer: removed "redeemable" dollar value, replaced with "Use BUX to enter airdrops & play games"
- SOL Balance icon: proper `solana-sol-logo.png` from ImageKit on black bg (same as coin flip page)
- Removed Edit Profile and Settings pill buttons from hero quick actions (kept logout only)
- X/Phone/Email hero pills: clickable when inactive (X links to `/auth/x`, Phone opens phone verify modal, Email opens email verify modal)
- Email added to Connected Accounts panel in Settings tab (between Telegram and Phone)
- Removed dollar redeemable text from Rewards tab lifetime total
- Refer tab: simplified earning description to "0.2% of every losing bet they place — forever"
- Formula footer: all four terms grey out independently based on their active state
- When overall multiplier is 0 (no SOL): footer shows "Deposit at least 0.1 SOL into your connected wallet to start earning BUX"
