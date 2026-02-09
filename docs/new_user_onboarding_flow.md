# New User Onboarding Flow

## Overview

After a new user's first login, they are guided through an onboarding flow that explains Blockster's value proposition and encourages profile completion to maximize earning power.

## User Flow Diagram

```
First Login
    │
    ▼
┌─────────────────────────┐
│  Step 1: Welcome        │
│  "Read, watch, share    │
│   to earn BUX"          │
│         [Next]          │
└─────────────────────────┘
    │
    ▼
┌─────────────────────────┐
│  Step 2: Redeem         │
│  "Redeem on merch,      │
│   games, airdrops"      │
│         [Next]          │
└─────────────────────────┘
    │
    ▼
┌─────────────────────────┐
│  Step 3: Complete       │
│  Profile Prompt         │
│  [Continue] [Skip]      │
└─────────────────────────┘
    │
    ├──── [Skip] ────────────────────────┐
    │                                     │
    ▼                                     ▼
┌─────────────────────────┐         ┌─────────────────────┐
│  Step 4: Connect Phone  │         │  News Page          │
│  [Connect] [Skip]       │         │  (First scroll      │
└─────────────────────────┘         │   triggers popup)   │
    │                                └─────────────────────┘
    ▼
┌─────────────────────────┐
│  Step 5: Connect Wallet │
│  [Connect] [Skip]       │
└─────────────────────────┘
    │
    ▼
┌─────────────────────────┐
│  Step 6: Connect X      │
│  [Connect] [Skip]       │
└─────────────────────────┘
    │
    ▼
┌─────────────────────────┐
│  Step 7: All Set!       │
│  "XXX earning power"    │
│  [Start Earning]        │
└─────────────────────────┘
    │
    ▼
┌─────────────────────────┐
│  Step 8: ROGUE Upsell   │
│  "Hold ROGUE to earn    │
│   even more"            │
│  [Learn More] [Skip]    │
└─────────────────────────┘
    │
    ▼
  News Page
```

---

## Screen Specifications

**Important**: All onboarding screens are **dedicated web pages** (not modals). This provides:
- URL state for each step (refresh-safe, browser back button works)
- Better mobile experience (no modal dismiss gestures)
- Cleaner UX without underlying page distractions
- Easier analytics tracking via page views

---

## Design System

### Modern Minimal Aesthetic

All onboarding pages follow a consistent, modern minimal design:

**Layout**:
- Centered content with generous whitespace
- Maximum content width: 480px (mobile-first)
- Vertical rhythm with consistent spacing (24px between elements)
- Single-column layout, vertically centered on viewport

**Typography**:
- Headlines: `font-haas_medium_65`, 32px (mobile) / 40px (desktop), black
- Subheadlines: `font-haas_roman_55`, 18px, gray-600
- Body text: 16px, gray-500
- All text center-aligned

**Colors**:
- Background: White (`#FFFFFF`)
- Primary accent: Blockster green (`#CAFC00`)
- Text: Black (`#000000`) for headlines, gray for body
- Secondary elements: Light gray (`#F5F5F5`) for cards/containers

**Buttons**:
- Primary: Black background, white text, full-width, 56px height, rounded-full
- On hover: Blockster green background (`#CAFC00`), black text
- Secondary (skip links): Gray text, no background, underline on hover

**Icons/Visuals**:
- Minimal line icons or simple filled shapes
- Single accent color (green) for highlights
- Subtle animations: fade-in on load, gentle scale on interaction
- No gradients, shadows minimal (if any)

**Progress Indicator**:
- Horizontal dots at top of page
- Current step: filled black dot
- Completed steps: filled green dot
- Future steps: gray outline dot

**Spacing**:
- Page padding: 24px (mobile), 48px (desktop)
- Between headline and subheadline: 16px
- Between content and CTA: 48px
- Between primary and secondary CTA: 16px

---

### Step 1: Welcome Screen

**Route**: `/onboarding` (redirects to `/onboarding/welcome`)

**Layout**:
```
┌─────────────────────────────────┐
│  ○ ○ ○ ○ ○ ○ ○ ○  (progress)   │
│                                 │
│                                 │
│         [Blockster Logo]        │
│              ⚡                  │
│                                 │
│     Welcome to Blockster        │
│                                 │
│   Read, watch and share daily   │
│    stories to earn BUX          │
│                                 │
│                                 │
│  ┌───────────────────────────┐  │
│  │          Next             │  │
│  └───────────────────────────┘  │
│                                 │
└─────────────────────────────────┘
```

**Content**:
- **Logo**: Blockster icon (lime green circle with black lightning bolt)
- **Headline**: "Welcome to Blockster"
- **Subheadline**: "Read, watch and share daily stories to earn BUX"
- **CTA Button**: "Next" (black, full-width, rounded-full)

**Design Notes**:
- Logo centered with subtle pulse animation on load
- Clean white background
- Progress dots at top: first dot filled black

---

