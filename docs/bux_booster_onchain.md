# BUX Booster On-Chain Implementation Plan

> **⚠️ DOCUMENTATION STATUS**: Parts of this document contain outdated V2 contract code and implementation details.
> For current contract implementation, see:
> - **V4 Upgrade**: [v4_upgrade_summary.md](v4_upgrade_summary.md) - Current version (removed server seed verification)
> - **V3 Upgrade**: [v3_upgrade_summary.md](v3_upgrade_summary.md) - Server-side result calculation
> - **Contract Source**: [contracts/bux-booster-game/contracts/BuxBoosterGame.sol](../contracts/bux-booster-game/contracts/BuxBoosterGame.sol)
>
> **Key Changes in V3/V4**:
> - Server calculates results off-chain (V3)
> - Contract removed server seed verification (V4)
> - `settleBet(commitmentHash, serverSeed, results[], won)` signature
> - Commitment hash serves as bet ID
>
> This document is preserved for historical reference and high-level architecture.

## Deployed Contract

| Property | Value |
|----------|-------|
| **Contract Address** | `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` |
| **Type** | UUPS Proxy |
| **Owner** | `0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0` |
| **Settler** | `0x4BBe1C90a0A6974d8d9A598d081309D8Ff27bb81` |
| **Network** | Rogue Chain Mainnet (Chain ID: 560013) |
| **Explorer** | [View on Roguescan](https://roguescan.io/address/0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B) |

## Overview

This document outlines the plan to convert BUX Booster to a fully on-chain game where:

1. Players bet actual ERC-20 tokens (BUX, moonBUX, etc.)
2. Tokens are held in escrow by the smart contract during gameplay
3. Winnings are automatically paid out on-chain
4. Game results remain provably fair using the existing commit-reveal pattern
5. House edge built into multipliers

## Unauthenticated User Access

**Updated: December 2024**

BUX Booster supports full UI interaction for unauthenticated users to preview the game before signing up:

### What Works for Non-Logged-In Users:

✅ **Full UI Access**:
- View game interface at `/play` without redirect
- See zero balances in all displays
- Switch between tokens (BUX/ROGUE) in dropdown
- Change difficulty levels (all 9 levels)
- Select predictions by clicking coins (heads/tails)
- Input any bet amount
- Use bet controls (½, 2×, MAX buttons)
- View Provably Fair dropdown (shows placeholder text)
- See potential win calculations update in real-time

✅ **Bet Controls Behavior**:
- **Manual Input**: Accept any positive integer
- **MAX Button**: Sets bet to contract's max bet (e.g., 60 BUX for 1.98x)
- **Double (2×)**: Doubles bet, capped at contract max
- **Halve (½)**: Halves bet amount
- **Potential Win**: Calculates correctly as `bet_amount × multiplier`

🔒 **What Requires Login**:
- Clicking "Place Bet" button → redirects to `/login`
- No blockchain transactions initiated
- No commitment hash submitted
- No Mnesia operations

### Implementation Details:

**File**: `lib/blockster_v2_web/live/bux_booster_live.ex`

**Mount Logic** ([lines 27-167](lib/blockster_v2_web/live/bux_booster_live.ex#L27-L167)):
- Unauthenticated users get zero balances map
- No wallet initialization
- No blockchain calls
- House balance still fetched for max bet calculation

**Event Handlers**:
- `select_token` - Skips user stats load if not logged in
- `set_max_bet` - Uses contract max instead of user balance
- `double_bet` - Caps at contract max instead of user balance
- `halve_bet` - Works identically for all users
- `update_bet_amount` - Accepts any positive integer
- `start_game` - Redirects to login if not authenticated
- `reset_game` - Only resets UI state for unauthenticated users
- `load-more-games` - Returns empty for unauthenticated users

**Provably Fair Display**:
- Shows placeholder: `<hashed_server_seed_displays_here_when_you_are_logged_in>`
- Dropdown still clickable to educate users about fairness system

### Benefits:

1. **Better Onboarding**: Users can explore game mechanics before signup
2. **Reduced Friction**: No forced login to see how the game works
3. **Education**: Users learn difficulty levels, multipliers, and fairness before playing
4. **Trust Building**: Transparent preview of all game features
5. **No Security Risk**: Zero blockchain exposure for unauthenticated users

## Provably Fair System (V4)

**Current Implementation**: Server calculates results, contract trusts server input, players verify off-chain with online SHA256 tools.

### How It Works

1. **Before Bet**: Server generates random server seed (64-char hex) and commits `SHA256(server_seed_hex_string)`
2. **Player Bets**: Player sees commitment hash, makes predictions, places bet
3. **Result Calculation**: Server calculates results using:
   - Client seed: `SHA256(user_id:bet_amount:token:difficulty:predictions)`
   - Combined seed: `SHA256(server_seed_hex:client_seed_hex:nonce)`
   - Results: Decode combined seed to bytes, each byte < 128 = Heads, >= 128 = Tails
4. **Settlement**: Server submits results to contract with revealed server seed
5. **Verification**: Player can verify:
   - Step 1: `SHA256(server_seed)` matches commitment shown before bet
   - Step 2: Recalculate client seed from their bet details
   - Step 3: Recalculate combined seed and results
   - All steps verifiable with online SHA256 calculators (e.g., md5calc.com)

### V4 Changes (Dec 2024)

**Removed**: Contract verification that `sha256(abi.encodePacked(serverSeed)) == commitmentHash`

**Rationale**:
- Solidity's `abi.encodePacked(bytes32)` hashes binary bytes
- Online SHA256 tools hash hex strings (characters)
- Same server seed produces different hashes depending on method
- Server is already trusted source for results (V3)
- Removing verification enables player verification with standard tools

**Impact**: No security regression, improved player transparency

## Key Requirements

- **No OpenZeppelin imports** - Roll our own Ownable, ReentrancyGuard, Pausable
- **Flatten IERC20** - Include interface directly for easier verification
- **9 difficulty levels** - Including negative (Win One mode)
- **House edge multipliers** - Edge built into payout rates
- **Dynamic max bet** - 0.1% of house balance, extrapolated for difficulty
- **Player stats on-chain** - Total bets, per-difficulty stats, profit/loss
- **Account Abstraction** - Players don't need ROGUE for gas (Paymaster sponsors)
- **Hardhat deployment** - Direct to Rogue Chain mainnet
- **Real-time balance sync** - Chain → Mnesia → UI

## Supported Tokens (11 tokens)

| Token | Contract Address |
|-------|------------------|
| BUX | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` |
| moonBUX | `0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5` |
| neoBUX | `0x423656448374003C2cfEaFF88D5F64fb3A76487C` |
| rogueBUX | `0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3` |
| flareBUX | `0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8` |
| nftBUX | `0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED` |
| nolchaBUX | `0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642` |
| solBUX | `0x92434779E281468611237d18AdE20A4f7F29DB38` |
| spaceBUX | `0xAcaCa77FbC674728088f41f6d978F0194cf3d55A` |
| tronBUX | `0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665` |
| tranBUX | `0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96` |

**EXCLUDED**: blocksterBUX (`0x133Faa922052aE42485609E14A1565551323CdbE`), ROGUE (separate contract later)

## Difficulty Levels & Multipliers (House Edge Built In)

### Win One Mode (Negative Difficulties)
Need only 1 correct flip out of N flips.

| Level | Flips | Win Chance | Multiplier | Basis Points |
|-------|-------|------------|------------|--------------|
| -4 | 5 | 96.875% | 1.02x | 10200 |
| -3 | 4 | 93.75% | 1.05x | 10500 |
| -2 | 3 | 87.5% | 1.13x | 11300 |
| -1 | 2 | 75% | 1.32x | 13200 |

### Win All Mode (Positive Difficulties)
Must get ALL flips correct.

| Level | Flips | Win Chance | Multiplier | Basis Points |
|-------|-------|------------|------------|--------------|
| 1 | 1 | 50% | 1.98x | 19800 |
| 2 | 2 | 25% | 3.96x | 39600 |
| 3 | 3 | 12.5% | 7.92x | 79200 |
| 4 | 4 | 6.25% | 15.84x | 158400 |
| 5 | 5 | 3.125% | 31.68x | 316800 |

## Max Bet Calculation

### Contract Formula

The contract calculates max bet to ensure consistent **max payout** of 0.2% of house balance:

```solidity
function _calculateMaxBet(uint256 houseBalance, uint8 diffIndex) internal view returns (uint256) {
    uint256 baseMaxBet = (houseBalance * MAX_BET_BPS) / 10000; // 0.1% of house
    uint256 multiplier = MULTIPLIERS[diffIndex];

    // Scale inversely with multiplier
    return (baseMaxBet * 20000) / multiplier;
}
```

Where:
- `MAX_BET_BPS = 10` (0.1% in basis points)
- `MULTIPLIERS[diffIndex]` = multiplier in basis points (e.g., 19800 for 1.98x)

### Formula Breakdown

1. **Base**: 0.1% of house balance (e.g., 59.7 BUX for 59,704 BUX house)
2. **Scaled by 20000**: Multiplied by 200 (20000/100) to get 2x the base
3. **Divided by multiplier**: Scales inversely to keep payout consistent

**Example** (House balance = 59,704 BUX):

| Difficulty | Multiplier | Max Bet | Max Payout | Formula |
|------------|-----------|---------|------------|---------|
| 1.02x | 10200 | 117 BUX | 119.4 BUX | (59.7 * 20000) / 10200 |
| 1.98x | 19800 | 60 BUX | 119.4 BUX | (59.7 * 20000) / 19800 |
| 31.68x | 316800 | 4 BUX | 119.4 BUX | (59.7 * 20000) / 316800 |

### Why This Design?

**Protects against winning streaks**: A player on a hot streak at 1.02x (high win rate) can't drain the bankroll with massive bets. Each win is capped at ~119 BUX payout regardless of difficulty.

**Consistent risk exposure**: House never risks more than ~0.2% of balance per bet, regardless of multiplier chosen.

### UI Implementation

Phoenix fetches house balance from contract **asynchronously** (non-blocking) and calculates max bet client-side:

```elixir
def mount(_params, _session, socket) do
  socket =
    socket
    |> assign(house_balance: 0.0)  # Default while loading
    |> assign(max_bet: 0)  # Default while loading
    # ... other assigns
    |> start_async(:fetch_house_balance, fn ->
      fetch_house_balance_async("BUX", 1)
    end)

  {:ok, socket}
end

# Async fetch helper
defp fetch_house_balance_async(token, difficulty_level) do
  case BuxMinter.get_house_balance(token) do
    {:ok, balance} ->
      max_bet = calculate_max_bet(balance, difficulty_level, @difficulty_options)
      {balance, max_bet}

    {:error, reason} ->
      Logger.warning("Failed to fetch house balance: #{inspect(reason)}")
      {0.0, 0}
  end
end

# Async result handler
def handle_async(:fetch_house_balance, {:ok, {house_balance, max_bet}}, socket) do
  {:noreply, socket |> assign(:house_balance, house_balance) |> assign(:max_bet, max_bet)}
end

defp calculate_max_bet(house_balance, difficulty_level, difficulty_options) do
  difficulty = Enum.find(difficulty_options, &(&1.level == difficulty_level))
  multiplier_bp = trunc(difficulty.multiplier * 10000)

  base_max_bet = house_balance * 0.001
  max_bet = (base_max_bet * 20000) / multiplier_bp

  trunc(max_bet)  # Round down to integer
end
```

**Async Updates** (non-blocking):
- Page load: Fetches house balance in background via `start_async`
- Token selection: Triggers async fetch for new token
- Difficulty change: Triggers async fetch to recalculate max bet
- Play Again button: Triggers async fetch to refresh values

**Display**:
- House balance shown below token selector: "House: 59,704.26 BUX"
- Max bet on button: "MAX (60)"
- Updates dynamically when async fetch completes
- Page loads instantly without waiting for API call

**API Endpoint**: `GET /game-token-config/:token` (via BUX Minter service)

**Performance**: All house balance fetches are non-blocking via `assign_async`. UI remains responsive during API calls.

## Architecture

### Key Design Decisions

1. **Blockster is the orchestrator** - generates server seeds, stores them in Mnesia, controls game flow
2. **BUX Minter is a stateless transaction relay** - just submits transactions to the blockchain, no event listeners
3. **No event polling** - Blockster receives bet confirmation from UI and controls settlement timing
4. **Artificial delay for animation** - Settlement happens only after coin flip animation completes

### System Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ON-CHAIN GAME FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Player/UI     Blockster (LiveView)    BUX Minter      Smart Contract       │
│      │                │                    │                 │               │
│  1. Click "Play"      │                    │                 │               │
│      │───────────────>│                    │                 │               │
│      │                │                    │                 │               │
│      │  2. Generate serverSeed            │                 │               │
│      │     Store in Mnesia                │                 │               │
│      │     commitmentHash = SHA256(seed)  │                 │               │
│      │                │                    │                 │               │
│      │                │  3. POST /submit-commitment        │               │
│      │                │     {commitmentHash, player, nonce} │               │
│      │                │───────────────────>│                 │               │
│      │                │                    │                 │               │
│      │                │                    │  4. submitCommitment()         │
│      │                │                    │────────────────>│               │
│      │                │                    │                 │               │
│      │                │  5. Return txHash  │                 │               │
│      │                │<───────────────────│                 │               │
│      │                │                    │                 │               │
│      │  6. Show commitment link (Roguescan)                 │               │
│      │<───────────────│                    │                 │               │
│      │                │                    │                 │               │
│  7. Make predictions  │                    │                 │               │
│     Click "Bet"       │                    │                 │               │
│      │                │                    │                 │               │
│      │  8. placeBet() via Thirdweb Smart Wallet            │               │
│      │─────────────────────────────────────────────────────>│               │
│      │                │                    │                 │               │
│      │  9. BetPlaced event (betId)        │                 │               │
│      │<─────────────────────────────────────────────────────│               │
│      │                │                    │                 │               │
│ 10. Send "bet_placed" to LiveView        │                 │               │
│      │───────────────>│                    │                 │               │
│      │                │                    │                 │               │
│      │ 11. Calculate result locally       │                 │               │
│      │     (we have serverSeed)           │                 │               │
│      │                │                    │                 │               │
│      │ 12. Push "start_coin_flip"         │                 │               │
│      │<───────────────│                    │                 │               │
│      │                │                    │                 │               │
│ 13. Show coin flip animation (3-5 seconds)                 │               │
│      │                │                    │                 │               │
│ 14. Animation complete                   │                 │               │
│     Send "animation_complete"            │                 │               │
│      │───────────────>│                    │                 │               │
│      │                │                    │                 │               │
│      │ 15. Show win/loss to player        │                 │               │
│      │<───────────────│                    │                 │               │
│      │                │                    │                 │               │
│      │                │ 16. POST /settle-bet               │               │
│      │                │     {betId, serverSeed}             │               │
│      │                │───────────────────>│                 │               │
│      │                │                    │                 │               │
│      │                │                    │ 17. settleBet(betId, serverSeed)
│      │                │                    │────────────────>│               │
│      │                │                    │                 │               │
│      │                │                    │ 18. Get player's on-chain balance
│      │                │                    │<────────────────│               │
│      │                │                    │                 │               │
│      │                │ 19. Return {txHash, playerBalance}  │               │
│      │                │<───────────────────│                 │               │
│      │                │                    │                 │               │
│      │ 20. Update Mnesia balance          │                 │               │
│      │     Push new balance to UI         │                 │               │
│      │<───────────────│                    │                 │               │
│                                                                              │
│  ✅ Tokens are REAL blockchain assets. Settlement is trustless.             │
│     Server can only reveal committed seeds - cannot cheat.                   │
│  ✅ BUX Minter is stateless - no event listeners, just transaction relay.   │
│  ✅ Animation plays while result is already known, settlement waits.        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### BUX Minter API Endpoints

BUX Minter (`https://bux-minter.fly.dev`) is a **stateless transaction relay**. It doesn't store any game state - Blockster handles all game logic.

#### POST /submit-commitment

Submit a commitment hash to the smart contract before the player bets.

**Request:**
```json
{
  "commitmentHash": "0x...",  // SHA256(serverSeed)
  "player": "0x...",          // Player's wallet address
  "nonce": 0                  // Player's expected nonce
}
```

**Response:**
```json
{
  "success": true,
  "txHash": "0x..."
}
```

#### POST /settle-bet

Settle a bet by revealing the server seed. Called AFTER animation completes.

**Request:**
```json
{
  "betId": "0x...",           // From BetPlaced event
  "serverSeed": "0x..."       // The original server seed
}
```

**Response:**
```json
{
  "success": true,
  "txHash": "0x...",
  "playerBalance": "1000000000000000000000"  // Player's new on-chain balance (wei)
}
```

### Mnesia Storage

Server seeds are stored in Blockster's existing `:bux_booster_games` Mnesia table:

```elixir
# Mnesia record structure
{:bux_booster_games,
  game_id,           # Unique game ID
  user_id,           # Player's user ID
  server_seed,       # The secret server seed (32 bytes hex)
  server_seed_hash,  # SHA256 hash (commitment)
  nonce,             # Player's nonce at time of commitment
  status,            # :pending | :placed | :settled | :expired
  created_at,        # Timestamp
  settled_at         # Timestamp (nil until settled)
}
```

---

## Smart Contract: BuxBoosterGame.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BuxBoosterGame
 * @notice On-chain provably fair coin flip game
 * @dev UUPS Upgradeable contract using commit-reveal pattern.
 *      Supports 9 difficulty levels (-4 to 5).
 *      All dependencies flattened at bottom of file for easier verification.
 *
 * GAME RULES:
 * - Win One Mode (difficulty -4 to -1): Player wins if ANY flip matches prediction
 * - Win All Mode (difficulty 1 to 5): Player must get ALL flips correct
 * - Multipliers include house edge
 * - Max bet = 0.1% of house balance, scaled by multiplier
 *
 * UPGRADEABILITY:
 * - Uses UUPS proxy pattern (EIP-1822)
 * - Only owner can authorize upgrades
 * - State is preserved across upgrades
 */

// ============================================================
// ===================== MAIN CONTRACT ========================
// ============================================================

contract BuxBoosterGame is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // ============ Structs ============

    struct TokenConfig {
        bool enabled;
        uint256 houseBalance;
    }

    struct Bet {
        address player;
        address token;
        uint256 amount;
        int8 difficulty;       // -4 to 5
        uint8[] predictions;   // 0 = heads, 1 = tails
        bytes32 commitmentHash;
        uint256 nonce;
        uint256 timestamp;
        BetStatus status;
    }

    struct PlayerStats {
        uint256 totalBets;
        uint256 totalStaked;
        int256 overallProfitLoss;
        // Per-difficulty stats (indexed by difficulty + 4 for array access)
        uint256[9] betsPerDifficulty;      // Count of bets at each difficulty
        int256[9] profitLossPerDifficulty; // P/L at each difficulty
    }

    enum BetStatus {
        Pending,
        Won,
        Lost,
        Expired
    }

    // ============ Constants ============

    uint8 constant MODE_WIN_ALL = 0;
    uint8 constant MODE_WIN_ONE = 1;

    // Multipliers in basis points (10000 = 1x) - includes house edge
    // Index 0-3: Win One (-4 to -1), Index 4-8: Win All (1 to 5)
    uint32[9] public MULTIPLIERS = [
        10200,   // -4: 1.02x (Win One, 5 flips)
        10500,   // -3: 1.05x (Win One, 4 flips)
        11300,   // -2: 1.13x (Win One, 3 flips)
        13200,   // -1: 1.32x (Win One, 2 flips)
        19800,   // 1: 1.98x (Win All, 1 flip)
        39600,   // 2: 3.96x (Win All, 2 flips)
        79200,   // 3: 7.92x (Win All, 3 flips)
        158400,  // 4: 15.84x (Win All, 4 flips)
        316800   // 5: 31.68x (Win All, 5 flips)
    ];

    uint8[9] public FLIP_COUNTS = [5, 4, 3, 2, 1, 2, 3, 4, 5];
    uint8[9] public GAME_MODES = [
        MODE_WIN_ONE, MODE_WIN_ONE, MODE_WIN_ONE, MODE_WIN_ONE,  // -4 to -1
        MODE_WIN_ALL, MODE_WIN_ALL, MODE_WIN_ALL, MODE_WIN_ALL, MODE_WIN_ALL  // 1 to 5
    ];

    uint256 public constant BET_EXPIRY = 1 hours;
    uint256 public constant MIN_BET = 1e18; // 1 token (18 decimals)
    uint256 public constant MAX_BET_BPS = 10; // 0.1% = 10 basis points

    // ============ State Variables ============

    mapping(address => TokenConfig) public tokenConfigs;
    mapping(bytes32 => Bet) public bets;
    mapping(address => uint256) public playerNonces;
    mapping(address => bytes32[]) public playerBetHistory;
    mapping(address => PlayerStats) public playerStats;

    // Commitment tracking: commitmentHash => Commitment
    // Server submits commitment BEFORE player bets, proving the result was pre-determined
    mapping(bytes32 => Commitment) public commitments;

    // Lookup commitment by player + nonce (for UI to find unused commitments)
    // player => nonce => commitmentHash
    mapping(address => mapping(uint256 => bytes32)) public playerCommitments;

    struct Commitment {
        address player;         // Player this commitment is for
        uint256 nonce;          // Expected nonce for this bet
        uint256 timestamp;      // When commitment was made (for record-keeping)
        bool used;              // Whether this commitment has been used
        bytes32 serverSeed;     // Revealed after bet is settled (empty until then)
    }

    address public settler;
    address public treasury;

    uint256 public totalBetsPlaced;
    uint256 public totalBetsSettled;

    // ============ Events ============

    event TokenConfigured(address indexed token, bool enabled);

    event CommitmentSubmitted(
        bytes32 indexed commitmentHash,
        address indexed player,
        uint256 nonce
    );

    event BetPlaced(
        bytes32 indexed betId,
        address indexed player,
        address indexed token,
        uint256 amount,
        int8 difficulty,
        uint8[] predictions,
        bytes32 commitmentHash,
        uint256 nonce
    );

    event BetSettled(
        bytes32 indexed betId,
        address indexed player,
        bool won,
        uint8[] results,
        uint256 payout,
        bytes32 serverSeed
    );

    event BetExpired(bytes32 indexed betId, address indexed player);
    event HouseDeposit(address indexed token, uint256 amount);
    event HouseWithdraw(address indexed token, uint256 amount);

    // ============ Errors ============

    error TokenNotEnabled();
    error BetAmountTooLow();
    error BetAmountTooHigh();
    error InvalidDifficulty();
    error InvalidPredictions();
    error BetNotFound();
    error BetAlreadySettled();
    error BetExpiredError();
    error InvalidServerSeed();
    error InsufficientHouseBalance();
    error UnauthorizedSettler();
    error BetNotExpired();
    error CommitmentNotFound();
    error CommitmentAlreadyUsed();
    error CommitmentWrongPlayer();
    error CommitmentWrongNonce();

    // ============ Modifiers ============

    modifier onlySettler() {
        if (msg.sender != settler && msg.sender != owner()) {
            revert UnauthorizedSettler();
        }
        _;
    }

    // ============ Initializer (replaces constructor for upgradeable contracts) ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (called once via proxy)
     * @param _settler Address authorized to settle bets
     * @param _treasury Address to receive house withdrawals
     */
    function initialize(address _settler, address _treasury) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        settler = _settler;
        treasury = _treasury;
    }

    /**
     * @notice Required by UUPS - only owner can upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Settler Functions ============

    /**
     * @notice Submit a commitment hash BEFORE player places bet (provably fair)
     * @dev Only settler can submit commitments. This proves the server seed
     *      was determined before the player made their predictions.
     *      The commitment is stored and can be looked up by player + nonce.
     * @param commitmentHash SHA256 hash of server seed
     * @param player The player this commitment is for
     * @param nonce The expected nonce for this player's next bet
     */
    function submitCommitment(
        bytes32 commitmentHash,
        address player,
        uint256 nonce
    ) external onlySettler {
        // Store commitment (no expiry - valid until used)
        commitments[commitmentHash] = Commitment({
            player: player,
            nonce: nonce,
            timestamp: block.timestamp,
            used: false,
            serverSeed: bytes32(0)  // Empty until revealed after settlement
        });

        // Store reverse lookup so UI can find commitment by player + nonce
        playerCommitments[player][nonce] = commitmentHash;

        emit CommitmentSubmitted(commitmentHash, player, nonce);
    }

    // ============ Player Functions ============

    /**
     * @notice Place a bet with predictions using a pre-submitted commitment
     * @param token The ERC-20 token to bet with
     * @param amount The bet amount (18 decimals)
     * @param difficulty Game difficulty (-4 to -1 for Win One, 1 to 5 for Win All)
     * @param predictions Array of predictions (0=heads, 1=tails)
     * @param commitmentHash The commitment hash submitted by server BEFORE this bet
     * @return betId The unique identifier for this bet
     */
    function placeBet(
        address token,
        uint256 amount,
        int8 difficulty,
        uint8[] calldata predictions,
        bytes32 commitmentHash
    ) external nonReentrant whenNotPaused returns (bytes32 betId) {
        // Validate commitment exists and is valid for this player
        Commitment storage commitment = commitments[commitmentHash];
        if (commitment.player == address(0)) revert CommitmentNotFound();
        if (commitment.used) revert CommitmentAlreadyUsed();
        if (commitment.player != msg.sender) revert CommitmentWrongPlayer();

        // Validate nonce matches expected
        uint256 expectedNonce = playerNonces[msg.sender];
        if (commitment.nonce != expectedNonce) revert CommitmentWrongNonce();

        // Mark commitment as used (but keep it for serverSeed reveal later)
        commitment.used = true;

        // Validate token
        TokenConfig storage config = tokenConfigs[token];
        if (!config.enabled) revert TokenNotEnabled();

        // Validate amount
        if (amount < MIN_BET) revert BetAmountTooLow();

        // Validate difficulty (-4 to -1 or 1 to 5, no zero)
        if (difficulty == 0 || difficulty < -4 || difficulty > 5) revert InvalidDifficulty();

        // Get array index (difficulty + 4, skip 0 which doesn't exist)
        uint8 diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);

        // Validate predictions match difficulty
        uint8 expectedFlips = FLIP_COUNTS[diffIndex];
        if (predictions.length != expectedFlips) revert InvalidPredictions();

        // Validate prediction values (0 or 1)
        for (uint i = 0; i < predictions.length; i++) {
            if (predictions[i] > 1) revert InvalidPredictions();
        }

        // Calculate max bet based on house balance and difficulty
        uint256 maxBet = _calculateMaxBet(config.houseBalance, diffIndex);
        if (amount > maxBet) revert BetAmountTooHigh();

        // Calculate potential payout and verify house can cover
        uint256 potentialPayout = (amount * MULTIPLIERS[diffIndex]) / 10000;
        uint256 potentialProfit = potentialPayout - amount; // What house might need to pay
        if (config.houseBalance < potentialProfit) revert InsufficientHouseBalance();

        // Transfer tokens from player to contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Increment nonce
        uint256 nonce = playerNonces[msg.sender]++;
        betId = keccak256(abi.encodePacked(msg.sender, token, nonce, block.timestamp));

        // Store bet
        bets[betId] = Bet({
            player: msg.sender,
            token: token,
            amount: amount,
            difficulty: difficulty,
            predictions: predictions,
            commitmentHash: commitmentHash,
            nonce: nonce,
            timestamp: block.timestamp,
            status: BetStatus.Pending
        });

        playerBetHistory[msg.sender].push(betId);
        totalBetsPlaced++;

        emit BetPlaced(
            betId,
            msg.sender,
            token,
            amount,
            difficulty,
            predictions,
            commitmentHash,
            nonce
        );
    }

    /**
     * @notice Settle a bet by revealing the server seed
     * @param betId The bet to settle
     * @param serverSeed The revealed server seed (must hash to commitmentHash)
     */
    function settleBet(
        bytes32 betId,
        bytes32 serverSeed
    ) external onlySettler nonReentrant returns (bool won, uint8[] memory results, uint256 payout) {
        Bet storage bet = bets[betId];

        if (bet.player == address(0)) revert BetNotFound();
        if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
        if (block.timestamp > bet.timestamp + BET_EXPIRY) revert BetExpiredError();

        // Verify server seed matches commitment
        bytes32 computedHash = sha256(abi.encodePacked(serverSeed));
        if (computedHash != bet.commitmentHash) revert InvalidServerSeed();

        // Store the revealed server seed in the commitment for transparency
        commitments[bet.commitmentHash].serverSeed = serverSeed;

        // Generate client seed from bet details (deterministic, same as off-chain)
        bytes32 clientSeed = _generateClientSeed(bet);

        // Generate combined seed
        bytes32 combinedSeed = sha256(abi.encodePacked(
            serverSeed,
            ":",
            clientSeed,
            ":",
            bet.nonce
        ));

        // Generate results
        results = _generateResults(combinedSeed, bet.predictions.length);

        // Get difficulty index
        uint8 diffIndex = bet.difficulty < 0
            ? uint8(int8(4) + bet.difficulty)
            : uint8(int8(3) + bet.difficulty);

        // Determine if player won
        won = _checkWin(bet.predictions, results, GAME_MODES[diffIndex]);

        // Calculate payout (includes original bet)
        TokenConfig storage config = tokenConfigs[bet.token];
        PlayerStats storage stats = playerStats[bet.player];

        // Update player stats
        stats.totalBets++;
        stats.totalStaked += bet.amount;
        stats.betsPerDifficulty[diffIndex]++;

        if (won) {
            // Payout INCLUDES original bet - don't add it separately
            payout = (bet.amount * MULTIPLIERS[diffIndex]) / 10000;
            bet.status = BetStatus.Won;

            // House pays the profit (payout minus original bet)
            uint256 profit = payout - bet.amount;
            config.houseBalance -= profit;

            // Update player stats
            int256 playerProfit = int256(payout) - int256(bet.amount);
            stats.overallProfitLoss += playerProfit;
            stats.profitLossPerDifficulty[diffIndex] += playerProfit;

            // Transfer full payout to player
            IERC20(bet.token).safeTransfer(bet.player, payout);
        } else {
            payout = 0;
            bet.status = BetStatus.Lost;

            // House keeps the bet
            config.houseBalance += bet.amount;

            // Update player stats (loss)
            stats.overallProfitLoss -= int256(bet.amount);
            stats.profitLossPerDifficulty[diffIndex] -= int256(bet.amount);
        }

        totalBetsSettled++;

        emit BetSettled(
            betId,
            bet.player,
            won,
            results,
            payout,
            serverSeed
        );
    }

    // ============ View Functions ============

    /**
     * @notice Get bet details
     */
    function getBet(bytes32 betId) external view returns (
        address player,
        address token,
        uint256 amount,
        int8 difficulty,
        uint8[] memory predictions,
        bytes32 commitmentHash,
        uint256 nonce,
        uint256 timestamp,
        BetStatus status
    ) {
        Bet storage bet = bets[betId];
        return (
            bet.player,
            bet.token,
            bet.amount,
            bet.difficulty,
            bet.predictions,
            bet.commitmentHash,
            bet.nonce,
            bet.timestamp,
            bet.status
        );
    }

    /**
     * @notice Get player statistics
     */
    function getPlayerStats(address player) external view returns (
        uint256 totalBets,
        uint256 totalStaked,
        int256 overallProfitLoss,
        uint256[9] memory betsPerDifficulty,
        int256[9] memory profitLossPerDifficulty
    ) {
        PlayerStats storage stats = playerStats[player];
        return (
            stats.totalBets,
            stats.totalStaked,
            stats.overallProfitLoss,
            stats.betsPerDifficulty,
            stats.profitLossPerDifficulty
        );
    }

    /**
     * @notice Calculate max bet for a given token and difficulty
     */
    function getMaxBet(address token, int8 difficulty) external view returns (uint256) {
        if (difficulty == 0 || difficulty < -4 || difficulty > 5) return 0;
        uint8 diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);
        return _calculateMaxBet(tokenConfigs[token].houseBalance, diffIndex);
    }

    /**
     * @notice Calculate potential payout for a bet
     */
    function calculatePotentialPayout(uint256 amount, int8 difficulty) external view returns (uint256) {
        if (difficulty == 0 || difficulty < -4 || difficulty > 5) return 0;
        uint8 diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);
        return (amount * MULTIPLIERS[diffIndex]) / 10000;
    }

    /**
     * @notice Get player's bet history
     */
    function getPlayerBetHistory(address player, uint256 offset, uint256 limit)
        external view returns (bytes32[] memory)
    {
        bytes32[] storage history = playerBetHistory[player];
        uint256 total = history.length;

        if (offset >= total) return new bytes32[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        bytes32[] memory result = new bytes32[](end - offset);
        for (uint i = offset; i < end; i++) {
            result[i - offset] = history[i];
        }
        return result;
    }

    /**
     * @notice Get a player's current (unused) commitment for their next bet
     * @dev UI can link to Roguescan to show the commitment was on-chain before bet
     * @param player The player's address
     * @return commitmentHash The commitment hash (bytes32(0) if none exists)
     * @return nonce The nonce this commitment is for
     * @return timestamp When the commitment was submitted
     * @return used Whether the commitment has been used
     */
    function getPlayerCurrentCommitment(address player) external view returns (
        bytes32 commitmentHash,
        uint256 nonce,
        uint256 timestamp,
        bool used
    ) {
        nonce = playerNonces[player];
        commitmentHash = playerCommitments[player][nonce];

        if (commitmentHash != bytes32(0)) {
            Commitment storage c = commitments[commitmentHash];
            return (commitmentHash, c.nonce, c.timestamp, c.used);
        }
        return (bytes32(0), nonce, 0, false);
    }

    /**
     * @notice Get a commitment by player and nonce
     * @dev Useful for looking up past commitments and their revealed server seeds
     * @param player The player's address
     * @param nonce The nonce to look up
     * @return commitmentHash The commitment hash
     * @return commitmentTimestamp When commitment was submitted
     * @return used Whether the commitment was used
     * @return serverSeed The revealed server seed (empty if not yet settled)
     */
    function getCommitmentByNonce(address player, uint256 nonce) external view returns (
        bytes32 commitmentHash,
        uint256 commitmentTimestamp,
        bool used,
        bytes32 serverSeed
    ) {
        commitmentHash = playerCommitments[player][nonce];

        if (commitmentHash != bytes32(0)) {
            Commitment storage c = commitments[commitmentHash];
            return (commitmentHash, c.timestamp, c.used, c.serverSeed);
        }
        return (bytes32(0), 0, false, bytes32(0));
    }

    /**
     * @notice Get full commitment details by hash
     * @param commitmentHash The commitment hash to look up
     * @return player The player this commitment is for
     * @return nonce The nonce
     * @return timestamp When commitment was submitted
     * @return used Whether it has been used
     * @return serverSeed The revealed server seed (empty if not yet settled)
     */
    function getCommitment(bytes32 commitmentHash) external view returns (
        address player,
        uint256 nonce,
        uint256 timestamp,
        bool used,
        bytes32 serverSeed
    ) {
        Commitment storage c = commitments[commitmentHash];
        return (c.player, c.nonce, c.timestamp, c.used, c.serverSeed);
    }

    // ============ Admin Functions ============

    /**
     * @notice Configure a token for betting
     */
    function configureToken(address token, bool enabled) external onlyOwner {
        tokenConfigs[token].enabled = enabled;
        emit TokenConfigured(token, enabled);
    }

    /**
     * @notice Deposit tokens as house balance
     */
    function depositHouseBalance(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        tokenConfigs[token].houseBalance += amount;
        emit HouseDeposit(token, amount);
    }

    /**
     * @notice Withdraw house balance to treasury
     */
    function withdrawHouseBalance(address token, uint256 amount) external onlyOwner {
        TokenConfig storage config = tokenConfigs[token];
        require(amount <= config.houseBalance, "Insufficient balance");
        config.houseBalance -= amount;
        IERC20(token).safeTransfer(treasury, amount);
        emit HouseWithdraw(token, amount);
    }

    /**
     * @notice Update settler address
     */
    function setSettler(address _settler) external onlyOwner {
        settler = _settler;
    }

    /**
     * @notice Update treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /**
     * @notice Pause/unpause the contract
     */
    function setPaused(bool _paused) external onlyOwner {
        if (_paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @notice Handle expired bets - refund to player
     */
    function refundExpiredBet(bytes32 betId) external {
        Bet storage bet = bets[betId];

        if (bet.player == address(0)) revert BetNotFound();
        if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
        if (block.timestamp <= bet.timestamp + BET_EXPIRY) revert BetNotExpired();

        bet.status = BetStatus.Expired;
        IERC20(bet.token).safeTransfer(bet.player, bet.amount);
        emit BetExpired(betId, bet.player);
    }

    // ============ Internal Functions ============

    /**
     * @notice Calculate max bet based on house balance and difficulty
     * @dev Max bet at difficulty 1 (2x) is 0.1% of house balance
     *      Other difficulties extrapolated so max payout is always ~0.1%
     */
    function _calculateMaxBet(uint256 houseBalance, uint8 diffIndex) internal view returns (uint256) {
        if (houseBalance == 0) return 0;

        // Base: 0.1% of house balance for 2x multiplier
        // For other multipliers, scale inversely with multiplier
        uint256 baseMaxBet = (houseBalance * MAX_BET_BPS) / 10000; // 0.1%
        uint256 multiplier = MULTIPLIERS[diffIndex];

        // Scale: maxBet = baseMaxBet * 20000 / multiplier
        // This ensures max potential payout is consistent across difficulties
        return (baseMaxBet * 20000) / multiplier;
    }

    /**
     * @notice Generate client seed from bet details (same as off-chain)
     */
    function _generateClientSeed(Bet storage bet) internal view returns (bytes32) {
        bytes memory predictionsStr;
        for (uint i = 0; i < bet.predictions.length; i++) {
            if (i > 0) {
                predictionsStr = abi.encodePacked(predictionsStr, ",");
            }
            predictionsStr = abi.encodePacked(
                predictionsStr,
                bet.predictions[i] == 0 ? "heads" : "tails"
            );
        }

        bytes memory input = abi.encodePacked(
            _addressToString(bet.player),
            ":",
            _uint256ToString(bet.amount),
            ":",
            _addressToString(bet.token),
            ":",
            _int8ToString(bet.difficulty),
            ":",
            predictionsStr
        );

        return sha256(input);
    }

    /**
     * @notice Generate flip results from combined seed
     */
    function _generateResults(bytes32 combinedSeed, uint256 numFlips) internal pure returns (uint8[] memory) {
        uint8[] memory results = new uint8[](numFlips);
        for (uint i = 0; i < numFlips; i++) {
            uint8 byteValue = uint8(combinedSeed[i]);
            results[i] = byteValue < 128 ? 0 : 1;
        }
        return results;
    }

    /**
     * @notice Check if player won
     */
    function _checkWin(uint8[] storage predictions, uint8[] memory results, uint8 mode) internal view returns (bool) {
        if (mode == MODE_WIN_ONE) {
            for (uint i = 0; i < predictions.length; i++) {
                if (predictions[i] == results[i]) return true;
            }
            return false;
        } else {
            for (uint i = 0; i < predictions.length; i++) {
                if (predictions[i] != results[i]) return false;
            }
            return true;
        }
    }

    function _addressToString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint(uint8(bytes20(addr)[i] >> 4))];
            str[3 + i * 2] = alphabet[uint(uint8(bytes20(addr)[i] & 0x0f))];
        }
        return string(str);
    }

    function _uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _int8ToString(int8 value) internal pure returns (string memory) {
        if (value < 0) {
            return string(abi.encodePacked("-", _uint256ToString(uint256(uint8(-value)))));
        }
        return _uint256ToString(uint256(uint8(value)));
    }
}

