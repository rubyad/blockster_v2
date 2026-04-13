# Onboarding flow · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/onboarding_live/index.ex` |
| Route(s) | `/onboarding`, `/onboarding/:step` |
| Mock file | **None** — design from DS spec per decision D11 |
| Bucket | **B** — visual refresh of multi-step wizard with branching; no schema changes |
| Wave | 6 (Page #19 — last page of the redesign release) |

## Layout decision

**Keep the `:onboarding` live_session and layout.** The onboarding flow is
intentionally distraction-free — no site header, no footer, no wallet modal, no
toast notifications. The `:redesign` layout includes `wallet_selector_modal` and
`NotificationToastHook` which are unnecessary during onboarding (the user already
has a wallet connected). The `:onboarding` layout (`<main class="min-h-screen">` +
flash) remains the right choice. The only visual change is applying DS color tokens
and typography to the template content.

## Page structure (top to bottom)

The onboarding is an 8-step wizard rendered in a single LiveView. Each step is a
`defp` component. The outer shell provides the progress indicator and centering.

### Outer shell

1. **Background**: `bg-[#fafaf9]` (DS eggshell) instead of plain `bg-white`
2. **Progress bar**: Segmented horizontal bar at top (replaces dot indicators).
   Each segment corresponds to one of the 8 steps. Filled segments use
   `bg-[#0a0a0a]`, current segment pulses, unfilled use `bg-neutral-200`.
3. **Step content**: Centered column, `max-w-md`, vertically centered with
   flexbox. Each step renders inside a white `rounded-2xl` card with subtle
   shadow.

### Per-step design

All steps share these patterns:
- **Icon box**: `w-14 h-14 bg-[#CAFC00] rounded-2xl` with `w-7 h-7 text-black` icon
- **Heading**: `text-[26px] font-bold tracking-[-0.022em] text-[#141414]`
- **Body text**: `text-[15px] text-[#6B7280] leading-relaxed`
- **Primary button**: `bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl hover:bg-[#1a1a22]`
- **Secondary button**: `bg-[#f5f5f4] text-[#141414] font-medium py-3.5 rounded-xl`
- **Skip link**: `text-[13px] text-[#9CA3AF] hover:text-[#6B7280]`
- **Inputs**: `bg-white border border-neutral-200 rounded-xl px-4 py-3 focus:ring-2 focus:ring-[#0a0a0a] focus:border-transparent`
- **Error alert**: `bg-red-50 border border-red-200 text-red-700 rounded-xl`
- **Success alert**: `bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-xl`
- **Verified badge**: `bg-emerald-50 border border-emerald-200 rounded-full` with green checkmark
- **Step indicator**: Eyebrow pattern — `text-[10px] font-bold tracking-[0.16em] uppercase text-[#9CA3AF]`
- **Multiplier display**: White card, `rounded-xl`, label left + mono value right

#### Step 1: Welcome
- Blockster icon with subtle animation
- "Welcome to Blockster" heading
- "Are you new here, or migrating from an existing Blockster account?" body
- Two buttons: "I'm new" (primary dark) + "I have an account" (secondary)

#### Step 2: Migrate email (conditional — "I have an account" branch)
- "Welcome back" eyebrow
- Email icon in lime box
- "Restore your account" heading
- Three sub-states: enter_email → enter_code → success (with merge summary)
- "I don't have an account" fallback link

#### Step 3: Redeem
- Three icon cards in a row (Shop, Games, Airdrop) with staggered fade-in
- "Redeem BUX" heading
- "Next" button

#### Step 4: Profile
- "Earn up to 20x more BUX" heading with lime highlight
- "Let's Go" primary + "I'll do this later" skip

#### Step 5: Phone
- "Step 1 of 3" eyebrow
- Phone icon in lime box
- Three sub-states: enter_phone → enter_code → success
- PhoneNumberFormatter hook preserved
- SMS opt-in checkbox preserved

#### Step 6: Email
- "Step 2 of 3" eyebrow
- Email icon in lime box
- Three sub-states: enter_email → enter_code → success
- Pre-populated email address preserved

#### Step 7: X
- "Step 3 of 3" eyebrow
- X logo (𝕏) in lime box
- Connect or Skip

#### Step 8: Complete
- Green checkmark animation
- "You're All Set!" heading
- Large multiplier display in lime box
- 4-row breakdown checklist (Phone, Email, SOL, X)
- "Start Earning BUX" primary CTA

## Decisions applied from release plan

- **Bucket B**: multi-step wizard with branching paths, but no schema changes,
  no new contexts, no new on-chain calls.
- **Route stays on `:onboarding` live_session**: intentionally distraction-free
  (no DS header/footer, no wallet modal). See layout decision above.
- **Legacy preservation**: copy current file to
  `lib/blockster_v2_web/live/onboarding_live/legacy/index_pre_redesign.ex`
- **No new DS components needed** — all visual elements use existing DS patterns
  (eyebrow-style text, card patterns, button patterns) via inline Tailwind.
  The onboarding doesn't use `<.header>`, `<.footer>`, `<.chip>`, etc.
- **No new schema migrations.**
- **All handlers preserved exactly** — every `handle_event` and `handle_info`
  callback stays, no behavior changes.
- **JS hooks preserved**: `PhoneNumberFormatter` on phone input.
- **Onboarding modal component (`onboarding_modal.ex`) is NOT touched** — it's a
  separate component used in a different context (post-wallet-connect modal) and
  is not part of this redesign scope.

## Visual components consumed

No DS components imported — the onboarding flow uses its own minimal layout
(no header/footer) and inline Tailwind utilities following DS color/typography
tokens.

**No new DS components needed.**

## Data dependencies

### ✓ Existing — already in production

- `@current_user` — from UserAuth on_mount
- `@user` — full user record
- `@multipliers` — UnifiedMultiplier struct (overall, phone, email, sol, x_score, x_multiplier)
- `@current_step` — string, one of 8 step names
- `@step_index` — 0-based index in @steps
- `@total_steps` — 8
- `@migration_intent` — :new | :returning | nil
- `@phone_step_state` — :enter_phone | :enter_code | :success
- `@phone_number`, `@phone_error`, `@phone_success`, `@phone_countdown`
- `@verification_result`, `@phone_country_code`
- `@email_step_state` — :enter_email | :enter_code | :success
- `@email_address`, `@email_error`, `@email_success`, `@email_countdown`
- `@migrate_email_step_state` — :enter_email | :enter_code | :success
- `@migrate_email_address`, `@migrate_email_error`, `@migrate_email_success`, `@migrate_email_countdown`
- `@merge_summary` — map with bux_claimed, username_transferred, etc.

### ✗ Removed assigns

None. All existing assigns preserved.

### ✗ New — must be added or schema-migrated

None. Bucket B (visual only).

## Handlers to preserve

### handle_event

- `"set_migration_intent"` — branches welcome step. **Preserved.**
- `"submit_phone"` — sends phone verification code. **Preserved.**
- `"submit_code"` — verifies phone code. **Preserved.**
- `"resend_code"` — resends phone code. **Preserved.**
- `"change_phone"` — resets to phone entry. **Preserved.**
- `"submit_email"` — sends email verification code. **Preserved.**
- `"submit_email_code"` — verifies email code. **Preserved.**
- `"resend_email_code"` — resends email code. **Preserved.**
- `"change_email"` — resets to email entry. **Preserved.**
- `"send_migration_code"` — sends migration email code. **Preserved.**
- `"verify_migration_code"` — verifies migration code, triggers merge. **Preserved.**
- `"resend_migration_code"` — resends migration code. **Preserved.**
- `"change_migration_email"` — resets migration email entry. **Preserved.**
- `"continue_after_merge"` — navigates to next unfilled step. **Preserved.**

### handle_info

- `{:countdown_tick, remaining}` — phone resend countdown. **Preserved.**
- `{:email_countdown_tick, remaining}` — email resend countdown. **Preserved.**
- `{:migrate_countdown_tick, remaining}` — migration resend countdown. **Preserved.**
- `{:email, _swoosh_email}` — Swoosh test adapter message. **Preserved.**

### Helper functions

- `next_unfilled_step/2` — public, used by tests. **Preserved.**
- `step_unfilled?/2` — private, step completion checks. **Preserved.**
- `format_multiplier/1` — private, multiplier display. **Preserved.**
- `format_phone_display/1` — private, phone formatting. **Preserved.**
- `step_title/1` — private, page title mapping. **Preserved.**

## JS hooks

- **`PhoneNumberFormatter`** — on phone number input. **Preserved.**
- No new JS hooks.

## Tests required

### Component tests

None — no new DS components.

### LiveView tests

**Extend** `test/blockster_v2_web/live/onboarding_live_test.exs`.

**New assertions:**

- **Progress bar renders**: assert segmented progress indicator present
- **Welcome step renders with DS styling**: assert heading "Welcome to Blockster"
- **Welcome buttons use correct DS button styles**: assert both branch buttons
- **Redeem step renders icons**: assert Shop, Games, Airdrop labels
- **Phone step renders with eyebrow**: assert "STEP 1 OF 3"
- **Email step renders with eyebrow**: assert "STEP 2 OF 3"
- **X step renders with eyebrow**: assert "STEP 3 OF 3"
- **Complete step renders multiplier display**: assert "BUX Earning Power"
- **Complete step shows breakdown checklist**: assert "Phone", "Email", "SOL", "X"
- **Anonymous access redirects**: assert redirect for unauthenticated user

**Existing tests preserved:**
- Welcome step branching (3 tests)
- migrate_email step — no legacy match (1 test)
- migrate_email step — full legacy merge (1 test)
- next_unfilled_step/2 unit tests (4 tests)

### Manual checks (on `bin/dev`)

- All 8 steps render correctly for logged-in user
- Anonymous user gets redirected
- Progress bar advances with each step
- "I'm new" path: welcome → redeem → profile → phone → email → x → complete
- "I have an account" path: welcome → migrate_email → (merge) → next unfilled
- Phone verification: enter → code → success
- Email verification: enter → code → success
- Skip links work on every step that has them
- Already-verified states show correctly
- Multiplier values display properly on complete step
- PhoneNumberFormatter hook works on phone input
- No console errors
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(onboarding): onboarding flow refresh · DS color tokens + typography + card patterns + segmented progress bar`

## Stubbed in v1

None. The onboarding flow is fully functional — all steps, branching, and
verification flows work end-to-end. No placeholders needed.

## Open items

None. This is the last page of the redesign release.
