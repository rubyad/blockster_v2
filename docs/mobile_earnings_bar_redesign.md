# Mobile Earnings Bar Redesign

## Overview

Redesign the mobile post reading experience to consolidate the earnings display into the sticky top bar, removing the green bottom bar and creating a more unified mobile UI.

## Current State

### Green Bottom Bar (Lines 264-298 in show.html.heex)
- **Location**: Fixed at `bottom-[68px]` (above bottom nav)
- **Visibility**: `md:hidden` (mobile only)
- **Content**: BUX icon, current amount, multiplier, progress bar
- **Styling**: Green gradient `from-[#8AE388] to-[#6BCB69]`

### Sticky Top Bar (Lines 429-507 in show.html.heex)
- **Location**: `sticky top-[58px] md:top-24`
- **Content**:
  - Left side: X Share button (various states)
  - Right side: BUX balance badge showing pool balance
- **Styling**: White background with bottom border

## Target State

### Mobile (< 768px)

The sticky top bar becomes the unified earnings display:

```
┌─────────────────────────────────────────────────────────────┐
│ [Progress Bar - full width, thin]                           │
├─────────────────────────────────────────────────────────────┤
│ 🪙 0.42 BUX earned • Keep reading to earn more!   [X Share] │
│                                   OR                         │
│ 🪙 0.42 BUX earned                               [X Share]   │
│ (when logged in with wide share button)                      │
│                                   OR                         │
│ 🪙 0.42 BUX earned • Keep reading to earn more!              │
│ (when not logged in - no X share button)                     │
└─────────────────────────────────────────────────────────────┘
```

### Desktop (≥ 768px)

No changes - keep existing layout with:
- Desktop green card (Lines 106-119)
- Sticky bar with X Share and BUX balance

## Implementation Details

### 1. Remove Mobile Green Bottom Bar

**File**: `lib/blockster_v2_web/live/post_live/show.html.heex`

**Lines to modify**: 264-298

Remove or hide the mobile-only green bar:
```heex
<!-- REMOVE: Mobile floating green earning bar -->
<%= if @pool_has_bux and not @already_rewarded do %>
  <div class="md:hidden fixed bottom-[68px] left-2 right-2 z-40 ...">
    ...
  </div>
<% end %>
```

**Action**: Wrap entire block in `hidden` class or delete for mobile.

### 2. Redesign Mobile Sticky Bar

**File**: `lib/blockster_v2_web/live/post_live/show.html.heex`

**Lines to modify**: 429-507

#### New Structure

```heex
<!-- Sticky bar - different layout for mobile vs desktop -->
<div class="sticky top-[58px] md:top-24 z-10 bg-white border-b">

  <!-- Mobile: Progress bar at top (only when earning) -->
  <%= if @pool_has_bux and not @already_rewarded do %>
    <div class="md:hidden h-1 bg-gray-100">
      <div
        class="h-full bg-gradient-to-r from-[#8AE388] to-[#6BCB69] transition-all duration-300"
        style={"width: #{@current_score * 10}%"}
      />
    </div>
  <% end %>

  <div class="flex items-center gap-2 px-4 py-2">

    <!-- LEFT SIDE: X Share Button -->
    <!-- Desktop: existing X share button (unchanged) -->
    <div class="hidden md:flex items-center">
      <!-- Keep existing X share button code for desktop -->
      ...
    </div>

    <!-- Mobile: Compact X Share Button (when logged in with campaign) -->
    <%= if @current_user && @share_campaign && @share_campaign.is_active do %>
      <div class="md:hidden shrink-0">
        <!-- Compact X share button for mobile -->
        ...
      </div>
    <% end %>

    <!-- MIDDLE: Encouragement text (mobile only, hide when X share visible) -->
    <!-- Uses flex-1 min-w-0 to allow shrinking and truncate as fallback -->
    <%= if @pool_has_bux and not @already_rewarded do %>
      <span class={[
        "md:hidden text-xs text-gray-500 flex-1 min-w-0 truncate",
        @current_user && @share_campaign && @share_campaign.is_active && "hidden"
      ]}>
        Keep reading to earn more!
      </span>
    <% end %>

    <!-- RIGHT SIDE: Earnings Display (mobile) / BUX Balance Badge (desktop) -->

    <!-- Desktop: BUX Balance Badge (existing - unchanged) -->
    <div class="hidden md:flex ml-auto">
      <!-- Keep existing BUX balance badge for desktop -->
      ...
    </div>

    <!-- Mobile: Earnings Display (replaces BUX balance) -->
    <div class="md:hidden ml-auto flex items-center gap-1.5 shrink-0">
      <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class="w-5 h-5 rounded-full" />
      <%= if @pool_has_bux and not @already_rewarded do %>
        <!-- Currently earning -->
        <span class="font-haas_medium_65 text-sm">
          <%= Float.round(@current_bux, 2) %> BUX
        </span>
      <% else %>
        <!-- Already earned or no pool -->
        <span class="font-haas_medium_65 text-sm text-gray-400">
          <%= if @already_rewarded, do: "Already earned", else: "No rewards" %>
        </span>
      <% end %>
    </div>

  </div>
</div>
```