### Step 2: Redeem Screen

**Route**: `/onboarding/redeem`

**Layout**:
```
┌─────────────────────────────────┐
│  ● ○ ○ ○ ○ ○ ○ ○  (progress)   │
│                                 │
│                                 │
│    ┌─────┐ ┌─────┐ ┌─────┐     │
│    │ 👕  │ │ 🎮  │ │ 🎁  │     │
│    │Shop │ │Game │ │Drops│     │
│    └─────┘ └─────┘ └─────┘     │
│                                 │
│       Redeem Your BUX           │
│                                 │
│    Cool merch, games and        │
│         airdrops                │
│                                 │
│  ┌───────────────────────────┐  │
│  │          Next             │  │
│  └───────────────────────────┘  │
│                                 │
└─────────────────────────────────┘
```

**Content**:
- **Visual**: 3 minimal icons in a row (48px each, outlined style)
  - Shopping bag icon → "Shop"
  - Game controller icon → "Games"
  - Gift/airdrop icon → "Drops"
- **Headline**: "Redeem Your BUX"
- **Subheadline**: "Cool merch, games and airdrops"
- **CTA Button**: "Next"

**Design Notes**:
- Icons use thin black stroke, no fill
- Labels below icons in small gray text (12px)
- Icons fade in sequentially on load (100ms stagger)

---

### Step 3: Complete Profile Prompt

**Route**: `/onboarding/profile`

**Layout**:
```
┌─────────────────────────────────┐
│  ● ● ○ ○ ○ ○ ○ ○  (progress)   │
│                                 │
│                                 │
│         ┌─────────┐             │
│         │ {curr}x │             │
│         │   ↓     │             │
│         │ {max}x  │             │
│         └─────────┘             │
│                                 │
│    Complete Your Profile        │
│                                 │
│   Increase your earning power   │
│   by connecting your accounts   │
│                                 │
│  ┌───────────────────────────┐  │
│  │        Let's Go           │  │
│  └───────────────────────────┘  │
│                                 │
│       I'll do this later        │
│                                 │
└─────────────────────────────────┘
```

**Content**:
- **Visual**: Minimal earning power indicator
  - Current multiplier in gray (dynamically calculated)
  - Downward arrow
  - Potential multiplier in black with green highlight (up to 360x max)
- **Headline**: "Complete Your Profile"
- **Subheadline**: "Increase your earning power by connecting your accounts"
- **Primary CTA**: "Let's Go" (black button)
- **Secondary CTA**: "I'll do this later" (gray text link)

**Design Notes**:
- Multiplier numbers use large bold font (48px)
- Arrow animates subtly (gentle bounce)
- Skip link has adequate touch target (44px height)

**Behavior**:
- "Let's Go" → Proceed to Step 4 (Connect Phone)
- "I'll do this later" →
  - Set `onboarding_skipped = true` in session (not database)
  - Redirect to `/news` (News page)
  - Enable first-scroll popup trigger

---

### Step 4: Connect Phone

**Route**: `/onboarding/phone`

**Layout**:
```
┌─────────────────────────────────┐
│  ● ● ● ○ ○ ○ ○ ○  (progress)   │
│                                 │
│         Step 1 of 3             │
│                                 │
│            📱                   │
│                                 │
│      Connect Your Phone         │
│                                 │
│   Verify to boost earnings      │
│                                 │
│    0.5x  →  2.0x (premium)      │
│                                 │
│  ┌───────────────────────────┐  │
│  │  🇺🇸 +1  │  Phone number  │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │       Send Code           │  │
│  └───────────────────────────┘  │
│                                 │
│        Skip for now             │
│                                 │
└─────────────────────────────────┘
```

**Content**:
- **Step Indicator**: "Step 1 of 3" (small, gray, above icon)
- **Visual**: Phone icon (minimal line style)
- **Headline**: "Connect Your Phone"
- **Subheadline**: "Verify to boost earnings"
- **Multiplier Preview**: "0.5x → 2.0x" (unverified penalty → premium tier)
- **Input**: Phone number field with country code dropdown
- **Primary CTA**: "Send Code" → "Verify" (after code sent)
- **Secondary CTA**: "Skip for now" (gray text link)

**Design Notes**:
- Input field: 56px height, light gray border, rounded-lg
- Country code dropdown on left side of input
- Multiplier change shown inline with arrow
- After sending code, show 6-digit code input field

**Behavior**:
- Successful verification:
  - Update `user.phone_verified = true`
  - Brief success animation (checkmark)
  - Auto-proceed to Step 5 after 1 second
- Skip:
  - Proceed to Step 5 without phone bonus

---

### Step 5: Connect Wallet

**Route**: `/onboarding/wallet`

