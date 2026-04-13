# Notifications · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView modules | `lib/blockster_v2_web/live/notification_live/index.ex` |
| | `lib/blockster_v2_web/live/notification_live/referrals.ex` |
| | `lib/blockster_v2_web/live/notification_settings_live/index.ex` |
| Route(s) | `/notifications`, `/notifications/settings`, `/notifications/referrals` |
| Mock file | **None** — design from DS spec per decision D11 |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 6 (Page #18 — first page of Wave 6 Internal Flows) |

## Page structure (top to bottom)

### Page 1: `/notifications` — Notification Index

1. **DS header** — `<BlocksterV2Web.DesignSystem.header />` with all standard attrs
2. **Page hero** — compact hero (matches tag page pattern):
   - Eyebrow: "Notifications" (uses `<.eyebrow>`)
   - Title h1: "Notifications" (article-title size)
   - Action buttons row: Mark all read, Referrals link, Settings link
3. **Filter row** — border-t divider with filter chips:
   - Chips: All (active) / Unread / Read (uses `<.chip>`)
   - Right side: unread count label (font-mono)
4. **Notification list** — vertical stack with InfiniteScroll:
   - Each item: white rounded-2xl card with category icon, unread accent bar,
     title, body (line-clamp-2), time, action label, mark-read button
   - Unread: solid white bg + shadow, lime left accent bar, lime dot
   - Read: bg-white/50, muted text
5. **Empty state** — centered icon + copy ("All caught up")
6. **DS footer** — `<BlocksterV2Web.DesignSystem.footer />`

### Page 2: `/notifications/referrals` — Referral Dashboard

1. **DS header**
2. **Page hero** — compact hero:
   - Eyebrow: "Referrals"
   - Title h1: "Referral Dashboard"
   - Subtitle: "Track your referrals and earnings"
   - Back link to `/notifications`
3. **Referral link card** — white rounded-2xl:
   - Input with referral URL + Copy button (CopyToClipboard hook)
   - Social share buttons: X, WhatsApp, Telegram, Email
   - Bonus text about bet commissions
4. **Stats grid** — 4-col on desktop, 2-col on mobile:
   - Referrals, Verified, BUX Earned, ROGUE Earned
   - Each: stat_card style with color dot + eyebrow label
5. **How referral rewards work** — 3-step horizontal cards
6. **Earnings table** — white rounded-2xl with sticky header:
   - Columns: Type (colored badge), From (truncated wallet), Amount, Time, TX (Solscan link)
   - Recent earnings highlighted (lime bg)
   - InfiniteScroll for pagination
   - Empty state with illustration
7. **DS footer**

### Page 3: `/notifications/settings` — Notification Settings

1. **DS header**
2. **Page hero** — compact hero:
   - Eyebrow: "Settings"
   - Title h1: "Notification Settings"
   - Back link to `/notifications`
   - "Saved" indicator (animated)
3. **Settings sections** — each a white rounded-2xl card:
   - **Email Notifications**: master toggle
   - **In-App Notifications**: master toggle
   - **Telegram**: connect account flow, group join, disconnect with confirmation
   - **Hub Notifications**: per-hub toggles (only if followed hubs exist)
4. **Unsubscribe section** — muted card with red confirmation flow
5. **DS footer**

## Decisions applied from release plan

- **Bucket A**: no schema changes, no new contexts, no new on-chain calls.
- **Route moves**: All 3 notification routes move from `:default` to `:redesign` live_session.
- **Legacy preservation**: copy current files to:
  - `lib/blockster_v2_web/live/notification_live/legacy/index_pre_redesign.ex`
  - `lib/blockster_v2_web/live/notification_live/legacy/referrals_pre_redesign.ex`
  - `lib/blockster_v2_web/live/notification_settings_live/legacy/index_pre_redesign.ex`
- **No new DS components needed** — all sections use existing DS components
  (`header`, `footer`, `eyebrow`, `chip`) plus inline Tailwind for notification
  cards, settings toggles, referral cards, and stats.
- **No new schema migrations.**
- **All handlers preserved exactly** — every `handle_event` and `handle_info`
  callback stays, no behavior changes.
- **JS hooks preserved**: `InfiniteScroll` (notifications list + earnings table),
  `CopyToClipboard` (referral link), `SolanaWallet` (DS header).

## Visual components consumed

- `<BlocksterV2Web.DesignSystem.header />` ✓ existing (active="home")
- `<BlocksterV2Web.DesignSystem.footer />` ✓ existing
- `<BlocksterV2Web.DesignSystem.eyebrow />` ✓ existing
- `<BlocksterV2Web.DesignSystem.chip />` ✓ existing

**No new DS components needed.**

## Data dependencies

### ✓ Existing — already in production (NotificationLive.Index)

- `@notifications` (list) — from `Notifications.list_notifications/2`
- `@active_filter` (string) — "all" / "unread" / "read"
- `@offset` (integer) — pagination offset
- `@end_reached` (boolean) — no more pages
- `@current_user` — from UserAuth on_mount
- `@page_title` (string) — "Notifications"

### ✓ Existing — already in production (NotificationLive.Referrals)

- `@stats` (map) — total_referrals, verified_referrals, total_bux_earned, total_rogue_earned
- `@earnings` (list) — referral earnings with pagination
- `@config` (map) — referrer_signup_bux, referee_signup_bux, phone_verify_bux
- `@referral_link` (string) — referral URL
- `@offset`, `@end_reached` — pagination

### ✓ Existing — already in production (NotificationSettingsLive.Index)

- `@preferences` (struct) — NotificationPreference
- `@followed_hubs` (list) — hubs with notification settings
- `@show_unsubscribe_confirm` (boolean)
- `@telegram_connected`, `@telegram_username`, `@telegram_group_joined`
- `@telegram_bot_url`, `@telegram_polling`, `@show_telegram_disconnect`
- `@saved` (boolean) — flash-style saved indicator

### ⚠ New assigns — additions for design fidelity

- **`@unread_count`** (integer) on NotificationLive.Index — computed from
  `Notifications.unread_count/1` in mount, displayed next to filter chips.
  Already available via `NotificationHook` but reading it separately avoids
  coupling the page to the hook's assign timing.

### ✗ Removed assigns

None. All existing assigns preserved.

### ✗ New — must be added or schema-migrated

None. Bucket A.

## Handlers to preserve

### NotificationLive.Index

**`handle_event`:**
- `"filter_status"` — switches active filter. **Preserved.**
- `"mark_read"` — marks single notification read + broadcasts count. **Preserved.**
- `"click_notification"` — marks clicked, navigates to action_url. **Preserved.**
- `"mark_all_read"` — batch mark all as read. **Preserved.**
- `"load-more-notifications"` — InfiniteScroll pagination. **Preserved.**

### NotificationLive.Referrals

**`handle_event`:**
- `"load_more_earnings"` — InfiniteScroll pagination. **Preserved.**

**`handle_info`:**
- `{:referral_earning, earning_data}` — real-time PubSub earning. **Preserved.**
- Catch-all `_` — **Preserved.**

**PubSub subscriptions:**
- `"referral:#{user.id}"` — subscribed in `mount/3` under `connected?(socket)`. **Preserved.**

### NotificationSettingsLive.Index

**`handle_event`:**
- `"toggle_preference"` — toggles email/in-app/SMS preference. **Preserved.**
- `"toggle_hub_notification"` — per-hub notification toggle. **Preserved.**
- `"connect_telegram"` — generates token, opens bot URL. **Preserved.**
- `"show_telegram_disconnect"` / `"cancel_telegram_disconnect"` / `"confirm_telegram_disconnect"` — disconnect flow. **Preserved.**
- `"show_unsubscribe_confirm"` / `"cancel_unsubscribe"` / `"confirm_unsubscribe_all"` — unsubscribe flow. **Preserved.**

**`handle_info`:**
- `:clear_saved` — dismisses saved indicator after 2s. **Preserved.**
- `:check_telegram_connected` — polls DB every 3s for Telegram connection. **Preserved.**

## JS hooks

- **`InfiniteScroll`** — on `#notifications-list` and `#referral-earnings-list`. **Preserved.**
- **`CopyToClipboard`** — on referral link copy button. **Preserved.**
- **`SolanaWallet`** — on DS header (`#ds-site-header`). Auto-injected. **No changes.**
- **`NotificationToastHook`** — on toast in layout (NOT in these pages). **No changes.**

No new JS hooks.

## Tests required

### Component tests

None — no new DS components.

### LiveView tests

**Create** `test/blockster_v2_web/live/notification_live/index_test.exs`.

**Assertions (NotificationLive.Index):**

- **Page renders with DS header**: assert `ds-site-header` element present
- **Page renders with DS footer**: assert "Where the chain meets the model"
- **Page hero renders**: assert "Notifications" eyebrow + h1
- **Filter chips render**: assert "All", "Unread", "Read" chip text
- **Empty state renders when no notifications**: assert "All caught up"
- **Notification items render**: seed notifications, assert titles appear
- **Unread indicator visible**: seed unread notification, assert lime accent
- **Mark all read button visible**: seed unread, assert "Mark all read"
- **Settings link present**: assert link to `/notifications/settings`
- **Referrals link present**: assert link to `/notifications/referrals`
- **Anonymous access works**: page renders without current_user
- **Logged-in access works**: page renders with current_user + notifications
- **Filter switches work**: click "Unread" chip, verify filter changes

**Assertions (NotificationLive.Referrals):**

- **Page renders with DS header/footer**
- **Referral link renders**: assert referral URL present
- **Copy button present**: assert CopyToClipboard hook
- **Stats cards render**: assert "Referrals", "Verified", "BUX Earned"
- **How it works section renders**: assert "How Referral Rewards Work"
- **Earnings table renders**: assert table headers
- **Empty state for no earnings**: assert "No earnings yet"
- **Anonymous access**: renders login prompt

**Assertions (NotificationSettingsLive.Index):**

- **Page renders with DS header/footer**
- **Settings sections render**: assert "Email Notifications", "In-App Notifications", "Telegram"
- **Toggle switches present**: assert switch elements
- **Back link to notifications**: assert link to `/notifications`
- **Unsubscribe section present**: assert "Unsubscribe all"
- **Anonymous access**: renders login prompt

### Manual checks (on `bin/dev`)

- All 3 pages render at their routes logged in and anonymous
- DS header + footer visible on all pages
- Notification list with read/unread styling
- Filter chips switch between All/Unread/Read
- Mark all read works
- Click notification navigates
- Referral link copy works
- Share buttons have correct URLs
- Settings toggles work
- Telegram connect/disconnect flow
- Hub notification toggles
- Unsubscribe confirmation flow
- Infinite scroll on notifications + earnings
- No console errors
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(notifications): notifications hub refresh · DS header/footer + notification list + referral dashboard + settings`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Release |
|---|---|---|---|
| Notification categories | Uses existing 5 categories (content/offers/social/rewards/system) | Add more granular categories | Follow-up |
| ROGUE Earned stat | Shows ROGUE earned in referrals (legacy) | Remove or replace with SOL | Post-migration cleanup |
| Filter chip behavior | Chips work for all/unread/read only | Add category-based filtering | Follow-up commit |

## Open items

None. All existing functionality maps directly to the redesigned template.
