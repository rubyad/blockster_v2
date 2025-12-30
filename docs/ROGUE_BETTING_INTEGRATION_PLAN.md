# ROGUE Betting Integration Plan for BUX Booster

**Date**: December 30, 2025
**Objective**: Enable ROGUE (native gas token) betting in BUX Booster using the existing ROGUEBankroll contract as the house bankroll.

---

## Executive Summary

This plan outlines the integration of ROGUE betting into the BUX Booster coin flip game. Unlike BUX-flavored tokens (ERC-20), ROGUE is the native gas token of Rogue Chain and requires different handling:

1. **No token approvals needed** - ROGUE is sent directly with transaction value
2. **External bankroll** - House balance managed by ROGUEBankroll contract (0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd)
3. **Different settlement flow** - BuxBoosterGame forwards bets to bankroll and triggers payouts via bankroll

---

## Architecture Overview

### Current BuxBoosterGame (ERC-20 tokens)
```
Player → approve token → placeBet() → contract holds bet
                                    → settleBet() → contract pays from internal balance
```

### New ROGUE Flow (Separate Functions)
```
Player → placeBetROGUE{value: amount} → contract receives ROGUE
                                      → forwards to ROGUEBankroll.updateHouseBalanceBuxBoosterBetPlaced()
      → settleBetROGUE() → contract calls ROGUEBankroll.settleBuxBoosterWinningBet()
                                        or ROGUEBankroll.settleBuxBoosterLosingBet()
                        → ROGUEBankroll sends payout directly to player
```

**Key Design Decision**: Use separate `placeBetROGUE()` and `settleBetROGUE()` functions instead of modifying existing functions. This ensures:
- Zero risk to existing ERC-20 betting flow
- Clear separation of concerns
- Easier testing and auditing
- No changes to existing contracts' behavior

---

## Smart Contract Changes

### 1. BuxBoosterGame.sol Modifications

**Design Principle**: Add NEW functions instead of modifying existing ones. This ensures zero impact on existing ERC-20 betting flow.

#### 1.1 Add State Variables (V5 upgrade - append to end of state)

```solidity
// IMPORTANT: Add these at the END to preserve storage layout
address public rogueBankroll;  // Address of ROGUEBankroll contract
address constant ROGUE_TOKEN = address(0);  // Special address to represent ROGUE (native token)
```

#### 1.2 Add ROGUEBankroll Interface

```solidity
interface IROGUEBankroll {
    // New functions to be added to ROGUEBankroll for BuxBooster
    function updateHouseBalanceBuxBoosterBetPlaced(
        bytes32 commitmentHash,
        int8 difficulty,
        uint8[] calldata predictions,
        uint256 nonce,
        uint256 maxPayout  // Maximum possible payout for this bet
    ) external payable returns(bool);

    function settleBuxBoosterWinningBet(
        address winner,
        bytes32 commitmentHash,
        uint256 betAmount,
        uint256 payout,
        int8 difficulty,
        uint8[] calldata predictions,
        uint8[] calldata results,
        uint256 nonce,
        uint256 maxPayout  // Maximum possible payout (for liability calculation)
    ) external returns(bool);

    function settleBuxBoosterLosingBet(
        address player,
        bytes32 commitmentHash,
        uint256 wagerAmount,
        int8 difficulty,
        uint8[] calldata predictions,
        uint8[] calldata results,
        uint256 nonce,
        uint256 maxPayout  // Maximum possible payout (for liability calculation)
    ) external returns(bool);

    // Existing function (no changes)
    function getHouseInfo() external view returns (uint256 netBalance, uint256 totalBalance, uint256 minBetSize, uint256 maxBetSize);
}
```

#### 1.3 Add New `placeBetROGUE()` Function

**NEW separate function for ROGUE betting - does not modify existing `placeBet()`**

