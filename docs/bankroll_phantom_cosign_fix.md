# Bankroll Phantom Co-Sign Warning Fix + OtterSec Verification

**Status**: SPEC — not yet implemented
**Owner**: TBD
**Bankroll Program ID (devnet + mainnet)**: `49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm`
The program account address is the same on both networks because it's derived from the same program keypair (see `docs/solana_mainnet_deployment.md:113`, `:471`, `:696`). The two deployments are independent program *accounts* under the same *address* — upgrading mainnet does not touch devnet, and vice versa.
**Public source repo**: the existing `contracts/blockster-bankroll/` directory has been initialized as a standalone git repo specifically for OtterSec verification. Local path: `/Users/tenmerry/Projects/blockster_v2/contracts/blockster-bankroll/`. Remote: TBD — Phase 3A creates the GitHub repo (`rubyad/blockster-bankroll-program`) and pushes from this directory. This eliminates the `/tmp/blockster-bankroll-program` clone-and-copy step in the original plan.

---

## 1. Why Phantom shows the red "this app could be malicious" warning

Confirmed by direct comparison: a Wallet Standard SOL **deposit** triggers no warning, a Wallet Standard SOL **place_bet** does. The only structural difference is in the bet tx:

- **Deposit** (`buildDepositSolTx` in `contracts/blockster-settler/src/services/bankroll-service.ts:466-472`): in player-fee-payer mode, the settler does **not** sign at all. Single-signer tx → Phantom is happy.
- **Place bet** (`buildPlaceBetTx`, same file `:743-809`): the settler is **always** a `Signer` on the instruction (Anchor `rent_payer: Signer<'info>`) and the settler **always** partial-signs (`tx.partialSign(settler)`) before the tx leaves the server, regardless of fee-payer mode.

So when Phantom opens the place_bet tx it sees:

1. A pre-applied signature from a keypair the user does not control (the settler `6b4n…`)
2. A request for the user to add a second signature
3. A SOL outflow from the user's wallet to a PDA owned by an unverified custom program

