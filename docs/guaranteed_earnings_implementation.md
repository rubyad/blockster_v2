# Guaranteed Earnings Implementation Plan

## Status: ✅ IMPLEMENTED (Jan 22, 2026)

**Branch:** `feature/guaranteed-earnings`

---

## Overview

This document describes the implementation changes needed to guarantee users receive their full earned rewards once they start an earning action, even if the pool depletes during their session.

## Core Principle

**Once a user starts an earning action with a positive pool, they are guaranteed the full reward regardless of pool balance changes during their session.**

---

## Rules

### 1. Starting Conditions
- Earning tracking ONLY starts when `pool_balance > 0`
- This applies to: video watch tracking, article read tracking, X share/like rewards
- **Users can still access content when pool is empty** - they just won't earn

### 2. In-Progress Guarantees
- Once tracking started (pool was positive), user receives FULL calculated reward
- No partial payments
- No zero payments for completed tracked actions
- Pool can go negative to honor these commitments

### 3. UI Display Rules
- Always show `max(0, pool_balance)` to users
- Show "Pool empty" indicator when `pool_balance <= 0`
- Never display negative values to users

### 4. Empty Pool Behavior
- **Video**: User CAN open modal and watch video, but sees "Pool empty" and no BUX tracking
- **Article**: User CAN read article, but engagement panel shows "Pool empty" and no BUX tracking
- **X Share**: User CAN share, but no BUX reward (share still counts for engagement)
- Existing in-progress tracked sessions continue unaffected

---

## Risk Analysis

### Worst Case Scenario

10 users start watching a 10-minute video (1 BUX/min) when pool has 5 BUX:

| Metric | Value |
|--------|-------|
| Pool before | 5 BUX |
| Users | 10 |
| Earnings per user | 10 BUX |
| Total payout | 100 BUX |
| Pool after | -95 BUX |
| Displayed balance | 0 BUX |

### Why This Is Acceptable

1. Users received what the UI promised
2. No one feels cheated by a bait-and-switch
3. Overspend is bounded by: `concurrent_sessions × max_earning_per_session`
4. Post author funded the pool expecting rewards to be distributed
5. Negative balance just means pool was popular - a good problem

---

## Implementation Summary

### Files Modified

| File | Changes |
|------|---------|
| `lib/blockster_v2/post_bux_pool_writer.ex` | Added `deduct_guaranteed/2` function that allows negative balances |
| `lib/blockster_v2/engagement_tracker.ex` | Added `get_post_bux_balance_display/1`, `pool_available?/1`, `deduct_from_pool_guaranteed/2` |
| `lib/blockster_v2_web/live/post_live/show.ex` | Removed pool checks at reward completion, added display helpers, updated all assigns |

### Files Unchanged (Already Correct)

| File | Reason |
|------|--------|
| `lib/blockster_v2_web/live/post_live/show.html.heex` | Already uses `@pool_available` for empty state display |
| `assets/js/video_watch_tracker.js` | Already checks `poolAvailable` at mount (correct behavior) |
| `assets/js/engagement_tracker.js` | Already checks `poolAvailable` at mount (correct behavior) |
| Database/Mnesia | Existing schema supports negative values |

---

## Key Code Changes

### 1. PostBuxPoolWriter - New Guaranteed Deduction

```elixir
# lib/blockster_v2/post_bux_pool_writer.ex

@doc """
Deducts BUX from post's pool with GUARANTEED payout (pool can go negative).
Used for guaranteed earnings - once a user starts an earning action with a positive pool,
they are guaranteed the full reward regardless of pool balance changes during their session.

Returns {:ok, new_balance} where new_balance can be negative.
"""
def deduct_guaranteed(post_id, amount) when is_number(amount) and amount > 0 do
  GenServer.call({:global, __MODULE__}, {:deduct_guaranteed, post_id, amount}, 10_000)
end
```

The implementation:
- Always deducts the full amount (no partial)
- Pool balance can go negative
- Broadcasts display value `max(0, new_balance)` to PubSub
- Logs the actual balance and display balance for debugging

### 2. EngagementTracker - Helper Functions

```elixir
# lib/blockster_v2/engagement_tracker.ex

@doc """
Gets pool balance for display purposes (always >= 0).
Never shows negative values to users.
"""
def get_post_bux_balance_display(post_id) do
  max(0, get_post_bux_balance(post_id))
end

@doc """
Checks if pool is available for NEW earning actions.
Returns true only if balance > 0.
"""
def pool_available?(post_id) do
  get_post_bux_balance(post_id) > 0
end

@doc """
Deducts amount from post's BUX pool with GUARANTEED payout.
Pool CAN go negative to honor guaranteed earnings.
"""
def deduct_from_pool_guaranteed(post_id, amount) when is_number(amount) and amount > 0 do
  BlocksterV2.PostBuxPoolWriter.deduct_guaranteed(post_id, amount)
end
```