```solidity
/**
 * @notice Place a ROGUE bet (native token) using ROGUEBankroll
 * @dev Separate function from placeBet() to avoid modifying existing ERC-20 flow
 * @param amount The bet amount in wei
 * @param difficulty Game difficulty (-4 to -1 for Win One, 1 to 5 for Win All)
 * @param predictions Array of predictions (0=heads, 1=tails)
 * @param commitmentHash The commitment hash submitted by server BEFORE this bet
 */
function placeBetROGUE(
    uint256 amount,
    int8 difficulty,
    uint8[] calldata predictions,
    bytes32 commitmentHash
) external payable nonReentrant whenNotPaused {
    require(msg.value == amount, "ROGUE amount mismatch");

    // Validate commitment
    _validateCommitment(commitmentHash);

    // Validate bet params with ROGUE-specific validation
    _validateROGUEBetParams(amount, difficulty, predictions);

    // Get commitment to read the nonce
    Commitment storage commitment = commitments[commitmentHash];
    uint256 nonce = commitment.nonce;

    // Calculate max possible payout for this bet
    uint8 diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);
    uint256 maxPayout = (amount * MULTIPLIERS[diffIndex]) / 10000;

    // Forward bet to ROGUEBankroll (also sends the ROGUE and bet details)
    IROGUEBankroll(rogueBankroll).updateHouseBalanceBuxBoosterBetPlaced{value: amount}(
        commitmentHash,
        difficulty,
        predictions,
        nonce,
        maxPayout
    );

    // Create bet record using ROGUE_TOKEN address
    _createBet(ROGUE_TOKEN, amount, difficulty, predictions, commitmentHash);
}
```

**Note**: Existing `placeBet()` function remains unchanged - no modifications to ERC-20 betting flow.

#### 1.4 Add New `_validateROGUEBetParams()` Function

**NEW separate validation function for ROGUE bets - does not modify existing `_validateBetParams()`**

```solidity
/**
 * @notice Validate ROGUE bet parameters
 * @dev Queries ROGUEBankroll for max bet and house balance
 */
function _validateROGUEBetParams(
    uint256 amount,
    int8 difficulty,
    uint8[] calldata predictions
) internal view returns (uint8 diffIndex) {
    if (difficulty == 0 || difficulty < -4 || difficulty > 5) revert InvalidDifficulty();
    if (amount < MIN_BET) revert BetAmountTooLow();

    diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);

    if (predictions.length != FLIP_COUNTS[diffIndex]) revert InvalidPredictions();
    for (uint i = 0; i < predictions.length; i++) {
        if (predictions[i] > 1) revert InvalidPredictions();
    }

    // Query ROGUEBankroll for limits
    (uint256 netBalance, , uint256 minBetSize, uint256 maxBetFromBankroll) =
        IROGUEBankroll(rogueBankroll).getHouseInfo();

    if (amount < minBetSize) revert BetAmountTooLow();

    // Apply both ROGUEBankroll's max bet AND BuxBooster's multiplier-based max
    uint256 maxBetForMultiplier = _calculateMaxBet(netBalance, diffIndex);
    uint256 maxBet = maxBetFromBankroll < maxBetForMultiplier ? maxBetFromBankroll : maxBetForMultiplier;

    if (amount > maxBet) revert BetAmountTooHigh();

    uint256 potentialProfit = ((amount * MULTIPLIERS[diffIndex]) / 10000) - amount;
    if (netBalance < potentialProfit) revert InsufficientHouseBalance();
}
```

**Note**: Existing `_validateBetParams()` function remains unchanged for ERC-20 tokens.

#### 1.5 Add New `settleBetROGUE()` Function

**NEW separate settlement function for ROGUE bets - does not modify existing `settleBet()`**

```solidity
/**
 * @notice Settle a ROGUE bet by revealing the server seed and results
 * @dev Calls ROGUEBankroll for actual payout instead of handling internally
 * @param commitmentHash The commitment hash (also serves as betId)
 * @param serverSeed The revealed server seed
 * @param results The flip results calculated by server
 * @param won Whether the player won
 */
function settleBetROGUE(
    bytes32 commitmentHash,
    bytes32 serverSeed,
    uint8[] calldata results,
    bool won
) external onlySettler nonReentrant returns (uint256 payout) {
    Bet storage bet = bets[commitmentHash];

    if (bet.player == address(0)) revert BetNotFound();
    if (bet.token != ROGUE_TOKEN) revert InvalidToken(); // Ensure this is a ROGUE bet
    if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
    if (block.timestamp > bet.timestamp + BET_EXPIRY) revert BetExpiredError();
    if (results.length != bet.predictions.length) revert InvalidPredictions();

    // Store revealed server seed
    commitments[bet.commitmentHash].serverSeed = serverSeed;

    uint8 diffIndex = bet.difficulty < 0 ? uint8(int8(4) + bet.difficulty) : uint8(int8(3) + bet.difficulty);

    // Settle via ROGUEBankroll (pass results array for event emission)
    payout = _settleROGUEBet(bet, diffIndex, won, results);

    totalBetsSettled++;
    _emitSettled(commitmentHash, bet, won, results, payout, serverSeed);
}
```

