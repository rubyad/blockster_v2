# Legacy Account Reclaim Plan

Migration from EVM/email-based auth to Solana wallet-based auth. After deploy, every existing Blockster user will reconnect with a Solana wallet, which creates a brand-new user row. This document specifies how those new rows reclaim ownership of identifiers (phone, email, X, Telegram) and BUX balances that already belong to legacy user rows.

---

## Goal

When a user who was previously active on Blockster connects a Solana wallet:

1. **Onboarding starts with an "are you migrating?" branch.** If they say yes, the email/migration step runs first; on a successful match the merge fires and they fast-forward past any onboarding steps already filled by the merge.
2. At each onboarding step (phone, email, X), if the identifier they provide is already attached to a legacy user, **transfer ownership** from the legacy user to the new user.
3. **Email verification is the trigger for a full account merge**: when a verified email matches a legacy user, transfer everything (BUX balance, username, X, Telegram, phone) and mark the legacy user inactive.
4. **Telegram reclaim** happens in the Telegram connect handler (Telegram is not part of onboarding — it's connected later from profile/settings), so the unique-constraint fix is needed there too.
5. Engagement and rewards history (`user_post_engagement`, `user_post_rewards`) is **not** transferred — the new user starts fresh on engagement.
6. Username can be transferred to the new user (legacy user gets a placeholder).
7. The legacy user's BUX balance is **minted to the new Solana wallet** as fresh SPL BUX.

---

## Background: The Unique-Constraint Problem

After the Solana auth migration, every legacy user reconnects with a Solana wallet, which creates a new `users` row (Solana base58 address ≠ legacy EVM hex address, so `get_or_create_user_by_wallet` finds nothing and creates a fresh row). Onboarding then tries to write the user's existing identifiers, which collide with the legacy row's:

| Identifier | Where it's set | Storage | Unique Constraint | Failure |
|---|---|---|---|---|
| Phone | Onboarding phone step | `phone_verifications.phone_number` | `phone_verifications_phone_number_unique` | Insert blocked |
| Email | Onboarding email step (or new "migrate" step) | `users.email` | `users_email_index` | Update blocked |
| X | Onboarding X step | `x_connections.x_user_id` | `x_connections_x_user_id_index` | Insert blocked |
| Telegram | Telegram connect handler (NOT in onboarding — set from profile/settings later) | `users.telegram_user_id` | `users_telegram_user_id_index` | Update blocked |

Plus secondary collisions when the new user tries to take the legacy username:

- `users.username` unique
- `users.slug` unique

**Onboarding steps today** (`@steps` in `lib/blockster_v2_web/live/onboarding_live/index.ex`):

```
welcome → redeem → profile → phone → email → x → complete
```

Telegram is not in this list — it's connected later from a separate UI surface (likely profile/settings). The Telegram reclaim logic still needs to be implemented in the Telegram connect handler so the unique constraint doesn't block returning users when they reconnect Telegram post-onboarding.

---

## Approach Summary

Three pieces:

1. **Onboarding migration branch**: the welcome step asks "new or returning?". Returning users go to a new `migrate_email` step that verifies their old email and triggers the full merge if it matches. They then fast-forward through any onboarding step the merge already filled.

2. **Per-step reclaim** (phone / X / Telegram): when the user proves ownership of an identifier already held by a legacy user, **transfer the row** (or fields) from legacy → new. The legacy user keeps everything else. No full merge. This is the safety net for users who skipped the migration branch and for Telegram (which is connected outside onboarding).

3. **Email full-merge** (triggered when a verified email matches a legacy user, either in `migrate_email` or in the regular `email` step): perform reclaim of every identifier the legacy user owns (BUX, username, X, Telegram, phone — anything not already held by the new user), then **deactivate** the legacy user (`is_active = false`, NULL out unique fields, set `merged_into_user_id` pointer).

Why email is the trigger and not phone/X/Telegram:

- Email is the canonical Blockster identity. Users without verified phones or X/Telegram still have email. The legacy BUX snapshot is keyed by email.
- Phone reclaims happen at the phone step. Doing the full merge on phone-match would mean we merge before the user has even told us their email — which is fine but means the merge can happen multiple times (once on phone, again on email if the legacy account differs). Restricting full merge to email keeps it deterministic.
- A separate phone reclaim step still removes the unique-constraint conflict, so the user can complete phone verification even if they never verify their email.

---

## Onboarding UX Flow (with Migration Branch)

### Today's flow

```
welcome → redeem → profile → phone → email → x → complete
```

A migrating user under this flow would do phone reclaim (wasted effort), then hit email and trigger the full merge, then land on the X step with X already connected (confusing). We need to reorder.

### New flow

```
welcome → [migrate?] → redeem → profile → phone → email → x → complete
                ↓
       [migrate_email]
                ↓
   on match: full merge → fast-forward to first unfilled step
   on no-match: continue normal flow at next step (email already verified)
```

A new step `migrate_email` is inserted between `welcome` and `redeem`. The `welcome` step adds a branch question:

> **Welcome to Blockster.**
>
> Are you new here, or migrating from an existing Blockster account?
>
> [ I'm new ]    [ I have an account ]

### Branch behavior

**"I'm new"** → goes to `redeem` (the existing flow). No migration logic touched.

**"I have an account"** → goes to `migrate_email`:

1. User enters their old Blockster email.
2. We send a 6-digit code to that email (same `EmailVerification.send_verification_code` path, but writing to `users.pending_email`).
3. User enters the code.
4. On valid code:
   - Look up legacy user by email (`Repo.get_by(User, email: <email>, is_active: true)`).
   - **If a legacy user is found** → call `LegacyMerge.merge_legacy_into!(new_user, legacy_user)` → all transferable fields move over → BUX is minted to the new Solana wallet → legacy is deactivated → user is shown a "Welcome back" success card with a summary (X BUX claimed, phone restored, X account restored, Telegram restored, etc.) → fast-forward to first unfilled onboarding step (see below).
   - **If no legacy user is found** → the email is still verified for the new user (treat the verified email as their new email). Show a friendly "No legacy account found, but your email is verified" message → continue to the next normal step (`redeem`), then proceed through the rest of onboarding **but skip the email step** (already complete).

### Intent-based branching, not gated

The branch is on user **intent**, not on whether they actually have a legacy account. The user clicks "I have an account" because they think they do. We don't pre-check anything — they enter their email, we verify it, then we look up. Even if there's no match, the verified email is theirs and we keep going.

This means: a user who misremembers their old email, or who never had a legacy account but clicks "I have an account" by mistake, still has a productive outcome (their email gets verified) and isn't punished. They just continue with normal onboarding.

### Fast-forward / skip-completed-steps logic after merge

After a successful merge, walk the new user's state and skip any onboarding step that's already filled by what was transferred:

| Step | Skip if |
|---|---|
| `redeem` | Never skip (informational, useful even for returning users) |
| `profile` | Skip if `username` is set on the new user (it will be, after username transfer) |
| `phone` | Skip if `phone_verified = true` on the new user |
| `email` | Always skip (just verified in `migrate_email`) |
| `x` | Skip if a row in `x_connections` exists for the new user_id |
| `complete` | Always shown — it displays the final earning power summary |

A legacy user who had **everything** connected (username, phone, email, X) lands on: `migrate_email → complete`. Two screens.

A legacy user who had **only email + phone** lands on: `migrate_email → redeem → profile → x → complete`. (Profile because no username; X because X wasn't connected before.)

A legacy user who had **only email** lands on: `migrate_email → redeem → profile → phone → x → complete`.

### Skip logic for users who say "I'm new" but actually merge later

A user who clicks "I'm new" but turns out to be a legacy user will hit the email step in the normal flow. The merge fires there (correctness preserved). At that point we should ALSO apply the same skip-completed-steps logic — if the email merge transfers an X connection, the next step (`x`) should be skipped.

This means the "skip filled steps" rule needs to fire at every step transition for any user, not just inside the migrate branch. Implement as a `next_step/1` helper that walks `@steps` from `current_step + 1` and returns the first one that isn't filled by the user's current state.

### Schema impact

Add `migrate_email` to `@steps` in `lib/blockster_v2_web/live/onboarding_live/index.ex`:

```elixir
@steps ["welcome", "migrate_email", "redeem", "profile", "phone", "email", "x", "complete"]
```

The `migrate_email` step is shown only if the user clicked "I have an account" on welcome. If they clicked "I'm new", route directly from `welcome → redeem` (skip `migrate_email`).

Track the choice in socket assigns: `assign(socket, :migration_intent, :new | :returning)` based on the welcome button click.

### Welcome step UI changes

The welcome step needs the two-button branch. Add to `welcome.html.heex` (or wherever the step content lives — likely inline in `index.html.heex`).

Event handler:
```elixir
def handle_event("set_migration_intent", %{"intent" => intent}, socket) do
  intent_atom = String.to_existing_atom(intent)
  next_step = if intent_atom == :returning, do: "migrate_email", else: "redeem"

  {:noreply,
   socket
   |> assign(:migration_intent, intent_atom)
   |> push_patch(to: ~p"/onboarding/#{next_step}")}
end
```

### Migrate_email step UI

A new step file (e.g., `migrate_email.html.heex` or inline) with two phases:

1. **Enter email**: input field, submit button. Wires to a `send_migration_code` event that calls `EmailVerification.send_verification_code(new_user, email)` (which writes `pending_email`).
2. **Enter code**: 6-digit code input, submit button. Wires to a `verify_migration_code` event that calls `EmailVerification.verify_code/2` — which internally checks for legacy match and dispatches to `LegacyMerge.merge_legacy_into!` if found.

After successful verification:
- If merge happened → render a success card showing transferred items + BUX amount → continue button routes to the next unfilled step.
- If no legacy match → render a "Email verified, no legacy account found" message → continue button routes to `redeem`.

---

## Schema Changes

### `users` table — add deactivation fields

```elixir
defmodule BlocksterV2.Repo.Migrations.AddLegacyDeactivationFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_active, :boolean, default: true, null: false
      add :merged_into_user_id, references(:users, on_delete: :nilify_all)
      add :deactivated_at, :utc_datetime
      add :pending_email, :string  # email being verified (before final write)
    end

    create index(:users, [:merged_into_user_id])
    create index(:users, [:is_active])
  end
end
```

- `is_active`: false on deactivated legacy rows. All user lookups (auth, profile, member pages, etc.) must filter on `is_active = true`.
- `merged_into_user_id`: pointer to the new Solana user that absorbed this legacy account. Audit trail + lets us redirect old member URLs.
- `deactivated_at`: timestamp.
- `pending_email`: holds the email being verified before we can safely write it to `email`. Avoids the unique-constraint collision during the verify step (see Email Reclaim Flow below).

### Why not delete legacy rows?

- Legacy users have authored posts (`posts.author_id`), organized events, comments, etc. Deleting cascades and orphans content.
- Soft-deactivate + null unique fields is the cleanest fix:
  - `email = nil` (PG allows multiple NULL in unique index)
  - `telegram_user_id = nil`
  - `telegram_username = nil`
  - `username = "deactivated_<id>"` (only if username was transferred)
  - `slug = "deactivated-<id>"` (only if username was transferred)
  - `smart_wallet_address = nil` (clean up legacy EVM smart wallet)
- Phone and X rows don't allow NULL on the constrained columns, so we **delete** those rows on the legacy side after copying / transferring. This is safe because the legacy user is being deactivated.

---

## Detailed Flow Per Step

### 1. Phone Reclaim

**Trigger**: user submits phone number in the phone step (`PhoneVerification.send_verification_code`).

**Current code path**: `PhoneVerification.send_verification_code` → calls Twilio → on success creates a row in `phone_verifications`.

**New behavior**:

1. Before sending Twilio code, look up `phone_verifications` by `phone_number`.
2. If a row exists for a **different user_id** (the legacy user):
   - Send the Twilio verification code as normal.
   - Mark the **new** user's pending verification: temporarily store the phone number on the new user (no DB collision because we don't write to `phone_verifications` yet — keep it in memory or in a transient store, e.g., reuse the existing `phone_verifications` row by atomically updating its `user_id` AFTER successful code verification).
3. When the user submits the SMS code (`PhoneVerification.verify_code`):
   - On success, in a transaction:
     - Delete the legacy user's `phone_verifications` row (if any) — actually, simpler: **transfer** it by `UPDATE phone_verifications SET user_id = <new_user_id>, attempts = 0, verified_at = NOW() WHERE phone_number = <phone>`. This avoids deleting/recreating.
     - Set `users.phone_verified = false` and reset `geo_multiplier`/`geo_tier` to defaults on the **legacy** user (since they no longer own the phone).
     - Set `users.phone_verified = true`, copy `geo_multiplier` and `geo_tier` from the transferred row to the new user.
     - Trigger `UnifiedMultiplier.refresh_multipliers(new_user.id)`.

**Edge case — no existing phone**: identical to today's flow. Insert new row.

**Edge case — same user**: already verified. No-op or "already verified" flash message.

### 2. Email Verification + Full Merge

**Trigger**: user submits email in onboarding email step (`EmailVerification.send_verification_code`).

**Current code path**: writes `users.email = <email>` immediately, sends code. Fails on unique constraint if email exists on a legacy user.

**New behavior**:

1. **Send code phase** (`send_verification_code`):
   - Do NOT write `users.email` yet. Write to `users.pending_email = <email>`.
   - Write `email_verification_code` and `email_verification_sent_at` as today.
   - Send the code email.
2. **Verify code phase** (`verify_code`):
   - Validate code as today.
   - Look up legacy user: `Repo.get_by(User, email: <email>, is_active: true)` — must be a different user_id than the new user.
   - If a legacy user is found → **call `LegacyMerge.merge_legacy_into!(new_user, legacy_user)`** (see Full Merge Function below).
   - If no legacy user found → just set `users.email = pending_email`, `users.email_verified = true`, `users.pending_email = nil`, clear verification fields.
   - Trigger `UnifiedMultiplier.update_email_multiplier(new_user.id)`.

**Why `pending_email` instead of writing email immediately**:

The cleanest alternative is to use a separate `pending_email_verifications` table (like phone_verifications). `pending_email` on the user row is simpler: one extra nullable column, no new table, scoped to the in-flight verification. The downside is one user can only verify one email at a time — which is the desired behavior anyway.

### 3. X Reclaim

**Trigger**: user clicks "Connect X" → OAuth redirect → callback inserts/updates `x_connections`.

**Current code path**: OAuth callback creates `x_connections` row keyed on `user_id`, with unique `x_user_id`. Insert fails if `x_user_id` is already taken by a legacy user.

**New behavior** (in the OAuth callback):

1. Look up existing `x_connections` row by `x_user_id` returned from the OAuth response.
2. If a row exists for a **different user_id**:
   - **Transfer** the row: `UPDATE x_connections SET user_id = <new_user_id>, access_token_encrypted = <new_token>, refresh_token_encrypted = <new_token>, connected_at = NOW() WHERE x_user_id = <id>`.
   - Refresh tokens and score with the new OAuth response.
   - Trigger any X-related side effects (e.g., recompute `x_score` if needed).
3. If no row exists → normal insert.
4. If a row exists for the **same** user_id → normal update.

**Why transfer instead of delete + insert**: preserves `x_score`, follower counts, and `score_calculated_at` so we don't have to refetch them. The data is about the X account itself, not the user who connected it.

### 4. Telegram Reclaim

**Trigger**: Telegram OAuth/widget callback writes `users.telegram_user_id` etc.

**Current code path**: writes telegram fields directly to the new user's row. Unique constraint on `telegram_user_id` fails if already held by a legacy user.

**New behavior**:

1. In the Telegram connect handler, before writing to the new user, look up `Repo.get_by(User, telegram_user_id: <tg_id>)`.
2. If a different user holds it (legacy user):
   - In a transaction:
     - NULL out `telegram_user_id`, `telegram_username`, `telegram_connect_token`, `telegram_connected_at`, `telegram_group_joined_at` on the legacy user.
     - Set those same fields on the new user (copying values from the OAuth response).
3. If no one holds it → normal insert.
4. If the same user holds it → no-op (already connected).

---

## Full Merge Function

```elixir
defmodule BlocksterV2.Migration.LegacyMerge do
  @moduledoc """
  Merges a legacy (EVM/email-auth) user into a new Solana-auth user.

  Triggered when a new user verifies an email that matches a legacy user.
  Transfers BUX, username, X, Telegram, phone (if not already held by new user),
  then deactivates the legacy user.

  Engagement history (user_post_engagement, user_post_rewards) is NOT transferred.
  """

  alias BlocksterV2.{Repo, BuxMinter}
  alias BlocksterV2.Accounts.{User, PhoneVerification}
  alias BlocksterV2.Social.XConnection
  alias BlocksterV2.Migration.{LegacyBux, LegacyBuxMigration}
  import Ecto.Query
  require Logger

  def merge_legacy_into!(new_user, legacy_user) do
    Repo.transaction(fn ->
      # 1. Deactivate legacy user FIRST (NULLs out unique fields so subsequent
      #    transfers don't collide on email/username/slug/telegram_user_id)
      legacy_user = deactivate_legacy_user(legacy_user, new_user.id)

      # 2. Mint legacy BUX to new Solana wallet (see BUX Claim Mechanism below)
      maybe_claim_legacy_bux(new_user, legacy_user)

      # 3. Transfer username + slug (legacy slot is now free)
      maybe_transfer_username(new_user, legacy_user)

      # 4. Transfer X connection (if legacy has it and new doesn't)
      maybe_transfer_x_connection(new_user, legacy_user)

      # 5. Transfer Telegram (if legacy has it and new doesn't)
      #    NOTE: deactivate_legacy_user already nulled telegram_user_id on legacy,
      #    so we just need to copy the values to the new user
      maybe_transfer_telegram(new_user, legacy_user)

      # 6. Transfer phone (if legacy has it and new doesn't)
      maybe_transfer_phone(new_user, legacy_user)

      # 7. Transfer content authorship & social FKs (posts, events, follows, orders)
      transfer_content_and_social_fks(new_user, legacy_user)

      # 8. Transfer referrals (inbound + outbound + affiliate attribution)
      transfer_referrals(new_user, legacy_user)

      # 9. Transfer device fingerprints (data continuity only — not used by Solana auth)
      transfer_fingerprints(new_user, legacy_user)

      # 10. Set new user's email + email_verified
      finalize_new_user_email(new_user)
    end)
    |> case do
      {:ok, _} ->
        BlocksterV2.UnifiedMultiplier.refresh_multipliers(new_user.id)
        {:ok, Repo.get!(User, new_user.id)}
      {:error, reason} ->
        Logger.error("[LegacyMerge] Failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Detailed implementations spec'd below in their own sections.
end
```

### Step 1: BUX claim

See "BUX Claim Mechanism" section below.

### Step 2: Transfer username

```elixir
defp maybe_transfer_username(new_user, legacy_user) do
  if legacy_user.username && legacy_user.username != "" do
    # Generate placeholder for legacy user. We do this in deactivate_legacy_user
    # by setting username = "deactivated_<id>" — here we just stage the new user.
    new_username = legacy_user.username
    new_slug = legacy_user.slug

    Repo.update!(Ecto.Changeset.change(new_user, %{
      username: new_username,
      slug: new_slug
    }))
  end
end
```

The legacy user's `username` and `slug` are NULLed/replaced inside `deactivate_legacy_user` (next step) so that the unique constraints don't collide. Order matters: deactivate FIRST so the unique slot is freed, THEN transfer to the new user. Will adjust the call order in the implementation.

### Step 3: Transfer X connection

```elixir
defp maybe_transfer_x_connection(new_user, legacy_user) do
  legacy_x = Repo.get_by(XConnection, user_id: legacy_user.id)
  new_x = Repo.get_by(XConnection, user_id: new_user.id)

  cond do
    legacy_x && is_nil(new_x) ->
      legacy_x
      |> Ecto.Changeset.change(%{user_id: new_user.id})
      |> Repo.update!()

    legacy_x && new_x ->
      # Both have an X connection — keep new user's, drop legacy's.
      # (Avoids unique_constraint(:user_id) conflict on transfer.)
      Repo.delete!(legacy_x)

    true -> :ok
  end
end
```

### Step 4: Transfer Telegram

```elixir
defp maybe_transfer_telegram(new_user, legacy_user) do
  if legacy_user.telegram_user_id && is_nil(new_user.telegram_user_id) do
    # NULL out on legacy first to free the unique constraint
    legacy_user
    |> Ecto.Changeset.change(%{
      telegram_user_id: nil,
      telegram_username: nil,
      telegram_connect_token: nil,
      telegram_connected_at: nil,
      telegram_group_joined_at: nil
    })
    |> Repo.update!()

    new_user
    |> Ecto.Changeset.change(%{
      telegram_user_id: legacy_user.telegram_user_id,
      telegram_username: legacy_user.telegram_username,
      telegram_connect_token: nil,  # don't carry over the one-shot token
      telegram_connected_at: legacy_user.telegram_connected_at,
      telegram_group_joined_at: legacy_user.telegram_group_joined_at
    })
    |> Repo.update!()
  end
end
```

### Step 5: Transfer phone

```elixir
defp maybe_transfer_phone(new_user, legacy_user) do
  legacy_phone = Repo.get_by(PhoneVerification, user_id: legacy_user.id)
  new_phone = Repo.get_by(PhoneVerification, user_id: new_user.id)

  if legacy_phone && is_nil(new_phone) do
    # Transfer the phone_verifications row
    legacy_phone
    |> Ecto.Changeset.change(%{user_id: new_user.id})
    |> Repo.update!()

    # Sync user-level phone fields
    new_user
    |> Ecto.Changeset.change(%{
      phone_verified: true,
      geo_multiplier: legacy_phone.geo_multiplier,
      geo_tier: legacy_phone.geo_tier
    })
    |> Repo.update!()

    # Clear them on legacy
    legacy_user
    |> Ecto.Changeset.change(%{
      phone_verified: false,
      geo_multiplier: Decimal.new("0.5"),
      geo_tier: "unverified"
    })
    |> Repo.update!()
  end
end
```

### Step 5b: Transfer content authorship & social FKs (Option A — bulk FK rewrite)

Blockster is a content platform, so the legacy user's authored posts and other public-facing content must show the new user as the owner. We do this in the merge transaction by running bulk UPDATE statements that rewrite every user FK from legacy → new.

```elixir
defp transfer_content_and_social_fks(new_user, legacy_user) do
  legacy_id = legacy_user.id
  new_id = new_user.id

  # Posts authored by legacy user → reassign to new user
  Repo.update_all(
    from(p in BlocksterV2.Blog.Post, where: p.author_id == ^legacy_id),
    set: [author_id: new_id]
  )

  # Events organized by legacy user
  Repo.update_all(
    from(e in BlocksterV2.Events.Event, where: e.organizer_id == ^legacy_id),
    set: [organizer_id: new_id]
  )

  # Event attendance
  Repo.update_all(
    from(ea in "event_attendees", where: ea.user_id == ^legacy_id),
    set: [user_id: new_id]
  )

  # Hub follows
  Repo.update_all(
    from(hf in "hub_followers", where: hf.user_id == ^legacy_id),
    set: [user_id: new_id]
  )

  # Order history (commerce)
  Repo.update_all(
    from(o in BlocksterV2.Orders.Order, where: o.user_id == ^legacy_id),
    set: [user_id: new_id]
  )
end
```

### Step 5c: Transfer referrals

Two directions:

1. **Legacy user's referrer** (who referred them) → copy onto the new user
2. **Legacy user's referees** (who they referred) → reassign to point at the new user
3. **Affiliate / order attribution** (`orders.referrer_id`, `affiliate_payouts.referrer_id`) → reassign so commissions follow the new user

```elixir
defp transfer_referrals(new_user, legacy_user) do
  legacy_id = legacy_user.id
  new_id = new_user.id

  # 1. Inbound referrer: legacy was referred by X → new user is now referred by X
  if legacy_user.referrer_id && is_nil(new_user.referrer_id) do
    new_user
    |> Ecto.Changeset.change(%{
      referrer_id: legacy_user.referrer_id,
      referred_at: legacy_user.referred_at
    })
    |> Repo.update!()
  end

  # 2. Outbound referees: anyone the legacy user referred now points at the new user
  Repo.update_all(
    from(u in User, where: u.referrer_id == ^legacy_id),
    set: [referrer_id: new_id]
  )

  # 3. Order-level affiliate attribution (so commissions on legacy-referred orders flow to the new user)
  Repo.update_all(
    from(o in BlocksterV2.Orders.Order, where: o.referrer_id == ^legacy_id),
    set: [referrer_id: new_id]
  )

  # 4. Outstanding affiliate payouts owed to the legacy user
  Repo.update_all(
    from(p in BlocksterV2.Affiliates.AffiliatePayout, where: p.referrer_id == ^legacy_id),
    set: [referrer_id: new_id]
  )
end
```

### Step 5d: Transfer fingerprints

Legacy users have device fingerprints in `user_fingerprints` from anti-Sybil tracking. Transfer them so the new user inherits the device history.

```elixir
defp transfer_fingerprints(new_user, legacy_user) do
  Repo.update_all(
    from(f in UserFingerprint, where: f.user_id == ^legacy_user.id),
    set: [user_id: new_user.id]
  )
end
```

**Note on fingerprint blocking**: The fingerprint anti-Sybil check (`Accounts.authenticate_email_with_fingerprint`) only fires on the legacy EVM email-auth path (`AuthController.verify_email`), which is being deprecated by the Solana migration. The new Solana wallet auth path (`get_or_create_user_by_wallet`) does **not** check fingerprints. So fingerprint is already non-blocking in the new flow — we're transferring the rows purely for data continuity in case we re-enable the system later. **No additional code is needed to "make sure fingerprint is not blocking"** — it already isn't, by virtue of which auth path the new flow uses.

### Step 6: Finalize new user email

```elixir
defp finalize_new_user_email(new_user) do
  email = new_user.pending_email

  if email do
    new_user
    |> Ecto.Changeset.change(%{
      email: email,
      email_verified: true,
      pending_email: nil,
      email_verification_code: nil,
      email_verification_sent_at: nil
    })
    |> Repo.update!()
  end
end
```

This must happen AFTER `deactivate_legacy_user` (which NULLs `legacy_user.email`) so the unique constraint is free.

### Step 7: Deactivate legacy user

```elixir
defp deactivate_legacy_user(legacy_user, new_user_id) do
  legacy_user
  |> Ecto.Changeset.change(%{
    is_active: false,
    merged_into_user_id: new_user_id,
    deactivated_at: DateTime.utc_now() |> DateTime.truncate(:second),
    email: nil,
    legacy_email: legacy_user.email,  # preserve for audit
    username: "deactivated_#{legacy_user.id}",
    slug: "deactivated-#{legacy_user.id}",
    smart_wallet_address: nil,
    telegram_user_id: nil,
    telegram_username: nil,
    telegram_connect_token: nil
  })
  |> Repo.update!()
end
```

### Final ordering inside the transaction

```
1.  deactivate_legacy_user            # frees email/username/slug/telegram unique slots
2.  claim_legacy_bux                  # mint to new Solana wallet
3.  transfer_username                 # takes the freed username/slug
4.  transfer_x_connection
5.  transfer_telegram
6.  transfer_phone
7.  transfer_content_and_social_fks   # posts, events, follows, orders
8.  transfer_referrals                # inbound + outbound + affiliate attribution
9.  transfer_fingerprints             # data continuity only
10. finalize_new_user_email           # writes the email field
```

The deactivation runs FIRST so that all unique constraints (email, username, slug, telegram_user_id) are freed before we try to write any of them onto the new user. The BUX claim runs early so that if the settler call fails the rest of the transaction never executes (rollback is cheaper before we've done dozens of FK rewrites).

---

## BUX Claim Mechanism — How It Works End to End

The legacy BUX balance lives in two places:

1. **On Rogue Chain ERC-20 contract** at `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` — the on-chain source of truth. We can't directly transfer from there to Solana.
2. **`legacy_bux_migrations` Postgres table** — a snapshot of every user's on-chain BUX balance, taken at a fixed cutoff date. Keyed by lowercase email.

The flow:

### Pre-deploy: snapshot all legacy balances

The snapshot must run BEFORE deploy. For every legacy user with an email:

```elixir
LegacyBux.snapshot_user(user)
```

`snapshot_user/1` reads the user's BUX balance from `EngagementTracker.get_user_bux_balance/1` (which reads `user_bux_balances` Mnesia, which mirrors on-chain), and inserts a row into `legacy_bux_migrations`:

```
{
  email: "alice@x.com",
  legacy_bux_balance: 12345.67,
  legacy_wallet_address: "0xabc...",
  migrated: false,
  new_wallet_address: nil,
  mint_tx_signature: nil,
  migrated_at: nil
}
```

There's a `unique_constraint(:email)` on the table, so re-running the snapshot is idempotent (`on_conflict: :nothing`).

**Critical pre-deploy task**: run this snapshot for every legacy user with an email, ideally a few hours before the cutover so the data is fresh. There needs to be a script `mix run priv/scripts/snapshot_legacy_bux.exs` that walks every user and calls `snapshot_user`.

**Open question**: legacy users WITHOUT an email (wallet-only signups) are excluded from the snapshot. Their BUX is stranded unless we add an alternative claim path. See "Open Questions" below.

### During email merge: claim and mint

Inside `merge_legacy_into!`, the BUX claim logic:

```elixir
defp maybe_claim_legacy_bux(new_user, legacy_user) do
  # Look up the snapshot row by the legacy email
  email = legacy_user.email || legacy_user.legacy_email
  if is_nil(email), do: throw(:ok)

  case Repo.get_by(LegacyBuxMigration, email: String.downcase(email)) do
    nil ->
      # No snapshot row → nothing to claim
      :ok

    %LegacyBuxMigration{migrated: true} ->
      # Already claimed (defensive — shouldn't happen mid-merge)
      :ok

    %LegacyBuxMigration{legacy_bux_balance: bal} = migration when bal > 0 ->
      amount = Decimal.to_float(bal)

      case BuxMinter.mint_bux(
             new_user.wallet_address,
             amount,
             new_user.id,
             nil,
             :legacy_migration
           ) do
        {:ok, response} ->
          signature = response["signature"]
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          migration
          |> Ecto.Changeset.change(%{
            new_wallet_address: new_user.wallet_address,
            mint_tx_signature: signature,
            migrated: true,
            migrated_at: now
          })
          |> Repo.update!()

          Logger.info("[LegacyMerge] Minted #{amount} legacy BUX to #{new_user.wallet_address} (sig: #{signature})")

        {:error, reason} ->
          # Mint failed — rollback the whole transaction.
          # User can retry by re-verifying email (idempotent because migrated=false).
          Logger.error("[LegacyMerge] BUX mint failed: #{inspect(reason)}")
          Repo.rollback({:bux_mint_failed, reason})
      end

    _ ->
      :ok
  end
end
```

What `BuxMinter.mint_bux/5` does on Solana:

1. POSTs to the settler service `/mint` endpoint with `{wallet_address, amount, user_id, post_id, reward_type}`.
2. The settler builds and signs a Solana SPL token mint transaction using the mint authority keypair (`6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1`).
3. The settler submits the tx to QuickNode, polls `getSignatureStatuses` until confirmed, and returns `{"signature": "<solana tx sig>"}`.
4. The new SPL BUX tokens land in the user's Solana associated token account for the BUX mint (`7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX`).

After mint:
- `legacy_bux_migrations.migrated = true` (one-time, prevents double-claim).
- `legacy_bux_migrations.mint_tx_signature` = Solana tx for audit.
- `legacy_bux_migrations.new_wallet_address` = the Solana wallet that received it.

### What happens to the legacy on-chain ERC-20 balance?

It stays on Rogue Chain. We don't burn it or move it. The BUX ERC-20 contract is effectively decommissioned — once we've snapshotted, the on-chain balance is meaningless. If users still have access to their old smart wallet they can technically still see the tokens in a block explorer, but the Blockster app no longer reads from Rogue Chain so they can't use them on Blockster.

If you want to be tidy, a separate post-migration task can transfer all legacy BUX to a burn address using the contract owner key, but it's not required for correctness.

### Failure modes

| Failure | Effect |
|---|---|
| Settler mint call fails | Transaction rolls back. User sees an error, can retry by re-verifying the same code (within 10 min) or restarting the email step. `legacy_bux_migrations.migrated` stays false. |
| Settler returns success but no signature | Treat as failure, rollback. |
| Snapshot row missing | Merge proceeds without BUX claim. Logged as a warning. |
| Snapshot row stale (user earned BUX after snapshot) | The newer earnings are lost. Mitigation: take snapshot as close to deploy as possible. |
| Double-claim attempt (same email matched twice) | Blocked by `migrated = true` check. Returns no-op. |

---

## Files to Change

### New files

| File | Purpose |
|---|---|
| `priv/repo/migrations/<timestamp>_add_legacy_deactivation_fields.exs` | Adds `is_active`, `merged_into_user_id`, `deactivated_at`, `pending_email` to users table. |
| `lib/blockster_v2/migration/legacy_merge.ex` | The `LegacyMerge` module spec'd above. |
| `priv/scripts/snapshot_legacy_bux.exs` | One-time pre-deploy script to snapshot all legacy users with email into `legacy_bux_migrations`. |
| `test/blockster_v2/migration/legacy_merge_test.exs` | Tests for full merge logic. |

### Modified files

| File | Change |
|---|---|
| `lib/blockster_v2/accounts/user.ex` | Add `is_active`, `merged_into_user_id`, `deactivated_at`, `pending_email` schema fields. Add to changeset cast list. Add `unique_constraint(:slug)`. Add `is_active` filter helper or scope. |
| `lib/blockster_v2/accounts.ex` | Update `get_user_by_wallet_address/1`, `get_user_by_email/1`, `get_user_by_slug/1`, `get_user_by_smart_wallet_address/1`, etc. to filter `is_active = true`. Otherwise legacy rows can still match lookups. |
| `lib/blockster_v2/accounts/email_verification.ex` | `send_verification_code`: write `pending_email` instead of `email`. `verify_code`: detect legacy match and call `LegacyMerge.merge_legacy_into!`; otherwise just promote `pending_email` → `email`. |
| `lib/blockster_v2/accounts/phone_verification.ex` | In send/verify flow, detect existing `phone_verifications` row for a different user and transfer ownership on successful verification. |
| `lib/blockster_v2/social/x_connections.ex` (or wherever the OAuth callback writes) | On insert, check for existing row with same `x_user_id` for a different user and transfer it. |
| Telegram connect handler (need to find — likely `lib/blockster_v2_web/controllers/telegram_controller.ex` or similar) | Detect existing `telegram_user_id` on a different user and transfer fields. |
| `lib/blockster_v2_web/live/onboarding_live/index.ex` | Add `migrate_email` to `@steps`. Add `welcome` branch handler (`set_migration_intent`). Add `migrate_email` step handlers (`send_migration_code`, `verify_migration_code`). Add `next_unfilled_step/1` helper for skip-completed-steps logic. Surface merge result. |
| `lib/blockster_v2_web/live/onboarding_live/index.html.heex` (or step partials) | Add two-button welcome branch UI. Add `migrate_email` step UI (enter-email + enter-code phases + success/no-match cards). |
| `lib/blockster_v2_web/live/member_live/show.ex` and any user lookup that powers public profiles | Filter `is_active = true` and 301-redirect old slugs to `merged_into_user_id`'s new slug if applicable. |

### Files to verify (not necessarily change)

- Anywhere that does `Repo.get_by(User, ...)` or `from u in User, where: ...` — needs `is_active` filter, otherwise authenticated views can return deactivated users.
- Bot system: bots have `is_bot = true`. Make sure bots aren't accidentally deactivated. The merge target is always email-matched legacy users; bots have no email so they're naturally excluded, but worth a guard.
- Authoring: handled by Step 5b's `transfer_content_and_social_fks` — posts/events/follows/orders are bulk-rewritten to the new user_id at merge time, so views that load by `author_id`/`organizer_id`/`user_id` keep working without changes.

### Tables touched by FK rewrites in `transfer_content_and_social_fks` and `transfer_referrals`

Cross-reference list so we don't miss any in the implementation:

| Table | Column | Updated by |
|---|---|---|
| `posts` | `author_id` | content rewrite |
| `events` | `organizer_id` | content rewrite |
| `event_attendees` | `user_id` | content rewrite |
| `hub_followers` | `user_id` | content rewrite |
| `orders` | `user_id` | content rewrite |
| `orders` | `referrer_id` | referral rewrite |
| `affiliate_payouts` | `referrer_id` | referral rewrite |
| `users` | `referrer_id` | referral rewrite (legacy user's referees) |
| `users` (target row) | `referrer_id`, `referred_at` | referral copy (legacy → new user) |
| `user_fingerprints` | `user_id` | fingerprint rewrite |
| `phone_verifications` | `user_id` | phone reclaim |
| `x_connections` | `user_id` | X reclaim |

---

## Test Plan

### Unit tests — `LegacyMerge`

1. New user verifies email matching legacy user with BUX, username, X, Telegram, phone — every field transfers, BUX is minted, legacy is deactivated.
2. Same as above but new user already has X — legacy X is deleted, not transferred.
3. Same but new user already has phone — legacy phone stays on the legacy user (since it can't double-write); the deactivation step handles the row.
4. New user verifies email with no legacy match — normal flow, no merge.
5. Legacy user has no BUX snapshot row — merge proceeds, no mint.
6. Legacy user has zero BUX balance — merge proceeds, no mint call.
7. Settler mint fails — entire merge transaction rolls back, legacy still active, no FK rewrites happened.
8. Already-migrated `legacy_bux_migrations` row — no double mint.
9. Content rewrite: legacy user authored 5 posts → after merge, all 5 posts have `author_id = new_user.id`.
10. Content rewrite: legacy user organized 2 events → after merge, both have `organizer_id = new_user.id`.
11. Content rewrite: legacy user followed 3 hubs → all 3 `hub_followers` rows now point at new user.
12. Content rewrite: legacy user attended 1 event → `event_attendees` row updated.
13. Content rewrite: legacy user had 4 orders → all 4 `orders.user_id` updated.
14. Referral inbound: legacy user was referred by user X → after merge, `new_user.referrer_id == X` and `new_user.referred_at` matches legacy.
15. Referral inbound: legacy has no referrer → new user's referrer field unchanged (don't accidentally clear an existing one).
16. Referral inbound: new user already has a referrer → don't overwrite (the `is_nil(new_user.referrer_id)` guard).
17. Referral outbound: legacy user referred 3 other users → all 3 now have `referrer_id = new_user.id`.
18. Referral attribution: 2 orders have `referrer_id = legacy_id` → both updated to `new_user.id`.
19. Affiliate payouts: 1 unpaid `affiliate_payouts` row referencing legacy → updated.
20. Fingerprints: legacy user has 2 `user_fingerprints` rows → both transferred to new user.
21. Username collision precondition test: assert two active users can never both have username "alice".

### Unit tests — Phone Reclaim

1. New user verifies phone that's already on a legacy user — transfer succeeds, legacy phone fields cleared.
2. New user verifies a fresh phone — normal insert.
3. New user verifies a phone that's already on themselves — no-op.

### Unit tests — X Reclaim

1. New user OAuth-connects X account already linked to legacy user — row transferred, x_score preserved.
2. New user OAuth-connects fresh X account — normal insert.
3. New user already has an X account, OAuths a different one — old row replaced (current behavior, no change needed).

### Unit tests — Telegram Reclaim

1. New user connects Telegram already on legacy user — transfer succeeds, legacy telegram fields nulled.
2. New user connects fresh Telegram — normal write.

### Integration tests — Onboarding flow

**Migrate-branch happy path (everything connected)**:
1. Seed a legacy user with email, phone, X, Telegram, username, BUX snapshot row (1000 BUX).
2. Connect a Solana wallet (creates new user).
3. Click "I have an account" on welcome → `migrate_email` step.
4. Enter the legacy email → enter code.
5. Assert: legacy user `is_active = false`, new user has email/phone/X/Telegram/username, BUX mint called with 1000, `legacy_bux_migrations.migrated = true`.
6. Assert: next route is `/onboarding/complete` (every other step skipped).

**Migrate-branch partial (only email + phone on legacy)**:
1. Seed a legacy user with only email and phone (no X, no Telegram, no username).
2. Connect Solana wallet → click "I have an account" → migrate_email → verify.
3. Assert: phone transferred, email verified, BUX claimed (if any), legacy deactivated.
4. Assert: next route is `/onboarding/redeem`. Walk through `redeem → profile → x → complete` (phone and email skipped).

**Migrate-branch no-match (user clicks "I have an account" but email doesn't match)**:
1. New Solana wallet → click "I have an account" → enter random email → verify code.
2. Assert: new user's `email` is set to the entered value, `email_verified = true`, no merge fired.
3. Assert: next route is `/onboarding/redeem`. Walk normal flow but `email` step is skipped (already verified).

**"I'm new" path with hidden legacy match**:
1. Seed a legacy user with email + X.
2. New Solana wallet → click "I'm new" → walk normal flow → reach email step → enter the legacy email → verify.
3. Assert: merge fires here, X transferred, legacy deactivated.
4. Assert: next route after email step is `/onboarding/complete` (X step skipped because X just got transferred).

**"I'm new" brand-new user (no legacy)**:
1. New Solana wallet → "I'm new" → full normal flow → no merge anywhere.
2. Assert: every step shown, normal completion.

### Edge cases to test

- Two new users race to verify the same email → only one wins, the other gets a "migration already completed" or fresh-account error.
- New user enters legacy email, code expires, retries → `pending_email` still set, new code sent, retry works.
- New user enters legacy email, completes merge, then logs out and logs in with a different Solana wallet → can't merge again (legacy `is_active = false`, no longer matchable).
- Legacy user has `is_active = true` but `is_bot = true` — guard to skip bot accounts in merge.
- User clicks "I have an account" then changes mind → back button routes to welcome → choose "I'm new" → continues correctly.
- `next_unfilled_step/1` correctness: every combination of (phone_verified, email_verified, has_x, has_username) routes to the right next step.

---

## Pre-Deploy Checklist

1. Run migration: `mix ecto.migrate` (adds `is_active`, `merged_into_user_id`, `deactivated_at`, `pending_email` columns).
2. Run snapshot script: `mix run priv/scripts/snapshot_legacy_bux.exs` — populates `legacy_bux_migrations` for every legacy user with email and a non-zero BUX balance.
3. Verify snapshot count matches expectations: `Repo.aggregate(LegacyBuxMigration, :count) |> IO.inspect()`.
4. Verify mint authority on settler service has enough mint capacity (no quota limits).
5. Tag release.
6. Deploy.

After deploy, monitor for:
- Failed merges in logs (`[LegacyMerge] Failed`).
- Failed BUX mints (`[LegacyMerge] BUX mint failed`).
- Settler service errors / 5xx rate.
- User reports of "I can't verify my phone/email".

---

## Resolved Decisions

These were open questions in earlier drafts. Resolved with the user:

1. **Wallet-only legacy users (no email)** — N/A. There are no legacy users without email. Drop the question.
2. **Post authorship & member redirects** — implement now via Option A (bulk FK rewrite at merge time). Member URL redirects are not needed because slug transfer makes `/member/alice` resolve to the new active user automatically.
3. **Referrals** — transfer in both directions: copy legacy user's `referrer_id` onto new user, reassign anyone referred BY legacy user, reassign affiliate `orders.referrer_id` and `affiliate_payouts.referrer_id`.
4. **Username** — always transfer (legacy is deactivated, slot is freed).
5. **Settler downtime** — keep BUX mint synchronous inside the merge transaction. All-or-nothing semantics. User retries if it fails.
6. **Mnesia engagement/rewards/game state** — not transferred. Spec is "no engagement transfer." Game state and reading rewards stay orphaned on the legacy user_id.
7. **Fingerprints** — transfer for data continuity only. Already non-blocking in the new Solana auth flow (the fingerprint check only fires on the deprecated EVM email-auth path).
8. **Cross-account chaos (multiple legacy accounts matching different identifiers)** — accepted. Doesn't happen in practice.
9. **`pending_email` expiry** — handled by the existing resend logic. Overwriting pending_email is fine.

## Tables Explicitly NOT Transferred

| Table | Reason |
|---|---|
| `user_post_engagement` (Mnesia) | Engagement history — spec says no |
| `user_post_rewards` (Mnesia) | Rewards history — spec says no |
| `coin_flip_games` (Mnesia) | Game state — engagement-like |
| `user_sessions` | Legacy auth sessions are dead |
| `connected_wallets`, `wallet_transfers` | Legacy EVM wallet records — meaningless on Solana |
| `notifications`, `notification_email_log` | Inbox / engagement |
| `user_events` | Telemetry |
| `ab_tests` | Telemetry |
| `ad_attributions` | Engagement |
| `airdrop_entries`, `airdrop_winners` | Legacy on-chain airdrop state. Even if we updated the PG row, the on-chain entry is registered to the legacy EVM wallet, so the new Solana user can't claim it. Stranded by design. |
| `user_fingerprints` | **WAIT — this IS transferred (see Step 5d)**. Listed here for clarity that the decision was made; it's transferred for data continuity only, not because it's actively used. |

(Last row is intentionally a callout — not actually skipped.)

## Open Questions

None remaining. Ready to implement.

---

## Rollout Plan

1. Implement migration + schema changes (1 commit): adds `is_active`, `merged_into_user_id`, `deactivated_at`, `pending_email`.
2. Implement `LegacyMerge` module + tests, including all transfer steps (BUX, username, X, Telegram, phone, content/social FKs, referrals, fingerprints, deactivation) (1 commit).
3. Update `EmailVerification` to write `pending_email`, detect legacy match in `verify_code`, dispatch to `LegacyMerge` (1 commit).
4. Implement phone reclaim in `PhoneVerification` + tests (1 commit).
5. Implement X reclaim in the X OAuth callback + tests (1 commit).
6. Implement Telegram reclaim in the Telegram connect handler + tests (1 commit).
7. Update `Accounts` lookups to filter `is_active = true` (1 commit).
8. Add `migrate_email` step + welcome branch UI + `next_unfilled_step/1` skip logic in `OnboardingLive.Index` + tests (1 commit).
9. Run snapshot script in production (one-off task — must be done within hours of deploy so balances are fresh).
10. Deploy.

Each commit should leave the test suite green.