**Layout**:
```
┌─────────────────────────────────┐
│  ● ● ● ● ○ ○ ○ ○  (progress)   │
│                                 │
│         Step 2 of 3             │
│                                 │
│            💳                   │
│                                 │
│      Connect Your Wallet        │
│                                 │
│    Receive BUX rewards          │
│         on-chain                │
│                                 │
│                                 │
│  ┌───────────────────────────┐  │
│  │     Connect Wallet        │  │
│  └───────────────────────────┘  │
│                                 │
│        Skip for now             │
│                                 │
└─────────────────────────────────┘
```

**Content**:
- **Step Indicator**: "Step 2 of 3"
- **Visual**: Wallet icon (minimal line style)
- **Headline**: "Connect Your Wallet"
- **Subheadline**: "Receive BUX rewards on-chain"
- **Primary CTA**: "Connect Wallet" (triggers Thirdweb connect modal)
- **Secondary CTA**: "Skip for now" (gray text link)

**Design Notes**:
- No multiplier shown (wallet is required for payouts, not a bonus)
- Thirdweb modal appears over this page when button clicked
- Success state shows abbreviated wallet address with checkmark

**Behavior**:
- Successful connection:
  - Create/link smart wallet via Thirdweb
  - Update `user.wallet_address` and `user.smart_wallet_address`
  - Show success state briefly, then proceed to Step 6
- Skip:
  - Proceed to Step 6 (user can connect later)

---

### Step 6: Connect X Account

**Route**: `/onboarding/x`

**Layout**:
```
┌─────────────────────────────────┐
│  ● ● ● ● ● ○ ○ ○  (progress)   │
│                                 │
│         Step 3 of 3             │
│                                 │
│            𝕏                    │
│                                 │
│     Connect Your X Account      │
│                                 │
│   Share stories to earn BUX     │
│                                 │
│     Up to +2.0x multiplier      │
│                                 │
│  ┌───────────────────────────┐  │
│  │       Connect X           │  │
│  └───────────────────────────┘  │
│                                 │
│        Skip for now             │
│                                 │
└─────────────────────────────────┘
```

**Content**:
- **Step Indicator**: "Step 3 of 3"
- **Visual**: X logo (black)
- **Headline**: "Connect Your X Account"
- **Subheadline**: "Share stories to earn BUX"
- **Bonus Info**: "Up to 10.0x multiplier" (green text, based on X quality score)
- **Primary CTA**: "Connect X" (triggers OAuth flow)
- **Secondary CTA**: "Skip for now" (gray text link)

**Design Notes**:
- X logo should be the official mark
- Multiplier range shown in green to emphasize benefit
- OAuth flow opens in popup or redirect

**Behavior**:
- Successful connection:
  - Complete X OAuth with PKCE
  - Store tokens in Mnesia `x_connections` table
  - Calculate X quality score → `x_multiplier`
  - Proceed to Step 7
- Skip:
  - Proceed to Step 7 with base multiplier only

---

### Step 7: All Set Screen

**Route**: `/onboarding/complete`

**Layout**:
```
┌─────────────────────────────────┐
│  ● ● ● ● ● ● ○ ○  (progress)   │
│                                 │
│            ✓                    │
│                                 │
│       You're All Set!           │
│                                 │
│                                 │
│          ┌───────┐              │
│          │ 2.5x  │              │
│          └───────┘              │
│       Earning Power             │
│                                 │
│   ✓ Phone    +0.5x              │
│   ✓ Wallet   Connected          │
│   ✓ X        +1.0x              │
│                                 │
│  ┌───────────────────────────┐  │
│  │      Start Earning        │  │
│  └───────────────────────────┘  │
│                                 │
└─────────────────────────────────┘
```

**Content**:
- **Visual**: Checkmark icon with subtle success animation
- **Headline**: "You're All Set!"
- **Earning Power Display**: Large multiplier in bordered box (e.g., "2.5x")
- **Label**: "Earning Power" below the number
- **Breakdown List**:
  - Each connected item with checkmark and bonus
  - Skipped items show "+" and potential bonus in gray
- **Primary CTA**: "Start Earning" (black button)

**Design Notes**:
- Multiplier number is extra large (64px) and bold
- Checkmarks are green
- Breakdown uses small text (14px)
- Skipped items shown as: "○ Phone +0.5x" in gray

**Behavior**:
- "Start Earning" → Proceed to Step 8 (ROGUE upsell)

---

### Step 8: ROGUE Upsell Screen

**Route**: `/onboarding/rogue`

**Layout**:
```
┌─────────────────────────────────┐
│  ● ● ● ● ● ● ● ○  (progress)   │
│                                 │
│                                 │
│           🟢                    │
│          ROGUE                  │
│                                 │
│   Psst... Want to Earn More?    │
│                                 │
│    Hold ROGUE tokens for        │
│       bonus rewards             │
│                                 │
│   • Extra BUX multiplier        │
│   • Exclusive airdrops          │
│   • Play BUX Booster            │
│                                 │
│  ┌───────────────────────────┐  │
│  │       Learn More          │  │
│  └───────────────────────────┘  │
│                                 │
│        Maybe Later              │
│                                 │
└─────────────────────────────────┘
```

