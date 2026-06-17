# Airdrop System

How the Blockster V2 airdrop works end-to-end: an on-chain, provably-fair **entry-pool
lottery**. Users spend ("redeem") BUX to buy sequential entry positions in an open round;
when the round closes, 33 winners are drawn from a revealed server seed + the Solana slot
at close, and winners claim SOL/SPL prizes from a per-round on-chain vault.

> **This is NOT an allocation airdrop.** Eligibility is *not* derived from multiplier,
> engagement score, holdings, or referrals. It is a lottery you buy entries into with BUX,
> and the only entry gate is **phone-verified + connected Solana wallet**.

## Architecture at a glance

```
 Admin (IEx)          Elixir main app                Settler (Node)          Solana (Anchor: blockster-airdrop)
┌──────────┐  create  ┌──────────────────┐   HMAC    ┌────────────────┐      ┌───────────────────────────────┐
│create_   │ ───────► │ Airdrop.*        │ ────────► │ airdrop-       │ ───► │ AirdropState (singleton)       │
│round/2   │          │ Airdrop.Settler  │  REST     │ service.ts     │ sign │ AirdropRound[ ]  (per round)   │
└──────────┘          │ (GenServer timer)│           │ routes/        │ by   │ prize_vault[ ]   (per round)   │
                      └──────────────────┘           │ airdrop.ts     │ 6b4n │ AirdropEntry[ ]  (per deposit) │
 User (LiveView /airdrop) ── BUX redeem / claim ───► │                │      └───────────────────────────────┘
                                                     └────────────────┘
```

Authority/fee-payer for all admin txs = `MINT_AUTHORITY` (`6b4n…`). Users sign their own
`deposit_bux` and `claim_prize` txs client-side.

## Key files

| Layer | Files |
|---|---|
| On-chain program | `contracts/blockster-airdrop/` (Anchor Rust + IDL — **build output, not in this branch**; see note below) |
| Settler tx builders | `contracts/blockster-settler/src/services/airdrop-service.ts`, `routes/airdrop.ts`, `scripts/init-airdrop.ts` |
| Settler infra | `contracts/blockster-settler/src/{config.ts,index.ts,middleware/hmac-auth.ts,services/rpc-client.ts}` |
| IDL cross-check (test) | `contracts/blockster-settler/tests/idl-consistency.test.ts` |
| Elixir core | `lib/blockster_v2/airdrop.ex`, `airdrop/{settler,round,entry,winner}.ex`, `provably_fair.ex` |
| Elixir client + supervision | `lib/blockster_v2/bux_minter.ex`, `application.ex` |
| Web | `lib/blockster_v2_web/router.ex`, `live/airdrop_live.ex`, `assets/js/hooks/airdrop_solana.js` |
| Addresses / plan | `docs/addresses.md`, `docs/solana_migration_plan.md` |