**Note**: Existing `settleBet()` function remains unchanged for ERC-20 tokens.

#### 1.6 Add `_settleROGUEBet()` Helper Function

```solidity
function _settleROGUEBet(
    Bet storage bet,
    uint8 diffIndex,
    bool won,
    uint8[] calldata results
) internal returns (uint256 payout) {
    PlayerStats storage stats = playerStats[bet.player];

    stats.totalBets++;
    stats.totalStaked += bet.amount;
    stats.betsPerDifficulty[diffIndex]++;

    if (won) {
        payout = (bet.amount * MULTIPLIERS[diffIndex]) / 10000;
        bet.status = BetStatus.Won;

        int256 profit = int256(payout) - int256(bet.amount);
        stats.overallProfitLoss += profit;
        stats.profitLossPerDifficulty[diffIndex] += profit;

        // Calculate max payout for liability tracking
        uint256 maxPayout = (bet.amount * MULTIPLIERS[diffIndex]) / 10000;

        // Call ROGUEBankroll to settle winning bet (bankroll pays out directly)
        IROGUEBankroll(rogueBankroll).settleBuxBoosterWinningBet(
            bet.player,
            bet.commitmentHash,
            bet.amount,
            payout,
            bet.difficulty,
            bet.predictions,
            results,
            bet.nonce,
            maxPayout
        );
    } else {
        payout = 0;
        bet.status = BetStatus.Lost;

        stats.overallProfitLoss -= int256(bet.amount);
        stats.profitLossPerDifficulty[diffIndex] -= int256(bet.amount);

        // Calculate max payout for liability tracking
        uint256 maxPayout = (bet.amount * MULTIPLIERS[diffIndex]) / 10000;

        // Call ROGUEBankroll to update house balance for losing bet
        IROGUEBankroll(rogueBankroll).settleBuxBoosterLosingBet(
            bet.player,
            bet.commitmentHash,
            bet.amount,
            bet.difficulty,
            bet.predictions,
            results,
            bet.nonce,
            maxPayout
        );
    }
}
```

#### 1.7 Add New `getMaxBetROGUE()` Function

**NEW separate function for ROGUE max bet - does not modify existing `getMaxBet()`**

```solidity
/**
 * @notice Get maximum bet size for ROGUE at given difficulty
 * @dev Queries ROGUEBankroll and applies multiplier-based constraints
 * @param difficulty Game difficulty (-4 to -1 for Win One, 1 to 5 for Win All)
 * @return Maximum allowed bet in wei
 */
function getMaxBetROGUE(int8 difficulty) external view returns (uint256) {
    if (difficulty == 0 || difficulty < -4 || difficulty > 5) return 0;

    // Get limits from ROGUEBankroll
    (uint256 netBalance, , , uint256 maxBetFromBankroll) = IROGUEBankroll(rogueBankroll).getHouseInfo();

    // Calculate our multiplier-based max bet
    uint8 diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);
    uint256 maxBetForMultiplier = _calculateMaxBet(netBalance, diffIndex);

    // Return the minimum of both constraints
    return maxBetFromBankroll < maxBetForMultiplier ? maxBetFromBankroll : maxBetForMultiplier;
}
```

**Note**: Existing `getMaxBet()` function remains unchanged for ERC-20 tokens.

#### 1.8 Add Admin Function to Set ROGUEBankroll Address

```solidity
function setROGUEBankroll(address _rogueBankroll) external onlyOwner {
    rogueBankroll = _rogueBankroll;
}
```

#### 1.9 Add InitializeV5 Function

```solidity
/**
 * @notice Initialize V5 - ROGUE betting support
 * @param _rogueBankroll Address of ROGUEBankroll contract
 */
function initializeV5(address _rogueBankroll) reinitializer(5) public {
    rogueBankroll = _rogueBankroll;
}
```

---

## ROGUEBankroll Contract Changes

### 6. Add New Functions to ROGUEBankroll.sol

**IMPORTANT**: These functions must be added to ROGUEBankroll contract to preserve storage layout.

#### 6.1 Add State Variable (Append to End)