// ============================================================
// =============== FLATTENED DEPENDENCIES =====================
// ============================================================
// The following interfaces and base contracts are included
// directly for easier verification on block explorers.
// Uses UPGRADEABLE versions for proxy compatibility.
// ============================================================

// ============ IERC20 Interface ============

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// ============ SafeERC20 Library ============

library SafeERC20 {
    error SafeERC20FailedOperation(address token);

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        if (!success || (returndata.length != 0 && !abi.decode(returndata, (bool)))) {
            revert SafeERC20FailedOperation(address(token));
        }
    }
}

// ============ Initializable (for upgradeable contracts) ============

abstract contract Initializable {
    uint64 private _initialized;
    bool private _initializing;

    error InvalidInitialization();
    error NotInitializing();

    event Initialized(uint64 version);

    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        uint64 initialized = _initialized;

        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    modifier reinitializer(uint64 version) {
        if (_initializing || _initialized >= version) {
            revert InvalidInitialization();
        }
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    modifier onlyInitializing() {
        if (!_initializing) {
            revert NotInitializing();
        }
        _;
    }

    function _disableInitializers() internal virtual {
        if (_initializing) {
            revert InvalidInitialization();
        }
        if (_initialized != type(uint64).max) {
            _initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    function _getInitializedVersion() internal view returns (uint64) {
        return _initialized;
    }

    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }
}

// ============ ContextUpgradeable ============

abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {}
    function __Context_init_unchained() internal onlyInitializing {}

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// ============ OwnableUpgradeable ============

abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    function __Ownable_init(address initialOwner) internal onlyInitializing {
        __Ownable_init_unchained(initialOwner);
    }

    function __Ownable_init_unchained(address initialOwner) internal onlyInitializing {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// ============ ReentrancyGuardUpgradeable ============

abstract contract ReentrancyGuardUpgradeable is Initializable {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    error ReentrancyGuardReentrantCall();

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = NOT_ENTERED;
    }
}

// ============ PausableUpgradeable ============

abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    error EnforcedPause();
    error ExpectedPause();

    function __Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal onlyInitializing {
        _paused = false;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// ============ ERC1967Utils (for UUPS) ============

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ERC1967InvalidImplementation(address implementation);

    function getImplementation() internal view returns (address) {
        return address(uint160(uint256(_getSlot(IMPLEMENTATION_SLOT))));
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        if (data.length > 0) {
            (bool success,) = newImplementation.delegatecall(data);
            require(success, "upgrade call failed");
        }
    }

    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(newImplementation);
        }
        assembly {
            sstore(IMPLEMENTATION_SLOT, newImplementation)
        }
    }

    function _getSlot(bytes32 slot) private view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }
}

