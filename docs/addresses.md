# Contract & Wallet Addresses

Single source of truth for all on-chain addresses used by Blockster V2.

---

## Wallets

| Wallet | Address | Chain(s) | Purpose |
|--------|---------|----------|---------|
| Deployer (Legacy EVM) | `0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0` | Rogue, Arbitrum | Deploys EVM contracts, initial owner |
| Vault Admin (Legacy EVM) | `0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9` | Rogue, Arbitrum | AirdropVault + AirdropPrizePool owner, depositFor/sendPrize txs |
| Referral Admin (Legacy EVM) | `0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad` | Rogue | Referral system admin |
| Authority / Mint Authority (Solana) | `6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1` | Solana Devnet + Mainnet | Program authority, BUX mint authority, settler keypair, sweep-tx fee payer for shop intents |
| CLI Deploy Wallet (Solana) | `49aNHDAduVnEcEEqCyEXMS1rT62UnW5TajA2fVtNpC1d` | Solana Devnet + Mainnet | Fee payer for program deploys |
| Shop SOL Treasury (Solana) | `B464W5HESYEgDKma9uYUeVWdWM5wpgdVFGQFztkxvTv4` | Solana Mainnet | Receives swept SOL revenue from shop checkout payment intents (`SOL_TREASURY_ADDRESS` on settler). Receive-only — no outbound spends, no funding required. |

### Secrets
| Secret | App | Purpose |
|--------|-----|---------|
| `DEPLOYER_PRIVATE_KEY` | legacy-evm (.env) | EVM contract deploys via Hardhat (legacy) |
| `VAULT_ADMIN_PRIVATE_KEY` | bux-minter (Fly) | AirdropVault deposits + AirdropPrizePool claims (legacy) |
| `API_SECRET` | bux-minter (Fly) | Auth token for Blockster backend → BUX Minter calls (legacy) |
| `SETTLER_API_SECRET` | blockster-settler (Fly) | Auth token for Blockster backend → Settler calls |
| `MINT_AUTHORITY_KEYPAIR` | blockster-settler (Fly) | Solana keypair for BUX minting + settlement + shop intent sweep fee payer |
| `PAYMENT_INTENT_SEED` | blockster-settler (Fly) | 32-byte HKDF master seed for shop checkout ephemeral keypair derivation. Rotating invalidates every unswept intent — only rotate after confirming all are `swept`. |
| `SOL_TREASURY_ADDRESS` | blockster-settler (Fly) | Solana pubkey that receives swept shop revenue (SOL) after buyers fund per-order intents |

---

## Rogue Chain Mainnet (Legacy — EVM) (Chain ID: 560013)

| Contract | Proxy Address | Purpose |
|----------|---------------|---------|
| BUX Token | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` | ERC-20 BUX token |
| BuxBoosterGame | `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` | Coin flip game (UUPS proxy) |
| ROGUEBankroll | `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd` | ROGUE house balance for BuxBooster |
| NFTRewarder | `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594` | NFT time-based rewards (UUPS proxy) |
| NFTRewarder V6 Impl | `0xC2Fb3A92C785aF4DB22D58FD8714C43B3063F3B1` | V6: added getBatchTimeRewardRaw, getBatchNFTOwners |
| AirdropVault (V3) | `0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c` | BUX airdrop vault (UUPS proxy) |
| AirdropVaultV3 Impl | `0x1d540f6bc7d55DCa7F392b9cc7668F2f14d330F9` | V3: simplified draw, server pushes winners |

### Account Abstraction (Legacy — EVM)
| Contract | Address | Purpose |
|----------|---------|---------|
| EntryPoint v0.6.0 | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` | ERC-4337 entry point |
| ManagedAccountFactory | `0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3` | Smart wallet factory |
| Paymaster | `0x804cA06a85083eF01C9aE94bAE771446c25269a6` | Gasless tx sponsor |

---

## Arbitrum One (Legacy — EVM) (Chain ID: 42161)