```solidity
// Add after existing state variables (line ~933)
address public buxBoosterGame;  // Authorized BuxBooster game contract
```

#### 6.2 Add Authorization Modifier

```solidity
modifier onlyBuxBooster() {
    require(msg.sender == buxBoosterGame, "Only BuxBooster can call this function");
    _;
}
```

#### 6.3 Add `updateHouseBalanceBuxBoosterBetPlaced()` Function

```solidity
/**
 * @notice Update house balance when BuxBooster bet is placed
 * @dev Called by BuxBoosterGame contract with ROGUE sent as msg.value
 * @param commitmentHash Bet identifier (commitment hash)
 * @param difficulty Game difficulty (-4 to -1 for Win One, 1 to 5 for Win All)
 * @param predictions Player's predictions array
 * @param nonce Player's nonce for this bet
 * @param maxPayout Maximum possible payout for this bet (based on multiplier)
 * @return success True if update successful
 */
function updateHouseBalanceBuxBoosterBetPlaced(
    bytes32 commitmentHash,
    int8 difficulty,
    uint8[] calldata predictions,
    uint256 nonce,
    uint256 maxPayout
) external payable onlyBuxBooster returns(bool) {
    require(msg.value >= minimumBetSize, "Your bet is below the minimum bet size");
    require(msg.value <= (houseBalance.net_balance / maximumBetSizeDivisor), "Your bet is above the maximum bet size");

    houseBalance.total_balance += msg.value;
    // Add liability based on actual max payout for this specific bet (not 2x)
    houseBalance.liability += maxPayout;
    houseBalance.unsettled_bets += msg.value;
    houseBalance.net_balance = houseBalance.total_balance - houseBalance.liability;
    houseBalance.actual_balance = address(this).balance;

    // Emit comprehensive bet placement event
    emit BuxBoosterBetPlaced(
        msg.sender,
        commitmentHash,
        msg.value,
        difficulty,
        predictions,
        nonce,
        block.timestamp
    );

    return true;
}
```

**Note**: Liability is set to the actual maximum possible payout (betAmount × multiplier), not a fixed 2x. This ensures accurate house balance tracking across all 9 difficulty levels (1.02x to 31.68x).

#### 6.4 Add New Events for BuxBooster

```solidity
// Add new events specifically for BuxBooster (completely separate from existing events)
event BuxBoosterBetPlaced(
    address indexed player,
    bytes32 indexed commitmentHash,
    uint256 amount,
    int8 difficulty,
    uint8[] predictions,
    uint256 nonce,
    uint256 timestamp
);

event BuxBoosterWinningPayout(
    address indexed winner,
    bytes32 indexed commitmentHash,
    uint256 betAmount,
    uint256 payout,
    uint256 profit,
    int8 difficulty,
    uint8[] predictions,
    uint8[] results,
    uint256 nonce
);

event BuxBoosterLosingBet(
    address indexed player,
    bytes32 indexed commitmentHash,
    uint256 betAmount,
    int8 difficulty,
    uint8[] predictions,
    uint8[] results,
    uint256 nonce
);

event BuxBoosterPayoutFailed(
    address indexed winner,
    bytes32 indexed commitmentHash,
    uint256 payout
);
```

#### 6.5 Add `settleBuxBoosterWinningBet()` Function

```solidity
/**
 * @notice Settle a winning BuxBooster bet and pay out winner
 * @dev NEW function specifically for BuxBooster - does not use legacy Payout event
 * @param winner Player address
 * @param commitmentHash Bet identifier (commitment hash)
 * @param betAmount Original bet amount
 * @param payout Total payout amount (includes original wager)
 * @param difficulty Game difficulty
 * @param predictions Player's predictions
 * @param results Actual game results
 * @param nonce Player's nonce
 * @param maxPayout Maximum possible payout (for liability calculation)
 * @return success True if settlement successful
 */
function settleBuxBoosterWinningBet(
    address winner,
    bytes32 commitmentHash,
    uint256 betAmount,
    uint256 payout,
    int8 difficulty,
    uint8[] calldata predictions,
    uint8[] calldata results,
    uint256 nonce,
    uint256 maxPayout
) external onlyBuxBooster returns(bool) {
    HouseBalance memory hb = houseBalance;

    uint256 profit = payout - betAmount;

    // Update house balance
    hb.total_balance -= payout;
    // Remove the liability that was added when bet was placed (using actual maxPayout)
    hb.liability -= maxPayout;
    hb.unsettled_bets -= betAmount;
    hb.net_balance = hb.total_balance - hb.liability;
    hb.pool_token_supply = this.totalSupply();
    hb.pool_token_price = ((hb.total_balance - hb.unsettled_bets) * 1000000000000000000) / hb.pool_token_supply;
    hb.actual_balance = address(this).balance;

    // Update player stats
    players[winner].winners += 1;
    players[winner].betCount += 1;
    players[winner].rogue_winnings += profit;

    // Send payout to winner
    (bool sent,) = payable(winner).call{value: payout}("");
    if (sent) {
        houseBalance = hb;
        emit BuxBoosterWinningPayout(
            winner,
            commitmentHash,
            betAmount,
            payout,
            profit,
            difficulty,
            predictions,
            results,
            nonce
        );
    } else {
        // If send fails, add to player's internal balance for later withdrawal
        players[winner].rogue_balance += payout;
        houseBalance = hb;
        emit BuxBoosterPayoutFailed(winner, commitmentHash, payout);
    }

    return true;
}
```