// ============ UUPSUpgradeable ============

abstract contract UUPSUpgradeable is Initializable {
    address private immutable __self = address(this);

    error UUPSUnauthorizedCallContext();
    error UUPSUnsupportedProxiableUUID(bytes32 slot);

    modifier onlyProxy() {
        if (address(this) == __self) {
            revert UUPSUnauthorizedCallContext();
        }
        _;
    }

    modifier notDelegated() {
        if (address(this) != __self) {
            revert UUPSUnauthorizedCallContext();
        }
        _;
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {}
    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {}

    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;
}
```

---

## Hardhat Configuration

### hardhat.config.js

```javascript
require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    rogueMainnet: {
      url: "https://rpc.roguechain.io/rpc",
      chainId: 560013,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY]
    }
  }
};
```

### package.json dependencies

```json
{
  "devDependencies": {
    "@nomicfoundation/hardhat-toolbox": "^4.0.0",
    "@openzeppelin/hardhat-upgrades": "^3.0.0",
    "hardhat": "^2.19.0",
    "dotenv": "^16.3.0"
  }
}
```

### Deploy Script (scripts/deploy.js)

```javascript
const { ethers, upgrades } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // TODO: Get these from user
  const settlerAddress = "SETTLER_ADDRESS_HERE";
  const treasuryAddress = "TREASURY_ADDRESS_HERE";

  // Deploy as UUPS upgradeable proxy
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  const game = await upgrades.deployProxy(
    BuxBoosterGame,
    [settlerAddress, treasuryAddress],  // initialize() arguments
    { kind: "uups" }
  );
  await game.waitForDeployment();

  const proxyAddress = await game.getAddress();
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);

  console.log("BuxBoosterGame Proxy deployed to:", proxyAddress);
  console.log("Implementation deployed to:", implementationAddress);

  // Configure tokens
  const tokens = [
    { name: "BUX", address: "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8" },
    { name: "moonBUX", address: "0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5" },
    { name: "neoBUX", address: "0x423656448374003C2cfEaFF88D5F64fb3A76487C" },
    { name: "rogueBUX", address: "0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3" },
    { name: "flareBUX", address: "0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8" },
    { name: "nftBUX", address: "0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED" },
    { name: "nolchaBUX", address: "0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642" },
    { name: "solBUX", address: "0x92434779E281468611237d18AdE20A4f7F29DB38" },
    { name: "spaceBUX", address: "0xAcaCa77FbC674728088f41f6d978F0194cf3d55A" },
    { name: "tronBUX", address: "0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665" },
    { name: "tranBUX", address: "0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96" }
  ];

  for (const token of tokens) {
    const tx = await game.configureToken(token.address, true);
    await tx.wait();
    console.log(`Configured ${token.name}`);
  }

  console.log("\n=== Deployment Complete ===");
  console.log("Proxy Address (use this):", proxyAddress);
  console.log("Implementation Address:", implementationAddress);
  console.log("Settler:", settlerAddress);
  console.log("Treasury:", treasuryAddress);
  console.log("\nSave these addresses! The Proxy Address is what users interact with.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

### Upgrade Script (scripts/upgrade.js)

```javascript
const { ethers, upgrades } = require("hardhat");

async function main() {
  // The proxy address from initial deployment
  const PROXY_ADDRESS = "0x..."; // Fill in after initial deploy

  console.log("Upgrading BuxBoosterGame...");

  const BuxBoosterGameV2 = await ethers.getContractFactory("BuxBoosterGame");
  const upgraded = await upgrades.upgradeProxy(PROXY_ADDRESS, BuxBoosterGameV2, {
    kind: "uups"
  });

  const newImplementation = await upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);

  console.log("Upgrade complete!");
  console.log("Proxy Address (unchanged):", PROXY_ADDRESS);
  console.log("New Implementation Address:", newImplementation);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

---

## Backend Integration

### BuxBoosterOnchain Module (Blockster)

This module orchestrates the on-chain game flow. Blockster generates server seeds, stores them in Mnesia, and calls BUX Minter to submit transactions.

```elixir
# lib/blockster_v2/bux_booster_onchain.ex
defmodule BlocksterV2.BuxBoosterOnchain do
  @moduledoc """
  On-chain BUX Booster game orchestration.

  Blockster is the orchestrator:
  - Generates server seeds
  - Stores seeds in Mnesia
  - Calls BUX Minter to submit/settle transactions
  - Controls game flow and timing

  BUX Minter is a stateless transaction relay.
  """

  alias BlocksterV2.{ProvablyFair, EngagementTracker}
  require Logger

  @bux_minter_url "https://bux-minter.fly.dev"
  @contract_address "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B"

  # Token contract addresses
  @token_addresses %{
    "BUX" => "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8",
    "moonBUX" => "0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5",
    "neoBUX" => "0x423656448374003C2cfEaFF88D5F64fb3A76487C",
    "rogueBUX" => "0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3",
    "flareBUX" => "0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8",
    "nftBUX" => "0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED",
    "nolchaBUX" => "0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642",
    "solBUX" => "0x92434779E281468611237d18AdE20A4f7F29DB38",
    "spaceBUX" => "0xAcaCa77FbC674728088f41f6d978F0194cf3d55A",
    "tronBUX" => "0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665",
    "tranBUX" => "0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96"
  }

  @doc """
  Initialize a new game session.
  Generates server seed, stores in Mnesia, submits commitment to chain.

  Returns {:ok, %{game_id, commitment_hash, commitment_tx}} or {:error, reason}
  """
  def init_game(user_id, wallet_address) do
    # 1. Generate server seed
    server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    commitment_hash = :crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower)
    commitment_hash = "0x" <> commitment_hash

    # 2. Get player's current nonce from contract (or track locally)
    nonce = get_player_nonce(wallet_address)

    # 3. Store in Mnesia
    game_id = generate_game_id()
    now = System.system_time(:second)

    :mnesia.transaction(fn ->
      :mnesia.write({:bux_booster_games, game_id, user_id, server_seed, commitment_hash,
                     nonce, :pending, now, nil})
    end)

    # 4. Call BUX Minter to submit commitment
    case submit_commitment(commitment_hash, wallet_address, nonce) do
      {:ok, tx_hash} ->
        Logger.info("[BuxBoosterOnchain] Commitment submitted: #{tx_hash}")
        {:ok, %{
          game_id: game_id,
          commitment_hash: commitment_hash,
          commitment_tx: tx_hash,
          nonce: nonce
        }}

      {:error, reason} ->
        # Clean up Mnesia record
        :mnesia.transaction(fn -> :mnesia.delete({:bux_booster_games, game_id}) end)
        {:error, reason}
    end
  end

  @doc """
  Calculate game result locally (we have the server seed).
  Called when UI sends "bet_placed" event.

  Returns the results without settling on-chain yet (animation plays first).
  """
  def calculate_result(game_id, predictions, bet_amount, token, difficulty) do
    case get_game(game_id) do
      {:ok, game} ->
        # Generate client seed from bet details (deterministic)
        client_seed = generate_client_seed(game.wallet_address, bet_amount, token, difficulty, predictions)

        # Combined seed
        combined = :crypto.hash(:sha256, game.server_seed <> ":" <> client_seed <> ":" <> Integer.to_string(game.nonce))

        # Generate results
        results = generate_flip_results(combined, length(predictions))

        # Determine win/loss
        won = check_win(predictions, results, difficulty)

        # Calculate payout
        payout = if won, do: calculate_payout(bet_amount, difficulty), else: 0

        {:ok, %{
          results: results,
          won: won,
          payout: payout,
          server_seed: game.server_seed
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Settle the bet on-chain after animation completes.
  Calls BUX Minter to submit settleBet transaction.

  Returns {:ok, %{tx_hash, player_balance}} or {:error, reason}
  """
  def settle_game(game_id, bet_id) do
    case get_game(game_id) do
      {:ok, game} ->
        # Call BUX Minter to settle
        case settle_bet(bet_id, game.server_seed) do
          {:ok, tx_hash, player_balance} ->
            # Update Mnesia record
            now = System.system_time(:second)
            :mnesia.transaction(fn ->
              :mnesia.write({:bux_booster_games, game_id, game.user_id, game.server_seed,
                             game.commitment_hash, game.nonce, :settled, game.created_at, now})
            end)

            {:ok, %{tx_hash: tx_hash, player_balance: player_balance}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sync player's on-chain balance to Mnesia.
  """
  def sync_balance(user_id, token, wallet_address) do
    token_address = Map.get(@token_addresses, token)

    case get_token_balance(token_address, wallet_address) do
      {:ok, balance_wei} ->
        # Convert from wei to integer tokens
        balance = div(balance_wei, 1_000_000_000_000_000_000)
        EngagementTracker.set_token_balance(user_id, token, balance)
        {:ok, balance}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============ BUX Minter API Calls ============

  defp submit_commitment(commitment_hash, player, nonce) do
    body = Jason.encode!(%{
      "commitmentHash" => commitment_hash,
      "player" => player,
      "nonce" => nonce
    })

    case HTTPoison.post("#{@bux_minter_url}/submit-commitment", body, [{"Content-Type", "application/json"}]) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode!(resp_body) do
          %{"success" => true, "txHash" => tx_hash} -> {:ok, tx_hash}
          %{"error" => error} -> {:error, error}
        end

      {:ok, %{status_code: code, body: body}} ->
        {:error, "HTTP #{code}: #{body}"}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  defp settle_bet(bet_id, server_seed) do
    body = Jason.encode!(%{
      "betId" => bet_id,
      "serverSeed" => "0x" <> server_seed
    })

    case HTTPoison.post("#{@bux_minter_url}/settle-bet", body, [{"Content-Type", "application/json"}]) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode!(resp_body) do
          %{"success" => true, "txHash" => tx_hash, "playerBalance" => balance} ->
            {:ok, tx_hash, String.to_integer(balance)}
          %{"error" => error} ->
            {:error, error}
        end

      {:ok, %{status_code: code, body: body}} ->
        {:error, "HTTP #{code}: #{body}"}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  defp get_token_balance(token_address, wallet_address) do
    # Call RPC directly or through BUX Minter
    # For now, assume BUX Minter returns balance in settle response
    {:ok, 0}
  end

  # ============ Helper Functions ============

  defp get_game(game_id) do
    case :mnesia.transaction(fn -> :mnesia.read({:bux_booster_games, game_id}) end) do
      {:atomic, [{:bux_booster_games, ^game_id, user_id, server_seed, commitment_hash, nonce, status, created_at, settled_at}]} ->
        {:ok, %{
          game_id: game_id,
          user_id: user_id,
          server_seed: server_seed,
          commitment_hash: commitment_hash,
          nonce: nonce,
          status: status,
          created_at: created_at,
          settled_at: settled_at
        }}

      {:atomic, []} ->
        {:error, :not_found}
    end
  end

  defp get_player_nonce(_wallet_address) do
    # TODO: Read from contract or track locally
    0
  end

  defp generate_game_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp generate_client_seed(wallet, amount, token, difficulty, predictions) do
    predictions_str = Enum.map(predictions, fn
      :heads -> "heads"
      :tails -> "tails"
    end) |> Enum.join(",")

    input = "#{wallet}:#{amount}:#{token}:#{difficulty}:#{predictions_str}"
    :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)
  end

  defp generate_flip_results(combined_seed, num_flips) do
    for i <- 0..(num_flips - 1) do
      byte = :binary.at(combined_seed, i)
      if byte < 128, do: :heads, else: :tails
    end
  end

  defp check_win(predictions, results, difficulty) when difficulty < 0 do
    # Win One mode: any match wins
    Enum.zip(predictions, results)
    |> Enum.any?(fn {pred, result} -> pred == result end)
  end

  defp check_win(predictions, results, _difficulty) do
    # Win All mode: all must match
    predictions == results
  end

  defp calculate_payout(bet_amount, difficulty) do
    multiplier = get_multiplier(difficulty)
    trunc(bet_amount * multiplier / 10000)
  end

  defp get_multiplier(difficulty) do
    case difficulty do
      -4 -> 10200
      -3 -> 10500
      -2 -> 11300
      -1 -> 13200
      1 -> 19800
      2 -> 39600
      3 -> 79200
      4 -> 158400
      5 -> 316800
    end
  end

  def contract_address, do: @contract_address
  def token_address(token), do: Map.get(@token_addresses, token)
end
```

### Updated LiveView Integration

```elixir
# lib/blockster_v2_web/live/bux_booster_live.ex (key changes for on-chain mode)

defmodule BlocksterV2Web.BuxBoosterLive do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.{BuxBoosterOnchain, EngagementTracker}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    wallet_address = user.smart_wallet_address

    # Initialize game session (generates seed, submits commitment)
    case BuxBoosterOnchain.init_game(user.id, wallet_address) do
      {:ok, game_session} ->
        {:ok,
         socket
         |> assign(game_id: game_session.game_id)
         |> assign(commitment_hash: game_session.commitment_hash)
         |> assign(commitment_tx: game_session.commitment_tx)
         |> assign(nonce: game_session.nonce)
         |> assign(game_state: :ready)
         |> assign(game_mode: :on_chain)}

      {:error, reason} ->
        {:ok,
         socket
         |> assign(game_state: :error)
         |> put_flash(:error, "Failed to initialize game: #{inspect(reason)}")}
    end
  end

  @doc """
  Player clicks "Bet" - push transaction data to frontend.
  Frontend will call placeBet() via Thirdweb smart wallet.
  """
  def handle_event("place_bet", _params, socket) do
    %{
      bet_amount: bet_amount,
      selected_token: token,
      selected_difficulty: difficulty,
      predictions: predictions,
      commitment_hash: commitment_hash
    } = socket.assigns

    # Convert predictions to contract format (0 = heads, 1 = tails)
    contract_predictions = Enum.map(predictions, fn
      :heads -> 0
      :tails -> 1
    end)

    token_address = BuxBoosterOnchain.token_address(token)
    amount_wei = bet_amount * 1_000_000_000_000_000_000

    # Build transaction data for frontend
    tx_data = %{
      contract: BuxBoosterOnchain.contract_address(),
      method: "placeBet",
      args: [token_address, amount_wei, difficulty, contract_predictions, commitment_hash],
      approval: %{
        token: token_address,
        spender: BuxBoosterOnchain.contract_address(),
        amount: "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      }
    }

    {:noreply,
     socket
     |> assign(game_state: :awaiting_tx)
     |> push_event("request_bet_transaction", tx_data)}
  end

  @doc """
  Bet placed on-chain - calculate result and start animation.
  Settlement waits until animation completes.
  """
  def handle_event("bet_placed", %{"tx_hash" => tx_hash, "bet_id" => bet_id}, socket) do
    %{
      game_id: game_id,
      predictions: predictions,
      bet_amount: bet_amount,
      selected_token: token,
      selected_difficulty: difficulty
    } = socket.assigns

    # Calculate result locally (we have the server seed in Mnesia)
    case BuxBoosterOnchain.calculate_result(game_id, predictions, bet_amount, token, difficulty) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(bet_tx: tx_hash)
         |> assign(bet_id: bet_id)
         |> assign(calculated_results: result.results)
         |> assign(calculated_won: result.won)
         |> assign(calculated_payout: result.payout)
         |> assign(game_state: :animating)
         |> push_event("start_coin_flip", %{results: result.results})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(game_state: :error)
         |> put_flash(:error, "Failed to calculate result: #{inspect(reason)}")}
    end
  end

  @doc """
  Animation complete - show result and settle on-chain.
  """
  def handle_event("animation_complete", _params, socket) do
    %{
      game_id: game_id,
      bet_id: bet_id,
      calculated_results: results,
      calculated_won: won,
      calculated_payout: payout,
      current_user: user,
      selected_token: token
    } = socket.assigns

    # Show result to player immediately
    socket = socket
    |> assign(results: results)
    |> assign(won: won)
    |> assign(payout: payout)
    |> assign(game_state: :result)

    # Settle on-chain in background (player already sees result)
    Task.start(fn ->
      case BuxBoosterOnchain.settle_game(game_id, bet_id) do
        {:ok, %{tx_hash: settle_tx, player_balance: balance_wei}} ->
          # Update Mnesia balance
          balance = div(balance_wei, 1_000_000_000_000_000_000)
          EngagementTracker.set_token_balance(user.id, token, balance)

          # Send settlement confirmation to LiveView
          send(self(), {:settlement_complete, settle_tx, balance})

        {:error, reason} ->
          send(self(), {:settlement_failed, reason})
      end
    end)

    {:noreply, socket}
  end

  @doc """
  Settlement completed - update UI with tx hash and new balance.
  """
  def handle_info({:settlement_complete, settle_tx, balance}, socket) do
    {:noreply,
     socket
     |> assign(settlement_tx: settle_tx)
     |> assign(token_balance: balance)
     |> push_event("balance_updated", %{balance: balance})
     |> init_new_game()}
  end

  def handle_info({:settlement_failed, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Settlement failed: #{inspect(reason)}")}
  end

  defp init_new_game(socket) do
    user = socket.assigns.current_user

    case BuxBoosterOnchain.init_game(user.id, user.smart_wallet_address) do
      {:ok, game_session} ->
        socket
        |> assign(game_id: game_session.game_id)
        |> assign(commitment_hash: game_session.commitment_hash)
        |> assign(commitment_tx: game_session.commitment_tx)
        |> assign(nonce: game_session.nonce)

      {:error, _reason} ->
        socket
    end
  end
end
```

---

## Frontend Integration

### JavaScript Hook for Transactions

```javascript
// assets/js/bux_booster_onchain.js
import { prepareContractCall, sendTransaction, readContract } from "thirdweb";

const BUX_BOOSTER_ABI = [
  // placeBet function
  {
    name: "placeBet",
    type: "function",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "difficulty", type: "int8" },
      { name: "predictions", type: "uint8[]" },
      { name: "commitmentHash", type: "bytes32" }
    ],
    outputs: [{ name: "betId", type: "bytes32" }]
  }
];

const ERC20_ABI = [
  {
    name: "approve",
    type: "function",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" }
    ],
    outputs: [{ type: "bool" }]
  },
  {
    name: "allowance",
    type: "function",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" }
    ],
    outputs: [{ type: "uint256" }]
  }
];