| Contract | Address | Purpose |
|----------|---------|---------|
| High Rollers NFT | `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD` | NFT collection |
| USDT | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` | Tether USD (6 decimals) |
| AirdropPrizePool | `0x919149CA8DB412541D2d8B3F150fa567fEFB58e1` | USDT prize distribution (UUPS proxy) |

---

## Solana Devnet

### Programs & Token
| Resource | Address / ID | Purpose |
|----------|-------------|---------|
| BUX Mint | `7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX` | BUX SPL token (9 decimals, no freeze authority) |
| Bankroll Program | `49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm` | Dual-vault SOL + BUX, LP tokens, game registry, commit-reveal. **Phase 1 upgrade 2026-04-20** (slot 456930093) — added per-bet `rent_payer: Pubkey` on `BetOrder` (was `_reserved`); `settle_bet` + `reclaim_expired` `close = rent_payer`. **Phase 2 upgrade 2026-04-30** (slot 459216753) — relaxed `rent_payer` constraint on `place_bet_sol/bux` to allow either settler OR player. Wallet Standard users now self-fund bet PDA rent (single-signer tx, no Phantom co-sign warning). Web3Auth path unchanged. See [bankroll_phantom_cosign_fix.md](bankroll_phantom_cosign_fix.md). |
| Airdrop Program | `wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG` | Multi-round airdrop, any SPL/SOL prizes, BUX entries |

### Wallets
| Wallet | Address | Purpose |
|--------|---------|---------|
| Authority / Mint Authority | `6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1` | Program authority, BUX mint authority, settler keypair |
| CLI Deploy Wallet | `49aNHDAduVnEcEEqCyEXMS1rT62UnW5TajA2fVtNpC1d` | Fee payer for program deploys |

### Bankroll PDAs (derived from program `49up2uz...`)
| PDA | Address | Seeds |
|-----|---------|-------|
| GameRegistry | `2hydqJEvNRV1hqMSf5CENZxCbhtQBQ5PVM7PrfmufjFE` | `["game_registry"]` |
| SOL Vault | `HU7LhJzF4NLBpyWCDZoQwZPEizQ4vxCTnZ7TeY8PjRJc` | `["sol_vault"]` |
| SOL Vault State | `4U8SATS95zhFitRWmaBZDwtBaTfeKZ73sEfssXsKis2o` | `["sol_vault_state"]` |
| BUX Vault State | `FNFYBcAXqQGK47dJw7TDwDa5ArD2eMxcoD7NTs6Qg5y` | `["bux_vault_state"]` |
| bSOL LP Mint | `4ppR9BUEKbu5LdtQze8C6ksnKzgeDquucEuQCck38StJ` | `["bsol_mint"]` |
| bBUX LP Mint | `CGNFj29F67BJhFmE3eJ2tCkb8ZwbQQ4Fd1xFynMCDMrX` | `["bbux_mint"]` |
| BUX Vault Token | `5AE7tPRawSSnMscCKkh75DYQWJPZVfkKcdAwbn13drnh` | `["bux_token_account"]` |

### Airdrop PDAs (derived from program `wxiuLBu...`)
| PDA | Address | Seeds |
|-----|---------|-------|
| AirdropState | `8xoz8FsdkBCP4TMguoG5t2zCqEHYYXg38ZLk7iyzaAmj` | `["airdrop"]` |

### Solana Devnet Config
| Property | Value |
|----------|-------|
| Network | Devnet |
| RPC URL | `https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/` |
| Explorer | `https://solscan.io` (append `?cluster=devnet`) |

### Solana Keypair Files (gitignored)
| File | Purpose |
|------|---------|
| `contracts/blockster-settler/keypairs/mint-authority.json` | Authority keypair (`6b4n...`) |
| `contracts/blockster-settler/keypairs/bux-mint.json` | BUX token mint keypair |
| `~/.config/solana/id.json` | CLI deploy wallet (`49aN...`) |

---

## Solana Mainnet

### Programs & Token
| Resource | Address / ID | Purpose |
|----------|-------------|---------|
| BUX Mint | `7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX` | BUX SPL token (same address as devnet — same mint keypair) |
| Bankroll Program | `49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm` | Dual-vault SOL + BUX. Same address as devnet (keypair-derived); independent program account on mainnet. **Phase 2 upgrade 2026-04-30** (slot 416763828) — `rent_payer` dual-mode (player OR settler) to remove Phantom co-sign warning for Wallet Standard users. Web3Auth users still use settler as rent_payer (zero-SOL UX). See [bankroll_phantom_cosign_fix.md](bankroll_phantom_cosign_fix.md). |
| Airdrop Program | `wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG` | Same address as devnet, separate mainnet deployment. |

### Verification (Bankroll Program)
| Field | Value |
|-------|-------|
| Public source | https://github.com/rubyad/blockster-bankroll-program |
| Source commits | `97d9c00` (initial public push), `6467aad` (Cargo.lock pin) |
| Build hash | `fce85f93ac470a3a279dc9da51470cb2ae605b7ea6f04c3c51b871cfcaa9d080` |
| On-chain verification PDA | written via `solana-verify verify-from-repo`, tx `5ezpAYfXNVxj9HxScZFBAKiCLTYMXTZAmkB1kfT5zxtivqQJkRGpzAMmMrDwWzKKdiYuxLN4sYakUSVpkRxv34zw` |
| OtterSec status | https://verify.osec.io/status/49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm — submission attempted, OtterSec backend returned `"Unexpected error while getting Data from DB"` for job `1cd0b2a5-a2f0-4fe2-8c5f-36cdf7f05101`. Retry pending their service recovery. Cryptographic verification is intact via the on-chain PDA above. |

### Solana Mainnet Config
| Property | Value |
|----------|-------|
| Network | Mainnet-beta |
| RPC URL | `https://radial-fittest-sanctuary.solana-mainnet.quiknode.pro/bba3cfea34edbf35708389240474cf5cd966c86b/` (set as `SOLANA_RPC_URL` Fly secret on `blockster-settler` + `blockster-v2`) |
| Explorer | `https://solscan.io` |

---

## Services

| Service | URL | Purpose |
|---------|-----|---------|
| Blockster App | `https://blockster.com` | Main web app |
| BUX Minter | `https://bux-minter.fly.dev` | DEPRECATED -- replaced by Blockster Settler |
| Bundler | `https://rogue-bundler-mainnet.fly.dev` | DEPRECATED -- EVM only, not needed on Solana |
| Blockster Settler | `https://blockster-settler.fly.dev` | Solana settler service (BUX minting, bet settlement, bankroll, airdrop) |

---

## Network Config

| Property | Rogue Chain (Legacy) | Arbitrum One (Legacy) | Solana Devnet |
|----------|----------------------|-----------------------|---------------|
| Chain ID | `560013` | `42161` | N/A |
| RPC URL | `https://rpc.roguechain.io/rpc` | `https://arb1.arbitrum.io/rpc` | QuickNode (see above) |
| Explorer | `https://roguescan.io` | `https://arbiscan.io` | `https://explorer.solana.com/?cluster=devnet` |
| Native Token | ROGUE | ETH | SOL |