#### 6.6 Add `settleBuxBoosterLosingBet()` Function

```solidity
/**
 * @notice Settle a losing BuxBooster bet (updates house balance only)
 * @dev NEW function specifically for BuxBooster - does not use legacy events
 * @param player Player address
 * @param commitmentHash Unique bet identifier (commitment hash)
 * @param wagerAmount Amount wagered
 * @param difficulty Difficulty level selected
 * @param predictions Array of player predictions
 * @param results Array of actual results
 * @param nonce Player's nonce for this bet
 * @param maxPayout Maximum possible payout (for liability calculation)
 * @return success True if update successful
 */
function settleBuxBoosterLosingBet(
    address player,
    bytes32 commitmentHash,
    uint256 wagerAmount,
    int8 difficulty,
    uint8[] calldata predictions,
    uint8[] calldata results,
    uint256 nonce,
    uint256 maxPayout
) external onlyBuxBooster returns(bool) {
    houseBalance.liability -= maxPayout;  // Remove the liability that was added when bet was placed
    houseBalance.unsettled_bets -= wagerAmount;
    houseBalance.net_balance = houseBalance.total_balance - houseBalance.liability;
    houseBalance.actual_balance = address(this).balance;
    houseBalance.pool_token_supply = this.totalSupply();
    houseBalance.pool_token_price = ((houseBalance.total_balance - houseBalance.unsettled_bets) * 1000000000000000000) / houseBalance.pool_token_supply;

    // Update player stats
    players[player].losers += 1;
    players[player].betCount += 1;
    players[player].rogue_losses += wagerAmount;

    // Emit BuxBooster-specific event with comprehensive information
    emit BuxBoosterLosingBet(
        player,
        commitmentHash,
        wagerAmount,
        difficulty,
        predictions,
        results,
        nonce
    );

    return true;
}
```

#### 6.7 Add Admin Function to Set BuxBooster Address

```solidity
/**
 * @notice Set the authorized BuxBooster game contract address
 * @param _buxBoosterGame Address of BuxBoosterGame contract
 */
function setBuxBoosterGame(address _buxBoosterGame) external onlyOwner {
    buxBoosterGame = _buxBoosterGame;
}
```

#### 6.8 Add Getter for BuxBooster Address

```solidity
/**
 * @notice Get the authorized BuxBooster game contract address
 * @return Address of BuxBoosterGame contract
 */
function getBuxBoosterGame() external view returns (address) {
    return buxBoosterGame;
}
```

**Storage Layout Notes**:
- `buxBoosterGame` address variable added at the END of state variables (after line ~933)
- No reordering of existing variables
- No removal of existing variables
- This ensures storage layout compatibility with existing proxy

---

## Frontend Changes (Phoenix/JavaScript)

### 2. BUX Minter Service Updates

#### 2.1 Add ROGUEBankroll Contract ABI

**File**: `bux-minter/abis/ROGUEBankroll.json`

Extract ABI from deployed contract at `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd`

#### 2.2 Add House Balance Fetch for ROGUE

**File**: `bux-minter/index.js`