export const BuxBoosterOnchain = {
  mounted() {
    this.handleEvent("request_bet_transaction", async (data) => {
      try {
        // Check if approval is needed (first time only)
        const needsApproval = await this.checkNeedsApproval(data.approval);

        if (needsApproval) {
          // Approve max amount so we never need to approve again
          await this.approveToken(data.approval);
        }

        // Place the bet
        const { txHash, betId } = await this.placeBet(data);

        // Display tx hash in UI
        this.el.querySelector('.bet-tx-hash').textContent = txHash;

        // Notify server of successful bet placement
        this.pushEvent("bet_placed", { tx_hash: txHash, bet_id: betId });

      } catch (error) {
        console.error("Transaction failed:", error);
        this.pushEvent("transaction_failed", { error: error.message });
      }
    });

    this.handleEvent("balance_updated", async () => {
      // Refresh balance display
      await this.updateBalanceDisplay();
    });
  },

  async checkNeedsApproval({ token, spender }) {
    const allowance = await readContract({
      contract: { address: token, abi: ERC20_ABI },
      method: "allowance",
      params: [window.thirdwebAccount.address, spender]
    });

    // If allowance is very large, we don't need to approve again
    return allowance < BigInt("0xffffffffffffffffffffffffffff");
  },

  async approveToken({ token, spender, amount }) {
    const tx = prepareContractCall({
      contract: { address: token, abi: ERC20_ABI },
      method: "approve",
      params: [spender, amount]
    });

    const result = await sendTransaction({
      transaction: tx,
      account: window.thirdwebAccount
    });

    // Wait for confirmation
    await result.wait();
  },

  async placeBet(data) {
    const tx = prepareContractCall({
      contract: { address: data.contract, abi: BUX_BOOSTER_ABI },
      method: "placeBet",
      params: data.args
    });

    const result = await sendTransaction({
      transaction: tx,
      account: window.thirdwebAccount
    });

    // Wait for confirmation and get receipt
    const receipt = await result.wait();

    // Extract betId from BetPlaced event
    const betPlacedEvent = receipt.logs.find(log =>
      log.topics[0] === "0x..." // BetPlaced event signature
    );

    const betId = betPlacedEvent.topics[1];

    return { txHash: receipt.transactionHash, betId };
  },

  async updateBalanceDisplay() {
    // This will be called by LiveView to refresh the balance
    // The actual balance comes from the server after syncing with chain
  }
};
```

### UI Updates for Transaction Hashes

```heex
<!-- In result state, show transaction hashes -->
<%= if @game_state == :result do %>
  <div class="space-y-2 mt-4">
    <div class="flex items-center justify-between text-sm">
      <span class="text-gray-500">Bet TX:</span>
      <a href={"https://roguescan.io/tx/#{@pending_tx}"}
         target="_blank"
         class="text-purple-600 hover:underline font-mono text-xs cursor-pointer">
        <%= String.slice(@pending_tx || "", 0, 10) %>...<%= String.slice(@pending_tx || "", -8, 8) %>
      </a>
    </div>
    <div class="flex items-center justify-between text-sm">
      <span class="text-gray-500">Settlement TX:</span>
      <a href={"https://roguescan.io/tx/#{@settlement_tx}"}
         target="_blank"
         class="text-purple-600 hover:underline font-mono text-xs cursor-pointer">
        <%= String.slice(@settlement_tx || "", 0, 10) %>...<%= String.slice(@settlement_tx || "", -8, 8) %>
      </a>
    </div>
  </div>
