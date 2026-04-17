# Admin Operations

Quick-reference snippets for running admin tasks against production via `flyctl ssh console`.

## Query User by Wallet

```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'alias BlocksterV2.{Repo, Accounts.User}; import Ecto.Query; Repo.all(from u in User, where: ilike(u.wallet_address, \"%PARTIAL%\") or ilike(u.smart_wallet_address, \"%PARTIAL%\"), select: {u.id, u.wallet_address, u.smart_wallet_address}) |> IO.inspect()'"
```

## Mint BUX

Use `wallet_address` (Solana) — `smart_wallet_address` is legacy EVM and is `nil` for Solana users.

Reward types: `:read`, `:x_share`, `:video_watch`, `:signup`, `:phone_verified`, `:legacy_migration`.

```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'BlocksterV2.BuxMinter.mint_bux(\"WALLET_ADDRESS\", 1000, USER_ID, nil, :signup) |> IO.inspect()'"
```

## Clear Phone Verification

```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
alias BlocksterV2.{Repo, Accounts.User, Accounts.PhoneVerification}; import Ecto.Query; user_id = 89
Repo.delete_all(from p in PhoneVerification, where: p.user_id == ^user_id)
Repo.update_all(from(u in User, where: u.id == ^user_id), set: [phone_verified: false, geo_multiplier: Decimal.new(\"0.5\"), geo_tier: \"unverified\"])
'"
```