**Content**:
- **Visual**: ROGUE token icon (green circle)
- **Headline**: "Psst... Want to Earn More?"
- **Subheadline**: "Hold ROGUE tokens for bonus rewards"
- **Benefits List** (left-aligned, minimal bullets):
  - "Extra BUX multiplier"
  - "Exclusive airdrops"
  - "Play BUX Booster"
- **Primary CTA**: "Learn More" (links to ROGUE info page)
- **Secondary CTA**: "Maybe Later" (gray text link)

**Design Notes**:
- Softer, less urgent tone than other screens
- Benefits list uses small bullet points
- ROGUE icon has subtle glow effect

**Behavior**:
- "Learn More" → Open ROGUE info in new tab, redirect to `/news`
- "Maybe Later" → Redirect to `/news`

---

## First Scroll Popup (For Skipped Users)

**Trigger Condition**:
- User clicked "I'll do this later" on Step 3
- User is viewing their first article
- User has scrolled at least 20% into the article

**Display**:
- Bottom sheet popup (mobile) or floating card (desktop)
- Non-blocking - user can continue reading

**Content**:
- **Headline**: "Boost Your Earnings"
- **Body**: "Your BUX earning power is currently **{multiplier}x**"
- **Subtext**: "Complete your profile to increase your earnings"
- **Primary CTA**: "Complete Profile" (links to `/onboarding/phone`)
- **Dismiss**: "X" close button (top-right)

**Design Notes**:
- Semi-transparent overlay behind popup
- Slide up animation from bottom (mobile)
- Fade in from bottom-right (desktop)
- Green accent for CTA button

**Behavior**:
- "Complete Profile" → Navigate to `/onboarding/phone`
- Close → Dismiss popup, set `user.onboarding_popup_dismissed = true`
- Popup should only show **once per session**

---

## Database/State Changes

**No database changes required.**

### How It Works

Onboarding is triggered **once, immediately after first signup**:

1. User signs up → Signup flow redirects to `/onboarding` instead of `/news`
2. User completes onboarding (or skips) → Redirects to `/news`
3. That's it. No tracking needed.

**Existing users**: Unaffected. Only new signups go through onboarding.

**Returning users**: Normal login goes to `/news`. The `/onboarding` route is only reached via the signup redirect.

### Session State (Minimal)

Only track popup display in session (not persisted):
```elixir
%{
  onboarding_popup_shown: boolean  # Prevents popup from showing twice per session
}
```

This is only needed for the "first scroll" popup for users who clicked "I'll do this later".

---

## Earning Power Calculation Display

The earning power is calculated using a **multiplicative formula**:

```
Overall = X Multiplier × Phone Multiplier × ROGUE Multiplier × Wallet Multiplier
```

### Multiplier Ranges

| Component | Min | Max | How It's Calculated |
|-----------|-----|-----|---------------------|
| X Multiplier | 1.0x | 10.0x | `max(x_score/10, 1.0)` based on X account quality score (0-100) |
| Phone Multiplier | 0.5x | 2.0x | Based on verification + geo tier |
| ROGUE Multiplier | 1.0x | 5.0x | Based on ROGUE in Blockster smart wallet |
| Wallet Multiplier | 1.0x | 3.6x | Based on ETH + tokens in external wallet |
| **Overall** | **0.5x** | **360.0x** | Product of all four multipliers |

### Phone Multiplier Tiers

| Tier | Multiplier | Countries |
|------|------------|-----------|
| Unverified | 0.5x | Not verified (penalty) |
| Basic | 1.0x | Other verified countries |
| Standard | 1.5x | BR, MX, EU, JP, KR |
| Premium | 2.0x | US, CA, UK, AU, DE, FR |

### Example Displays

- Minimum (no phone): "0.5x Earning Power" (unverified penalty)
- Phone verified (basic): "1.0x Earning Power"
- Phone + X connected: "5.0x Earning Power" (1.0 × 5.0 × 1.0 × 1.0)
- Full setup: "36.0x Earning Power" (2.0 × 3.0 × 3.0 × 2.0)

**Note**: Wallet connection is required to receive on-chain BUX rewards but provides its own multiplier based on token holdings.

---

## Technical Implementation

### LiveView Structure

```
lib/blockster_v2_web/live/onboarding_live/
├── index.ex           # Main onboarding LiveView (handles all steps)
├── welcome.html.heex  # Step 1 template
├── redeem.html.heex   # Step 2 template
├── profile.html.heex  # Step 3 template
├── phone.html.heex    # Step 4 template
├── wallet.html.heex   # Step 5 template
├── x.html.heex        # Step 6 template
├── complete.html.heex # Step 7 template
└── rogue.html.heex    # Step 8 template
```

### Route Configuration

```elixir
# router.ex
scope "/", BlocksterV2Web do
  pipe_through [:browser, :require_authenticated_user]

  live "/onboarding", OnboardingLive.Index, :welcome
  live "/onboarding/:step", OnboardingLive.Index, :step
end
```