### 3. Show.ex - Display Helpers

```elixir
# lib/blockster_v2_web/live/post_live/show.ex

@doc """
Returns pool balance for display purposes.
Always returns 0 or positive - never shows negative to users.
"""
defp display_pool_balance(pool_balance) when pool_balance <= 0, do: 0
defp display_pool_balance(pool_balance), do: pool_balance

@doc """
Determines if pool is available for NEW earning actions.
Returns false if pool is zero or negative.
"""
defp pool_available_for_new_actions?(pool_balance), do: pool_balance > 0
```

### 4. Show.ex - Mount Pattern

```elixir
# In handle_params:
pool_balance_internal = EngagementTracker.get_post_bux_balance(post.id)
pool_balance = display_pool_balance(pool_balance_internal)
pool_available = pool_available_for_new_actions?(pool_balance_internal)

socket
|> assign(:pool_balance, pool_balance)      # Always >= 0 for display
|> assign(:pool_available, pool_available)  # False if internal balance <= 0
```

### 5. Reward Completion - No Pool Checks

**Video rewards** (`mint_video_session_reward/4`):
```elixir
# GUARANTEED EARNINGS: Always pay full calculated amount (no min with pool)
actual_bux = final_session_bux

# ... mint tokens ...

# GUARANTEED EARNINGS: Deduct from pool (can go negative)
EngagementTracker.deduct_from_pool_guaranteed(post.id, trunc(actual_bux))
```

**Read rewards** (`handle_event("article-read", ...)`):
```elixir
# GUARANTEED EARNINGS: Always pay full calculated amount
actual_amount = desired_bux

# ... mint tokens ...

# GUARANTEED EARNINGS: Deduct from pool (can go negative)
EngagementTracker.deduct_from_pool_guaranteed(post_id_capture, recorded_bux)
```

**X share rewards**:
```elixir
# GUARANTEED EARNINGS: Award full BUX amount
actual_bux = socket.assigns.x_share_reward

# ... mint tokens ...

# GUARANTEED EARNINGS: Deduct from pool (can go negative)
EngagementTracker.deduct_from_pool_guaranteed(post.id, actual_bux)
```

---

## Testing Checklist

### Video Watch Rewards

- [ ] User starts video when pool = 100, watches 5 min (5 BUX), pool still positive → gets 5 BUX
- [ ] User starts video when pool = 100, another user drains pool during watch → first user still gets full reward
- [ ] User starts video when pool = 5, earns 10 BUX → gets 10 BUX, pool goes to -5
- [ ] User tries to start video when pool = 0 → tracking disabled, no earnings
- [ ] User tries to start video when pool = -50 → tracking disabled, no earnings
- [ ] Pool display shows 0 when actual balance is negative

### Article Read Rewards

- [ ] User completes article when pool = 100, earns 8 BUX → gets 8 BUX
- [ ] User completes article when pool = 3, earns 8 BUX → gets 8 BUX, pool goes to -5
- [ ] User starts reading when pool = 0 → pool_available = false, no reward tracking
- [ ] No "partial payment" messages appear

### X Share Rewards

- [ ] User shares when pool = 100, earns 5 BUX → gets 5 BUX
- [ ] User shares when pool = 2, earns 5 BUX → gets 5 BUX, pool goes to -3
- [ ] User tries to share when pool = 0 → appropriate "pool empty" message
- [ ] No "partial payment" messages appear

### UI Display

- [ ] Pool balance never shows negative numbers
- [ ] "Pool empty" indicator shows when balance <= 0
- [ ] No earning actions can start when pool <= 0
- [ ] In-progress actions complete successfully regardless of pool state

### Edge Cases

- [ ] Multiple users finish simultaneously when pool is low → all get full rewards
- [ ] User refreshes page mid-video → session state preserved, still gets reward
- [ ] Network error during mint → appropriate error handling (not pool-related)

---

## Migration Notes

### No Database Migration Needed

The pool balance field already supports the values we need. No schema changes required.

### Mnesia Tables

No changes to Mnesia table structure. The `post_bux_points` table already stores numeric values that can be negative.

### Backward Compatibility

- Existing positive pool balances: No change
- Existing zero pool balances: No change (still blocks new actions)
- New behavior only affects in-progress sessions when pool depletes

---

## Rollback Plan

If issues arise, revert to previous behavior by:

1. Restore the `pool_balance <= 0` checks in `show.ex`
2. Restore the `min(earned, pool_balance)` calculations
3. Restore partial payment flash messages
4. Change `deduct_from_pool_guaranteed` back to `try_deduct_from_pool`

No data migration needed for rollback.

---

## Implementation Checklist

### Phase 1: EngagementTracker Changes ✅

- [x] **1.1** Existing `get_post_bux_balance/1` returns internal balance (can be negative)
- [x] **1.2** Add `get_post_bux_balance_display/1` function - returns `max(0, balance)`
- [x] **1.3** Add `pool_available?/1` function - returns `balance > 0`
- [x] **1.4** Add `deduct_from_pool_guaranteed/2` function - delegates to PostBuxPoolWriter