```javascript
// Add new endpoint to get ROGUE house balance
app.get('/rogue-house-balance', async (req, res) => {
  try {
    const rogueBankroll = new ethers.Contract(
      ROGUE_BANKROLL_ADDRESS,
      ROGUEBankrollABI,
      provider
    );

    const [netBalance, totalBalance, minBetSize, maxBetSize] =
      await rogueBankroll.getHouseInfo();

    res.json({
      netBalance: ethers.formatEther(netBalance),
      totalBalance: ethers.formatEther(totalBalance),
      minBetSize: ethers.formatEther(minBetSize),
      maxBetSize: ethers.formatEther(maxBetSize)
    });
  } catch (error) {
    console.error('Error fetching ROGUE house balance:', error);
    res.status(500).json({ error: error.message });
  }
});
```

### 3. Phoenix Backend Changes

#### 3.1 Update BuxMinter Module

**File**: `lib/blockster_v2/bux_minter.ex`

```elixir
def get_rogue_house_balance do
  case HTTPoison.get("#{@base_url}/rogue-house-balance") do
    {:ok, %{status_code: 200, body: body}} ->
      case Jason.decode(body) do
        {:ok, %{"netBalance" => balance}} ->
          {balance_float, _} = Float.parse(balance)
          {:ok, balance_float}
        {:error, reason} ->
          {:error, reason}
      end
    {:ok, %{status_code: status}} ->
      {:error, "HTTP #{status}"}
    {:error, reason} ->
      {:error, reason}
  end
end
```

#### 3.2 Update BuxBoosterLive Module

**File**: `lib/blockster_v2_web/live/bux_booster_live.ex`

**Changes:**

1. Add ROGUE to token list in mount:
```elixir
# ROGUE is represented as "ROGUE" but contract address is address(0)
tokens = ["BUX", "ROGUE", "moonBUX", "neoBUX", ...]
```

2. Handle ROGUE house balance fetch:
```elixir
defp fetch_house_balance_async(socket, token) do
  if token == "ROGUE" do
    start_async(socket, :fetch_house_balance, fn ->
      case BuxMinter.get_rogue_house_balance() do
        {:ok, balance} ->
          max_bet = calculate_max_bet_from_bankroll(balance, ...)
          {balance, max_bet}
        {:error, _} ->
          {0.0, 0}
      end
    end)
  else
    # Existing logic for BUX tokens
  end
end
```

### 4. JavaScript Frontend Changes

#### 4.1 Update bux_booster_onchain.js

**File**: `assets/js/bux_booster_onchain.js`

**Key changes:**

1. **Token contract address mapping:**
```javascript
const TOKEN_ADDRESSES = {
  "BUX": "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8",
  "ROGUE": "0x0000000000000000000000000000000000000000",  // Special address
  "moonBUX": "0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5",
  // ... other tokens
};
```

2. **Skip approval for ROGUE:**
```javascript
async function placeOnchainBet(token, amount, difficulty, predictions, commitmentHash) {
  const tokenAddress = TOKEN_ADDRESSES[token];

  if (tokenAddress === "0x0000000000000000000000000000000000000000") {
    // ROGUE - no approval needed, send value directly
    return await placeBetROGUE(amount, difficulty, predictions, commitmentHash);
  } else {
    // ERC-20 flow (existing)
    await approveToken(tokenAddress, amount);
    return await placeBetERC20(tokenAddress, amount, difficulty, predictions, commitmentHash);
  }
}
```

3. **Add ROGUE-specific bet function:**
```javascript
async function placeBetROGUE(amount, difficulty, predictions, commitmentHash) {
  const gameContract = new ethers.Contract(GAME_ADDRESS, gameABI, signer);

  // Convert predictions array (heads/tails strings to 0/1)
  const predictionValues = predictions.map(p => p === 'heads' ? 0 : 1);

  // Call NEW placeBetROGUE function (not placeBet)
  const tx = await gameContract.placeBetROGUE(
    ethers.parseEther(amount.toString()),
    difficulty,
    predictionValues,
    commitmentHash,
    { value: ethers.parseEther(amount.toString()) }  // Send ROGUE
  );

  return await tx.wait();
}
```

4. **Update balance fetching:**
```javascript
async function getROGUEBalance(address) {
  const provider = new ethers.BrowserProvider(window.ethereum);
  const balance = await provider.getBalance(address);
  return ethers.formatEther(balance);
}
```

---

## Database/Mnesia Changes

### 5. Token Balance Tracking

**No changes needed** - ROGUE is already tracked separately in `user_rogue_balances` table (different from `user_bux_balances`).