### Signup Redirect

```elixir
# In accounts.ex or session controller - after successful signup only
def after_signup(conn, user) do
  # New signups go to onboarding
  redirect(conn, to: ~p"/onboarding")
end

def after_login(conn, user) do
  # Existing users go directly to news
  redirect(conn, to: ~p"/news")
end
```

### First Scroll Popup Hook

```javascript
// assets/js/onboarding_popup.js
let OnboardingPopup = {
  mounted() {
    if (this.el.dataset.showPopup !== "true") return;

    let hasScrolled = false;
    const scrollThreshold = 0.2; // 20% scroll depth

    window.addEventListener('scroll', () => {
      if (hasScrolled) return;

      const scrollPercent = window.scrollY / (document.body.scrollHeight - window.innerHeight);
      if (scrollPercent >= scrollThreshold) {
        hasScrolled = true;
        this.pushEvent("show_onboarding_popup", {});
      }
    }, { passive: true });
  }
}
```

---

## Mobile Considerations

### Screen Sizing
- All onboarding screens should be full-screen on mobile
- Buttons should be full-width with adequate touch targets (44px minimum)
- Progress indicators should be visible without scrolling

### Gestures
- Support swipe left/right to navigate between steps
- Pull down to dismiss popups (iOS pattern)

### Safe Areas
- Respect notch and home indicator on iOS
- Use `safe-area-inset-*` CSS properties

---

## Analytics Events

Track the following events for funnel analysis:

| Event | Properties |
|-------|------------|
| `onboarding_started` | `user_id`, `timestamp` |
| `onboarding_step_viewed` | `user_id`, `step_number`, `step_name` |
| `onboarding_step_completed` | `user_id`, `step_number`, `action` (connect/skip) |
| `onboarding_skipped` | `user_id`, `skipped_at_step` |
| `onboarding_completed` | `user_id`, `total_time_seconds`, `connections_made` |
| `onboarding_popup_shown` | `user_id`, `article_id` |
| `onboarding_popup_clicked` | `user_id`, `action` (complete/dismiss) |

---

## Success Metrics

- **Completion Rate**: % of users completing all 8 steps
- **Profile Completion Rate**: % of users connecting phone + wallet + X
- **Skip Recovery Rate**: % of skipped users who complete profile via popup
- **Time to Complete**: Average time from start to finish
- **Drop-off Points**: Identify which steps have highest abandonment

---

## Future Enhancements

1. **Personalized Welcome**: Use referral source to customize messaging
2. **Achievement Badges**: Award badges for completing onboarding
3. **Re-engagement**: Email/push reminders for incomplete profiles
4. **A/B Testing**: Test different copy, visuals, and step order
5. **Gamification**: Add progress rewards (small BUX bonus for each step)

---

## Implementation Progress

**Status**: In Progress (Phases 1-3 Complete)
**Last Updated**: February 8, 2026

---

## Implementation Checklist

### Phase 1: Backend Setup ✅ COMPLETE

- [x] **1.1 Earning Power Display**
  - [x] Use existing `BlocksterV2.UnifiedMultiplier` module (already implemented)
  - [x] Call `UnifiedMultiplier.get_user_multipliers(user_id)` for breakdown
  - [x] Display `overall_multiplier` as earning power
  - [x] No new backend code needed - multiplier system already exists

**Implementation Notes (Phase 1)**:
- `UnifiedMultiplier` module located at `lib/blockster_v2/unified_multiplier.ex`
- Key function: `get_user_multipliers(user_id)` returns map with:
  - `x_score`, `x_multiplier`, `phone_multiplier`, `rogue_multiplier`, `wallet_multiplier`, `overall_multiplier`
- `max_overall()` returns maximum potential multiplier (360.0)
- No changes required - module was already fully implemented

---

### Phase 2: Routing & Navigation ✅ COMPLETE

- [x] **2.1 Router Configuration**
  - [x] Add onboarding routes to `lib/blockster_v2_web/router.ex`
  - [x] Create `/onboarding` base route (redirects to `/onboarding/welcome`)
  - [x] Create `/onboarding/:step` dynamic route
  - [x] Ensure routes require authentication

- [x] **2.2 Signup Flow Integration**
  - [x] Modify signup success handler
  - [x] After successful signup → redirect to `/onboarding` (not `/news`)
  - [x] Normal login flow unchanged → goes to `/news`

