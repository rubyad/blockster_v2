# Solana Program Deploy Runbook

Deploy + upgrade procedure for the Bankroll and Airdrop Anchor programs.

## Authorities

- **Upgrade authority** (both programs): settler keypair `6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1` — NOT the CLI wallet.
- **Fee payer**: CLI wallet `49aNHDAduVnEcEEqCyEXMS1rT62UnW5TajA2fVtNpC1d` — needs ~5 SOL for a full program deploy.
- Keypair path: `contracts/blockster-settler/keypairs/mint-authority.json`.

## RPC

ALWAYS use the project QuickNode RPC. NEVER use public endpoints (`api.devnet.solana.com`, `api.mainnet-beta.solana.com`) — they are rate-limited and unreliable. Source of truth: `contracts/blockster-settler/src/config.ts`.

NEVER use `solana airdrop` or any devnet faucet — they do not work. Ask the user to fund the wallet manually.

## Deploy Command

```bash
solana program deploy target/deploy/blockster_bankroll.so \
  --program-id 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm \
  --upgrade-authority contracts/blockster-settler/keypairs/mint-authority.json \
  --url https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/
```

## Deploy Failure → Buffer Recovery (MANDATORY)

If the deploy fails (insufficient funds, network error), Solana creates a **buffer account** with an ephemeral keypair. The output prints a 12-word seed phrase. **You MUST recover and close this buffer** or the deploy SOL is permanently lost.

1. Save the seed phrase from the error output.
2. Recover the keypair via `expect` (solana-keygen needs a TTY):

   ```bash
   expect -c '
   spawn solana-keygen recover --outfile /tmp/buffer-keypair.json --force --skip-seed-phrase-validation
   expect "seed phrase:"
   send "PASTE_SEED_PHRASE_HERE\r"
   expect "passphrase"
   send "\r"
   expect "Continue"
   send "y\r"
   expect eof
   '
   ```

3. Close the buffer to recover the SOL:

   ```bash
   solana program close /tmp/buffer-keypair.json \
     --url https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/
   ```

4. Retry the deploy after funding the wallet.

**NEVER ignore a failed deploy.** Always recover the buffer first.

## Transaction Confirmation Rules

All Solana transactions (settler, client-side JS, scripts) MUST follow these rules:

- **NEVER use `confirmTransaction`** (websocket subscriptions) — unreliable, creates RPC contention, causes slow/stuck confirmations.
- **NEVER use manual rebroadcast loops** (`setInterval` + `sendRawTransaction`) — `maxRetries` on `sendRawTransaction` handles delivery retries at the RPC level.
- **ALWAYS use `getSignatureStatuses` polling** (like ethers `tx.wait()`): send once with `maxRetries:5`, poll every 2s until "confirmed". See `rpc-client.ts:waitForConfirmation` and `coin_flip_solana.js:pollForConfirmation`.
- All txs should include priority fees (`computeBudgetIxs`).

## State Propagation Rules

- **NEVER chain dependent Solana transactions back-to-back** — even the SAME RPC endpoint can return stale state in `simulateTransaction` immediately after confirming the prior tx via `getSignatureStatuses`.
- **NEVER pre-submit the next game's `submit_commitment` immediately after `settle_bet`** — the following `place_bet` will fail with `NonceMismatch`. Sleeps and retries are insufficient.
- **The fix**: trigger dependent transactions from USER ACTIONS (button clicks, page loads), not programmatically back-to-back. The natural delay gives RPCs time to sync. Full narrative in `docs/session_learnings.md`.
