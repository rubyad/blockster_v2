# Contract & Wallet Addresses

Single source of truth for all on-chain addresses used by Blockster V2.

---

## Wallets

| Wallet | Address | Chain(s) | Purpose |
|--------|---------|----------|---------|
| Deployer | `0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0` | Rogue, Arbitrum | Deploys contracts, initial owner |
| Vault Admin | `0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9` | Rogue, Arbitrum | AirdropVault + AirdropPrizePool owner, depositFor/sendPrize txs |
| Referral Admin | `0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad` | Rogue | Referral system admin |

### Secrets
| Secret | App | Purpose |
|--------|-----|---------|
| `DEPLOYER_PRIVATE_KEY` | bux-booster-game (.env) | Contract deploys via Hardhat |
| `VAULT_ADMIN_PRIVATE_KEY` | bux-minter (Fly) | AirdropVault deposits + AirdropPrizePool claims |
| `API_SECRET` | bux-minter (Fly) | Auth token for Blockster backend → BUX Minter calls |

---

## Rogue Chain Mainnet (Chain ID: 560013)

| Contract | Proxy Address | Purpose |
|----------|---------------|---------|
| BUX Token | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` | ERC-20 BUX token |
| BuxBoosterGame | `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` | Coin flip game (UUPS proxy) |
| ROGUEBankroll | `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd` | ROGUE house balance for BuxBooster |
| NFTRewarder | `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594` | NFT time-based rewards |
| AirdropVault | _TBD — deploy in Phase 3_ | BUX airdrop vault (UUPS proxy) |

### Account Abstraction (Rogue Chain)
| Contract | Address | Purpose |
|----------|---------|---------|
| EntryPoint v0.6.0 | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` | ERC-4337 entry point |
| ManagedAccountFactory | `0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3` | Smart wallet factory |
| Paymaster | `0x804cA06a85083eF01C9aE94bAE771446c25269a6` | Gasless tx sponsor |

---

## Arbitrum One (Chain ID: 42161)

| Contract | Address | Purpose |
|----------|---------|---------|
| High Rollers NFT | `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD` | NFT collection |
| USDT | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` | Tether USD (6 decimals) |
| AirdropPrizePool | _TBD — deploy in Phase 3_ | USDT prize distribution (UUPS proxy) |

---

## Services

| Service | URL | Purpose |
|---------|-----|---------|
| Blockster App | `https://blockster.com` | Main web app |
| BUX Minter | `https://bux-minter.fly.dev` | Token minting, game settlement, airdrop deposits/claims |
| Bundler | `https://rogue-bundler-mainnet.fly.dev` | ERC-4337 bundler for smart wallets |

---

## Network Config

| Property | Rogue Chain | Arbitrum One |
|----------|-------------|--------------|
| Chain ID | `560013` | `42161` |
| RPC URL | `https://rpc.roguechain.io/rpc` | `https://arb1.arbitrum.io/rpc` |
| Explorer | `https://roguescan.io` | `https://arbiscan.io` |
| Native Token | ROGUE | ETH |