**Implementation Notes (Phase 2)**:
- Routes added to `router.ex` before the `:default` live_session (lines 91-96)
- Uses dedicated `:onboarding` layout (no header/footer) via `layout: {BlocksterV2Web.Layouts, :onboarding}`
- Layout file: `lib/blockster_v2_web/components/layouts/onboarding.html.heex`
- Only `UserAuth` hook mounted (no BuxBalanceHook, SearchHook)
- Signup redirect modified in `assets/js/home_hooks.js` in BOTH `authenticateEmail` AND `authenticateWallet` functions
- Auth API returns `is_new_user: true/false` flag - used to determine redirect target
- New users → `/onboarding`, returning users → `/member/{smart_wallet_address}`
- **Bug Fix (Feb 8, 2026)**: Wallet auth was missing `is_new_user` - fixed in `accounts.ex` and `auth_controller.ex`
- **Bug Fix (Feb 8, 2026)**: "Cannot bind multiple views" error - created dedicated `:onboarding` layout instead of using `:root` directly

---

### Phase 3: LiveView Implementation ✅ COMPLETE

- [x] **3.1 Create LiveView Structure**
  - [x] Create directory: `lib/blockster_v2_web/live/onboarding_live/`
  - [x] Create main LiveView: `index.ex`
  - [x] Implement `mount/3` with step detection from URL params
  - [x] Implement `handle_params/3` for step navigation
  - [x] Add assigns: `current_step`, `total_steps`, `user`, `earning_power`

- [x] **3.2 Step 1: Welcome Template**
  - [x] Create `welcome.html.heex` (inline in index.ex as function component)
  - [x] Add Blockster logo with pulse animation
  - [x] Add headline: "Welcome to Blockster"
  - [x] Add subheadline: "Read, watch and share daily stories to earn BUX"
  - [x] Add "Next" button with `phx-click="next_step"`
  - [x] Style with modern minimal design system

- [x] **3.3 Step 2: Redeem Template**
  - [x] Create `redeem.html.heex` (inline in index.ex as function component)
  - [x] Add 3 category icons (Shop, Games, Drops)
  - [x] Add staggered fade-in animation for icons
  - [x] Add headline: "Redeem Your BUX"
  - [x] Add subheadline: "Cool merch, games and airdrops"
  - [x] Add "Next" button

- [x] **3.4 Step 3: Profile Prompt Template**
  - [x] Create `profile.html.heex` (inline in index.ex as function component)
  - [x] Add multiplier visualization (current → potential using `UnifiedMultiplier`)
  - [x] Add animated arrow between multipliers
  - [x] Add headline: "Complete Your Profile"
  - [x] Add "Let's Go" primary button
  - [x] Add "I'll do this later" secondary link
  - [x] Implement skip logic: set session flag for popup, redirect to `/`

- [x] **3.5 Step 4: Connect Phone Template**
  - [x] Create `phone.html.heex` (inline in index.ex as function component)
  - [x] Add step indicator: "Step 1 of 3"
  - [x] Add phone icon
  - [x] Add multiplier preview (0.5x unverified → up to 2.0x verified)
  - [x] Add phone input with country code dropdown
  - [x] Add "Send Code" button → switches to verification input
  - [x] Add 6-digit code input field (appears after sending)
  - [x] Add "Verify" button
  - [x] Add "Skip for now" link
  - [x] Implement phone verification logic (reuse existing if available)

- [x] **3.6 Step 5: Connect Wallet Template**
  - [x] Create `wallet.html.heex` (inline in index.ex as function component)
  - [x] Add step indicator: "Step 2 of 3"
  - [x] Add wallet icon
  - [x] Add "Connect Wallet" button
  - [x] Integrate Thirdweb connect modal trigger
  - [x] Add success state showing abbreviated wallet address
  - [x] Add "Skip for now" link
  - [x] Handle wallet connection callback

- [x] **3.7 Step 6: Connect X Template**
  - [x] Create `x.html.heex` (inline in index.ex as function component)
  - [x] Add step indicator: "Step 3 of 3"
  - [x] Add X logo
  - [x] Add multiplier info: "Up to 10.0x multiplier" (based on X quality score)
  - [x] Add "Connect X" button
  - [x] Trigger X OAuth flow on click
  - [x] Add "Skip for now" link
  - [x] Handle OAuth callback and X score calculation

- [x] **3.8 Step 7: Complete Template**
  - [x] Create `complete.html.heex` (inline in index.ex as function component)
  - [x] Add checkmark icon with success animation
  - [x] Add headline: "You're All Set!"
  - [x] Add large multiplier display (e.g., "2.5x")
  - [x] Add breakdown list of connected items with bonuses
  - [x] Show skipped items in gray with potential bonus
  - [x] Add "Start Earning" button
  - [x] No database tracking needed - onboarding is complete once user reaches this step

- [x] **3.9 Step 8: ROGUE Upsell Template**
  - [x] Create `rogue.html.heex` (inline in index.ex as function component)
  - [x] Add ROGUE token icon with glow effect
  - [x] Add headline: "Psst... Want to Earn More?"
  - [x] Add benefits list (3 items)
  - [x] Add "Learn More" button (opens ROGUE page in new tab)
  - [x] Add "Maybe Later" link
  - [x] Both CTAs redirect to `/`