That is byte-for-byte the [drainer phishing pattern Blowfish was built to flag](https://blog.phantom.app/security/transaction-simulation). The warning is technically correct — Phantom cannot tell our settler keypair apart from an attacker's.

### Why settler co-signs today

The on-chain handlers (`programs/blockster-bankroll/src/instructions/place_bet_sol.rs:75-78` and `place_bet_bux.rs:83-86`) require:

```rust
require!(
    ctx.accounts.rent_payer.key() == registry.settler,
    BankrollError::InvalidRentPayer
);
```

Reasoning at the time: forcing rent payer to be the settler keypair lets us absorb the ~0.002 SOL `bet_order` PDA rent on behalf of zero-SOL Web3Auth users. Rent cycles back via `close = rent_payer` on `settle_bet`/`reclaim_expired`. The settler is the safe identity to fund-and-receive PDA rent.

### What we want to keep

Web3Auth (email / X / Telegram) users **must remain zero-SOL**. Their UX is the whole point of the social-login flow — we cannot ask them to fund a wallet before they can play.

---

## 2. The fix: dual-mode rent_payer

Relax the on-chain constraint from "rent_payer MUST be settler" to "rent_payer MUST be settler OR the player". Then let the **client** (settler service) pick the mode based on the user's signing source:

| User signed in via | `fee_payer_mode` | `rent_payer` on tx | Tx signers visible to wallet | Phantom warning? |
|---|---|---|---|---|
| Wallet Standard (Phantom/Solflare/Backpack) | `"player"` | **player** | 1 (player only) | **No** |
| Web3Auth (email / X / Telegram) | `"settler"` | **settler** | (Web3Auth signs locally — no popup) | N/A |

Web3Auth path is **unchanged byte-for-byte**. The diff only touches the `feePayerMode === "player"` branch on the settler, plus a one-line constraint relaxation in the program.

`bet_order.rent_payer` is already stored per-bet (the field was added in the Phase 1 upgrade on 2026-04-20). On settle/reclaim, `close = rent_payer` returns rent to whichever pubkey was written at placement time — so the change is automatically backwards-compatible with in-flight bets.

### Why the player-as-rent_payer cost is a non-issue for Wallet Standard users

- ~0.002 SOL rent locks for the duration of the bet (typically <60 seconds — settler settles on the next minute tick).
- Refunded **net zero** on settle/reclaim via `close = rent_payer`.
- Wallet Standard users already pay the ~5000 lamport priority fee per bet, so they're already a fee-payer. Adding rent doesn't change the UX shape — just the dollar amount, by a fraction of a cent.

---

## 3. Program changes (Rust / Anchor 0.30.1)

Two files. One-line constraint change in each.

### `programs/blockster-bankroll/src/instructions/place_bet_sol.rs`

```diff
@@ -73,7 +73,9 @@
-    // Rent payer must be the settler — blocks Sybil drain of rent payer's
-    // balance by forcing the payer identity we control.
+    // Rent payer must be either the settler (zero-SOL Web3Auth path) or the
+    // player themselves (Wallet Standard path — avoids Phantom's drainer-
+    // pattern co-sign warning). Any third-party rent_payer is rejected.
     require!(
-        ctx.accounts.rent_payer.key() == registry.settler,
+        ctx.accounts.rent_payer.key() == registry.settler
+            || ctx.accounts.rent_payer.key() == ctx.accounts.player.key(),
         BankrollError::InvalidRentPayer
     );
```

### `programs/blockster-bankroll/src/instructions/place_bet_bux.rs`

Identical diff — copy the same pattern at lines 82-86.

```diff
@@ -82,7 +82,9 @@
-    // Rent payer must be the settler — see place_bet_sol for rationale.
+    // Rent payer must be either settler (Web3Auth) or player (Wallet
+    // Standard) — see place_bet_sol for rationale.
     require!(
-        ctx.accounts.rent_payer.key() == registry.settler,
+        ctx.accounts.rent_payer.key() == registry.settler
+            || ctx.accounts.rent_payer.key() == ctx.accounts.player.key(),
         BankrollError::InvalidRentPayer
     );
```

### What does NOT change

- Account structs in `place_bet_sol.rs:11-60` and `place_bet_bux.rs:11-69`: `rent_payer: Signer<'info>` stays. Anchor handles `player == rent_payer` (same pubkey appears in two account slots) automatically — Solana dedupes signers in the message header, so the player signs once.
- `bet_order.rent_payer` field, `BetOrder::LEN`, account layout: unchanged.
- `settle_bet.rs` and `reclaim_expired.rs`: `close = rent_payer` + `has_one = rent_payer` already work. Whatever pubkey was stored at placement is what receives rent on close — works identically for both modes.
- `state/game_registry.rs`: the `settler` field stays as the settler pubkey. We are not changing who signs commitments / settles / reclaims — only who funds bet PDA rent.

---

## 4. Settler changes (TypeScript)

Three functions in `contracts/blockster-settler/src/services/bankroll-service.ts`:

1. `buildPlaceBetTx` (`:706-814`) — pick rent_payer based on mode (the main fix).
2. `settleBet` (`:978-1088`) — must stop hardcoding `settler.publicKey` as rent_payer; instead read `bet_order.rent_payer` from on-chain.
3. `buildReclaimExpiredTx` (`:829-915`) — same as `settleBet`.

The reason for #2 and #3: the on-chain handlers validate `has_one = rent_payer` against the per-bet `bet_order.rent_payer` field. After the upgrade, Phantom-placed bets store `rent_payer = player.pubkey`. If we keep hardcoding `settler.publicKey` in the settle/reclaim tx, those bets will fail with `InvalidRentPayer`.

### 4.1 `buildPlaceBetTx`

```diff
@@ -738,18 +738,29 @@
   // Account order MUST match Anchor struct exactly.
-  // Post-Phase-1 rent_payer upgrade — `rent_payer` is the second account
-  // (right after `player`). Program validates it == game_registry.settler.
+  // Post-Phase-2 rent_payer upgrade — `rent_payer` is the second account
+  // (right after `player`). Program validates it ∈ {settler, player}.
+  // Wallet Standard users (feePayerMode === "player"): rent_payer = player.
+  // Single-signer tx, no Phantom co-sign warning. Player covers ~0.002 SOL
+  // rent which is refunded on settle/reclaim via close=rent_payer.
+  // Web3Auth users (feePayerMode === "settler"): rent_payer = settler.
+  // Player keeps zero SOL; settler absorbs rent (and recovers it on close).
+  const useSettlerFeePayer = feePayerMode === "settler";
+  const rentPayerKey = useSettlerFeePayer ? settler.publicKey : player;
   const keys: { pubkey: PublicKey; isSigner: boolean; isWritable: boolean }[] = [
     { pubkey: player, isSigner: true, isWritable: true },
-    { pubkey: settler.publicKey, isSigner: true, isWritable: true },
+    { pubkey: rentPayerKey, isSigner: true, isWritable: true },
     { pubkey: gameRegistry, isSigner: false, isWritable: false },
   ];
@@ -795,12 +806,15 @@
-  const useSettlerFeePayer = feePayerMode === "settler";
-
   const tx = new Transaction({
     recentBlockhash: blockhash,
     feePayer: useSettlerFeePayer ? settler.publicKey : player,
   });
   tx.add(...computeBudgetIxs(), ix);

-  // Settler always partial-signs as rent_payer. When it's also fee_payer,
-  // the single partialSign call covers both slots because the same
-  // Keypair signs all slots it controls.
-  tx.partialSign(settler);
+  // Settler partial-signs ONLY when it's the rent_payer or fee_payer
+  // (i.e. Web3Auth path). For Wallet Standard users the player is the
+  // sole signer — that's the whole point of this branch, removing the
+  // pre-applied second signature that triggered Phantom's warning.
+  if (useSettlerFeePayer) {
+    tx.partialSign(settler);
+  }

   return tx
     .serialize({ requireAllSignatures: false, verifySignatures: false })
     .toString("base64");
 }
```

### 4.2 `settleBet` — read rent_payer from on-chain

The current code at `:1067` hardcodes settler:

```ts
{ pubkey: settler.publicKey, isSigner: false, isWritable: true },      // 8. rent_payer (UncheckedAccount, validated via has_one)
```

We already fetch the bet_order PDA at `:1014` (for the commitment hash check). Extend that block to also read `rent_payer` and use it in the keys array.

`BetOrder` layout (verified against `programs/blockster-bankroll/src/state/bet_order.rs:51-63`):

| Field | Bytes | Cum offset |
|-------|------:|-----------:|
| disc | 8 | 8 |
| player | 32 | 40 |
| game_id | 8 | 48 |
| vault_type | 1 | 49 |
| amount | 8 | 57 |
| max_payout | 8 | 65 |
| commitment_hash | 32 | 97 |
| nonce | 8 | 105 |
| status | 1 | 106 |
| created_at | 8 | 114 |
| bump | 1 | 115 |
| **rent_payer** | **32** | **147** |

So `rent_payer` lives at byte offset **115..147**.

```diff
@@ -1014,6 +1014,11 @@
   const betOrderAcct = await connection.getAccountInfo(betOrder, "confirmed");
   if (!betOrderAcct) {
     throw new Error(`Bet order PDA not found on-chain for nonce ${nonce}`);
   }
+  if (betOrderAcct.data.length < 147) {
+    throw new Error(
+      `Bet order PDA data too short (${betOrderAcct.data.length} bytes) — expected ≥ 147 for rent_payer field`
+    );
+  }
   if (betOrderAcct.data.length < 97) {
     throw new Error(
       `Bet order PDA data too short (${betOrderAcct.data.length} bytes) for nonce ${nonce}`
@@ -1023,6 +1028,11 @@
   const onchainCommitment = Buffer.from(betOrderAcct.data.subarray(65, 97)).toString("hex");
   const computedCommitment = createHash("sha256").update(seedBytes).digest("hex");
+  // Post-Phase-2: bet_order.rent_payer can be either settler (Web3Auth-mode
+  // bets) or player (Wallet Standard-mode bets). settle_bet's `has_one =
+  // rent_payer` constraint validates the account we pass matches whatever
+  // is stored on-chain — so we MUST read the actual stored value, not
+  // hardcode settler.
+  const rentPayer = new PublicKey(betOrderAcct.data.subarray(115, 147));
   if (computedCommitment !== onchainCommitment) {
     ...

@@ -1067,1 +1077,1 @@
-    { pubkey: settler.publicKey, isSigner: false, isWritable: true },      // 8. rent_payer (UncheckedAccount, validated via has_one)
+    { pubkey: rentPayer, isSigner: false, isWritable: true },              // 8. rent_payer (read from bet_order — settler OR player)
```

(The redundant length check is shown for diff clarity; in the final code, replace the existing `< 97` check with a `< 147` one — same purpose, larger floor.)

### 4.3 `buildReclaimExpiredTx` — same fix

Currently at `:887` hardcodes settler:

```ts
{ pubkey: settler.publicKey, isSigner: false, isWritable: true },
```

Reclaim doesn't fetch the bet_order today (no commitment check), so we add one fetch.

```diff
@@ -837,6 +837,16 @@
   const [betOrder] = deriveBetOrder(player, nonceBigint);

+  // Read bet_order.rent_payer from on-chain — see settleBet for rationale.
+  // For pre-Phase-2 bets this is settler; for Phantom-placed Phase-2 bets
+  // it's the player. The on-chain reclaim_expired's `has_one = rent_payer`
+  // constraint will reject any other pubkey.
+  const betOrderAcct = await connection.getAccountInfo(betOrder, "confirmed");
+  if (!betOrderAcct || betOrderAcct.data.length < 147) {
+    throw new Error(`Bet order PDA missing or too short for nonce ${nonce}`);
+  }
+  const rentPayer = new PublicKey(betOrderAcct.data.subarray(115, 147));
+
   // Instruction data: discriminator (8) + nonce (u64 LE, 8) = 16 bytes
@@ -887,1 +897,1 @@
-    { pubkey: settler.publicKey, isSigner: false, isWritable: true },
+    { pubkey: rentPayer, isSigner: false, isWritable: true },
```

### What does NOT change in TypeScript

- `submitCommitment` (settler-signed): unchanged. Doesn't touch rent_payer.
- `buildDepositSolTx`, `buildWithdrawSolTx`, `buildDepositBuxTx`, `buildWithdrawBuxTx`: unchanged. No bet_order PDA, no rent_payer field.
- Server-side dispatch in `lib/blockster_v2/bux_minter.ex:506-510` (`fee_payer_mode_for_user/1`) is **already correct** — Web3Auth users get `"settler"`, everyone else gets `"player"`. No Elixir changes.

---

## 5. Backwards compatibility

To be explicit about what "upgrade" means here, since "migration" is ambiguous:

- **Program upgrade (REQUIRED).** We build a new `.so` from the modified Rust source and run `solana program deploy --program-id 49up2uz…` against the existing program account. The on-chain bytecode is replaced. Without this, the relaxed `require!` constraint isn't live and Wallet Standard txs with `rent_payer = player` would still fail with `InvalidRentPayer`. See §8 for the deploy commands.
- **Settler service deploy (REQUIRED).** The TypeScript fixes from §4 must ship together with the program upgrade. Without §4.2 and §4.3 (the on-chain `bet_order.rent_payer` lookup in `settleBet` / `buildReclaimExpiredTx`), Phantom-placed bets would land on-chain successfully but fail to settle/reclaim — they'd be stuck pending forever because the settler keeps passing the wrong rent_payer.
- **No data migration.** We do **not** rewrite any existing on-chain account, and we do **not** touch the `BetOrder` / `GameRegistry` / vault state layouts. Every existing PDA stays valid and deserializes identically after the upgrade.

Behaviour for in-flight bets at upgrade time:

- A bet placed before the upgrade has `bet_order.rent_payer = settler.pubkey` written on-chain.
- After the upgrade, the new settler service code reads that field from chain and passes `settler.pubkey` to `settle_bet` / `reclaim_expired`. The on-chain `has_one = rent_payer` constraint passes, `close = rent_payer` returns rent to settler. **No operator action needed for these old bets.**
- A bet placed after the upgrade by a Wallet Standard user has `bet_order.rent_payer = player.pubkey`. The settler reads that from chain, passes `player.pubkey`, rent closes to player.
- A bet placed after the upgrade by a Web3Auth user has `bet_order.rent_payer = settler.pubkey` (same as before). Path identical to the pre-upgrade behaviour.

---

## 6. Anchor tests

Add to `contracts/blockster-bankroll/tests/`:

1. `place_bet_player_rent_payer.ts` — Wallet Standard mode
   - Initialize a bet with `rent_payer = player`. Assert success.
   - Assert `bet_order.rent_payer == player.publicKey`.
   - Settle the bet. Assert `close = rent_payer` returned rent to player (player.lamports increased by ~0.00203 SOL).

2. `place_bet_settler_rent_payer.ts` — Web3Auth mode (regression + backwards-compat for pre-upgrade bets)
   - Initialize a bet with `rent_payer = settler`. Assert success (existing behaviour).
   - Assert `bet_order.rent_payer == settler.publicKey`.
   - **Settle the bet.** Assert `close = rent_payer` returned rent to settler.
   - Note: this test doubles as the pre-upgrade-bet backwards-compat test. A bet placed under the old program had `rent_payer = settler` written on-chain; structurally identical to a Web3Auth bet placed under the new program.

3. `place_bet_invalid_rent_payer.ts` — security
   - Initialize a bet with `rent_payer = random_keypair`. Assert it fails with `InvalidRentPayer`.
   - This is the critical test — confirms we still reject third-party rent_payers.

Run with: `cd contracts/blockster-bankroll && anchor test`.

---

## 7. Manual QA on devnet (before mainnet)

Run all six cases on devnet, with `bin/dev` + a real Phantom wallet on devnet:

| # | Wallet | Vault | Expected |
|---|--------|-------|----------|
| 1 | Phantom (Wallet Standard) | SOL | **No red warning** in Phantom popup. Bet places. Settles correctly. Rent returns to player on settle. |
| 2 | Phantom (Wallet Standard) | BUX | **No red warning**. Bet places. Settles. Rent returns to player. |
| 3 | Web3Auth email | SOL | No popup at all (Web3Auth signs locally). Bet places. Settles. Player wallet keeps zero SOL. |
| 4 | Web3Auth email | BUX | No popup. Bet places. Settles. Player wallet keeps zero SOL. |

Plus the in-flight-bet case:

5. **In-flight bet across the upgrade.** Before upgrading the program, place a bet from Phantom (current behaviour: settler is rent_payer). Do **not** settle it. Upgrade the program. Then settle the bet via the (also upgraded) settler service. Assert it settles correctly and rent returns to settler. *Timing note*: bets settle within ~1 minute via the GenServer loop, so coordinate the upgrade window. If timing is awkward to test in real time, this path is structurally identical to a Web3Auth bet placed under the new program (covered by case 3) — so it's a confirmation rather than the only proof.

Reclaim (the 5-min stuck-bet path on `/play`):

6. Place a Phantom bet under the new program (rent_payer = player). Wait > 5 minutes. Click "Reclaim" on the banner. Assert reclaim succeeds and rent returns to player.

---

## 8. Deployment plan

**Two phases — devnet first, mainnet second.** Do not start the mainnet phase until every devnet QA case is green.

### Phase 1 — Devnet (validate the fix)

Devnet is throwaway; we use a normal `anchor build` (faster, simpler). No OtterSec verification on devnet — it doesn't matter for users.

```bash
# 1. Build
cd contracts/blockster-bankroll
anchor build

# 2. Deploy to devnet (CLI deploy wallet 49aN... pays fees, settler 6b4n... is upgrade authority)
solana program deploy target/deploy/blockster_bankroll.so \
  --program-id 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm \
  --upgrade-authority ~/path/to/settler-keypair.json \
  --url <DEVNET_QUICKNODE_URL>

# 3. Deploy the matching settler (TypeScript changes ship together)
cd contracts/blockster-settler
# (devnet settler runs locally via `bin/dev settler` — restart it instead)
```

Then:

- Run the Anchor test suite (`anchor test` in `contracts/blockster-bankroll/`) — all three tests from §6 pass.
- Run the full manual QA matrix from §7 against devnet (Phantom × {SOL, BUX}, Web3Auth × {SOL, BUX}, the in-flight pre/post settle case, and the reclaim case).
- Confirm specifically: **Phantom no longer shows the red warning** for case 1 and 2.

**Hard stop**: if any QA case fails, debug and re-deploy on devnet. Do not proceed to mainnet.

### Phase 2 — Mainnet (deploy + OtterSec)

Mainnet deploys use the **Docker-built binary** (from `solana-verify build`), not `anchor build`. This is the only build that's reproducible and verifiable. Deploying the wrong build means re-deploying once verification fails, wasting ~5 SOL on the buffer cycle.

The full mainnet sequence is in §9 (it's the OtterSec workflow — building with `solana-verify`, deploying that exact binary, then running the verification jobs). The settler deploy comes after the program is verified:

```bash
# After §9 completes successfully:
cd contracts/blockster-settler
flyctl deploy --app blockster-settler
# (verify cwd is contracts/blockster-settler/ per CLAUDE.md hard rule before running)
```

Smoke-test once on prod with a small Phantom bet, confirm no red warning, confirm Solscan shows the verified badge.

### Phase 3 — Documentation update

Once the Solscan verified badge is live and the smoke test passes, update both internal and on-site documentation as per §11. This includes:

- `docs/addresses.md` — add the Solana Mainnet section with the OtterSec job ID + build hash (§11.1).
- The `/docs/smart-contracts`, `/docs/coin-flip`, and `/docs/security-audit` LiveView pages — every reference to "rent_payer must equal settler" is now stale and needs updating to reflect the dual-mode invariant. Add an OtterSec verified badge on the security audit page header (§11.2).

This is a Phoenix-only deploy (no program changes, no settler changes) — `git push origin main && flyctl deploy --app blockster-v2`.

---

## 9. Phase 2 details — mainnet deploy + OtterSec verification

Mirrors `Projects/roguetrader/docs/verification_guide.md`. Only run this after Phase 1 (devnet) is green.

On-chain program verification proves the deployed binary matches the public source. Required for:

- **OtterSec verified badge** on Solscan
- User trust / signal that the program is what we say it is — partly mitigates the "unverified program" angle of Phantom's warning even on the residual surface

The process uses [solana-verify](https://github.com/Ellipsis-Labs/solana-verify), which builds inside a Docker container for deterministic output. Local `anchor build` produces a different hash and **cannot** be used.

### 9.1 Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Desktop | Must be running. Uses `solanalabs/solana:v1.18.26` image. |
| `solana-verify` CLI | `cargo install solana-verify` |
| Solana CLI 1.18.26 | Match the version pinned in `rust-toolchain.toml` (must add — see 9.2) |
| Deploy authority keypair | settler keypair (`6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1`) |
| ~5 SOL in deploy wallet | `49aNHDAduVnEcEEqCyEXMS1rT62UnW5TajA2fVtNpC1d` — buffer locks ~5 SOL during deploy, returned after. |
| QuickNode mainnet RPC | The mainnet URL from CLAUDE.md (`SOLANA_RPC_URL` Fly secret on `blockster-v2`). Public RPC fails for program data fetch. |

### 9.2 One-time setup

The bankroll project does not currently have `rust-toolchain.toml`. Add one to pin the toolchain inside the Docker build:

```toml
# contracts/blockster-bankroll/rust-toolchain.toml
[toolchain]
channel = "1.79.0"
```

Commit alongside the program changes.

### 9.3 Step 1 — Push source to public repo

**The bankroll directory is its own git repo already** — `contracts/blockster-bankroll/.git` was initialized specifically for OtterSec verification. Working tree contains exactly the on-chain Anchor code (no settler, no Phoenix app). Untracked files at the time of writing: `.gitignore`, `.prettierignore`, `Anchor.toml`, `Cargo.lock`, `Cargo.toml`, `migrations/`, `package.json`, `programs/`, `scripts/`, `tests/`, `tsconfig.json`, `yarn.lock`. None contain secrets — keypairs live in `contracts/blockster-settler/keypairs/` and never touch this directory.

No `/tmp` clone needed; commit + push directly from `contracts/blockster-bankroll/`.

```bash
# 1. Create the empty GitHub repo (one-time)
gh repo create rubyad/blockster-bankroll-program --public --description "Blockster bankroll Solana program — public source for on-chain verification"

# 2. From the bankroll dir, wire up the remote, rename master → main (GitHub default), add files, commit, push.
cd /Users/tenmerry/Projects/blockster_v2/contracts/blockster-bankroll

# Quick eyeball — confirm no surprises before staging
git status

git remote add origin https://github.com/rubyad/blockster-bankroll-program.git
git branch -M main

# Stage everything except gitignored stuff (target/, node_modules/, .anchor/, test-ledger, .yarn).
git add -A
git status --short   # second look: confirm only intended files staged

git commit -m "Initial public source: rent_payer dual-mode upgrade"
git push -u origin main
```

Subsequent updates: just `git add / commit / push` from `contracts/blockster-bankroll/` — no copying.

**Optional cleanup before the first push**: `Anchor.toml` currently has `[programs.localnet]` and `[programs.devnet]` sections but no `[programs.mainnet]`. Adding one (pointing to the same `49up2uz…` ID) is purely cosmetic — verification uses the program ID via the `--program-id` CLI flag, not Anchor.toml — but leaves the public repo's config tidier for outside readers.

```toml
# add to Anchor.toml
[programs.mainnet]
blockster_bankroll = "49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm"
```

### 9.4 Step 2 — Deterministic Docker build

**Docker Desktop must be running.**

```bash
cd /Users/tenmerry/Projects/blockster_v2/contracts/blockster-bankroll
solana-verify build
```

Expected output:

```
Building program...
Using docker image: solanalabs/solana:v1.18.26
...
Build hash: <DETERMINISTIC_HASH>
```

**Troubleshooting:**
- Docker not running: `open -a Docker`, wait for it to start.
- Dependency errors: confirm `Cargo.lock` is committed (pins exact versions). Anchor 0.30.1 needs the transitive pins already in `programs/blockster-bankroll/Cargo.toml` (`blake3 = "=1.5.5"`, `proc-macro-crate = "=3.2.0"`).
- The Docker build uses the Solana version from `rust-toolchain.toml` (Rust 1.79.0).

### 9.5 Step 3 — Deploy the Docker-built binary

**CRITICAL**: Deploy the binary from step 9.4, NOT from a local `anchor build`. The hashes will differ.

```bash
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

# Check current deployed program size
solana program show 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm --url mainnet-beta

# If the new binary is larger than the deployed one, extend first:
# solana program extend 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm <EXTRA_BYTES> --url mainnet-beta

# Deploy
solana program deploy target/deploy/blockster_bankroll.so \
  --program-id 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm \
  --upgrade-authority ~/path/to/settler-keypair.json \
  --url mainnet-beta
```

**If deploy fails with "insufficient funds":**
- Buffer locks ~5 SOL temporarily (returned after deploy).
- Top up `49aNHDAduVnEcEEqCyEXMS1rT62UnW5TajA2fVtNpC1d`.
- Close any leftover buffers: `solana program close --buffers --url mainnet-beta`.

**If "account data too small":**
- `solana program extend 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm <EXTRA_BYTES> --url mainnet-beta`, then retry.

### 9.6 Step 4 — Verify the binary matches source

```bash
# Pipe `echo y` to handle the interactive upload prompt — the CLI panics
# with UnexpectedEof if there's no stdin.
echo "y" | solana-verify verify-from-repo \
  --url <MAINNET_QUICKNODE_URL> \
  --program-id 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm \
  https://github.com/rubyad/blockster-bankroll-program
```

Expected:

```
On-chain hash: <HASH>
Executable hash: <HASH>
Program hash matches ✅
Uploading the program verification params to the Solana blockchain...
Program uploaded successfully. Transaction ID: <TX_ID>
```

**Troubleshooting:**
- Use the QuickNode RPC — public RPC fails for large program data fetch.
- "FAIL" hash mismatch: deployed binary doesn't match Docker build. Re-run step 9.5 with the actual `target/deploy/blockster_bankroll.so` from `solana-verify build`.
- Without `echo "y" |` the CLI panics with `UnexpectedEof`.

### 9.7 Step 5 — Submit to OtterSec

```bash
solana-verify remote submit-job \
  --url <MAINNET_QUICKNODE_URL> \
  --program-id 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm \
  https://github.com/rubyad/blockster-bankroll-program
```

Expected:

```
Job submitted: <JOB_ID>
```

**Troubleshooting:**
- Rate-limited: wait 30s and retry.
- Status: `https://verify.osec.io/status/49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm`
- Solscan badge typically appears within a few minutes of "Verified" status.

### 9.8 Step 6 — Confirm

1. Visit `https://verify.osec.io/status/49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm` — should show "Verified".
2. Visit Solscan program page — should show "Verified" badge.
3. Update `docs/addresses.md` with the new build hash, OtterSec job ID, and verification URL (see 11).

---

## 10. Quick reference — full command sequence

```bash
# 0. Docker must be running
open -a Docker

# 1. Wire up the existing bankroll repo to GitHub and push.
cd /Users/tenmerry/Projects/blockster_v2/contracts/blockster-bankroll
gh repo create rubyad/blockster-bankroll-program --public --description "Blockster bankroll Solana program — public source for on-chain verification"
git remote add origin https://github.com/rubyad/blockster-bankroll-program.git
git branch -M main
git add -A
git commit -m "rent_payer dual-mode + Phantom co-sign fix"
git push -u origin main

# 2. Docker build (from same dir)
solana-verify build

# 3. Deploy Docker binary
solana program deploy target/deploy/blockster_bankroll.so \
  --program-id 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm \
  --upgrade-authority ~/path/to/settler-keypair.json \
  --url mainnet-beta

# 4. Verify
echo "y" | solana-verify verify-from-repo \
  --url <MAINNET_QUICKNODE_URL> \
  --program-id 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm \
  https://github.com/rubyad/blockster-bankroll-program

# 5. Submit OtterSec
solana-verify remote submit-job \
  --url <MAINNET_QUICKNODE_URL> \
  --program-id 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm \
  https://github.com/rubyad/blockster-bankroll-program
```

---

## 11. Post-verification housekeeping

After §9 finishes (OtterSec badge live on Solscan), three documentation surfaces need to be updated. Do these as part of the same PR sweep so internal and external docs don't drift.

### 11.1 Internal: `docs/addresses.md`

Update the existing devnet Bankroll Program entry (currently mentions "Phase 1 upgrade 2026-04-20") to record the Phase 2 upgrade. Add a new "Solana Mainnet" section since one doesn't exist yet:

```markdown
## Solana Mainnet

### Programs & Token
| Resource | Address / ID | Purpose |
|----------|-------------|---------|
| Bankroll Program | `49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm` | Dual-vault SOL + BUX. **Phase 2 upgrade <DATE>** — rent_payer dual-mode (player OR settler) to remove Phantom co-sign warning for Wallet Standard users. Web3Auth users still use settler as rent_payer (zero-SOL UX). |

### Verification
| Field | Value |
|-------|-------|
| Public source | `https://github.com/rubyad/blockster-bankroll-program` |
| Build hash | `<HASH_FROM_DOCKER_BUILD>` |
| OtterSec job | `<JOB_ID>` |
| OtterSec status | `https://verify.osec.io/status/49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm` |
```

### 11.2 On-site: `/docs/smart-contracts`, `/docs/coin-flip`, `/docs/security-audit`

The on-site docs and the security audit page describe the old "rent_payer must equal settler" invariant in many places. Every reference is now stale. Update each one. Use `Edit` (not `Write`) — these are `.html.heex` files with code samples that need precise edits.

**File: `lib/blockster_v2_web/live/docs_live/smart_contracts.html.heex`**

| Line | Current text | Updated text |
|------|--------------|--------------|
| `:40` | `{"Program ID", "49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm"}` | Add a new row directly below: `{"OtterSec verification", "<verify.osec.io/status/...> (Verified)"}` |
| `:224` | `pub rent_payer: Pubkey,            // Locked at placement to game_registry.settler` | `pub rent_payer: Pubkey,            // Set at placement to either game_registry.settler (Web3Auth) or player.key() (Wallet Standard)` |
| `:229` | "rent rebate goes back to … the settler keypair in force at placement" | "rent rebate goes back to whichever pubkey was stored in `bet_order.rent_payer` at placement — settler for Web3Auth bets, player for Wallet Standard bets." |
| `:314-315` | signer column: `"player + settler (rent_payer)"` | `"player + (settler or player as rent_payer; depends on signer source)"` |
| `:392` | `InvalidRentPayer` msg: "rent_payer at placement ≠ game_registry.settler; or bet_order.rent_payer at settle/reclaim ≠ supplied account." | "rent_payer at placement ∉ {game_registry.settler, player}; or bet_order.rent_payer at settle/reclaim ≠ supplied account." |

**File: `lib/blockster_v2_web/live/docs_live/coin_flip.html.heex`**

| Line | What to change |
|------|----------------|
| `:241` | "Two signatures are involved … settler partial-signs the transaction" — rewrite. For Wallet Standard, only the player signs; for Web3Auth, only the settler signs (locally). The `rent_payer` is whoever is funding bet PDA rent for that flow (player for Wallet Standard, settler for Web3Auth). |
| `:244` | "rent_payer identity is checked on-chain against game_registry.settler" — change to "checked against {game_registry.settler, player.key()}". Drop the "binds the BetOrder to the current settler keypair" implication. |
| `:285` | "rent (~0.002 SOL) is returned to the original rent_payer — always the settler" → drop "— always the settler". Returning to whoever paid is the whole point of `close = rent_payer`. |
| `:408` | Account list: `rent_payer — Signer, mut (must equal game_registry.settler)` → `(must equal game_registry.settler OR player)` |
| `:417` | Constraint check: `rent_payer == game_registry.settler → InvalidRentPayer` → `rent_payer ∈ {settler, player} → InvalidRentPayer` (negate for the error condition). |
| `:480` | "Closes: bet_order → rent_payer (the original settler)" → drop "(the original settler)". |
| `:484` | `bet_order.rent_payer matches stored pubkey → InvalidRentPayer` — leave as-is (settle/reclaim still uses `has_one`, this still holds). |

**File: `lib/blockster_v2_web/live/docs_live/security_audit.html.heex`**

| Line | What to change |
|------|----------------|
| `:28` | "Program 49up2u…" header — add a small "Verified by OtterSec" badge linking to verify.osec.io. (Mirror the visual treatment from the rest of the audit page.) |
| `:327` | "BetOrder stores the rent_payer at placement time (enforced to equal the current settler)" → "(enforced to equal current settler or player)". |
| `:347` | The "Document the rotation runbook" paragraph already suggests the exact relaxation we shipped. Update tense: "Phase 2 upgrade <DATE> shipped this relaxation: rent_payer ∈ {settler, player} at placement; settle/reclaim still close to whoever is stored on the BetOrder." Drop the "Alternatively, relax …" suggestion since we've now done it. |
| `:351` | File references: bump line numbers to match the post-upgrade source if they shifted. |
| `:452` | "submit_commitment and place_bet_* calls (which require the settler as rent_payer) will fail" — the settler-rent-payer dependency only applies to **submit_commitment** now; **place_bet_*** can use the player as rent_payer for Wallet Standard users. Re-scope this DoS analysis. |
| `:596+` (Verified properties) | Add a new entry: "rent_payer at placement ∈ {settler, player} — both paths exercised in the Anchor test suite (`tests/place_bet_*_rent_payer.ts`); third-party rent_payers correctly rejected with `InvalidRentPayer`." |
| `:624` | "has_one = player and has_one = rent_payer correctly bind settlement and reclaim accounts" — leave as-is (still true; the binding now permits player-as-rent_payer cases too, but the property holds either way). |

After editing, smoke-test all three pages locally (`/docs/smart-contracts`, `/docs/coin-flip`, `/docs/security-audit`) before deploying the Phoenix app. The pages are static heex; no LV state to worry about, just visual proofreading.

---

## 12. Important notes

1. **Local `anchor build` ≠ Docker build** — hashes ALWAYS differ. Only the Docker build is verifiable.
2. **Program must remain upgradeable** — NEVER use `--final` on `set-upgrade-authority`.
3. **Account layouts are unchanged** — no data migration, no field reshuffle. The change is handler-side constraint relaxation only. The program upgrade itself (deploying a new `.so` to the existing program ID) is required, but no on-chain account needs to be rewritten.
4. **The Web3Auth UX is preserved** — server dispatch in `bux_minter.ex:506-510` already routes those users to `feePayerMode = "settler"`. We are not changing that path.
5. **In-flight bets at upgrade time are safe** — `close = rent_payer` reads from the per-bet `bet_order.rent_payer` field, not from the registry. Pre-upgrade bets still close to settler; post-upgrade Wallet Standard bets close to player.
6. **Verifying does not eliminate every Phantom warning** — Blowfish may still flag the SOL outflow + custom-program shape. Verified-program status downgrades the severity but is not a silver bullet. The co-sign warning (the actual cause of the red banner) is what this fix removes.

---

## 13. Open questions / before merge

- [ ] Confirm the public repo name (`rubyad/blockster-bankroll-program`) — adjust if a different org/name is preferred. roguetrader uses `rubyad/roguetrader-program`, so this matches the convention.
- [ ] Confirm there are no in-flight bets older than 5 minutes at upgrade time — if yes, settle them first (or they'll go through the reclaim path, which still works).
- [ ] Decide whether to also seek Phantom dApp allowlisting (separate process, app-side rather than program-side, but compounds well with verification).
