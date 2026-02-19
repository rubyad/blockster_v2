# Cross-Chain Bridge Research for BUX Booster

> Research compiled Feb 2026. Goal: Enable players to deposit any major token on Ethereum/Arbitrum/Solana and instantly receive ROGUE on Rogue Chain for gambling, and withdraw ROGUE back to any token on any chain.

## Table of Contents
1. [Critical Discovery: Existing Infrastructure](#1-critical-discovery-existing-infrastructure)
2. [Protocol Feasibility Matrix](#2-protocol-feasibility-matrix)
3. [Architecture Options](#3-architecture-options-ranked)
4. [Recommended Approach: Phased Rollout](#4-recommended-approach-phased-rollout)
5. [Deposit & Withdrawal Flows](#5-deposit--withdrawal-flows)
6. [Supported Tokens](#6-supported-tokens-priority-order)
7. [LayerZero V2 Deep Dive](#7-layerzero-v2-deep-dive)
8. [Hyperlane Deep Dive](#8-hyperlane-deep-dive)
9. [deBridge IaaS Deep Dive](#9-debridge-iaas-deep-dive)
10. [Thirdweb Pay / Universal Bridge](#10-thirdweb-pay--universal-bridge)
11. [Gaming Platform UX Patterns](#11-gaming-platform-ux-patterns)
12. [Solana Bridging Specifics](#12-solana-bridging-specifics)
13. [ERC-4337 Integration](#13-erc-4337-integration)
14. [Security Considerations](#14-security-considerations)
15. [Cost Estimates](#15-cost-estimates)
16. [Confirmation Times](#16-confirmation-times)

---

## 1. Critical Discovery: Existing Infrastructure

**Rogue Chain is an Arbitrum Orbit L3** (AnyTrust variant) built on Arbitrum's Nitro stack.

**An existing bridge already exists:**
- URL: https://roguetrader.io/bridge
- Connects: Rogue Chain <-> Arbitrum One
- Mechanism: Lock-and-mint (lock on Arbitrum, mint on Rogue Chain; burn on Rogue Chain, release on Arbitrum)
- Supported tokens: ROGUE, USDT, ARB
- Speed: ~1 minute
- Cost: Free

**ROGUE token specifics:**
- Native gas token on Rogue Chain (like ETH on Ethereum)
- 100B ROGUE created on Arbitrum One (Sept 2024)
- 90B bridged to Rogue Chain, 10B remain on Arbitrum One (liquidity pools + founder wallets)
- Gas cost: fixed 100 Gwei (~0.031 ROGUE per transaction)
- Exists as ERC-20 on Arbitrum One, becomes native gas on Rogue Chain

**Current problem:** The existing bridge ONLY connects to Arbitrum One. To bridge from Ethereum, Solana, Base, etc., users must multi-hop (source chain -> Arbitrum One -> Rogue Chain). This is the friction we need to eliminate.

---

## 2. Protocol Feasibility Matrix

| Protocol | Rogue Chain Support | Self-Deploy? | Solana? | Cost | Timeline | Feasibility |
|----------|-------------------|--------------|---------|------|----------|-------------|
| **LayerZero V2** | NOT supported | No (needs LZ partnership) | Yes | Partnership | Months+ | LOW |
| **Hyperlane** | NOT supported (but self-deployable) | YES | Yes (SVM) | Infra only | 4-8 weeks | HIGH |
| **deBridge IaaS** | NOT supported (but IaaS available) | Turnkey | Yes | ~$10K/month | 2-4 weeks | HIGH |
| **Wormhole** | NOT supported | No (19 Guardians needed) | Yes | Partnership | Months+ | VERY LOW |
| **Axelar** | NOT supported | Planned 2026 (Amplifier) | No | TBD | 2026+ | MEDIUM |
| **Thirdweb Universal Bridge** | Aggregator (needs underlying bridge) | N/A | Yes | Free/usage | Depends | CONDITIONAL |
| **Existing Orbit Bridge** | YES (Arbitrum only) | Already deployed | No | Free | Today | Already works |
| **Custom Relayer/Vault** | Build ourselves | Yes | Yes | Dev cost | 2-4 weeks | HIGH |

---

## 3. Architecture Options (Ranked)

### Option A: Centralized Relayer/Vault (FASTEST, BEST GAMING UX)

Deploy vault contracts on source chains. Users deposit tokens, backend detects and instantly credits ROGUE/BUX on Rogue Chain.

**How it works:**
1. Deploy vault contracts on Ethereum, Arbitrum, (Solana via program)
2. User deposits USDC/ETH/SOL/etc. to vault
3. Backend relayer detects deposit event
4. Instantly credits ROGUE to user's smart_wallet_address on Rogue Chain
5. Settlement/rebalancing happens async

**Pros:** Fastest to build (2-4 weeks), instant deposits, integrates with existing BUX minter, works with any source chain, no external dependencies

**Cons:** Centralized (single point of failure), custodial risk, needs multi-sig + monitoring + emergency pause, Ronin Bridge hack ($625M) cautionary tale

### Option B: Hyperlane Warp Routes (BEST DECENTRALIZED, PERMISSIONLESS)

Self-deploy Hyperlane on Rogue Chain. Use Warp Routes for token bridging.

**How it works:**
1. `hyperlane registry init` - configure Rogue Chain metadata
2. `hyperlane core deploy` - deploy Mailbox, ISM, hooks, validators
3. Deploy Warp Routes: HypNative.sol for ROGUE, HypERC20Collateral.sol for BUX
4. Run validator(s) and relayer infrastructure
5. Submit registry PR for official listing

**Pros:** Truly permissionless, supports EVM + Solana (SVM), 150+ chains, configurable security via ISMs, no protocol fees beyond gas

**Cons:** Must run own validator/relayer infra, self-managed security, needs 2+ audits ($75K-$150K), 4-8 week timeline

### Option C: deBridge IaaS (BEST TURNKEY, PROFESSIONAL)

Subscribe to deBridge's Infrastructure-as-a-Service for Rogue Chain.

**How it works:**
- Pay subscription -> smart contracts deployed -> validators auto-pick-up -> market makers auto-start
- Intent-based DLN (zero-TVL) architecture
- Already integrated 20+ chains (Injective, Cronos, HyperEVM, MegaETH)

**Pros:** Turnkey, 24+ chains connected automatically, built-in liquidity network, professional security, includes Solana support, DLN API for programmatic integration

**Cons:** ~$10K/month subscription, dependency on deBridge, less control

### Option D: Extend Existing Orbit Bridge + Aggregators

Use existing Rogue Chain <-> Arbitrum bridge. Add Layer Leap for direct ETH->Rogue Chain. Use LI.FI/Squid for the "any token" part up to Arbitrum.

**How it works:**
1. User selects token on any chain
2. LI.FI/Squid widget swaps + bridges to USDC/ETH on Arbitrum
3. Existing Orbit bridge handles Arbitrum -> Rogue Chain hop
4. Two transactions but can be abstracted in UI

**Pros:** Leverages existing infra, no new bridge contracts needed, free

**Cons:** Two-hop latency, no direct Solana path, depends on Rogue Chain team adopting Layer Leap

### Option E: LayerZero OFT (LONG-TERM IDEAL)

Get LayerZero to deploy Endpoint on Rogue Chain. Deploy OFT Adapter for ROGUE.

**Feasibility:** LOW without demonstrating significant volume/TVL. Requires LayerZero Labs partnership via Discord. 132+ chains supported but adding new ones is gated.

---

## 4. Recommended Approach: Phased Rollout

### Phase 1: Quick Win (Week 1-2) — Optimize Existing Bridge
- Embed a bridge widget in BUX Booster UI that wraps the existing roguetrader.io bridge
- Add LI.FI or Squid widget for "any token -> Arbitrum" first hop
- Two-step flow but much better than current manual process
- **Cost:** Minimal (widget integration only)

### Phase 2: Instant Deposits via Centralized Vault (Week 3-6)
- Deploy vault contracts on Ethereum and Arbitrum
- Backend relayer service detects deposits, instantly credits ROGUE to user's smart wallet
- Integrate with existing BUX minter service for crediting
- Multi-sig on vaults, rate limiting, emergency pause
- **Tokens:** ETH, USDC, USDT on Ethereum; ETH, USDC, ARB on Arbitrum
- **Cost:** $15-30K development + $50-100K audit

### Phase 3: Solana + Decentralized Bridge (Month 2-3)
- Either: Deploy Hyperlane on Rogue Chain (decentralized, $75-150K audit)
- Or: Subscribe to deBridge IaaS (~$10K/month, turnkey)
- This adds Solana support (SOL, USDC) and provides decentralized fallback
- **Cost:** $100-200K (Hyperlane) OR $120K/year (deBridge)

### Phase 4: Full Abstraction (Month 3-4)
- Build unified deposit/withdrawal UI
- Integrate Thirdweb Pay for fiat onramp
- "Enter amount -> Pay with card/crypto -> Funds in game wallet" flow
- Investigate Thirdweb Universal Bridge routes if underlying bridge infra now exists
- **Cost:** $10-20K development

### Phase 5: LayerZero Integration (Long-term, if volume justifies)
- Approach LayerZero with volume/TVL data
- Deploy OFT Adapter for ROGUE
- Access to 132+ chains via single standard
- **Cost:** Partnership negotiation + $20-40K development

---

## 5. Deposit & Withdrawal Flows

### Deposit: User has ETH/USDC/SOL -> needs ROGUE on Rogue Chain

**Centralized Vault Flow (fastest UX):**
```
User selects "Deposit $100 USDC from Ethereum"
  -> User approves USDC transfer to our vault contract on Ethereum
  -> Vault emits DepositEvent(user, amount, token)
  -> Backend relayer detects event (waits for finality)
  -> Backend sends ROGUE to user's smart_wallet_address on Rogue Chain
  -> User sees ROGUE balance instantly (or within 1-2 blocks)
```

**Decentralized Bridge Flow (Hyperlane/deBridge):**
```
User selects "Deposit $100 USDC from Ethereum"
  -> Swap USDC to bridge-compatible token on source chain (if needed)
  -> Bridge contract locks tokens on source chain
  -> Cross-chain message sent via Hyperlane/deBridge
  -> Destination contract mints/releases ROGUE on Rogue Chain
  -> ROGUE sent to user's smart_wallet_address
  -> ~1-5 min confirmation
```

### Withdrawal: User has ROGUE on Rogue Chain -> wants USDC on Ethereum

**Centralized Vault Flow:**
```
User selects "Withdraw 10,000 ROGUE to USDC on Ethereum"
  -> User signs gasless UserOperation on Rogue Chain (Paymaster sponsors)
  -> UserOp sends ROGUE to our vault on Rogue Chain
  -> Backend converts ROGUE amount to USDC equivalent
  -> Backend releases USDC from Ethereum vault to user's address
  -> User receives USDC on Ethereum (1-5 min)
```

### Price Conversion
- Use existing token_prices Mnesia table for ROGUE price
- Use CoinGecko/price feeds for source token prices
- Apply small spread (0.5-1%) to cover price volatility during bridge time
- Rate limit large withdrawals (>$10K require manual review)

---

## 6. Supported Tokens (Priority Order)

| Priority | Token | Chains | Bridge Volume Share |
|----------|-------|--------|-------------------|
| 1 | **USDC** | Ethereum, Arbitrum, Solana | Highest bridged stablecoin |
| 2 | **ETH** | Ethereum, Arbitrum | Dominant bridged asset |
| 3 | **USDT** | Ethereum, Arbitrum, Solana | Second stablecoin |
| 4 | **SOL** | Solana | Native Solana gas |
| 5 | **ARB** | Arbitrum | Already on existing bridge |
| 6 | **WETH** | All EVM | Wrapped ETH for DeFi |
| 7 | **WBTC** | Ethereum, Arbitrum | Bitcoin exposure |
| 8 | **DAI** | Ethereum, Arbitrum | Decentralized stablecoin |
| 9 | **LINK** | Ethereum, Arbitrum | DeFi infrastructure |
| 10 | **MATIC/POL** | Polygon | Gaming ecosystem |

**MVP recommendation:** Start with ETH, USDC, USDT on Ethereum + Arbitrum. Add SOL + USDC on Solana in Phase 3.

---

## 7. LayerZero V2 Deep Dive

### Architecture
- **Endpoints:** Immutable contracts on each chain (validate messages, assign verification jobs)
- **DVNs:** 30+ providers (Google Cloud, Polyhedra, Animoca). Apps choose which to use.
- **Executors:** Monitor source chains, submit txs on destination, abstract destination gas
- **132+ chains** supported (all major EVM + Solana, Aptos, Sui, TON)

### Message Flow
1. OApp calls `EndpointV2.send()` on source chain
2. DVNs independently verify payloadHash on destination
3. Once DVN threshold met, message committed
4. Executor calls `Endpoint.lzReceive()` with verified payload

### OFT Standard (what we'd use for ROGUE)
- **OFT Adapter** for existing tokens: lock/unlock on source chain, mint/burn on destination
- Major adoption: 25.4% of stablecoins >$50M use OFT (USDT0, USDe, PYUSD)
- Supports composable execution (custom logic on destination)

### Adding Rogue Chain
- **NOT self-service.** LayerZero Labs must deploy Endpoints, Send/Receive Libraries, Executors
- At least one DVN must support the chain
- Contact via Discord, demonstrate chain maturity
- Can run your own DVN but still need LZ to deploy core contracts first

### Fees
- 4 components: source gas + DVN fees + executor fees + destination gas
- Typical: **$0.70-$1.20 per transfer** (2025)
- Payable in native gas or ZRO token

### Security
- X-of-Y-of-N DVN configuration per source-destination pair
- Default: Google Cloud + LayerZero Labs DVNs
- Trust assumption: security holds if at least one required DVN is honest

---

## 8. Hyperlane Deep Dive

### Why Hyperlane is Best for Rogue Chain
- **Truly permissionless** - deploy on ANY chain without approval
- Supports EVM + SVM (Solana) + Cosmos
- 150+ chains, $6B+ bridged, ~9M messages
- CLI-driven deployment process

### Deployment Process
```bash
# 1. Configure chain metadata
hyperlane registry init  # Set chain ID 560013, RPC, native token

# 2. Deploy core contracts
hyperlane core init       # Generate config
hyperlane core deploy     # Deploy Mailbox, ISM factories, hooks

# 3. Test messaging
hyperlane send message --relay

# 4. Deploy token bridge (Warp Routes)
hyperlane warp init       # Configure: HypNative.sol for ROGUE, HypERC20Collateral.sol for BUX
hyperlane warp deploy

# 5. Run infrastructure
# - Validator(s): sign checkpoints for message verification
# - Relayer: delivers messages cross-chain

# 6. Register
# Submit PR to Hyperlane Registry on GitHub
```

### Warp Routes for ROGUE
- **HypNative.sol**: For native gas tokens (ROGUE on Rogue Chain)
- **HypERC20Collateral.sol**: For ERC-20s (BUX, or ROGUE-as-ERC20 on Arbitrum)
- User sends native ROGUE -> contract wraps and bridges -> destination unwraps

### Security
- Configurable ISMs (Interchain Security Modules)
- Options: multisig validators, trusted relayers, custom modules
- Self-managed = your responsibility

### Infrastructure Requirements
- Run 1+ validators (sign checkpoints)
- Run 1+ relayers (deliver messages)
- Cloud hosting: ~$500-2K/month for basic setup

---

## 9. deBridge IaaS Deep Dive

### Architecture
- Intent-based DLN (Decentralized Liquidity Network)
- Zero-TVL model: no user funds stored in contracts
- User creates order -> solvers compete to fulfill -> proof submitted -> funds released
- Transfers settle in seconds

### IaaS for Custom Chains
- Turnkey solution for any EVM/SVM chain
- **Reported cost: ~$10,000/month** (quarterly/yearly payments)
- Process: pay subscription -> contracts deployed -> validators auto-start -> market makers auto-start
- Grace period of 10 days if payments stop
- Recent integrations: Injective, Cronos, HyperEVM, MegaETH

### DLN API
- RESTful at `dln.debridge.finance`
- Endpoints for quoting, creating, managing trades
- Hooks system for custom destination logic (e.g., credit to smart wallet)

### Solana Support
- Full via `evm-sol-serializer` library
- Constructs Solana calls from EVM side

---

## 10. Thirdweb Pay / Universal Bridge

### What It Does
- Unified API: swap tokens + bridge chains + fiat onramp + payments
- 95+ EVM chains + Solana
- 14,000+ tokens, 15M+ aggregated routes
- Components: `BuyWidget`, `CheckoutWidget`, `TransactionWidget`, `PayEmbed`

### Smart Wallet Integration
- Designed for ERC-4337 natively
- Paymasters sponsor gas -> users sign UserOps -> bundlers submit
- `PayEmbed` handles: fiat -> crypto -> bridge -> destination chain

### Limitation for Rogue Chain
- Universal Bridge is an **aggregator** of underlying bridges
- If NO bridge protocol supports Rogue Chain, no routes will exist
- Need to check `thirdweb.com/routes` for chain 560013 availability
- **After deploying Hyperlane or deBridge**, Thirdweb may auto-aggregate those routes

### Best Use
- Fiat onramp layer ON TOP of whatever bridge we deploy
- Users can buy crypto with card, which then bridges to Rogue Chain
- Integrate after Phase 2/3 when bridge infrastructure exists

---

## 11. Gaming Platform UX Patterns

### Ronin (Axie Infinity)
- Custom bridge (migrated from multi-sig to Chainlink CCIP after $625M hack)
- Simplified wallet via social logins
- Bridge: ~15 min from Ethereum, few min from Arbitrum

### Immutable X
- ZK-rollup on Ethereum (StarkEx)
- "Passport": email login, no seed phrases
- Zero gas fees for minting/trading

### Rhino.fi Smart Deposit Addresses (BEST UX PATTERN)
- Each user gets a **static deposit address**
- Send tokens from ANY chain/wallet/CEX to this address
- Platform auto-detects, routes, swaps, settles
- No wallet connection, no network switching, no approvals
- 35 chains including Solana
- Used by GRVT, Paradex, EveDex

### Key UX Principles
1. Abstract chain complexity - user never thinks about "bridging"
2. Show progress indicators during transfer
3. Email/social login (no seed phrases)
4. "Instant credit" pattern: show balance immediately, confirm in background
5. Single deposit address (Rhino.fi style) = gold standard
6. "Refuel" feature for destination gas tokens

---

## 12. Solana Bridging Specifics

### EVM <-> Solana Differences
- Solana uses Rust/Anchor programs, not Solidity
- Account model vs storage model
- `uint64` balances vs EVM `uint256` (max ~18.4T tokens with 6 shared decimals)
- CPI depth limit (4 levels max)
- Max 5 DVNs per path due to 1232-byte tx limit
- Each dev deploys own OFT Program instance

### Best Solana Bridge Options
1. **deBridge DLN** - full Solana support, intent-based, fast
2. **Wormhole** - Solana-native, 30+ chains, NTT framework
3. **Across Protocol** - launched Solana bridging Aug 2025, ZK-based
4. **LayerZero** - live on Solana Mainnet, connects to 70+ chains

### For Rogue Chain <-> Solana
Since neither LayerZero nor Wormhole support Rogue Chain:
- **deBridge IaaS** would handle this automatically (Solana included)
- **Hyperlane** supports SVM but deployment on Solana is more complex
- **Centralized vault** works for Solana too (deploy Solana program for vault)

---

## 13. ERC-4337 Integration

### Deposit Side (Source Chain)
- User has funds on Ethereum/Arbitrum/Solana
- They approve + deposit to vault/bridge contract on source chain
- **This side still requires gas from the user** (or use Thirdweb Pay fiat onramp)
- For non-crypto users: fiat -> crypto via Thirdweb Pay -> deposit in one flow

### Destination Side (Rogue Chain) - FULLY GASLESS
- ROGUE credited to user's `smart_wallet_address`
- Existing Paymaster sponsors all gas
- User never pays gas on Rogue Chain

### Withdrawal
- User signs gasless UserOperation on Rogue Chain
- UserOp calls bridge/vault contract
- Paymaster sponsors the Rogue Chain gas
- Bridge relays to destination chain
- User receives tokens on destination

### Integration with Existing Stack
- Thirdweb already manages smart wallets
- Paymaster already deployed on Rogue Chain
- BUX Minter service can be extended for ROGUE crediting
- Key: ensure bridge credits go to `smart_wallet_address`, not `wallet_address`

---

## 14. Security Considerations

### Bridge Hack History
| Hack | Amount | Cause |
|------|--------|-------|
| Ronin | $625M | Multi-sig too centralized (5/9 keys, 1 entity) |
| Wormhole | $325M | Signature verification bug in Solana contract |
| Nomad | $190M | Uninitialized proxy allowed fraudulent messages |

### Security Requirements for Custom Bridge
1. **Multi-sig:** Minimum 3-of-5 (ideally 5-of-9 with diverse key holders)
2. **Event verification:** Verify source CONTRACT ADDRESS, not just event structure
3. **Finality:** Wait for source chain finality before minting (critical for L2s)
4. **Rate limiting:** Cap per-transaction and per-hour withdrawal amounts
5. **Time-locked upgrades:** On all bridge contracts
6. **Emergency pause:** Circuit breaker for anomalous activity
7. **Audits:** 2+ independent security audits ($75K-$150K each)
8. **Monitoring:** Real-time alerts for large transfers, failed verifications
9. **Never hardcode private keys** in relayer code
10. **Separate hot/cold wallets** for vault management

### For Centralized Vault Specifically
- Hot wallet: holds small operating balance for instant crediting
- Cold wallet: holds bulk of vault funds (multi-sig, time-locked)
- Auto-rebalance: refill hot wallet from cold when low
- Withdrawal limits: instant up to $1K, 1-hour delay for $1K-$10K, manual review for >$10K

---

## 15. Cost Estimates

| Approach | Development | Audit | Monthly Ongoing | First Year Total |
|----------|------------|-------|-----------------|-----------------|
| Phase 1: Widget integration | $2-5K | $0 | $0 | $2-5K |
| Phase 2: Centralized vault | $15-30K | $50-100K | $1-3K (infra) | $80-160K |
| Phase 3a: Hyperlane deploy | $20-40K | $75-150K | $2-5K (validators) | $120-220K |
| Phase 3b: deBridge IaaS | $5-10K | Included | ~$10K | $125-130K |
| Phase 4: Full UI abstraction | $10-20K | $0 | $0 | $10-20K |
| Phase 5: LayerZero OFT | $20-40K | Included | $0 | Partnership |

**Estimated total for Phases 1-3:** $200K-$400K first year (Hyperlane path) or $200K-$300K (deBridge path)

---

## 16. Confirmation Times

| Method | Deposit Time | Withdrawal Time |
|--------|-------------|-----------------|
| Centralized vault (instant credit) | Instant (1-2 blocks) | 1-5 min |
| Existing Orbit bridge | ~1 min | ~1 min |
| Hyperlane Warp Route | 2-5 min | 2-5 min |
| deBridge DLN | Seconds to 1 min | Seconds to 1 min |
| LayerZero OFT | 1-3 min | 1-3 min |
| LI.FI/Squid (multi-hop) | 5-15 min | 5-15 min |

---

## Summary: TL;DR Recommendation

**Rogue Chain is an Arbitrum Orbit L3 with an existing bridge to Arbitrum One.** The fastest path to smooth UX:

1. **Now:** Embed existing bridge + LI.FI widget for "any token -> Arbitrum -> Rogue Chain"
2. **Month 1:** Build centralized vault for instant deposits (ETH, USDC, USDT on ETH + Arbitrum)
3. **Month 2-3:** Deploy Hyperlane OR subscribe to deBridge for decentralized bridging + Solana
4. **Month 3-4:** Build unified "one-click deposit" UI with Thirdweb Pay fiat onramp
5. **Long-term:** Pursue LayerZero listing once volume justifies it

The centralized vault + instant credit pattern is what most gaming platforms actually use. Combine with decentralized bridge for withdrawals and fallback. The end-user experience should be: **"Enter amount -> Pay -> Play"** with zero bridge/chain awareness.
