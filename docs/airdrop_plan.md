# Airdrop Feature — Implementation Plan

## Progress
- [x] Phase 1: AirdropVault.sol + Hardhat tests (77 tests passing)
- [x] Phase 2: AirdropPrizePool.sol + Hardhat tests (48 tests passing)
- [x] Phase 3: Deploy Both Contracts + post-deploy verification tests
- [x] Phase 4: Backend — Airdrop Context & Provably Fair + Elixir tests (99 tests passing)
- [x] Phase 5: Backend — BUX Minter Integration (Redeem + Claim) + integration tests (15 tests passing)
- [x] Phase 6: Frontend — Redeem Flow + LiveView tests
- [x] Phase 7: Frontend — Winners Display, Claim & Provably Fair Modal + LiveView tests
- [ ] Phase 8: End-to-End Testing on mainnet

**Testing rule**: Every phase must include extensive tests before moving to the next phase. No phase is complete without passing tests.

### Phase 1 Implementation Notes (AirdropVault.sol)
- **File**: `contracts/bux-booster-game/contracts/AirdropVault.sol` (flattened OZ v5 UUPS)
- **Inherits**: Initializable, OwnableUpgradeable, UUPSUpgradeable
- **Key functions**: `depositFor()` (owner deposits on behalf of users), `startRound()`, `closeAirdrop()`, `drawWinners()`, `withdrawBux()`, `getWalletForPosition()` (binary search)
- **Events**: `BuxDeposited`, `AirdropClosed`, `WinnerSelected`, `AirdropDrawn`, `RoundStarted`
- **Provably fair on-chain**: commit-reveal pattern — `sha256(serverSeed) == commitmentHash`, combined seed = `keccak256(serverSeed | blockHashAtClose)`, winner[i] = `keccak256(combined, i) % totalEntries + 1`
- **Multi-round**: All data keyed by `roundId`, previous rounds remain queryable
- **Position blocks**: Sequential 1-indexed positions, each BUX = 1 position, binary search for O(log n) lookup
- **77 Hardhat tests** across deployment, UUPS upgrade, round lifecycle, deposits, binary search, winner selection, fairness verification, multi-round, and edge cases

### Phase 2 Implementation Notes (AirdropPrizePool.sol)
- **File**: `contracts/bux-booster-game/contracts/AirdropPrizePool.sol` (flattened OZ v5 UUPS)
- **Inherits**: Initializable, OwnableUpgradeable, UUPSUpgradeable
- **Key functions**: `fundPrizePool()`, `setPrize(roundId, winnerIndex, winner, amount)`, `sendPrize(roundId, winnerIndex)`, `startNewRound()`, `withdrawUsdt()`
- **Events**: `PrizePoolFunded`, `PrizeSet`, `PrizeSent`, `NewRoundStarted`, `UsdtWithdrawn`
- **Prize lifecycle**: Fund pool with USDT → set 33 prizes per round → send each prize individually (marks claimed, prevents double-send)
- **SafeERC20**: All USDT transfers use `safeTransfer`/`safeTransferFrom`
- **Multi-round**: Prizes isolated by `roundId`, independent per round
- **48 Hardhat tests** (technically 47 in file) across deployment, UUPS upgrade, funding, prize config, distribution, withdrawal, multi-round, view functions, and E2E flow

### Phase 3 Deployed Addresses
- **AirdropVault (Rogue Chain)**: `0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c` (impl: `0x0770BF55BdA8d070971D6288272E3A59aC43b5b4`)
- **AirdropPrizePool (Arbitrum One)**: `0x919149CA8DB412541D2d8B3F150fa567fEFB58e1` (impl: `0x168861a4056b1b9E4A49302b5EC53695b8974471`)
- Both owned by Vault Admin: `0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9`
- Arbiscan verification pending (Etherscan v1 API deprecated — verify manually)

### Phase 5 Implementation Notes
- **BUX Minter (Node.js)**: 3 new endpoints added to `bux-minter/index.js`:
  - `POST /airdrop-deposit` — Mints BUX to vault + `depositFor()`, parses `BuxDeposited` event
  - `POST /airdrop-claim` — Calls `sendPrize()` on Arbitrum, parses `PrizeSent` event
  - `POST /airdrop-set-prize` — Calls `setPrize()` to register winners during draw
- **Infrastructure**: Vault admin wallet + contract instances for both chains, two new TransactionQueues (`vaultAdmin` on Rogue, `vaultAdminArbitrum` on Arbitrum)
- **Elixir BuxMinter**: 3 new functions — `airdrop_deposit/4`, `airdrop_claim/2`, `airdrop_set_prize/4`
- **Deposit strategy**: Mint BUX directly to vault contract, then call `depositFor` (avoids approve/transferFrom complexity with smart wallets)
- **Prerequisite**: BUX Minter must be redeployed to `bux-minter.fly.dev` before endpoints work from Elixir backend
- **Fly secret needed**: `VAULT_ADMIN_PRIVATE_KEY` already staged on bux-minter app

### Phase 4 Implementation Notes (Backend — Airdrop Context)
- **Context module**: `lib/blockster_v2/airdrop.ex` — all public API for rounds, entries, winners, verification
- **Schemas**: `Airdrop.Round` (status: pending→open→closed→drawn), `Airdrop.Entry` (user deposits with start/end positions), `Airdrop.Winner` (33 per round with claim tracking)
- **Round functions**: `create_round/1`, `get_current_round/0`, `get_round/1`, `get_past_rounds/0`, `close_round/2`
- **Entry functions**: `redeem_bux/4` (validates phone verified, open round, creates position block), `get_user_entries/2`, `get_total_entries/1`, `get_participant_count/1`
- **Winner functions**: `draw_winners/1`, `get_winners/1`, `get_winner/2`, `is_winner?/2`, `claim_prize/5`
- **Provably fair**: `keccak256_combined/2` (ExKeccak), `derive_position/3`, `verify_fairness/1`, `get_verification_data/1` (only reveals server_seed after draw)
- **Prize structure**: 33 winners — $250 (1st), $150 (2nd), $100 (3rd), $50×30 (4th-33rd) = $2,000 total
- **Position system**: Contiguous 1-indexed blocks, each BUX = 1 position, `find_entry_for_position/2` binary search
- **99 tests across 4 files**: `airdrop_test.exs` (60), `airdrop_provably_fair_test.exs` (15), `airdrop_schema_test.exs` (24)