**Important**: Ensure ROGUE balance updates continue to exclude ROGUE from aggregate BUX total.

---

## Testing Plan

### Phase 1: Contract Testing (Local)

1. Deploy BuxBoosterGame V5 to local Rogue Chain testnet
2. Call `initializeV5(ROGUE_BANKROLL_ADDRESS)`
3. Test ROGUE bet placement with `msg.value`
4. Verify bet forwarding to ROGUEBankroll
5. Test settlement (both win and loss scenarios)
6. Verify ROGUEBankroll pays winners correctly

### Phase 2: Integration Testing

1. Test Phoenix → BUX Minter → Contract flow
2. Test ROGUE house balance fetching
3. Test max bet calculation from ROGUEBankroll
4. Verify UI displays ROGUE balance correctly
5. Test bet placement from UI (no approval needed)

### Phase 3: Production Deployment

1. Deploy V5 implementation to mainnet
2. Upgrade proxy via UUPS
3. Call `initializeV5("0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd")`
4. Verify with small test bet
5. Monitor first production ROGUE bets

---

## Security Considerations

### 1. ROGUEBankroll Trust

**Risk**: BuxBoosterGame forwards ROGUE to ROGUEBankroll and trusts it to pay winners.

**Mitigation**:
- ROGUEBankroll is already deployed and audited (used by another game)
- Contract address is hardcoded and verified
- Only owner can change ROGUEBankroll address

### 2. Re-entrancy Protection

**Risk**: ROGUE transfers could be vulnerable to re-entrancy.

**Mitigation**:
- All bet functions already use `nonReentrant` modifier
- ROGUEBankroll handles actual ROGUE transfers (not BuxBoosterGame)

### 3. Access Control

**Risk**: Unauthorized calls to ROGUEBankroll functions.

**Mitigation**:
- ROGUEBankroll requires `msg.sender == rogueTrader` for settlement functions
- BuxBoosterGame must be set as authorized caller in ROGUEBankroll
- Owner must call `ROGUEBankroll.setAddress(BuxBoosterGameAddress)` after deployment

### 4. Balance Synchronization

**Risk**: ROGUE balance in ROGUEBankroll could become out of sync.

**Mitigation**:
- Always query `getHouseInfo()` for fresh balance data
- Don't cache ROGUE house balance in BuxBoosterGame
- ROGUEBankroll manages its own accounting

---

## Deployment Checklist

### Pre-Deployment

- [ ] Review and test all contract changes locally
- [ ] Audit V5 upgrade for storage layout correctness (BuxBoosterGame)
- [ ] Audit ROGUEBankroll changes for storage layout correctness
- [ ] Test ROGUEBankroll integration thoroughly
- [ ] Prepare deployment scripts for both contracts
- [ ] Document new ROGUE betting flow

### Deployment Steps

#### Part 1: ROGUEBankroll Upgrade

1. [ ] Compile updated ROGUEBankroll contract with new functions
2. [ ] Deploy new ROGUEBankroll implementation to mainnet
3. [ ] Verify contract on Roguescan
4. [ ] Call `upgradeToAndCall()` on ROGUEBankroll proxy (0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd)
5. [ ] Verify ROGUEBankroll upgrade successful

#### Part 2: BuxBoosterGame Upgrade

6. [ ] Compile BuxBoosterGame V5 contract
7. [ ] Deploy new BuxBoosterGame implementation to mainnet
8. [ ] Verify contract on Roguescan
9. [ ] Call `upgradeToAndCall()` on BuxBoosterGame proxy
10. [ ] Call `initializeV5(0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd)`
11. [ ] Verify upgrade with test call

#### Part 3: Authorization Setup

12. [ ] Call `ROGUEBankroll.setBuxBoosterGame(BuxBoosterGameProxyAddress)` as owner
13. [ ] Verify authorization with `getBuxBoosterGame()` call

#### Part 4: Application Updates

14. [ ] Deploy BUX Minter updates
15. [ ] Deploy Phoenix updates
16. [ ] Test with small ROGUE bet (1-10 ROGUE)
17. [ ] Monitor first 10 production bets
18. [ ] Update documentation

### Post-Deployment

- [ ] Add ROGUE to token dropdown in UI
- [ ] Update help text to explain ROGUE betting differences
- [ ] Monitor ROGUEBankroll balance via dashboard
- [ ] Track ROGUE betting metrics in analytics

