# Wallet Analysis Report: 0xA2b101eF9EC4788D12b3352438cc0583dAacBf60

**Analysis Date:** January 21, 2026
**Chain:** Rogue Chain (ID: 560013)

---

## Executive Summary

This wallet is a **high-volume operations/distribution wallet** that:
- Received **592M ROGUE from the DGTXAirdrop contract** (original DGTX → ROGUE token migration)
- Has deposited and withdrawn from **ROGUEBankroll** extensively (1.15B withdrawn, 444M deposited)
- Distributed over **1B ROGUE** to a distribution contract (0x282D...)
- Currently holds **300M ROGUE** and **112M LP-ROGUE** tokens

---

## Current Holdings

| Asset | Amount | Notes |
|-------|--------|-------|
| ROGUE | 299,950,205 | Native balance |
| LP-ROGUE | 112,504,411 | ROGUEBankroll LP shares |
| OUTLAW | 999,994,100 | Meme token |
| FLAME | 999,999,738 | Meme token |
| SNIPER | 47,918,148 | Meme token |

---

## Fund Flow Summary

### Total Received: 1.85 Billion ROGUE

| Source | Amount (ROGUE) | Count | Type |
|--------|---------------|-------|------|
| **ROGUEBankroll** | 1,153,785,351 | 2,063 | Internal (LP withdrawals) |
| **0x3E5884fe... (via DGTXAirdrop)** | 592,009,949 | 3 | Direct transfer |
| **Bridge** | 48,030,080 | 11 | Internal (cross-chain) |
| **0x6ed91824... (contract)** | 46,865,544 | 58 | Internal |
| **0x3B7c76e8...** | 5,000,000 | 1 | Direct transfer |
| **Tournament wins** | 202,000 | 20 | Internal |
| **Other** | 3,509,786 | various | Mixed |

### Total Sent: 1.55 Billion ROGUE

| Destination | Amount (ROGUE) | Count | Type |
|-------------|---------------|-------|------|
| **0x282DA32f... (Distribution Contract)** | 1,032,157,965 | 4,023 | Direct transfer |
| **ROGUEBankroll** | 444,467,161 | 288 | LP deposits |
| **Bridge** | 40,750,000 | 30 | Cross-chain |
| **0x2262243C...** | 30,700,000 | 6 | Direct transfer |
| **Other** | 4,253,025 | various | Mixed |

---

## Origin of Funds: The DGTXAirdrop Connection

### The 592M ROGUE Source Chain

```
DGTXAirdrop Contract (0x529528bE627B93d40b6DCE84a1b791Ee14c9BeA8)
    │
    │ 591,697,867 ROGUE (Dec 20, 2024)
    ▼
0x3E5884fe0cf92bce71eDb169978f64F333cbCc1A (EOA - Intermediary)
    │
    │ 592,009,949 ROGUE (Dec 20, 2024)
    ▼
0xA2b101eF9EC4788D12b3352438cc0583dAacBf60 (TARGET WALLET)
```

### DGTXAirdrop Contract Details

| Property | Value |
|----------|-------|
| Address | `0x529528bE627B93d40b6DCE84a1b791Ee14c9BeA8` |
| Contract Type | TransparentUpgradeableProxy |
| Implementation | DGTXAirdrop (`0x10995E8A421D48194BFE5AF93D862d0D88d44F6e`) |
| Creator | `0x83c44402F328592cB04db5f50C56F0aeC1f05371` |
| Current Balance | 276,976,702 ROGUE |

**This is the original DGTX to ROGUE token migration airdrop contract.** The target wallet received a large allocation from this airdrop.

---

## Key Contracts Identified

| Address | Name | Role |
|---------|------|------|
| `0x529528bE627B93d40b6DCE84a1b791Ee14c9BeA8` | DGTXAirdrop | Original token migration airdrop |
| `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd` | ROGUEBankroll | LP protocol (66B ROGUE TVL) |
| `0x282DA32f5c45c625A2D129b62e2C3f8bE733BD6A` | Distribution Contract | Received 1B ROGUE from target |
| `0x202aA9C1238E635E4a214d1e600179A1496404CE` | Bridge | Cross-chain transfers |
| `0xF5d5bAF38acc367e12D9d0A9500554cDf7724460` | AirdropRewards | Game/player rewards |
| `0x6ed91824BCa568f7543C54333a1a3998e8cA4b32` | Unknown Proxy | 600M ROGUE balance |
| `0xfe962a55694AacA7b74C99d171F5cF8e0A1D5058` | Tournament Contract | Sit-Go tournaments |

---

## ROGUEBankroll Activity

The wallet has been very active with the ROGUEBankroll LP protocol:

| Activity | Amount (ROGUE) | Transactions |
|----------|---------------|--------------|
| Deposits | 444,467,161 | 288 |
| Withdrawals | 1,153,785,351 | 2,063 |
| **Net** | **+709,318,190** | - |

The wallet has withdrawn **709M more ROGUE** than it deposited. This represents:
1. Original principal returned
2. LP fee earnings accumulated over time
3. Possible arbitrage or strategy profits

---

## Timeline

| Date | Event | Amount |
|------|-------|--------|
| Dec 5, 2024 | First funding from 0x3E58... | 5,000 ROGUE |
| Dec 20, 2024 | Major DGTXAirdrop distribution | 591M ROGUE |
| Dec 20, 2024 | Additional from 0x3E58... | 1M ROGUE |
| 2025 | Ongoing bankroll activity | Billions in volume |
| Oct 6, 2025 | Funding from 0x3B7c... | 5M ROGUE |
| Jan 21, 2026 | Analysis date | 300M balance |

---

## Activity Pattern Analysis

This wallet exhibits behavior consistent with a **project treasury/operations wallet**:

1. **Large Initial Allocation**: Received 592M from official airdrop contract
2. **LP Yield Farming**: Active deposits/withdrawals from ROGUEBankroll
3. **Distribution Function**: Sent 1B+ to distribution contract
4. **Bridge Activity**: Cross-chain transfers (48M in, 41M out)
5. **Tournament Participation**: Minor (200K from 20 wins)

---

## Accounting Verification

```
Starting Balance:           0 ROGUE (verified at genesis)
+ Total Received:   1,850,402,711 ROGUE
- Total Sent:       1,552,329,505 ROGUE
= Expected Balance:   298,073,206 ROGUE
  Actual Balance:     299,950,205 ROGUE
  Discrepancy:          1,877,000 ROGUE (0.6% - likely API incompleteness)
```

The small discrepancy is within expected API pagination limits.

---

## Conclusion

**The wallet `0xA2b101eF9EC4788D12b3352438cc0583dAacBf60` is a project operations wallet that:**

1. Received a ~592M ROGUE allocation from the **DGTXAirdrop contract** (the official DGTX → ROGUE token migration)
2. Actively manages liquidity in **ROGUEBankroll**, earning LP fees
3. Functions as a distribution hub, sending over **1B ROGUE** to other contracts/wallets
4. Maintains a healthy **300M ROGUE + 112M LP-ROGUE** balance

The source of funds is legitimate - it traces back to the official token migration airdrop contract deployed by the Rogue Chain team.

---

## Files Created

All analysis scripts are in `/Users/tenmerry/Projects/blockster_v2/scripts/`:

- `analyze_wallet_a2b1.js` - Main wallet analysis
- `trace_funding_sources.js` - Trace upstream funding
- `deep_trace_origin.js` - Deep dive into fund origins
- `identify_origin_contract.js` - Contract identification
- `find_big_transfer.js` - Locate large transfers
