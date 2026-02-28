# FateSwap — Solana On-Chain Architecture

> Comprehensive implementation blueprint for the FateSwap protocol on Solana.
> Transfers the proven patterns from ROGUEBankroll (LP pool) and BuxBoosterGame (provably fair commit-reveal) into the FateSwap concept — a DEX-framed gambling protocol where users "trade at the price they believe in."

**Scope**: On-chain Anchor/Rust programs only. Frontend, database, and backend services are out of scope.

### Version Requirements

Rust is managed via **rustup** + `rust-toolchain.toml` (standard for Solana/Anchor). Claude installs toolchains and creates config files during Phase S1 scaffold.

| Component | Version | Manager |
|---|---|---|
| Rust | 1.84.1 | rustup (`rust-toolchain.toml`) |
| Anchor CLI | 0.31.1 | `cargo install --git` |
| anchor-lang | 0.31.1 | Cargo.toml |
| Solana CLI | latest compatible with Anchor 0.31.1 | `sh -c "$(curl ...)"` |

---

## Table of Contents

1. [Concept Mapping: EVM → Solana](#1-concept-mapping-evm--solana)
2. [Architecture Decision: Single Program](#2-architecture-decision-single-program)
3. [Account Model & PDA Design](#3-account-model--pda-design)
4. [Module 1: ClearingHouse (LP Pool)](#4-module-1-clearinghouse-lp-pool)
5. [Module 2: FateGame (Bet Logic)](#5-module-2-fategame-bet-logic)
   - [5.7 Buy-Side Orders (Discount Buying)](#57-buy-side-orders-discount-buying)
   - [5.8 Anchor Account Context Structs](#58-anchor-account-context-structs)
   - [5.9 Admin Instructions](#59-admin-instructions)
6. [Provably Fair System (Commit-Reveal)](#6-provably-fair-system-commit-reveal)
7. [Jupiter Integration (Token → SOL Swap)](#7-jupiter-integration-token--sol-swap)
8. [Fate Fee & Revenue Model](#8-fate-fee--revenue-model)
9. [Referral System](#9-referral-system)
10. [Dynamic Bet Limits (Kelly Criterion)](#10-dynamic-bet-limits-kelly-criterion)
11. [Security Model](#11-security-model)
12. [Compute Budget & Gas Costs](#12-compute-budget--gas-costs)
13. [Upgradeability & State Migration](#13-upgradeability--state-migration)
14. [Testing Strategy](#14-testing-strategy)
15. [Deployment Plan](#15-deployment-plan)
16. [EVM → Solana Translation Reference](#16-evm--solana-translation-reference)
17. [Error Codes](#17-error-codes)
18. [Events](#18-events)
19. [Program Entry Point & Module Structure](#19-program-entry-point--module-structure)
20. [Open Questions & Future Considerations](#20-open-questions--future-considerations)

---

## 1. Concept Mapping: EVM → Solana

### What We're Porting

| EVM Component | Solana Equivalent | FateSwap Name |
|---|---|---|
| ROGUEBankroll.sol (LP pool, native ROGUE) | ClearingHouse module (LP pool, native SOL) | ClearingHouse |
| BuxBoosterGame.sol (coin flip, commit-reveal) | FateGame module (multiplier bet, commit-reveal) | FateGame |
| ROGUEBankroll LP token (ERC-20) | SPL Token LP mint (PDA-controlled) | FATE-LP |
| `depositROGUE()` / `withdrawROGUE()` | `deposit_sol()` / `withdraw_sol()` | LP deposit/withdraw |
| `submitCommitment()` | `submit_commitment()` | Commitment submission |
| `placeBetROGUE()` | `place_fate_order()` | Place fate order |
| `settleBetROGUE()` | `settle_fate_order()` | Settle fate order |
| `refundExpiredBet()` | `reclaim_expired_order()` | Reclaim expired order |
| ROGUE (native gas token) | SOL (native gas token) | SOL |
| House edge via multiplier math | Fate fee (1.5%) via multiplier math | Fate fee |

### Key Reframing: Gambling → Trading Language

Per the FateSwap concept doc, all on-chain events and account names use DEX language:

| Gambling Term | FateSwap On-Chain Name |
|---|---|
| Bet | Fate Order |
| Place bet | `place_fate_order` |
| Settle bet | `settle_fate_order` |
| Win / Lose | Filled / Not Filled |
| Win probability | Fill chance |
| House edge | Fate fee |
| Multiplier | Target price multiplier |
| Bankroll | ClearingHouse vault |

### Fundamental Difference: Solana's Account Model

On EVM, a contract holds its own state and balance. On Solana:

- **Programs are stateless** — they contain only executable code
- **State lives in Accounts** — separate data accounts owned by the program
- **SOL is held in PDAs** — Program Derived Addresses act as vaults
- **SPL tokens are separate programs** — minting LP tokens requires CPI to the Token Program
- **No reentrancy** — Solana's runtime borrow-checker prevents CPI callbacks from re-accessing already-borrowed accounts within a transaction

---

## 2. Architecture Decision: Single Program

### Decision: One Anchor program containing both ClearingHouse and FateGame logic

**Why not two programs (like our EVM architecture)?**

On EVM, we separated ROGUEBankroll and BuxBoosterGame into two contracts because:
- Inter-contract calls are cheap (~2,600 gas for a warm CALL)
- Deploying separate contracts has minimal overhead
- Upgradeability was handled separately (Transparent vs UUPS proxy)

On Solana, the calculus is different:
- **CPI overhead is ~5,000-10,000 CU per call** for the invocation mechanism alone, plus the called instruction's compute cost (significant when default budget is 200,000 CU)
- Every bet placement + settlement would need 2-3 CPIs, consuming 60,000-90,000 CU in overhead alone
- A single program avoids this entirely — pool state and bet logic share direct memory access

**How existing Solana protocols handle this:**
- **Drift Protocol** (perpetual futures): Single monolithic program — specifically to avoid CPI overhead on the hot path
- **Zeta Markets**: Single program, same reasoning
- **Monaco Protocol** (parimutuel betting): Single program

**Program size estimate:**

| Component | Estimated Size |
|---|---|
| ClearingHouse instructions (init, deposit, withdraw, pause, config) | ~80 KB |
| FateGame instructions (commit, place, settle, expire) | ~100 KB |
| Account serialization (Anchor boilerplate) | ~60 KB |
| Validation logic (constraints, access control) | ~40 KB |
| Math operations (LP price, fees, fixed-point) | ~30 KB |
| Events and errors | ~20 KB |
| CPI to Token Program | ~15 KB |
| **Total** | **~345 KB** |

Solana's program size limit is 10 MB (BPF loader v3). We're well under at ~345 KB. For reference, Drift v2 is ~750 KB.

**If we need multiple game types later** (FatePlinko, FateDice), we can refactor into multi-program with CPI at that point. The account structures (bet PDAs, pool state) remain identical.

### Program Structure

```
programs/
├── fateswap/                           # Main program: ClearingHouse + FateGame
│   ├── src/
│   │   ├── lib.rs                        # Program entry point, declare_id!
│   │   ├── state/
│   │   │   ├── mod.rs
│   │   │   ├── clearing_house.rs         # ClearingHouseState account
│   │   │   ├── fate_order.rs             # FateOrder account, FateOrderStatus enum
│   │   │   ├── player_state.rs           # PlayerState account
│   │   │   └── referral_state.rs         # ReferralState account
│   │   ├── instructions/
│   │   │   ├── mod.rs
│   │   │   ├── initialize.rs             # Initialize ClearingHouse + vault + LP mint
│   │   │   ├── deposit_sol.rs            # LP deposit SOL → FATE-LP
│   │   │   ├── withdraw_sol.rs           # LP burn FATE-LP → SOL
│   │   │   ├── submit_commitment.rs      # Server commits hash
│   │   │   ├── place_fate_order.rs       # Player places fate order
│   │   │   ├── settle_fate_order.rs      # Server reveals seed, settles + 5-way split
│   │   │   ├── reclaim_expired_order.rs  # Player reclaims after timeout
│   │   │   ├── set_referrer.rs           # Player sets referrer (auto-resolves tier-2)
│   │   │   ├── pause.rs                  # Authority toggles pause state
│   │   │   ├── update_config.rs          # Authority updates fee/limits/timeout/wallets
│   │   │   └── update_settler.rs         # Authority changes settler wallet
│   │   ├── errors.rs                     # FateSwapError enum
│   │   ├── events.rs                     # All Anchor events
│   │   └── math.rs                       # LP pricing, fee calc, max bet
│   ├── Anchor.toml
│   ├── Cargo.toml
│   └── tests/
│       ├── clearing_house.test.ts
│       ├── fate_game.test.ts
│       ├── provably_fair.test.ts
│       ├── revenue_split.test.ts         # 5-way split on losses
│       └── integration.test.ts
│
├── nft-rewarder/                       # Separate program: NFT reward distribution
│   ├── src/
│   │   ├── lib.rs                        # Program entry point
│   │   ├── state/
│   │   │   ├── mod.rs
│   │   │   ├── rewarder_state.rs         # RewarderState (global singleton)
│   │   │   └── nft_holder.rs             # NFTHolder (per-wallet, aggregated points)
│   │   ├── instructions/
│   │   │   ├── mod.rs
│   │   │   ├── initialize.rs             # Init rewarder + vault
│   │   │   ├── sync_rewards.rs           # Permissionless crank: detect new SOL, update accumulator
│   │   │   ├── claim_reward.rs           # NFT holder claims pending SOL
│   │   │   ├── update_holder.rs          # Admin: set wallet + points
│   │   │   └── batch_update_holders.rs   # Admin: batch holder updates
│   │   └── errors.rs
│   ├── Anchor.toml
│   ├── Cargo.toml
│   └── tests/
│       ├── nft_rewarder.test.ts
│       └── bridge.test.ts
```

---

## 3. Account Model & PDA Design

### Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Account Layout                        │
│                                                          │
│  ClearingHouseState (PDA, global singleton)              │
│  seeds: [b"clearing_house"]                              │
│  ├── authority (Pubkey)          — admin/owner           │
│  ├── settler (Pubkey)            — server wallet         │
│  ├── vault_bump (u8)             — vault PDA bump        │
│  ├── lp_mint_bump (u8)           — LP mint PDA bump      │
│  ├── lp_authority_bump (u8)      — mint authority bump   │
│  ├── fate_fee_bps (u16)          — 150 = 1.5%           │
│  ├── max_bet_bps (u16)           — 10 = 0.1% of net     │
│  ├── referral_bps (u16)          — 20 = 0.2% tier-1     │
│  ├── tier2_referral_bps (u16)    — 10 = 0.1% tier-2     │
│  ├── nft_reward_bps (u16)        — 30 = 0.3% to NFTs    │
│  ├── platform_fee_bps (u16)      — 30 = 0.3% to team    │
│  ├── bonus_bps (u16)             — 10 = 0.1% to bonuses │
│  ├── platform_wallet (Pubkey)    — team/treasury wallet  │
│  ├── bonus_wallet (Pubkey)       — bonuses wallet        │
│  ├── nft_rewarder (Pubkey)       — NFTRewarder program   │
│  ├── min_bet (u64)               — minimum lamports      │
│  ├── bet_timeout_seconds (i64)   — 300 = 5 minutes      │
│  ├── total_liability (u64)       — pending payouts       │
│  ├── unsettled_count (u32)       — active bet count      │
│  ├── total_bets (u64)            — lifetime count        │
│  ├── total_volume (u128)         — lifetime SOL wagered  │
│  ├── total_filled (u64)          — lifetime wins         │
│  ├── total_not_filled (u64)      — lifetime losses       │
│  ├── house_profit (i128)         — net P/L in lamports   │
│  ├── paused (bool)               — emergency stop        │
│  └── _reserved ([u8; 192])       — future fields         │
│                                                          │
│  Vault (SystemAccount PDA, holds native SOL)             │
│  seeds: [b"vault", clearing_house.key()]                 │
│                                                          │
│  LP Mint (SPL Token Mint PDA, FATE-LP token)             │
│  seeds: [b"lp_mint", clearing_house.key()]               │
│  decimals: 9 (matches SOL)                               │
│                                                          │
│  LP Authority (PDA, signs mint/burn)                     │
│  seeds: [b"lp_authority", clearing_house.key()]          │
│                                                          │
│  FateOrder (PDA, per-bet, created → closed)              │
│  seeds: [b"fate_order", player.key(), nonce_bytes]       │
│  ├── player (Pubkey)                                     │
│  ├── amount (u64)                — SOL wagered           │
│  ├── multiplier_bps (u32)        — 101000 = 1.01x       │
│  ├── potential_payout (u64)      — pre-computed max      │
│  ├── commitment_hash ([u8; 32])  — SHA256(server_seed)   │
│  ├── nonce (u64)                 — player's incrementor  │
│  ├── timestamp (i64)             — placement time        │
│  ├── status (FateOrderStatus)    — Pending/Filled/etc.   │
│  ├── token_mint (Pubkey)         — which memecoin sold   │
│  ├── token_amount (u64)          — original token amount │
│  └── bump (u8)                                           │
│                                                          │
│  PlayerState (PDA, per-player, persistent)               │
│  seeds: [b"player", player.key()]                        │
│  ├── player (Pubkey)                                     │
│  ├── nonce (u64)                 — next bet nonce        │
│  ├── pending_commitment ([u8;32])— server's SHA256 hash  │
│  ├── pending_nonce (u64)         — nonce for commitment  │
│  ├── active_order (Pubkey)       — current pending order │
│  ├── has_active_order (bool)     — quick check flag      │
│  ├── total_orders (u64)          — lifetime count        │
│  ├── total_wagered (u64)         — lifetime SOL wagered  │
│  ├── total_won (u64)             — lifetime fill profit  │
│  ├── net_pnl (i128)             — net profit/loss        │
│  ├── referrer (Pubkey)           — tier-1 referral parent│
│  ├── tier2_referrer (Pubkey)     — tier-2 (referrer's    │
│  │                                  referrer, set once)  │
│  └── bump (u8)                                           │
│                                                          │
│  ReferralState (PDA, per-referrer, persistent)           │
│  seeds: [b"referral", referrer.key()]                    │
│  ├── referrer (Pubkey)                                   │
│  ├── total_referrals (u32)       — players referred      │
│  ├── total_earnings (u64)        — SOL earned            │
│  └── bump (u8)                                           │
└─────────────────────────────────────────────────────────┘
```

### PDA Seed Summary

| Account | Seeds | Lifecycle |
|---|---|---|
| ClearingHouseState | `[b"clearing_house"]` | Created once at init, never closed |
| Vault | `[b"vault", clearing_house.key()]` | Created once, holds SOL permanently |
| LP Mint | `[b"lp_mint", clearing_house.key()]` | Created once, SPL token mint |
| LP Authority | `[b"lp_authority", clearing_house.key()]` | PDA only (no data), signs CPI |
| FateOrder | `[b"fate_order", player.key(), nonce.to_le_bytes()]` | Created on `place_fate_order`, closed on settle/expire |
| PlayerState | `[b"player", player.key()]` | Created on first bet, persists forever |
| ReferralState | `[b"referral", referrer.key()]` | Created when first referral set, persists |

### Account Size & Rent Costs

| Account | Approx Size | Rent-Exempt (SOL) | Notes |
|---|---|---|---|
| ClearingHouseState | ~716 bytes | ~0.0060 | One-time, paid by deployer (5 bps fields + 3 wallet Pubkeys + stats) |
| FateOrder | ~180 bytes | ~0.0021 | Player pays, reclaimed on close |
| PlayerState | ~242 bytes | ~0.0026 | Settler pays on first commitment (init_if_needed). Includes both referrer + tier2_referrer Pubkeys. |
| ReferralState | ~80 bytes | ~0.0014 | Created when referral set |
| LP Mint | ~82 bytes | ~0.0014 | One-time, paid by deployer |

### Concurrency & Write Lock Analysis

**Critical question**: Does the global `ClearingHouseState` create a bottleneck?

Every `place_fate_order` and `settle_fate_order` must write to `ClearingHouseState` (updating `total_liability`, `unsettled_count`, stats). This means all bets are serialized at the global state level.

**Throughput math**:
- Solana processes ~2-3 conflicting transactions per 400ms slot per write-locked account
- That's ~5-7 global-state writes per second
- At 10,000 bets/day = ~0.12 bets/second average
- Peak 10x = ~1.2 bets/second
- **Well within limits.** No sharding needed.

If FateSwap ever hits 100,000+ bets/day, we can introduce epoch-based accounting (bets write to rolling epoch PDAs, a cranker flushes to global state periodically). Not needed at launch.

---

## 4. Module 1: ClearingHouse (LP Pool)

This is the direct Solana equivalent of ROGUEBankroll.sol's deposit/withdraw/LP token mechanics.

### 4.1 Initialize

Creates the global state, vault PDA, LP mint, and LP authority PDA.

```rust
pub fn initialize(
    ctx: Context<Initialize>,
    fate_fee_bps: u16,       // 150 = 1.5%
    max_bet_bps: u16,        // 10 = 0.1% of net balance (base rate, scaled by multiplier)
    min_bet: u64,             // e.g., 10_000_000 = 0.01 SOL
    bet_timeout: i64,         // 300 = 5 minutes
    platform_wallet: Pubkey,  // Team/treasury wallet for 0.3% platform fee
    bonus_wallet: Pubkey,     // Bonuses wallet for 0.1% bonus fee
    nft_rewarder: Pubkey,     // NFTRewarder vault PDA for 0.3% NFT rewards
) -> Result<()> {
    // --- Validate config parameters (same bounds as update_config) ---
    require!(fate_fee_bps <= 1000, FateSwapError::InvalidConfig); // Max 10% fee
    require!(max_bet_bps <= 500, FateSwapError::InvalidConfig);   // Max 5% of pool
    require!(min_bet > 0, FateSwapError::InvalidConfig);
    require!(bet_timeout >= 60, FateSwapError::InvalidConfig);    // Minimum 60 seconds

    let state = &mut ctx.accounts.clearing_house_state;
    state.authority = ctx.accounts.authority.key();
    state.settler = ctx.accounts.settler.key();
    state.vault_bump = ctx.bumps.vault;
    state.lp_mint_bump = ctx.bumps.lp_mint;
    state.lp_authority_bump = ctx.bumps.lp_authority;
    state.fate_fee_bps = fate_fee_bps;
    state.max_bet_bps = max_bet_bps; // base rate, scaled by multiplier in calculate_max_bet()
    state.min_bet = min_bet;
    state.bet_timeout_seconds = bet_timeout;
    state.paused = false;

    // Revenue split config — all default to 0, set via update_config after deploy
    state.referral_bps = 0;         // Tier-1 referral (target: 20 = 0.2%)
    state.tier2_referral_bps = 0;   // Tier-2 referral (target: 10 = 0.1%)
    state.nft_reward_bps = 0;       // NFT holders (target: 30 = 0.3%)
    state.platform_fee_bps = 0;     // Platform/team (target: 30 = 0.3%)
    state.bonus_bps = 0;            // Bonuses (target: 10 = 0.1%)

    // Revenue split wallets — set at init, updatable via update_config
    state.platform_wallet = platform_wallet;
    state.bonus_wallet = bonus_wallet;
    state.nft_rewarder = nft_rewarder;

    Ok(())
}
```

### 4.2 Deposit SOL → Receive FATE-LP

Direct port of `ROGUEBankroll.depositROGUE()`. Same LP pricing math.

```rust
pub fn deposit_sol(ctx: Context<DepositSol>, amount_lamports: u64) -> Result<()> {
    require!(!ctx.accounts.state.paused, FateSwapError::Paused);
    require!(amount_lamports > 0, FateSwapError::ZeroAmount);

    let state = &mut ctx.accounts.state;

    // --- LP pricing (identical to ROGUEBankroll) ---
    // effective_balance = vault SOL - rent_exempt_minimum
    // This excludes unsettled bets from LP pricing to prevent dilution
    let vault_balance = ctx.accounts.vault.lamports();
    let rent_exempt = Rent::get()?.minimum_balance(8); // vault has 8-byte Anchor discriminator
    let effective_balance = vault_balance
        .saturating_sub(rent_exempt)
        .saturating_sub(state.total_liability); // exclude pending payouts

    let lp_supply = ctx.accounts.lp_mint.supply;

    let lp_to_mint: u64 = if lp_supply == 0 {
        // First deposit: 1:1 ratio (1 LP = 1 lamport), minus MINIMUM_LIQUIDITY
        // burned to dead address to prevent first-depositor donation attack.
        // Without this, an attacker could: deposit 1 lamport → donate SOL to vault →
        // inflate LP price so subsequent depositors receive 0 LP tokens.
        const MINIMUM_LIQUIDITY: u64 = 10_000; // ~0.00001 SOL burned permanently
        require!(amount_lamports > MINIMUM_LIQUIDITY, FateSwapError::DepositTooSmall);
        // Mint MINIMUM_LIQUIDITY to dead address (Pubkey::default / SystemProgram)
        // to ensure lp_supply is never trivially small
        // (implementation: mint MINIMUM_LIQUIDITY to a burn PDA, then continue)
        amount_lamports - MINIMUM_LIQUIDITY
    } else {
        // lp_minted = (deposit * supply) / effective_balance
        // Use u128 to prevent overflow
        let minted = (amount_lamports as u128)
            .checked_mul(lp_supply as u128)
            .ok_or(FateSwapError::MathOverflow)?
            .checked_div(effective_balance as u128)
            .ok_or(FateSwapError::MathOverflow)?;
        require!(minted > 0, FateSwapError::DepositTooSmall);
        minted as u64
    };

    // --- Transfer SOL: depositor → vault PDA ---
    anchor_lang::system_program::transfer(
        CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            anchor_lang::system_program::Transfer {
                from: ctx.accounts.depositor.to_account_info(),
                to: ctx.accounts.vault.to_account_info(),
            },
        ),
        amount_lamports,
    )?;

    // --- Mint FATE-LP tokens to depositor ---
    let ch_key = ctx.accounts.state.key();
    let authority_seeds = &[
        b"lp_authority",
        ch_key.as_ref(),
        &[state.lp_authority_bump],
    ];
    token::mint_to(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            MintTo {
                mint: ctx.accounts.lp_mint.to_account_info(),
                to: ctx.accounts.depositor_lp_account.to_account_info(),
                authority: ctx.accounts.lp_authority.to_account_info(),
            },
            &[authority_seeds],
        ),
        lp_to_mint,
    )?;

    emit!(LiquidityDeposited {
        depositor: ctx.accounts.depositor.key(),
        sol_amount: amount_lamports,
        lp_minted: lp_to_mint,
        vault_balance: ctx.accounts.vault.lamports(),
        lp_supply: ctx.accounts.lp_mint.supply + lp_to_mint,
        timestamp: Clock::get()?.unix_timestamp,
    });

    Ok(())
}
```

**Comparison with ROGUEBankroll.depositROGUE():**

| ROGUEBankroll (EVM) | ClearingHouse (Solana) |
|---|---|
| `msg.value` (ETH sent with call) | `amount_lamports` parameter + `system_program::transfer` |
| `this.totalSupply()` (ERC-20) | `lp_mint.supply` (SPL Token) |
| `hb.total_balance` (storage var) | `vault.lamports()` (account balance) |
| `_mint(msg.sender, amountLPToken)` | CPI to `token::mint_to` with PDA signer |
| Reentrancy guard modifier | Not needed (Solana runtime prevents) |

### 4.3 Burn FATE-LP → Withdraw SOL

Direct port of `ROGUEBankroll.withdrawROGUE()`.

```rust
pub fn withdraw_sol(ctx: Context<WithdrawSol>, lp_amount: u64) -> Result<()> {
    require!(!ctx.accounts.state.paused, FateSwapError::Paused);
    require!(lp_amount > 0, FateSwapError::ZeroAmount);

    let state = &ctx.accounts.state;

    // --- Calculate withdrawable SOL ---
    let vault_balance = ctx.accounts.vault.lamports();
    let rent_exempt = Rent::get()?.minimum_balance(8); // vault has 8-byte Anchor discriminator
    let available = vault_balance
        .saturating_sub(rent_exempt)
        .saturating_sub(state.total_liability);

    let lp_supply = ctx.accounts.lp_mint.supply;

    // sol_out = (lp_amount * available) / lp_supply
    let sol_out = (lp_amount as u128)
        .checked_mul(available as u128)
        .ok_or(FateSwapError::MathOverflow)?
        .checked_div(lp_supply as u128)
        .ok_or(FateSwapError::MathOverflow)? as u64;

    require!(sol_out > 0, FateSwapError::WithdrawTooSmall);
    require!(sol_out <= available, FateSwapError::InsufficientLiquidity);

    // --- Burn LP tokens (user signs, they own the tokens) ---
    token::burn(
        CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Burn {
                mint: ctx.accounts.lp_mint.to_account_info(),
                from: ctx.accounts.withdrawer_lp_account.to_account_info(),
                authority: ctx.accounts.withdrawer.to_account_info(),
            },
        ),
        lp_amount,
    )?;

    // --- Transfer SOL: vault PDA → withdrawer ---
    // Direct lamport manipulation (PDA-owned accounts)
    **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? -= sol_out;
    **ctx.accounts.withdrawer.to_account_info().try_borrow_mut_lamports()? += sol_out;

    emit!(LiquidityWithdrawn {
        withdrawer: ctx.accounts.withdrawer.key(),
        lp_burned: lp_amount,
        sol_withdrawn: sol_out,
        vault_balance: ctx.accounts.vault.lamports(),
        lp_supply: ctx.accounts.lp_mint.supply - lp_amount,
        timestamp: Clock::get()?.unix_timestamp,
    });

    Ok(())
}
```

**Key Solana difference**: We use direct lamport manipulation (`try_borrow_mut_lamports`) to transfer SOL FROM the vault PDA. On EVM, `payable(msg.sender).call{value: amount}("")` handles this. On Solana, `system_program::transfer` requires a signer, but PDAs "sign" via CPI with `invoke_signed`. Direct lamport manipulation is simpler and cheaper — the runtime enforces that only the owning program can debit an account.

### 4.4 LP Token Price

Computed on-demand, not stored (avoids consistency bugs):

```rust
/// Get current FATE-LP price in lamports (18-decimal fixed point)
/// price = effective_balance * 1e18 / lp_supply
pub fn get_lp_price(vault_balance: u64, rent_exempt: u64, liability: u64, lp_supply: u64) -> Result<u64> {
    if lp_supply == 0 {
        return Ok(1_000_000_000_000_000_000); // 1:1 default (1e18)
    }
    let effective = vault_balance
        .saturating_sub(rent_exempt)
        .saturating_sub(liability);
    // price = effective * 1e18 / supply (u128 intermediate, checked cast back to u64)
    let price = (effective as u128)
        .checked_mul(1_000_000_000_000_000_000u128)
        .ok_or(FateSwapError::MathOverflow)?
        / (lp_supply as u128);
    u64::try_from(price).map_err(|_| FateSwapError::MathOverflow.into())
}
```

This is identical to ROGUEBankroll's formula:
```solidity
// EVM equivalent
pool_token_price = ((total_balance - unsettled_bets) * 1e18) / pool_token_supply;
```

### 4.5 How LP Token Price Goes Up

Same mechanic as ROGUEBankroll. When players lose:
1. Their wagered SOL stays in the vault
2. `effective_balance` increases
3. `lp_supply` stays the same
4. `price_per_lp = effective_balance / lp_supply` increases
5. LPs can now withdraw more SOL per LP token than they deposited

When players win:
1. SOL leaves the vault as payout
2. `effective_balance` decreases
3. `price_per_lp` decreases
4. LPs absorb the loss proportionally

This is the exact same mechanism as our EVM bankroll, just implemented with Solana's account model.

---

## 5. Module 2: FateGame (Bet Logic)

### 5.1 FateSwap Mechanics (from concept doc)

A user sets a "target price" for their memecoin, which maps to a multiplier:

| Target Price | Multiplier | Fill Chance | Feels Like |
|---|---|---|---|
| +5% above market | 1.05x | 93.8% | Safe limit order |
| +25% above market | 1.25x | 78.8% | Optimistic sell |
| +50% above market | 1.50x | 65.7% | Bullish conviction |
| +100% above market | 2.00x | 49.3% | Coin flip moonshot |
| +400% above market | 5.00x | 19.7% | Full degen |
| +900% above market | 10.0x | 9.9% | Lottery ticket |

> **Note**: Multipliers use discrete steps — see [Section 5.2](#52-supported-multiplier-range-discrete-steps) for the 210 allowed values.

**Fill chance formula**: `fill_chance = (1 / multiplier) × (1 − fate_fee)`
Where `fate_fee = 0.015` (1.5%)

**Off-chain math** (basis points — computed by server, NOT on-chain):
```
fill_chance_bps = (MULTIPLIER_BASE * (10000 - fate_fee_bps)) / multiplier_bps
```
This restructured formula avoids destructive integer division. Do NOT divide first then multiply.

Where `multiplier_bps` uses 100000 as 1.0x (5 decimal places for precision):
- 1.05x = 105000
- 2.00x = 200000
- 10.0x = 1000000

### 5.2 Supported Multiplier Range (Discrete Steps)

```rust
const MIN_MULTIPLIER: u32 = 101_000;   // 1.01x (~99% fill chance)
const MAX_MULTIPLIER: u32 = 1_000_000; // 10.0x (~10% fill chance)
const MULTIPLIER_BASE: u64 = 100_000;  // 1.0x reference
```

FateSwap uses **210 discrete multiplier values** across 6 tiers with progressively coarser steps at higher payouts. This gives fine-grained control where it matters most (low multipliers where most users play) while keeping the selection manageable at high multipliers.

| Tier | Display Range | Step | BPS Range | BPS Step | Count |
|------|---------------|------|-----------|----------|-------|
| 1 | 1.01x – 1.99x | 0.01 | 101,000 – 199,000 | 1,000 | 99 |
| 2 | 2.00x – 2.98x | 0.02 | 200,000 – 298,000 | 2,000 | 50 |
| 3 | 3.00x – 3.95x | 0.05 | 300,000 – 395,000 | 5,000 | 20 |
| 4 | 4.0x – 5.9x | 0.10 | 400,000 – 590,000 | 10,000 | 20 |
| 5 | 6.0x – 9.8x | 0.20 | 600,000 – 980,000 | 20,000 | 20 |
| 6 | 10.0x | — | 1,000,000 | — | 1 |

**On-chain validation** — the program validates both range AND step alignment:

```rust
/// Returns true if multiplier_bps is one of the 210 allowed discrete values.
#[inline(always)]
fn is_valid_multiplier(multiplier_bps: u32) -> bool {
    match multiplier_bps {
        101_000..=199_000 => (multiplier_bps - 101_000) % 1_000 == 0,   // step 1,000
        200_000..=298_000 => (multiplier_bps - 200_000) % 2_000 == 0,   // step 2,000
        300_000..=395_000 => (multiplier_bps - 300_000) % 5_000 == 0,   // step 5,000
        400_000..=590_000 => (multiplier_bps - 400_000) % 10_000 == 0,  // step 10,000
        600_000..=980_000 => (multiplier_bps - 600_000) % 20_000 == 0,  // step 20,000
        1_000_000 => true,                                               // 10.0x
        _ => false,
    }
}
```

The UI slider maps to an array index (0–209) that maps to the corresponding BPS value. The server and on-chain program both validate step alignment independently.

### 5.3 Submit Commitment (Server → Chain)

Identical to BuxBoosterGame V3's commitment pattern:

```rust
/// Server submits SHA256(server_seed) BEFORE player can bet.
/// This anchors the randomness before the player commits funds.
pub fn submit_commitment(
    ctx: Context<SubmitCommitment>,
    commitment_hash: [u8; 32],
    player: Pubkey,
    nonce: u64,
) -> Result<()> {
    let state = &ctx.accounts.state;
    require!(!state.paused, FateSwapError::Paused);

    // Only the authorized settler can submit commitments
    require!(
        ctx.accounts.settler.key() == state.settler,
        FateSwapError::UnauthorizedSettler
    );

    // Store commitment in the player's state
    let player_state = &mut ctx.accounts.player_state;

    // Set player pubkey on first init (init_if_needed leaves it as default)
    if player_state.player == Pubkey::default() {
        player_state.player = player;
    }

    player_state.pending_commitment = commitment_hash;
    player_state.pending_nonce = nonce;

    emit!(CommitmentSubmitted {
        player,
        commitment_hash,
        nonce,
        timestamp: Clock::get()?.unix_timestamp,
    });

    Ok(())
}
```

**Why store on PlayerState instead of a separate commitment PDA?**
In BuxBoosterGame, we stored commitments in a mapping `playerCommitments[player][nonce] → hash`. On Solana, creating a PDA per commitment adds rent cost. Since a player can only have one pending commitment at a time, storing it on the persistent `PlayerState` is cheaper and simpler.

### 5.4 Place Fate Order (Player → Chain)

This is the core bet placement instruction. The player references the server's commitment and deposits SOL.

```rust
/// Player places a fate order. SOL is transferred from player to vault.
/// The commitment_hash must match what the server previously submitted.
pub fn place_fate_order(
    ctx: Context<PlaceFateOrder>,
    nonce: u64,
    multiplier_bps: u32,      // 101000 (1.01x) to 1000000 (10x)
    sol_amount: u64,           // SOL to wager (in lamports) — from Jupiter swap output or direct deposit
    // Optional metadata (which token they're "selling")
    token_mint: Pubkey,        // e.g., BONK mint address
    token_amount: u64,         // original token amount (for display/events)
) -> Result<()> {
    let state = &mut ctx.accounts.state;
    require!(!state.paused, FateSwapError::Paused);

    let player_state = &mut ctx.accounts.player_state;

    // --- Validate multiplier (must be one of the 210 discrete allowed values) ---
    require!(
        is_valid_multiplier(multiplier_bps),
        FateSwapError::InvalidMultiplier
    );

    // --- Validate nonce matches commitment ---
    require!(
        nonce == player_state.pending_nonce,
        FateSwapError::NonceMismatch
    );
    require!(
        player_state.pending_commitment != [0u8; 32],
        FateSwapError::NoCommitment
    );

    // --- Validate no active order ---
    require!(
        !player_state.has_active_order,
        FateSwapError::ActiveOrderExists
    );

    // --- Calculate potential payout ---
    // payout = amount * multiplier / 100000
    let potential_payout_u128 = (sol_amount as u128)
        .checked_mul(multiplier_bps as u128)
        .ok_or(FateSwapError::MathOverflow)?
        .checked_div(MULTIPLIER_BASE as u128)
        .ok_or(FateSwapError::MathOverflow)?;
    let potential_payout = u64::try_from(potential_payout_u128)
        .map_err(|_| FateSwapError::MathOverflow)?;

    // --- Validate bet size ---
    require!(sol_amount >= state.min_bet, FateSwapError::BetTooSmall);

    let vault_balance = ctx.accounts.vault.lamports();
    let rent_exempt = Rent::get()?.minimum_balance(8); // vault has 8-byte Anchor discriminator
    let net_balance = vault_balance
        .saturating_sub(rent_exempt)
        .saturating_sub(state.total_liability);

    // Max bet scales inversely with multiplier (same as BuxBoosterGame._calculateMaxBet)
    // Lower multipliers = higher win rate = larger max bet but tiny profit per win
    // Higher multipliers = lower win rate = smaller max bet but large profit per win
    // Example (100 SOL bank, max_bet_bps=10):
    //   1.01x: max_bet = 1.980 SOL, profit = 0.020 SOL  (wins ~99%)
    //   2x:    max_bet = 1.000 SOL, profit = 1.000 SOL  (wins ~50%)
    //   10x:   max_bet = 0.200 SOL, profit = 1.800 SOL  (wins ~10%)
    let max_bet = calculate_max_bet(net_balance, state.max_bet_bps, multiplier_bps);

    require!(sol_amount <= max_bet, FateSwapError::BetTooLarge);

    // --- Validate vault can cover potential payout ---
    require!(
        net_balance >= potential_payout,
        FateSwapError::InsufficientVaultBalance
    );

    // --- Transfer SOL: player → vault ---
    anchor_lang::system_program::transfer(
        CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            anchor_lang::system_program::Transfer {
                from: ctx.accounts.player.to_account_info(),
                to: ctx.accounts.vault.to_account_info(),
            },
        ),
        sol_amount,
    )?;

    // --- Update global state ---
    state.total_liability = state.total_liability
        .checked_add(potential_payout)
        .ok_or(FateSwapError::MathOverflow)?;
    state.unsettled_count = state.unsettled_count
        .checked_add(1)
        .ok_or(FateSwapError::MathOverflow)?;

    // --- Initialize FateOrder PDA ---
    let order = &mut ctx.accounts.fate_order;
    order.player = ctx.accounts.player.key();
    order.amount = sol_amount;
    order.multiplier_bps = multiplier_bps;
    order.potential_payout = potential_payout;
    order.commitment_hash = player_state.pending_commitment;
    order.nonce = nonce;
    order.timestamp = Clock::get()?.unix_timestamp;
    order.status = FateOrderStatus::Pending;
    order.token_mint = token_mint;
    order.token_amount = token_amount;
    order.bump = ctx.bumps.fate_order;

    // --- Update player state ---
    player_state.active_order = order.key();
    player_state.has_active_order = true;
    player_state.nonce = nonce + 1; // increment for next bet
    player_state.pending_commitment = [0u8; 32]; // clear commitment

    emit!(FateOrderPlaced {
        player: ctx.accounts.player.key(),
        order: order.key(),
        sol_amount,
        multiplier_bps,
        potential_payout,
        commitment_hash: order.commitment_hash,
        nonce,
        token_mint,
        token_amount,
        timestamp: order.timestamp,
    });

    Ok(())
}
```

**Comparison with BuxBoosterGame.placeBetROGUE():**

| BuxBoosterGame (EVM) | FateGame (Solana) |
|---|---|
| `msg.value` is the wager | `sol_amount` param + `system_program::transfer` |
| `bets[commitmentHash]` mapping | FateOrder PDA (created with `init`) |
| `playerNonces[player]++` | `player_state.nonce += 1` |
| `rogueBankroll.updateHouseBalanceBuxBoosterBetPlaced{value: msg.value}(...)` | Direct state update (single program) |
| `_calculateMaxBet(balance, diffIndex)` | `calculate_max_bet(balance, max_bet_bps, multiplier_bps)` |
| Fixed difficulty levels (-4 to 5) | Any multiplier from 1.01x to 10x |

### 5.5 Settle Fate Order (Server → Chain)

The server tells the program the outcome (`filled: bool`) and reveals the `server_seed`. **The program verifies `SHA256(server_seed) == commitment_hash`** to prevent seed substitution, but trusts the settler's `filled` bool (no outcome recomputation on-chain). The outcome can be independently verified off-chain by anyone using the commitment hash, revealed seed, player pubkey, and nonce — all stored in on-chain events.

**Why hybrid verification?** Full on-chain verification (hash commitment + outcome recomputation) was a source of bugs in BuxBoosterGame. The seed check alone (~20K CU) prevents the most dangerous attack (settler substituting a different seed), while outcome verification is left to off-chain auditors. If the settler claims the wrong outcome, the mismatch is publicly provable from event data.

```rust
/// Server settles a fate order by providing the outcome and revealing the server seed.
/// The program trusts the authorized settler for the outcome.
/// The server_seed is emitted in the event for off-chain provably fair verification.
pub fn settle_fate_order(
    ctx: Context<SettleFateOrder>,
    filled: bool,
    server_seed: [u8; 32],
) -> Result<()> {
    // Read order fields into local vars before mutable borrows (Rust borrow checker)
    let order_status = ctx.accounts.fate_order.status;
    let order_timestamp = ctx.accounts.fate_order.timestamp;
    let order_amount = ctx.accounts.fate_order.amount;
    let order_potential_payout = ctx.accounts.fate_order.potential_payout;
    let order_commitment_hash = ctx.accounts.fate_order.commitment_hash;
    let order_player = ctx.accounts.fate_order.player;
    let order_nonce = ctx.accounts.fate_order.nonce;
    let order_multiplier_bps = ctx.accounts.fate_order.multiplier_bps;
    let order_token_mint = ctx.accounts.fate_order.token_mint;
    let order_token_amount = ctx.accounts.fate_order.token_amount;

    let state = &mut ctx.accounts.state;

    // --- Verify order is pending ---
    require!(
        order_status == FateOrderStatus::Pending,
        FateSwapError::OrderNotPending
    );

    // --- Verify timeout hasn't elapsed ---
    let clock = Clock::get()?;
    require!(
        clock.unix_timestamp <= order_timestamp + state.bet_timeout_seconds,
        FateSwapError::OrderExpired
    );

    // --- Verify commitment hash (proves settler revealed the real seed) ---
    // This prevents seed substitution: the settler MUST reveal the seed
    // that was committed before the player bet. Without this check, a
    // malicious settler could reveal a different seed to flip the outcome.
    let computed_hash = solana_program::hash::hash(&server_seed);
    require!(
        computed_hash.to_bytes() == order_commitment_hash,
        FateSwapError::InvalidServerSeed
    );

    // Outcome computation (filled/not-filled) is still trusted from the settler.
    // Off-chain verification of the outcome is possible by anyone:
    //   1. Get server_seed from FateOrderSettled event
    //   2. Compute: SHA256(server_seed || player_pubkey || nonce) → roll
    //   3. Compare roll against threshold for multiplier + fee → verify filled/not-filled

    // --- Release liability ---
    state.total_liability = state.total_liability
        .saturating_sub(order_potential_payout);
    state.unsettled_count = state.unsettled_count.saturating_sub(1);
    state.total_bets = state.total_bets.checked_add(1).unwrap_or(u64::MAX);
    state.total_volume = state.total_volume
        .checked_add(order_amount as u128)
        .unwrap_or(u128::MAX);

    let mut payout: u64 = 0;

    if filled {
        // --- FILLED: Pay player ---
        payout = order_potential_payout;

        // Transfer SOL from vault to player
        let vault = &ctx.accounts.vault;
        let player = &ctx.accounts.player;
        **vault.to_account_info().try_borrow_mut_lamports()? -= payout;
        **player.to_account_info().try_borrow_mut_lamports()? += payout;

        // Update stats
        state.total_filled = state.total_filled.checked_add(1).unwrap_or(u64::MAX);
        let profit = payout as i128 - order_amount as i128;
        state.house_profit = state.house_profit.checked_sub(profit).unwrap_or(i128::MIN);

        // Update player stats
        let player_state = &mut ctx.accounts.player_state;
        // total_won tracks cumulative profit from fills (payout - wager), not total payout
        player_state.total_won = player_state.total_won
            .checked_add(payout - order_amount)
            .unwrap_or(u64::MAX);
        player_state.net_pnl = player_state.net_pnl
            .checked_add(profit)
            .unwrap_or(i128::MAX);
    } else {
        // --- NOT FILLED: House keeps wager ---
        // SOL already in vault, nothing to transfer

        state.total_not_filled = state.total_not_filled.checked_add(1).unwrap_or(u64::MAX);
        // Gross profit before 1.0% reward deductions (referral, NFT, platform, bonus, tier-2)
        state.house_profit = state.house_profit
            .checked_add(order_amount as i128)
            .unwrap_or(i128::MAX);

        // Update player stats
        let player_state = &mut ctx.accounts.player_state;
        player_state.net_pnl = player_state.net_pnl
            .checked_sub(order_amount as i128)
            .unwrap_or(i128::MIN);

        // --- Revenue distribution: 5-way split on losses (1.0% total) ---
        // All transfers are non-blocking: failure doesn't revert settlement.
        // See Section 9 for full implementation details.

        let vault_info = ctx.accounts.vault.to_account_info();

        let order_key = ctx.accounts.fate_order.key();

        // 1. Tier-1 referral (0.2% = 20 bps)
        if player_state.referrer != Pubkey::default() {
            match _send_reward(&vault_info, &ctx.accounts.referrer.to_account_info(), state.referral_bps, order_amount) {
                Ok(reward) if reward > 0 => {
                    if let Some(ref mut rs) = ctx.accounts.referral_state {
                        rs.total_earnings = rs.total_earnings.checked_add(reward).unwrap_or(u64::MAX);
                    }
                    emit!(RewardPaid {
                        recipient: ctx.accounts.referrer.key(),
                        player: order_player, order: order_key,
                        reward_type: 0, reward_amount: reward, bps: state.referral_bps,
                        timestamp: clock.unix_timestamp,
                    });
                },
                Ok(_) => {},
                Err(e) => msg!("Tier-1 referral failed (non-blocking): {:?}", e),
            }
        }

        // 2. Tier-2 referral (0.1% = 10 bps)
        if player_state.tier2_referrer != Pubkey::default() {
            match _send_reward(&vault_info, &ctx.accounts.tier2_referrer.to_account_info(), state.tier2_referral_bps, order_amount) {
                Ok(reward) if reward > 0 => {
                    if let Some(ref mut rs) = ctx.accounts.tier2_referral_state {
                        rs.total_earnings = rs.total_earnings.checked_add(reward).unwrap_or(u64::MAX);
                    }
                    emit!(RewardPaid {
                        recipient: ctx.accounts.tier2_referrer.key(),
                        player: order_player, order: order_key,
                        reward_type: 1, reward_amount: reward, bps: state.tier2_referral_bps,
                        timestamp: clock.unix_timestamp,
                    });
                },
                Ok(_) => {},
                Err(e) => msg!("Tier-2 referral failed (non-blocking): {:?}", e),
            }
        }

        // 3. NFT holders (0.3% = 30 bps) — direct lamport transfer to NFTRewarder vault PDA.
        // NFTRewarder uses a sync_rewards crank to detect balance changes and update its
        // MasterChef accumulator. Direct transfer is cheaper than CPI (~5K CU saved per settle).
        match _send_reward(&vault_info, &ctx.accounts.nft_rewarder.to_account_info(), state.nft_reward_bps, order_amount) {
            Ok(reward) if reward > 0 => {
                emit!(RewardPaid {
                    recipient: ctx.accounts.nft_rewarder.key(),
                    player: order_player, order: order_key,
                    reward_type: 2, reward_amount: reward, bps: state.nft_reward_bps,
                    timestamp: clock.unix_timestamp,
                });
            },
            Ok(_) => {},
            Err(e) => msg!("NFT reward failed (non-blocking): {:?}", e),
        }

        // 4. Platform/team (0.3% = 30 bps)
        match _send_reward(&vault_info, &ctx.accounts.platform_wallet.to_account_info(), state.platform_fee_bps, order_amount) {
            Ok(reward) if reward > 0 => {
                emit!(RewardPaid {
                    recipient: ctx.accounts.platform_wallet.key(),
                    player: order_player, order: order_key,
                    reward_type: 3, reward_amount: reward, bps: state.platform_fee_bps,
                    timestamp: clock.unix_timestamp,
                });
            },
            Ok(_) => {},
            Err(e) => msg!("Platform fee failed (non-blocking): {:?}", e),
        }

        // 5. Bonuses (0.1% = 10 bps)
        match _send_reward(&vault_info, &ctx.accounts.bonus_wallet.to_account_info(), state.bonus_bps, order_amount) {
            Ok(reward) if reward > 0 => {
                emit!(RewardPaid {
                    recipient: ctx.accounts.bonus_wallet.key(),
                    player: order_player, order: order_key,
                    reward_type: 4, reward_amount: reward, bps: state.bonus_bps,
                    timestamp: clock.unix_timestamp,
                });
            },
            Ok(_) => {},
            Err(e) => msg!("Bonus fee failed (non-blocking): {:?}", e),
        }
    }

    // --- Update FateOrder status ---
    let order = &mut ctx.accounts.fate_order;
    order.status = if filled { FateOrderStatus::Filled } else { FateOrderStatus::NotFilled };

    // --- Clear player's active order ---
    let player_state = &mut ctx.accounts.player_state;
    player_state.has_active_order = false;
    player_state.active_order = Pubkey::default();
    player_state.total_orders = player_state.total_orders.checked_add(1).unwrap_or(u64::MAX);
    player_state.total_wagered = player_state.total_wagered
        .checked_add(order_amount)
        .unwrap_or(u64::MAX);

    emit!(FateOrderSettled {
        player: order_player,
        order: ctx.accounts.fate_order.key(),
        filled,
        sol_wagered: order_amount,
        payout,
        multiplier_bps: order_multiplier_bps,
        server_seed,              // Revealed for off-chain provably fair verification
        nonce: order_nonce,
        token_mint: order_token_mint,
        token_amount: order_token_amount,
        timestamp: clock.unix_timestamp,
    });

    // Note: FateOrder account is closed via Anchor's `close = player`
    // constraint, returning rent to the player

    Ok(())
}
```

### 5.6 Reclaim Expired Order (Player → Chain)

If the server fails to settle within the timeout, the player can reclaim their SOL. This is the safety valve — identical to BuxBoosterGame's `refundExpiredBet()`.

```rust
/// Player reclaims their SOL if the server fails to settle within timeout.
pub fn reclaim_expired_order(ctx: Context<ReclaimExpiredOrder>) -> Result<()> {
    let order = &ctx.accounts.fate_order;
    let state = &mut ctx.accounts.state;
    let clock = Clock::get()?;

    // Verify timeout has elapsed
    require!(
        clock.unix_timestamp > order.timestamp + state.bet_timeout_seconds,
        FateSwapError::OrderNotExpired
    );

    // Verify order is still pending
    require!(
        order.status == FateOrderStatus::Pending,
        FateSwapError::OrderNotPending
    );

    // Transfer SOL back from vault to player
    let vault = &ctx.accounts.vault;
    let player = &ctx.accounts.player;
    **vault.to_account_info().try_borrow_mut_lamports()? -= order.amount;
    **player.to_account_info().try_borrow_mut_lamports()? += order.amount;

    // Release liability
    state.total_liability = state.total_liability
        .saturating_sub(order.potential_payout);
    state.unsettled_count = state.unsettled_count.saturating_sub(1);

    // Clear player's active order
    let player_state = &mut ctx.accounts.player_state;
    player_state.has_active_order = false;
    player_state.active_order = Pubkey::default();

    // Order account closed via `close = player` constraint

    emit!(FateOrderReclaimed {
        player: order.player,
        order: ctx.accounts.fate_order.key(),
        sol_refunded: order.amount,
        nonce: order.nonce,
        timestamp: clock.unix_timestamp,
    });

    Ok(())
}
```

### 5.7 Buy-Side Orders (Discount Buying)

The FateSwap program handles **both sell-side and buy-side** because the on-chain logic is identical. The program only ever handles SOL — it accepts SOL in, applies a multiplier, and pays SOL out. The difference between sell-side and buy-side is purely the **transaction ordering** on the client side.

**Sell-side framing**: "I'm selling my memecoin at a target price above market."
- User swaps memecoin to SOL via Jupiter **before** placing the fate order
- If filled: user receives SOL at their target multiplier (effectively sold high)
- If not filled: user loses the SOL (effectively sold at market but lost the proceeds)

**Buy-side framing**: "I'm buying a memecoin at a discount below market."
- User places the fate order with raw SOL (no preceding Jupiter swap)
- If filled: user receives multiplied SOL, then swaps SOL to memecoin via Jupiter **after** settlement
- If not filled: user loses the SOL (didn't get the discount)

#### Discount-to-Multiplier Mapping

The buy discount maps directly to the multiplier: **`multiplier = 1 / (1 - discount)`**

The UI snaps to the nearest valid discrete multiplier. Examples:

- Buy at 99% of market (1% discount) → **1.01x** multiplier
- Buy at 98% of market (2% discount) → **1.02x** multiplier
- Buy at 50% of market (50% discount) → **2.00x** multiplier
- Buy at 10% of market (90% discount) → **10.0x** multiplier

#### Buy-Side Bet Limits ($100k Bankroll)

| Buy Price | Discount | Multiplier | Max Bet | Max Profit | Fill Chance |
|---|---|---|---|---|---|
| 99% of market | 1% off | 1.01x | $198.02 | $1.98 | ~99% |
| 98% of market | 2% off | 1.02x | $196.08 | $3.92 | ~98% |
| 90% of market | 10% off | 1.10x | $181.82 | $18.18 | ~91% |
| 80% of market | 20% off | 1.25x | $160.00 | $40.00 | ~80% |
| 50% of market | 50% off | 2.00x | $100.00 | $100.00 | ~50% |
| 20% of market | 80% off | 5.00x | $40.00 | $160.00 | ~20% |
| 10% of market | 90% off | 10.0x | $20.00 | $180.00 | ~10% |

#### Buy-Side Transaction Flow

```
BUY SIDE (3 TXs — same on-chain instructions, different client ordering):

  TX0: submit_commitment (server signs)
    └── Server submits SHA256(server_seed) for this nonce

  TX1: place_fate_order (player signs)
    └── Player deposits raw SOL (no preceding Jupiter swap)
    └── token_mint = target memecoin address (metadata only)
    └── token_amount = 0 (no token involved yet, metadata only)

  TX2: settle_fate_order (server signs)
    ├── FILLED (player online) → 1 TX partial-sign:
    │   settle_fate_order (settler signs) + Jupiter swap (player co-signs)
    │   Player receives tokens directly in 1 atomic TX
    ├── FILLED (player offline) → Fallback server-only TX:
    │   settle_fate_order → player receives SOL, swaps manually later
    └── NOT FILLED → SOL stays in vault
```

Compare with sell-side:
```
SELL SIDE (3 TXs — includes Jupiter swap before bet):

  TX0: submit_commitment (server signs)
    └── Server submits SHA256(server_seed) for this nonce

  TX1: Jupiter swap + place_fate_order (player signs, multi-instruction)
    ├── IX 0-4: Jupiter swapInstruction (memecoin → SOL)
    └── IX 5:   FateSwap.place_fate_order (SOL into vault)
    └── token_mint = memecoin that was sold (metadata)
    └── token_amount = original token amount pre-swap (metadata)

  TX2: settle_fate_order (server signs)
    ├── FILLED → SOL paid from vault to player (sold high!)
    └── NOT FILLED → SOL stays in vault (sold at market, lost proceeds)
```

#### Key Implementation Note

The `token_mint` and `token_amount` fields on `FateOrder` are **metadata only** — they exist for display purposes and event logging. The program never reads, holds, or transfers any SPL token. It only ever handles native SOL. This means:

- **No token account validation** is needed on-chain
- **No CPI to the Token Program** during bet placement or settlement
- **Zero inventory risk** — the vault only holds SOL
- **Buy-side and sell-side use identical instructions** — the client decides when to invoke Jupiter

### 5.8 Anchor Account Context Structs

Every Anchor instruction requires a `#[derive(Accounts)]` struct that declares which accounts are needed, their constraints, and their relationships. These structs are validated by Anchor at deserialization time, before any instruction logic runs.

#### Initialize

```rust
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    /// The authorized settler wallet (server that submits commitments and settles)
    /// CHECK: This is just stored as a Pubkey, validated on usage
    pub settler: UncheckedAccount<'info>,

    #[account(
        init,
        seeds = [b"clearing_house"],
        bump,
        payer = authority,
        space = 8 + ClearingHouseState::INIT_SPACE,
    )]
    pub clearing_house_state: Account<'info, ClearingHouseState>,

    /// Vault PDA that holds all native SOL
    #[account(
        init,
        seeds = [b"vault", clearing_house_state.key().as_ref()],
        bump,
        payer = authority,
        space = 8, // Anchor discriminator only — makes vault program-owned so we can debit via direct lamport manipulation
    )]
    /// CHECK: Vault is a PDA owned by the FateSwap program, holds SOL
    pub vault: UncheckedAccount<'info>,

    /// LP token mint (FATE-LP), PDA-controlled
    #[account(
        init,
        seeds = [b"lp_mint", clearing_house_state.key().as_ref()],
        bump,
        payer = authority,
        mint::decimals = 9,
        mint::authority = lp_authority,
    )]
    pub lp_mint: Account<'info, Mint>,

    /// PDA that has mint/burn authority over the LP token
    /// CHECK: PDA derived from seeds, no data stored
    #[account(
        seeds = [b"lp_authority", clearing_house_state.key().as_ref()],
        bump,
    )]
    pub lp_authority: UncheckedAccount<'info>,

    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
    // Note: Rent sysvar not needed as account — use Rent::get() from sysvar cache instead
}
```

#### DepositSol

```rust
#[derive(Accounts)]
pub struct DepositSol<'info> {
    #[account(mut)]
    pub depositor: Signer<'info>,

    #[account(
        mut,
        seeds = [b"clearing_house"],
        bump,
    )]
    pub state: Account<'info, ClearingHouseState>,

    /// CHECK: Vault PDA, verified by seeds
    #[account(
        mut,
        seeds = [b"vault", state.key().as_ref()],
        bump = state.vault_bump,
    )]
    pub vault: UncheckedAccount<'info>,

    #[account(
        mut,
        seeds = [b"lp_mint", state.key().as_ref()],
        bump = state.lp_mint_bump,
    )]
    pub lp_mint: Account<'info, Mint>,

    /// CHECK: LP authority PDA, verified by seeds
    #[account(
        seeds = [b"lp_authority", state.key().as_ref()],
        bump = state.lp_authority_bump,
    )]
    pub lp_authority: UncheckedAccount<'info>,

    /// Depositor's LP token account (ATA)
    #[account(
        mut,
        associated_token::mint = lp_mint,
        associated_token::authority = depositor,
    )]
    pub depositor_lp_account: Account<'info, TokenAccount>,

    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
}
```

#### WithdrawSol

```rust
#[derive(Accounts)]
pub struct WithdrawSol<'info> {
    #[account(mut)]
    pub withdrawer: Signer<'info>,

    #[account(
        mut,
        seeds = [b"clearing_house"],
        bump,
    )]
    pub state: Account<'info, ClearingHouseState>,

    /// CHECK: Vault PDA, verified by seeds
    #[account(
        mut,
        seeds = [b"vault", state.key().as_ref()],
        bump = state.vault_bump,
    )]
    pub vault: UncheckedAccount<'info>,

    #[account(
        mut,
        seeds = [b"lp_mint", state.key().as_ref()],
        bump = state.lp_mint_bump,
    )]
    pub lp_mint: Account<'info, Mint>,

    /// Withdrawer's LP token account
    #[account(
        mut,
        associated_token::mint = lp_mint,
        associated_token::authority = withdrawer,
    )]
    pub withdrawer_lp_account: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}
```

#### SubmitCommitment

```rust
#[derive(Accounts)]
#[instruction(commitment_hash: [u8; 32], player: Pubkey, nonce: u64)]
pub struct SubmitCommitment<'info> {
    #[account(mut)]
    pub settler: Signer<'info>,

    #[account(
        seeds = [b"clearing_house"],
        bump,
        has_one = settler @ FateSwapError::UnauthorizedSettler,
    )]
    pub state: Account<'info, ClearingHouseState>,

    #[account(
        init_if_needed,
        seeds = [b"player", player.as_ref()],
        bump,
        payer = settler,
        space = 8 + PlayerState::INIT_SPACE,
    )]
    pub player_state: Account<'info, PlayerState>,

    pub system_program: Program<'info, System>,
}
```

#### PlaceFateOrder

```rust
#[derive(Accounts)]
#[instruction(nonce: u64, multiplier_bps: u32, sol_amount: u64, token_mint: Pubkey, token_amount: u64)]
pub struct PlaceFateOrder<'info> {
    #[account(mut)]
    pub player: Signer<'info>,

    #[account(
        mut,
        seeds = [b"clearing_house"],
        bump,
    )]
    pub state: Account<'info, ClearingHouseState>,

    /// CHECK: Vault PDA, verified by seeds
    #[account(
        mut,
        seeds = [b"vault", state.key().as_ref()],
        bump = state.vault_bump,
    )]
    pub vault: UncheckedAccount<'info>,

    #[account(
        mut,
        seeds = [b"player", player.key().as_ref()],
        bump = player_state.bump,
        constraint = !player_state.has_active_order @ FateSwapError::ActiveOrderExists,
    )]
    pub player_state: Account<'info, PlayerState>,

    #[account(
        init,
        seeds = [b"fate_order", player.key().as_ref(), &nonce.to_le_bytes()],
        bump,
        payer = player,
        space = 8 + FateOrder::INIT_SPACE,
    )]
    pub fate_order: Account<'info, FateOrder>,

    pub system_program: Program<'info, System>,
}
```

#### SettleFateOrder

```rust
#[derive(Accounts)]
#[instruction(filled: bool, server_seed: [u8; 32])]
pub struct SettleFateOrder<'info> {
    #[account(mut)]
    pub settler: Signer<'info>,

    #[account(
        mut,
        seeds = [b"clearing_house"],
        bump,
        has_one = settler @ FateSwapError::UnauthorizedSettler,
    )]
    pub state: Account<'info, ClearingHouseState>,

    /// CHECK: Vault PDA, verified by seeds
    #[account(
        mut,
        seeds = [b"vault", state.key().as_ref()],
        bump = state.vault_bump,
    )]
    pub vault: UncheckedAccount<'info>,

    /// CHECK: Player receives payout, verified via fate_order.player
    #[account(
        mut,
        constraint = player.key() == fate_order.player @ FateSwapError::InvalidPlayer,
    )]
    pub player: UncheckedAccount<'info>,

    #[account(
        mut,
        seeds = [b"player", player.key().as_ref()],
        bump = player_state.bump,
    )]
    pub player_state: Account<'info, PlayerState>,

    #[account(
        mut,
        seeds = [b"fate_order", player.key().as_ref(), &fate_order.nonce.to_le_bytes()],
        bump = fate_order.bump,
        constraint = fate_order.status == FateOrderStatus::Pending @ FateSwapError::OrderNotPending,
        close = player, // Return rent to player on settlement
    )]
    pub fate_order: Account<'info, FateOrder>,

    // --- Revenue Distribution Accounts (5 recipients on losses) ---

    /// CHECK: Tier-1 referrer wallet — must match player_state.referrer
    #[account(
        mut,
        constraint = referrer.key() == player_state.referrer
            || player_state.referrer == Pubkey::default()
            @ FateSwapError::InvalidReferrer,
    )]
    pub referrer: UncheckedAccount<'info>,

    /// Tier-1 referral tracking state
    #[account(
        mut,
        seeds = [b"referral", referrer.key().as_ref()],
        bump = referral_state.bump,
    )]
    pub referral_state: Option<Account<'info, ReferralState>>,

    /// CHECK: Tier-2 referrer wallet — must match player_state.tier2_referrer
    #[account(
        mut,
        constraint = tier2_referrer.key() == player_state.tier2_referrer
            || player_state.tier2_referrer == Pubkey::default()
            @ FateSwapError::InvalidReferrer,
    )]
    pub tier2_referrer: UncheckedAccount<'info>,

    /// Tier-2 referral tracking state
    #[account(
        mut,
        seeds = [b"referral", tier2_referrer.key().as_ref()],
        bump = tier2_referral_state.bump,
    )]
    pub tier2_referral_state: Option<Account<'info, ReferralState>>,

    /// CHECK: NFTRewarder vault PDA — receives 0.3% for NFT holder distribution
    #[account(
        mut,
        constraint = nft_rewarder.key() == state.nft_rewarder
            @ FateSwapError::InvalidNFTRewarder,
    )]
    pub nft_rewarder: UncheckedAccount<'info>,

    /// CHECK: Platform/team wallet — receives 0.3%
    #[account(
        mut,
        constraint = platform_wallet.key() == state.platform_wallet
            @ FateSwapError::InvalidPlatformWallet,
    )]
    pub platform_wallet: UncheckedAccount<'info>,

    /// CHECK: Bonuses wallet — receives 0.1%
    #[account(
        mut,
        constraint = bonus_wallet.key() == state.bonus_wallet
            @ FateSwapError::InvalidBonusWallet,
    )]
    pub bonus_wallet: UncheckedAccount<'info>,

    pub system_program: Program<'info, System>,
}
```

**Account count**: 13 accounts total. Well within Solana's per-TX limit. The settler builds this instruction server-side, so the additional accounts add no UX complexity — the player never signs the settlement TX.

#### ReclaimExpiredOrder

```rust
#[derive(Accounts)]
pub struct ReclaimExpiredOrder<'info> {
    #[account(mut)]
    pub player: Signer<'info>,

    #[account(
        mut,
        seeds = [b"clearing_house"],
        bump,
    )]
    pub state: Account<'info, ClearingHouseState>,

    /// CHECK: Vault PDA, verified by seeds
    #[account(
        mut,
        seeds = [b"vault", state.key().as_ref()],
        bump = state.vault_bump,
    )]
    pub vault: UncheckedAccount<'info>,

    #[account(
        mut,
        seeds = [b"player", player.key().as_ref()],
        bump = player_state.bump,
    )]
    pub player_state: Account<'info, PlayerState>,

    #[account(
        mut,
        seeds = [b"fate_order", player.key().as_ref(), &fate_order.nonce.to_le_bytes()],
        bump = fate_order.bump,
        has_one = player,
        constraint = fate_order.status == FateOrderStatus::Pending @ FateSwapError::OrderNotPending,
        close = player, // Return rent to player
    )]
    pub fate_order: Account<'info, FateOrder>,
}
```

#### SetReferrer

```rust
/// See Section 9 for the full SetReferrer context struct with tier-2 auto-resolution.
#[derive(Accounts)]
#[instruction(referrer: Pubkey)]
pub struct SetReferrer<'info> {
    #[account(mut)]
    pub player: Signer<'info>,

    #[account(
        mut,
        seeds = [b"player", player.key().as_ref()],
        bump = player_state.bump,
        constraint = player_state.referrer == Pubkey::default() @ FateSwapError::ReferrerAlreadySet,
    )]
    pub player_state: Account<'info, PlayerState>,

    /// The referrer's PlayerState — used to look up tier-2 referrer.
    /// Optional: if referrer has never played, they won't have a PlayerState.
    #[account(
        seeds = [b"player", referrer.as_ref()],
        bump = referrer_player_state.bump,
    )]
    pub referrer_player_state: Option<Account<'info, PlayerState>>,

    /// Referral tracking account for the referrer — created if needed
    #[account(
        init_if_needed,
        seeds = [b"referral", referrer.as_ref()],
        bump,
        payer = player,
        space = 8 + ReferralState::INIT_SPACE,
    )]
    pub referral_state: Account<'info, ReferralState>,

    pub system_program: Program<'info, System>,
}
```

#### Pause

```rust
#[derive(Accounts)]
pub struct Pause<'info> {
    pub authority: Signer<'info>,

    #[account(
        mut,
        seeds = [b"clearing_house"],
        bump,
        has_one = authority,
    )]
    pub state: Account<'info, ClearingHouseState>,
}
```

#### UpdateConfig

```rust
#[derive(Accounts)]
pub struct UpdateConfig<'info> {
    pub authority: Signer<'info>,

    #[account(
        mut,
        seeds = [b"clearing_house"],
        bump,
        has_one = authority,
    )]
    pub state: Account<'info, ClearingHouseState>,
}
```

#### UpdateSettler

```rust
#[derive(Accounts)]
pub struct UpdateSettler<'info> {
    pub authority: Signer<'info>,

    #[account(
        mut,
        seeds = [b"clearing_house"],
        bump,
        has_one = authority,
    )]
    pub state: Account<'info, ClearingHouseState>,
}
```

### 5.9 Admin Instructions

Authority-only instructions for protocol management. These are thin wrappers that modify `ClearingHouseState`.

#### Pause / Unpause

```rust
/// Toggle the protocol pause state. When paused, no deposits, withdrawals,
/// or new fate orders can be placed. Existing pending orders can still be
/// settled or reclaimed.
pub fn pause(ctx: Context<Pause>, paused: bool) -> Result<()> {
    let state = &mut ctx.accounts.state;
    let old_paused = state.paused;
    state.paused = paused;

    emit!(Paused {
        paused,
        authority: ctx.accounts.authority.key(),
        timestamp: Clock::get()?.unix_timestamp,
    });

    msg!(
        "Protocol pause state changed: {} -> {}",
        old_paused,
        paused
    );

    Ok(())
}
```

#### Update Config

```rust
/// Update protocol configuration parameters. All fields are optional —
/// pass None to leave a field unchanged.
pub fn update_config(
    ctx: Context<UpdateConfig>,
    fate_fee_bps: Option<u16>,
    max_bet_bps: Option<u16>,
    referral_bps: Option<u16>,
    tier2_referral_bps: Option<u16>,
    nft_reward_bps: Option<u16>,
    platform_fee_bps: Option<u16>,
    bonus_bps: Option<u16>,
    platform_wallet: Option<Pubkey>,
    bonus_wallet: Option<Pubkey>,
    nft_rewarder: Option<Pubkey>,
    min_bet: Option<u64>,
    bet_timeout: Option<i64>,
) -> Result<()> {
    let state = &mut ctx.accounts.state;
    let clock = Clock::get()?;

    if let Some(fee) = fate_fee_bps {
        require!(fee <= 1000, FateSwapError::InvalidConfig); // Max 10% fee
        let old = state.fate_fee_bps;
        state.fate_fee_bps = fee;
        emit!(ConfigUpdated {
            field: 0, // fate_fee_bps
            old_value: old as u64,
            new_value: fee as u64,
            authority: ctx.accounts.authority.key(),
            timestamp: clock.unix_timestamp,
        });
    }

    if let Some(max_bps) = max_bet_bps {
        require!(max_bps <= 500, FateSwapError::InvalidConfig); // Max 5% of pool
        let old = state.max_bet_bps;
        state.max_bet_bps = max_bps;
        emit!(ConfigUpdated {
            field: 1, // max_bet_bps
            old_value: old as u64,
            new_value: max_bps as u64,
            authority: ctx.accounts.authority.key(),
            timestamp: clock.unix_timestamp,
        });
    }

    if let Some(ref_bps) = referral_bps {
        require!(ref_bps <= 100, FateSwapError::InvalidConfig); // Max 1% per tier
        let old = state.referral_bps;
        state.referral_bps = ref_bps;
        emit!(ConfigUpdated {
            field: 4, // referral_bps (tier-1)
            old_value: old as u64,
            new_value: ref_bps as u64,
            authority: ctx.accounts.authority.key(),
            timestamp: clock.unix_timestamp,
        });
    }

    if let Some(t2_bps) = tier2_referral_bps {
        require!(t2_bps <= 100, FateSwapError::InvalidConfig); // Max 1% per tier
        let old = state.tier2_referral_bps;
        state.tier2_referral_bps = t2_bps;
        emit!(ConfigUpdated {
            field: 5, // tier2_referral_bps
            old_value: old as u64,
            new_value: t2_bps as u64,
            authority: ctx.accounts.authority.key(),
            timestamp: clock.unix_timestamp,
        });
    }

    if let Some(nft_bps) = nft_reward_bps {
        require!(nft_bps <= 100, FateSwapError::InvalidConfig); // Max 1%
        let old = state.nft_reward_bps;
        state.nft_reward_bps = nft_bps;
        emit!(ConfigUpdated {
            field: 6, // nft_reward_bps
            old_value: old as u64,
            new_value: nft_bps as u64,
            authority: ctx.accounts.authority.key(),
            timestamp: clock.unix_timestamp,
        });
    }

    if let Some(plat_bps) = platform_fee_bps {
        require!(plat_bps <= 100, FateSwapError::InvalidConfig); // Max 1%
        let old = state.platform_fee_bps;
        state.platform_fee_bps = plat_bps;
        emit!(ConfigUpdated {
            field: 7, // platform_fee_bps
            old_value: old as u64,
            new_value: plat_bps as u64,
            authority: ctx.accounts.authority.key(),
            timestamp: clock.unix_timestamp,
        });
    }

    if let Some(b_bps) = bonus_bps {
        require!(b_bps <= 100, FateSwapError::InvalidConfig); // Max 1%
        let old = state.bonus_bps;
        state.bonus_bps = b_bps;
        emit!(ConfigUpdated {
            field: 8, // bonus_bps
            old_value: old as u64,
            new_value: b_bps as u64,
            authority: ctx.accounts.authority.key(),
            timestamp: clock.unix_timestamp,
        });
    }

    // Wallet updates (no events — use WalletUpdated event if needed)
    if let Some(wallet) = platform_wallet {
        state.platform_wallet = wallet;
    }
    if let Some(wallet) = bonus_wallet {
        state.bonus_wallet = wallet;
    }
    if let Some(rewarder) = nft_rewarder {
        state.nft_rewarder = rewarder;
    }

    if let Some(min) = min_bet {
        require!(min > 0, FateSwapError::InvalidConfig);
        let old = state.min_bet;
        state.min_bet = min;
        emit!(ConfigUpdated {
            field: 2, // min_bet
            old_value: old,
            new_value: min,
            authority: ctx.accounts.authority.key(),
            timestamp: clock.unix_timestamp,
        });
    }

    if let Some(timeout) = bet_timeout {
        require!(timeout >= 60, FateSwapError::InvalidConfig); // Minimum 60 seconds
        let old = state.bet_timeout_seconds;
        state.bet_timeout_seconds = timeout;
        emit!(ConfigUpdated {
            field: 3, // bet_timeout_seconds
            old_value: old as u64,
            new_value: timeout as u64,
            authority: ctx.accounts.authority.key(),
            timestamp: clock.unix_timestamp,
        });
    }

    Ok(())
}
```

#### Update Settler

```rust
/// Change the authorized settler wallet. Only the current authority can do this.
/// The settler is the server wallet that submits commitments and settles fate orders.
pub fn update_settler(
    ctx: Context<UpdateSettler>,
    new_settler: Pubkey,
) -> Result<()> {
    let state = &mut ctx.accounts.state;
    let old_settler = state.settler;
    state.settler = new_settler;

    emit!(SettlerUpdated {
        old_settler,
        new_settler,
        authority: ctx.accounts.authority.key(),
        timestamp: Clock::get()?.unix_timestamp,
    });

    msg!(
        "Settler updated: {} -> {}",
        old_settler,
        new_settler
    );

    Ok(())
}
```

---

## 6. Provably Fair System (Commit-Reveal)

### Identical to BuxBoosterGame V3

We use the exact same provably fair commit-reveal system that's proven in production on BuxBoosterGame. No VRF, no Switchboard, no external oracle.

### How It Works

```
┌──────────────────────────────────────────────────────┐
│  PROVABLY FAIR FLOW (same as BuxBoosterGame V3)      │
│                                                       │
│  1. Server generates: server_seed (32 random bytes)   │
│  2. Server computes:  commitment = SHA256(server_seed) │
│  3. Server submits commitment on-chain (TX0)          │
│  4. Player sees commitment on-chain (can verify later) │
│  5. Player places fate order referencing commitment    │
│     with their nonce (TX1 — player signs)              │
│  6. Server computes outcome OFF-CHAIN:                  │
│     result = SHA256(server_seed || player_pubkey ||    │
│              nonce_bytes)                               │
│     First 4 bytes → u32 → normalize to [0, u32::MAX] │
│     Compare against fill_chance threshold              │
│     If roll < threshold → FILLED (player wins)        │
│     If roll >= threshold → NOT FILLED (house wins)    │
│  7. Server submits TX2 with {filled: bool, seed}       │
│     Program verifies SHA256(seed) == commitment_hash  │
│     Program trusts settler's filled bool (no outcome  │
│     recomputation on-chain)                            │
│  8. Anyone can verify outcome off-chain from events    │
└──────────────────────────────────────────────────────┘
```

### Verification by Anyone (Off-Chain)

The on-chain program verifies `SHA256(server_seed) == commitment_hash` (prevents seed substitution) but trusts the settler's `filled` outcome. All data needed for independent outcome verification is stored in on-chain events:

```
1. Get commitment_hash from the FateOrderPlaced event (stored BEFORE bet)
2. Get server_seed from the FateOrderSettled event (revealed AFTER settlement)
3. Verify: SHA256(server_seed) == commitment_hash
   → Proves the seed was committed before the player bet
4. Compute: SHA256(server_seed || player_pubkey || nonce)
5. Take first 4 bytes as u32 (big-endian) → roll
6. Calculate threshold for the given multiplier & fee
7. Verify: (roll < threshold) matches the claimed filled/not-filled result
```

Step 3 is now verified on-chain (the program rejects settlement if the seed doesn't match the commitment). Steps 4-7 remain off-chain verification — if any fail, it proves the server lied about the outcome, publicly and immutably from on-chain data.

### Hybrid Verification: Seed On-Chain, Outcome Off-Chain

The program verifies `SHA256(server_seed) == commitment_hash` on-chain (~20,000 CU). This prevents seed substitution — the settler MUST reveal the exact seed that was committed before the bet. Without this, a malicious settler could reveal a different seed to flip the outcome.

The program does NOT recompute the outcome on-chain (no hash of `server_seed || player_pubkey || nonce`, no threshold comparison). The `filled: bool` is trusted from the settler. This avoids the complexity and bugs we experienced with full on-chain verification in BuxBoosterGame.

**Why this split?**
- **Seed verification on-chain**: Cheap (~20K CU), prevents the most dangerous attack (seed substitution), and guarantees that the revealed seed is the one committed before the bet
- **Outcome verification off-chain**: Anyone can verify from on-chain events. If the settler claims `filled=false` but the actual computation yields `filled=true`, it's publicly provable from the commitment hash + revealed seed + player pubkey + nonce — all stored in events

The 5-min timeout protects players if the server withholds settlement entirely.

### Why Not VRF?

| Server-Computed (our choice) | VRF (Switchboard/Orao) |
|---|---|
| Free (no oracle fees) | ~0.002 SOL per request |
| Minimal CU (no hashing on-chain) | ~100,000+ CU for VRF verification |
| Settles in 1 TX (~400ms) | Requires callback TX (~2-5s latency) |
| Trust: authorized settler | Trustless (cryptographic proof) |
| Proven pattern (BuxBoosterGame) | Would be new infrastructure |
| 5-min timeout protects players | N/A (always resolves) |

The trust assumption is mitigated by the timeout reclaim mechanism: if the server sees an unfavorable outcome and refuses to reveal, the player gets their SOL back after 5 minutes. The server has no incentive to withhold settlement.

### Optimization: Combined Commitment + Bet (2 TX instead of 3)

In BuxBoosterGame on EVM, we do 3 on-chain transactions:
1. `submitCommitment` (server)
2. `placeBet` (player)
3. `settleBet` (server)

On Solana, we can optimize to **2 transactions** by having the server send the commitment off-chain:

1. Server generates seed, sends `commitment_hash` to client via WebSocket/API
2. **TX1**: `submit_commitment` + `place_fate_order` (batched by frontend, player signs the bet, settler signs the commitment — partial signing or multi-instruction)
3. **TX2**: `settle_fate_order` (server signs)

Alternative: include commitment storage in the `place_fate_order` instruction itself, with the commitment passed as a parameter that the server pre-signed off-chain. The player's transaction includes both the server's commitment and their bet.

**Recommendation**: Start with 3 transactions (simpler, mirrors EVM). Optimize to 2 once the flow is proven.

---

## 7. Jupiter Integration (Token → SOL Swap)

### Architecture: Multi-Instruction Transaction (Not CPI)

The frontend constructs a single atomic transaction with multiple instructions:

```
Transaction (player signs):
  IX 0: ComputeBudgetProgram.setComputeUnitLimit(800_000)
  IX 1: ComputeBudgetProgram.setComputeUnitPrice(50_000)
  IX 2: Jupiter setupInstructions (create wSOL ATA if needed)
  IX 3: Jupiter swapInstruction (BONK → wSOL)
  IX 4: Jupiter cleanupInstruction (close wSOL ATA → native SOL)
  IX 5: FateSwap.place_fate_order (transfers native SOL to vault)
```

**Why multi-instruction over CPI:**
- Jupiter routes use many accounts (10-30+); CPI cannot use Address Lookup Tables, hitting the 1,232-byte TX size limit
- Multi-instruction with VersionedTransaction + ALTs avoids this entirely
- Equally atomic: if Jupiter swap fails, FateSwap instruction never executes
- Simpler Anchor code: `place_fate_order` doesn't need to know about Jupiter at all

**Key insight**: The house NEVER holds memecoins. Jupiter converts everything to SOL before it reaches the vault. Zero inventory risk — exactly as described in the FateSwap concept doc.

### Frontend Flow (TypeScript Pseudocode)

```typescript
async function createSellHighTransaction(
  userWallet: PublicKey,
  tokenMint: PublicKey,
  tokenAmount: bigint,
  multiplierBps: number,
  commitmentHash: Uint8Array,
  nonce: bigint,
) {
  // 1. Get Jupiter quote: token → SOL
  const quote = await jupiterApi.getQuote({
    inputMint: tokenMint,
    outputMint: SOL_MINT,
    amount: tokenAmount,
    slippageBps: 50,
    platformFeeBps: 10, // 0.1% Jupiter referral
  });

  // 2. Get Jupiter swap instructions
  const { setupInstructions, swapInstruction, cleanupInstruction, addressLookupTables }
    = await jupiterApi.getSwapInstructions(quote, userWallet);

  // 3. Build FateSwap place_fate_order instruction
  const solAmount = BigInt(quote.outAmount); // SOL received from swap
  const placeFateOrderIx = buildPlaceFateOrderIx({
    player: userWallet,
    solAmount,
    multiplierBps,
    commitmentHash,
    nonce,
    tokenMint,
    tokenAmount,
  });

  // 4. Compose into single VersionedTransaction
  const instructions = [
    ComputeBudgetProgram.setComputeUnitLimit({ units: 800_000 }),
    ...setupInstructions,
    swapInstruction,
    ...(cleanupInstruction ? [cleanupInstruction] : []),
    placeFateOrderIx,
  ];

  return buildVersionedTransaction(instructions, addressLookupTables);
}
```

### Buy-Side (Settlement → Token Purchase via Partial Signing)

When a buy-side player wins and is online, settlement and Jupiter swap happen in **1 atomic TX** via partial signing:

1. Server pre-computes outcome → Filled
2. Server fetches Jupiter quote for payout SOL → target token via fate-settler `/build-settle-and-swap`
3. fate-settler builds combined TX: `settle_fate_order` (settler signs) + Jupiter swap instructions (player must sign)
4. fate-settler partially signs with settler keypair, returns serialized TX to Elixir app
5. Elixir app pushes partially-signed TX to JS hook via LiveView `push_event`
6. Phantom/Solflare pops up — player approves and co-signs
7. JS hook submits fully-signed TX → player ends up with tokens in 1 atomic TX

**Fallback** (player offline or doesn't respond within 30s): Server submits settle-only TX. Player receives SOL in their wallet and can swap manually next visit.

**Why partial signing works**: Solana's `VersionedTransaction` supports multiple signers. The settler signs the settlement instruction, the player signs the Jupiter swap instructions. Both signatures are present in the single submitted TX. The recent blockhash has a ~60-90 second validity window — the 30s fallback timeout is well within this.

### Token Eligibility (Off-Chain Validation)

Validated before allowing a token in the UI, NOT on-chain:
- Must be on Jupiter's verified token list
- Must have >$50K DEX liquidity
- Must have <1% price impact at $50K trade size
- Validated via Jupiter Quote API + token list endpoint
- Cached and refreshed every 15-30 minutes

---

## 8. Fate Fee & Revenue Model

### Fee Structure

| Revenue Stream | Rate | Mechanism |
|---|---|---|
| Fate fee (house edge) | 1.5% | Built into fill chance math |
| Jupiter referral fee | ~0.1% | `platformFeeBps` on Jupiter quote |

### How the Fate Fee Works On-Chain

The fate fee is NOT deducted from the payout. It's embedded in the fill chance calculation:

```
// Without fee: fill_chance = 1 / multiplier
// A 2x multiplier would have exactly 50% fill chance

// With 1.5% fee: fill_chance = (1 / multiplier) × (1 - 0.015)
// A 2x multiplier has 49.25% fill chance instead of 50%
// The 0.75% difference is the house edge
```

Over many bets, the house retains ~1.5% of total volume. This is identical to how BuxBoosterGame's multiplier math includes house edge.

### Revenue Split on Losing Orders (1.0% total deduction)

When a player loses (order not filled), 1.0% of the wager is deducted from the vault and distributed to 5 recipients. The remaining 99.0% stays in the vault as LP holder revenue. This mirrors how ROGUEBankroll deducts NFT + referral rewards on losing bets.

| Recipient | BPS | % of Wager | Mechanism |
|---|---|---|---|
| Tier-1 referrer | 20 | 0.2% | Direct SOL transfer to referrer wallet |
| Tier-2 referrer | 10 | 0.1% | Direct SOL transfer to referrer's referrer |
| NFT holders | 30 | 0.3% | SOL transfer to NFTRewarder program PDA |
| Platform/team | 30 | 0.3% | SOL transfer to `platform_wallet` |
| Bonuses | 10 | 0.1% | SOL transfer to `bonus_wallet` |
| **Total deductions** | **100** | **1.0%** | |
| LP pool (house) | 9900 | 99.0% | Stays in vault, increases LP price |

All 5 transfers are **non-blocking** — if any individual transfer fails (e.g., referrer has no referrer for tier-2), the settlement still succeeds. This is identical to ROGUEBankroll's `_sendReferralReward()` and `_sendNFTReward()` pattern.

**Configurable on-chain**: All 5 bps values are stored on `ClearingHouseState` and can be updated via `update_config`. The wallets (`platform_wallet`, `bonus_wallet`, `nft_rewarder`) are also updatable by authority.

### Revenue Accrual

After deductions, revenue flows naturally to FATE-LP holders:
1. Player loses → 1.0% deducted for rewards → 99.0% stays in vault → `effective_balance` increases → LP price goes up
2. LP holders ARE the house — they earn 99% of all losing wagers
3. This is exactly how ROGUEBankroll works today (minus NFT + referral deductions)

### Jupiter Referral Fee Collection

Separate from the fate fee and separate from the loss deductions. Collected in a dedicated wSOL token account:

```
Platform fee ATA (wSOL): owned by FateSwap operations wallet
Set via platformFeeBps=10 (0.1%) on Jupiter quote requests
```

This is pure additional revenue on top of the fate fee, collected on ALL orders (win or lose) that involve a Jupiter swap.

---

## 9. Referral & Revenue Distribution System

### Overview

FateSwap uses a 5-way revenue split on losing orders, deducting 1.0% (100 bps) of the wager. This is an evolution of ROGUEBankroll's simpler 2-way split (referral + NFT). The tier-2 referral system, platform wallet, and bonuses wallet are new additions.

### Tier-1 & Tier-2 Referral Architecture

Each `PlayerState` stores both referrer addresses:

```rust
pub struct PlayerState {
    // ... other fields ...
    pub referrer: Pubkey,        // Tier-1: the player who referred this player
    pub tier2_referrer: Pubkey,  // Tier-2: the referrer's own referrer (set automatically)
    // ...
}
```

**How tier-2 is set**: When a player calls `set_referrer(referrer)`, the program also reads the referrer's `PlayerState` to look up `referrer.referrer`. If the referrer has their own referrer, that becomes the tier-2 referrer. This is a **one-time operation** per player — the cost is one additional account read during `set_referrer`, but zero additional reads during settlement (both are already on `PlayerState`).

### Referral Setup (with Tier-2 auto-resolution)

```rust
/// Set a player's referrer (one-time, admin or self-service).
/// Automatically resolves the tier-2 referrer from the referrer's PlayerState.
pub fn set_referrer(ctx: Context<SetReferrer>, referrer: Pubkey) -> Result<()> {
    let player_state = &mut ctx.accounts.player_state;
    require!(
        player_state.referrer == Pubkey::default(),
        FateSwapError::ReferrerAlreadySet
    );
    require!(
        referrer != ctx.accounts.player.key(),
        FateSwapError::SelfReferral
    );

    // Set tier-1 referrer
    player_state.referrer = referrer;

    // Increment referral count for the referrer
    let referral_state = &mut ctx.accounts.referral_state;
    referral_state.total_referrals += 1;

    // Auto-resolve tier-2 referrer from the referrer's PlayerState
    // (the referrer's own referrer, if they have one)
    if let Some(referrer_player_state) = &ctx.accounts.referrer_player_state {
        if referrer_player_state.referrer != Pubkey::default() {
            player_state.tier2_referrer = referrer_player_state.referrer;
        }
    }

    emit!(ReferrerSet {
        player: ctx.accounts.player.key(),
        referrer,
        tier2_referrer: player_state.tier2_referrer,
    });
    Ok(())
}
```

**SetReferrer context** adds `referrer_player_state` as an optional account:

```rust
#[derive(Accounts)]
#[instruction(referrer: Pubkey)]
pub struct SetReferrer<'info> {
    #[account(mut)]
    pub player: Signer<'info>,

    #[account(
        mut,
        seeds = [b"player", player.key().as_ref()],
        bump = player_state.bump,
        constraint = player_state.referrer == Pubkey::default() @ FateSwapError::ReferrerAlreadySet,
    )]
    pub player_state: Account<'info, PlayerState>,

    /// The referrer's PlayerState — used to look up tier-2 referrer.
    /// Optional: if referrer has never played, they won't have a PlayerState.
    #[account(
        seeds = [b"player", referrer.as_ref()],
        bump = referrer_player_state.bump,
    )]
    pub referrer_player_state: Option<Account<'info, PlayerState>>,

    /// Referral tracking account for the referrer — created if needed
    #[account(
        init_if_needed,
        seeds = [b"referral", referrer.as_ref()],
        bump,
        payer = player,
        space = 8 + ReferralState::INIT_SPACE,
    )]
    pub referral_state: Account<'info, ReferralState>,

    pub system_program: Program<'info, System>,
}
```

### Settlement: 5-Way Revenue Distribution (Losing Orders Only)

All 5 transfers happen in the `else` (not filled) branch of `settle_fate_order`. Each is non-blocking — failure is logged but does not revert settlement.

```rust
// --- NOT FILLED: House keeps wager, distribute revenue splits ---

// 1. Tier-1 referral reward (0.2% = 20 bps)
if player_state.referrer != Pubkey::default() {
    match _send_reward(vault, &ctx.accounts.referrer, state.referral_bps, order_amount) {
        Ok(reward) => {
            if let Some(ref mut rs) = ctx.accounts.referral_state {
                rs.total_earnings = rs.total_earnings.checked_add(reward).unwrap_or(u64::MAX);
            }
        },
        Err(e) => msg!("Tier-1 referral reward failed (non-blocking): {:?}", e),
    }
}

// 2. Tier-2 referral reward (0.1% = 10 bps)
if player_state.tier2_referrer != Pubkey::default() {
    match _send_reward(vault, &ctx.accounts.tier2_referrer, state.tier2_referral_bps, order_amount) {
        Ok(reward) => {
            if let Some(ref mut rs) = ctx.accounts.tier2_referral_state {
                rs.total_earnings = rs.total_earnings.checked_add(reward).unwrap_or(u64::MAX);
            }
        },
        Err(e) => msg!("Tier-2 referral reward failed (non-blocking): {:?}", e),
    }
}

// 3. NFT holder rewards (0.3% = 30 bps) — direct lamport transfer to NFTRewarder vault.
// NFTRewarder uses a sync_rewards crank to detect balance changes and update its accumulator.
match _send_reward(vault, &ctx.accounts.nft_rewarder, state.nft_reward_bps, order_amount) {
    Ok(_) => {},
    Err(e) => msg!("NFT reward failed (non-blocking): {:?}", e),
}

// 4. Platform/team wallet (0.3% = 30 bps)
match _send_reward(vault, &ctx.accounts.platform_wallet, state.platform_fee_bps, order_amount) {
    Ok(_) => {},
    Err(e) => msg!("Platform fee failed (non-blocking): {:?}", e),
}

// 5. Bonuses wallet (0.1% = 10 bps)
match _send_reward(vault, &ctx.accounts.bonus_wallet, state.bonus_bps, order_amount) {
    Ok(_) => {},
    Err(e) => msg!("Bonus fee failed (non-blocking): {:?}", e),
}
```

### Shared Reward Transfer Helper

```rust
/// Transfer SOL from vault to a recipient. Returns the reward amount on success.
fn _send_reward(
    vault: &AccountInfo,
    recipient: &AccountInfo,
    bps: u16,
    wager_amount: u64,
) -> Result<u64> {
    if bps == 0 { return Ok(0); }

    let reward = (wager_amount as u128)
        .checked_mul(bps as u128)
        .ok_or(FateSwapError::MathOverflow)?
        .checked_div(10_000u128)
        .ok_or(FateSwapError::MathOverflow)? as u64;

    if reward == 0 { return Ok(0); }

    // Safety: ensure vault stays above rent-exempt minimum
    let rent_exempt_minimum = Rent::get()?.minimum_balance(vault.data_len());
    if vault.lamports() - reward < rent_exempt_minimum {
        return Err(FateSwapError::InsufficientVaultBalance.into());
    }

    // Transfer from vault to recipient
    **vault.try_borrow_mut_lamports()? -= reward;
    **recipient.try_borrow_mut_lamports()? += reward;

    Ok(reward)
}
```

### NFTRewarder Program (Solana)

A separate Anchor program that distributes SOL rewards to High Rollers NFT holders proportionally by aggregated points per wallet. Uses a per-wallet model (NFTHolder with aggregated points) rather than per-NFT tracking, with cross-chain NFT data bridged from Arbitrum.

#### Architecture

```
┌──────────────────────────────────────────────────────────┐
│  NFTRewarder Program (Separate Anchor program)           │
│                                                          │
│  RewarderState (PDA, global singleton)                   │
│  seeds: [b"nft_rewarder"]                                │
│  ├── authority (Pubkey)              — admin wallet      │
│  ├── fateswap_program (Pubkey)       — for reference only │
│  ├── accumulated_reward_per_point (u128)  — MasterChef   │
│  ├── total_points (u64)             — sum of all holders │
│  ├── total_distributed (u64)         — lifetime SOL      │
│  ├── last_synced_balance (u64)      — for sync_rewards   │
│  └── _reserved ([u8; 120])                               │
│                                                          │
│  NFTHolder (PDA, per wallet)                             │
│  seeds: [b"holder", wallet.as_ref()]                     │
│  ├── wallet (Pubkey)                 — Solana wallet     │
│  ├── points (u64)                    — aggregated points │
│  ├── reward_debt (u128)             — MasterChef debt    │
│  ├── pending_reward (u64)           — unclaimed SOL      │
│  └── bump (u8)                                           │
│                                                          │
│  Vault (SystemAccount PDA, holds accumulated SOL)        │
│  seeds: [b"nft_vault", nft_rewarder.key()]               │
└──────────────────────────────────────────────────────────┘
```

#### NFT Types (from Arbitrum High Rollers collection)

| Type | Name | Multiplier | Count | Total Points |
|---|---|---|---|---|
| 0 | Vivienne Allure | 30 | ~290 | 8,700 |
| 1 | Scarlett Ember | 40 | ~290 | 11,600 |
| 2 | Aurora Seductra | 50 | ~290 | 14,500 |
| 3 | Luna Mirage | 60 | ~290 | 17,400 |
| 4 | Sophia Spark | 70 | ~290 | 20,300 |
| 5 | Cleo Enchante | 80 | ~293 | 23,440 |
| 6 | Mia Siren | 90 | ~298 | 26,820 |
| 7 | Penelope Fatale | 100 | ~290 | 29,000 |
| | **Total** | | **2,341** | **~109,390** |

Arbitrum contract: `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD`

#### Reward Distribution (MasterChef Pattern)

FateSwap's settlement sends SOL to the NFTRewarder vault via direct lamport transfer (0.3% of losing wagers). The NFTRewarder detects new SOL via a `sync_rewards` crank that compares vault balance against `last_synced_balance`:

```rust
/// Permissionless crank — anyone can call this to sync the MasterChef accumulator
/// with new SOL that arrived in the vault via direct lamport transfers from FateSwap
/// settlement. Compares current vault balance against last_synced_balance to compute
/// the delta, then updates accumulated_reward_per_point.
pub fn sync_rewards(ctx: Context<SyncRewards>) -> Result<()> {
    let state = &mut ctx.accounts.state;
    let vault_balance = ctx.accounts.vault.lamports();
    let rent_exempt = Rent::get()?.minimum_balance(8);
    let available = vault_balance.saturating_sub(rent_exempt);

    if available <= state.last_synced_balance || state.total_points == 0 {
        return Ok(());
    }

    let new_rewards = available - state.last_synced_balance;

    // MasterChef accumulator update
    state.accumulated_reward_per_point = state.accumulated_reward_per_point
        .checked_add(
            (new_rewards as u128)
                .checked_mul(1_000_000_000_000_000_000) // 1e18 precision
                .unwrap()
                / state.total_points as u128
        ).unwrap();

    state.total_distributed = state.total_distributed.checked_add(new_rewards).unwrap_or(u64::MAX);
    state.last_synced_balance = available;

    Ok(())
}
```

NFT holders claim rewards (per-wallet model):

```rust
pub fn claim_reward(ctx: Context<ClaimReward>) -> Result<()> {
    let holder = &mut ctx.accounts.nft_holder;
    let state = &ctx.accounts.state;

    // pending = (points * accumulated_reward_per_point) / 1e18 - reward_debt + pending_reward
    let accumulated = (holder.points as u128)
        .checked_mul(state.accumulated_reward_per_point).unwrap()
        / 1_000_000_000_000_000_000u128;
    let pending = accumulated
        .checked_sub(holder.reward_debt as u128)
        .unwrap_or(0)
        + holder.pending_reward as u128;

    if pending == 0 { return Ok(()); }

    // Transfer from vault to holder wallet
    let vault = &ctx.accounts.vault;
    let owner = &ctx.accounts.owner;
    **vault.to_account_info().try_borrow_mut_lamports()? -= pending as u64;
    **owner.to_account_info().try_borrow_mut_lamports()? += pending as u64;

    // Update debt and clear pending
    holder.reward_debt = accumulated as u128;
    holder.pending_reward = 0;

    Ok(())
}
```

#### Cross-Chain NFT Bridge (Arbitrum → Solana)

NFT ownership data is bridged from Arbitrum to Solana via **`FateSwap.NFTOwnershipPoller`**, a GenServer in the Phoenix app. This follows the exact same pattern as Blockster V2's `ReferralRewardPoller` (which was itself modeled on high-rollers-elixir's `RogueRewardPoller`):

**GenServer pattern** (same as `BlocksterV2.ReferralRewardPoller`):
- Registered globally via `GlobalSingleton` (single instance across cluster)
- Polls Arbitrum RPC `eth_getLogs` for `Transfer(from, to, tokenId)` events on the High Rollers contract (`0x7176d2edd83aD037bd94b7eE717bd9F661F560DD`)
- Polls every ~5 seconds (Arbitrum has ~250ms block time, no need for 1s like Rogue Chain)
- Persists last processed block in PostgreSQL for crash recovery
- Backfills from deploy block on first run (chunks of 10,000 blocks with rate limiting)
- Non-blocking polling with overlap prevention (`polling: true` guard)

**Flow**:
1. `NFTOwnershipPoller` detects a `Transfer` event on Arbitrum
2. Looks up the new owner's registered Solana wallet (from PostgreSQL `nft_wallet_mappings` table)
3. Calls fate-settler API endpoint to build and submit `update_holder` TX on Solana NFTRewarder program (admin-signed by fate-settler's keypair)
4. If the NFT holder hasn't registered a Solana wallet yet, the transfer is queued and applied when they register

**Wallet mapping**: NFT holders register their Solana wallet on the FateSwap UI (`/nft` page), which creates a mapping: `(arbitrum_address) → solana_wallet`. When NFTs transfer on Arbitrum, the poller recalculates the owner's aggregated points and updates the on-chain NFTHolder account.

Admin instructions on NFTRewarder:

```rust
/// Update a holder's points (admin only, called by bridge poller via fate-settler).
/// Creates the NFTHolder PDA if it doesn't exist. Settles any pending rewards
/// before updating points to prevent reward loss/gain from the change.
pub fn update_holder(ctx: Context<UpdateHolder>, wallet: Pubkey, points: u64) -> Result<()> { ... }

/// Batch update multiple holders' points (admin only, saves TX costs)
pub fn batch_update_holders(ctx: Context<BatchUpdate>, updates: Vec<(Pubkey, u64)>) -> Result<()> { ... }
```

---

## 10. Dynamic Bet Limits (Kelly Criterion)

### Direct Port from BuxBoosterGame

The key insight: **max profit per bet must scale with the multiplier to compensate for win frequency**. Low-multiplier games (1.02x) win almost every time, so the profit per win must be tiny. High-multiplier games (10x) rarely win, so larger profit per win is acceptable. The formula `maxBet = base * 2x_reference / multiplier` naturally achieves this.

### BuxBoosterGame Reference ($100k bankroll)

BuxBoosterGame has 9 fixed difficulty levels. With `MAX_BET_BPS = 10` (0.1%), `baseMaxBet = $100`:

| Payout | Max Bet | Max Profit | Win Rate |
|--------|---------|------------|----------|
| 1.02x | $196.08 | $3.92 | ~97% |
| 1.05x | $190.48 | $9.52 | ~94% |
| 1.13x | $176.99 | $23.01 | ~88% |
| 1.32x | $151.52 | $48.49 | ~75% |
| 1.98x | $101.01 | $98.99 | ~50% |
| 3.96x | $50.51 | $149.49 | ~25% |
| 7.92x | $25.25 | $174.75 | ~12.5% |
| 15.84x | $12.63 | $187.37 | ~6.25% |
| 31.68x | $6.31 | $193.69 | ~3.1% |

The max profit at 1.02x ($3.92) is **25x smaller** than at 1.98x ($98.99). This is correct — a 1.02x player can go on 30+ win streaks easily, so each win must extract very little from the bank.

### FateSwap Bet Limits ($100k bankroll)

FateSwap uses the same formula but with 210 discrete multiplier values from 1.01x to 10.0x. Same `max_bet_bps = 10` (0.1%), `baseMaxBet = $100`:

| Payout | Tier | Max Bet | Max Profit | Approx Win Rate |
|--------|------|---------|------------|-----------------|
| 1.01x | 1 (step 0.01) | $198.02 | $1.98 | ~99% |
| 1.50x | 1 (step 0.01) | $133.33 | $66.67 | ~67% |
| 2.00x | 2 (step 0.02) | $100.00 | $100.00 | ~50% |
| 2.50x | 2 (step 0.02) | $80.00 | $120.00 | ~40% |
| 3.00x | 3 (step 0.05) | $66.67 | $133.33 | ~33% |
| 3.50x | 3 (step 0.05) | $57.14 | $142.86 | ~29% |
| 4.0x | 4 (step 0.1) | $50.00 | $150.00 | ~25% |
| 5.0x | 4 (step 0.1) | $40.00 | $160.00 | ~20% |
| 6.0x | 5 (step 0.2) | $33.33 | $166.67 | ~17% |
| 8.0x | 5 (step 0.2) | $25.00 | $175.00 | ~13% |
| 10.0x | 6 (single) | $20.00 | $180.00 | ~10% |

At 1.01x someone can bet $198 but only profits $1.98 per win. At 10.0x they can only bet $20 but profit $180. The max bet shrinks proportionally as the multiplier climbs, so a lucky streak at 1.01x is just a slow grind while a lucky streak at 10.0x is practically impossible.

### Implementation

```rust
/// Maximum bet for a given multiplier.
/// Scales inversely with multiplier — low multipliers get large bets but tiny profit,
/// high multipliers get small bets but large profit.
fn calculate_max_bet(
    net_balance: u64,
    max_bet_bps: u16,
    multiplier_bps: u32,
) -> u64 {
    if net_balance == 0 { return 0; }

    // base_max_bet = net_balance * max_bet_bps / 10000
    // e.g., $100k * 10 / 10000 = $100
    let base_max = (net_balance as u128)
        .checked_mul(max_bet_bps as u128)
        .unwrap_or(0)
        / 10_000u128;

    // Scale inversely with multiplier, using 2x as reference point:
    // max_bet = base_max * (2 * MULTIPLIER_BASE) / multiplier_bps
    //
    // At 1.01x (101000): max_bet = base * 200000 / 101000 = $198.02 → profit = $1.98
    // At 2x   (200000):  max_bet = base * 200000 / 200000 = $100.00 → profit = $100.00
    // At 10x  (1000000): max_bet = base * 200000 / 1000000 = $20.00 → profit = $180.00
    let reference_multiplier = 2u128 * MULTIPLIER_BASE as u128; // 200000
    let scaled = base_max
        .checked_mul(reference_multiplier)
        .unwrap_or(0)
        / multiplier_bps as u128;

    scaled as u64
}
```

This is identical to BuxBoosterGame's `_calculateMaxBet()`:
```solidity
// EVM equivalent (MULTIPLIER_BASE = 10000, so 2x = 20000)
uint256 baseMaxBet = (houseBalance * MAX_BET_BPS) / 10000; // 0.1%
return (baseMaxBet * 20000) / multiplier;
// 20000 = 2 * 10000 = 2x reference, same as our 200000 = 2 * 100000
```

The formula keeps `max_bet * multiplier` constant, but max **profit** varies enormously. This is by design — it compensates for win frequency. A 1.02x player winning 98% of the time with $3.92 profit per win can't grind the bank down. A 10x player can profit $180 per win but only wins ~10% of the time — natural variance protects the bank.

---

## 11. Security Model

### Solana-Specific Security (vs EVM)

| EVM Concern | Solana Equivalent | Mitigation |
|---|---|---|
| Reentrancy | Not possible (runtime enforced) | N/A |
| Integer overflow | Panic on overflow (Rust default) | `checked_*` operations throughout |
| Access control (`onlyOwner`) | `has_one = authority` Anchor constraint | Anchor validates at deserialization |
| Flash loan manipulation | No flash loans in Solana | N/A |
| Front-running | No mempool (leader-based scheduling) | Commitment submitted before bet |
| Unauthorized callers | PDA seed verification | Anchor `seeds` + `bump` constraints |
| Storage collision (proxy) | Not applicable (no proxies) | N/A |

### Security Checklist

1. **All PDAs verified via Anchor constraints** — never accept user-supplied bumps
2. **Bumps stored on-chain during init** — reused in all subsequent instructions
3. **Authority checks via `has_one`** — admin functions require authority signer
4. **Settler checks via `has_one`** — only authorized settler can submit commitments and settle outcomes
5. **All arithmetic uses `checked_*`** — with explicit error propagation
6. **LP burn requires user signature** — users own their token accounts
7. **Withdrawals bounded by `net_balance`** — can't drain funds needed for liabilities
8. **Max bet capped** — scales inversely with multiplier (low-mult games = big bet/tiny profit, high-mult = small bet/big profit)
9. **Total liability tracked** — prevents over-commitment of vault
10. **Pause mechanism** — authority can freeze deposits, withdrawals, and new orders
11. **Commitment must exist before bet** — prevents manipulation of randomness
12. **5-minute timeout** — players can reclaim if server doesn't settle
13. **On-chain seed verification** — `SHA256(server_seed) == commitment_hash` checked during settlement; prevents seed substitution attack
14. **Off-chain outcome verification** — commitment hash + server seed + player pubkey + nonce all stored in on-chain events; anyone can independently verify the outcome was fair; server cheating would be publicly provable

### Server Seed Security

- Generate 32 bytes from CSPRNG (`crypto.randomBytes(32)`)
- Never reuse seeds across bets
- Never reveal seed for unsettled orders (same rule as BuxBoosterGame)
- Store seeds in encrypted database with access logging
- Settler key should use KMS or hardware wallet in production

---

## 12. Compute Budget & Gas Costs

### Per-Instruction Estimates

| Instruction | Estimated CU | Priority Fee | Total Cost (USD) |
|---|---|---|---|
| `initialize` | ~50,000 | One-time | ~$0.005 |
| `deposit_sol` | ~35,000 | Standard | ~$0.001 |
| `withdraw_sol` | ~35,000 | Standard | ~$0.001 |
| `submit_commitment` | ~15,000 | Standard | ~$0.001 |
| `place_fate_order` | ~25,000 | Standard | ~$0.002 |
| `settle_fate_order` | ~15,000 | Standard | ~$0.001 |
| `reclaim_expired_order` | ~10,000 | Standard | ~$0.001 |
| Jupiter swap (1-2 hops) | ~200,000-400,000 | Standard | ~$0.005 |

### Full Trade Cost (Sell-Side)

```
TX1: Jupiter swap + place_fate_order
  Compute: ~400,000 + 25,000 = ~425,000 CU
  Base fee: ~0.000005 SOL
  Priority fee: ~0.00001 SOL
  Total: ~0.000015 SOL (~$0.003)

TX2: settle_fate_order (server-signed, server pays)
  Compute: ~15,000 CU
  Base fee: ~0.000005 SOL
  Priority fee: ~0.00001 SOL
  Total: ~0.000015 SOL (~$0.003)

TOTAL PER TRADE: ~0.00003 SOL (~$0.006)
```

This is even cheaper than the FateSwap concept doc's estimate of ~$0.01 per trade.

### Comparison with Our EVM Costs

| Chain | Cost per Trade | Settlement Time |
|---|---|---|
| Solana (FateSwap) | ~$0.006 | ~1 second |
| Rogue Chain (BuxBoosterGame) | ~$0.001 | ~2 seconds |
| Ethereum L1 (hypothetical) | ~$5-50 | ~12 minutes |
| Ethereum L2 (hypothetical) | ~$0.10-0.50 | ~10 seconds |

Solana is ~100x cheaper than any EVM L2 and comparable to our private Rogue Chain.

---

## 13. Upgradeability & State Migration

### Solana's Native Upgrade Model

| EVM (UUPS/Transparent) | Solana (Native) |
|---|---|
| Deploy implementation + proxy | Deploy program |
| `upgradeTo(newImpl)` on proxy | `solana program deploy --program-id <existing>` |
| Storage layout must be preserved | Account struct layout must be preserved |
| Can renounce (make immutable) | `solana program set-upgrade-authority --final` |
| Upgrade authority in proxy storage | Upgrade authority in program metadata |

No proxy pattern needed. Solana replaces program code directly. State accounts are separate from the program, so code upgrades never overwrite state.

### State Migration Rules (Same as EVM)

1. **Only add fields at the END** of structs (same as EVM storage layout)
2. **Never remove or reorder fields**
3. **Use `_reserved` bytes** for future expansion (192 bytes in ClearingHouseState)
4. **Test deserialization** of existing account data against new struct before deploying

### Reserved Bytes Strategy

```rust
// Before upgrade:
pub some_new_field: u64,       // 0 bytes (doesn't exist yet)
pub _reserved: [u8; 192],     // 192 bytes of zeros

// After upgrade:
pub some_new_field: u64,       // 8 bytes (reads zeros = 0)
pub _reserved: [u8; 184],     // 184 bytes remaining
```

Existing accounts' reserved bytes are all zeros, which deserialize correctly as `0` for numeric types and `false` for bools.

### Upgrade Authority

- **Development**: Deployer keypair
- **Production**: Squads Protocol multisig (Solana's standard multisig solution)
- **Final**: `set-upgrade-authority --final` once battle-tested (makes program immutable)

---

## 14. Testing Strategy

### Framework: `bankrun` (solana-bankrun)

Fast test startup (~1s vs ~30s for full validator), high fidelity, TypeScript-based.

```typescript
import { startAnchor } from "solana-bankrun";
import { BankrunProvider } from "anchor-bankrun";

describe("FateSwap ClearingHouse", () => {
  let context, provider, program;

  beforeAll(async () => {
    context = await startAnchor("", [], []);
    provider = new BankrunProvider(context);
    program = new Program(IDL, provider);
  });

  it("deposits SOL and receives LP tokens", async () => { /* ... */ });
  it("LP price increases after house wins", async () => { /* ... */ });
  it("withdrawals respect liability cap", async () => { /* ... */ });
});
```

### Time Manipulation for Timeout Tests

```typescript
it("reclaims after timeout", async () => {
  // Place order
  await program.methods.placeFateOrder(/* ... */).rpc();

  // Warp time forward 5 minutes
  const clock = await context.banksClient.getClock();
  context.setClock(new Clock(
    clock.slot,
    clock.epochStartTimestamp,
    clock.epoch,
    clock.leaderScheduleEpoch,
    BigInt(clock.unixTimestamp) + BigInt(301) // past 300s timeout
  ));

  // Reclaim should succeed
  await program.methods.reclaimExpiredOrder().rpc();
});
```

### Test Categories

```
tests/
├── clearing_house/
│   ├── deposit.test.ts         # First deposit 1:1, subsequent proportional
│   ├── withdraw.test.ts        # Proportional withdrawal, liability cap
│   ├── lp_price.test.ts        # Price goes up on losses, down on wins
│   ├── max_bet.test.ts         # Dynamic bet limits per multiplier
│   └── pause.test.ts           # Pause blocks all operations
├── fate_game/
│   ├── commitment.test.ts      # Commitment submission and validation
│   ├── place_order.test.ts     # Order placement, validation, edge cases
│   ├── settle_filled.test.ts   # Winning settlement, payout transfer
│   ├── settle_not_filled.test.ts # Losing settlement, stats update
│   ├── expire_order.test.ts    # Timeout expiration, refund
│   └── multiplier_range.test.ts # 1.01x to 10x, boundary conditions
├── provably_fair/
│   ├── commitment_verify.test.ts  # SHA256(seed) matches hash
│   ├── outcome_determinism.test.ts # Same inputs → same result
│   ├── fill_chance.test.ts     # Statistical validation over many runs
│   └── invalid_seed.test.ts    # Wrong seed rejected
├── referral/
│   ├── set_referrer.test.ts    # One-time set, self-referral blocked
│   └── reward_payment.test.ts  # Correct amount on losses only
├── security/
│   ├── access_control.test.ts  # Unauthorized callers rejected
│   ├── overflow.test.ts        # Max values don't panic
│   └── double_settle.test.ts   # Can't settle same order twice
└── integration/
    └── full_flow.test.ts       # End-to-end: deposit → bet → settle → withdraw
```

---

## 15. Deployment Plan

### Phase 1: Core Program (Devnet)

1. Implement ClearingHouse (init, deposit, withdraw)
2. Implement FateGame (commit, place, settle, expire)
3. Full test suite with bankrun
4. Deploy to Solana devnet
5. Manual testing with Phantom wallet

### Phase 2: Jupiter Integration (Devnet)

1. Frontend integration with Jupiter Swap API
2. Multi-instruction TX construction
3. Token eligibility validation
4. End-to-end testing on devnet with real Jupiter swaps

### Phase 3: Referral & Admin

1. Referral system implementation
2. Admin functions (pause, update config, update settler)
3. LP price view functions for frontend
4. Stats query functions

### Phase 4: Audit & Mainnet

1. Security audit (internal + external)
2. Deploy to mainnet-beta
3. Seed initial LP (house bankroll)
4. Start with conservative limits (low max bet, whitelist tokens)
5. Gradually increase limits as the system proves itself

### Deployment Costs

| Item | Cost |
|---|---|
| Program deployment (rent-exempt) | ~2.7 SOL (~$400) |
| ClearingHouseState account | ~0.005 SOL |
| LP Mint account | ~0.002 SOL |
| Initial LP seed | Variable (house bankroll) |
| **Total one-time** | **~2.71 SOL + bankroll** |

---

## 16. EVM → Solana Translation Reference

### Complete Mapping

| EVM Concept | Solana Equivalent |
|---|---|
| `contract ROGUEBankroll` | `mod clearing_house` in Anchor program |
| `contract BuxBoosterGame` | `mod fate_game` in same Anchor program |
| Contract storage variables | `ClearingHouseState` PDA account |
| `address(this).balance` | `vault.lamports()` |
| `mapping(address => Player)` | Per-player PDA accounts |
| `mapping(bytes32 => Bet)` | Per-bet PDA accounts |
| ERC-20 LP token (`_mint`/`_burn`) | SPL Token CPI (`mint_to`/`burn`) |
| `msg.sender` | `Signer<'info>` in accounts struct |
| `msg.value` | `system_program::transfer` parameter |
| `payable(addr).call{value: x}("")` | Direct lamport manipulation |
| `onlyOwner` modifier | `has_one = authority` Anchor constraint |
| `onlyBuxBooster` modifier | Not needed (single program) |
| `nonReentrant` modifier | Not needed (Solana runtime) |
| `require(...)` | `require!(...)` Anchor macro |
| `emit Event(...)` | `emit!(EventStruct { ... })` |
| `keccak256(...)` | `solana_program::hash::hash(...)` (SHA-256) |
| UUPS `upgradeTo` | `solana program deploy --program-id` |
| `initializer` modifier | `initialize` instruction (one-time) |
| OpenZeppelin libraries | Anchor framework + `anchor_spl` |
| Hardhat tests | `bankrun` + `anchor test` |
| Transparent/UUPS proxy | Native program upgradeability |
| Gas: ~100k gas units | ~25k compute units |
| Block time: ~2s (Rogue Chain) | Slot time: ~400ms (Solana) |

---

## 17. Error Codes

Complete `FateSwapError` enum with all errors referenced throughout the program. Anchor assigns these sequential error codes starting from 6000 (Anchor's custom error offset).

```rust
use anchor_lang::prelude::*;

#[error_code]
pub enum FateSwapError {
    /// Protocol is paused — no deposits, withdrawals, or new orders
    #[msg("Protocol is currently paused")]
    Paused,                         // 6000

    /// Multiplier not one of the 210 allowed discrete values (1.01x–10.0x, tiered steps)
    #[msg("Multiplier must be a valid discrete step (1.01-1.99 by 0.01, 2.00-2.98 by 0.02, 3.00-3.95 by 0.05, 4.0-5.9 by 0.1, 6.0-9.8 by 0.2, or 10.0)")]
    InvalidMultiplier,              // 6001

    /// Player's nonce doesn't match the committed nonce
    #[msg("Nonce does not match pending commitment")]
    NonceMismatch,                  // 6002

    /// No pending commitment found for this player
    #[msg("No commitment found — server must submit commitment first")]
    NoCommitment,                   // 6003

    /// Player already has a pending (unsettled) order
    #[msg("Player already has an active order")]
    ActiveOrderExists,              // 6004

    /// Wager is below the minimum bet threshold
    #[msg("Bet amount is below minimum")]
    BetTooSmall,                    // 6005

    /// Wager exceeds the dynamic max bet for this multiplier
    #[msg("Bet amount exceeds maximum for this multiplier")]
    BetTooLarge,                    // 6006

    /// Vault cannot cover the potential payout
    #[msg("Insufficient vault balance to cover potential payout")]
    InsufficientVaultBalance,       // 6007

    /// Arithmetic overflow in checked math operations
    #[msg("Math overflow")]
    MathOverflow,                   // 6008

    /// Attempting to settle an order that isn't Pending
    #[msg("Order is not in Pending status")]
    OrderNotPending,                // 6009

    /// SHA256(server_seed) does not match the commitment hash stored on the order
    #[msg("Server seed does not match commitment hash")]
    InvalidServerSeed,              // 6010

    /// Server tried to settle after the bet timeout elapsed
    #[msg("Order has expired — player should reclaim")]
    OrderExpired,                   // 6011

    /// Player tried to reclaim before the timeout elapsed
    #[msg("Order has not expired yet")]
    OrderNotExpired,                // 6012

    /// LP withdrawal would leave insufficient balance for liabilities
    #[msg("Insufficient liquidity after accounting for liabilities")]
    InsufficientLiquidity,          // 6013

    /// Deposit too small to mint any LP tokens
    #[msg("Deposit too small to mint LP tokens")]
    DepositTooSmall,                // 6014

    /// Withdrawal would return zero SOL
    #[msg("Withdrawal amount too small")]
    WithdrawTooSmall,               // 6015

    /// Deposit or withdrawal amount is zero
    #[msg("Amount must be greater than zero")]
    ZeroAmount,                     // 6016

    /// Player tried to set themselves as their own referrer
    #[msg("Cannot refer yourself")]
    SelfReferral,                   // 6017

    /// Player already has a referrer set (one-time only)
    #[msg("Referrer already set")]
    ReferrerAlreadySet,             // 6018

    /// Caller is not the authorized settler
    #[msg("Unauthorized settler")]
    UnauthorizedSettler,            // 6019

    /// Player account doesn't match the order's player field
    #[msg("Invalid player for this order")]
    InvalidPlayer,                  // 6020

    /// Admin config value out of acceptable range
    #[msg("Invalid configuration value")]
    InvalidConfig,                  // 6021

    /// Referrer account doesn't match the referrer stored on PlayerState
    #[msg("Referrer does not match player's stored referrer")]
    InvalidReferrer,                // 6022

    /// NFT rewarder account doesn't match state.nft_rewarder
    #[msg("NFT rewarder does not match configured address")]
    InvalidNFTRewarder,             // 6023

    /// Platform wallet doesn't match state.platform_wallet
    #[msg("Platform wallet does not match configured address")]
    InvalidPlatformWallet,          // 6024

    /// Bonus wallet doesn't match state.bonus_wallet
    #[msg("Bonus wallet does not match configured address")]
    InvalidBonusWallet,             // 6025
}
```

---

## 18. Events

All Anchor events emitted by the program. Events are indexed by Solana's transaction logs and can be parsed by any client subscribing to program logs.

```rust
use anchor_lang::prelude::*;

/// Emitted once when the ClearingHouse is initialized
#[event]
pub struct ClearingHouseInitialized {
    pub authority: Pubkey,
    pub settler: Pubkey,
    pub fate_fee_bps: u16,
    pub max_bet_bps: u16,
    pub min_bet: u64,
    pub bet_timeout_seconds: i64,
    pub timestamp: i64,
}

/// Emitted when an LP deposits SOL and receives FATE-LP tokens
#[event]
pub struct LiquidityDeposited {
    pub depositor: Pubkey,
    pub sol_amount: u64,
    pub lp_minted: u64,
    pub vault_balance: u64,
    pub lp_supply: u64,
    pub timestamp: i64,
}

/// Emitted when an LP burns FATE-LP tokens and receives SOL
#[event]
pub struct LiquidityWithdrawn {
    pub withdrawer: Pubkey,
    pub lp_burned: u64,
    pub sol_withdrawn: u64,
    pub vault_balance: u64,
    pub lp_supply: u64,
    pub timestamp: i64,
}

/// Emitted when the server submits a commitment hash for a player
#[event]
pub struct CommitmentSubmitted {
    pub player: Pubkey,
    pub commitment_hash: [u8; 32],
    pub nonce: u64,
    pub timestamp: i64,
}

/// Emitted when a player places a fate order (SOL deposited to vault)
#[event]
pub struct FateOrderPlaced {
    pub player: Pubkey,
    pub order: Pubkey,
    pub sol_amount: u64,
    pub multiplier_bps: u32,
    pub potential_payout: u64,
    pub commitment_hash: [u8; 32],
    pub nonce: u64,
    pub token_mint: Pubkey,
    pub token_amount: u64,
    pub timestamp: i64,
}

/// Emitted when a fate order is settled (server provides outcome + reveals seed)
/// Contains all data needed for off-chain provably fair verification
#[event]
pub struct FateOrderSettled {
    pub player: Pubkey,
    pub order: Pubkey,
    pub filled: bool,
    pub sol_wagered: u64,
    pub payout: u64,
    pub multiplier_bps: u32,
    pub server_seed: [u8; 32],   // Revealed for off-chain verification
    pub nonce: u64,
    pub token_mint: Pubkey,
    pub token_amount: u64,
    pub timestamp: i64,
}

/// Emitted when a player reclaims SOL from an expired order
#[event]
pub struct FateOrderReclaimed {
    pub player: Pubkey,
    pub order: Pubkey,
    pub sol_refunded: u64,
    pub nonce: u64,
    pub timestamp: i64,
}

/// Emitted when a player sets their referrer (includes auto-resolved tier-2)
#[event]
pub struct ReferrerSet {
    pub player: Pubkey,
    pub referrer: Pubkey,           // Tier-1
    pub tier2_referrer: Pubkey,     // Tier-2 (auto-resolved, or Pubkey::default)
}

/// Emitted for each reward transfer on a losing order (up to 5 per settlement)
#[event]
pub struct RewardPaid {
    pub recipient: Pubkey,
    pub player: Pubkey,
    pub order: Pubkey,
    pub reward_type: u8,           // 0=tier1_referral, 1=tier2_referral, 2=nft, 3=platform, 4=bonus
    pub reward_amount: u64,
    pub bps: u16,
    pub timestamp: i64,
}

/// Emitted when an admin updates a config parameter
#[event]
pub struct ConfigUpdated {
    pub field: u8,       // 0=fate_fee_bps, 1=max_bet_bps, 2=min_bet, 3=bet_timeout, 4=referral_bps, 5=tier2_referral_bps, 6=nft_reward_bps, 7=platform_fee_bps, 8=bonus_bps
    pub old_value: u64,
    pub new_value: u64,
    pub authority: Pubkey,
    pub timestamp: i64,
}

/// Emitted when the settler wallet is changed
#[event]
pub struct SettlerUpdated {
    pub old_settler: Pubkey,
    pub new_settler: Pubkey,
    pub authority: Pubkey,
    pub timestamp: i64,
}

/// Emitted when the protocol is paused or unpaused
#[event]
pub struct Paused {
    pub paused: bool,
    pub authority: Pubkey,
    pub timestamp: i64,
}
```

---

## 19. Program Entry Point & Module Structure

### lib.rs

The program entry point declares the program ID, imports all modules, and dispatches instructions to their handlers.

```rust
use anchor_lang::prelude::*;

declare_id!("FateXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX");

pub mod state;
pub mod instructions;
pub mod errors;
pub mod events;
pub mod math;

use instructions::*;
use errors::FateSwapError;

#[program]
pub mod fateswap {
    use super::*;

    // --- ClearingHouse (LP Pool) ---

    pub fn initialize(
        ctx: Context<Initialize>,
        fate_fee_bps: u16,
        max_bet_bps: u16,
        min_bet: u64,
        bet_timeout: i64,
        platform_wallet: Pubkey,
        bonus_wallet: Pubkey,
        nft_rewarder: Pubkey,
    ) -> Result<()> {
        instructions::initialize::handler(ctx, fate_fee_bps, max_bet_bps, min_bet, bet_timeout, platform_wallet, bonus_wallet, nft_rewarder)
    }

    pub fn deposit_sol(ctx: Context<DepositSol>, amount_lamports: u64) -> Result<()> {
        instructions::deposit_sol::handler(ctx, amount_lamports)
    }

    pub fn withdraw_sol(ctx: Context<WithdrawSol>, lp_amount: u64) -> Result<()> {
        instructions::withdraw_sol::handler(ctx, lp_amount)
    }

    // --- FateGame (Bet Logic) ---

    pub fn submit_commitment(
        ctx: Context<SubmitCommitment>,
        commitment_hash: [u8; 32],
        player: Pubkey,
        nonce: u64,
    ) -> Result<()> {
        instructions::submit_commitment::handler(ctx, commitment_hash, player, nonce)
    }

    pub fn place_fate_order(
        ctx: Context<PlaceFateOrder>,
        nonce: u64,
        multiplier_bps: u32,
        sol_amount: u64,
        token_mint: Pubkey,
        token_amount: u64,
    ) -> Result<()> {
        instructions::place_fate_order::handler(ctx, nonce, multiplier_bps, sol_amount, token_mint, token_amount)
    }

    pub fn settle_fate_order(
        ctx: Context<SettleFateOrder>,
        filled: bool,
        server_seed: [u8; 32],
    ) -> Result<()> {
        instructions::settle_fate_order::handler(ctx, filled, server_seed)
    }

    pub fn reclaim_expired_order(ctx: Context<ReclaimExpiredOrder>) -> Result<()> {
        instructions::reclaim_expired_order::handler(ctx)
    }

    // --- Referral ---

    pub fn set_referrer(ctx: Context<SetReferrer>, referrer: Pubkey) -> Result<()> {
        instructions::set_referrer::handler(ctx, referrer)
    }

    // --- Admin ---

    pub fn pause(ctx: Context<Pause>, paused: bool) -> Result<()> {
        instructions::pause::handler(ctx, paused)
    }

    pub fn update_config(
        ctx: Context<UpdateConfig>,
        fate_fee_bps: Option<u16>,
        max_bet_bps: Option<u16>,
        referral_bps: Option<u16>,
        tier2_referral_bps: Option<u16>,
        nft_reward_bps: Option<u16>,
        platform_fee_bps: Option<u16>,
        bonus_bps: Option<u16>,
        platform_wallet: Option<Pubkey>,
        bonus_wallet: Option<Pubkey>,
        nft_rewarder: Option<Pubkey>,
        min_bet: Option<u64>,
        bet_timeout: Option<i64>,
    ) -> Result<()> {
        instructions::update_config::handler(ctx, fate_fee_bps, max_bet_bps, referral_bps, tier2_referral_bps, nft_reward_bps, platform_fee_bps, bonus_bps, platform_wallet, bonus_wallet, nft_rewarder, min_bet, bet_timeout)
    }

    pub fn update_settler(ctx: Context<UpdateSettler>, new_settler: Pubkey) -> Result<()> {
        instructions::update_settler::handler(ctx, new_settler)
    }
}
```

### File & Module Structure

```
programs/fateswap/src/
├── lib.rs                          # declare_id!, #[program] mod with instruction dispatch
├── state/
│   ├── mod.rs                      # pub mod clearing_house; pub mod fate_order; ...
│   ├── clearing_house.rs           # ClearingHouseState account struct
│   ├── fate_order.rs               # FateOrder account struct, FateOrderStatus enum
│   ├── player_state.rs             # PlayerState account struct (incl. tier2_referrer)
│   └── referral_state.rs           # ReferralState account struct
├── instructions/
│   ├── mod.rs                      # pub mod initialize; pub mod deposit_sol; ... pub use
│   ├── initialize.rs               # Initialize ClearingHouse + vault + LP mint
│   ├── deposit_sol.rs              # LP deposits SOL, receives FATE-LP tokens
│   ├── withdraw_sol.rs             # LP burns FATE-LP, receives SOL
│   ├── submit_commitment.rs        # Server commits SHA256(server_seed)
│   ├── place_fate_order.rs         # Player places fate order, SOL → vault
│   ├── settle_fate_order.rs        # Server reveals seed, settles order + 5-way revenue split
│   ├── reclaim_expired_order.rs    # Player reclaims after timeout
│   ├── set_referrer.rs             # Player sets referrer (auto-resolves tier-2)
│   ├── pause.rs                    # Authority toggles pause state
│   ├── update_config.rs            # Authority updates fee/limits/timeout/wallets
│   └── update_settler.rs           # Authority changes settler wallet
├── errors.rs                       # FateSwapError enum (all custom error codes)
├── events.rs                       # All #[event] structs (incl. RewardPaid)
└── math.rs                         # calculate_max_bet, get_lp_price, fee calculations
```

### Module Re-exports (instructions/mod.rs)

```rust
pub mod initialize;
pub mod deposit_sol;
pub mod withdraw_sol;
pub mod submit_commitment;
pub mod place_fate_order;
pub mod settle_fate_order;
pub mod reclaim_expired_order;
pub mod set_referrer;
pub mod pause;
pub mod update_config;
pub mod update_settler;

// Re-export account context structs for use in lib.rs
pub use initialize::Initialize;
pub use deposit_sol::DepositSol;
pub use withdraw_sol::WithdrawSol;
pub use submit_commitment::SubmitCommitment;
pub use place_fate_order::PlaceFateOrder;
pub use settle_fate_order::SettleFateOrder;
pub use reclaim_expired_order::ReclaimExpiredOrder;
pub use set_referrer::SetReferrer;
pub use pause::Pause;
pub use update_config::UpdateConfig;
pub use update_settler::UpdateSettler;
```

### State Module Re-exports (state/mod.rs)

```rust
pub mod clearing_house;
pub mod fate_order;
pub mod player_state;
pub mod referral_state;

pub use clearing_house::ClearingHouseState;
pub use fate_order::{FateOrder, FateOrderStatus};
pub use player_state::PlayerState;
pub use referral_state::ReferralState;
```

---

## 20. Open Questions & Future Considerations

### Questions to Resolve Before Building

1. **Commitment flow**: Do we want 2 TX (commitment in same TX as bet via partial signing) or 3 TX (commitment separate)? Recommendation: start with 3 for simplicity.

2. ~~**Buy-side settlement**~~: **RESOLVED**: Use 1-TX partial signing for buy-side fills when player is online (settler signs settlement, player co-signs Jupiter swap). Fallback to settle-only TX if player doesn't respond within 30s. See LiveView doc Section 3.2 for full flow.

3. ~~**Max multiplier**~~: **RESOLVED** — 210 discrete values from 1.01x to 10.0x across 6 tiers with progressively coarser steps. See Section 5.2.

4. **LP deposit/withdraw fees**: ROGUEBankroll has no fees. BUXBankroll has no fees. Should FateSwap charge LP entry/exit fees? Recommendation: no fees (more attractive for LPs).

5. **Multisig for authority**: Use Squads Protocol or simple keypair? Recommendation: Squads for mainnet, keypair for devnet.

6. **Token eligibility enforcement**: Purely off-chain (current plan) or on-chain allowlist? Recommendation: off-chain (cheaper, more flexible).

### Future Extensions (Not in v1)

- **Multiple game types**: FatePlinko, FateDice — add as new instruction modules in same program
- **Epoch-based accounting**: For >100K bets/day throughput
- **On-chain order book**: For limit-order-style fate orders with matching
- **Multi-token vaults**: Accept USDC alongside SOL
- **Social features**: On-chain leaderboards via PDAs
- **Governance**: LP token holders vote on fee changes

---

*This document covers the complete on-chain architecture for FateSwap on Solana. It transfers every proven pattern from our EVM contracts (ROGUEBankroll LP pool mechanics, BuxBoosterGame commit-reveal provably fair system, referral rewards, dynamic bet limits) into the Solana/Anchor paradigm while leveraging Solana's unique strengths (cheap transactions, fast finality, native program upgradeability).*

*The same provably fair commit-reveal system used in BuxBoosterGame V3 is used here — no VRF, no external oracle. If it's provably fair enough for BuxBoosterGame on Rogue Chain, it's provably fair enough for FateSwap on Solana.*