### 3. Conditional Logic Summary

| State | Logged In | X Share Visible | Encouragement Text | Progress Bar |
|-------|-----------|-----------------|-------------------|--------------|
| Earning, no campaign | No | No | Yes | Yes |
| Earning, no campaign | Yes | No | Yes | Yes |
| Earning, has campaign | Yes | Yes (compact) | No (hidden) | Yes |
| Already earned | Any | Depends | N/A (shows "Already earned") | No |
| No pool | Any | Depends | N/A (shows "No rewards") | No |

### 4. Mobile X Share Button States

When logged in with active campaign, show compact X button. Compare to current desktop:

#### Current Desktop Button (h-9, ~120px wide when shared)
```
┌───────────────────────────────────────────┐
│ 𝕏  Shared & Liked!  [🪙 10 BUX]          │  ← h-10, px-4, ring-2
└───────────────────────────────────────────┘
```

#### Proposed Mobile Compact Button (h-7, ~70px wide)

**Not yet shared:**
```heex
<button
  phx-click="open_share_modal"
  class="flex items-center gap-1.5 h-7 px-2.5 bg-black text-white rounded-full text-xs font-haas_medium_65"
>
  <svg class="w-3.5 h-3.5"><!-- X icon --></svg>
  <span class="bg-[#8AE388] text-black px-1.5 py-0.5 rounded-full text-[10px] font-bold">
    +<%= @x_share_reward %>
  </span>
</button>
```
```
┌─────────────────┐
│ 𝕏  [+10]       │  ← h-7, compact
└─────────────────┘
```

**Already shared:**
```heex
<div class="flex items-center gap-1 h-7 px-2.5 bg-[#8AE388]/20 text-[#22863a] rounded-full text-xs font-haas_medium_65">
  <svg class="w-3.5 h-3.5"><!-- checkmark --></svg>
  <span>Shared</span>
</div>
```
```
┌─────────────────┐
│ ✓  Shared      │  ← Green tint bg
└─────────────────┘
```

**Pool empty:**
```heex
<div class="flex items-center gap-1 h-7 px-2.5 bg-gray-100 text-gray-500 rounded-full text-xs">
  <svg class="w-3.5 h-3.5"><!-- X icon --></svg>
  <span>Empty</span>
</div>
```
```
┌─────────────────┐
│ 𝕏  Empty       │  ← Gray, disabled look
└─────────────────┘
```

### 5. Desktop Preservation

All desktop elements remain unchanged:

- **Lines 106-119**: Desktop green card (keep `hidden md:block`)
- **Lines 431-495**: Desktop X share section (keep `hidden md:flex`)
- **Lines 497-506**: Desktop BUX balance badge (keep `hidden md:block`)

### 6. Remove Mobile BUX Balance Display

The current right-side BUX balance badge (showing pool balance) is replaced by the earnings display. Remove it from mobile:

```heex
<!-- Change from: -->
<div class="ml-auto bg-[#F7F8FA] rounded-full px-3 py-1.5 flex items-center gap-1.5">
  ...
</div>

<!-- To: -->
<div class="hidden md:flex ml-auto bg-[#F7F8FA] rounded-full px-3 py-1.5 items-center gap-1.5">
  ...
</div>
```

## File Changes Summary

### `lib/blockster_v2_web/live/post_live/show.html.heex`

| Section | Lines | Action |
|---------|-------|--------|
| Mobile green bottom bar | 264-298 | Add `hidden` class or delete mobile section |
| Sticky bar container | 429-430 | Keep, no changes |
| Progress bar | NEW | Add above sticky bar content for mobile |
| Mobile earnings display | NEW | Add left-aligned earnings with encouragement |
| Desktop X share | 431-495 | Add `hidden md:flex` wrapper |
| Mobile X share | NEW | Add compact button for mobile |
| Desktop BUX balance | 497-506 | Add `hidden md:flex` |

## CSS Classes Reference

### New Mobile-Specific Classes

