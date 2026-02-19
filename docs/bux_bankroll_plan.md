# BUXBankroll LP System — Implementation Plan

> **Purpose**: Centralized BUX liquidity pool with LP tokens, servicing all BUX-based games (Plinko first, BuxBoosterGame migration later). Users deposit BUX, receive LP-BUX tokens, and earn/lose as the house wins/loses bets. Includes a real-time bankroll dashboard with candlestick price charts.

> **BuxBoosterGame Migration Note**: BuxBoosterGame will be migrated to use BUXBankroll for all BUX house funds AFTER Plinko + BUXBankroll are successfully deployed and battle-tested in production. This migration involves removing BuxBoosterGame's internal BUX TokenConfig and delegating to BUXBankroll, same pattern as Plinko. No BuxBoosterGame changes should be made until then.

## Implementation Progress

### Phase B1: BUXBankroll.sol — COMPLETE (Feb 18, 2026)
- **Worktree**: `../blockster-v2-bankroll` on branch `feat/bux-bankroll` (based off `main`)
- **Files created**:
  - `contracts/bux-booster-game/contracts/BUXBankroll.sol` — flattened contract (all OZ v5 deps inlined, 1335 lines)
  - `contracts/bux-booster-game/contracts/IBUXBankroll.sol` — interface for PlinkoGame integration
  - `contracts/bux-booster-game/test/BUXBankroll.test.js` — 87 tests, all passing
- **Source**: Copied from `docs/BUXBankroll_full.sol` and `docs/IBUXBankroll_full.sol`
- **Fix applied**: Added `receive() external payable {}` fallback (was in plan but missing from flattened source)
- **Compiler**: Compiles clean. 4 expected warnings (unused params in `settlePlinkoPushBet` — needed for interface consistency)
- **UUPS upgrade tests**: Tested via direct `upgradeToAndCall` (not OZ plugin) because flattened contract only has `upgradeToAndCall` (OZ v5), not standalone `upgradeTo` that the plugin's `upgradeProxy` expects
- **Test coverage**: Initialization (9), depositBUX (7), withdrawBUX (7), LP Price Mechanics (6), Plinko Bet Placed (4), Winning Settlement (4), Losing Settlement (5), Push Settlement (3), Liability Tracking (3), Referral Rewards (10), Stats Tracking (5), Admin Functions (11), getMaxBet (3), UUPS Upgrade (3), View Functions (4), Edge Cases (3)
- **Not committed yet** — awaiting user instructions

### Phase B2: Deploy BUXBankroll — NOT STARTED
### Phase B3: BUX Minter routes — NOT STARTED
### Phase B4: Backend (LPBuxPriceTracker, Mnesia, BuxMinter) — NOT STARTED
### Phase B5: BankrollLive + Chart/Onchain hooks — NOT STARTED

## Review Notes (Feb 2026)

> **Status**: Plan reviewed for production-readiness. Issues found and fixed inline throughout. Key changes:
>
> **Contract fixes**:
> - OZ version decision: Use OZ v5 style (`__Ownable_init(msg.sender)`) matching BuxBoosterGame.sol, NOT OZ v4 style matching ROGUEBankroll.sol. BUXBankroll is a new deployment so we pick the newer pattern.
> - `_sendReferralReward` uses `try IERC20(buxToken).transfer(...)` — NOT `safeTransfer`, because `safeTransfer` is a library (internal) call and `try` only works with external calls. The `try-catch` pattern ensures referral failures never block bet settlement.
> - Added `setPaused(bool)` admin function (was missing despite PausableUpgradeable inheritance)
> - Added `getPlinkoAccounting`, `getPlinkoPlayerStats` view function bodies (were stubs)
> - Added `receive() external payable {}` fallback — not strictly needed for ERC-20 only contract, but safe to include
>
> **Backend fixes**:
> - BuxMinter helper functions corrected: `get_minter_url()` / `get_api_secret()` + `http_get`/`http_post` wrappers (not raw `Req.get`)
> - LPBuxPriceTracker updated to use GlobalSingleton pattern (matching all other global GenServers)
> - Application.ex registration corrected: `{BlocksterV2.LPBuxPriceTracker, []}` (module calls GlobalSingleton internally)
> - Added missing `handle_async` callbacks for all `start_async` calls
> - Added missing `handle_event` implementations for deposit/withdraw/timeframe
> - Added missing `handle_info` for PubSub messages
> - Added missing `bux_bankroll_lp_balance/1` and `bux_bankroll_player_stats/1` BuxMinter functions
> - Fixed `get_candles` to properly calculate cutoff based on candle count, not duration * limit
>
> **Frontend fixes**:
> - Added complete HeeX template for BankrollLive
> - Added LP-BUX user balance async fetch on mount
> - Added `localStorage` approval caching in BankrollOnchain JS hook (matching BuxBoosterOnchain pattern)
> - Fixed deposit/withdraw amount handling for decimal BUX values

### LP Price Math — Design Notes