> **Sourcing note.** The Anchor program's Rust source and compiled IDL are **not checked
> into this branch** (`contracts/blockster-airdrop/**` is a build output that lives on the
> build machine). Everything below about the on-chain *wire format* — instruction names,
> discriminators, PDA seeds, account orderings, byte layouts — is taken from the settler's
> TypeScript client and is **independently asserted against the real IDL** by
> `tests/idl-consistency.test.ts` (discriminators `:223-250`, seeds `:308-325`, account
> counts `:643-692`, program address `:733-739`). What is **not** readable here: the Rust
> `#[derive(Accounts)]` constraints, handler bodies, and the error enum — claims about
> program-internal validation are flagged as inferred in [§ Uncertainties](#uncertainties).

---

## 1. On-chain program

### 1.1 Identity

| Item | Value | Source |
|---|---|---|
| Program ID (devnet & mainnet) | `wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG` | `config.ts:31-34`, `docs/addresses.md:69,116` |
| Env override | `AIRDROP_PROGRAM_ID` | `config.ts:32`, `init-airdrop.ts:44` |
| Devnet `AirdropState` PDA | `8xoz8FsdkBCP4TMguoG5t2zCqEHYYXg38ZLk7iyzaAmj` | `docs/addresses.md:88-91` |
| Entry token (BUX mint) | `7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX`, 9 decimals | `config.ts:21-24,96` |

### 1.2 Multi-round model

- One global singleton **`AirdropState`** (seed `["airdrop"]`) holds a monotonic
  `current_round_id` counter, the `authority`, the `bux_mint`, and the `treasury`.
- Each round is its own **`AirdropRound`** PDA (seed `["round", round_id u64 LE]`), with its
  own **`prize_vault`** PDA (seed `["prize_vault", round_id u64 LE]`).
- The program allocates the next round id itself (`current_round_id + 1`); the client never
  supplies it (`airdrop-service.ts:282-285`).
- Round status enum: `0 = open`, `1 = closed`, `2 = drawn` (`airdrop-service.ts:142-146`).

### 1.3 PDAs (IDL-verified seeds)

| PDA | Seeds | Source |
|---|---|---|
| `AirdropState` (singleton) | `["airdrop"]` | `airdrop-service.ts:35,44-49` |
| `AirdropRound` (per round) | `["round", round_id u64 LE]` | `:36,57-62` |
| `AirdropEntry` (per deposit) | `["entry", round_id u64 LE, depositor Pubkey, entry_index u64 LE]` | `:37,64-78` |
| `prize_vault` (per round) | `["prize_vault", round_id u64 LE]` | `:38,80-87` |

Round ids and entry indices are encoded **8-byte little-endian** (`roundIdToBuffer`,
`airdrop-service.ts:51-55`).

### 1.4 Instructions (8, IDL-verified)

`initialize`, `start_round`, `deposit_bux`, `fund_prizes`, `close_round`, `draw_winners`,
`claim_prize`, `withdraw_unclaimed` (roster asserted at `idl-consistency.test.ts:212-221`;
discriminators at `airdrop-service.ts:254-263`).

| Instruction | Signer | Built/called by | Notes |
|---|---|---|---|
| `initialize` | authority | `scripts/init-airdrop.ts` (one-time) | creates `AirdropState`; no Elixir caller |
| `start_round` | `MINT_AUTHORITY` | settler `/airdrop-start-round` | args: `commitment_hash[32]`, `end_time i64`; round id auto-assigned |
| `deposit_bux` | **user wallet** | settler builds unsigned, user signs | args: `round_id`, `entry_index`, `amount`; BUX → treasury ATA |
| `fund_prizes` | `MINT_AUTHORITY` | settler `/airdrop-fund-prizes` | moves SOL/SPL into `prize_vault` |
| `close_round` | `MINT_AUTHORITY` | settler `/airdrop-close` | captures `slot_at_close`, status → closed |
| `draw_winners` | `MINT_AUTHORITY` | settler `/airdrop-draw-winners` | reveals `server_seed`, writes winners[], status → drawn |
| `claim_prize` | **winner wallet** | settler builds unsigned, winner signs | args: `round_id`, `winner_index u8`; pays from vault, flips `claimed` |
| `withdraw_unclaimed` | — | **no builder/route/caller** | discriminator known; behavior unverified (likely authority sweep) |

### 1.5 Claim & eligibility mechanism

**Admin-signed on-chain allocation list — NOT a Merkle proof, NOT a per-user allocation
PDA, NOT signature-gating.**

1. The authority computes the 33 winners off-chain and writes them into the round via
   `draw_winners`: a fixed `winners: [WinnerInfo; 33]` array, each
   `{ wallet, amount, claimed }` (`airdrop-service.ts:135-137, 452-460`).
2. To claim, a winner submits `claim_prize` with their **`winner_index`** (the positional
   slot in that array) (`airdrop-service.ts:571-575`).
3. Entitlement is proven by **being the signer whose pubkey equals
   `round.winners[winner_index].wallet`**; the amount paid is that slot's `amount`.

**Double-claim prevention = inline per-winner `claimed: bool`** inside the round account.
A successful claim flips `winners[winner_index].claimed = true`; a second claim at the same
index fails. **There is no bitmap PDA and no claim-receipt PDA** — claimed state lives in
the round's fixed array (`airdrop-service.ts:136,197,580`).

### 1.6 Token handling

- **Entries are BUX**, and flow **depositor ATA → treasury ATA** (not into the prize vault)
  (`airdrop-service.ts:527-528`). Treasury = `AirdropState.treasury` (in dev = authority).
- **Prizes can be SOL or any SPL** (`docs/addresses.md:69`). Sentinel: `prize_mint ==
  SystemProgram (11111…111)` means SOL (`airdrop-service.ts:567-569`).
- **Prize escrow = per-round `prize_vault` PDA.** SOL is held as lamports on the PDA; SPL is
  held in the PDA-owned ATA `getAssociatedTokenAddress(prize_mint, prize_vault, true)`.
- **Prizes are funded upfront** by the authority via `fund_prizes`
  (`docs/solana_migration_plan.md:133`).

### 1.7 Provably-fair design (on-chain)

1. `start_round` commits `commitment_hash = SHA256(server_seed)` + `end_time`.
2. `close_round` records `slot_at_close` — public, unpredictable-at-commit entropy — and
   freezes entries.
3. `draw_winners` **reveals** `server_seed` on-chain so anyone can verify
   `SHA256(server_seed) == commitment_hash` (`airdrop-service.ts:184-186,447`).

---

## 2. Settler service

All airdrop logic is in `routes/airdrop.ts` (HTTP) + `services/airdrop-service.ts`
(tx-building). The airdrop router mounts **after** `hmacAuth` (`index.ts:40,47`), so every
endpoint is HMAC-authenticated (only `GET /health` is exempt).

### 2.1 Endpoints (`routes/airdrop.ts`)

| Route | Method | Instruction | Signed by | Returns |
|---|---|---|---|---|
| `/airdrop-start-round` | POST | `start_round` | settler | `{roundId, transactionHash}` |
| `/airdrop-fund-prizes` | POST | `fund_prizes` | settler | `{transactionHash}` |
| `/airdrop-close` | POST | `close_round` | settler | `{transactionHash, slotAtClose}` |
| `/airdrop-draw-winners` | POST | `draw_winners` | settler | `{transactionHash}` |
| `/airdrop-build-deposit` | POST | `deposit_bux` (**unsigned, base64**) | user (client) | `{transaction}` |
| `/airdrop-build-claim` | POST | `claim_prize` (**unsigned, base64**) | user (client) | `{transaction}` |
| `/airdrop-vault-round-id` | GET | reads `current_round_id` | — | `{roundId}` |
| `/airdrop-round-info/:roundId` | GET | reads round PDA | — | full round data |
| `/airdrop-state` | GET | reads `AirdropState` | — | state data |

The two `build-*` endpoints serialize with `{requireAllSignatures: false,
verifySignatures: false}` and `feePayer = user`, returning base64 — the settler **does not
sign or submit** them. There is **no Merkle/allocation generation** in the settler; winner
selection happens in the Elixir app and is pushed via `/airdrop-draw-winners`.

### 2.2 Auth & confirmation

- **HMAC** (`hmac-auth.ts`): requires `x-signature` + `x-timestamp`; 5-minute freshness
  window (`Math.abs(now - ts) > 300 → 401`, `:28-32`); timing-safe compare over `rawBody`;
  `API_SECRET === "dev-secret"` bypasses in dev.
- **Confirmation** (`rpc-client.ts:39-63`): `getSignatureStatuses` polling, default
  `timeoutMs 60_000` / `pollIntervalMs 1_000` — no websockets, no rebroadcast. Authority
  txs use `feePayer = MINT_AUTHORITY` and `sendRawTransaction({maxRetries: 5})`.

### 2.3 Config (`config.ts`)

`AIRDROP_PROGRAM_ID`, `MINT_AUTHORITY_KEYPAIR` (authority + fee payer, `6b4n…`),
`BUX_MINT_ADDRESS`, `SOLANA_RPC_URL`, `SETTLER_API_SECRET`, `BUX_DECIMALS = 9`. There are
**no airdrop-specific env vars** beyond `AIRDROP_PROGRAM_ID`.

---

## 3. Elixir orchestration

### 3.1 Web surface

- Route: `live "/airdrop", AirdropLive, :index` in the `:redesign` live_session
  (`router.ex:198`). **No admin gate, no feature flag** — reachable by any visitor.
- `BlocksterV2Web.AirdropLive` (`airdrop_live.ex`) serves **both** the BUX-redeem (entry)
  flow and the winner-claim flow. There is **no separate admin LiveView** — round creation
  is programmatic (IEx/`rpc`).

### 3.2 Entry eligibility & the entry-pool model

**1 BUX = 1 entry position.** Users buy contiguous position blocks; 33 winners are drawn
from positions. Entry guards (`airdrop_live.ex:133-150`, re-validated server-side in
`airdrop.ex:242-252`):

1. logged-in user, 2. **`phone_verified`**, 3. connected Solana `wallet_address`,
4. round `status == "open"`, 5. `amount > 0`, 6. `amount <= user_bux_balance`.

`create_entry/4` (`airdrop.ex:455-502`): deducts Mnesia BUX **first** via
`EngagementTracker.deduct_user_token_balance/4`, then inside a `Repo.transaction` locks the
round row `FOR UPDATE`, computes `start_position = total_entries + 1`,
`end_position = total_entries + amount`, inserts the `Entry`, and bumps
`round.total_entries`.

### 3.3 Prize structure

```elixir
# airdrop.ex:15-24
@num_winners 33
@prize_structure %{0 => 25_000, 1 => 15_000, 2 => 10_000}  # USD cents: $250 / $150 / $100
@default_prize_usd 5_000                                    # 4th–33rd = $50 each
# Total prize pool = $2,000
```

> ⚠️ **Denomination caveat.** `draw_on_chain/2` submits each winner's on-chain
> `WinnerInfo.amount` as the **USD-cent integer** (`amount: w.prize_usd`,
> `airdrop/settler.ex:156-159`), e.g. `25_000`. There is no code in this workspace
> converting USD cents to lamports/SPL raw units for winner amounts, and **no Elixir caller
> wires `fund_prizes`**. How the funded vault denomination reconciles with the USD-cent
> winner amounts at claim time is not determinable from the readable code — see
> [Uncertainties](#uncertainties).

### 3.4 Winner selection (provably-fair, off-chain compute)

`derive_winners/4` (`airdrop.ex:504-557`):

1. `combined_seed = SHA256(server_seed_bytes <> slot_bytes)`, where the slot is encoded
   **little-endian 64-bit** (`:533-540, 567-577`).
2. For `i <- 0..32`: `hash = SHA256(combined_seed <> <<i::unsigned-big-integer-size(256)>>)`,
   then `position = rem(value, total_entries) + 1` (`:542-551`).
3. `find_entry_for_position` maps each position into its entry block
   (`start_position <= position <= end_position`).

The 33 `Winner` rows are bulk-inserted in a `Repo.transaction` by `draw_winners/2`
(`airdrop.ex:205-224`), which also flips the round to `"drawn"`. The moduledoc claims this
mirrors the on-chain derivation (`airdrop.ex:178-184`); the on-chain side stores the
authority-submitted list (the program may or may not re-verify — see Uncertainties).

### 3.5 Round lifecycle GenServer

`BlocksterV2.Airdrop.Settler` (`airdrop/settler.ex`) — a **GlobalSingleton**
(cluster-wide), started in the supervision tree under the `:start_genservers` branch
(`application.ex:71-72`; off in test). It is **timer-driven, not a poller**: at round
creation it schedules `Process.send_after(self(), {:settle, round_id}, delay_ms)` for
`end_time`.

On boot, `recover_from_db/1` compares the DB max `round_id` against
`BuxMinter.airdrop_get_vault_round_id()` (logs sync/ahead/behind), then settles `closed`
rounds now, settles `open` rounds past `end_time` now, schedules `open` future rounds, and
waits on `drawn`. The settle pipeline:

- `open` → `airdrop_close` → `Airdrop.close_round` (stores slot in `block_hash_at_close`) →
  recurse on the now-closed round.
- `closed` → `Airdrop.draw_winners` (local draw + DB insert) → `draw_on_chain` (non-blocking
  `airdrop_draw_winners`) → PubSub `{:airdrop_drawn}` on `airdrop:<round_id>` → a `Task`
  re-broadcasts `{:airdrop_winner_revealed}` per winner.

There is **no separate claim-confirmation watcher** — claims confirm synchronously through
the JS hook, then record via `Airdrop.claim_prize/5`.

### 3.6 Backing tables (all PostgreSQL/Ecto)

| Table / schema | Key fields | Source |
|---|---|---|
| `airdrop_rounds` (`Round`) | `round_id` (unique), `status` (pending/open/closed/drawn), `end_time`, `server_seed`, `commitment_hash`, `block_hash_at_close` (**reused to store the Solana slot**), `total_entries`, `start_round_tx`, `close_tx`, `draw_tx` | `airdrop/round.ex` |
| `airdrop_entries` (`Entry`) | `user_id`, `round_id`, `wallet_address`, `amount`, `start_position`, `end_position`, `deposit_tx` (**no unique constraint**) | `airdrop/entry.ex` |
| `airdrop_winners` (`Winner`) | `user_id`, `round_id`, `winner_index` (0–32), `wallet_address`, `prize_usd`, `prize_usdt`, `claimed`, `claim_tx`, `claim_wallet`; unique `[round_id, winner_index]` | `airdrop/winner.ex` |

The only Mnesia touchpoint is the BUX balance cache (`deduct_user_token_balance`).

---

## 4. End-to-end sequence

1. **Create** (admin/programmatic): `Airdrop.create_round(end_time)` (`airdrop.ex:43-92`)
   generates `server_seed` + `commitment_hash = SHA256(server_seed)`, calls
   `BuxMinter.airdrop_start_round` **first** → settler `start_round` (signed by
   `MINT_AUTHORITY`) → program auto-increments `current_round_id`, creates the round PDA →
   DB `Round` inserted `status: "open"` with the on-chain `round_id` →
   `Settler.notify_round_created` schedules the settle timer for `end_time`.
2. **Fund** (out-of-band): settler `/airdrop-fund-prizes` (or `init-airdrop.ts --test-round`)
   → `fund_prizes` moves SOL/SPL into the round's `prize_vault`. *(No Elixir caller.)*
3. **Enter** (user): on `/airdrop`, user picks an amount → `redeem_bux` → settler
   `/airdrop-build-deposit` returns an unsigned `deposit_bux` tx → `AirdropSolanaHook`
   (`airdrop_solana.js`) signs + submits via the user's wallet → BUX moves
   depositor ATA → treasury ATA and the `entry` PDA is created → on
   `airdrop_deposit_confirmed`, Elixir `redeem_bux` deducts Mnesia BUX and writes the
   `Entry` block.
4. **Close** (auto, at `end_time`): the GenServer timer fires → `airdrop_close` →
   `close_round` captures `slot_at_close` → DB `status: "closed"`, slot stored in
   `block_hash_at_close`.
5. **Draw** (auto, recurse): `Airdrop.draw_winners` computes 33 winners locally from
   `SHA256(server_seed | slot_at_close)` → inserts `Winner` rows, DB `status: "drawn"` →
   `draw_on_chain` submits `airdrop_draw_winners(round_id, server_seed, [{wallet,
   amount: prize_usd}])` → settler `draw_winners` reveals `server_seed` and writes
   `winners[]` on-chain → PubSub `{:airdrop_drawn}` + per-winner `{:airdrop_winner_revealed}`.
6. **Claim** (winner): on `/airdrop` (round `drawn`), winner clicks Claim →
   `/airdrop-build-claim` returns an unsigned `claim_prize` for their `winner_index` →
   winner signs + submits → program verifies `signer == winners[winner_index].wallet` and
   `claimed == false`, pays `amount` from `prize_vault`, flips `claimed = true` →
   `airdrop_claim_confirmed` → `Airdrop.claim_prize/5` records
   `claimed/claim_tx/claim_wallet` in the DB (mirroring the on-chain flag).

`Airdrop.claim_prize/5` (`airdrop.ex:329-349`) validates DB-side: `nil →
{:error, :winner_not_found}`, user mismatch → `{:error, :not_your_prize}`, already
claimed → `{:error, :already_claimed}`.

---

## 5. Verification (provably-fair)

`get_verification_data/1` exposes `server_seed`, `commitment_hash`, `slot_at_close`,
`total_entries`, and the on-chain tx hashes **only once `status == "drawn"`**
(`airdrop.ex:369-388`). `verify_fairness/1` checks
`SHA256(server_seed) == commitment_hash` (`airdrop.ex:393-401`, `provably_fair.ex:36-38`).
The seed is never revealed before the draw.

---

## 6. Current status

- **Routed & enabled, no gate:** `/airdrop` is live in `:redesign` (`router.ex:198`); the
  settler GenServer boots in prod (`application.ex:71-72`).
- **Implementation = Phase 8 "COMPLETE (2026-04-03)"** (`docs/solana_migration_plan.md:124-146`).
- **On-chain = devnet, fully initialized** (`AirdropState` `8xoz8…`,
  `docs/addresses.md:88-91`); a mainnet deployment of the same program address is recorded
  (`docs/addresses.md:116`).
- **No round-creation UI** — rounds must be created programmatically via
  `Airdrop.create_round/2`. When no round exists, the page renders a default "Opening soon"
  countdown hardcoded to `~D[2026-05-01] 17:00 UTC` (`airdrop_live.ex:36`).
- No EVM/legacy paths remain (Phase 8 removed Arbitrum/USDT + per-winner prize registration).
- No evidence in the readable docs of a production round ever having been run.

---

## Verified on-chain layout

### `AirdropState` (seed `["airdrop"]`) — `airdrop-service.ts:95-119`
```
disc(8) │ authority Pubkey(32)@8 │ bux_mint(32)@40 │ treasury(32)@72
        │ current_round_id u64@104 │ bump u8@112 │ _reserved[64]@113
```

### `AirdropRound` (seed `["round", round_id u64 LE]`) — `airdrop-service.ts:122-204`
```
disc(8) │ round_id u64@8 │ commitment_hash[32]@16 │ status u8@48 (0 open/1 closed/2 drawn)
        │ end_time i64@49 │ total_entries u64@57 │ deposit_count u64@65
        │ prize_mint Pubkey(32)@73 (111…111 = SOL) │ prize_amount u64@105
        │ server_seed[32]@113 │ slot_at_close u64@145 │ winner_count u8@153
        │ winners[WinnerInfo; 33]@154 (33 × 41 = 1353B) │ drawn_at i64@1507
        │ bump u8@1515 │ _reserved[64]@1516

WinnerInfo (41B): wallet Pubkey(32) + amount u64(8) + claimed bool(1)
```

### Instruction arg encodings — `airdrop-service.ts`
```
start_round  : disc + commitment_hash[32] + end_time i64 LE @40           (:288-291)
deposit_bux  : disc + round_id u64 @8 + entry_index u64 @16 + amount u64 @24  (:516-520)
fund_prizes  : disc + round_id u64 @8 + amount u64 @16                     (:332-335)
close_round  : disc + round_id u64 @8                                      (:396-398)
draw_winners : disc + round_id u64 @8 + server_seed[32] @16 + Vec<WinnerInfo>(u32 len + 41B each)  (:438-460)
claim_prize  : disc + round_id u64 @8 + winner_index u8 @16                (:572-575)
initialize   : disc only                                                  (init-airdrop.ts:133-134)
```

Account counts (IDL-verified, `idl-consistency.test.ts`): `initialize`=5, `start_round`=5,
`deposit_bux`=8, `fund_prizes`=8, `close_round`=3, `draw_winners`=3, `claim_prize`=8.

---

## Uncertainties

These could not be verified from this branch (Anchor Rust/IDL absent; the byte format below
is IDL-cross-checked, but program *logic* is not readable):

1. **Program-side enforcement is inferred, not read** — that `claim_prize` checks
   `winners[winner_index].wallet == signer && !claimed` before paying; that the authority
   instructions enforce `signer == AirdropState.authority`; whether `draw_winners`
   recomputes winners on-chain or simply trusts the authority-supplied list (the settler
   submits a pre-computed list, suggesting trust); whether `close_round` requires `end_time`
   to have passed.
2. **`AirdropEntry` field byte layout is unknown** — only its seeds are confirmed; the
   settler creates the PDA but never deserializes it.
3. **`withdraw_unclaimed` accounts/args/behavior are unknown** — discriminator and roster
   membership confirmed, but no builder/route/caller exists. By name, likely an authority
   sweep of unclaimed prize funds.
4. **Prize-amount denomination** — on-chain `WinnerInfo.amount` is submitted as the USD-cent
   integer (`prize_usd`), and no Elixir caller wires `fund_prizes`; how the funded vault
   denomination reconciles at claim time is not determinable here (§3.3).
5. **Entry double-deduction risk** — `Entry` has no unique constraint on `deposit_tx` and
   `create_entry` deducts BUX before insert; a duplicate `airdrop_deposit_confirmed` event
   could deduct twice. No server-side dedup guard was found.
6. **No admin UI / documented creation procedure** — no airdrop route in the `:admin`
   live_session and no snippet in `docs/admin_operations.md`. Creation appears IEx/`rpc`-only.
7. **Whether a production (mainnet) round has ever run** is not stated in any readable doc;
   inferred "no," not positively confirmed.