```css
/* Progress bar */
h-1                     /* 4px height */
bg-gray-100            /* Track background */
from-[#8AE388] to-[#6BCB69]  /* Green gradient fill */

/* Earnings display */
shrink-0               /* Prevent BUX amount from shrinking */
flex-1 min-w-0         /* Allow text to truncate */
truncate               /* Truncate long encouragement text */

/* Compact X button */
px-2 py-1              /* Tight padding */
text-xs                /* Small text */
rounded-full           /* Pill shape */
```

### Responsive Visibility

```css
md:hidden              /* Mobile only */
hidden md:flex         /* Desktop only */
hidden md:block        /* Desktop only (block) */
```

## Testing Checklist

### Mobile Tests (< 768px)

- [ ] Progress bar appears at top of sticky bar when earning
- [ ] Progress bar width matches `@current_score * 10%`
- [ ] BUX icon and amount display correctly
- [ ] "Keep reading to earn more!" shows when no X share button
- [ ] X share button (compact) shows when logged in with campaign
- [ ] Encouragement text hidden when X share button visible
- [ ] "Already earned" state displays correctly
- [ ] "No rewards" state displays correctly
- [ ] Green bottom bar is removed/hidden
- [ ] Sticky bar stays fixed during scroll
- [ ] No horizontal overflow on narrow screens

### Desktop Tests (≥ 768px)

- [ ] No changes to existing layout
- [ ] Desktop green card still visible
- [ ] Full X share button visible
- [ ] BUX balance badge visible on right
- [ ] Progress bar NOT showing (use desktop card instead)

### Edge Cases

- [ ] Very long post titles don't break layout
- [ ] Zero BUX earned displays correctly
- [ ] Maximum BUX earned (e.g., 10.00) fits
- [ ] X share success state (green "Shared" badge) fits
- [ ] Multiplier display (if keeping) fits

## Current Sticky Bar Layout (Lines 429-507)

### Container Structure

```heex
<div class="sticky top-[58px] md:top-24 z-10 bg-white flex items-center gap-2 py-4 mb-4 border-b border-[#E7E8F1]">
  <!-- LEFT: X Share Button (various states) -->
  <!-- RIGHT: BUX Balance Badge (ml-auto pushes to right) -->
</div>
```

### Current Layout Visualization

```
┌─────────────────────────────────────────────────────────────────┐
│ [X Share Button]                              [🪙 1,234 BUX]    │
│     ↑                                              ↑            │
│  Left side                                    ml-auto (right)   │
│  (gap-2 spacing)                                                │
└─────────────────────────────────────────────────────────────────┘
```

### X Share Button States (Left Side)

#### State 1: Active Campaign + Already Shared (Lines 435-448)
```
┌──────────────────────────────────────────────────────────────────────┐
│ ┌─────────────────────────────────────────────┐  ┌───┐              │
│ │ 𝕏  Shared & Liked!  [🪙 10 BUX]            │  │ ↗ │   [🪙 1,234] │
│ └─────────────────────────────────────────────┘  └───┘              │
│   ↑ Black bg, green ring, h-10                    ↑ TX link         │
└──────────────────────────────────────────────────────────────────────┘
```
- Black pill with green ring (`ring-2 ring-[#8AE388]`)
- X icon + "Shared & Liked!" in green + BUX amount badge
- Optional transaction link button (gray circle)

#### State 2: Active Campaign + Logged In + Not Shared (Lines 450-470)
```
┌──────────────────────────────────────────────────────────────────────┐
│ ┌─────────────────────────────┐                                      │
│ │ 𝕏  [🪙 10 BUX]             │                        [🪙 1,234 BUX] │
│ └─────────────────────────────┘                                      │
│   ↑ Black pill, h-9, clickable                                       │
└──────────────────────────────────────────────────────────────────────┘
```
- Black pill button (`h-9 px-3`)
- X icon + green BUX badge (or gray "Pool empty" if no pool)
- Hover tooltip: "Earn X BUX for liking and retweeting..."

#### State 3: Active Campaign + Not Logged In (Lines 472-489)
```
┌──────────────────────────────────────────────────────────────────────┐
│ ┌─────────────────────────────┐                                      │
│ │ 𝕏  [🪙 10 BUX]             │                        [🪙 1,234 BUX] │
│ └─────────────────────────────┘                                      │
│   ↑ Link to login (same styling as above)                            │
└──────────────────────────────────────────────────────────────────────┘
```
- Same appearance as logged-in state
- Links to `/users/log_in?return_to=/post-slug`