---

## Configuration Values

| Item | Value | Notes |
|------|-------|-------|
| ROGUEBankroll Address | `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd` | Mainnet (verified) |
| ROGUE Token Address | `address(0)` | Special value for native token |
| Current Bankroll | ~65 billion ROGUE | Verify before deployment |
| Min Bet Size | From `ROGUEBankroll.getMinimumBetSize()` | 100 ROGUE currently |
| Max Bet Divisor | From `ROGUEBankroll.getMaximumBetSizeDivisor()` | 1000 (0.1%) currently |

---

## Open Questions

1. **Approval Caching**: Should we clear localStorage approval cache when user switches to ROGUE (since no approval needed)?
   - **Answer**: Yes, add logic to skip approval check entirely for ROGUE

2. **Error Handling**: What if ROGUEBankroll payout fails?
   - **Answer**: ROGUEBankroll has fallback logic - adds to player's internal balance if transfer fails

3. **Max Bet Calculation**: Should BuxBoosterGame apply its own multiplier-based max bet on top of ROGUEBankroll's max?
   - **Answer**: Yes, take the minimum of both constraints

4. **UI Differentiation**: How to clearly show users that ROGUE betting doesn't require approval?
   - **Answer**: Add tooltip/info icon explaining ROGUE is native token (no approval step)

---

## Success Criteria

1. ✅ ROGUE appears in token dropdown
2. ✅ ROGUE bets place without approval transaction using `placeBetROGUE()`
3. ✅ ROGUE bets forward correctly to `ROGUEBankroll.updateHouseBalanceBuxBoosterBetPlaced()`
4. ✅ Winners receive ROGUE payouts from `ROGUEBankroll.settleBuxBoosterWinningBet()`
5. ✅ Losers' bets are correctly recorded via `ROGUEBankroll.settleBuxBoosterLosingBet()`
6. ✅ House balance displays correctly for ROGUE via `getHouseInfo()`
7. ✅ Max bet calculation respects ROGUEBankroll limits via `getMaxBetROGUE()`
8. ✅ All existing BUX token betting continues to work (zero changes to `placeBet()`, `settleBet()`)
9. ✅ ROGUEBankroll storage layout preserved (new state variable appended to end)
10. ✅ BuxBoosterGame authorized in ROGUEBankroll via `setBuxBoosterGame()`

---

## Timeline Estimate

| Phase | Duration | Tasks |
|-------|----------|-------|
| **Contract Development** | 2-3 days | Write V5 code, add ROGUEBankroll interface, test locally |
| **Frontend Development** | 1-2 days | Update JavaScript, add ROGUE handling, update UI |
| **Backend Development** | 1 day | Add ROGUE balance fetching, update BuxMinter |
| **Testing** | 2-3 days | Integration tests, testnet deployment, security review |
| **Deployment** | 1 day | Mainnet upgrade, verification, monitoring |
| **Total** | **7-10 days** | End-to-end implementation |

---

## Risk Assessment

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| ROGUEBankroll contract bug | HIGH | LOW | Already deployed and tested by other game |
| Storage layout corruption | HIGH | LOW | Careful V5 upgrade, append-only state variables |
| Failed ROGUE transfers | MEDIUM | LOW | ROGUEBankroll has fallback mechanisms |
| Max bet calculation error | MEDIUM | MEDIUM | Thorough testing with various difficulty levels |
| Unauthorized access to ROGUEBankroll | HIGH | LOW | Access control already implemented in ROGUEBankroll |

---

## Future Enhancements

1. **ROGUE Staking**: Allow ROGUE holders to stake in ROGUEBankroll and earn from house edge
2. **Multi-Game Support**: Use same ROGUEBankroll for other games (dice, crash, etc.)
3. **Dynamic Max Bet**: Adjust max bet based on recent volatility
4. **ROGUE Analytics**: Track ROGUE betting separately from BUX tokens

---

## References

- [BuxBoosterGame Contract](contracts/bux-booster-game/contracts/BuxBoosterGame.sol)
- [ROGUEBankroll Contract](contracts/bux-booster-game/contracts/ROGUEBankroll.sol)
- [UUPS Upgrade Guide](docs/contract_upgrades.md)
- [Rogue Chain Documentation](https://roguescan.io)
- [Account Abstraction Performance Optimizations](docs/AA_PERFORMANCE_OPTIMIZATIONS.md)
