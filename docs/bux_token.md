# BUX Token System

> **Note (January 2026)**: Hub tokens have been removed from the application. Only BUX (for rewards and shop discounts) and ROGUE (for BUX Booster betting) are active. This document retains hub token contract addresses for historical reference.

## Overview

The BUX token system consists of:
- **BUX**: The only ERC-20 token for reading/sharing rewards and shop discounts
- **ROGUE**: The native gas token of Rogue Chain used for BUX Booster betting (NOT an ERC-20 token)

## Active Tokens

| Token | Contract Address | Purpose |
|-------|------------------|---------|
| BUX | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` | Reading/sharing rewards, shop discounts |
| ROGUE | (native token - no contract) | BUX Booster betting, gas fees |

## Balance Display

**Header Display**:
- Shows only BUX and ROGUE balances
- No aggregate calculation needed (only one BUX token now)

**Calculation**:
```elixir
# Token balances returned by EngagementTracker
%{
  "BUX" => bux_balance,
  "ROGUE" => rogue_balance
}
```

---

# BUX Token Contract Details

**Contract Address:** `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8`

**Name:** BUX

**Symbol:** BUX

**Decimals:** 18

**Owner:** `0x2dDC1caA8e63B091D353b8E3E7e3Eeb6008DC7Cd`

**Total Supply:** Minted as needed

## Minting Tokens

To mint tokens, the owner can call:

```solidity
bux.mint(recipientAddress, amount)
```

---

# Deprecated Hub Tokens (Historical Reference)

> **IMPORTANT**: These tokens are no longer used by the application as of January 2026.
> The contracts still exist on Rogue Chain but the app no longer mints or tracks these tokens.

| Token | Contract Address | Former Owner Wallet |
|-------|------------------|---------------------|
| moonBUX | `0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5` | `0x198C14bAa29c8a01d6b08A08a9c32b61F1Aa011F` |
| neoBUX | `0x423656448374003C2cfEaFF88D5F64fb3A76487C` | `0xDBAe86548451Bb1aDCC8dec3711888C20f70a0d2` |
| rogueBUX | `0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3` | `0x8DbeD9fcF5e0BD80CA512634D9f8a2Fe9605bD3e` |
| flareBUX | `0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8` | `0x7f2b766D73f4A1d5930AFb3C4eB19a1d5c07F426` |
| nftBUX | `0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED` | `0xE9432533e06fa3f61A9d85E31B451B3094702B72` |
| nolchaBUX | `0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642` | `0xB6e8cFFBd667C5139C53E18d48F83891c0beF531` |
| solBUX | `0x92434779E281468611237d18AdE20A4f7F29DB38` | `0x1dd957dD4B8F299a087665A72986Ed50cCE5a489` |
| spaceBUX | `0xAcaCa77FbC674728088f41f6d978F0194cf3d55A` | `0x9409B1A555862c5B399B355744829E5187db9354` |
| tronBUX | `0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665` | `0x95e5364787574021fD9Ea44eEd90b30dF5bB5e78` |
| tranBUX | `0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96` | `0x16E02A25FDfab050Fd3D7E1FB6cB39B61b6CB4A4` |
| blocksterBUX | `0x133Faa922052aE42485609E14A1565551323CdbE` | `0x2dDC1caA8e63B091D353b8E3E7e3Eeb6008DC7Cd` |