#### State 4: No Active Campaign (Lines 492-494)
```
┌──────────────────────────────────────────────────────────────────────┐
│ ┌───┐                                                                │
│ │ 𝕏 │                                              [🪙 1,234 BUX]    │
│ └───┘                                                                │
│   ↑ Simple gray circle (w-9 h-9), links to Twitter intent            │
└──────────────────────────────────────────────────────────────────────┘
```
- Small gray circle button (`w-9 h-9 bg-[#F7F8FA]`)
- Just X icon, no BUX reward

### BUX Balance Badge (Right Side, Lines 497-506)

```heex
<div class="relative group ml-auto">
  <div class="flex items-center gap-2 bg-[#F7F8FA] rounded-full px-3 py-1.5">
    <img src="bux-icon.png" class="h-5 w-5" />
    <span class="text-sm font-haas_medium_65">1,234 BUX</span>
  </div>
  <!-- Hover tooltip showing remaining pool -->
</div>
```

- `ml-auto` pushes to far right
- Gray pill background (`bg-[#F7F8FA]`)
- Shows post's remaining BUX pool balance
- Hover tooltip: "X BUX remaining in rewards pool"

---

## Proposed New Mobile Layout

### New Structure (Mobile Only)

The X share button stays on the **left** (same position as current).
The earnings display replaces the BUX balance on the **right** (where `ml-auto` badge currently is).

```
┌─────────────────────────────────────────────────────────────────┐
│ ████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │ ← Progress bar (h-1)
├─────────────────────────────────────────────────────────────────┤
│ [𝕏 +10]     Keep reading to earn more!           🪙 0.42 BUX   │
│    ↑                    ↑                              ↑        │
│ X Share           Encouragement                    Earnings     │
│ (left)        (middle, hide if X wide)         (ml-auto, right) │
└─────────────────────────────────────────────────────────────────┘
```

### Proposed States

#### Mobile - Not Logged In, Earning (no X share button)
```
┌──────────────────────────────────────────────────────────────────────┐
│ ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
├──────────────────────────────────────────────────────────────────────┤
│ Keep reading to earn more!                              🪙 0.42 BUX │
└──────────────────────────────────────────────────────────────────────┘
```
- No X share button (not logged in)
- Full width for encouragement text
- Earnings on right

#### Mobile - Logged In with Campaign, Earning
```
┌──────────────────────────────────────────────────────────────────────┐
│ ████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
├──────────────────────────────────────────────────────────────────────┤
│ [𝕏 +10]                                                🪙 0.65 BUX │
└──────────────────────────────────────────────────────────────────────┘
```
- X share button on left (compact)
- Encouragement text hidden (X button takes space)
- Earnings on right

#### Mobile - Already Shared
```
┌──────────────────────────────────────────────────────────────────────┐
│ ██████████████████████████████████████████████████████████████████░░ │
├──────────────────────────────────────────────────────────────────────┤
│ [✓ Shared]                                             🪙 1.12 BUX │
└──────────────────────────────────────────────────────────────────────┘
```
- Green "Shared" badge on left
- Earnings on right

#### Mobile - Already Earned (no progress bar)
```
┌──────────────────────────────────────────────────────────────────────┐
│ [𝕏 +10]                                           🪙 Already earned │
└──────────────────────────────────────────────────────────────────────┘
```
- X share button still available (if campaign active)
- "Already earned" replaces amount on right

#### Mobile - No Pool Available
```
┌──────────────────────────────────────────────────────────────────────┐
│ [𝕏 Empty]                                          🪙 No rewards    │
└──────────────────────────────────────────────────────────────────────┘
```
- Gray X button on left
- "No rewards" on right

## Implementation Order

1. **Phase 1**: Hide mobile green bottom bar
2. **Phase 2**: Add progress bar to sticky bar (mobile only)
3. **Phase 3**: Add mobile earnings display with encouragement text
4. **Phase 4**: Add compact mobile X share button
5. **Phase 5**: Hide desktop elements on mobile
6. **Phase 6**: Test all states and edge cases

## Related Files

- `lib/blockster_v2_web/live/post_live/show.html.heex` - Main template
- `lib/blockster_v2_web/live/post_live/show.ex` - LiveView logic (no changes needed)
- `assets/js/engagement_tracker.js` - Updates `@current_score` and `@current_bux`
- `assets/css/app.css` - No new styles needed (using Tailwind)

## Notes

- The `@current_score` value ranges from 0-10, representing engagement percentage
- The `@current_bux` value is a float that updates in real-time via the EngagementTracker hook
- The `@has_active_share_campaign` assign may need to be added if not already present
- Consider adding a subtle animation when progress bar updates for better UX