### Phase 2: PostBuxPoolWriter Changes ✅

- [x] **2.1** Add `deduct_guaranteed/2` public function
- [x] **2.2** Add `handle_call({:deduct_guaranteed, ...})` handler
- [x] **2.3** Add `do_deduct_guaranteed/2` private function that allows negative balances
- [x] **2.4** Broadcast display value `max(0, new_balance)` after deduction

### Phase 3: show.ex - Helper Functions ✅

- [x] **3.1** Add `display_pool_balance/1` helper
- [x] **3.2** Add `pool_available_for_new_actions?/1` helper

### Phase 4: show.ex - Mount & Initial Load ✅

- [x] **4.1** Update `handle_params` to use internal balance for logic, display for UI

### Phase 5: show.ex - Video Reward Changes ✅

- [x] **5.1** Remove `pool_balance <= 0` branch from `mint_video_session_reward/4`
- [x] **5.2** Remove `pool_balance` fetch (no longer needed)
- [x] **5.3** Change `min(final_session_bux, pool_balance)` to just `final_session_bux`
- [x] **5.4** Update deduction to use `deduct_from_pool_guaranteed/2`

### Phase 6: show.ex - Read Reward Changes ✅

- [x] **6.1** Remove `pool_balance <= 0` branch from `handle_event("article-read", ...)`
- [x] **6.2** Change `min(desired_bux, pool_balance)` to just `desired_bux`
- [x] **6.3** Remove "Pool depleted! You earned X BUX (partial)" flash message
- [x] **6.4** Update deduction to use `deduct_from_pool_guaranteed/2`

### Phase 7: show.ex - X Share Reward Changes ✅

- [x] **7.1** Remove `{:ok, 0, status}` branch (pool empty at completion)
- [x] **7.2** Remove `{:ok, actual_bux, :partial_amount}` handling
- [x] **7.3** Always use full `x_share_reward` amount
- [x] **7.4** Update deduction to use `deduct_from_pool_guaranteed/2`

### Phase 8: show.ex - Pool Update Handlers ✅

- [x] **8.1** Update `handle_info({:bux_update, ...})` to use display helpers
- [x] **8.2** Update `handle_info({:video_mint_completed, ...})` to use display helpers

### Phase 9: Template Verification ✅

- [x] **9.1** Verify `show.html.heex` already uses `@pool_available` correctly
- [x] **9.2** Verify no "partial" text in templates

### Phase 10: JavaScript Hook Verification ✅

- [x] **10.1** Verify `video_watch_tracker.js` checks `poolAvailable` at mount
- [x] **10.2** Verify `engagement_tracker.js` checks `poolAvailable` at mount
- [x] **10.3** Confirm no changes needed to hooks

### Phase 11: Compilation ✅

- [x] **11.1** `mix compile` succeeds with no errors
- [x] **11.2** Only pre-existing warnings (unrelated to this change)

---

## Quick Reference: Key Code Locations

| What | File | Line (approx) |
|------|------|---------------|
| `deduct_guaranteed/2` | `post_bux_pool_writer.ex` | 56-65 |
| `do_deduct_guaranteed/2` | `post_bux_pool_writer.ex` | 200-257 |
| `get_post_bux_balance_display/1` | `engagement_tracker.ex` | 1159-1162 |
| `pool_available?/1` | `engagement_tracker.ex` | 1164-1168 |
| `deduct_from_pool_guaranteed/2` | `engagement_tracker.ex` | 1170-1177 |
| `display_pool_balance/1` | `show.ex` | 21-22 |
| `pool_available_for_new_actions?/1` | `show.ex` | 27-28 |
| Video reward minting | `show.ex` | ~580-665 |
| Read reward minting | `show.ex` | ~340-440 |
| X share reward | `show.ex` | ~850-920 |
| Pool balance display | `show.html.heex` | Multiple (uses `@pool_balance`, `@pool_available`) |
| JS video tracking | `video_watch_tracker.js` | 24, 41-43 |
| JS article tracking | `engagement_tracker.js` | 31-35 |

---

## Notes

### Old Behavior (Before This Change)

1. Pool was checked at completion time
2. If pool had less than earned, user got partial amount
3. If pool was empty, user got 0 (even after watching full video)
4. UI showed "Pool depleted! You earned X BUX (partial)"

### New Behavior (After This Change)

1. Pool is checked only at START of earning action
2. If pool was positive at start, user gets FULL calculated reward
3. Pool can go negative to honor commitments
4. No partial payment messages - users always get full amount or nothing

### Why `try_deduct_from_pool` Still Exists

The old function is kept for backward compatibility and potential rollback. It's no longer called from the reward flows, but could be used elsewhere in the codebase. The new `deduct_from_pool_guaranteed` is the preferred function for reward completions.