**Deposit pricing** uses `effectiveBalance = totalBalance - unsettledBets` (removes in-flight wager amounts that haven't resolved yet). This prevents depositors from being diluted by unrealized bets.

**Withdrawal pricing** uses `netBalance = totalBalance - liability` (removes maximum possible payouts for active bets). This prevents withdrawals from draining funds needed to cover worst-case bet outcomes.

**This is intentional and correct.** The two formulas serve different purposes:
- `effectiveBalance` answers: "What is the pool actually worth right now?" (for fair LP pricing)
- `netBalance` answers: "How much can safely leave the pool?" (for withdrawal safety)

A depositor entering during active bets gets LP tokens priced on realized pool value. A withdrawer during active bets can only withdraw what isn't reserved for potential payouts. After all bets settle, `unsettledBets = 0` and `liability = 0`, so both converge to `totalBalance`.

## Overview

| Component | Description |
|-----------|-------------|
| **BUXBankroll.sol** | ERC-20 LP token contract that holds all BUX house funds, services game settlements |
| **BankrollLive** | LiveView page: deposit/withdraw BUX, LP-BUX stats, candlestick price chart |
| **LP-BUX Token** | Minted on deposit, burned on withdraw. Price = total BUX / LP supply |
| **Chart System** | TradingView `lightweight-charts`, OHLC data stored in Mnesia, real-time PubSub updates |

### Architecture

```
User deposits BUX ──► BUXBankroll ──► mints LP-BUX to user
User withdraws LP-BUX ──► BUXBankroll ──► burns LP-BUX, returns BUX

PlinkoGame.placeBet ──► BUX transferred from player to BUXBankroll
PlinkoGame.settleBet(win) ──► BUXBankroll.settlePlinkoWinningBet ──► sends payout to player
PlinkoGame.settleBet(loss) ──► BUXBankroll.settlePlinkoLosingBet ──► keeps BUX, pays referral
```

---

## Table of Contents

1. [Smart Contract: BUXBankroll.sol](#1-smart-contract-buxbankrollsol)
2. [PlinkoGame.sol Changes](#2-plinkogamesol-changes)
3. [BUX Minter Service Changes](#3-bux-minter-service-changes)
4. [Backend: Elixir Modules](#4-backend-elixir-modules)
5. [UI: BankrollLive (Deposit/Withdraw/Charts)](#5-ui-bankrolllive)
6. [JavaScript: Chart Hook](#6-javascript-chart-hook)
7. [Price History Storage](#7-price-history-storage)
8. [Implementation Order](#8-implementation-order)
9. [File List](#9-file-list)
10. [Testing Plan](#10-testing-plan)

---

## 1. Smart Contract: BUXBankroll.sol

### Overview

New UUPS Proxy contract. ERC-20 LP token built-in (inherits ERC20Upgradeable, same pattern as ROGUEBankroll). Holds all BUX house funds. Authorizes game contracts to settle bets.

### Inheritance

```solidity
// Flattened contract (all OZ dependencies inlined, same pattern as ROGUEBankroll.sol)
// Must include: SafeERC20 library for IERC20 safe transfer wrappers
// Must include: PausableUpgradeable for emergency pause capability

BUXBankroll is Initializable, UUPSUpgradeable, OwnableUpgradeable,
              ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20Upgradeable {
    using SafeERC20 for IERC20;
```

> **Flattening note**: All OpenZeppelin dependencies (Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20Upgradeable, SafeERC20, IERC20) must be inlined into the .sol file for Roguescan verification, same approach as ROGUEBankroll.sol.
>
> **SafeERC20**: Required for all `safeTransfer` / `safeTransferFrom` calls on BUX token. Without this `using` directive, those calls will not compile.
>
> **PausableUpgradeable**: Enables emergency pause of deposits/withdrawals via `whenNotPaused` modifier.
>
> **OZ Version**: Use OZ v5 upgradeable contracts (matching BuxBoosterGame.sol). Key differences from OZ v4 (ROGUEBankroll.sol):
> - `__Ownable_init(msg.sender)` takes an explicit initial owner argument
> - `Initializable` uses `uint64` not `uint8` for version tracking
> - Custom errors instead of string reverts (e.g., `OwnableUnauthorizedAccount`)
> - Copy the flattened OZ v5 base contracts from BuxBoosterGame.sol (Initializable, ContextUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable, ERC1967Utils)
> - Additionally inline: ERC20Upgradeable (from OZ v5), SafeERC20, IERC20, IERC20Metadata

### Key Differences from ROGUEBankroll

| Aspect | ROGUEBankroll | BUXBankroll |
|--------|---------------|-------------|
| Asset type | Native ROGUE (msg.value) | ERC-20 BUX (transferFrom/transfer) |
| Deposit | `depositROGUE() payable` | `depositBUX(uint256 amount)` — requires prior approval |
| Withdrawal | Sends via `payable.call{value}` | Sends via `IERC20.safeTransfer` |
| Payout delivery | `payable(winner).call{value: payout}` | `buxToken.safeTransfer(winner, payout)` |
| Fallback on failed send | Credits `players[addr].rogue_balance` | Not needed — ERC-20 transfer reverts cleanly |
| Proxy type | Transparent Proxy (OZ v4) | UUPS Proxy (OZ v5, matches PlinkoGame) |
| NFT rewards | Sends ROGUE to NFTRewarder | Not applicable (NFT rewards are ROGUE-only) |
| Referral rewards | Sends ROGUE to referrer via native call | Sends BUX to referrer via safeTransfer from pool |

### Structs

```solidity
struct HouseBalance {
    uint256 totalBalance;       // Total BUX held (deposits + bet wagers)
    uint256 liability;          // Outstanding max payouts for active bets
    uint256 unsettledBets;      // Sum of wager amounts for unsettled bets
    uint256 netBalance;         // totalBalance - liability (available for new bets/withdrawals)
    uint256 poolTokenSupply;    // Cached LP-BUX totalSupply()
    uint256 poolTokenPrice;     // Cached LP price (18 decimals precision)
}

// Per-game stats (separate structs for each game)
struct PlinkoPlayerStats {
    uint256 totalBets;
    uint256 wins;
    uint256 losses;
    uint256 pushes;
    uint256 totalWagered;
    uint256 totalWinnings;
    uint256 totalLosses;
}

struct PlinkoAccounting {
    uint256 totalBets;
    uint256 totalWins;
    uint256 totalLosses;
    uint256 totalPushes;
    uint256 totalVolumeWagered;
    uint256 totalPayouts;
    int256 totalHouseProfit;
    uint256 largestWin;
    uint256 largestBet;
}
```

### Constants

```solidity
address public buxToken;                    // BUX ERC-20 address (set in initialize)
uint256 public constant MAX_BET_BPS = 10;   // 0.1% of net balance
uint256 public constant MULTIPLIER_DENOMINATOR = 10000;
```

### Storage Layout (UUPS — only add at END)

```
// Inherited: _initialized (uint64), _owner, _status (reentrancy), _paused
// Inherited ERC20: _balances, _allowances, _totalSupply, _name, _symbol

// BUXBankroll storage:
address buxToken                                          // BUX ERC-20 contract address
HouseBalance houseBalance                                 // Pool accounting
uint256 maximumBetSizeDivisor                             // Default 1000 (0.1%)

// Game authorization
address plinkoGame                                        // Authorized Plinko contract
// address buxBoosterGame                                 // Future: authorize BuxBooster

// Plinko stats
mapping(address => PlinkoPlayerStats) plinkoPlayerStats
PlinkoAccounting plinkoAccounting
mapping(address => uint256[9]) plinkoBetsPerConfig
mapping(address => int256[9]) plinkoPnLPerConfig

// Referral system (shared across all games)
uint256 referralBasisPoints                               // e.g. 20 = 0.2%
mapping(address => address) playerReferrers
uint256 totalReferralRewardsPaid
mapping(address => uint256) referrerTotalEarnings
address referralAdmin

// Price history (for chart snapshots)
uint256 lastPriceSnapshotTime
```

### Events

```solidity
// LP Token
event BUXDeposited(address indexed depositor, uint256 amountBUX, uint256 amountLP);
event BUXWithdrawn(address indexed withdrawer, uint256 amountBUX, uint256 amountLP);
event PoolPriceUpdated(uint256 newPrice, uint256 totalBalance, uint256 totalSupply, uint256 timestamp);

// Plinko Game
event PlinkoBetPlaced(address indexed player, bytes32 indexed commitmentHash,
                      uint256 amount, uint8 configIndex, uint256 nonce, uint256 timestamp);
event PlinkoWinningPayout(address indexed winner, bytes32 indexed commitmentHash,
                          uint256 betAmount, uint256 payout, uint256 profit);
event PlinkoWinDetails(bytes32 indexed commitmentHash, uint8 configIndex,
                       uint8 landingPosition, uint8[] path, uint256 nonce);
event PlinkoLosingBet(address indexed player, bytes32 indexed commitmentHash,
                      uint256 wagerAmount, uint256 partialPayout);
event PlinkoLossDetails(bytes32 indexed commitmentHash, uint8 configIndex,
                        uint8 landingPosition, uint8[] path, uint256 nonce);

// Referrals
event ReferralRewardPaid(bytes32 indexed commitmentHash, address indexed referrer,
                         address indexed player, uint256 amount);
event ReferrerSet(address indexed player, address indexed referrer);

// Admin
event GameAuthorized(address indexed game, bool authorized);
event MaxBetDivisorChanged(uint256 oldDivisor, uint256 newDivisor);
```

### Errors

```solidity
error UnauthorizedGame();
error InsufficientBalance();
error InsufficientLiquidity();
error ZeroAmount();
error ZeroAddress();
error TransferFailed();
```

### Functions

#### LP Token (Public)

```solidity
/// @notice Deposit BUX and receive LP-BUX tokens. Caller must approve BUXBankroll first.
function depositBUX(uint256 amount) external nonReentrant whenNotPaused {
    if (amount == 0) revert ZeroAmount();

    uint256 lpMinted;
    uint256 supply = totalSupply();

    if (supply == 0) {
        lpMinted = amount;  // 1:1 for first deposit
    } else {
        // IMPORTANT: Use (totalBalance - unsettledBets) as the "real" pool value
        // for LP pricing. unsettledBets are wager amounts that haven't been settled
        // yet — they inflate totalBalance but aren't realized profit/loss.
        // This matches _recalculateHouseBalance() which uses the same formula for poolTokenPrice.
        uint256 effectiveBalance = houseBalance.totalBalance - houseBalance.unsettledBets;
        lpMinted = (amount * supply) / effectiveBalance;
    }

    // Transfer BUX from depositor to this contract
    IERC20(buxToken).safeTransferFrom(msg.sender, address(this), amount);

    // Mint LP tokens to depositor
    _mint(msg.sender, lpMinted);

    // Update house balance
    houseBalance.totalBalance += amount;
    _recalculateHouseBalance();

    emit BUXDeposited(msg.sender, amount, lpMinted);
    emit PoolPriceUpdated(houseBalance.poolTokenPrice, houseBalance.totalBalance, totalSupply(), block.timestamp);
}

/// @notice Withdraw BUX by burning LP-BUX tokens.
/// @dev Uses netBalance (totalBalance - liability) to ensure withdrawals
///      cannot drain funds needed for outstanding bet payouts.
function withdrawBUX(uint256 lpAmount) external nonReentrant whenNotPaused {
    if (lpAmount == 0) revert ZeroAmount();
    if (balanceOf(msg.sender) < lpAmount) revert InsufficientBalance();

    uint256 supply = totalSupply();
    // Withdrawable amount based on net balance (respects outstanding liabilities)
    uint256 buxOut = (lpAmount * houseBalance.netBalance) / supply;
    if (buxOut > houseBalance.netBalance) revert InsufficientLiquidity();

    // Burn LP tokens
    _burn(msg.sender, lpAmount);

    // Transfer BUX to withdrawer
    IERC20(buxToken).safeTransfer(msg.sender, buxOut);

    // Update house balance
    houseBalance.totalBalance -= buxOut;
    _recalculateHouseBalance();

    emit BUXWithdrawn(msg.sender, buxOut, lpAmount);
    emit PoolPriceUpdated(houseBalance.poolTokenPrice, houseBalance.totalBalance, totalSupply(), block.timestamp);
}
```

#### Game Integration — Plinko (onlyPlinko)

```solidity
modifier onlyPlinko() {
    if (msg.sender != plinkoGame) revert UnauthorizedGame();
    _;
}

/// @notice Called by PlinkoGame when player places a BUX bet.
///         BUX is transferred from player to BUXBankroll by PlinkoGame before calling this.
function updateHouseBalancePlinkoBetPlaced(
    bytes32 commitmentHash,
    address player,
    uint256 wagerAmount,
    uint8 configIndex,
    uint256 nonce,
    uint256 maxPayout
) external onlyPlinko returns (bool) {
    houseBalance.totalBalance += wagerAmount;
    houseBalance.liability += maxPayout;
    houseBalance.unsettledBets += wagerAmount;
    _recalculateHouseBalance();

    emit PlinkoBetPlaced(player, commitmentHash, wagerAmount, configIndex, nonce, block.timestamp);
    return true;
}

/// @notice Settle a winning Plinko bet. Sends payout to winner.
function settlePlinkoWinningBet(
    address winner,
    bytes32 commitmentHash,
    uint256 betAmount,
    uint256 payout,
    uint8 configIndex,
    uint8 landingPosition,
    uint8[] calldata path,
    uint256 nonce,
    uint256 maxPayout
) external onlyPlinko nonReentrant returns (bool) {
    uint256 profit = payout - betAmount;

    // Transfer payout to winner
    IERC20(buxToken).safeTransfer(winner, payout);

    // Update house balance
    houseBalance.totalBalance -= payout;
    houseBalance.liability -= maxPayout;
    houseBalance.unsettledBets -= betAmount;
    _recalculateHouseBalance();

    // Update stats
    _updatePlinkoStatsWin(winner, betAmount, profit, configIndex);

    emit PlinkoWinningPayout(winner, commitmentHash, betAmount, payout, profit);
    emit PlinkoWinDetails(commitmentHash, configIndex, landingPosition, path, nonce);
    emit PoolPriceUpdated(houseBalance.poolTokenPrice, houseBalance.totalBalance, totalSupply(), block.timestamp);

    return true;
}

/// @notice Settle a losing Plinko bet. House keeps BUX. Sends partial payout if multiplier > 0.
function settlePlinkoLosingBet(
    address player,
    bytes32 commitmentHash,
    uint256 wagerAmount,
    uint256 partialPayout,
    uint8 configIndex,
    uint8 landingPosition,
    uint8[] calldata path,
    uint256 nonce,
    uint256 maxPayout
) external onlyPlinko nonReentrant returns (bool) {
    // Send partial payout if > 0 (e.g. 0.3x on a loss)
    if (partialPayout > 0) {
        IERC20(buxToken).safeTransfer(player, partialPayout);
        houseBalance.totalBalance -= partialPayout;
    }

    // Release liability
    houseBalance.liability -= maxPayout;
    houseBalance.unsettledBets -= wagerAmount;
    _recalculateHouseBalance();

    // Update stats
    uint256 lossAmount = wagerAmount - partialPayout;
    _updatePlinkoStatsLoss(player, wagerAmount, lossAmount, configIndex);

    // Referral reward on loss portion (non-blocking)
    if (lossAmount > 0) {
        _sendReferralReward(commitmentHash, player, lossAmount);
    }

    emit PlinkoLosingBet(player, commitmentHash, wagerAmount, partialPayout);
    emit PlinkoLossDetails(commitmentHash, configIndex, landingPosition, path, nonce);
    emit PoolPriceUpdated(houseBalance.poolTokenPrice, houseBalance.totalBalance, totalSupply(), block.timestamp);

    return true;
}

/// @notice Settle a push (payout == bet). Return exact amount, no house movement.
function settlePlinkoPushBet(
    address player,
    bytes32 commitmentHash,
    uint256 betAmount,
    uint8 configIndex,
    uint8 landingPosition,
    uint8[] calldata path,
    uint256 nonce,
    uint256 maxPayout
) external onlyPlinko nonReentrant returns (bool) {
    IERC20(buxToken).safeTransfer(player, betAmount);

    houseBalance.totalBalance -= betAmount;
    houseBalance.liability -= maxPayout;
    houseBalance.unsettledBets -= betAmount;
    _recalculateHouseBalance();

    // Update stats (push)
    plinkoPlayerStats[player].totalBets++;
    plinkoPlayerStats[player].pushes++;
    plinkoPlayerStats[player].totalWagered += betAmount;
    plinkoBetsPerConfig[player][configIndex]++;
    plinkoAccounting.totalBets++;
    plinkoAccounting.totalPushes++;
    plinkoAccounting.totalVolumeWagered += betAmount;

    emit PoolPriceUpdated(houseBalance.poolTokenPrice, houseBalance.totalBalance, totalSupply(), block.timestamp);

    return true;
}
```

#### View Functions

```solidity
function getHouseInfo() external view returns (
    uint256 totalBalance,
    uint256 liability,
    uint256 unsettledBets,
    uint256 netBalance,
    uint256 poolTokenSupply,
    uint256 poolTokenPrice
) {
    return (
        houseBalance.totalBalance,
        houseBalance.liability,
        houseBalance.unsettledBets,
        houseBalance.netBalance,
        houseBalance.poolTokenSupply,
        houseBalance.poolTokenPrice
    );
}

function getLPPrice() external view returns (uint256) {
    return houseBalance.poolTokenPrice;
}

function getMaxBet(uint8 configIndex, uint32 maxMultiplierBps) external view returns (uint256) {
    uint256 baseMaxBet = (houseBalance.netBalance * MAX_BET_BPS) / 10000;
    return (baseMaxBet * 20000) / maxMultiplierBps;
}

function getPlinkoAccounting() external view returns (
    uint256 totalBets,
    uint256 totalWins,
    uint256 totalLosses,
    uint256 totalPushes,
    uint256 totalVolumeWagered,
    uint256 totalPayouts,
    int256 totalHouseProfit,
    uint256 largestWin,
    uint256 largestBet,
    uint256 winRate,
    int256 houseEdge
) {
    PlinkoAccounting storage acc = plinkoAccounting;
    totalBets = acc.totalBets;
    totalWins = acc.totalWins;
    totalLosses = acc.totalLosses;
    totalPushes = acc.totalPushes;
    totalVolumeWagered = acc.totalVolumeWagered;
    totalPayouts = acc.totalPayouts;
    totalHouseProfit = acc.totalHouseProfit;
    largestWin = acc.largestWin;
    largestBet = acc.largestBet;
    winRate = acc.totalBets > 0 ? (acc.totalWins * 10000) / acc.totalBets : 0;
    houseEdge = acc.totalVolumeWagered > 0
        ? (acc.totalHouseProfit * 10000) / int256(acc.totalVolumeWagered) : int256(0);
}

function getPlinkoPlayerStats(address player) external view returns (
    uint256 totalBets,
    uint256 wins,
    uint256 losses,
    uint256 pushes,
    uint256 totalWagered,
    uint256 totalWinnings,
    uint256 totalLosses,
    uint256[9] memory betsPerConfig,
    int256[9] memory pnlPerConfig
) {
    PlinkoPlayerStats storage stats = plinkoPlayerStats[player];
    totalBets = stats.totalBets;
    wins = stats.wins;
    losses = stats.losses;
    pushes = stats.pushes;
    totalWagered = stats.totalWagered;
    totalWinnings = stats.totalWinnings;
    totalLosses = stats.totalLosses;
    betsPerConfig = plinkoBetsPerConfig[player];
    pnlPerConfig = plinkoPnLPerConfig[player];
}
```

#### Admin Functions (onlyOwner)

```solidity
function setPlinkoGame(address _plinkoGame) external onlyOwner {
    emit GameAuthorized(_plinkoGame, true);
    plinkoGame = _plinkoGame;
}

// Future: function setBuxBoosterGame(address _game) external onlyOwner;

function setMaxBetDivisor(uint256 _divisor) external onlyOwner {
    emit MaxBetDivisorChanged(maximumBetSizeDivisor, _divisor);
    maximumBetSizeDivisor = _divisor;
}

function setReferralBasisPoints(uint256 _bps) external onlyOwner {
    require(_bps <= 1000, "Basis points cannot exceed 10%");
    referralBasisPoints = _bps;
}

function setReferralAdmin(address _admin) external onlyOwner {
    referralAdmin = _admin;
}

function setPlayerReferrer(address player, address referrer) external {
    require(msg.sender == owner() || msg.sender == referralAdmin, "Not authorized");
    require(playerReferrers[player] == address(0), "Referrer already set");
    require(referrer != address(0), "Invalid referrer");
    require(player != referrer, "Self-referral not allowed");
    playerReferrers[player] = referrer;
    emit ReferrerSet(player, referrer);
}

function setPlayerReferrersBatch(address[] calldata players, address[] calldata referrers) external {
    require(msg.sender == owner() || msg.sender == referralAdmin, "Not authorized");
    require(players.length == referrers.length, "Array length mismatch");
    for (uint256 i = 0; i < players.length; i++) {
        if (playerReferrers[players[i]] == address(0) &&
            referrers[i] != address(0) &&
            players[i] != referrers[i]) {
            playerReferrers[players[i]] = referrers[i];
            emit ReferrerSet(players[i], referrers[i]);
        }
    }
}

/// @notice Emergency withdraw BUX to owner (only use if contract is broken)
function emergencyWithdrawBUX(uint256 amount) external onlyOwner {
    IERC20(buxToken).safeTransfer(owner(), amount);
    houseBalance.totalBalance -= amount;
    _recalculateHouseBalance();
}

/// @notice Pause/unpause deposits, withdrawals, and settlements
function setPaused(bool _paused) external onlyOwner {
    if (_paused) {
        _pause();
    } else {
        _unpause();
    }
}
```

#### Internal Functions

```solidity
function _recalculateHouseBalance() internal {
    houseBalance.netBalance = houseBalance.totalBalance - houseBalance.liability;
    houseBalance.poolTokenSupply = totalSupply();
    if (houseBalance.poolTokenSupply > 0) {
        houseBalance.poolTokenPrice =
            ((houseBalance.totalBalance - houseBalance.unsettledBets) * 1e18) / houseBalance.poolTokenSupply;
    } else {
        houseBalance.poolTokenPrice = 1e18;  // Default 1:1 when no supply
    }
}

function _sendReferralReward(bytes32 commitmentHash, address player, uint256 lossAmount) internal {
    if (referralBasisPoints == 0) return;
    address referrer = playerReferrers[player];
    if (referrer == address(0)) return;

    uint256 rewardAmount = (lossAmount * referralBasisPoints) / 10000;
    if (rewardAmount == 0) return;

    // Non-blocking: try-catch so settlement never fails due to referral
    // NOTE: Using safeTransfer (not transfer) for consistency. The try-catch
    // wraps the external call so a revert from safeTransfer is caught.
    try IERC20(buxToken).transfer(referrer, rewardAmount) returns (bool success) {
        if (success) {
            houseBalance.totalBalance -= rewardAmount;
            _recalculateHouseBalance();
            totalReferralRewardsPaid += rewardAmount;
            referrerTotalEarnings[referrer] += rewardAmount;
            emit ReferralRewardPaid(commitmentHash, referrer, player, rewardAmount);
        }
    } catch {
        // Silently skip — don't block settlement
    }
}

function _updatePlinkoStatsWin(address player, uint256 betAmount, uint256 profit, uint8 configIndex) internal {
    plinkoPlayerStats[player].totalBets++;
    plinkoPlayerStats[player].wins++;
    plinkoPlayerStats[player].totalWagered += betAmount;
    plinkoPlayerStats[player].totalWinnings += profit;
    plinkoBetsPerConfig[player][configIndex]++;
    plinkoPnLPerConfig[player][configIndex] += int256(profit);

    plinkoAccounting.totalBets++;
    plinkoAccounting.totalWins++;
    plinkoAccounting.totalVolumeWagered += betAmount;
    plinkoAccounting.totalPayouts += betAmount + profit;
    plinkoAccounting.totalHouseProfit -= int256(profit);
    if (profit > plinkoAccounting.largestWin) plinkoAccounting.largestWin = profit;
    if (betAmount > plinkoAccounting.largestBet) plinkoAccounting.largestBet = betAmount;
}

function _updatePlinkoStatsLoss(address player, uint256 betAmount, uint256 lossAmount, uint8 configIndex) internal {
    plinkoPlayerStats[player].totalBets++;
    plinkoPlayerStats[player].losses++;
    plinkoPlayerStats[player].totalWagered += betAmount;
    plinkoPlayerStats[player].totalLosses += lossAmount;
    plinkoBetsPerConfig[player][configIndex]++;
    plinkoPnLPerConfig[player][configIndex] -= int256(lossAmount);

    plinkoAccounting.totalBets++;
    plinkoAccounting.totalLosses++;
    plinkoAccounting.totalVolumeWagered += betAmount;
    if (betAmount > lossAmount) plinkoAccounting.totalPayouts += betAmount - lossAmount;
    plinkoAccounting.totalHouseProfit += int256(lossAmount);
    if (betAmount > plinkoAccounting.largestBet) plinkoAccounting.largestBet = betAmount;
}
```

### Initialization

```solidity
/// @custom:oz-upgrades-unsafe-allow constructor
constructor() {
    _disableInitializers();
}

function initialize(address _buxToken) initializer public {
    if (_buxToken == address(0)) revert ZeroAddress();

    __Ownable_init(msg.sender);      // OZ v5 style — explicit initial owner
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();
    __Pausable_init();
    __ERC20_init("BUX Bankroll", "LP-BUX");

    buxToken = _buxToken;
    maximumBetSizeDivisor = 1000;  // 0.1% max bet
    houseBalance.poolTokenPrice = 1e18;  // Initial 1:1
    referralBasisPoints = 20;  // 0.2% referral rate on losing bets (matches ROGUE)
}

function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

/// @notice Accept native token (ROGUE) sent to this contract. Not expected, but safe to include.
receive() external payable {}
```

> **IMPORTANT**: The `constructor() { _disableInitializers(); }` pattern prevents the implementation contract from being initialized directly (security best practice for UUPS proxies). ROGUEBankroll.sol and BuxBoosterGame.sol both use this same pattern.
>
> **OwnableUpgradeable**: Uses `__Ownable_init(msg.sender)` — the OZ v5 style where the initial owner is passed explicitly. This matches BuxBoosterGame.sol.

### Deployment Steps

1. Deploy BUXBankroll implementation contract
2. Deploy ERC1967Proxy pointing to BUXBankroll implementation, with `initialize(BUX_TOKEN_ADDRESS)` calldata
3. Deploy PlinkoGame proxy (Section 2)
4. Call `buxBankroll.setPlinkoGame(plinkoGameAddress)`
5. Call `plinkoGame.setBuxBankroll(buxBankrollAddress)`
6. Owner approves BUXBankroll to spend their BUX: `buxToken.approve(buxBankroll, amount)`
7. Owner deposits initial house BUX: `buxBankroll.depositBUX(initialAmount)`
8. Set referral config: `buxBankroll.setReferralBasisPoints(20)` (0.2% — matches ROGUE referral rate)
9. Set referral admin: `buxBankroll.setReferralAdmin(BUX_MINTER_WALLET)` (same admin as ROGUEBankroll)

---

## 2. PlinkoGame.sol Changes

### What Changes (BUX path only — ROGUE path unchanged)

**Removed from PlinkoGame:**
- `TokenConfig` struct's `houseBalance` field (keep `enabled` bool)
- `depositHouseBalance()` / `withdrawHouseBalance()` for BUX
- Direct BUX settlement transfers
- BUX referral reward logic (moved to BUXBankroll)
- `HouseDeposit` / `HouseWithdraw` events

**Added to PlinkoGame:**
- `address public buxBankroll` storage variable
- `address public buxToken` storage variable
- `setBuxBankroll(address)` admin function

**Changed in PlinkoGame:**

| Function | Before | After |
|----------|--------|-------|
| `placeBet` | `safeTransferFrom(player -> PlinkoGame)` | `safeTransferFrom(player -> BUXBankroll)` then call `buxBankroll.updateHouseBalancePlinkoBetPlaced()` |
| `settleBet` (win) | Deduct from local houseBalance, `safeTransfer(PlinkoGame -> player)` | Call `buxBankroll.settlePlinkoWinningBet(winner, ...)` |
| `settleBet` (loss) | Add to local houseBalance | Call `buxBankroll.settlePlinkoLosingBet(player, ...)` |
| `settleBet` (push) | Return from local balance | Call `buxBankroll.settlePlinkoPushBet(player, ...)` |
| `getMaxBet` | Uses `tokenConfigs[token].houseBalance` | Calls `buxBankroll.getMaxBet(configIndex, maxMultiplierBps)` |
| `configureToken` | Sets enabled + houseBalance | Only sets enabled flag (no houseBalance needed) |

**BUX-specific accounting (buxPlayerStats, buxAccounting):**
- Moved to BUXBankroll. PlinkoGame no longer tracks BUX stats directly.
- PlinkoGame still tracks: `totalBetsPlaced`, `totalBetsSettled`, bet records, commitment records.

**placeBet updated flow:**
```solidity
function placeBet(uint256 amount, uint8 configIndex, bytes32 commitmentHash) external nonReentrant whenNotPaused {
    // Validations (unchanged): configIndex, amount, commitment, etc.
    if (payoutTables[configIndex].length == 0) revert PayoutTableNotSet();

    // Validate commitment
    _validateCommitment(commitmentHash);

    uint256 maxPayout = calculateMaxPayout(amount, configIndex);

    // Check max bet against BUXBankroll limits
    uint256 maxBet = IBUXBankroll(buxBankroll).getMaxBet(configIndex, plinkoConfigs[configIndex].maxMultiplierBps);
    if (amount > maxBet) revert BetAmountTooHigh();

    // Transfer BUX from player directly to BUXBankroll
    IERC20(buxToken).safeTransferFrom(msg.sender, buxBankroll, amount);

    // Notify BUXBankroll of bet placement (updates liability tracking)
    IBUXBankroll(buxBankroll).updateHouseBalancePlinkoBetPlaced(
        commitmentHash, msg.sender, amount, configIndex,
        commitments[commitmentHash].nonce, maxPayout
    );

    // Create bet record
    bets[commitmentHash] = PlinkoBet({
        player: msg.sender,
        token: buxToken,
        amount: amount,
        configIndex: configIndex,
        commitmentHash: commitmentHash,
        nonce: commitments[commitmentHash].nonce,
        timestamp: block.timestamp,
        status: BetStatus.Pending
    });

    playerBetHistory[msg.sender].push(commitmentHash);
    totalBetsPlaced++;

    emit PlinkoBetPlaced(commitmentHash, msg.sender, buxToken, amount, configIndex);
}

function calculateMaxPayout(uint256 amount, uint8 configIndex) public view returns (uint256) {
    uint32 maxMult = plinkoConfigs[configIndex].maxMultiplierBps;
    return (amount * maxMult) / MULTIPLIER_DENOMINATOR;
}
```

**settleBet updated flow:**
```solidity
function settleBet(bytes32 commitmentHash, bytes32 serverSeed, uint8[] calldata path, uint8 landingPosition)
    external onlySettler nonReentrant
{
    PlinkoBet storage bet = bets[commitmentHash];
    if (bet.player == address(0)) revert BetNotFound();
    if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
    if (block.timestamp > bet.timestamp + BET_EXPIRY) revert BetExpiredError();

    // Path validation
    if (path.length != plinkoConfigs[bet.configIndex].rows) revert InvalidPath();
    uint8 computedPosition = 0;
    for (uint i = 0; i < path.length; i++) {
        if (path[i] > 1) revert InvalidPath();
        computedPosition += path[i];
    }
    if (computedPosition != landingPosition) revert InvalidPath();

    uint32 multiplierBps = payoutTables[bet.configIndex][landingPosition];
    uint256 payout = (bet.amount * multiplierBps) / MULTIPLIER_DENOMINATOR;
    uint256 maxPayout = calculateMaxPayout(bet.amount, bet.configIndex);

    if (payout > bet.amount) {
        // WIN
        bet.status = BetStatus.Won;
        IBUXBankroll(buxBankroll).settlePlinkoWinningBet(
            bet.player, commitmentHash, bet.amount, payout,
            bet.configIndex, landingPosition, path,
            commitments[commitmentHash].nonce, maxPayout
        );
    } else if (payout < bet.amount) {
        // LOSS (partialPayout is the payout value, e.g. 0.3x returns 0.3 * betAmount)
        bet.status = BetStatus.Lost;
        IBUXBankroll(buxBankroll).settlePlinkoLosingBet(
            bet.player, commitmentHash, bet.amount, payout,
            bet.configIndex, landingPosition, path,
            commitments[commitmentHash].nonce, maxPayout
        );
    } else {
        // PUSH (payout == bet amount, exactly 1.0x)
        bet.status = BetStatus.Push;
        IBUXBankroll(buxBankroll).settlePlinkoPushBet(
            bet.player, commitmentHash, bet.amount,
            bet.configIndex, landingPosition, path,
            commitments[commitmentHash].nonce, maxPayout
        );
    }

    // Reveal server seed
    commitments[commitmentHash].serverSeed = serverSeed;
    totalBetsSettled++;

    emit PlinkoBetSettled(commitmentHash, bet.player, bet.status, payout, serverSeed);
    emit PlinkoBallPath(commitmentHash, path, landingPosition, bet.configIndex);
}
```

**ROGUE path: No changes.** `placeBetROGUE` and `settleBetROGUE` still use ROGUEBankroll exactly as in the original plinko plan.

### IBUXBankroll Interface

```solidity
interface IBUXBankroll {
    function updateHouseBalancePlinkoBetPlaced(
        bytes32 commitmentHash, address player, uint256 wagerAmount,
        uint8 configIndex, uint256 nonce, uint256 maxPayout
    ) external returns (bool);

    function settlePlinkoWinningBet(
        address winner, bytes32 commitmentHash, uint256 betAmount, uint256 payout,
        uint8 configIndex, uint8 landingPosition, uint8[] calldata path,
        uint256 nonce, uint256 maxPayout
    ) external returns (bool);

    function settlePlinkoLosingBet(
        address player, bytes32 commitmentHash, uint256 wagerAmount, uint256 partialPayout,
        uint8 configIndex, uint8 landingPosition, uint8[] calldata path,
        uint256 nonce, uint256 maxPayout
    ) external returns (bool);

    function settlePlinkoPushBet(
        address player, bytes32 commitmentHash, uint256 betAmount,
        uint8 configIndex, uint8 landingPosition, uint8[] calldata path,
        uint256 nonce, uint256 maxPayout
    ) external returns (bool);

    function getMaxBet(uint8 configIndex, uint32 maxMultiplierBps) external view returns (uint256);
    function getHouseInfo() external view returns (uint256, uint256, uint256, uint256, uint256, uint256);
    function getLPPrice() external view returns (uint256);
}
```

---

## 3. BUX Minter Service Changes

### New Endpoints

| Method | Endpoint | Body/Params | Purpose |
|--------|----------|-------------|---------|
| GET | `/bux-bankroll/house-info` | — | Pool stats (total, liability, net, LP price, supply) |
| GET | `/bux-bankroll/lp-price` | — | Current LP-BUX price |
| GET | `/bux-bankroll/lp-balance/:address` | — | User's LP-BUX token balance |
| GET | `/bux-bankroll/max-bet/:configIndex` | — | Max BUX bet for Plinko config |
| GET | `/bux-bankroll/player-stats/:address` | — | Player's Plinko stats from BUXBankroll |
| GET | `/bux-bankroll/accounting` | — | Global Plinko accounting from BUXBankroll |

### Route Implementation

```javascript
// routes/bux-bankroll.js
const express = require('express');
const router = express.Router();

// Assumes buxBankrollContract is initialized in the parent module:
// const buxBankrollContract = new ethers.Contract(BUX_BANKROLL_ADDRESS, BUX_BANKROLL_ABI, provider);

router.get('/house-info', async (req, res) => {
  try {
    const info = await buxBankrollContract.getHouseInfo();
    res.json({
      totalBalance: info[0].toString(),
      liability: info[1].toString(),
      unsettledBets: info[2].toString(),
      netBalance: info[3].toString(),
      poolTokenSupply: info[4].toString(),
      poolTokenPrice: info[5].toString()
    });
  } catch (error) {
    console.error('[BUXBankroll] house-info error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

router.get('/lp-price', async (req, res) => {
  try {
    const price = await buxBankrollContract.getLPPrice();
    res.json({ price: price.toString() });
  } catch (error) {
    console.error('[BUXBankroll] lp-price error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

router.get('/lp-balance/:address', async (req, res) => {
  try {
    const { address } = req.params;
    const balance = await buxBankrollContract.balanceOf(address);
    res.json({ balance: balance.toString() });
  } catch (error) {
    console.error('[BUXBankroll] lp-balance error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

router.get('/max-bet/:configIndex', async (req, res) => {
  try {
    const { configIndex } = req.params;
    // PlinkoGame stores config with maxMultiplierBps
    const config = await plinkoContract.plinkoConfigs(configIndex);
    const maxBet = await buxBankrollContract.getMaxBet(configIndex, config.maxMultiplierBps);
    res.json({ maxBet: maxBet.toString() });
  } catch (error) {
    console.error('[BUXBankroll] max-bet error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

router.get('/player-stats/:address', async (req, res) => {
  try {
    const { address } = req.params;
    const stats = await buxBankrollContract.getPlinkoPlayerStats(address);
    res.json({
      totalBets: stats.totalBets.toString(),
      wins: stats.wins.toString(),
      losses: stats.losses.toString(),
      pushes: stats.pushes.toString(),
      totalWagered: stats.totalWagered.toString(),
      totalWinnings: stats.totalWinnings.toString(),
      totalLosses: stats.totalLosses.toString(),
      betsPerConfig: stats.betsPerConfig.map(b => b.toString()),
      pnlPerConfig: stats.pnlPerConfig.map(p => p.toString())
    });
  } catch (error) {
    console.error('[BUXBankroll] player-stats error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

router.get('/accounting', async (req, res) => {
  try {
    const acc = await buxBankrollContract.getPlinkoAccounting();
    res.json({
      totalBets: acc.totalBets.toString(),
      totalWins: acc.totalWins.toString(),
      totalLosses: acc.totalLosses.toString(),
      totalPushes: acc.totalPushes.toString(),
      totalVolumeWagered: acc.totalVolumeWagered.toString(),
      totalPayouts: acc.totalPayouts.toString(),
      totalHouseProfit: acc.totalHouseProfit.toString(),
      largestWin: acc.largestWin.toString(),
      largestBet: acc.largestBet.toString(),
      winRate: acc.winRate.toString(),
      houseEdge: acc.houseEdge.toString()
    });
  } catch (error) {
    console.error('[BUXBankroll] accounting error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
```

Register in `app.js`:
```javascript
const buxBankrollRoutes = require('./routes/bux-bankroll');
app.use('/bux-bankroll', authMiddleware, buxBankrollRoutes);
```

### Updated Plinko Settlement Endpoints

The existing `/plinko/settle-bet` endpoint stays the same — PlinkoGame.settleBet internally calls BUXBankroll. The BUX Minter just calls PlinkoGame; it doesn't interact with BUXBankroll for settlements.

### Updated Plinko House Balance

Change `/plinko/game-token-config/BUX` (or equivalent) to read from BUXBankroll instead of PlinkoGame:

```javascript
router.get('/game-token-config/:token', async (req, res) => {
  if (req.params.token === 'BUX') {
    // Read from BUXBankroll
    const info = await buxBankrollContract.getHouseInfo();
    res.json({ enabled: true, houseBalance: info[0].toString() });
  } else {
    // ROGUE - unchanged, reads from ROGUEBankroll
    // ...existing code...
  }
});
```

---

## 4. Backend: Elixir Modules

### 4.1 BuxMinter Additions (`lib/blockster_v2/bux_minter.ex`)

Add these functions to the existing `BlocksterV2.BuxMinter` module. They follow the same `http_get`/`get_minter_url`/`get_api_secret` patterns already used in the module.

```elixir
# ============ BUX Bankroll API Calls ============

@doc "Fetch pool stats from BUXBankroll contract via BUX Minter"
def bux_bankroll_house_info do
  minter_url = get_minter_url()
  headers = [{"content-type", "application/json"}, {"authorization", "Bearer #{get_api_secret()}"}]

  case http_get("#{minter_url}/bux-bankroll/house-info", headers) do
    {:ok, %{status_code: 200, body: body}} ->
      case Jason.decode(body) do
        {:ok, data} -> {:ok, data}
        {:error, _} -> {:error, "Failed to parse response"}
      end
    {:ok, %{status_code: status, body: body}} ->
      {:error, "HTTP #{status}: #{body}"}
    {:error, reason} ->
      {:error, inspect(reason)}
  end
end

@doc "Fetch current LP-BUX price from BUXBankroll"
def bux_bankroll_lp_price do
  minter_url = get_minter_url()
  headers = [{"content-type", "application/json"}, {"authorization", "Bearer #{get_api_secret()}"}]

  case http_get("#{minter_url}/bux-bankroll/lp-price", headers) do
    {:ok, %{status_code: 200, body: body}} ->
      case Jason.decode(body) do
        {:ok, %{"price" => price}} -> {:ok, price}
        _ -> {:error, "Failed to parse LP price"}
      end
    {:ok, %{status_code: status, body: body}} ->
      {:error, "HTTP #{status}: #{body}"}
    {:error, reason} ->
      {:error, inspect(reason)}
  end
end

@doc "Fetch user's LP-BUX token balance"
def bux_bankroll_lp_balance(wallet_address) do
  minter_url = get_minter_url()
  headers = [{"content-type", "application/json"}, {"authorization", "Bearer #{get_api_secret()}"}]

  case http_get("#{minter_url}/bux-bankroll/lp-balance/#{wallet_address}", headers) do
    {:ok, %{status_code: 200, body: body}} ->
      case Jason.decode(body) do
        {:ok, %{"balance" => balance}} -> {:ok, balance}
        _ -> {:error, "Failed to parse LP balance"}
      end
    {:ok, %{status_code: status, body: body}} ->
      {:error, "HTTP #{status}: #{body}"}
    {:error, reason} ->
      {:error, inspect(reason)}
  end
end

@doc "Fetch max BUX bet for a specific Plinko config"
def bux_bankroll_max_bet(config_index) do
  minter_url = get_minter_url()
  headers = [{"content-type", "application/json"}, {"authorization", "Bearer #{get_api_secret()}"}]

  case http_get("#{minter_url}/bux-bankroll/max-bet/#{config_index}", headers) do
    {:ok, %{status_code: 200, body: body}} ->
      case Jason.decode(body) do
        {:ok, %{"maxBet" => max_bet}} -> {:ok, max_bet}
        _ -> {:error, "Failed to parse max bet"}
      end
    {:ok, %{status_code: status, body: body}} ->
      {:error, "HTTP #{status}: #{body}"}
    {:error, reason} ->
      {:error, inspect(reason)}
  end
end

@doc "Fetch player's Plinko stats from BUXBankroll"
def bux_bankroll_player_stats(wallet_address) do
  minter_url = get_minter_url()
  headers = [{"content-type", "application/json"}, {"authorization", "Bearer #{get_api_secret()}"}]

  case http_get("#{minter_url}/bux-bankroll/player-stats/#{wallet_address}", headers) do
    {:ok, %{status_code: 200, body: body}} ->
      case Jason.decode(body) do
        {:ok, data} -> {:ok, data}
        _ -> {:error, "Failed to parse player stats"}
      end
    {:ok, %{status_code: status, body: body}} ->
      {:error, "HTTP #{status}: #{body}"}
    {:error, reason} ->
      {:error, inspect(reason)}
  end
end
```

### 4.2 LP Price Tracker (`lib/blockster_v2/lp_bux_price_tracker.ex`)

New GenServer (global singleton) that periodically fetches LP-BUX price and stores OHLC snapshots.

```elixir
defmodule BlocksterV2.LPBuxPriceTracker do
  @moduledoc """
  Periodically polls the BUXBankroll LP-BUX price and stores 5-minute OHLC candles
  in Mnesia. Broadcasts real-time price updates via PubSub for the BankrollLive chart.

  Uses GlobalSingleton for safe registration during rolling deploys.
  """
  use GenServer
  require Logger

  @poll_interval 60_000        # Fetch price every 60 seconds
  @candle_interval 300         # 5-minute candles (in seconds)

  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} ->
        Logger.info("[LPBuxPriceTracker] Already running on #{node(pid)}")
        :ignore
    end
  end

  @impl true
  def init(_opts) do
    # Don't poll immediately if we lost the global registration race
    if Process.whereis(__MODULE__) == self() || :global.whereis_name(__MODULE__) == self() do
      schedule_poll()
    end

    {:ok, %{current_candle: nil, candle_start: nil}}
  end

  @impl true
  def handle_info(:poll_price, state) do
    state =
      case BlocksterV2.BuxMinter.bux_bankroll_lp_price() do
        {:ok, price_str} ->
          price = parse_price(price_str)
          new_state = update_candle(state, price)
          broadcast_price(price, new_state)
          new_state

        {:error, reason} ->
          Logger.warning("[LPBuxPriceTracker] Failed to fetch price: #{inspect(reason)}")
          state
      end

    schedule_poll()
    {:noreply, state}
  end

  # ============ Candle Management ============

  defp update_candle(state, price) do
    now = System.system_time(:second)
    candle_start = div(now, @candle_interval) * @candle_interval

    if state.candle_start == candle_start and state.current_candle != nil do
      # Update existing candle
      candle = state.current_candle
      updated = %{candle |
        high: max(candle.high, price),
        low: min(candle.low, price),
        close: price
      }
      %{state | current_candle: updated}
    else
      # Save previous candle to Mnesia and start new one
      if state.current_candle do
        save_candle(state.current_candle)
      end

      new_candle = %{
        timestamp: candle_start,
        open: price,
        high: price,
        low: price,
        close: price
      }
      %{state | current_candle: new_candle, candle_start: candle_start}
    end
  end

  defp save_candle(candle) do
    record = {:lp_bux_candles, candle.timestamp, candle.open, candle.high,
              candle.low, candle.close}
    :mnesia.dirty_write(record)
  end

  defp broadcast_price(price, state) do
    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "lp_bux_price", {
      :lp_bux_price_updated,
      %{price: price, candle: state.current_candle}
    })
  end

  defp schedule_poll do
    Process.send_after(self(), :poll_price, @poll_interval)
  end

  defp parse_price(price_str) when is_binary(price_str) do
    case Integer.parse(price_str) do
      {price_int, _} -> price_int / 1.0e18
      :error -> 1.0
    end
  end
  defp parse_price(price) when is_integer(price), do: price / 1.0e18
  defp parse_price(price) when is_float(price), do: price

  # ============ Public API ============

  @doc "Get the current LP-BUX price (fetches fresh from chain)"
  def get_current_price do
    case BlocksterV2.BuxMinter.bux_bankroll_lp_price() do
      {:ok, price_str} -> {:ok, parse_price(price_str)}
      error -> error
    end
  end

  @doc """
  Get OHLC candles aggregated to the requested timeframe.

  Parameters:
    - timeframe_seconds: Target candle duration (e.g. 3600 for 1-hour candles)
    - count: Number of candles to return

  Returns a sorted list of %{time: unix_ts, open: f, high: f, low: f, close: f}
  """
  def get_candles(timeframe_seconds, count \\ 100) do
    now = System.system_time(:second)
    # Calculate how far back we need to go: count candles * timeframe
    cutoff = now - (timeframe_seconds * count)

    :mnesia.dirty_select(:lp_bux_candles, [
      {{:lp_bux_candles, :"$1", :"$2", :"$3", :"$4", :"$5"},
       [{:>=, :"$1", cutoff}],
       [{{:"$1", :"$2", :"$3", :"$4", :"$5"}}]}
    ])
    |> Enum.sort_by(&elem(&1, 0))
    |> aggregate_candles(timeframe_seconds)
  end

  @doc "Get high/low price stats for common timeframes"
  def get_stats do
    now = System.system_time(:second)

    %{
      price_1h: get_high_low(now - 3600, now),
      price_24h: get_high_low(now - 86400, now),
      price_7d: get_high_low(now - 604_800, now),
      price_30d: get_high_low(now - 2_592_000, now),
      price_all: get_high_low(0, now)
    }
  end

  defp get_high_low(from_ts, to_ts) do
    candles = :mnesia.dirty_select(:lp_bux_candles, [
      {{:lp_bux_candles, :"$1", :"$2", :"$3", :"$4", :"$5"},
       [{:>=, :"$1", from_ts}, {:"=<", :"$1", to_ts}],
       [{{:"$3", :"$4"}}]}  # Select {high, low}
    ])

    case candles do
      [] -> %{high: nil, low: nil}
      _ ->
        highs = Enum.map(candles, &elem(&1, 0))
        lows = Enum.map(candles, &elem(&1, 1))
        %{high: Enum.max(highs), low: Enum.min(lows)}
    end
  end

  defp aggregate_candles(base_candles, target_seconds) do
    base_candles
    |> Enum.group_by(fn {ts, _, _, _, _} ->
      div(ts, target_seconds) * target_seconds
    end)
    |> Enum.map(fn {group_ts, candles} ->
      # Sort candles within group by timestamp for correct open/close
      sorted = Enum.sort_by(candles, &elem(&1, 0))
      {_, first_open, _, _, _} = List.first(sorted)
      {_, _, _, _, last_close} = List.last(sorted)
      highs = Enum.map(candles, &elem(&1, 2))
      lows = Enum.map(candles, &elem(&1, 3))

      %{
        time: group_ts,
        open: first_open,
        high: Enum.max(highs),
        low: Enum.min(lows),
        close: last_close
      }
    end)
    |> Enum.sort_by(& &1.time)
  end
end
```

### 4.3 Mnesia Table: `:lp_bux_candles`

Add to `@tables` list in `lib/blockster_v2/mnesia_initializer.ex`:

```elixir
# LP-BUX price candles for bankroll dashboard chart
%{
  name: :lp_bux_candles,
  type: :ordered_set,
  attributes: [:timestamp, :open, :high, :low, :close],
  index: []
}
```

5-minute candle resolution. Aggregated to larger timeframes on read. `ordered_set` ensures candles are sorted by timestamp for efficient range queries.

### 4.4 Application.ex Addition

Add to the `genserver_children` list in `lib/blockster_v2/application.ex`:

```elixir
# LP-BUX price tracker (polls BUXBankroll price every 60s, stores candles)
{BlocksterV2.LPBuxPriceTracker, []},
```

> **NOTE**: The module itself calls `GlobalSingleton.start_link` internally (same pattern as PriceTracker, BuxBoosterBetSettler, etc.). Do NOT wrap it in `{GlobalSingleton, ...}` — just add the module directly.

---

## 5. UI: BankrollLive

### Route

Add to the `:default` live_session in `lib/blockster_v2_web/router.ex`:

```elixir
live "/bankroll", BankrollLive, :index
```

### LiveView: `lib/blockster_v2_web/live/bankroll_live.ex`

```elixir
defmodule BlocksterV2Web.BankrollLive do
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.{BuxMinter, EngagementTracker, LPBuxPriceTracker}

  @timeframes %{
    "1h" => {300, 12},       # 5-min candles, 12 candles
    "24h" => {3600, 24},     # 1-hour candles, 24 candles
    "7d" => {14400, 42},     # 4-hour candles, 42 candles
    "30d" => {86400, 30},    # 1-day candles, 30 candles
    "all" => {86400, 365}    # 1-day candles, up to 365 candles
  }

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "lp_bux_price")
      if current_user, do: Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:#{current_user.id}")
    end

    balances = if current_user, do: EngagementTracker.get_user_token_balances(current_user.id), else: %{}

    socket =
      socket
      |> assign(page_title: "BUX Bankroll")
      |> assign(current_user: current_user)
      |> assign(balances: balances)
      # Pool info
      |> assign(pool_total: 0, pool_net: 0, pool_liability: 0, pool_unsettled: 0)
      |> assign(lp_supply: 0, lp_price: 1.0)
      |> assign(lp_user_balance: 0)
      # Price stats
      |> assign(stats: %{})
      # Chart
      |> assign(selected_timeframe: "24h")
      |> assign(candles: [])
      # Deposit/Withdraw
      |> assign(deposit_amount: "", withdraw_amount: "")
      |> assign(action_loading: false, action_error: nil, action_success: nil)

    socket = if connected?(socket) do
      wallet_address = if current_user, do: current_user.smart_wallet_address, else: nil

      socket
      |> start_async(:fetch_pool_info, fn -> BuxMinter.bux_bankroll_house_info() end)
      |> start_async(:fetch_candles, fn -> LPBuxPriceTracker.get_candles(3600, 24) end)
      |> start_async(:fetch_stats, fn -> LPBuxPriceTracker.get_stats() end)
      |> then(fn s ->
        if wallet_address do
          start_async(s, :fetch_lp_balance, fn -> BuxMinter.bux_bankroll_lp_balance(wallet_address) end)
        else
          s
        end
      end)
    else
      socket
    end

    {:ok, socket}
  end

  # ============ Async Result Handlers ============

  @impl true
  def handle_async(:fetch_pool_info, {:ok, {:ok, data}}, socket) do
    total = parse_wei(data["totalBalance"])
    net = parse_wei(data["netBalance"])
    liability = parse_wei(data["liability"])
    unsettled = parse_wei(data["unsettledBets"])
    supply = parse_wei(data["poolTokenSupply"])
    price = parse_wei(data["poolTokenPrice"])

    {:noreply,
     socket
     |> assign(pool_total: total, pool_net: net, pool_liability: liability, pool_unsettled: unsettled)
     |> assign(lp_supply: supply, lp_price: price)}
  end

  def handle_async(:fetch_pool_info, {:ok, {:error, _}}, socket), do: {:noreply, socket}
  def handle_async(:fetch_pool_info, {:exit, _}, socket), do: {:noreply, socket}

  def handle_async(:fetch_candles, {:ok, candles}, socket) when is_list(candles) do
    {:noreply, socket |> assign(candles: candles) |> push_event("set_candles", %{candles: candles})}
  end

  def handle_async(:fetch_candles, _, socket), do: {:noreply, socket}

  def handle_async(:fetch_stats, {:ok, stats}, socket) when is_map(stats) do
    {:noreply, assign(socket, stats: stats)}
  end

  def handle_async(:fetch_stats, _, socket), do: {:noreply, socket}

  def handle_async(:fetch_lp_balance, {:ok, {:ok, balance_str}}, socket) do
    {:noreply, assign(socket, lp_user_balance: parse_wei(balance_str))}
  end

  def handle_async(:fetch_lp_balance, _, socket), do: {:noreply, socket}

  # Refresh pool info after deposit/withdraw
  def handle_async(:refresh_pool_info, {:ok, {:ok, data}}, socket) do
    total = parse_wei(data["totalBalance"])
    net = parse_wei(data["netBalance"])
    liability = parse_wei(data["liability"])
    unsettled = parse_wei(data["unsettledBets"])
    supply = parse_wei(data["poolTokenSupply"])
    price = parse_wei(data["poolTokenPrice"])

    {:noreply,
     socket
     |> assign(pool_total: total, pool_net: net, pool_liability: liability, pool_unsettled: unsettled)
     |> assign(lp_supply: supply, lp_price: price)
     |> assign(action_loading: false)}
  end

  def handle_async(:refresh_pool_info, _, socket), do: {:noreply, assign(socket, action_loading: false)}

  def handle_async(:refresh_lp_balance, {:ok, {:ok, balance_str}}, socket) do
    {:noreply, assign(socket, lp_user_balance: parse_wei(balance_str))}
  end

  def handle_async(:refresh_lp_balance, _, socket), do: {:noreply, socket}

  # ============ Event Handlers ============

  @impl true
  def handle_event("select_timeframe", %{"timeframe" => timeframe}, socket) do
    {candle_seconds, count} = Map.get(@timeframes, timeframe, {3600, 24})

    socket =
      socket
      |> assign(selected_timeframe: timeframe)
      |> start_async(:fetch_candles, fn -> LPBuxPriceTracker.get_candles(candle_seconds, count) end)

    {:noreply, socket}
  end

  def handle_event("update_deposit_amount", %{"value" => value}, socket) do
    {:noreply, assign(socket, deposit_amount: value, action_error: nil, action_success: nil)}
  end

  def handle_event("update_withdraw_amount", %{"value" => value}, socket) do
    {:noreply, assign(socket, withdraw_amount: value, action_error: nil, action_success: nil)}
  end

  def handle_event("deposit_bux", _params, socket) do
    amount = parse_input_amount(socket.assigns.deposit_amount)

    cond do
      amount <= 0 ->
        {:noreply, assign(socket, action_error: "Enter a valid amount")}

      socket.assigns.current_user == nil ->
        {:noreply, assign(socket, action_error: "Please log in to deposit")}

      true ->
        # Push to JS hook for on-chain transaction
        socket =
          socket
          |> assign(action_loading: true, action_error: nil, action_success: nil)
          |> push_event("deposit_bux", %{amount: amount})

        {:noreply, socket}
    end
  end

  def handle_event("withdraw_bux", _params, socket) do
    lp_amount = parse_input_amount(socket.assigns.withdraw_amount)

    cond do
      lp_amount <= 0 ->
        {:noreply, assign(socket, action_error: "Enter a valid amount")}

      socket.assigns.current_user == nil ->
        {:noreply, assign(socket, action_error: "Please log in to withdraw")}

      true ->
        socket =
          socket
          |> assign(action_loading: true, action_error: nil, action_success: nil)
          |> push_event("withdraw_bux", %{lp_amount: lp_amount})

        {:noreply, socket}
    end
  end

  # JS hook pushes back after on-chain tx
  def handle_event("deposit_confirmed", %{"tx_hash" => tx_hash}, socket) do
    wallet = socket.assigns.current_user.smart_wallet_address

    socket =
      socket
      |> assign(action_success: "Deposit confirmed! TX: #{String.slice(tx_hash, 0, 10)}...")
      |> assign(deposit_amount: "")
      |> start_async(:refresh_pool_info, fn -> BuxMinter.bux_bankroll_house_info() end)
      |> start_async(:refresh_lp_balance, fn -> BuxMinter.bux_bankroll_lp_balance(wallet) end)

    # Also sync BUX balance
    if wallet, do: BuxMinter.sync_user_balances_async(socket.assigns.current_user.id, wallet)

    {:noreply, socket}
  end

  def handle_event("deposit_failed", %{"error" => error}, socket) do
    {:noreply, assign(socket, action_loading: false, action_error: error)}
  end

  def handle_event("withdraw_confirmed", %{"tx_hash" => tx_hash}, socket) do
    wallet = socket.assigns.current_user.smart_wallet_address

    socket =
      socket
      |> assign(action_success: "Withdrawal confirmed! TX: #{String.slice(tx_hash, 0, 10)}...")
      |> assign(withdraw_amount: "")
      |> start_async(:refresh_pool_info, fn -> BuxMinter.bux_bankroll_house_info() end)
      |> start_async(:refresh_lp_balance, fn -> BuxMinter.bux_bankroll_lp_balance(wallet) end)

    if wallet, do: BuxMinter.sync_user_balances_async(socket.assigns.current_user.id, wallet)

    {:noreply, socket}
  end

  def handle_event("withdraw_failed", %{"error" => error}, socket) do
    {:noreply, assign(socket, action_loading: false, action_error: error)}
  end

  # ============ PubSub Handlers ============

  @impl true
  def handle_info({:lp_bux_price_updated, %{price: price, candle: candle}}, socket) do
    socket =
      socket
      |> assign(lp_price: price)

    socket = if candle do
      push_event(socket, "update_candle", %{candle: candle})
    else
      socket
    end

    {:noreply, socket}
  end

  def handle_info({:bux_balance_updated, balances}, socket) do
    {:noreply, assign(socket, balances: balances)}
  end

  # Catch-all for unknown messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============ Helpers ============

  defp parse_wei(nil), do: 0.0
  defp parse_wei(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int / 1.0e18
      :error -> 0.0
    end
  end
  defp parse_wei(val) when is_integer(val), do: val / 1.0e18
  defp parse_wei(val) when is_float(val), do: val

  defp parse_input_amount(""), do: 0
  defp parse_input_amount(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> trunc(f)
      :error ->
        case Integer.parse(val) do
          {i, _} -> i
          :error -> 0
        end
    end
  end
  defp parse_input_amount(val) when is_number(val), do: trunc(val)

  defp deposit_preview(amount, lp_price) when is_number(amount) and lp_price > 0 do
    Float.round(amount / lp_price, 2)
  end
  defp deposit_preview(_, _), do: 0.0

  defp withdraw_preview(lp_amount, lp_price) when is_number(lp_amount) do
    Float.round(lp_amount * lp_price, 2)
  end
  defp withdraw_preview(_, _), do: 0.0

  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(_), do: "0"

  # ============ Template ============

  @impl true
  def render(assigns) do
    ~H"""
    <div id="bankroll-page" class="max-w-6xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-haas_medium_65 text-white mb-8">BUX Bankroll</h1>

      <%!-- Pool Stats Card --%>
      <div class="bg-zinc-900 rounded-xl border border-zinc-800 p-6 mb-6">
        <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
          <div>
            <p class="text-xs text-zinc-500 uppercase tracking-wider">Total BUX</p>
            <p class="text-lg font-haas_medium_65 text-white"><%= format_number(@pool_total) %></p>
          </div>
          <div>
            <p class="text-xs text-zinc-500 uppercase tracking-wider">Net Balance</p>
            <p class="text-lg font-haas_medium_65 text-white"><%= format_number(@pool_net) %></p>
          </div>
          <div>
            <p class="text-xs text-zinc-500 uppercase tracking-wider">LP-BUX Supply</p>
            <p class="text-lg font-haas_medium_65 text-white"><%= format_number(@lp_supply) %></p>
          </div>
          <div>
            <p class="text-xs text-zinc-500 uppercase tracking-wider">LP Price</p>
            <p class="text-lg font-haas_medium_65 text-[#CAFC00]"><%= format_number(@lp_price) %> BUX</p>
          </div>
          <div>
            <p class="text-xs text-zinc-500 uppercase tracking-wider">Active Bets</p>
            <p class="text-lg font-haas_medium_65 text-white"><%= format_number(@pool_unsettled) %></p>
          </div>
        </div>
      </div>

      <%!-- Price Stats --%>
      <%= if map_size(@stats) > 0 do %>
        <div class="bg-zinc-900 rounded-xl border border-zinc-800 p-4 mb-6">
          <div class="grid grid-cols-5 gap-3 text-center">
            <%= for {label, key} <- [{"1H", :price_1h}, {"24H", :price_24h}, {"7D", :price_7d}, {"30D", :price_30d}, {"ALL", :price_all}] do %>
              <div>
                <p class="text-xs text-zinc-500 mb-1"><%= label %></p>
                <p class="text-xs text-green-400">H: <%= format_number((@stats[key] || %{})[:high]) %></p>
                <p class="text-xs text-red-400">L: <%= format_number((@stats[key] || %{})[:low]) %></p>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Chart --%>
      <div class="bg-zinc-900 rounded-xl border border-zinc-800 p-4 mb-6">
        <div class="flex gap-2 mb-4">
          <%= for tf <- ["1h", "24h", "7d", "30d", "all"] do %>
            <button
              phx-click="select_timeframe"
              phx-value-timeframe={tf}
              class={"px-3 py-1 rounded text-sm cursor-pointer " <>
                if(@selected_timeframe == tf, do: "bg-[#CAFC00] text-black font-medium", else: "bg-zinc-800 text-zinc-400 hover:bg-zinc-700")}
            >
              <%= String.upcase(tf) %>
            </button>
          <% end %>
        </div>
        <div id="lp-bux-chart" phx-hook="LPBuxChart" class="w-full h-[400px]"></div>
      </div>

      <%!-- Deposit / Withdraw --%>
      <%= if @current_user do %>
        <div id="bankroll-onchain" phx-hook="BankrollOnchain" class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
          <%!-- Deposit Card --%>
          <div class="bg-zinc-900 rounded-xl border border-zinc-800 p-6">
            <h3 class="text-lg font-haas_medium_65 text-white mb-4">Deposit BUX</h3>
            <p class="text-sm text-zinc-400 mb-2">
              Balance: <%= format_number(Map.get(@balances, "BUX", 0)) %> BUX
            </p>
            <input
              type="number"
              value={@deposit_amount}
              phx-keyup="update_deposit_amount"
              phx-key=""
              placeholder="Amount to deposit"
              class="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-4 py-3 text-white mb-3 focus:border-[#CAFC00] focus:ring-1 focus:ring-[#CAFC00] outline-none"
            />
            <p class="text-sm text-zinc-500 mb-4">
              You receive: ~<%= deposit_preview(parse_input_amount(@deposit_amount), @lp_price) %> LP-BUX
            </p>
            <button
              phx-click="deposit_bux"
              disabled={@action_loading}
              class="w-full bg-[#CAFC00] text-black font-haas_medium_65 py-3 rounded-lg cursor-pointer hover:bg-[#b8e600] disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <%= if @action_loading, do: "Processing...", else: "DEPOSIT" %>
            </button>
          </div>

          <%!-- Withdraw Card --%>
          <div class="bg-zinc-900 rounded-xl border border-zinc-800 p-6">
            <h3 class="text-lg font-haas_medium_65 text-white mb-4">Withdraw LP-BUX</h3>
            <p class="text-sm text-zinc-400 mb-2">
              LP Balance: <%= format_number(@lp_user_balance) %> LP-BUX
            </p>
            <input
              type="number"
              value={@withdraw_amount}
              phx-keyup="update_withdraw_amount"
              phx-key=""
              placeholder="LP-BUX to burn"
              class="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-4 py-3 text-white mb-3 focus:border-[#CAFC00] focus:ring-1 focus:ring-[#CAFC00] outline-none"
            />
            <p class="text-sm text-zinc-500 mb-4">
              You receive: ~<%= withdraw_preview(parse_input_amount(@withdraw_amount), @lp_price) %> BUX
            </p>
            <button
              phx-click="withdraw_bux"
              disabled={@action_loading}
              class="w-full bg-zinc-700 text-white font-haas_medium_65 py-3 rounded-lg cursor-pointer hover:bg-zinc-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <%= if @action_loading, do: "Processing...", else: "WITHDRAW" %>
            </button>
          </div>
        </div>

        <%!-- Success/Error messages --%>
        <%= if @action_success do %>
          <div class="bg-green-900/30 border border-green-800 rounded-lg p-4 mb-4 text-green-400 text-sm">
            <%= @action_success %>
          </div>
        <% end %>
        <%= if @action_error do %>
          <div class="bg-red-900/30 border border-red-800 rounded-lg p-4 mb-4 text-red-400 text-sm">
            <%= @action_error %>
          </div>
        <% end %>
      <% else %>
        <div class="bg-zinc-900 rounded-xl border border-zinc-800 p-8 text-center">
          <p class="text-zinc-400 mb-4">Log in to deposit BUX and earn LP-BUX tokens</p>
          <a href="/login" class="inline-block bg-[#CAFC00] text-black font-haas_medium_65 px-6 py-3 rounded-lg cursor-pointer hover:bg-[#b8e600] transition-colors">
            Log In
          </a>
        </div>
      <% end %>
    </div>
    """
  end
end
```

### Socket Assigns

| Assign | Type | Default | Description |
|--------|------|---------|-------------|
| `pool_total` | float | 0.0 | Total BUX in pool (human-readable, divided by 1e18) |
| `pool_net` | float | 0.0 | Net balance (available) |
| `pool_liability` | float | 0.0 | Outstanding bet liabilities |
| `pool_unsettled` | float | 0.0 | Unsettled bet wagers |
| `lp_supply` | float | 0.0 | Total LP-BUX supply |
| `lp_price` | float | 1.0 | Current LP-BUX price in BUX |
| `lp_user_balance` | float | 0.0 | User's LP-BUX token balance |
| `stats` | map | %{} | High/low stats per timeframe |
| `selected_timeframe` | string | "24h" | Active chart timeframe |
| `candles` | list | [] | OHLC data for chart |
| `deposit_amount` | string | "" | Amount to deposit (text input) |
| `withdraw_amount` | string | "" | LP amount to withdraw (text input) |
| `action_loading` | boolean | false | Deposit/withdraw in progress |
| `action_error` | string | nil | Error message |
| `action_success` | string | nil | Success message |

---

## 6. JavaScript: Chart Hook

### Install Dependency

```bash
cd assets && npm install lightweight-charts
```

### Hook: `assets/js/lp_bux_chart.js`

```javascript
import { createChart, CandlestickSeries } from 'lightweight-charts';

export const LPBuxChart = {
  mounted() {
    this.chart = createChart(this.el, {
      width: this.el.clientWidth,
      height: 400,
      layout: {
        background: { color: '#18181b' },  // zinc-900
        textColor: '#a1a1aa',              // zinc-400
      },
      grid: {
        vertLines: { color: '#27272a' },   // zinc-800
        horzLines: { color: '#27272a' },
      },
      crosshair: { mode: 0 },
      timeScale: {
        timeVisible: true,
        secondsVisible: false,
        borderColor: '#3f3f46',
      },
      rightPriceScale: {
        borderColor: '#3f3f46',
      },
    });

    this.candleSeries = this.chart.addSeries(CandlestickSeries, {
      upColor: '#CAFC00',      // brand lime for up candles
      downColor: '#ef4444',    // red for down candles
      borderUpColor: '#CAFC00',
      borderDownColor: '#ef4444',
      wickUpColor: '#CAFC00',
      wickDownColor: '#ef4444',
    });

    // Handle initial candle data from LiveView
    this.handleEvent("set_candles", ({ candles }) => {
      if (!candles || candles.length === 0) return;

      const data = candles.map(c => ({
        time: c.time,
        open: c.open,
        high: c.high,
        low: c.low,
        close: c.close,
      }));
      this.candleSeries.setData(data);
      this.chart.timeScale().fitContent();
    });

    // Handle real-time candle updates
    this.handleEvent("update_candle", ({ candle }) => {
      if (!candle) return;

      this.candleSeries.update({
        time: candle.time || candle.timestamp,
        open: candle.open,
        high: candle.high,
        low: candle.low,
        close: candle.close,
      });
    });

    // Responsive resize
    this.resizeObserver = new ResizeObserver(entries => {
      const { width } = entries[0].contentRect;
      this.chart.applyOptions({ width });
    });
    this.resizeObserver.observe(this.el);
  },

  destroyed() {
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.chart) this.chart.remove();
  }
};
```

### Hook: `assets/js/bankroll_onchain.js`

```javascript
import { getContract, prepareContractCall, sendTransaction, readContract } from "thirdweb";
import { approve } from "thirdweb/extensions/erc20";

const BUX_BANKROLL_ADDRESS = "0x<DEPLOYED>";  // Set after deployment
const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";

// Approval cache key (same pattern as BuxBoosterOnchain)
const APPROVAL_CACHE_KEY = `bux_bankroll_approved_${BUX_BANKROLL_ADDRESS}`;

export const BankrollOnchain = {
  mounted() {
    this.handleEvent("deposit_bux", ({ amount }) => this.deposit(amount));
    this.handleEvent("withdraw_bux", ({ lp_amount }) => this.withdraw(lp_amount));
  },

  async deposit(amount) {
    try {
      if (!window.smartAccount) {
        this.pushEvent("deposit_failed", { error: "Wallet not connected" });
        return;
      }

      const amountWei = BigInt(amount) * BigInt(10 ** 18);

      // Check approval cache first (same pattern as BuxBoosterOnchain)
      const cachedApproval = localStorage.getItem(APPROVAL_CACHE_KEY);
      let needsApproval = !cachedApproval;

      if (!needsApproval) {
        // Verify cached approval is still valid
        const buxContract = getContract({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          address: BUX_TOKEN_ADDRESS,
        });

        const allowance = await readContract({
          contract: buxContract,
          method: "function allowance(address, address) view returns (uint256)",
          params: [window.smartAccount.address, BUX_BANKROLL_ADDRESS],
        });

        needsApproval = BigInt(allowance) < amountWei;
      }

      if (needsApproval) {
        const buxContract = getContract({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          address: BUX_TOKEN_ADDRESS,
        });

        const approveTx = approve({
          contract: buxContract,
          spender: BUX_BANKROLL_ADDRESS,
          amountWei: BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
        });
        await sendTransaction({ transaction: approveTx, account: window.smartAccount });
        localStorage.setItem(APPROVAL_CACHE_KEY, "true");
      }

      // Call depositBUX
      const bankrollContract = getContract({
        client: window.thirdwebClient,
        chain: window.rogueChain,
        address: BUX_BANKROLL_ADDRESS,
      });

      const tx = prepareContractCall({
        contract: bankrollContract,
        method: "function depositBUX(uint256 amount)",
        params: [amountWei],
      });

      const receipt = await sendTransaction({ transaction: tx, account: window.smartAccount });
      this.pushEvent("deposit_confirmed", { tx_hash: receipt.transactionHash });

    } catch (error) {
      console.error("[BankrollOnchain] Deposit failed:", error);
      this.pushEvent("deposit_failed", { error: error.message?.slice(0, 200) || "Transaction failed" });
    }
  },

  async withdraw(lpAmount) {
    try {
      if (!window.smartAccount) {
        this.pushEvent("withdraw_failed", { error: "Wallet not connected" });
        return;
      }

      const lpAmountWei = BigInt(lpAmount) * BigInt(10 ** 18);

      const bankrollContract = getContract({
        client: window.thirdwebClient,
        chain: window.rogueChain,
        address: BUX_BANKROLL_ADDRESS,
      });

      const tx = prepareContractCall({
        contract: bankrollContract,
        method: "function withdrawBUX(uint256 lpAmount)",
        params: [lpAmountWei],
      });

      const receipt = await sendTransaction({ transaction: tx, account: window.smartAccount });
      this.pushEvent("withdraw_confirmed", { tx_hash: receipt.transactionHash });

    } catch (error) {
      console.error("[BankrollOnchain] Withdraw failed:", error);
      this.pushEvent("withdraw_failed", { error: error.message?.slice(0, 200) || "Transaction failed" });
    }
  },
};
```

### Register in `assets/js/app.js`

```javascript
import { LPBuxChart } from "./lp_bux_chart";
import { BankrollOnchain } from "./bankroll_onchain";

let hooks = {
  // ...existing hooks...
  LPBuxChart,
  BankrollOnchain,
};
```

---

## 7. Price History Storage

### Mnesia Table: `:lp_bux_candles`

| Pos | Field | Type | Description |
|-----|-------|------|-------------|
| 0 | (table name) | atom | `:lp_bux_candles` |
| 1 | `timestamp` | integer | Unix timestamp (candle open time), PRIMARY KEY |
| 2 | `open` | float | Opening LP-BUX price |
| 3 | `high` | float | Highest price in period |
| 4 | `low` | float | Lowest price in period |
| 5 | `close` | float | Closing price |

- **Type**: `:ordered_set` (sorted by timestamp)
- **Base resolution**: 5-minute candles
- **Aggregation**: Larger timeframes (1h, 4h, 1d) aggregated on read from 5-min base
- **Retention**: No auto-cleanup needed — 5-min candles for 1 year = ~105K records (small for Mnesia)

### Timeframe Mapping

| UI Timeframe | Candle Size | Candles Shown | Data Span |
|-------------|-------------|---------------|-----------|
| 1H | 5 min | 12 | Last hour |
| 24H | 1 hour | 24 | Last day |
| 7D | 4 hours | 42 | Last week |
| 30D | 1 day | 30 | Last month |
| ALL | 1 day | up to 365 | All time |

---

## 8. Implementation Order

This integrates with the existing Plinko plan phases. BUXBankroll is built BEFORE PlinkoGame since PlinkoGame depends on it.

| Phase | What | Tests to Write & Run |
|-------|------|----------------------|
| **B1** | Write BUXBankroll.sol (flattened, with all OZ v5 deps inlined) | Hardhat tests: LP mint/burn, deposit/withdraw, settlement functions, liability tracking, referrals, stats, UUPS upgrade (~60 tests) |
| **B2** | Deploy BUXBankroll proxy to Rogue Chain | Deployment verification script: check initialization, LP name/symbol, price, owner (~15 assertions) |
| **B3** | BUX Minter: add `routes/bux-bankroll.js` | Manual curl tests against deployed contract (house-info, lp-price, lp-balance, max-bet, player-stats, accounting) |
| **B4** | Backend: LPBuxPriceTracker GenServer, Mnesia `:lp_bux_candles` table, BuxMinter additions | Elixir tests: candle aggregation, price parsing, Mnesia read/write, BuxMinter API functions (~25 tests) |
| **B5** | BankrollLive + LPBuxChart hook + BankrollOnchain hook | LiveView tests: mount, timeframe switch, deposit/withdraw events, chart data pushing, PubSub handlers (~30 tests) |

Then continue with Plinko phases (PlinkoGame depends on BOTH BUXBankroll AND ROGUEBankroll):
- Phase P1: ROGUEBankroll V10 upgrade (add Plinko storage + functions)
- Phase P2: PlinkoGame.sol (uses BUXBankroll for BUX, ROGUEBankroll for ROGUE)
- Phase P3: Deploy PlinkoGame + wire contracts together
- Phase P4: BUX Minter Plinko endpoints
- Phase P5: Backend (PlinkoGame.ex, PlinkoSettler.ex, Mnesia)
- Phase P6: Frontend (PlinkoLive, SVG board, JS animation hooks)
- Phase P7: Integration testing

---

## 9. File List

| File | Action | Description |
|------|--------|-------------|
| **Smart Contract** | | |
| `contracts/bux-booster-game/contracts/BUXBankroll.sol` | NEW | LP token bankroll for BUX (flattened with OZ v5 deps) |
| `contracts/bux-booster-game/contracts/IBUXBankroll.sol` | NEW | Interface for game contracts |
| `contracts/bux-booster-game/scripts/deploy-bux-bankroll.js` | NEW | Deployment script (proxy + implementation) |
| `contracts/bux-booster-game/test/BUXBankroll.test.js` | NEW | Hardhat tests |
| `contracts/bux-booster-game/scripts/verify-bux-bankroll.js` | NEW | Post-deploy verification |
| **BUX Minter** | | |
| `routes/bux-bankroll.js` (in bux-minter repo) | NEW | Express routes for bankroll reads |
| **Backend** | | |
| `lib/blockster_v2/lp_bux_price_tracker.ex` | NEW | LP price polling + OHLC candle storage (GlobalSingleton) |
| `lib/blockster_v2/bux_minter.ex` | MODIFY | Add 5 bankroll API functions |
| `lib/blockster_v2/mnesia_initializer.ex` | MODIFY | Add `:lp_bux_candles` table definition |
| `lib/blockster_v2/application.ex` | MODIFY | Add LPBuxPriceTracker to genserver_children |
| **Frontend** | | |
| `lib/blockster_v2_web/live/bankroll_live.ex` | NEW | Deposit/withdraw/chart LiveView (complete with template) |
| `assets/js/lp_bux_chart.js` | NEW | TradingView lightweight-charts hook |
| `assets/js/bankroll_onchain.js` | NEW | Deposit/withdraw blockchain hook |
| `assets/js/BUXBankroll.json` | NEW | Contract ABI (generated from Hardhat compile) |
| `assets/js/app.js` | MODIFY | Register LPBuxChart + BankrollOnchain hooks |
| **Routing** | | |
| `lib/blockster_v2_web/router.ex` | MODIFY | Add `live "/bankroll", BankrollLive, :index` to `:default` session |
| **Tests** | | |
| `contracts/bux-booster-game/test/BUXBankroll.test.js` | NEW | Contract tests (~60) |
| `contracts/bux-booster-game/scripts/verify-bux-bankroll.js` | NEW | Deploy verification |
| `test/blockster_v2/lp_bux_price_tracker_test.exs` | NEW | Price tracker + candle tests |
| `test/blockster_v2_web/live/bankroll_live_test.exs` | NEW | LiveView tests |

---

## 10. Testing Plan

### 10.1 BUXBankroll.sol — Hardhat Tests

**File:** `contracts/bux-booster-game/test/BUXBankroll.test.js`

**MockERC20 helper contract** (needed for testing):
```solidity
// contracts/bux-booster-game/contracts/MockERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
```

**Full test file:**
```javascript
const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("BUXBankroll", function () {
  let buxBankroll, buxToken, owner, user1, user2, plinkoGame, referrer, unauthorized;
  const DEPOSIT_AMOUNT = ethers.parseEther("10000");
  const BET_AMOUNT = ethers.parseEther("100");
  const MULTIPLIER_DENOM = 10000n;

  beforeEach(async function () {
    [owner, user1, user2, plinkoGame, referrer, unauthorized] = await ethers.getSigners();

    // Deploy MockERC20 as BUX token
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    buxToken = await MockERC20.deploy("BUX Token", "BUX", 18);
    await buxToken.waitForDeployment();

    // Deploy BUXBankroll proxy
    const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
    buxBankroll = await upgrades.deployProxy(BUXBankroll, [await buxToken.getAddress()], {
      kind: "uups",
    });
    await buxBankroll.waitForDeployment();

    // Mint BUX to users for testing
    const mintAmount = ethers.parseEther("1000000");
    await buxToken.mint(owner.address, mintAmount);
    await buxToken.mint(user1.address, mintAmount);
    await buxToken.mint(user2.address, mintAmount);

    // Approve BUXBankroll to spend BUX
    const bankrollAddr = await buxBankroll.getAddress();
    await buxToken.connect(owner).approve(bankrollAddr, ethers.MaxUint256);
    await buxToken.connect(user1).approve(bankrollAddr, ethers.MaxUint256);
    await buxToken.connect(user2).approve(bankrollAddr, ethers.MaxUint256);

    // Set plinko game
    await buxBankroll.setPlinkoGame(plinkoGame.address);
  });

  // ============================================================
  // Helper: simulate bet placement from plinkoGame signer
  // ============================================================
  async function placeBet(player, amount, configIndex, maxMultBps) {
    const commitmentHash = ethers.keccak256(ethers.toUtf8Bytes(
      `bet-${player.address}-${Date.now()}-${Math.random()}`
    ));
    const nonce = 1n;
    const maxPayout = (amount * BigInt(maxMultBps)) / MULTIPLIER_DENOM;

    // Player sends BUX directly to BUXBankroll (simulates PlinkoGame.placeBet doing safeTransferFrom)
    await buxToken.connect(player).transfer(await buxBankroll.getAddress(), amount);

    await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
      commitmentHash, player.address, amount, configIndex, nonce, maxPayout
    );
    return { commitmentHash, nonce, maxPayout };
  }

  // ============================================================
  // 1. Initialization
  // ============================================================
  describe("Initialization", function () {
    it("should set buxToken address correctly", async function () {
      expect(await buxBankroll.buxToken()).to.equal(await buxToken.getAddress());
    });

    it("should set LP token name and symbol", async function () {
      expect(await buxBankroll.name()).to.equal("BUX Bankroll");
      expect(await buxBankroll.symbol()).to.equal("LP-BUX");
    });

    it("should set initial LP price to 1e18", async function () {
      expect(await buxBankroll.getLPPrice()).to.equal(ethers.parseEther("1"));
    });

    it("should set owner to deployer", async function () {
      expect(await buxBankroll.owner()).to.equal(owner.address);
    });

    it("should set maximumBetSizeDivisor to 1000", async function () {
      expect(await buxBankroll.maximumBetSizeDivisor()).to.equal(1000);
    });

    it("should set referralBasisPoints to 20", async function () {
      expect(await buxBankroll.referralBasisPoints()).to.equal(20);
    });

    it("should reject double initialization", async function () {
      await expect(
        buxBankroll.initialize(await buxToken.getAddress())
      ).to.be.reverted;
    });

    it("should reject zero address for buxToken", async function () {
      const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
      await expect(
        upgrades.deployProxy(BUXBankroll, [ethers.ZeroAddress], { kind: "uups" })
      ).to.be.revertedWithCustomError(buxBankroll, "ZeroAddress");
    });
  });

  // ============================================================
  // 2. depositBUX
  // ============================================================
  describe("depositBUX", function () {
    it("should mint LP tokens 1:1 on first deposit", async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
      expect(await buxBankroll.balanceOf(user1.address)).to.equal(DEPOSIT_AMOUNT);
    });

    it("should mint proportional LP on subsequent deposits", async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
      await buxBankroll.connect(user2).depositBUX(DEPOSIT_AMOUNT);
      // Same amount deposited at same price = same LP
      expect(await buxBankroll.balanceOf(user2.address)).to.equal(DEPOSIT_AMOUNT);
    });

    it("should transfer BUX from depositor to contract", async function () {
      const before = await buxToken.balanceOf(user1.address);
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
      const after_ = await buxToken.balanceOf(user1.address);
      expect(before - after_).to.equal(DEPOSIT_AMOUNT);
    });

    it("should update totalBalance in houseBalance", async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
      const info = await buxBankroll.getHouseInfo();
      expect(info[0]).to.equal(DEPOSIT_AMOUNT); // totalBalance
    });

    it("should update poolTokenPrice", async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
      const info = await buxBankroll.getHouseInfo();
      expect(info[5]).to.equal(ethers.parseEther("1")); // price = 1.0 after first deposit
    });

    it("should emit BUXDeposited event", async function () {
      await expect(buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT))
        .to.emit(buxBankroll, "BUXDeposited")
        .withArgs(user1.address, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
    });

    it("should emit PoolPriceUpdated event", async function () {
      await expect(buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT))
        .to.emit(buxBankroll, "PoolPriceUpdated");
    });

    it("should reject zero amount", async function () {
      await expect(
        buxBankroll.connect(user1).depositBUX(0)
      ).to.be.revertedWithCustomError(buxBankroll, "ZeroAmount");
    });

    it("should reject without prior BUX approval", async function () {
      await buxToken.connect(unauthorized).approve(await buxBankroll.getAddress(), 0);
      await buxToken.mint(unauthorized.address, DEPOSIT_AMOUNT);
      // unauthorized has tokens but no approval
      await expect(
        buxBankroll.connect(unauthorized).depositBUX(DEPOSIT_AMOUNT)
      ).to.be.reverted;
    });

    it("should reject when paused", async function () {
      await buxBankroll.setPaused(true);
      await expect(
        buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT)
      ).to.be.reverted;
    });

    it("multiple depositors get correct proportional LP", async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
      // user2 deposits half
      const halfDeposit = DEPOSIT_AMOUNT / 2n;
      await buxBankroll.connect(user2).depositBUX(halfDeposit);
      expect(await buxBankroll.balanceOf(user2.address)).to.equal(halfDeposit);
    });

    it("deposit during active bets uses effectiveBalance for LP pricing", async function () {
      // user1 deposits initial liquidity
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);

      // Place a bet (increases totalBalance but also unsettledBets)
      await placeBet(user2, BET_AMOUNT, 0, 20000); // 2x max multiplier

      // user2 deposits — LP price should use effectiveBalance, not totalBalance
      const depositAmount = ethers.parseEther("5000");
      await buxBankroll.connect(user2).depositBUX(depositAmount);

      // LP minted should be based on effectiveBalance (totalBalance - unsettledBets)
      const lpBalance = await buxBankroll.balanceOf(user2.address);
      // effectiveBalance = DEPOSIT_AMOUNT + BET_AMOUNT - BET_AMOUNT = DEPOSIT_AMOUNT
      // lpMinted = (depositAmount * supply) / effectiveBalance = (5000 * 10000) / 10000 = 5000
      expect(lpBalance).to.equal(depositAmount);
    });
  });

  // ============================================================
  // 3. withdrawBUX
  // ============================================================
  describe("withdrawBUX", function () {
    beforeEach(async function () {
      // user1 deposits initial funds
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
    });

    it("should burn LP tokens and return proportional BUX", async function () {
      const lpBefore = await buxBankroll.balanceOf(user1.address);
      const withdrawLP = lpBefore / 2n;
      await buxBankroll.connect(user1).withdrawBUX(withdrawLP);
      expect(await buxBankroll.balanceOf(user1.address)).to.equal(lpBefore - withdrawLP);
    });

    it("should transfer BUX back to withdrawer", async function () {
      const buxBefore = await buxToken.balanceOf(user1.address);
      const withdrawLP = DEPOSIT_AMOUNT / 2n;
      await buxBankroll.connect(user1).withdrawBUX(withdrawLP);
      const buxAfter = await buxToken.balanceOf(user1.address);
      // At 1:1 price, LP withdrawn = BUX received
      expect(buxAfter - buxBefore).to.equal(withdrawLP);
    });

    it("should update totalBalance after withdrawal", async function () {
      await buxBankroll.connect(user1).withdrawBUX(DEPOSIT_AMOUNT / 2n);
      const info = await buxBankroll.getHouseInfo();
      expect(info[0]).to.equal(DEPOSIT_AMOUNT / 2n);
    });

    it("should emit BUXWithdrawn event", async function () {
      const withdrawLP = DEPOSIT_AMOUNT / 2n;
      await expect(buxBankroll.connect(user1).withdrawBUX(withdrawLP))
        .to.emit(buxBankroll, "BUXWithdrawn");
    });

    it("should reject zero amount", async function () {
      await expect(
        buxBankroll.connect(user1).withdrawBUX(0)
      ).to.be.revertedWithCustomError(buxBankroll, "ZeroAmount");
    });

    it("should reject if user has insufficient LP tokens", async function () {
      await expect(
        buxBankroll.connect(user2).withdrawBUX(1) // user2 has no LP
      ).to.be.revertedWithCustomError(buxBankroll, "InsufficientBalance");
    });

    it("should reject when paused", async function () {
      await buxBankroll.setPaused(true);
      await expect(
        buxBankroll.connect(user1).withdrawBUX(100)
      ).to.be.reverted;
    });

    it("partial withdrawal leaves correct balances", async function () {
      const quarter = DEPOSIT_AMOUNT / 4n;
      await buxBankroll.connect(user1).withdrawBUX(quarter);
      expect(await buxBankroll.balanceOf(user1.address)).to.equal(DEPOSIT_AMOUNT - quarter);
      const info = await buxBankroll.getHouseInfo();
      expect(info[0]).to.equal(DEPOSIT_AMOUNT - quarter);
    });

    it("full withdrawal returns all BUX", async function () {
      const buxBefore = await buxToken.balanceOf(user1.address);
      await buxBankroll.connect(user1).withdrawBUX(DEPOSIT_AMOUNT);
      const buxAfter = await buxToken.balanceOf(user1.address);
      expect(buxAfter - buxBefore).to.equal(DEPOSIT_AMOUNT);
      expect(await buxBankroll.balanceOf(user1.address)).to.equal(0);
    });

    it("withdrawal during active bets limited by liability", async function () {
      // Place a bet creating liability
      await placeBet(user2, BET_AMOUNT, 0, 100000); // 10x max mult = 1000 BUX liability

      // netBalance = totalBalance - liability
      const info = await buxBankroll.getHouseInfo();
      const netBalance = info[3]; // netBalance

      // Trying to withdraw more LP than netBalance allows should fail
      // The LP supply = DEPOSIT_AMOUNT, so withdrawing all LP would request > netBalance BUX
      await expect(
        buxBankroll.connect(user1).withdrawBUX(DEPOSIT_AMOUNT)
      ).to.be.revertedWithCustomError(buxBankroll, "InsufficientLiquidity");
    });
  });

  // ============================================================
  // 4. LP Price Mechanics
  // ============================================================
  describe("LP Price Mechanics", function () {
    beforeEach(async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
    });

    it("LP price increases when house wins (losing bet)", async function () {
      const priceBefore = (await buxBankroll.getHouseInfo())[5];

      // Place and settle a losing bet (house wins)
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      const partialPayout = 0n; // complete loss
      const path = [0, 1, 0]; // dummy path
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, partialPayout,
        0, 2, path, nonce, maxPayout
      );

      const priceAfter = (await buxBankroll.getHouseInfo())[5];
      expect(priceAfter).to.be.gt(priceBefore);
    });

    it("LP price decreases when house loses (winning bet)", async function () {
      const priceBefore = (await buxBankroll.getHouseInfo())[5];

      // Place and settle a winning bet (house loses)
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      const payout = BET_AMOUNT * 15n / 10n; // 1.5x payout
      const path = [1, 1, 1];
      await buxBankroll.connect(plinkoGame).settlePlinkoWinningBet(
        user2.address, commitmentHash, BET_AMOUNT, payout,
        0, 3, path, nonce, maxPayout
      );

      const priceAfter = (await buxBankroll.getHouseInfo())[5];
      expect(priceAfter).to.be.lt(priceBefore);
    });

    it("LP price stays at 1.0 when no bets have occurred", async function () {
      expect(await buxBankroll.getLPPrice()).to.equal(ethers.parseEther("1"));
    });

    it("deposit at higher price gives fewer LP tokens", async function () {
      // Simulate house win to increase price
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], nonce, maxPayout
      );

      // user2 deposits same amount as user1, but at higher price
      const user2LP = await buxBankroll.balanceOf(user2.address); // should be 0 before
      await buxBankroll.connect(user2).depositBUX(DEPOSIT_AMOUNT);
      const user2LPAfter = await buxBankroll.balanceOf(user2.address);
      // user2 gets fewer LP since price is now > 1.0
      expect(user2LPAfter).to.be.lt(DEPOSIT_AMOUNT);
    });

    it("withdrawal at higher price gives more BUX per LP", async function () {
      // Simulate house win
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], nonce, maxPayout
      );

      // user1 withdraws half their LP — should get more BUX than they deposited ratio
      const buxBefore = await buxToken.balanceOf(user1.address);
      const halfLP = DEPOSIT_AMOUNT / 2n;
      await buxBankroll.connect(user1).withdrawBUX(halfLP);
      const buxAfter = await buxToken.balanceOf(user1.address);
      const buxReceived = buxAfter - buxBefore;

      // Should receive more than half the deposit since price went up
      expect(buxReceived).to.be.gt(DEPOSIT_AMOUNT / 2n);
    });

    it("LP price uses effectiveBalance (excludes unsettledBets)", async function () {
      const priceBefore = (await buxBankroll.getHouseInfo())[5];

      // Place bet — totalBalance increases but effectiveBalance stays the same
      await placeBet(user2, BET_AMOUNT, 0, 20000);

      const priceAfter = (await buxBankroll.getHouseInfo())[5];
      // Price should not change because effectiveBalance = totalBalance - unsettledBets is the same
      expect(priceAfter).to.equal(priceBefore);
    });
  });

  // ============================================================
  // 5. Game Integration — Plinko
  // ============================================================
  describe("Game Integration — Plinko", function () {
    beforeEach(async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
    });

    it("setPlinkoGame sets authorized game address", async function () {
      expect(await buxBankroll.plinkoGame()).to.equal(plinkoGame.address);
    });

    it("setPlinkoGame emits GameAuthorized event", async function () {
      await expect(buxBankroll.setPlinkoGame(user2.address))
        .to.emit(buxBankroll, "GameAuthorized")
        .withArgs(user2.address, true);
    });

    it("rejects setPlinkoGame from non-owner", async function () {
      await expect(
        buxBankroll.connect(user1).setPlinkoGame(user2.address)
      ).to.be.reverted;
    });

    it("updateHouseBalancePlinkoBetPlaced increases liability and totalBalance", async function () {
      const infoBefore = await buxBankroll.getHouseInfo();
      await placeBet(user2, BET_AMOUNT, 0, 20000);
      const infoAfter = await buxBankroll.getHouseInfo();

      expect(infoAfter[0]).to.be.gt(infoBefore[0]); // totalBalance up (wager added)
      expect(infoAfter[1]).to.be.gt(infoBefore[1]); // liability up
      expect(infoAfter[2]).to.be.gt(infoBefore[2]); // unsettledBets up
    });

    it("settlePlinkoWinningBet sends payout to winner", async function () {
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      const payout = BET_AMOUNT * 15n / 10n; // 1.5x
      const buxBefore = await buxToken.balanceOf(user2.address);

      await buxBankroll.connect(plinkoGame).settlePlinkoWinningBet(
        user2.address, commitmentHash, BET_AMOUNT, payout,
        0, 3, [1, 1, 1], nonce, maxPayout
      );

      const buxAfter = await buxToken.balanceOf(user2.address);
      expect(buxAfter - buxBefore).to.equal(payout);
    });

    it("settlePlinkoLosingBet with partial payout sends partial amount", async function () {
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      const partialPayout = BET_AMOUNT * 3n / 10n; // 0.3x
      const buxBefore = await buxToken.balanceOf(user2.address);

      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, partialPayout,
        0, 0, [0], nonce, maxPayout
      );

      const buxAfter = await buxToken.balanceOf(user2.address);
      expect(buxAfter - buxBefore).to.equal(partialPayout);
    });

    it("settlePlinkoLosingBet with 0 payout sends nothing", async function () {
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      const buxBefore = await buxToken.balanceOf(user2.address);

      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], nonce, maxPayout
      );

      const buxAfter = await buxToken.balanceOf(user2.address);
      expect(buxAfter).to.equal(buxBefore);
    });

    it("settlePlinkoPushBet returns exact bet amount", async function () {
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      const buxBefore = await buxToken.balanceOf(user2.address);

      await buxBankroll.connect(plinkoGame).settlePlinkoPushBet(
        user2.address, commitmentHash, BET_AMOUNT,
        0, 2, [0, 1], nonce, maxPayout
      );

      const buxAfter = await buxToken.balanceOf(user2.address);
      expect(buxAfter - buxBefore).to.equal(BET_AMOUNT);
    });

    it("all settle functions release liability and unsettledBets", async function () {
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);

      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], nonce, maxPayout
      );

      const info = await buxBankroll.getHouseInfo();
      expect(info[1]).to.equal(0); // liability = 0
      expect(info[2]).to.equal(0); // unsettledBets = 0
    });

    it("unauthorized caller cannot call onlyPlinko functions", async function () {
      const commitHash = ethers.keccak256(ethers.toUtf8Bytes("fake"));
      await expect(
        buxBankroll.connect(user1).updateHouseBalancePlinkoBetPlaced(
          commitHash, user1.address, BET_AMOUNT, 0, 1, BET_AMOUNT * 2n
        )
      ).to.be.revertedWithCustomError(buxBankroll, "UnauthorizedGame");
    });

    it("getMaxBet returns correct value based on netBalance and multiplier", async function () {
      // netBalance = 10000 BUX, MAX_BET_BPS = 10 (0.1%), maxMult = 20000 (2x)
      const maxBet = await buxBankroll.getMaxBet(0, 20000);
      // baseMaxBet = (10000e18 * 10) / 10000 = 10e18 BUX
      // adjusted = (10e18 * 20000) / 20000 = 10e18
      expect(maxBet).to.equal(ethers.parseEther("10"));
    });
  });

  // ============================================================
  // 6. Liability Tracking
  // ============================================================
  describe("Liability Tracking", function () {
    beforeEach(async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
    });

    it("liability increases on bet placement", async function () {
      await placeBet(user2, BET_AMOUNT, 0, 20000);
      const info = await buxBankroll.getHouseInfo();
      expect(info[1]).to.be.gt(0); // liability > 0
    });

    it("liability decreases on settlement", async function () {
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      const infoBefore = await buxBankroll.getHouseInfo();

      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], nonce, maxPayout
      );

      const infoAfter = await buxBankroll.getHouseInfo();
      expect(infoAfter[1]).to.be.lt(infoBefore[1]); // liability decreased
    });

    it("netBalance = totalBalance - liability", async function () {
      await placeBet(user2, BET_AMOUNT, 0, 20000);
      const info = await buxBankroll.getHouseInfo();
      expect(info[3]).to.equal(info[0] - info[1]); // netBalance = totalBalance - liability
    });

    it("multiple concurrent bets tracked correctly", async function () {
      await placeBet(user2, BET_AMOUNT, 0, 20000);
      await placeBet(user2, BET_AMOUNT * 2n, 0, 20000);
      const info = await buxBankroll.getHouseInfo();
      expect(info[2]).to.equal(BET_AMOUNT * 3n); // unsettledBets = 100 + 200
    });

    it("liability and unsettledBets return to 0 after all bets settled", async function () {
      const bet1 = await placeBet(user2, BET_AMOUNT, 0, 20000);
      const bet2 = await placeBet(user2, BET_AMOUNT, 0, 20000);

      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, bet1.commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], bet1.nonce, bet1.maxPayout
      );
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, bet2.commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], bet2.nonce, bet2.maxPayout
      );

      const info = await buxBankroll.getHouseInfo();
      expect(info[1]).to.equal(0); // liability
      expect(info[2]).to.equal(0); // unsettledBets
    });
  });

  // ============================================================
  // 7. Referral Rewards
  // ============================================================
  describe("Referral Rewards", function () {
    beforeEach(async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
      // Set referrer for user2
      await buxBankroll.setPlayerReferrer(user2.address, referrer.address);
    });

    it("pays BUX referral reward on losing bet", async function () {
      const refBefore = await buxToken.balanceOf(referrer.address);
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);

      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], nonce, maxPayout
      );

      const refAfter = await buxToken.balanceOf(referrer.address);
      // Reward = BET_AMOUNT * 20 / 10000 = 0.2% of loss
      expect(refAfter - refBefore).to.equal(BET_AMOUNT * 20n / 10000n);
    });

    it("no referral on winning bets", async function () {
      const refBefore = await buxToken.balanceOf(referrer.address);
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);

      await buxBankroll.connect(plinkoGame).settlePlinkoWinningBet(
        user2.address, commitmentHash, BET_AMOUNT, BET_AMOUNT * 15n / 10n,
        0, 3, [1, 1, 1], nonce, maxPayout
      );

      const refAfter = await buxToken.balanceOf(referrer.address);
      expect(refAfter).to.equal(refBefore);
    });

    it("tracks totalReferralRewardsPaid", async function () {
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], nonce, maxPayout
      );
      expect(await buxBankroll.totalReferralRewardsPaid()).to.equal(BET_AMOUNT * 20n / 10000n);
    });

    it("tracks referrerTotalEarnings per referrer", async function () {
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], nonce, maxPayout
      );
      expect(await buxBankroll.referrerTotalEarnings(referrer.address)).to.equal(BET_AMOUNT * 20n / 10000n);
    });

    it("emits ReferralRewardPaid event", async function () {
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);
      await expect(
        buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
          user2.address, commitmentHash, BET_AMOUNT, 0,
          0, 0, [0], nonce, maxPayout
        )
      ).to.emit(buxBankroll, "ReferralRewardPaid");
    });

    it("silently skips if referrer not set", async function () {
      // user1 has no referrer set — should not revert
      const { commitmentHash, nonce, maxPayout } = await placeBet(user1, BET_AMOUNT, 0, 20000);
      await expect(
        buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
          user1.address, commitmentHash, BET_AMOUNT, 0,
          0, 0, [0], nonce, maxPayout
        )
      ).to.not.be.reverted;
    });

    it("silently skips if referralBasisPoints is 0", async function () {
      await buxBankroll.setReferralBasisPoints(0);
      const refBefore = await buxToken.balanceOf(referrer.address);
      const { commitmentHash, nonce, maxPayout } = await placeBet(user2, BET_AMOUNT, 0, 20000);

      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], nonce, maxPayout
      );

      expect(await buxToken.balanceOf(referrer.address)).to.equal(refBefore);
    });

    it("setPlayerReferrer works for owner", async function () {
      await buxBankroll.setPlayerReferrer(user1.address, referrer.address);
      expect(await buxBankroll.playerReferrers(user1.address)).to.equal(referrer.address);
    });

    it("setPlayerReferrer works for referralAdmin", async function () {
      await buxBankroll.setReferralAdmin(user1.address);
      await buxBankroll.connect(user1).setPlayerReferrer(unauthorized.address, referrer.address);
      expect(await buxBankroll.playerReferrers(unauthorized.address)).to.equal(referrer.address);
    });

    it("setPlayerReferrer rejects self-referral", async function () {
      await expect(
        buxBankroll.setPlayerReferrer(user1.address, user1.address)
      ).to.be.revertedWith("Self-referral not allowed");
    });

    it("setPlayerReferrer rejects duplicate setting", async function () {
      await buxBankroll.setPlayerReferrer(user1.address, referrer.address);
      await expect(
        buxBankroll.setPlayerReferrer(user1.address, user2.address)
      ).to.be.revertedWith("Referrer already set");
    });

    it("setPlayerReferrersBatch works correctly", async function () {
      await buxBankroll.setPlayerReferrersBatch(
        [user1.address, unauthorized.address],
        [referrer.address, referrer.address]
      );
      expect(await buxBankroll.playerReferrers(user1.address)).to.equal(referrer.address);
      expect(await buxBankroll.playerReferrers(unauthorized.address)).to.equal(referrer.address);
    });
  });

  // ============================================================
  // 8. Stats Tracking
  // ============================================================
  describe("Stats Tracking", function () {
    beforeEach(async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
    });

    it("tracks PlinkoPlayerStats per player", async function () {
      // Place and settle a win
      const bet1 = await placeBet(user2, BET_AMOUNT, 0, 20000);
      await buxBankroll.connect(plinkoGame).settlePlinkoWinningBet(
        user2.address, bet1.commitmentHash, BET_AMOUNT, BET_AMOUNT * 15n / 10n,
        0, 3, [1, 1, 1], bet1.nonce, bet1.maxPayout
      );

      // Place and settle a loss
      const bet2 = await placeBet(user2, BET_AMOUNT, 0, 20000);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, bet2.commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], bet2.nonce, bet2.maxPayout
      );

      const stats = await buxBankroll.getPlinkoPlayerStats(user2.address);
      expect(stats.totalBets).to.equal(2);
      expect(stats.wins).to.equal(1);
      expect(stats.losses).to.equal(1);
    });

    it("tracks PlinkoAccounting globally", async function () {
      const bet1 = await placeBet(user2, BET_AMOUNT, 0, 20000);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, bet1.commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], bet1.nonce, bet1.maxPayout
      );

      const acc = await buxBankroll.getPlinkoAccounting();
      expect(acc.totalBets).to.equal(1);
      expect(acc.totalLosses).to.equal(1);
      expect(acc.totalHouseProfit).to.be.gt(0);
    });

    it("tracks plinkoBetsPerConfig per player", async function () {
      const bet1 = await placeBet(user2, BET_AMOUNT, 2, 20000); // configIndex 2
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, bet1.commitmentHash, BET_AMOUNT, 0,
        2, 0, [0], bet1.nonce, bet1.maxPayout
      );

      const stats = await buxBankroll.getPlinkoPlayerStats(user2.address);
      expect(stats.betsPerConfig[2]).to.equal(1);
    });

    it("getPlinkoAccounting returns correct winRate and houseEdge", async function () {
      // 1 win, 1 loss
      const bet1 = await placeBet(user2, BET_AMOUNT, 0, 20000);
      await buxBankroll.connect(plinkoGame).settlePlinkoWinningBet(
        user2.address, bet1.commitmentHash, BET_AMOUNT, BET_AMOUNT * 15n / 10n,
        0, 3, [1, 1, 1], bet1.nonce, bet1.maxPayout
      );

      const bet2 = await placeBet(user2, BET_AMOUNT, 0, 20000);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        user2.address, bet2.commitmentHash, BET_AMOUNT, 0,
        0, 0, [0], bet2.nonce, bet2.maxPayout
      );

      const acc = await buxBankroll.getPlinkoAccounting();
      // winRate = (1 * 10000) / 2 = 5000 (50%)
      expect(acc.winRate).to.equal(5000);
    });
  });

  // ============================================================
  // 9. Admin
  // ============================================================
  describe("Admin", function () {
    beforeEach(async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);
    });

    it("owner can set maxBetDivisor", async function () {
      await buxBankroll.setMaxBetDivisor(2000);
      expect(await buxBankroll.maximumBetSizeDivisor()).to.equal(2000);
    });

    it("owner can emergencyWithdrawBUX", async function () {
      const ownerBefore = await buxToken.balanceOf(owner.address);
      const withdrawAmount = ethers.parseEther("1000");
      await buxBankroll.emergencyWithdrawBUX(withdrawAmount);
      const ownerAfter = await buxToken.balanceOf(owner.address);
      expect(ownerAfter - ownerBefore).to.equal(withdrawAmount);
    });

    it("owner can set referral basis points", async function () {
      await buxBankroll.setReferralBasisPoints(50);
      expect(await buxBankroll.referralBasisPoints()).to.equal(50);
    });

    it("owner can set referral admin", async function () {
      await buxBankroll.setReferralAdmin(user1.address);
      expect(await buxBankroll.referralAdmin()).to.equal(user1.address);
    });

    it("owner can pause and unpause", async function () {
      await buxBankroll.setPaused(true);
      await expect(buxBankroll.connect(user1).depositBUX(1000)).to.be.reverted;
      await buxBankroll.setPaused(false);
      await expect(buxBankroll.connect(user1).depositBUX(1000)).to.not.be.reverted;
    });

    it("non-owner cannot call admin functions", async function () {
      await expect(buxBankroll.connect(user1).setPlinkoGame(user2.address)).to.be.reverted;
      await expect(buxBankroll.connect(user1).setMaxBetDivisor(2000)).to.be.reverted;
      await expect(buxBankroll.connect(user1).emergencyWithdrawBUX(1000)).to.be.reverted;
      await expect(buxBankroll.connect(user1).setPaused(true)).to.be.reverted;
    });

    it("emergency withdraw reduces totalBalance correctly", async function () {
      const withdrawAmount = ethers.parseEther("1000");
      await buxBankroll.emergencyWithdrawBUX(withdrawAmount);
      const info = await buxBankroll.getHouseInfo();
      expect(info[0]).to.equal(DEPOSIT_AMOUNT - withdrawAmount);
    });
  });

  // ============================================================
  // 10. UUPS Upgrade
  // ============================================================
  describe("UUPS Upgrade", function () {
    it("owner can upgrade to new implementation", async function () {
      // Deploy a V2 (same contract, simulating upgrade)
      const BUXBankrollV2 = await ethers.getContractFactory("BUXBankroll");
      await upgrades.upgradeProxy(await buxBankroll.getAddress(), BUXBankrollV2, {
        kind: "uups",
      });
      // Should succeed without error
    });

    it("non-owner cannot upgrade", async function () {
      const BUXBankrollV2 = await ethers.getContractFactory("BUXBankroll", user1);
      await expect(
        upgrades.upgradeProxy(await buxBankroll.getAddress(), BUXBankrollV2, {
          kind: "uups",
        })
      ).to.be.reverted;
    });

    it("state is preserved after upgrade", async function () {
      await buxBankroll.connect(user1).depositBUX(DEPOSIT_AMOUNT);

      const BUXBankrollV2 = await ethers.getContractFactory("BUXBankroll");
      const upgraded = await upgrades.upgradeProxy(await buxBankroll.getAddress(), BUXBankrollV2, {
        kind: "uups",
      });

      expect(await upgraded.balanceOf(user1.address)).to.equal(DEPOSIT_AMOUNT);
      expect(await upgraded.buxToken()).to.equal(await buxToken.getAddress());
    });
  });
});
```

**Expected test count:** ~70 tests

### 10.2 Deployment Script

**File:** `contracts/bux-booster-game/scripts/deploy-bux-bankroll.js`

```javascript
const { ethers, upgrades } = require("hardhat");

const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying BUXBankroll with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  // 1. Deploy BUXBankroll (UUPS proxy)
  const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
  console.log("\nDeploying BUXBankroll proxy...");
  const buxBankroll = await upgrades.deployProxy(BUXBankroll, [BUX_TOKEN_ADDRESS], {
    kind: "uups",
    initializer: "initialize",
  });
  await buxBankroll.waitForDeployment();
  const proxyAddress = await buxBankroll.getAddress();
  console.log("BUXBankroll proxy deployed to:", proxyAddress);

  // 2. Get implementation address
  const implAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("BUXBankroll implementation:", implAddress);

  // 3. Verify initial state
  console.log("\n--- Initial State ---");
  console.log("Owner:", await buxBankroll.owner());
  console.log("BUX Token:", await buxBankroll.buxToken());
  console.log("LP Name:", await buxBankroll.name());
  console.log("LP Symbol:", await buxBankroll.symbol());
  console.log("LP Price:", ethers.formatEther(await buxBankroll.getLPPrice()));
  console.log("Max Bet Divisor:", (await buxBankroll.maximumBetSizeDivisor()).toString());
  console.log("Referral BPS:", (await buxBankroll.referralBasisPoints()).toString());

  console.log("\n--- Deployment Complete ---");
  console.log("Save these addresses:");
  console.log(`  BUXBankroll Proxy: ${proxyAddress}`);
  console.log(`  BUXBankroll Implementation: ${implAddress}`);
  console.log("\nNext steps:");
  console.log("  1. Deploy PlinkoGame");
  console.log("  2. Call buxBankroll.setPlinkoGame(plinkoGameAddress)");
  console.log("  3. Call plinkoGame.setBuxBankroll(buxBankrollAddress)");
  console.log("  4. Approve BUXBankroll to spend owner BUX");
  console.log("  5. Deposit initial house BUX via buxBankroll.depositBUX()");
  console.log("  6. Set referral admin: buxBankroll.setReferralAdmin(adminAddress)");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

### 10.3 Post-Deploy Verification Script

**File:** `contracts/bux-booster-game/scripts/verify-bux-bankroll.js`

```javascript
const { ethers } = require("hardhat");

// Set these after deployment
const BUX_BANKROLL_PROXY = process.env.BUX_BANKROLL_ADDRESS || "0x<SET_AFTER_DEPLOY>";
const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Verifying BUXBankroll at:", BUX_BANKROLL_PROXY);

  const buxBankroll = await ethers.getContractAt("BUXBankroll", BUX_BANKROLL_PROXY);
  let passed = 0;
  let failed = 0;

  function assert(condition, message) {
    if (condition) {
      console.log(`  ✓ ${message}`);
      passed++;
    } else {
      console.log(`  ✗ ${message}`);
      failed++;
    }
  }

  // 1. Initialization
  console.log("\n1. Initialization");
  assert(await buxBankroll.owner() === deployer.address, `Owner is deployer (${deployer.address})`);
  assert(await buxBankroll.buxToken() === BUX_TOKEN_ADDRESS, "BUX token address correct");
  assert(await buxBankroll.name() === "BUX Bankroll", "LP name is 'BUX Bankroll'");
  assert(await buxBankroll.symbol() === "LP-BUX", "LP symbol is 'LP-BUX'");
  assert((await buxBankroll.getLPPrice()) === ethers.parseEther("1"), "LP price is 1.0");
  assert((await buxBankroll.maximumBetSizeDivisor()) === 1000n, "Max bet divisor is 1000");
  assert((await buxBankroll.referralBasisPoints()) === 20n, "Referral BPS is 20");
  assert((await buxBankroll.totalSupply()) === 0n, "LP supply is 0");

  // 2. House balance
  console.log("\n2. House Balance");
  const info = await buxBankroll.getHouseInfo();
  assert(info[0] === 0n, "totalBalance is 0");
  assert(info[1] === 0n, "liability is 0");
  assert(info[2] === 0n, "unsettledBets is 0");
  assert(info[3] === 0n, "netBalance is 0");
  assert(info[4] === 0n, "poolTokenSupply is 0");
  assert(info[5] === ethers.parseEther("1"), "poolTokenPrice is 1e18");

  // 3. Plinko game (not set yet)
  console.log("\n3. Plinko Game");
  assert(await buxBankroll.plinkoGame() === ethers.ZeroAddress, "Plinko game not yet set");

  console.log(`\n--- Results: ${passed} passed, ${failed} failed ---`);
  if (failed > 0) process.exit(1);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

### 10.4 Backend Tests

**File:** `test/blockster_v2/lp_bux_price_tracker_test.exs`

Tests for LPBuxPriceTracker candle logic, BuxMinter bankroll functions, Mnesia candle storage.

```elixir
defmodule BlocksterV2.LPBuxPriceTrackerTest do
  use ExUnit.Case, async: false
  alias BlocksterV2.LPBuxPriceTracker

  setup do
    # Ensure Mnesia lp_bux_candles table exists for tests
    :mnesia.create_table(:lp_bux_candles, [
      attributes: [:timestamp, :open, :high, :low, :close],
      type: :ordered_set,
      disc_copies: []
    ])

    on_exit(fn ->
      :mnesia.clear_table(:lp_bux_candles)
    end)

    :ok
  end

  # Helper: insert a candle directly into Mnesia
  defp insert_candle(timestamp, open, high, low, close) do
    :mnesia.dirty_write({:lp_bux_candles, timestamp, open, high, low, close})
  end

  # ============ Candle Aggregation ============

  describe "get_candles/2" do
    test "returns empty list when no candles exist" do
      assert LPBuxPriceTracker.get_candles(3600, 24) == []
    end

    test "returns raw 5-min candles when timeframe matches base (300s)" do
      now = System.system_time(:second)
      base = div(now, 300) * 300
      insert_candle(base - 600, 1.0, 1.1, 0.9, 1.05)
      insert_candle(base - 300, 1.05, 1.2, 1.0, 1.1)
      insert_candle(base, 1.1, 1.15, 1.05, 1.12)

      candles = LPBuxPriceTracker.get_candles(300, 100)
      assert length(candles) >= 3
      assert Enum.all?(candles, fn c -> Map.has_key?(c, :time) end)
    end

    test "aggregates 5-min candles into 1-hour candles correctly" do
      now = System.system_time(:second)
      hour_start = div(now, 3600) * 3600

      # Insert 12 x 5-min candles within the hour
      for i <- 0..11 do
        ts = hour_start + i * 300
        insert_candle(ts, 1.0 + i * 0.01, 1.0 + i * 0.01 + 0.05, 1.0 + i * 0.01 - 0.02, 1.0 + (i + 1) * 0.01)
      end

      candles = LPBuxPriceTracker.get_candles(3600, 100)
      # Should aggregate into 1 hourly candle
      assert length(candles) >= 1
      hourly = Enum.find(candles, fn c -> c.time == hour_start end)
      assert hourly != nil
      assert hourly.open == 1.0  # First 5-min candle's open
    end

    test "aggregated candles have correct high and low" do
      now = System.system_time(:second)
      hour_start = div(now, 3600) * 3600

      insert_candle(hour_start, 1.0, 1.5, 0.8, 1.2)         # high=1.5, low=0.8
      insert_candle(hour_start + 300, 1.2, 1.8, 0.9, 1.3)   # high=1.8, low=0.9
      insert_candle(hour_start + 600, 1.3, 1.4, 0.7, 1.1)   # high=1.4, low=0.7

      candles = LPBuxPriceTracker.get_candles(3600, 100)
      hourly = Enum.find(candles, fn c -> c.time == hour_start end)
      assert hourly.high == 1.8
      assert hourly.low == 0.7
    end

    test "candles are sorted by timestamp ascending" do
      now = System.system_time(:second)
      base = div(now, 300) * 300
      insert_candle(base, 1.0, 1.1, 0.9, 1.05)
      insert_candle(base - 300, 1.05, 1.2, 1.0, 1.1)

      candles = LPBuxPriceTracker.get_candles(300, 100)
      timestamps = Enum.map(candles, & &1.time)
      assert timestamps == Enum.sort(timestamps)
    end

    test "respects count parameter to limit data range" do
      now = System.system_time(:second)
      base = div(now, 300) * 300

      # Insert 20 candles
      for i <- 0..19 do
        insert_candle(base - i * 300, 1.0, 1.1, 0.9, 1.0)
      end

      # Request only 5 candles worth of time
      candles = LPBuxPriceTracker.get_candles(300, 5)
      assert length(candles) <= 5
    end
  end

  describe "get_stats/0" do
    test "returns high/low for each timeframe" do
      now = System.system_time(:second)
      base = div(now, 300) * 300
      insert_candle(base, 1.0, 1.5, 0.8, 1.2)

      stats = LPBuxPriceTracker.get_stats()
      assert Map.has_key?(stats, :price_1h)
      assert Map.has_key?(stats, :price_24h)
      assert Map.has_key?(stats, :price_7d)
      assert Map.has_key?(stats, :price_30d)
      assert Map.has_key?(stats, :price_all)
    end

    test "returns nil high/low when no data for a timeframe" do
      stats = LPBuxPriceTracker.get_stats()
      assert stats.price_1h == %{high: nil, low: nil}
    end
  end

  # ============ Price Parsing (tested via public API indirectly) ============

  describe "price parsing" do
    # These test the parse_price/1 function indirectly through module behavior
    test "handles standard wei values" do
      # 1e18 wei = 1.0
      now = System.system_time(:second)
      base = div(now, 300) * 300
      insert_candle(base, 1.0, 1.0, 1.0, 1.0)
      candles = LPBuxPriceTracker.get_candles(300, 1)
      assert length(candles) >= 1
    end
  end

  # ============ Mnesia Integration ============

  describe "candle storage" do
    test "candles are ordered by timestamp (ordered_set)" do
      insert_candle(300, 1.0, 1.1, 0.9, 1.05)
      insert_candle(100, 0.9, 1.0, 0.8, 0.95)
      insert_candle(200, 0.95, 1.05, 0.85, 1.0)

      all = :mnesia.dirty_select(:lp_bux_candles, [
        {{:lp_bux_candles, :"$1", :"$2", :"$3", :"$4", :"$5"},
         [],
         [{{:"$1", :"$2", :"$3", :"$4", :"$5"}}]}
      ])

      timestamps = Enum.map(all, &elem(&1, 0))
      assert timestamps == Enum.sort(timestamps)
    end

    test "dirty_select with range works" do
      insert_candle(100, 1.0, 1.1, 0.9, 1.0)
      insert_candle(200, 1.0, 1.1, 0.9, 1.0)
      insert_candle(300, 1.0, 1.1, 0.9, 1.0)
      insert_candle(400, 1.0, 1.1, 0.9, 1.0)

      # Select only ts >= 200 and <= 300
      result = :mnesia.dirty_select(:lp_bux_candles, [
        {{:lp_bux_candles, :"$1", :"$2", :"$3", :"$4", :"$5"},
         [{:>=, :"$1", 200}, {:"=<", :"$1", 300}],
         [{{:"$1"}}]}
      ])

      timestamps = Enum.map(result, &elem(&1, 0))
      assert length(timestamps) == 2
      assert 200 in timestamps
      assert 300 in timestamps
    end
  end
end
```

**Expected test count:** ~15 tests

### 10.5 BankrollLive Tests

**File:** `test/blockster_v2_web/live/bankroll_live_test.exs`

```elixir
defmodule BlocksterV2Web.BankrollLiveTest do
  use BlocksterV2Web.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias BlocksterV2.{Repo, Accounts.User}

  setup do
    # Create test user
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        email: "bankroll_test@test.com",
        wallet_address: "0xTestWallet",
        smart_wallet_address: "0xTestSmartWallet"
      })
      |> Repo.insert()

    # Ensure Mnesia tables exist
    :mnesia.create_table(:lp_bux_candles, [
      attributes: [:timestamp, :open, :high, :low, :close],
      type: :ordered_set,
      disc_copies: []
    ])
    :mnesia.create_table(:user_bux_balances, [
      attributes: [:user_id, :balances],
      type: :set,
      disc_copies: []
    ])

    on_exit(fn ->
      :mnesia.clear_table(:lp_bux_candles)
      Repo.delete(user)
    end)

    %{user: user}
  end

  describe "mount (unauthenticated)" do
    test "renders bankroll page with pool stats", %{conn: conn} do
      {:ok, view, html} = live(conn, "/bankroll")
      assert html =~ "BUX Bankroll"
      assert html =~ "Total BUX"
      assert html =~ "LP Price"
    end

    test "shows login prompt instead of deposit/withdraw", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "Log in to deposit"
      refute html =~ "DEPOSIT"
    end

    test "does not show LP balance section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      refute html =~ "LP Balance:"
    end
  end

  describe "mount (authenticated)" do
    test "renders deposit and withdraw cards", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "Deposit BUX"
      assert html =~ "Withdraw LP-BUX"
      assert html =~ "DEPOSIT"
      assert html =~ "WITHDRAW"
    end

    test "shows user's BUX balance", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "Balance:"
    end
  end

  describe "timeframe selection" do
    test "clicking timeframe tab updates selected_timeframe", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/bankroll")

      html = view
        |> element("button", "7D")
        |> render_click()

      # The 7D button should now have the highlighted style
      assert html =~ "bg-[#CAFC00]"
    end
  end

  describe "deposit flow" do
    test "updating deposit amount shows LP preview", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      html = view
        |> element("input[placeholder='Amount to deposit']")
        |> render_keyup(%{"value" => "1000"})

      assert html =~ "You receive:"
    end

    test "rejects zero deposit amount", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      # Set amount to empty/zero
      view |> element("input[placeholder='Amount to deposit']") |> render_keyup(%{"value" => "0"})
      html = view |> element("button", "DEPOSIT") |> render_click()

      assert html =~ "Enter a valid amount"
    end

    test "deposit_confirmed updates pool info", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      # Simulate JS hook pushing deposit_confirmed
      send(view.pid, %{event: "deposit_confirmed", params: %{"tx_hash" => "0xabc123"}})
      html = render(view)
      assert html =~ "Deposit confirmed"
    end

    test "deposit_failed shows error", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      # Simulate JS hook pushing deposit_failed
      send(view.pid, %{event: "deposit_failed", params: %{"error" => "Insufficient BUX"}})
      html = render(view)
      assert html =~ "Insufficient BUX"
    end
  end

  describe "withdraw flow" do
    test "updating withdraw amount shows BUX preview", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      html = view
        |> element("input[placeholder='LP-BUX to burn']")
        |> render_keyup(%{"value" => "500"})

      assert html =~ "You receive:"
    end

    test "rejects zero withdraw amount", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      view |> element("input[placeholder='LP-BUX to burn']") |> render_keyup(%{"value" => "0"})
      html = view |> element("button", "WITHDRAW") |> render_click()

      assert html =~ "Enter a valid amount"
    end
  end

  describe "PubSub handlers" do
    test "lp_bux_price_updated updates price", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/bankroll")

      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "lp_bux_price",
        {:lp_bux_price_updated, %{price: 1.25, candle: nil}}
      )

      # Give LiveView time to process
      :timer.sleep(50)
      html = render(view)
      assert html =~ "1.25"
    end
  end

  describe "chart rendering" do
    test "chart container is present with hook", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "lp-bux-chart"
      assert html =~ "LPBuxChart"
    end

    test "timeframe buttons are rendered", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "1H"
      assert html =~ "24H"
      assert html =~ "7D"
      assert html =~ "30D"
      assert html =~ "ALL"
    end
  end
end
```

**Expected test count:** ~20 tests

### 10.6 Total Test Counts by Phase

| Phase | File | Test Count |
|-------|------|------------|
| B1 | `BUXBankroll.test.js` | ~70 |
| B2 | `verify-bux-bankroll.js` | ~15 assertions |
| B4 | `lp_bux_price_tracker_test.exs` | ~15 |
| B5 | `bankroll_live_test.exs` | ~20 |
| **Total** | | **~105 tests + 15 deploy assertions** |