<% end %>
```

### Coin Flip Animation System

**Updated: December 2024 - 3 Second Duration with Gradual Deceleration**

The BUX Booster coin flip animation system creates a smooth, realistic coin flipping experience with gradual deceleration. The animation uses a 3 second duration with carefully tuned keyframes to create a natural slowdown effect.

#### Animation Architecture

**Multi-Flip Optimization**:
- **First flip**: Uses continuous spinning animation while waiting for bet confirmation on-chain
- **Subsequent flips** (2-5 flips for multi-flip difficulties): Go straight to reveal animation since the result is already known

This optimization significantly improves perceived performance for multi-flip games (Win One and Win All modes with 2-5 predictions).

#### CSS Animation Mechanics

**File**: `assets/css/app.css` (lines 874-929)

The animation uses CSS `@keyframes` with percentage-based timing for smooth deceleration:

```css
/* Continuous spin while waiting for bet confirmation (first flip only) */
@keyframes flip-continuous {
  from { transform: rotateY(0deg); }
  to { transform: rotateY(2520deg); }  /* 7 full rotations */
}

.animate-flip-continuous {
  animation: flip-continuous 3s linear infinite;
}

/* Final reveal animations (3 seconds) */
@keyframes flip-to-heads {
  0%   { transform: rotateY(0deg); }       /* Start position */
  50%  { transform: rotateY(1260deg); }   /* Fast spin: 840°/sec */
  75%  { transform: rotateY(1620deg); }   /* Slowing down: 480°/sec */
  85%  { transform: rotateY(1800deg); }   /* Slower: 600°/sec */
  95%  { transform: rotateY(1890deg); }   /* Very slow: 300°/sec */
  100% { transform: rotateY(1980deg); }   /* Land on heads: 600°/sec */
}

@keyframes flip-to-tails {
  0%   { transform: rotateY(0deg); }
  50%  { transform: rotateY(1260deg); }   /* Fast spin: 840°/sec */
  75%  { transform: rotateY(1620deg); }   /* Slowing down: 480°/sec */
  85%  { transform: rotateY(1890deg); }   /* Slower: 900°/sec */
  95%  { transform: rotateY(2070deg); }   /* Very slow: 600°/sec */
  100% { transform: rotateY(2160deg); }   /* Land on tails: 600°/sec */
}

.animate-flip-heads {
  animation: flip-to-heads 3s linear forwards;
}