**Implementation Notes (Phase 3)**:
- All 8 step templates implemented as function components in `index.ex` (not separate .heex files)
- Step order: welcome → redeem → profile → phone → wallet → x → complete → rogue
- Progress dots component implemented inline as `progress_dots/1`
- Multiplier data fetched via `UnifiedMultiplier.get_user_multipliers(user.id)` on mount
- Phone verification uses `phone_state` assign with states: `:input`, `:code_sent`, `:verified`
- Wallet connection triggers Thirdweb modal via `phx-click` JS command
- X connection redirects to existing OAuth flow at `/auth/x`
- Skip actions navigate to next step or redirect to `/` (news page)
- Animations added to `app.css`: `animate-fade-in`, `animate-scale-in`

---

### Phase 4: Progress Indicator Component ✅ COMPLETE (merged into Phase 3)

- [x] **4.1 Create Progress Component**
  - [x] ~~Create `lib/blockster_v2_web/components/onboarding_components.ex`~~ (implemented inline)
  - [x] Implement `progress_dots/1` function component
  - [x] Accept `current_step` and `total_steps` assigns
  - [x] Render filled black dot for current step
  - [x] Render filled green dots for completed steps
  - [x] Render gray outline dots for future steps
  - [x] Add to all onboarding templates

**Implementation Notes (Phase 4)**:
- Progress dots implemented as `progress_dots/1` function component directly in `index.ex`
- Each step template includes `<.progress_dots current={@step_number} total={8} />`
- Styling: completed = green fill, current = black fill, future = gray outline

---

### Phase 5: First Scroll Popup ✅ COMPLETE

- [x] **5.1 Create Popup Component**
  - [x] Created popup template inline in `show.html.heex`
  - [x] Style as bottom sheet (mobile) / floating card (desktop)
  - [x] Add headline: "Boost Your Earnings!"
  - [x] Add dynamic multiplier display from `UnifiedMultiplier`
  - [x] Add "Complete Profile" button linking to `/onboarding`
  - [x] Add close button (X) and "Maybe Later" dismiss link

- [x] **5.2 Create JavaScript Hook**
  - [x] Created `OnboardingPopup` hook inline in `assets/js/app.js`
  - [x] Detect scroll depth (20% threshold)
  - [x] Push `show_onboarding_popup` event to LiveView
  - [x] Uses `sessionStorage` to ensure popup only shows once per session
  - [x] Registered hook in liveSocket hooks object

- [x] **5.3 Integrate with Post LiveView**
  - [x] Modified `lib/blockster_v2_web/live/post_live/show.ex`
  - [x] Added `assign_onboarding_popup_eligible/1` helper function
  - [x] Added assigns: `show_onboarding_popup`, `onboarding_popup_eligible`, `onboarding_popup_multiplier`
  - [x] Added `phx-hook="OnboardingPopup"` wrapper div in template
  - [x] Added `show_onboarding_popup` and `dismiss_onboarding_popup` event handlers

**Implementation Notes (Phase 5)**:
- Popup eligibility checks if user is logged in AND has incomplete profile:
  - `phone_verified == false` OR
  - No external wallet connected (`auth_method != "wallet"` AND `wallet_multiplier <= 1.0`) OR
  - No X account connected (`x_connection == nil`)
- **Important**: Checks for external wallet connection, NOT smart_wallet_address (which is auto-generated for email users)
- Uses `UnifiedMultiplier.get_user_multipliers(user.id)` to get current multiplier for display
- Popup component includes ROGUE glow animation on token icon
- Responsive design: `animate-slide-up` for mobile, `animate-fade-in-bottom-right` for desktop

---

### Phase 6: Styling & Animations ✅ COMPLETE

- [x] **6.1 CSS Setup**
  - [x] Add onboarding-specific styles to `assets/css/app.css`
  - [x] Button hover states use Tailwind classes: `hover:bg-[#CAFC00] hover:text-black`
  - [x] Progress dot styles implemented with inline Tailwind
  - [x] Define animation keyframes (pulse, fade-in, slide-up, rogue-glow)

- [x] **6.2 Animations**
  - [x] Logo pulse animation on Step 1
  - [x] Staggered icon fade-in on Step 2
  - [x] Arrow bounce animation on Step 3
  - [x] Success checkmark animation on Step 7
  - [x] ROGUE glow effect on Step 8 (`animate-rogue-glow` class)
  - [x] Popup slide-up animation (`animate-slide-up` for mobile)
  - [x] Popup fade-in animation (`animate-fade-in-bottom-right` for desktop)

- [ ] **6.3 Responsive Design** (needs testing)
  - [ ] Test on mobile viewport (375px width)
  - [ ] Test on tablet viewport (768px width)
  - [ ] Test on desktop viewport (1024px+ width)
  - [ ] Ensure buttons are full-width on mobile
  - [ ] Verify touch targets are 44px+ height