### Phase 6 Implementation Notes (Frontend — Redeem Flow)
- **File**: `lib/blockster_v2_web/live/airdrop_live.ex` (991 lines)
- **Mount**: Loads current round, user entries, connected wallet, BUX balance, total entries, participant count; subscribes to PubSub `airdrop:{round_id}` on connected mount; starts 1s tick timer for countdown
- **Entry section**: BUX balance display, numeric input with MAX button, contextual button states (Login / Verify Phone / Connect Wallet / Enter Amount / Insufficient Balance / Redeem X BUX)
- **Redeem flow**: `handle_event("redeem_bux")` validates user, phone verified, connected wallet, round open, amount > 0, amount <= balance → `start_async(:redeem_bux)` calling `Airdrop.redeem_bux/4`
- **Async handlers**: Success updates balance, entries list, total entries, participant count, broadcasts PubSub `{:airdrop_deposit, ...}`; error maps reason atoms to user-friendly messages
- **Receipt panels**: Per-entry cards showing position blocks (#start–#end), entry count, timestamp, RogueScan tx link
- **Real-time updates**: PubSub `handle_info({:airdrop_deposit, ...})` updates total entries/participants for all connected users; `:tick` updates countdown timer
- **Pool stats bar**: Shows "X BUX from Y participants" above entry form
- **Prize distribution grid**: 4-column grid showing 1st ($250), 2nd ($150), 3rd ($100), 30× ($50)
- **"How It Works"**: 3-step explainer (Earn BUX → Redeem → Win)

### Phase 7 Implementation Notes (Frontend — Winners Display, Claim & Provably Fair)
- **Celebration section** (`celebration_section/1`): Replaces entry section after draw — gradient header, top-3 podium with medal icons and prize amounts, full 33-winner table with columns: #, Winner (RogueScan link), Position, Block range, Prize, Status
- **Winner status** (`winner_status/1`): 4 states — "Claimed" badge (+ Arbiscan tx link), "Claim" button (if current user is winner + has connected wallet), "Connect Wallet" link (if winner but no wallet), dash (other users)
- **Claim flow**: `handle_event("claim_prize")` → `start_async(:claim_prize)` → `Airdrop.claim_prize/5`; success updates winner in list + recomputes entry results; error maps `:already_claimed`, `:not_your_prize`, `:winner_not_found`
- **TODO**: `claim_tx = "pending"` at line 159 — needs to call `BuxMinter.airdrop_claim` for real Arbitrum tx hash (wiring deferred to Phase 8 E2E)
- **Receipt panels post-draw**: Winning entries show trophy icon, place, prize amount, claim button; losing entries show "No win this round"
- **Entry results**: `compute_entry_results/2` maps each entry to matching winners by checking if `winner.random_number` falls within entry's `start_position..end_position`
- **Provably fair modal** (`fairness_modal/1`): 4-step walkthrough — (1) Commitment hash published before round opened, (2) Block hash captured at close, (3) Server seed revealed + SHA256 match verified, (4) Winner derivation formula + full 33-winner verification table
- **PubSub for draw**: `handle_info({:airdrop_drawn, round_id, winners})` flips `airdrop_drawn: true`, loads verification data, computes entry results, shows flash

---

## Overview

Users redeem BUX tokens into an on-chain vault on Rogue Chain. Each BUX redeemed becomes 1 "entry" with a sequential position number. When the countdown reaches zero, a provably fair RNG selects 33 random positions — the wallets holding those positions win USDT prizes on Arbitrum One.

### Architecture

```
ROGUE CHAIN                           ARBITRUM ONE
┌──────────────────────┐              ┌──────────────────────┐
│   AirdropVault.sol   │              │  AirdropPrizePool.sol│
│                      │              │                      │
│  - Accept BUX deposits│             │  - Hold USDT         │
│  - Track position    │              │  - sendPrize() by    │
│    blocks per wallet │              │    admin to winner's │
│  - Provably fair RNG │              │    external wallet   │
│  - Record 33 winners │              │  - Track claimed     │
│  - Verifiable on     │              │    status per winner │
│    RogueScan         │              │    on Arbiscan       │
└──────────────────────┘              └──────────────────────┘
         ▲                                     ▲
         │ BUX transfer                        │ USDT transfer
         │                                     │
┌────────┴─────────────────────────────────────┴──────────┐
│                  Blockster Backend (Elixir)              │
│                                                          │
│  - Airdrop context module                                │
│  - Provably fair seed management (reuse ProvablyFair.ex) │
│  - BUX Minter calls for deposit txs                      │
│  - Prize claim orchestration (cross-chain)               │
│  - LiveView real-time updates                            │
└──────────────────────────────────────────────────────────┘
         ▲
         │
┌────────┴─────────────────────────────────────────────────┐
│                  Airdrop LiveView (UI)                    │
│                                                          │
│  BEFORE countdown ends:                                  │
│  - Prize pool header ($2,000 USDT)                       │
│  - Countdown timer (existing)                            │
│  - Prize distribution boxes (existing)                   │
│  - "Enter the Airdrop" — amount input + Redeem button    │
│  - User's position block display                         │
│                                                          │
│  AFTER countdown ends:                                   │
│  - Countdown frozen at 00:00:00:00                       │
│  - Prize distribution boxes (kept)                       │
│  - "Airdrop has been drawn" section replaces entry form  │
│  - 33 winners table (position, wallet, prize, claim btn) │
│  - Top 3 winners highlighted                             │
│  - Claim button → sends USDT to external wallet on Arb   │
│  - After claimed: "Claimed" badge + Arbiscan tx link     │
└──────────────────────────────────────────────────────────┘
```

### Prize Structure (Same Every Round)
| Place | Prize | Count |
|-------|-------|-------|
| 1st   | $250 USDT | 1 |
| 2nd   | $150 USDT | 1 |
| 3rd   | $100 USDT | 1 |
| 4th-33rd | $50 USDT | 30 |
| **Total** | **$2,000 USDT** | **33** |

### Rules
- **No minimum redemption** — users can redeem as little as 1 BUX
- **Phone verification required** — user must be phone verified to redeem (same check as other token-gated features)
- **Unlimited redemptions** — users can redeem multiple times per round, each creating a new position block
- **Redeemed BUX**: Admin withdraws from vault after draw (back to treasury)
- **Same prizes every round** — $2,000 USDT, 33 winners, fixed structure

---

## Phase 1: AirdropVault.sol (Rogue Chain)

**New file**: `contracts/bux-booster-game/contracts/AirdropVault.sol`

### Contract Responsibilities
- UUPS upgradeable proxy (same pattern as BuxBoosterGame)
- Accept BUX deposits from any wallet (via `transferFrom` after user approves)
- Track sequential position blocks per depositor
- Store provably fair commitment hash before airdrop opens
- After deadline: draw 33 winners using revealed server seed
- Store winners on-chain for public verification
- Multi-round support — each round is independent, old round data persists on-chain

### State Variables
```solidity
// Core
address public owner;
IERC20 public buxToken;                           // BUX on Rogue Chain
uint256 public airdropEndTime;                    // Countdown deadline
bool public isOpen;                               // Accepting deposits?
bool public isDrawn;                              // Winners selected?
uint256 public roundId;                           // For multiple test rounds

// Provably Fair
bytes32 public commitmentHash;                    // SHA256(serverSeed), published before open
bytes32 public revealedServerSeed;                // Revealed after draw
bytes32 public blockHashAtClose;                  // Block hash when airdrop closed (external entropy)
uint256 public closeBlockNumber;                  // Block number when closed

// Position Tracking
uint256 public totalEntries;                      // Total BUX deposited (1 BUX = 1 entry)
struct Deposit {
    address blocksterWallet;                      // Smart wallet that sent the BUX
    address externalWallet;                       // Connected external wallet (for prize delivery proof)
    uint256 startPosition;                        // Inclusive (1-indexed)
    uint256 endPosition;                          // Inclusive
    uint256 amount;
}
Deposit[] public deposits;                        // Sequential deposit log
mapping(address => uint256) public totalDeposited; // Per-blocksterWallet total

// Winners
uint256 public constant NUM_WINNERS = 33;
struct Winner {
    uint256 randomNumber;                         // The random position selected
    address blocksterWallet;                      // Blockster smart wallet
    address externalWallet;                       // External wallet receiving USDT prize
    uint256 depositIndex;                         // Index into deposits[] for verification
    uint256 depositAmount;                        // BUX redeemed in winning deposit block
    uint256 depositStart;                         // Winning block start position
    uint256 depositEnd;                           // Winning block end position
}
Winner[33] public winners;                        // 0-indexed internally, but view function is 1-indexed
```

### Key Functions
```solidity
// --- Admin ---
function initialize(address _buxToken) external;  // Set BUX token address (UUPS initializer)
function startRound(bytes32 _commitmentHash, uint256 _endTime) external onlyOwner;  // Starts new round (increments roundId)
function closeAirdrop() external onlyOwner;        // Stops deposits for current round, records block hash
function drawWinners(bytes32 _serverSeed) external onlyOwner;  // Reveal seed + select winners for current round
function withdrawBux(uint256 roundId) external onlyOwner;      // Recover deposited BUX after draw

// --- Deposit (admin calls on behalf of user) ---
function depositFor(
    address blocksterWallet,   // User's smart_wallet_address (BUX source)
    address externalWallet,    // User's connected external wallet (prize destination)
    uint256 amount             // BUX amount (must be pre-transferred to vault)
) external onlyOwner;

// --- Public View Functions ---
function getDeposit(uint256 index) external view returns (Deposit memory);
function getDepositCount() external view returns (uint256);
function getWalletForPosition(uint256 position) external view returns (address blocksterWallet, address externalWallet);
function getUserDeposits(address blocksterWallet) external view returns (Deposit[] memory);
function verifyFairness() external view returns (bytes32 commitment, bytes32 seed, bytes32 blockHash, uint256 totalEntries);

// --- Winner Verification (1-indexed: 1 = 1st prize, 33 = last) ---
function getWinnerInfo(uint256 prizePosition) external view returns (
    address blocksterWallet,   // Blockster smart wallet that deposited BUX
    address externalWallet,    // External wallet that receives USDT prize
    uint256 buxRedeemed,       // BUX amount in the winning deposit block
    uint256 blockStart,        // Deposit block start position
    uint256 blockEnd,          // Deposit block end position
    uint256 randomNumber       // The random position that was selected
);
```

### Winner Selection Algorithm (On-Chain)
```solidity
function drawWinners(bytes32 _serverSeed) external onlyOwner {
    require(isOpen == false, "Must close first");
    require(!isDrawn, "Already drawn");
    require(sha256(abi.encodePacked(_serverSeed)) == commitmentHash, "Invalid seed");

    revealedServerSeed = _serverSeed;
    isDrawn = true;

    // Combined seed = keccak256(serverSeed | blockHashAtClose)
    // blockHashAtClose provides external entropy the server can't predict
    bytes32 combinedSeed = keccak256(abi.encodePacked(_serverSeed, blockHashAtClose));

    for (uint256 i = 0; i < NUM_WINNERS; i++) {
        // Each winner: hash(combinedSeed, winnerIndex) mod totalEntries + 1
        uint256 randomNumber = (uint256(keccak256(abi.encodePacked(combinedSeed, i))) % totalEntries) + 1;
        uint256 depositIdx = _findDepositIndex(randomNumber);
        Deposit storage dep = deposits[depositIdx];

        winners[i] = Winner({
            randomNumber: randomNumber,
            blocksterWallet: dep.blocksterWallet,
            externalWallet: dep.externalWallet,
            depositIndex: depositIdx,
            depositAmount: dep.amount,
            depositStart: dep.startPosition,
            depositEnd: dep.endPosition
        });

        // prizePosition is 1-indexed in events for human readability
        emit WinnerSelected(roundId, i + 1, randomNumber, dep.blocksterWallet, dep.externalWallet);
    }

    emit AirdropDrawn(roundId, _serverSeed, blockHashAtClose, totalEntries);
}
```

### Position Lookup (Binary Search)
```solidity
function _findWalletForPosition(uint256 position) internal view returns (address) {
    // Binary search through deposits[] to find which deposit contains this position
    uint256 low = 0;
    uint256 high = deposits.length - 1;
    while (low <= high) {
        uint256 mid = (low + high) / 2;
        if (position < deposits[mid].startPosition) {
            high = mid - 1;
        } else if (position > deposits[mid].endPosition) {
            low = mid + 1;
        } else {
            return deposits[mid].wallet;
        }
    }
    revert("Position not found");
}
```

### Provably Fair Guarantee
1. **commitmentHash** published on-chain before airdrop opens (users can see it)
2. **blockHashAtClose** captured when airdrop closes (server can't predict future block hash)
3. **revealedServerSeed** must hash to commitmentHash (server can't change it)
4. **combinedSeed** = keccak256(serverSeed + blockHashAtClose) — neither party controls both inputs
5. **Winner derivation** is deterministic from combinedSeed — anyone can verify

### `getWinnerInfo` View Function — Detailed Explanation

This is the key public verification function. Anyone can call it on RogueScan to prove winners are real.

**Solidity implementation:**
```solidity
function getWinnerInfo(uint256 prizePosition) external view returns (
    address blocksterWallet,
    address externalWallet,
    uint256 buxRedeemed,
    uint256 blockStart,
    uint256 blockEnd,
    uint256 randomNumber
) {
    require(isDrawn, "Airdrop not drawn yet");
    require(prizePosition >= 1 && prizePosition <= NUM_WINNERS, "Invalid prize position");

    // Convert 1-indexed input to 0-indexed internal storage
    Winner storage winner = winners[prizePosition - 1];
    Deposit storage dep = deposits[winner.depositIndex];

    return (
        dep.blocksterWallet,    // The Blockster smart wallet that sent the BUX
        dep.externalWallet,     // The external wallet (MetaMask etc.) receiving the USDT prize
        dep.amount,             // How much BUX was in this deposit block
        dep.startPosition,      // Block start (e.g., 2001)
        dep.endPosition,        // Block end (e.g., 2100)
        winner.randomNumber     // The random number selected (e.g., 2056)
    );
}
```

**What each return value proves:**
| Field | What it proves | Example |
|-------|---------------|---------|
| `blocksterWallet` | This Blockster user deposited BUX into the airdrop | `0xAbC...dEf` |
| `externalWallet` | This is where their USDT prize was sent (verifiable on Arbiscan) | `0x123...789` |
| `buxRedeemed` | They put 100 BUX into this deposit block | `100` |
| `blockStart` | Their entries start at position 2,001 | `2001` |
| `blockEnd` | Their entries end at position 2,100 | `2100` |
| `randomNumber` | The provably fair RNG selected position 2,056 | `2056` |

**Anyone can verify**: randomNumber (2,056) falls within blockStart–blockEnd (2,001–2,100), proving this wallet legitimately won. The externalWallet can be checked on Arbiscan to confirm the USDT was actually sent there.

### RogueScan Deep Link

RogueScan is Blockscout-based. Deep links can target a specific function on the read contract tab using the function selector hash fragment.

**`getWinnerInfo(uint256)` selector:** `0x6b1da364`

**Deep link format (UUPS proxy):**
```
https://roguescan.io/address/{PROXY_ADDRESS}?tab=read_proxy&source_address={IMPLEMENTATION_ADDRESS}#0x6b1da364
```

This opens the Read Proxy tab scrolled directly to the `getWinnerInfo` function. The visitor enters a prize position (1-33) and clicks Query.

**Example link in winners table:**
Each winner row has a "Verify" link that goes to:
```
https://roguescan.io/address/0xVAULT_PROXY?tab=read_proxy&source_address=0xVAULT_IMPL#0x6b1da364
```

The table shows the prize position number (1-33) next to each winner so the visitor knows what to enter.

**What the visitor sees after querying `getWinnerInfo(1)`:**
```
blocksterWallet:  0xAbCdEf...1234    ← Blockster smart wallet that deposited BUX
externalWallet:   0x789012...5678    ← External wallet that received the USDT prize
buxRedeemed:      100                ← 100 BUX in this deposit block
blockStart:       2001               ← Entries start at position 2,001
blockEnd:         2100               ← Entries end at position 2,100
randomNumber:     2056               ← Provably fair RNG selected position 2,056
```

**Verification chain:**
1. `randomNumber` (2,056) falls within `blockStart`–`blockEnd` (2,001–2,100) → proves this wallet won
2. `externalWallet` can be checked on [Arbiscan](https://arbiscan.io) to confirm USDT was sent there
3. `verifyFairness()` shows the seed + block hash that produced the random number
4. Anyone can recompute: `keccak256(serverSeed, blockHashAtClose)` → derive all 33 random numbers

**Other verification functions on the same page:**
- `verifyFairness()` → returns commitmentHash, revealedServerSeed, blockHashAtClose, totalEntries
- `getDeposit(index)` → browse all deposits sequentially
- `getDepositCount()` → see total number of deposits
- `commitmentHash` / `revealedServerSeed` / `blockHashAtClose` → public state variables readable directly

### Events
```solidity
event RoundStarted(uint256 roundId, bytes32 commitmentHash, uint256 endTime);
event BuxDeposited(uint256 roundId, address indexed blocksterWallet, address indexed externalWallet, uint256 amount, uint256 startPosition, uint256 endPosition);
event AirdropClosed(uint256 roundId, uint256 totalEntries, bytes32 blockHashAtClose);
event WinnerSelected(uint256 roundId, uint256 prizePosition, uint256 randomNumber, address blocksterWallet, address externalWallet);
event AirdropDrawn(uint256 roundId, bytes32 serverSeed, bytes32 blockHash, uint256 totalEntries);
```

### Tests (Hardhat) — `test/AirdropVault.test.js`

**Deployment & Initialization**
- Deploy as UUPS proxy, verify owner set correctly
- Initialize with BUX token address, verify stored
- Cannot initialize twice (UUPS initializer guard)
- Upgrade to new implementation, verify state preserved

**Round Lifecycle**
- startRound sets commitmentHash, endTime, roundId, isOpen=true
- Cannot startRound while another round is open
- Cannot startRound with zero commitment hash or past endTime
- closeAirdrop sets isOpen=false, captures blockHashAtClose
- Cannot close an already closed round
- Cannot close if no round is open

**Deposits**
- depositFor records correct blocksterWallet, externalWallet, amount
- Position blocks are sequential: first deposit gets 1→N, second gets N+1→M
- Multiple deposits from same wallet create separate position blocks, totalDeposited accumulates
- Cannot deposit when round is not open
- Cannot deposit when round is closed
- Cannot deposit zero amount
- Deposit with 1 BUX works (no minimum)
- Events: BuxDeposited emitted with correct args

**Position Lookup**
- getWalletForPosition returns correct wallet for first/middle/last position in a block
- Binary search works with 1 deposit, 2 deposits, 100 deposits
- getWalletForPosition reverts for position 0 or position > totalEntries
- getUserDeposits returns all deposit blocks for a wallet

**Winner Selection (drawWinners)**
- Reverts if round not closed
- Reverts if already drawn
- Reverts if serverSeed doesn't hash to commitmentHash (invalid seed)
- Valid seed: draws 33 winners, each randomNumber between 1 and totalEntries
- Each winner has correct blocksterWallet, externalWallet, depositAmount, depositStart, depositEnd
- Deterministic: same seed + same blockHash = same winners every time
- Same wallet can win multiple prizes (not excluded after first win)
- Events: WinnerSelected emitted 33 times, AirdropDrawn emitted once

**getWinnerInfo View Function**
- Returns correct data for prizePosition 1 (1st place) through 33
- Reverts for prizePosition 0 and 34 (out of range)
- Reverts before draw (isDrawn=false)
- randomNumber falls within blockStart–blockEnd for every winner

**verifyFairness**
- Returns all four values correctly after draw
- SHA256(revealedServerSeed) == commitmentHash

**Multi-Round**
- Start round 1, deposit, close, draw → start round 2
- Round 2 deposits don't interfere with round 1 data
- getWinnerInfo works for both rounds independently

**Edge Cases**
- 1 depositor, 1 BUX: all 33 winners point to same wallet
- 2 depositors with equal amounts: roughly even distribution
- Large number of deposits (100+): gas usage acceptable
- withdrawBux after draw succeeds, before draw reverts

---

## Phase 2: AirdropPrizePool.sol (Arbitrum One)

**New file**: `contracts/bux-booster-game/contracts/AirdropPrizePool.sol`

### Contract Responsibilities
- UUPS upgradeable proxy (same pattern as BuxBoosterGame)
- Hold USDT for prize distribution
- Admin sends prizes to winners' external wallets
- Track claimed status per winner per round
- Configurable prize amounts for testing

### Key State
```solidity
address public owner;
IERC20 public usdt;                              // USDT on Arbitrum (6 decimals)
uint256 public roundId;

struct Prize {
    address winner;
    uint256 amount;                               // In USDT (6 decimals)
    bool claimed;
    bytes32 txRef;                                // Cross-reference to Rogue Chain proof
}

mapping(uint256 => mapping(uint256 => Prize)) public prizes;  // roundId => winnerIndex => Prize
```

### Key Functions
```solidity
// --- Admin ---
function initialize(address _usdt) external;
function fundPrizePool(uint256 amount) external onlyOwner;    // Deposit USDT
function setPrize(uint256 _roundId, uint256 winnerIndex, address winner, uint256 amount) external onlyOwner;
function sendPrize(uint256 _roundId, uint256 winnerIndex) external onlyOwner;  // Transfer USDT to winner
function startNewRound() external onlyOwner;
function withdrawUsdt(uint256 amount) external onlyOwner;     // Recover unused USDT

// --- View ---
function getPrize(uint256 _roundId, uint256 winnerIndex) external view returns (Prize memory);
function getRoundPrizeTotal(uint256 _roundId) external view returns (uint256);
```

### USDT on Arbitrum One
- **Contract**: `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` (USDT on Arb One, 6 decimals)
- Admin approves + calls `fundPrizePool()` to deposit
- `sendPrize()` calls `usdt.transfer(winner, amount)`

### Events
```solidity
event PrizePoolFunded(uint256 roundId, uint256 amount);
event PrizeSet(uint256 roundId, uint256 winnerIndex, address winner, uint256 amount);
event PrizeSent(uint256 roundId, uint256 winnerIndex, address winner, uint256 amount);
```

### Tests (Hardhat) — `test/AirdropPrizePool.test.js`

**Deployment & Initialization**
- Deploy as UUPS proxy, verify owner set correctly
- Initialize with USDT address, verify stored
- Cannot initialize twice
- Upgrade to new implementation, verify state preserved

**Funding**
- fundPrizePool transfers USDT from owner to contract
- Contract USDT balance increases correctly
- Cannot fund with zero amount
- Event: PrizePoolFunded emitted

**Prize Configuration**
- setPrize stores winner address and amount correctly for each winnerIndex
- Set all 33 prizes, verify each stored
- Cannot setPrize for winnerIndex > 32 (0-indexed internally)
- Only owner can call setPrize
- Event: PrizeSet emitted

**Prize Distribution**
- sendPrize transfers correct USDT amount to winner's external wallet
- Winner's USDT balance increases by exact prize amount
- Prize marked as claimed after send
- Cannot sendPrize twice for same winnerIndex (already claimed)
- Cannot sendPrize if prize not set (zero address)
- Cannot sendPrize if contract has insufficient USDT balance
- Only owner can call sendPrize
- Event: PrizeSent emitted

**Withdrawal**
- withdrawUsdt sends USDT back to owner
- Cannot withdraw more than contract balance
- Only owner can withdraw

**Multi-Round**
- startNewRound increments roundId
- Prizes from round 1 are independent of round 2
- Can fund and distribute prizes across multiple rounds

**Full Flow**
- Fund $2000 USDT → set 33 prizes ($250, $150, $100, 30×$50) → send all 33 → verify all claimed
- Verify contract USDT balance is 0 after all prizes sent

---

## Phase 3: Deploy Both Contracts

### AirdropVault → Rogue Chain (560013)
1. Add `AirdropVault` to Hardhat config (already has `rogueMainnet` network)
2. Deploy script: `scripts/deploy-airdrop-vault.js`
3. Deploy as UUPS proxy (same pattern as BuxBoosterGame deploy.js)
4. Initialize with BUX token address: `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8`
5. Transfer ownership to vault admin wallet: `0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9`

### AirdropPrizePool → Arbitrum One
1. Add `arbitrumOne` network to `hardhat.config.js`:
   ```javascript
   arbitrumOne: {
     url: "https://arb1.arbitrum.io/rpc",
     chainId: 42161,
     accounts: [process.env.DEPLOYER_PRIVATE_KEY],
     gasPrice: "auto",
     timeout: 120000
   }
   ```
2. Deploy script: `scripts/deploy-airdrop-prize-pool.js`
3. Deploy as UUPS proxy
4. Initialize with USDT address: `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9`
5. Fund with test amount of USDT (e.g., $5-10 initially)

### Post-Deploy
- Record both contract addresses in CLAUDE.md
- Verify on RogueScan and Arbiscan
- Test basic interactions (deposit BUX, fund USDT)

---

## Phase 4: Backend — Airdrop Context & Provably Fair

**New files**:
- `lib/blockster_v2/airdrop.ex` — Main context module
- `lib/blockster_v2/airdrop/round.ex` — Ecto schema for airdrop rounds
- `lib/blockster_v2/airdrop/entry.ex` — Ecto schema for user entries
- `lib/blockster_v2/airdrop/winner.ex` — Ecto schema for winners
- Migration for airdrop tables

### Ecto Schemas

**airdrop_rounds**
```elixir
schema "airdrop_rounds" do
  field :round_id, :integer
  field :status, :string            # "open", "closed", "drawn"
  field :end_time, :utc_datetime
  field :server_seed, :string       # Hidden until drawn
  field :commitment_hash, :string
  field :block_hash_at_close, :string
  field :total_entries, :integer, default: 0
  field :vault_address, :string     # AirdropVault on Rogue Chain
  field :prize_pool_address, :string # AirdropPrizePool on Arbitrum
  field :start_round_tx, :string
  field :close_tx, :string
  field :draw_tx, :string
  timestamps()
end
```

**airdrop_entries**
```elixir
schema "airdrop_entries" do
  belongs_to :user, User
  field :round_id, :integer
  field :wallet_address, :string    # User's smart_wallet_address (BUX source)
  field :amount, :integer
  field :start_position, :integer
  field :end_position, :integer
  field :deposit_tx, :string        # Rogue Chain tx hash
  timestamps()
end
```

**airdrop_winners**
```elixir
schema "airdrop_winners" do
  belongs_to :user, User
  field :round_id, :integer
  field :winner_index, :integer     # 0-32
  field :random_number, :integer    # The selected position
  field :wallet_address, :string    # Winner's smart wallet
  field :deposit_start, :integer    # Winning deposit block start position
  field :deposit_end, :integer      # Winning deposit block end position
  field :deposit_amount, :integer   # BUX redeemed in that deposit block
  field :prize_usd, :integer        # Prize in cents (25000 = $250)
  field :prize_usdt, :integer       # Prize in USDT smallest unit (6 decimals)
  field :claimed, :boolean, default: false
  field :claim_tx, :string          # Arbitrum tx hash
  field :claim_wallet, :string      # External wallet that received USDT
  timestamps()
end
```

### Context Functions
```elixir
# Round management
create_round(end_time)              # Generate seed, compute commitment, store
get_current_round()                 # Get active round
close_round(round_id)               # Close deposits, record block hash
draw_winners(round_id)              # Reveal seed, call contract, store winners

# Entry management
redeem_bux(user, amount, round_id)  # Deposit BUX to vault, record entry (requires phone_verified)
get_user_entries(user_id, round_id) # Get user's position blocks
get_total_entries(round_id)         # Total BUX deposited

# Winner management
get_winners(round_id)               # List all 33 winners with details
claim_prize(user, winner_index)     # Send USDT via AirdropPrizePool
is_winner?(user_id, round_id)       # Check if user won

# Provably fair
get_commitment_hash(round_id)       # Public: show commitment before draw
get_verification_data(round_id)     # Public: seed + block hash + results after draw
```

### Provably Fair Flow (Adapted from BUX Booster)
1. **Before airdrop opens**: Generate `server_seed` via `:crypto.strong_rand_bytes(32)`, compute `commitment_hash = SHA256(server_seed)`, call `startRound(commitmentHash, endTime)` on contract
2. **Airdrop open**: Users deposit BUX, commitment hash visible on-chain
3. **Countdown ends**: Call `closeAirdrop()` on contract — captures `blockHashAtClose`
4. **Draw**: Call `drawWinners(serverSeed)` on contract — seed revealed, winners computed on-chain
5. **Verification**: Anyone can see `commitmentHash`, `revealedServerSeed`, `blockHashAtClose` on RogueScan and verify `SHA256(serverSeed) == commitmentHash` and re-derive all 33 winners

### Tests (Elixir) — `test/blockster_v2/airdrop/`

**Schema Tests** (`airdrop_schema_test.exs`)
- Round changeset validates required fields (status, end_time, commitment_hash)
- Entry changeset validates amount > 0, required wallet_address
- Winner changeset validates winner_index 0-32, required fields
- Unique constraints: one entry per user+round+start_position

**Context Tests** (`airdrop_test.exs`)
- `create_round/1` generates server_seed, computes correct commitment_hash
- `get_current_round/0` returns the open round, nil if none
- `get_past_rounds/0` returns drawn rounds ordered by most recent
- `redeem_bux/5` creates entry with correct positions, increments total_entries
- `redeem_bux/5` sequential: two users get non-overlapping position blocks
- `redeem_bux/5` rejects when user is not phone verified
- `redeem_bux/5` rejects when round is closed/drawn
- `get_user_entries/2` returns all entries for a user in a round
- `get_total_entries/1` returns sum of all deposits
- `get_participant_count/1` returns unique wallet count
- `close_round/1` updates status to "closed"
- `draw_winners/1` updates status to "drawn", creates 33 winner records
- `draw_winners/1` assigns correct prize amounts ($250, $150, $100, 30×$50)
- `get_winners/1` returns all 33 winners ordered by winner_index
- `is_winner?/2` returns true for winner, false for non-winner
- `claim_prize/3` marks winner as claimed, stores claim_tx and claim_wallet
- `claim_prize/3` rejects if already claimed
- `claim_prize/3` rejects if user doesn't own the winning index
- `claim_prize/3` rejects if no connected external wallet

**Provably Fair Tests** (`airdrop_provably_fair_test.exs`)
- Server seed generation produces 32-byte hex string
- Commitment hash is SHA256 of server seed
- Verification: SHA256(server_seed) == commitment_hash
- Winner derivation is deterministic (same inputs = same winners)

---

## Phase 5: Backend — BUX Minter Integration

### Vault Admin Wallet & Nonce Management
- **Dedicated vault admin wallet**: `0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9` — used exclusively for AirdropVault `depositFor` calls
- The BUX Minter already has a `TransactionQueue` class (`index.js` line 19) that serializes transactions per wallet, tracks nonces locally, and retries on nonce errors with exponential backoff
- Create a new `TransactionQueue` instance for the vault admin wallet — all `depositFor` calls are enqueued and processed one at a time, preventing nonce conflicts under concurrent load
- **Fly secret**: `VAULT_ADMIN_PRIVATE_KEY` already set on `bux-minter` app
- The AirdropVault contract owner must be transferred to `0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9` after deploy
- **Local testing uses production BUX Minter** — new endpoints on bux-minter must be deployed before local testing works

### Redeem Flow (User deposits BUX to vault)
The BUX Minter service needs a new endpoint to handle the deposit:

**Option A: Direct on-chain from user's smart wallet** (simpler)
- User's smart wallet already holds BUX
- Backend calls BUX Minter: `POST /approve-and-transfer` to approve vault + transfer BUX
- BUX Minter executes: `bux.approve(vault, amount)` then `vault.deposit(amount)` from user's smart wallet

**Option B: Burn + re-mint pattern** (if smart wallet can't call vault directly)
- Backend calls `POST /burn` to burn user's BUX
- Backend calls vault admin function to credit position (off-chain tracking only)

**Recommended: Option A** — keeps everything on-chain and verifiable.

New BUX Minter endpoint needed:
```
POST /airdrop-deposit
Body: { wallet: "0x...", amount: 100, vaultAddress: "0x..." }
Action:
  1. Call bux.approve(vault, amount) from user's smart wallet (via bundler UserOp)
  2. Enqueue on vault admin TransactionQueue: vault.depositFor(wallet, externalWallet, amount)
  3. Return tx hash
```

### Claim Flow (Send USDT to winner on Arbitrum)
- Same vault admin wallet (`0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9`) — different chain, different nonce space, no conflicts
- Second `TransactionQueue` instance on BUX Minter with an Arbitrum One provider
- Wallet needs some ETH on Arbitrum for gas
- AirdropPrizePool ownership must also be transferred to this wallet after deploy

New BUX Minter endpoint:
```
POST /airdrop-claim
Body: { roundId: 1, winnerIndex: 0 }
Action:
  1. Enqueue on Arbitrum TransactionQueue: prizePool.sendPrize(roundId, winnerIndex)
  2. Return tx hash
```

**Fly secret required**: `ARBITRUM_RPC_URL` on `bux-minter` app (or hardcode public RPC)

### Backend Claim Validation
```elixir
def claim_prize(user, round_id, winner_index) do
  winner = get_winner(round_id, winner_index)

  # 1. Verify this user actually won this index
  assert winner.user_id == user.id

  # 2. Verify not already claimed
  assert winner.claimed == false

  # 3. Verify user has connected external wallet
  connected_wallet = Wallets.get_connected_wallet(user.id)
  assert connected_wallet != nil, "Must connect external wallet to claim"

  # 4. Send USDT to connected external wallet on Arbitrum
  {:ok, tx} = call_prize_pool_send(round_id, winner_index, connected_wallet.wallet_address, winner.prize_usdt)

  # 5. Update winner record
  update_winner(winner, %{claimed: true, claim_tx: tx, claim_wallet: connected_wallet.wallet_address})
end
```

### Tests (Elixir) — `test/blockster_v2/airdrop/airdrop_integration_test.exs`

**BUX Minter Integration (mocked)**
- `airdrop_deposit/4` calls BUX Minter with correct wallet, amount, vault address
- `airdrop_deposit/4` handles timeout gracefully (Req 60s timeout)
- `airdrop_deposit/4` returns tx hash on success
- `airdrop_claim/4` calls BUX Minter with correct roundId, winnerIndex, wallet, amount
- `airdrop_claim/4` returns Arbitrum tx hash on success

**Claim Validation**
- Claim succeeds for legitimate winner with connected wallet
- Claim rejects wrong user (user_id doesn't match winner)
- Claim rejects already claimed prize
- Claim rejects user without connected external wallet
- Claim rejects invalid round_id or winner_index

**Full Flow (mocked blockchain)**
- Create round → deposit from 2 users → close → draw → verify winners → claim prize
- All database records created correctly at each step

---

## Phase 6: Frontend — Redeem Flow

**File**: `lib/blockster_v2_web/live/airdrop_live.ex`

### Changes to Existing UI

**1. Wire Up Redeem Button** (replace stub at line 53-62 that currently shows "Redemption coming soon!")
```elixir
def handle_event("redeem_bux", _params, socket) do
  user = socket.assigns.current_user
  amount = socket.assigns.redeem_amount
  round = socket.assigns.current_round
  connected_wallet = socket.assigns.connected_wallet

  # Validate
  cond do
    user == nil -> {:noreply, redirect(socket, to: ~p"/login")}
    !user.phone_verified -> {:noreply, put_flash(socket, :error, "Phone verification required to enter the airdrop")}
    connected_wallet == nil -> {:noreply, put_flash(socket, :error, "Connect an external wallet on your profile page first")}
    amount <= 0 -> {:noreply, put_flash(socket, :error, "Enter an amount")}
    amount > socket.assigns.bux_balance -> {:noreply, put_flash(socket, :error, "Insufficient BUX")}
    round.status != "open" -> {:noreply, put_flash(socket, :error, "Airdrop is closed")}
    true ->
      # Use start_async for blockchain call
      # Pass both wallets — stored on-chain in the deposit for public verification
      user_id = user.id
      smart_wallet = user.smart_wallet_address
      external_wallet = connected_wallet.wallet_address
      start_async(socket, :redeem_bux, fn ->
        Airdrop.redeem_bux(user_id, smart_wallet, external_wallet, amount, round.id)
      end)
      {:noreply, assign(socket, redeeming: true)}
  end
end
```

**2. External Wallet Requirement for Redemption**
- User must have a connected external wallet (from member profile page) BEFORE they can redeem
- Check `Wallets.get_connected_wallet(user.id)` on mount, store in `connected_wallet` assign
- If no wallet: redeem button says "Connect Wallet to Enter" and links to `/member/:slug`
- Both wallets (Blockster smart wallet + external wallet) are recorded on-chain in the deposit
- This means the `getWinnerInfo` view function shows both wallets, proving prizes go to real people

**3. Immediate BUX Balance Update**
- After successful redemption, the user's BUX balance in the top-right header updates immediately
- Use PubSub or direct assign to refresh `bux_balance` without page reload
- User sees their BUX go down in real time as confirmation

**4. Redemption Receipt Panels** (the core post-redeem UX)
- After each successful redemption, show a prominent receipt panel on the page
- Receipts stack vertically — each redemption creates a new panel
- Receipt panels are **always visible** every time the user visits the airdrop page (persisted via `airdrop_entries` DB records)
- Receipt panel contents (before draw):
  ```
  ┌─────────────────────────────────────────────────────┐
  │  ✓ Redeemed 100 BUX                                │
  │                                                     │
  │  Your Block: #2,001 — #2,100                       │
  │  Entries: 100                                       │
  │  Time: Feb 27, 2026 3:42 PM                        │
  │                                                     │
  │  [View on RogueScan →]                              │
  │  (links to deposit tx on roguescan.io)              │
  └─────────────────────────────────────────────────────┘
  ```
- RogueScan link goes to the deposit transaction hash: `https://roguescan.io/tx/{deposit_tx}`
- Multiple receipts stack newest-on-top

**After the draw — receipt panels update in real-time with results:**
- When `airdrop_drawn` PubSub event fires, each receipt panel updates live to show win/lose
- The result is determined by checking if any of the 33 winning random numbers fall within that receipt's block range
- Win state:
  ```
  ┌─────────────────────────────────────────────────────┐
  │  🏆 WINNER! — 1st Place ($250 USDT)                │
  │                                                     │
  │  Redeemed 100 BUX                                   │
  │  Your Block: #2,001 — #2,100                       │
  │  Winning Position: #2,056                           │
  │  Prize: $250 USDT                                   │
  │                                                     │
  │  [Claim Prize]  [View on RogueScan →]               │
  └─────────────────────────────────────────────────────┘
  ```
- Lose state:
  ```
  ┌─────────────────────────────────────────────────────┐
  │  Redeemed 100 BUX — No win this round              │
  │                                                     │
  │  Your Block: #5,001 — #5,100                       │
  │  Entries: 100                                       │
  │                                                     │
  │  [View on RogueScan →]                              │
  └─────────────────────────────────────────────────────┘
  ```
- A single deposit block can win multiple prizes (if multiple random numbers land in same block)
  - In that case, show all prizes on the same receipt panel
- After claiming: receipt shows "Claimed" badge + Arbiscan tx link

**5. Show Total Pool Stats**
- "Total pool: 15,000 BUX from 142 participants"
- Live updates via PubSub broadcast when new deposits come in

### State Management
```elixir
# On mount (connected)
if connected?(socket) do
  # Subscribe to real-time airdrop events
  Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "airdrop:#{round.id}")
  # Tick every second for countdown
  Process.send_after(self(), :tick, 1000)
end

assign(socket,
  current_round: Airdrop.get_current_round(),
  user_entries: Airdrop.get_user_entries(user_id, round_id),
  entry_results: %{},  # Populated after draw — maps entry_id => [winning hits]
  total_entries: Airdrop.get_total_entries(round_id),
  participant_count: Airdrop.get_participant_count(round_id),
  connected_wallet: Wallets.get_connected_wallet(user_id),
  airdrop_drawn: round.status == "drawn",
  winners: if(round.status == "drawn", do: Airdrop.get_winners(round_id), else: []),
  redeeming: false
)

# If already drawn on mount, compute entry results immediately
if round.status == "drawn" do
  entry_results = compute_entry_results(user_entries, winners)
  assign(socket, entry_results: entry_results)
end

# handle_async for redeem success — update BUX balance + add receipt panel
def handle_async(:redeem_bux, {:ok, {:ok, entry}}, socket) do
  user_id = socket.assigns.current_user.id
  new_balance = BlocksterV2.Engagement.get_user_token_balances(user_id) |> Map.get("bux", 0.0)

  {:noreply,
   socket
   |> assign(
     bux_balance: new_balance,
     user_entries: [entry | socket.assigns.user_entries],
     redeeming: false
   )
   |> put_flash(:info, "Successfully redeemed #{entry.amount} BUX!")}
end

# Real-time transition when draw completes
def handle_info({:airdrop_drawn, round_id, winners}, socket) do
  # Update receipt panels with win/lose results for each of the user's entries
  user_entries = socket.assigns.user_entries
  entry_results = compute_entry_results(user_entries, winners)

  {:noreply,
   socket
   |> assign(airdrop_drawn: true, winners: winners, entry_results: entry_results)
   |> put_flash(:info, "The airdrop has been drawn! Check your results below.")}
end

# Matches each user entry's block range against the 33 winning positions
# Returns a map of entry_id => [%{prize_position: 1, random_number: 2056, prize_usd: 250}, ...]
defp compute_entry_results(user_entries, winners) do
  for entry <- user_entries, into: %{} do
    matching_wins = Enum.filter(winners, fn w ->
      w.random_number >= entry.start_position and w.random_number <= entry.end_position
    end)
    {entry.id, matching_wins}
  end
end

# Real-time update when someone deposits
def handle_info({:airdrop_deposit, _round_id, total_entries, participant_count}, socket) do
  {:noreply, assign(socket, total_entries: total_entries, participant_count: participant_count)}
end
```

### Tests (LiveView) — `test/blockster_v2_web/live/airdrop_live_test.exs` (Part 1)

**Page Render**
- Renders countdown timer with correct target date
- Renders prize distribution boxes ($250, $150, $100, 30×$50)
- Shows BUX balance for logged-in user
- Shows "Login to Enter" for unauthenticated user
- Shows "Verify Phone to Enter" when user is not phone verified
- Shows "Connect Wallet to Enter" when user has no connected external wallet
- Shows redeem form when user is phone verified and has connected external wallet

**Redeem Button States**
- Disabled with "Login to Enter" when not logged in
- Disabled with "Verify Phone to Enter" when user is not phone verified
- Disabled with "Connect Wallet to Enter" when no external wallet
- Disabled with "Enter Amount" when amount is 0
- Disabled with "Insufficient Balance" when amount > balance
- Enabled with "Redeem X BUX" when valid
- Shows entry count: "= X entries" below input

**Redeem Flow**
- Clicking MAX sets amount to full BUX balance
- Successful redeem shows receipt panel with block range, BUX amount, timestamp, RogueScan tx link
- Multiple redeems stack receipt panels (newest on top)
- BUX balance in top-right header updates immediately after redeem
- Total pool stats update after redeem
- Receipt panels persist across page visits (loaded from `airdrop_entries` on mount)
- Flash error when airdrop is closed
- Flash error when user is not phone verified

**Receipt Panels**
- Each receipt shows: BUX amount, block range, entry count, timestamp, RogueScan tx link
- Before draw: receipt panels show deposit confirmation only
- After draw: receipt panels update in real-time via PubSub with win/lose result
- Winning receipt: shows prize position, winning number, prize amount, claim button
- Losing receipt: shows "No win this round" state
- A single receipt can show multiple prizes if multiple winners land in same block
- After claim: receipt shows "Claimed" badge + Arbiscan tx link

**Pool Stats**
- Shows total BUX deposited and participant count
- Updates via PubSub when other users deposit

---

## Phase 7: Frontend — Winners Display & Claim

### Page Layout

The entire airdrop page transforms in real-time at 12:00 PM EST when the countdown hits zero. No page refresh needed — LiveView pushes the update to all connected clients via PubSub.

**Before countdown ends**: Entry form with countdown, prize boxes, redeem button
**After countdown ends**: Full celebration + winners display — the page IS the results

### Real-Time Transition at Countdown End

When the countdown reaches 00:00:00:00:
1. Backend `handle_info(:tick)` detects `total_seconds <= 0`
2. Backend triggers `close_round` + `draw_winners` (or these run via scheduled Oban job at exact end time)
3. PubSub broadcasts `airdrop_drawn` to all connected LiveView clients
4. Every user's page transforms instantly — no refresh, no navigation
5. The "Enter the Airdrop" section smoothly replaces with the winners celebration

### Post-Draw UI (replaces entire entry section)

**1. Celebration Header**
- Large: "The Airdrop Has Been Drawn!" with celebratory styling
- "Congratulations to our 33 winners!"
- Countdown frozen at 00:00:00:00
- Prize distribution boxes remain visible

**2. Top 3 Winners Highlight**
- Larger cards above the table for 1st, 2nd, 3rd
- Gold/silver/bronze styling
- Show wallet + position + prize prominently

**3. Full Winners Table**
```
| #  | Winner           | Position | Block        | BUX Redeemed | Prize    | Status      |
|----|------------------|----------|--------------|--------------|----------|-------------|
| 1  | 0xAbC...dEf      | #2,056   | #2,001-2,100 | 100 BUX      | $250     | [Claim]     |  ← gold
| 2  | 0x123...789      | #891     | #501-1,000   | 500 BUX      | $150     | [Claim]     |  ← silver
| 3  | 0xDef...456      | #5,230   | #5,001-5,500 | 500 BUX      | $100     | [Claim]     |  ← bronze
| 4  | 0x789...012      | #3,401   | #3,400-3,450 | 50 BUX       | $50      | Claimed ✓   |
| ...                                                                                      |
| 33 | 0xFed...CbA      | #12,088  | #12,001-13,000| 1,000 BUX   | $50      | [Claim]     |
```

**4. Winner Row Details**
- **Wallet**: Truncated address, linked to RogueScan vault contract `readContract` showing their deposit block (startPosition → endPosition)
- **Position**: The random number that was selected
- **Block**: The winning deposit's position range (startPosition — endPosition)
- **BUX Redeemed**: Amount of BUX in that specific deposit block (so viewers can see the winning number falls within the block)
- **Prize**: USD amount
- **Claim Button**: Only visible to the actual winner when logged in
  - Checks `Wallets.get_connected_wallet(user.id)` — uses the wallet already connected on member profile page
  - After claim: shows "Claimed" with Arbiscan tx link
  - If no external wallet connected: button says "Connect Wallet to Claim" → links to `/member/:slug` profile page
  - No wallet connection UI on the airdrop page itself

**5. Provably Fair Verification Modal**
- Button below winners table: "Verify Fairness" → opens full-screen modal
- Use `/frontend-design` for polished modal design
- Modal contents:
  - **Header**: "Provably Fair Verification" with lock icon
  - **Step-by-step visual explanation**:
    1. **Before Airdrop Opened** — "We committed to a secret seed before anyone could enter"
       - Show: `Commitment Hash: 0xabc...` (truncated, copy button, link to RogueScan tx that submitted it)
       - Explain: "This hash was published on-chain before the airdrop opened. It locks in our secret seed — we can't change it."
    2. **Airdrop Closed** — "The blockchain provided external randomness we couldn't predict"
       - Show: `Block Hash at Close: 0xdef...` (copy button, link to RogueScan block)
       - Show: `Block Number: 12345678`
       - Explain: "When the airdrop closed, we captured this block hash. Nobody can predict future block hashes."
    3. **Seed Revealed** — "We revealed our secret seed — verify it matches the commitment"
       - Show: `Server Seed: 0x789...` (full value, copy button)
       - Show: `SHA256(Server Seed) = 0xabc...` ← matches commitment hash from step 1
       - Visual checkmark: "✓ Seed matches commitment"
    4. **Winner Derivation** — "Each winner is derived deterministically from the combined seed"
       - Show: `Combined Seed = keccak256(Server Seed + Block Hash)`
       - For each winner (collapsible list):
         - `Winner #1: keccak256(Combined Seed, 0) mod Total Entries + 1 = Position #2,056`
         - `Winner #2: keccak256(Combined Seed, 1) mod Total Entries + 1 = Position #891`
         - etc.
       - Explain: "Anyone can re-run this math to verify every winner was selected fairly."
  - **Footer**: "All values are stored on-chain at [contract address] — verify on RogueScan"
  - Link to RogueScan contract read functions showing commitmentHash, revealedServerSeed, blockHashAtClose, winners[]

### Claim Handler
```elixir
def handle_event("claim_prize", %{"winner_index" => index}, socket) do
  user = socket.assigns.current_user
  round_id = socket.assigns.current_round.id

  # Check for connected external wallet on member profile
  connected_wallet = Wallets.get_connected_wallet(user.id)

  if connected_wallet == nil do
    {:noreply, put_flash(socket, :error, "Connect an external wallet on your profile page to claim")}
  else
    start_async(socket, :claim_prize, fn ->
      Airdrop.claim_prize(user, round_id, String.to_integer(index))
    end)
    {:noreply, assign(socket, claiming_index: String.to_integer(index))}
  end
end
```

### Tests (LiveView) — `test/blockster_v2_web/live/airdrop_live_test.exs` (Part 2)

**Winners Display**
- After draw: "Enter the Airdrop" section replaced by "Airdrop Has Been Drawn"
- Countdown frozen at 00:00:00:00
- Top 3 winners rendered with gold/silver/bronze styling
- Full 33-row winners table renders correctly
- Each row shows: wallet, position, block range, BUX redeemed, prize, status
- Wallet addresses truncated and linked to RogueScan getWinnerInfo deep link
- Prize amounts correct: $250, $150, $100, 30×$50

**Claim Button**
- Claim button visible only to the logged-in winner
- Other users see prize amount but no claim button
- Non-logged-in users see no claim buttons
- Clicking claim triggers async claim flow
- After claim: button replaced by "Claimed" with Arbiscan tx link
- If winner has no connected wallet: shows "Connect Wallet to Claim" linking to profile

**Provably Fair Modal**
- "Verify Fairness" button renders below winners table
- Clicking opens modal with 4 verification steps
- Modal shows commitment hash, block hash, server seed, winner derivation
- SHA256 verification checkmark displayed
- Modal has RogueScan contract link
- Modal closes on backdrop click or X button

**Real-Time Transition**
- Page transforms live at countdown end — no refresh needed
- PubSub broadcast triggers UI update for all connected clients
- Entry form replaced by celebration + winners table instantly
- Users who were on the page at 12:00 PM see it happen live

---

## Phase 8: End-to-End Testing

### Test Plan (Mainnet with Small Amounts)

**Setup**:
1. Deploy AirdropVault to Rogue Chain with BUX token
2. Deploy AirdropPrizePool to Arbitrum One with USDT
3. Fund prize pool with $5 USDT (test amounts: 1st=$2, 2nd=$1.50, 3rd=$1, rest=$0.05)

**Test Scenario**:
1. Start round with commitment hash + 5-minute countdown
2. Redeem 50 BUX from Account A → positions 1-50
3. Redeem 30 BUX from Account B → positions 51-80
4. Wait for countdown / manually close
5. Draw winners — verify 33 random numbers generated
6. Check winners table displays correctly
7. Claim prize from winning account — verify USDT arrives on Arbitrum
8. Verify "Claimed" status updates in UI
9. Reset round, repeat with different amounts

**Contract Testability Features**:
- `startRound()` creates a new round — no need to reset, just start another
- No hardcoded prize amounts in vault (just tracks positions)
- Prize amounts set dynamically in AirdropPrizePool via `setPrize()`
- Short countdown times allowed (1 minute for testing)
- `withdrawBux(roundId)` to recover test BUX after draw
- UUPS upgradeable — can fix issues without redeploying

---

## Key Decisions

### Why On-Chain RNG vs Off-Chain?
The winner selection runs **on-chain** in `drawWinners()` because:
- Fully verifiable by anyone on RogueScan
- No trust required in Blockster server
- Combined seed uses `blockHashAtClose` (external entropy server can't control)
- Matches the "on-chain verifiable randomness" promise shown on current page

### Why Two Contracts?
BUX lives on Rogue Chain, USDT prizes on Arbitrum. No bridge needed — backend orchestrates cross-chain by:
1. Reading winners from Rogue Chain contract
2. Calling prize distribution on Arbitrum contract
3. Storing claim tx hashes in Postgres for UI

### UUPS Upgradeable Proxies
Both contracts use UUPS proxy pattern (same as BuxBoosterGame) so we can fix bugs and add improvements after deployment without redeploying. Standard OZ UUPS with `_authorizeUpgrade` restricted to owner.

### External Wallet for Claims
- **Redeem**: Any logged-in user (BUX comes from their smart wallet)
- **Claim**: User must already have a connected external wallet on their member profile page
- Uses existing `ConnectedWallet` schema — no new wallet connection UI on airdrop page
- Backend checks `Wallets.get_connected_wallet(user.id)` at claim time
- If no wallet connected: claim button says "Connect Wallet on Profile" and links to `/member/:slug`

### Multi-Round Support (Future)
- The contract supports multiple rounds via `roundId` for future airdrops
- For now, the UI focuses entirely on the current round — no next-round countdown shown after draw
- After draw, the page celebrates the winners — that's the whole focus
- When we're ready for round 2, we'll update the UI to show the next countdown
- Each round has its own commitment hash, server seed, winners — fully independent on-chain

---

## Files to Create/Modify

### New Files
| File | Purpose |
|------|---------|
| `contracts/bux-booster-game/contracts/AirdropVault.sol` | BUX deposit + winner selection |
| `contracts/bux-booster-game/contracts/AirdropPrizePool.sol` | USDT prize distribution |
| `contracts/bux-booster-game/scripts/deploy-airdrop-vault.js` | Deploy to Rogue Chain |
| `contracts/bux-booster-game/scripts/deploy-airdrop-prize-pool.js` | Deploy to Arbitrum |
| `contracts/bux-booster-game/test/AirdropVault.test.js` | Hardhat tests |
| `contracts/bux-booster-game/test/AirdropPrizePool.test.js` | Hardhat tests |
| `lib/blockster_v2/airdrop.ex` | Airdrop context |
| `lib/blockster_v2/airdrop/round.ex` | Round schema |
| `lib/blockster_v2/airdrop/entry.ex` | Entry schema |
| `lib/blockster_v2/airdrop/winner.ex` | Winner schema |
| `priv/repo/migrations/xxx_create_airdrop_tables.exs` | DB migration |

### Modified Files
| File | Changes |
|------|---------|
| `lib/blockster_v2_web/live/airdrop_live.ex` | Activate redeem, add winners display, claim flow |
| `contracts/bux-booster-game/hardhat.config.js` | Add Arbitrum One network |
| `bux-minter/index.js` | Add `/airdrop-deposit` and `/airdrop-claim` endpoints |
| `lib/blockster_v2/bux_minter.ex` | Add `airdrop_deposit/3` and `airdrop_claim/4` functions |
| `CLAUDE.md` | Add AirdropVault and AirdropPrizePool contract addresses |