.animate-flip-tails {
  animation: flip-to-tails 3s linear forwards;
}
```

#### Landing Face Mathematics

**Critical**: The final rotation degree determines which face shows:
- **Heads**: Odd multiples of 180° (e.g., 180°, 540°, 900°, 1260°, **1980°**)
- **Tails**: Even multiples of 360° (e.g., 360°, 720°, 1080°, 1440°, 1800°, **2160°**)

The animation uses:
- **1980° for heads** = 5.5 full rotations = 11 × 180° (odd multiple)
- **2160° for tails** = 6 full rotations = 6 × 360° (even multiple)

#### Deceleration Curve Analysis

The animation creates a realistic gradual deceleration curve with speeds (in degrees/second):

| Keyframe Range | Heads Speed | Tails Speed | Notes |
|---------------|-------------|-------------|-------|
| 0% → 50% | **840°/sec** | **840°/sec** | Fast initial spin |
| 50% → 75% | **480°/sec** | **480°/sec** | Initial slowdown |
| 75% → 85% | **600°/sec** | **900°/sec** | Continued slowing |
| 85% → 95% | **300°/sec** | **600°/sec** | Very slow |
| 95% → 100% | **600°/sec** | **600°/sec** | Final gentle stop |

**Note**: The animation uses linear timing with carefully spaced keyframes to create a gradual deceleration effect that feels natural and smooth.

#### JavaScript Integration

**File**: `assets/js/coin_flip.js`

The JavaScript hook manages animation state and transitions:

```javascript
export const CoinFlip = {
  mounted() {
    this.coinEl = this.el.querySelector('.coin');
    this.result = this.el.dataset.result;
    const flipIndex = parseInt(this.el.dataset.flipIndex || '1');

    if (flipIndex === 1) {
      // First flip: start with continuous spinning
      this.coinEl.className = 'coin w-full h-full absolute animate-flip-continuous';
      console.log('[CoinFlip] First flip - starting continuous spin');
    } else {
      // Subsequent flips: go straight to the result animation
      const finalAnimation = this.result === 'heads' ? 'animate-flip-heads' : 'animate-flip-tails';
      this.coinEl.className = `coin w-full h-full absolute ${finalAnimation}`;
      console.log('[CoinFlip] Flip', flipIndex, '- starting direct reveal animation:', finalAnimation);

      // Notify backend when animation completes (3000ms = 3s)
      setTimeout(() => {
        if (!this.flipCompleted && this.el.id === this.currentFlipId) {
          this.flipCompleted = true;
          this.pushEvent('flip_complete', {});
        }
      }, 3000);
    }
  }
}
```

**Reveal Result Handler**:
```javascript
this.handleEvent("reveal_result", ({ flip_index, result }) => {
  this.resultRevealed = true;
  this.pendingResult = result;

  // Listen for the next animationiteration event (when continuous animation completes one loop)
  const switchAnimation = () => {
    const finalAnimation = this.pendingResult === 'heads' ? 'animate-flip-heads' : 'animate-flip-tails';
    this.coinEl.className = `coin w-full h-full absolute ${finalAnimation}`;
    console.log('[CoinFlip] Switched to final animation:', finalAnimation, 'at 0deg');
    this.coinEl.removeEventListener('animationiteration', switchAnimation);
  };

  this.coinEl.addEventListener('animationiteration', switchAnimation);

  // Wait for final animation to complete (3 seconds)
  setTimeout(() => {
    if (!this.flipCompleted && this.el.id === this.currentFlipId) {
      this.flipCompleted = true;
      this.pushEvent('flip_complete', {});
    }
  }, 3000);
});
```

#### Animation Flow for Multi-Flip Games

**Example: 3-flip game (difficulty 1.13x, Win One Mode)**

1. **Flip 1** (First flip):
   - Mount: Apply `animate-flip-continuous` (infinite spinning)
   - Backend confirms bet (2-4s)
   - Backend sends `reveal_result` event
   - Wait for next `animationiteration` (0° position)
   - Switch to `animate-flip-heads` or `animate-flip-tails`
   - Animation completes in 3s
   - Push `flip_complete` to backend

2. **Flip 2** (Subsequent):
   - Mount: Apply `animate-flip-heads` directly (result already known)
   - Animation completes in 3s
   - Push `flip_complete` to backend

3. **Flip 3** (Subsequent):
   - Same as Flip 2

**Total Time**: ~8-10s (depending on blockchain confirmation)

#### Performance Optimizations

1. **Multi-Flip Optimization**: Subsequent flips skip continuous spin phase
2. **Matching Initial Speed**: 50% keyframe at 1260° matches continuous spin's 840°/sec for seamless transition
3. **Linear Timing**: Uses `linear` instead of `ease` for predictable deceleration curve
4. **Gradual Deceleration**: Multiple keyframes (50%, 75%, 85%, 95%, 100%) create smooth slowdown

#### Key Characteristics

1. **Gradual Deceleration**: The animation uses carefully spaced keyframes to create a natural slowdown effect:
   - Fast initial spin (840°/sec at 0-50%)
   - Progressive slowing through intermediate keyframes
   - Very slow final rotation (300-600°/sec at 85-100%)
   - Smooth stop on the correct face

2. **Linear Timing with Keyframes**: Instead of using easing functions, the animation uses `linear` timing with multiple percentage-based keyframes. This allows precise control over the deceleration curve while maintaining predictable behavior.

---

## Required Admin Addresses

Before deployment, the following addresses are needed:

1. **Settler Address**: A regular EOA with ROGUE tokens for gas. The private key is stored in BUX Minter's environment file. This wallet calls `submitCommitment()` and `settleBet()`.

2. **Treasury Address**: Same as the contract owner. Only the owner can withdraw house balance.

**Note**: The settler is NOT a smart wallet - it's a regular EOA that pays its own gas fees from its ROGUE balance.

---

## Implementation Checklist

### Smart Contract
- [ ] Create `contracts/BuxBoosterGame.sol` with full code above
- [ ] Set up Hardhat project with config above
- [ ] Get settler and treasury addresses from user
- [ ] Deploy to Rogue Chain mainnet
- [ ] Configure all 11 tokens
- [ ] Deposit house balance for each token
- [ ] Verify contract on Roguescan

### BUX Minter Updates
- [ ] Add `POST /submit-commitment` endpoint
- [ ] Add `POST /settle-bet` endpoint (returns player balance)
- [ ] Configure settler wallet for game contract
- [ ] Test gasless transactions via Paymaster

### Blockster Backend
- [ ] Create `lib/blockster_v2/bux_booster_onchain.ex` (orchestration module)
- [ ] Update `:bux_booster_games` Mnesia table with new fields if needed
- [ ] Update `lib/blockster_v2_web/live/bux_booster_live.ex` for on-chain mode
- [ ] Add HTTPoison calls to BUX Minter
- [ ] Test full game flow end-to-end

### Frontend
- [ ] Create `assets/js/bux_booster_onchain.js` hook
- [ ] Add hook to `app.js`
- [ ] Implement `placeBet()` via Thirdweb smart wallet
- [ ] Handle approval flow (first time only)
- [ ] Implement coin flip animation with results
- [ ] Send "animation_complete" event when done
- [ ] Update LiveView template for TX hashes (commitment, bet, settlement)
- [ ] Show link to Roguescan for commitment verification

### Testing
- [ ] Test all 9 difficulty levels
- [ ] Test win/loss scenarios
- [ ] Test max bet limits
- [ ] Test expired bet refunds
- [ ] Test player stats tracking
- [ ] Verify on-chain balance sync to Mnesia
- [ ] Test animation timing (settlement waits for animation)
- [ ] Test commitment lookup on Roguescan

### Game Flow Summary
1. **Mount**: Blockster generates seed → stores in Mnesia → calls BUX Minter → submitCommitment
2. **Place Bet**: UI sends placeBet via Thirdweb → JS hook sends "bet_placed" to LiveView
3. **Calculate**: LiveView calculates result locally → pushes "start_coin_flip"
4. **Animate**: JS shows animation → sends "animation_complete"
5. **Settle**: LiveView shows result → calls BUX Minter → settleBet → updates balance

---

## Performance Optimizations (December 2024)

### Overview

The original implementation had **~6 second transaction times** for placing bets due to:
1. Sequential approve → placeBet transactions (2 separate UserOperations)
2. Waiting for transaction receipts before showing UI updates
3. Conservative gas limits causing slower bundler processing
4. Redundant allowance checks on every bet

After optimizations, transaction times reduced to:
- **First bet**: ~2-3 seconds (includes approval)
- **Subsequent bets**: ~1-2 seconds (approval cached)

### Key Optimizations Implemented

#### 1. Batch Transactions (`sendBatchTransaction`)

**Before**: Two separate UserOperations sent sequentially
```javascript
// Old flow (slow)
await sendTransaction({ approve });  // UserOp 1: ~3s
await sendTransaction({ placeBet }); // UserOp 2: ~3s
// Total: ~6s
```

**After**: Single UserOperation with batched calls
```javascript
// New flow (fast)
await sendBatchTransaction({
  transactions: [approve, placeBet]  // Single UserOp: ~2-3s
});
// Total: ~2-3s
```

**Savings**: ~3 seconds per first bet

#### 2. Infinite Approval with localStorage Caching

**Before**: Check allowance and approve exact amount on every bet
```javascript
// Every bet
const allowance = await checkAllowance(); // ~0.5s
if (allowance < amount) {
  await approve(amount); // ~3s
}
```

**After**: Approve infinite amount once, cache in localStorage
```javascript
// First bet only
const cached = localStorage.getItem('approval_...');
if (!cached) {
  await approve(MAX_UINT256); // Infinite approval
  localStorage.setItem('approval_...', 'true');
}
// Subsequent bets: skip entirely (0s)
```

**Savings**: ~3.5s on repeat bets

#### 3. Optimistic UI Updates

**Before**: Wait for transaction receipt before showing results
```javascript
const result = await sendTransaction(...);
const receipt = await waitForReceipt(result.txHash); // ~2s
// Parse events for betId
this.pushEvent("bet_placed", { betId });
```

**After**: Update UI immediately, poll for betId in background
```javascript
const result = await sendTransaction(...);
// Immediately update UI (0s wait)
this.pushEvent("bet_placed", {
  betId: commitmentHash, // Use temporary ID
  pending: true
});
// Background polling (doesn't block UI)
this.pollForBetId(result.txHash);
```

**Savings**: ~2s perceived latency

#### 4. Optimized Gas Limits

Reduced gas limits based on actual transaction requirements:

| Gas Parameter | Before | After | Savings |
|---------------|--------|-------|---------|
| `preVerificationGas` | 46856 | 30000 | -36% |
| `verificationGasLimit` | 100000 | 62500 | -37.5% |
| `callGasLimit` (single) | 120000 | 200000* | +67%** |
| `callGasLimit` (batch) | 120000 | 300000 | +150%** |

\* Increased for safety margin with new batching
\*\* Higher limits for batched operations, but overall faster due to single UserOp

**Batch transaction detection**: Paymaster now detects `executeBatch` calls and adjusts gas accordingly.

**Savings**: ~0.5-1s bundler processing time

### File Changes

#### JavaScript
- **[assets/js/bux_booster_onchain.js](../assets/js/bux_booster_onchain.js)**: Complete rewrite with batching, caching, and optimistic updates
- **[assets/js/home_hooks.js](../assets/js/home_hooks.js)**: Optimized paymaster gas limits, batch detection

#### Elixir
- **[lib/blockster_v2_web/live/bux_booster_live.ex](../lib/blockster_v2_web/live/bux_booster_live.ex)**: Handle `pending` flag and `bet_confirmed` event

### Testing the Optimizations

1. **First bet** (with approval):
   ```
   # Should complete in 2-3 seconds
   - Check approval cache (instant)
   - Submit batched approve + placeBet (2-3s)
   - UI updates immediately
   - Background: poll for betId
   ```

2. **Subsequent bets** (already approved):
   ```
   # Should complete in 1-2 seconds
   - Cache hit (instant)
   - Submit placeBet only (1-2s)
   - UI updates immediately
   ```

3. **Monitor console logs**:
   ```
   [BuxBoosterOnchain] Using cached approval ✅
   [BuxBoosterOnchain] Executing batch transaction (2 calls)...
   💰 Paymaster function called
   📦 Batch transaction detected, using higher callGasLimit
   [BuxBoosterOnchain] ✅ Batch tx submitted: 0x...
   ```

### Cache Management

Approval cache keys:
```
approval_{walletAddress}_{tokenAddress}_{contractAddress}
```

**Clear cache** when:
- User manually revokes approval via external wallet
- Token contract is upgraded
- Testing different scenarios

```javascript
// Clear all approvals
Object.keys(localStorage)
  .filter(k => k.startsWith('approval_'))
  .forEach(k => localStorage.removeItem(k));
```

### Future Optimizations

1. **Bundler tuning**: Reduce `max_bundle_size` to 1 for instant processing
2. **Gas price optimization**: Use priority fee multipliers during low congestion
3. **WebSocket for receipts**: Replace polling with event-driven receipt fetching
4. **Parallel commitment**: Submit next game's commitment while current game animates

### Performance Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| First bet latency | ~6s | ~2-3s | **50-60%** |
| Repeat bet latency | ~6s | ~1-2s | **67-83%** |
| UserOperations per bet | 2 | 1 | **50%** |
| Allowance checks | Every bet | First only | **N/A** |
| UI responsiveness | Blocked | Instant | **100%** |

### Monitoring

Check bundler logs for batch transaction processing:
```bash
flyctl logs --app rogue-bundler-mainnet | grep "batch"
```

Monitor gas usage:
```bash
# Check actual gas used vs estimates
cast receipt <tx_hash> --rpc-url https://rpc.roguechain.io/rpc
```

---

## Optimistic UI Architecture (December 2024)

### Overview

The BUX Booster game implements a sophisticated optimistic UI pattern to provide instant feedback to users while maintaining provably fair gameplay. This section documents the complete architecture, data flow, and critical lessons learned.

### Problem Statement

Before optimistic UI implementation:
- **High perceived latency**: Users waited for blockchain confirmation before seeing results
- **Poor UX**: 2-3 second freeze while waiting for transaction confirmation
- **Balance sync issues**: UI showed stale balances after winning bets
- **No visual feedback**: Users didn't know if their bet was being processed

After optimistic UI implementation:
- **Instant feedback**: Balance updates immediately when placing bet
- **Smooth animations**: Coin flips start without waiting for blockchain
- **Accurate balance sync**: Blockchain balances propagate to all LiveViews
- **~2s+ perceived latency reduction**

### Architecture Components

#### 1. Balance Management System

**Source of Truth**: Mnesia serves as the **optimistic** balance cache, synced from blockchain

**Data Flow**:
```
┌──────────────────────────────────────────────────────────────────────┐
│                     BALANCE MANAGEMENT FLOW                           │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  User Places Bet                                                      │
│       │                                                               │
│       ├─> IMMEDIATE: Deduct balance in Mnesia                        │
│       │   EngagementTracker.deduct_token_balance(user_id, token, amt)│
│       │                                                               │
│       └─> BROADCAST: PubSub sends balance update to all LiveViews    │
│           BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update│
│                                                                       │
│  Blockchain Confirms Bet                                              │
│       │                                                               │
│       └─> MARK: Update bet status to :placed in Mnesia               │
│           (balance already deducted, no change needed)                │
│                                                                       │
│  Settlement Completes On-Chain                                        │
│       │                                                               │
│       ├─> TRIGGER: Async balance sync from blockchain                │
│       │   BuxMinter.sync_user_balances_async(user_id, wallet)        │
│       │                                                               │
│       └─> BROADCAST: PubSub sends updated balances when sync done    │
│           (includes payout from winning bet)                          │
│                                                                       │
│  Page Load                                                            │
│       │                                                               │
│       └─> SYNC: Fetch latest balances from blockchain                │
│           BuxMinter.sync_user_balances_async() on connected mount    │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