**Implementation Notes (Phase 6)**:
- Added CSS animations to `assets/css/app.css`:
  ```css
  @keyframes slide-up { from { opacity: 0; transform: translateY(100%); } to { opacity: 1; transform: translateY(0); } }
  @keyframes fade-in-bottom-right { from { opacity: 0; transform: translate(20px, 20px); } to { opacity: 1; transform: translate(0, 0); } }
  @keyframes rogue-glow { 0%, 100% { box-shadow: 0 0 20px rgba(202, 252, 0, 0.3), 0 0 40px rgba(202, 252, 0, 0.1); } 50% { box-shadow: 0 0 30px rgba(202, 252, 0, 0.5), 0 0 60px rgba(202, 252, 0, 0.2); } }
  ```
- ROGUE glow added to both:
  - OnboardingLive Step 8 (rogue_step component at line 697)
  - Onboarding popup in PostLive.Show
- Inline Tailwind used for most styling in templates

---

### Phase 7: Integration Testing ⏳ PENDING

- [ ] **7.1 Happy Path Testing**
  - [ ] New user signup → redirects to onboarding
  - [ ] Complete all 8 steps with all connections
  - [ ] Verify redirect to /news after completion
  - [ ] Verify earning power calculation is correct
  - [ ] Existing user login → goes directly to /news (no onboarding)

- [ ] **7.2 Skip Flow Testing**
  - [ ] Click "I'll do this later" on Step 3
  - [ ] Verify redirect to /news
  - [ ] Open first article, scroll 20%+
  - [ ] Verify popup appears (once per session)
  - [ ] Click "Complete Profile" → verify redirect to /onboarding/phone
  - [ ] Dismiss popup → verify it doesn't reappear in same session

- [ ] **7.3 Partial Completion Testing**
  - [ ] Skip phone → verify multiplier reflects this
  - [ ] Skip wallet → verify can still proceed
  - [ ] Skip X → verify multiplier reflects this
  - [ ] Complete some, skip others → verify breakdown is accurate

- [ ] **7.4 Edge Cases**
  - [ ] Browser refresh mid-onboarding → resumes at correct step
  - [ ] Browser back button → navigates to previous step
  - [ ] Direct URL access to step → handles gracefully
  - [ ] Already completed user visits /onboarding → redirect to /news
  - [ ] Phone verification timeout → proper error handling
  - [ ] Wallet connection failure → proper error handling
  - [ ] X OAuth failure → proper error handling

---

### Phase 8: Analytics Integration ⏳ PENDING

- [ ] **8.1 Event Tracking Setup**
  - [ ] Choose analytics provider (Mixpanel, Amplitude, or custom)
  - [ ] Create analytics helper module
  - [ ] Define event schemas

- [ ] **8.2 Implement Event Tracking**
  - [ ] Track `onboarding_started` on Step 1 mount
  - [ ] Track `onboarding_step_viewed` on each step mount
  - [ ] Track `onboarding_step_completed` on each next/skip action
  - [ ] Track `onboarding_skipped` when user clicks "I'll do this later"
  - [ ] Track `onboarding_completed` on Step 8 completion
  - [ ] Track `onboarding_popup_shown` when popup displays
  - [ ] Track `onboarding_popup_clicked` on popup CTA/dismiss

---

### Phase 9: Deployment ⏳ PENDING

- [ ] **9.1 Pre-deployment**
  - [ ] Run all tests locally
  - [ ] Test full flow on staging
  - [ ] Verify existing users are unaffected (login goes to /news)
  - [ ] Verify new signups redirect to /onboarding

- [ ] **9.2 Production Deployment**
  - [ ] Deploy code changes (no database migration needed)
  - [ ] Monitor error logs for issues
  - [ ] Verify analytics events are firing
  - [ ] Test with a new user account

- [ ] **9.3 Post-deployment**
  - [ ] Monitor onboarding completion rates
  - [ ] Check for drop-off points
  - [ ] Gather user feedback
  - [ ] Plan iterations based on data

---

### Phase 10: Documentation ⏳ PENDING

- [ ] **10.1 Code Documentation**
  - [ ] Add module docs to OnboardingLive
  - [ ] Document earning power calculation logic
  - [ ] Document skip flow and popup trigger logic

- [ ] **10.2 Update CLAUDE.md**
  - [ ] Add onboarding routes to "Common Routes" section
  - [ ] Document signup redirect behavior
  - [ ] Add any session learnings

---

## Estimated Timeline

| Phase | Description | Estimated Time |
|-------|-------------|----------------|
| 1 | Backend Setup | 1-2 hours |
| 2 | Routing & Navigation | 1 hour |
| 3 | LiveView Implementation | 6-8 hours |
| 4 | Progress Indicator | 1 hour |
| 5 | First Scroll Popup | 2-3 hours |
| 6 | Styling & Animations | 3-4 hours |
| 7 | Integration Testing | 2-3 hours |
| 8 | Analytics Integration | 1-2 hours |
| 9 | Deployment | 1-2 hours |
| 10 | Documentation | 1 hour |
| **Total** | | **19-27 hours**
