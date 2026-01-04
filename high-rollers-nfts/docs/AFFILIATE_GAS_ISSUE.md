# Affiliate Array Gas Issue

## Summary

The High Rollers NFT contract has an unbounded array growth issue in the Affiliate struct that can cause VRF callback failures when arrays become too large. This document explains the issue and lists problematic affiliate addresses.

## Root Cause

The contract's `fulfillRandomWords` function (VRF callback) updates affiliate arrays during minting:
- `buyers[]` - addresses of direct buyers
- `referrees[]` - addresses referred by this affiliate
- `referredAffiliates[]` - other affiliates referred
- `tokenIds[]` - token IDs minted through this affiliate

When these arrays grow large (500+ elements combined), the gas required to iterate/update them can exceed the VRF callback gas limit of **2,500,000 gas**, causing the mint to fail.

## Failure Mode

1. User calls `requestNFT()` and pays 0.32 ETH
2. Contract requests random number from Chainlink VRF
3. VRF callback (`fulfillRandomWords`) tries to mint NFT
4. During minting, affiliate arrays are updated
5. **If affiliate arrays are too large, gas exceeds 2.5M limit**
6. VRF callback fails with "out of gas: not enough gas for reentrancy sentry"
7. User loses 0.32 ETH but receives no NFT

## Failed Transaction Example

- **User**: `0x3095658F5b3380d42A12Cc184aAA835F86523A87`
- **Request TX**: [0x8e563c3471ddf4418b30e9eb0bb38fc2cf689f71517c7ba931777eba5086ef2b](https://arbiscan.io/tx/0x8e563c3471ddf4418b30e9eb0bb38fc2cf689f71517c7ba931777eba5086ef2b)
- **VRF Callback TX**: [0x48aabe55065295e9137580e7ae5c355ec8010abe7cae3a3d1a36e24e7fea9676](https://arbiscan.io/tx/0x48aabe55065295e9137580e7ae5c355ec8010abe7cae3a3d1a36e24e7fea9676)
- **Cause**: Default affiliate had 1,337 array elements

## Problematic Affiliates

The following affiliates have array sizes that could cause gas failures:

| Address | Buyers | Referrees | Ref Affiliates | TokenIds | Total | Risk |
|---------|--------|-----------|----------------|----------|-------|------|
| `0x315443bf8fba3d9a38b11300e921a97b991d8c24` | 44 | 199 | 1,050 | 44 | **1,337** | CRITICAL |
| `0xc2a8120fbc7d1506a30eaedd67aeae754c4beea9` | 0 | 112 | 780 | 0 | **892** | HIGH |
| `0x884934c68b4a2cffe293a96579b497aaccca461a` | 3 | 798 | 38 | 3 | **842** | HIGH |
| `0x90dd6aa425215712c754494aec02a8b81e9fa758` | 0 | 50 | 588 | 0 | **638** | HIGH |

### Near Threshold (Monitor)

| Address | Total Elements |
|---------|----------------|
| `0x22954874e57778a5e65d19b87560fdb65522351b` | 428 |
| `0xc96c62e560fe3f0f84591c2fb1f3b7b3d78392c1` | 375 |
| `0x644617467a67e4b9534e0e37b75cb914ac8a778c` | 298 |
| `0x2658911a7d9bcc4437cff7290f3ee629e0eac41b` | 295 |
| `0x6ad1ea38156b0204d312d69da25aa9b212e4a8e4` | 289 |
| `0x6023135c79bd1b9b296de6e3f3b0ad8349fb2818` | 274 |

## Mitigation Actions Taken

### 1. Changed Default Affiliate (Jan 4, 2025)

The default affiliate was changed from the problematic address to a fresh one:

- **Old default**: `0x315443bf8fba3d9a38b11300e921a97b991d8c24` (1,337 elements)
- **New default**: `0xb91b270212F0F7504ECBa6Ff1d9c1f58DfcEEa14` (0 elements)

This was done by calling `setAddress(1, newAddress)` on the contract.

### 2. Monitoring

Affiliates approaching 500 elements should be monitored. If any reach dangerous levels, users linked to them should be warned.

## How to Check Affiliate Array Size

Use the contract's `getAffiliateInfo(address)` function:

```javascript
const info = await contract.getAffiliateInfo(affiliateAddress);
const total = info.buyers.length + info.referrees.length +
              info.referredAffiliates.length + info.tokenIds.length;
console.log(`Total elements: ${total}`);
```

## Prevention (Future Contracts)

For future contracts, consider:

1. **Bounded arrays**: Limit array sizes or use mappings instead
2. **Separate storage**: Store affiliate data in a separate contract
3. **Lazy evaluation**: Don't iterate arrays in VRF callback
4. **Higher gas limits**: Request higher callback gas (if supported)

## Refund Required

User `0x3095658F5b3380d42A12Cc184aAA835F86523A87` paid 0.32 ETH but received no NFT due to this issue. They should be refunded.

---

*Last updated: January 4, 2025*