#### 2. PubSub Broadcasting Pattern

**Topic**: `"bux_balance:{user_id}"`

**Messages**:
- `{:bux_balance_updated, new_total_balance}` - Aggregate balance changed
- `{:token_balances_updated, %{token => balance}}` - Individual token balances changed

**Subscription Pattern**:
```elixir
# In mount/3 - connected mount only
if wallet_address != nil and connected?(socket) do
  Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:#{current_user.id}")

  # Trigger initial balance sync from blockchain
  BuxMinter.sync_user_balances_async(current_user.id, wallet_address)

  socket
else
  socket
end
```

**Handler Pattern**:
```elixir
# In handle_info/2
def handle_info({:bux_balance_updated, _new_balance}, socket) do
  # Aggregate balance maintained in header component
  # BuxBoosterLive doesn't need it directly
  {:noreply, socket}
end

def handle_info({:token_balances_updated, token_balances}, socket) do
  # Update our local token balances when broadcast
  {:noreply, assign(socket, balances: token_balances)}
end
```

#### 3. Bet State Machine

**States**:
- `:pending` - Server seed generated, commitment submitted to blockchain
- `:placed` - User's placeBet transaction confirmed on-chain
- `:settled` - Bet settled, payout (if any) distributed
- `:expired` - Bet not settled within timeout period

**Optimistic Flow**:
```elixir
# 1. User clicks "Bet" → Deduct balance immediately (optimistic)
EngagementTracker.deduct_token_balance(user_id, token, amount)
BuxBalanceHook.broadcast_token_balances_update(user_id, new_balances)

# 2. Frontend submits placeBet transaction
push_event("place_bet_background", %{game_id: ..., amount: ...})

# 3. Transaction confirms → Update bet status (balance already deducted)
handle_info({:bet_confirmed, ...}, socket) do
  BuxBoosterOnchain.mark_bet_placed(game_id)
  {:noreply, socket}
end

# 4. Settlement completes → Trigger balance sync
handle_info({:settlement_complete, tx_hash}, socket) do
  user_id = socket.assigns.current_user.id
  wallet_address = socket.assigns.wallet_address

  # Async sync from blockchain (will broadcast when done)
  BuxMinter.sync_user_balances_async(user_id, wallet_address)

  {:noreply, assign(socket, settlement_tx: tx_hash)}
end
```

#### 4. Balance Sync Implementation

**Module**: `BlocksterV2.BuxMinter`

**Function**: `sync_user_balances_async/2`

**Implementation**:
```elixir
@doc """
Asynchronously sync all token balances from blockchain to Mnesia.
Broadcasts to PubSub when complete, updating all subscribed LiveViews.

NEVER use Process.sleep() after calling this function - it's async!
"""
def sync_user_balances_async(user_id, wallet_address) do
  Task.start(fn ->
    case get_all_balances(wallet_address) do
      {:ok, balances} ->
        # Update Mnesia with fresh blockchain data
        Enum.each(balances, fn {token, balance_wei} ->
          balance = div(balance_wei, 1_000_000_000_000_000_000)
          EngagementTracker.set_token_balance(user_id, token, balance)
        end)

        # Broadcast updated balances to ALL subscribed LiveViews
        token_balances = EngagementTracker.get_user_token_balances(user_id)
        BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update(
          user_id,
          token_balances
        )

      {:error, reason} ->
        Logger.error("[BuxMinter] Failed to sync balances: #{inspect(reason)}")
    end
  end)
end
```

**Key Properties**:
- **Asynchronous**: Does not block calling process
- **Broadcasts when done**: PubSub notifies all LiveViews
- **Self-contained**: No need to wait for it or poll

#### 5. LiveView Hook Integration

**BuxBalanceHook**: Global hook for balance updates in header AND game page

**Responsibilities**:
- Fetches initial balances on mount
- Subscribes to PubSub for balance updates
- Attaches `handle_info` interceptor for balance messages
- **Updates BOTH `:token_balances` (header) AND `:balances` (BuxBoosterLive) assigns**
- Broadcasts balance changes after minting/spending

**How It Works**:
```elixir
# In bux_balance_hook.ex
def on_mount(:default, _params, _session, socket) do
  # ... fetch initial balances ...

  socket
  |> assign(:bux_balance, initial_balance)
  |> assign(:token_balances, initial_token_balances)
  |> attach_hook(:bux_balance_updates, :handle_info, fn
    {:token_balances_updated, token_balances}, socket ->
      # Update both :token_balances (for header) and :balances (for BuxBoosterLive)
      socket = assign(socket, :token_balances, token_balances)
      socket = if Map.has_key?(socket.assigns, :balances) do
        assign(socket, :balances, token_balances)
      else
        socket
      end
      {:halt, socket}  # CRITICAL: :halt prevents message from reaching LiveView's handle_info

    _other, socket ->
      {:cont, socket}
  end)
end
```

**Usage in Router**:
```elixir
# BuxBalanceHook is attached globally via on_mount in router.ex
live_session :default,
  on_mount: [BlocksterV2Web.UserAuth, BlocksterV2Web.BuxBalanceHook]
```

**Usage in BuxBoosterLive**:
```elixir
defmodule BlocksterV2Web.BuxBoosterLive do
  # BuxBalanceHook is automatically attached via on_mount in router
  # The hook updates socket.assigns.balances automatically when broadcast is received

  def mount(_params, _session, socket) do
    # Sync balances from blockchain on connected mount (async)
    if wallet_address != nil and connected?(socket) do
      BuxMinter.sync_user_balances_async(current_user.id, wallet_address)
    end

    # Use :balances assign (updated by BuxBalanceHook)
    {:ok, assign(socket, balances: EngagementTracker.get_user_token_balances(current_user.id))}
  end

  # NO handle_info needed - BuxBalanceHook intercepts with {:halt, ...}
end
```

**Key Points**:
- BuxBalanceHook uses `{:halt, socket}` which **intercepts** the broadcast before it reaches the LiveView's `handle_info`
- The hook conditionally updates `:balances` assign only if it exists (for BuxBoosterLive)
- No need for manual `handle_info` in BuxBoosterLive - the hook handles everything

### Critical Lessons Learned

#### 1. NEVER Use `Process.sleep()` After Async Calls

**Wrong**:
```elixir
# ❌ WRONG - sleep doesn't wait for async task
BuxMinter.sync_user_balances_async(user_id, wallet_address)
Process.sleep(100)  # This does NOTHING useful
balances = EngagementTracker.get_user_token_balances(user_id)  # Still stale!
```

**Why it's wrong**:
- `async` means the function runs in a **separate process**
- `Process.sleep(100)` only sleeps the **calling process**, not the async task
- The async task might not even start within 100ms
- The async task broadcasts when done - no need to wait

**Right**:
```elixir
# ✅ CORRECT - rely on async broadcast
BuxMinter.sync_user_balances_async(user_id, wallet_address)
# UI updates automatically when balance sync completes via PubSub
```

#### 2. Use PubSub for Cross-LiveView Updates

**Pattern**: One operation (bet settlement) affects multiple views (game page + header balance)

**Solution**: Broadcast via PubSub, all subscribed LiveViews update automatically

**Example**:
```elixir
# In EngagementTracker after updating Mnesia
def set_token_balance(user_id, token, new_balance) do
  # Update Mnesia
  :mnesia.dirty_write({:user_bux_balances, user_id, updated_balances})

  # Broadcast to all LiveViews
  BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update(
    user_id,
    updated_balances
  )
end
```

#### 3. Balance Sync Timing Strategy

**On Page Load**:
- Trigger `sync_user_balances_async()` on **connected mount** only
- Ensures user sees most up-to-date balance when landing on page
- Async operation doesn't block page render

**On Bet Placed**:
- Deduct balance **immediately** in Mnesia (optimistic)
- Broadcast updated balance to UI
- Don't wait for blockchain confirmation

**On Bet Confirmed**:
- Mark bet as `:placed` in Mnesia
- Balance already deducted, no additional changes needed

**On Settlement**:
- Trigger `sync_user_balances_async()` to fetch actual on-chain balance
- Includes payout if user won
- Broadcast when sync completes

#### 4. Aggregate Balance Calculation Bug

**Problem**: When summing token balances, accidentally included the "aggregate" key itself

**Wrong**:
```elixir
# ❌ Includes aggregate in sum, double-counting
aggregate_balance = Enum.reduce(balances, 0, fn {_token, bal}, acc -> acc + bal end)
```

**Right**:
```elixir
# ✅ Exclude "aggregate" key from sum
aggregate_balance =
  balances
  |> Map.drop(["aggregate"])
  |> Enum.reduce(0, fn {_token, bal}, acc -> acc + bal end)
```

#### 5. LiveView Hook Conflicts

**Problem**: `on_mount BlocksterV2Web.BuxBalanceHook` uses `attach_hook(:bux_balance_updates, :handle_info, ...)`, which can only be attached once. Using it in multiple LiveViews causes error:

```
ArgumentError: existing hook :bux_balance_updates already attached on :handle_info
```

**Solution**: Don't use `on_mount` for BuxBalanceHook in BuxBoosterLive. Instead:
1. Manually subscribe to PubSub in mount
2. Add direct `handle_info` callbacks for balance messages
3. Let the hook handle the header component

**Code**:
```elixir
# In BuxBoosterLive - NO on_mount for BuxBalanceHook
def mount(_params, _session, socket) do
  # Subscribe directly
  if wallet_address and connected?(socket) do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:#{current_user.id}")
  end

  {:ok, socket}
end

# Add handlers directly (not via hook)
def handle_info({:bux_balance_updated, _}, socket), do: {:noreply, socket}
def handle_info({:token_balances_updated, balances}, socket) do
  {:noreply, assign(socket, balances: balances)}
end
```

### Complete Flow Example

**Scenario**: User places 100 BUX bet, wins 198 BUX payout

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   COMPLETE OPTIMISTIC UI FLOW                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ 1. PAGE LOAD                                                             │
│    mount/3 (connected)                                                   │
│      ├─> Subscribe to PubSub: "bux_balance:42"                           │
│      ├─> Fetch initial balances from Mnesia: 1000 BUX                   │
│      └─> Trigger: BuxMinter.sync_user_balances_async()                  │
│           (fetches from blockchain, broadcasts when done)                │
│                                                                          │
│ 2. USER CLICKS "BET" (100 BUX)                                           │
│    handle_event("bet_now")                                               │
│      ├─> Deduct immediately in Mnesia: 1000 - 100 = 900 BUX            │
│      ├─> Broadcast: {:token_balances_updated, %{"BUX" => 900}}          │
│      │    → Header balance updates to 900 instantly                      │
│      │    → Game page balance updates to 900 instantly                   │
│      └─> Push JS event: "place_bet_background"                          │
│                                                                          │
│ 3. FRONTEND SUBMITS TRANSACTION                                          │
│    bux_booster_onchain.js                                                │
│      ├─> Check approval cache (instant)                                 │
│      ├─> Execute approve + placeBet (sequential, ~2-3s)                 │
│      └─> Push event: "bet_confirmed" when tx confirms                   │
│                                                                          │
│ 4. BET CONFIRMED ON-CHAIN                                                │
│    handle_info({:bet_confirmed, ...})                                    │
│      ├─> Mark bet as :placed in Mnesia                                  │
│      ├─> Start coin flip animation                                      │
│      └─> NO balance changes (already deducted in step 2)                │
│                                                                          │
│ 5. SETTLEMENT COMPLETES (~3s animation + settlement)                     │
│    handle_info({:settlement_complete, tx_hash})                          │
│      ├─> Trigger: BuxMinter.sync_user_balances_async()                  │
│      │    → Fetches blockchain balance: 998 BUX (900 + 198 payout - 100)│
│      │    → Updates Mnesia with fresh data                               │
│      │    → Broadcast: {:token_balances_updated, %{"BUX" => 998}}       │
│      │                                                                   │
│      └─> UI updates automatically when broadcast arrives:                │
│           - Header shows 998 BUX                                         │
│           - Game page shows 998 BUX                                      │
│           - Payout visible: +98 BUX profit                               │
│                                                                          │
│ 6. NEXT PAGE LOAD (FRESH SESSION)                                        │
│    mount/3 (connected)                                                   │
│      └─> Sync from blockchain again                                     │
│           → Ensures user always sees accurate balance                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Performance Impact

