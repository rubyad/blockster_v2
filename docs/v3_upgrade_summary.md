# BuxBoosterGame V3 Upgrade Summary

## Problem Solved

**Issue**: On-chain game results were showing incorrect win/loss outcomes because of a mismatch between how the Elixir server and Solidity contract calculated the combined seed. Specifically, the nonce was encoded differently (string vs uint256 bytes), leading to different results.

**Root Cause**: The Elixir code converted nonce to a string (`"32"`), while Solidity's `abi.encodePacked` encoded uint256 as 32 bytes in big-endian format.

## Solution: Server-Side Result Calculation

Instead of trying to perfectly match Solidity's encoding in Elixir, we redesigned the contract to accept results from the server. This:
- **Eliminates the synchronization problem** - only one source of truth (server)
- **Reduces gas costs** - contract doesn't need to generate results on-chain
- **Simplifies the contract** - removed ~100 lines of result generation code
- **Maintains provably fair** - server seed is still revealed and can be verified off-chain

## Changes Made

### 1. Smart Contract (`BuxBoosterGame.sol`)

#### Changed bet ID from hash to commitment hash
- **Before**: `betId = keccak256(abi.encodePacked(msg.sender, token, nonce, block.timestamp))`
- **After**: `betId = commitmentHash`
- **Benefit**: Simpler, more gas efficient, commitment hash is already unique

#### Updated `settleBet` function signature
```solidity
// V2
function settleBet(bytes32 betId, bytes32 serverSeed)
    external returns (bool won, uint8[] memory results, uint256 payout)

// V3
function settleBet(
    bytes32 commitmentHash,  // Now serves as betId
    bytes32 serverSeed,
    uint8[] calldata results,  // Server provides results
    bool won                   // Server determines win/loss
) external returns (uint256 payout)
```

#### Enhanced `BetSettled` event
```solidity
// V2
event BetSettled(
    bytes32 indexed betId,
    address indexed player,
    bool won,
    uint8[] results,
    uint256 payout,
    bytes32 serverSeed
);

// V3 - Now includes full game context
event BetSettled(
    bytes32 indexed commitmentHash,
    address indexed player,
    address indexed token,
    uint256 amount,
    int8 difficulty,
    uint8[] predictions,
    bool won,
    uint8[] results,
    uint256 payout,
    bytes32 serverSeed,
    uint256 nonce,
    uint256 timestamp
);
```

#### Removed functions
- `_generateClientSeed()` - No longer needed
- `_generateResults()` - No longer needed
- `_checkWin()` - No longer needed
- `_addressToString()`, `_uint256ToString()`, `_int8ToString()` - No longer needed

#### Added `initializeV3()`
Empty reinitializer function to mark the upgrade. No state changes needed.

### 2. BUX Minter Service (`bux-minter/index.js`)

#### Updated `/settle-bet` endpoint
```javascript
// V2
app.post('/settle-bet', authenticate, async (req, res) => {
  const { betId, serverSeed } = req.body;
  const tx = await buxBoosterContract.settleBet(betId, serverSeed);
  // ...
});

// V3
app.post('/settle-bet', authenticate, async (req, res) => {
  const { commitmentHash, serverSeed, results, won } = req.body;
  const tx = await buxBoosterContract.settleBet(
    commitmentHash,
    serverSeed,
    results,
    won
  );
  // ...
});
```

### 3. Elixir Server (`lib/blockster_v2/bux_booster_onchain.ex`)

#### Updated `settle_bet/4` private function
```elixir
# V2
defp settle_bet(bet_id, server_seed)

# V3
defp settle_bet(commitment_hash, server_seed, results, won)
```

Now converts results to integers and includes them in the API call:
```elixir
results_int = Enum.map(results, fn
  :heads -> 0
  :tails -> 1
end)

body = Jason.encode!(%{
  "commitmentHash" => commitment_hash,
  "serverSeed" => server_seed,
  "results" => results_int,
  "won" => won
})
```

#### Updated `settle_game/1` function
Now calls `settle_bet` with commitment_hash and results:
```elixir
case settle_bet(game.commitment_hash, server_seed_hex, game.results, game.won) do
  {:ok, tx_hash, player_balance} -> # ...
end
```

## Deployment Steps

### 1. Deploy and Upgrade Contract
```bash
cd contracts/bux-booster-game

# Compile
npx hardhat compile

# Upgrade using manual upgrade script (if needed)
npx hardhat run scripts/upgrade-manual.js --network rogueMainnet

# Call initializeV3
npx hardhat run scripts/init-v3.js --network rogueMainnet

# Verify upgrade
npx hardhat run scripts/verify-upgrade.js --network rogueMainnet
```

### 2. Deploy BUX Minter
```bash
cd bux-minter
flyctl deploy  # Deploys to bux-minter.fly.dev
```

### 3. Restart Blockster Nodes
```bash
# Terminal 1
elixir --sname node1 -S mix phx.server

# Terminal 2
PORT=4001 elixir --sname node2 -S mix phx.server
```

## Breaking Changes

### Client-Side JavaScript
The client code doesn't directly call the contract for settlement, so no changes needed. The bet flow remains:
1. Player places bet via `placeBet()`
2. Server calculates results
3. Server calls BUX Minter `/settle-bet` with results
4. Contract emits `BetSettled` event with full details

### Event Listeners
If any code listens to `BetSettled` events, update the event structure to use the new fields.

## Verification

After upgrade, players can still verify game fairness:
1. Get `commitmentHash` shown before bet
2. After settlement, get revealed `serverSeed` from BetSettled event
3. Verify `SHA256(serverSeed) == commitmentHash`
4. Recalculate results using revealed seed and verify they match

The difference is results are now calculated server-side instead of on-chain, but the cryptographic commitment still proves the server couldn't change the outcome after seeing the player's predictions.

## Gas Savings

Estimated gas savings per settlement:
- **V2**: ~200k gas (result generation + verification)
- **V3**: ~150k gas (just verify seed and transfer tokens)
- **Savings**: ~50k gas per bet (~25% reduction)

## Security Considerations

**Trust Model Change**:
- V2: Contract calculated results (trustless)
- V3: Server calculates results (requires trust in server)

However, provably fair guarantees remain:
- Server commits before seeing predictions ✓
- Server reveals seed after settlement ✓
- Players can verify results off-chain ✓
- Contract verifies seed matches commitment ✓

The server could theoretically send wrong results, but:
1. Players can verify and dispute if results don't match revealed seed
2. All results are logged in BetSettled event for transparency
3. Reputation risk makes cheating impractical

## Future Improvements

1. **Dispute mechanism**: Allow players to challenge results if they don't match the revealed seed
2. **Result verification contract**: Optional view function to verify results match seed (for extra transparency)
3. **Event indexing**: Index BetSettled events for easier verification by players

---

**Upgrade completed**: December 28, 2025
**Contract address**: 0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B (proxy)
**Network**: Rogue Chain Mainnet (Chain ID: 560013)