| Metric | Before Optimistic UI | After Optimistic UI | Improvement |
|--------|---------------------|---------------------|-------------|
| Balance deduction feedback | ~2-3s (wait for blockchain) | Instant | **100%** |
| Settlement balance update | Manual refresh required | Automatic | **100%** |
| UI freeze during bet | ~2-3s | 0s | **100%** |
| Cross-view consistency | Refresh required | Automatic (PubSub) | **100%** |
| Perceived latency | ~5-6s total | ~3s total | **~40%** |

### Testing Checklist

**Balance Deduction**:
- [ ] Balance decreases instantly when clicking "Bet"
- [ ] Header balance updates immediately
- [ ] Game page balance updates immediately
- [ ] Balance is correct even if transaction fails (handle `bet_failed` event)

**Settlement Balance Sync**:
- [ ] Winning bet: balance increases after settlement
- [ ] Losing bet: balance stays deducted (no additional change)
- [ ] Balance syncs to exact blockchain value (no rounding errors)
- [ ] Multiple tabs: all tabs show same balance after settlement

**Page Load Sync**:
- [ ] Fresh page load shows most recent blockchain balance
- [ ] Balance doesn't flash/jump when sync completes
- [ ] Works correctly after winning bet in another tab

**Error Handling**:
- [ ] Failed bet: balance restored if transaction reverts
- [ ] Network error during sync: doesn't crash LiveView
- [ ] Multiple rapid bets: balance deductions stack correctly

**PubSub Broadcasts**:
- [ ] Balance updates propagate to all open tabs
- [ ] Header component receives updates
- [ ] Game page receives updates
- [ ] No duplicate updates

### Debugging Tips

**Enable verbose logging**:
```elixir
# In config/dev.exs
config :logger, level: :debug

# In BuxMinter module
require Logger
Logger.debug("[BuxMinter] Syncing balances for user #{user_id}...")
```

**Monitor PubSub messages**:
```elixir
# In IEx
Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:42")

# You'll see:
# {:token_balances_updated, %{"BUX" => 900, "moonBUX" => 500}}
```

**Check Mnesia directly**:
```elixir
# In IEx
:mnesia.dirty_read({:user_bux_balances, 42})
# [{:user_bux_balances, 42, %{"BUX" => 900, "moonBUX" => 500, "aggregate" => 1400}}]
```

**Verify balance sync timing**:
```javascript
// In browser console
console.log('[BuxBoosterOnchain] Balance before bet:', balances);
// Place bet...
console.log('[BuxBoosterOnchain] Balance after bet:', balances);
// Wait for settlement...
console.log('[BuxBoosterOnchain] Balance after settlement:', balances);
```

### Common Pitfalls

1. **Using `Process.sleep()` after async calls** - Does nothing, removed entirely
2. **Not subscribing on connected mount** - Subscriptions in disconnected mount don't work
3. **Including "aggregate" in balance sums** - Double-counts total balance
4. **Using `on_mount` for hooks that attach to `:handle_info`** - Can only attach once
5. **Not handling `bet_failed` event** - Balance stays deducted if transaction fails
6. **Forgetting to broadcast after Mnesia updates** - Other LiveViews won't update
7. **Syncing balances synchronously** - Blocks the LiveView process

### Future Enhancements

1. **Optimistic settlement**: Show payout immediately, sync in background
2. **Balance prediction**: Predict balance after pending transactions
3. **WebSocket for faster updates**: Replace polling with event-driven updates
4. **Transaction queue**: Handle multiple rapid bets without race conditions
5. **Rollback mechanism**: Revert optimistic updates if transaction fails

---

## Bug Fixes & Learnings

### Multi-Flip Coin Reveal Bug (Dec 2024)

**Problem**: In games with 2+ flips (1.32x, 1.13x, 1.05x, 1.02x, 3.96x, 7.92x, 15.84x, 31.68x), the second and subsequent coin flips would spin continuously and never reveal the result, causing the game to hang.

**Root Cause**: 
- The `reveal_result` push event (which tells the CoinFlip JavaScript hook to stop spinning and show the final coin face) was only scheduled once during the initial bet confirmation in `handle_event("bet_confirmed")`
- When moving to subsequent flips via `handle_info(:next_flip)`, no new `reveal_result` was scheduled
- The CoinFlip hook would wait forever for the reveal event that never came

**The Flow**:
```elixir
# BEFORE (broken for flip 2+)
bet_confirmed → schedule reveal_flip_result (flip 1) → flip 1 reveals ✓
             → :next_flip (flip 2) → 🔴 NO REVEAL SCHEDULED → coin spins forever

# AFTER (fixed)
bet_confirmed → schedule reveal_flip_result (flip 1) → flip 1 reveals ✓
             → :next_flip (flip 2) → ✅ schedule reveal_flip_result → flip 2 reveals ✓
             → :next_flip (flip 3) → ✅ schedule reveal_flip_result → flip 3 reveals ✓
```

**Solution**: 
Added `Process.send_after(self(), :reveal_flip_result, 3000)` to the `:next_flip` handler:

```elixir
def handle_info(:next_flip, socket) do
  # ... existing code ...
  
  # Schedule reveal_result for this flip (3 second minimum spin time)
  Process.send_after(self(), :reveal_flip_result, 3000)
  
  {:noreply,
   socket
   |> assign(game_state: :flipping)
   |> assign(current_flip: socket.assigns.current_flip + 1)
   |> assign(flip_id: socket.assigns.flip_id + 1)
   |> assign(current_bet: new_current_bet)}
end
```

**Files Changed**: 
- [bux_booster_live.ex:1600](lib/blockster_v2_web/live/bux_booster_live.ex#L1600)

**Testing**: All difficulty levels with multiple flips now work correctly:
- ✅ 1.32x (2 flips, Win One)
- ✅ 1.13x (3 flips, Win One)
- ✅ 1.05x (4 flips, Win One)
- ✅ 1.02x (5 flips, Win One)
- ✅ 3.96x (2 flips, Win All)
- ✅ 7.92x (3 flips, Win All)
- ✅ 15.84x (4 flips, Win All)
- ✅ 31.68x (5 flips, Win All)

**Key Lesson**: When using timed events in multi-step processes, ensure each step schedules its own events. Don't assume one-time scheduling will cover all iterations.

---

## Recent Games Table & Infinite Scroll (Dec 2024)

### Overview
Added a comprehensive game history table with infinite scroll pagination to display all settled on-chain bets.

### Features
- **Initial Load**: Displays last 30 games
- **Infinite Scroll**: Automatically loads 30 more games as user scrolls
- **Scrollable Container**: `max-h-96` (384px) shows ~10 rows, rest accessible via scroll
- **Sticky Header**: Table header remains visible during scroll
- **Live Updates**: New bets automatically appear after settlement

### Table Columns

| Column | Content | Link |
|--------|---------|------|
| **Bet ID** | Nonce number (e.g., #137) | Links to bet placement tx on Roguescan with `?tab=logs` |
| **Bet** | Token amount wagered | - |
| **Token** | Token type with logo | - |
| **Predictions** | User's predictions (H/T) | - |
| **Results** | Actual flip results (H/T, bold) | - |
| **Odds** | Multiplier (e.g., 1.98x) | - |
| **Result** | Win/Loss | - |
| **Payout** | Payout amount | Links to settlement tx on Roguescan with `?tab=logs` |
| **Verify** | Provably Fair verification | Opens modal for settled games only |

### Implementation

#### 1. Data Loading with Pagination
```elixir
defp load_recent_games(user_id, opts \\ []) do
  limit = Keyword.get(opts, :limit, 10)
  offset = Keyword.get(opts, :offset, 0)

  :mnesia.dirty_index_read(:bux_booster_onchain_games, user_id, :user_id)
  |> Enum.filter(fn record -> elem(record, 7) == :settled end)
  |> Enum.sort_by(fn record -> elem(record, 21) end, :desc)  # settled_at
  |> Enum.drop(offset)
  |> Enum.take(limit)
  |> Enum.map(fn record -> %{...} end)
end
```

#### 2. Socket State Management
```elixir
# Mount - load initial 30 games
socket
|> assign(recent_games: load_recent_games(current_user.id, limit: 30))
|> assign(games_offset: 30)  # Track pagination position
```

#### 3. Infinite Scroll Event Handler
```elixir
def handle_event("load-more-games", _params, socket) do
  user_id = socket.assigns.current_user.id
  offset = socket.assigns.games_offset

  new_games = load_recent_games(user_id, limit: 30, offset: offset)

  if Enum.empty?(new_games) do
    {:reply, %{end_reached: true}, socket}  # Signal no more data
  else
    updated_games = socket.assigns.recent_games ++ new_games
    
    {:noreply,
     socket
     |> assign(:recent_games, updated_games)
     |> assign(:games_offset, offset + length(new_games))}
  end
end
```

#### 4. Template Structure
```heex
<div id="recent-games-scroll" class="overflow-y-auto max-h-96" phx-hook="InfiniteScroll">
  <div class="overflow-x-auto">
    <table class="w-full text-xs">
      <thead class="sticky top-0 bg-white z-10">
        <!-- Table headers -->
      </thead>
      <tbody>
        <%= for game <- @recent_games do %>
          <!-- Game rows -->
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

### InfiniteScroll Hook Updates

Enhanced the existing `InfiniteScroll` hook to support both window scrolling and scrollable div containers.

#### Key Improvements
1. **Auto-Detection**: Detects if element has overflow scrolling
2. **Dual Mode**: 
   - Window scroll (existing posts index behavior)
   - Element scroll (new for scrollable containers)
3. **Element-Specific Events**: Routes to correct event based on element ID

#### Implementation
```javascript
let InfiniteScroll = {
  mounted() {
    // Detect if element has overflow scrolling
    const hasOverflow = this.el.scrollHeight > this.el.clientHeight;
    const isScrollable = getComputedStyle(this.el).overflowY === 'auto' ||
                         getComputedStyle(this.el).overflowY === 'scroll';
    this.useElementScroll = hasOverflow && isScrollable;

    // IntersectionObserver with element as root for scrollable divs
    this.observer = new IntersectionObserver(
      entries => {
        if (entries[0].isIntersecting && !this.pending && !this.endReached) {
          this.loadMore();
        }
      },
      {
        root: this.useElementScroll ? this.el : null,
        rootMargin: '200px',
        threshold: 0
      }
    );

    // Attach scroll listener to element or window
    if (this.useElementScroll) {
      this.el.addEventListener('scroll', this.handleScroll, { passive: true });
    } else {
      window.addEventListener('scroll', this.handleScroll, { passive: true });
    }
  },

  loadMore() {
    let eventName = 'load-more';
    if (this.el.id === 'hub-news-stream') {
      eventName = 'load-more-news';
    } else if (this.el.id === 'recent-games-scroll') {
      eventName = 'load-more-games';
    }

    this.pushEvent(eventName, {}, (reply) => {
      if (reply && reply.end_reached) {
        this.endReached = true;
        this.observer.disconnect();
      }
      setTimeout(() => { this.pending = false; }, 200);
    });
  }
}
```

### Security: Verify Modal Fix

**CRITICAL BUG FIXED**: The verify modal was showing the server seed for the UPCOMING game, which would allow players to predict all future results!

#### The Problem
```elixir
# WRONG - Shows upcoming game's server seed
def handle_event("show_fairness_modal", _params, socket) do
  game_id = socket.assigns.onchain_game_id  # Current/upcoming game!
  server_seed = BuxBoosterOnchain.get_game(game_id).server_seed  # DANGER!
end
```

#### The Fix
```elixir
# CORRECT - Only shows settled games
def handle_event("show_fairness_modal", %{"game-id" => game_id}, socket) do
  case :mnesia.dirty_read({:bux_booster_onchain_games, game_id}) do
    [record] when elem(record, 7) == :settled ->  # status field check
      # Build fairness_game from THIS SPECIFIC SETTLED GAME
      {:noreply, assign(socket, show_fairness_modal: true, fairness_game: ...)}
    _ ->
      {:noreply, socket}  # Reject non-settled games
  end
end
```

#### Security Rules (Added to CLAUDE.md)
1. Server seed MUST ONLY be revealed AFTER bet is settled
2. Verify modal MUST ONLY show data for settled games (status = `:settled`)
3. NEVER fetch server seed from current/pending game session
4. Always query Mnesia with `status == :settled` guard
5. Any UI showing server seed must pass specific `game_id` and verify it's settled

### Files Changed
- [bux_booster_live.ex](lib/blockster_v2_web/live/bux_booster_live.ex) - Recent games, pagination, verify modal fix
- [app.js](assets/js/app.js) - InfiniteScroll hook enhancements
- [CLAUDE.md](CLAUDE.md) - Security warnings for provably fair systems

### Performance Characteristics
- **Initial Query**: 30 games from Mnesia (~1-2ms)
- **Scroll Load**: 30 games per trigger (~1-2ms)
- **UI Rendering**: ~10 rows visible, smooth scrolling
- **Memory**: Unbounded growth (consider limit in future)

### Future Improvements
- [ ] Add max total games limit (e.g., 300) to prevent memory issues
- [ ] Add filters (token type, win/loss, date range)
- [ ] Add search by nonce or bet ID
- [ ] Add CSV export functionality
- [ ] Consider virtual scrolling for 1000+ games

