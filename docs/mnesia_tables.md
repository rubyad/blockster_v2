# Mnesia Tables

**Directories**: Production `/data/mnesia/blockster`, Dev `priv/mnesia/{node_name}`.

## Active Tables

| Table | Purpose | Key |
|-------|---------|-----|
| `user_solana_balances` | SOL + BUX balances (source of truth for display) | `user_id` |
| `user_post_engagement` | Reading metrics | `{user_id, post_id}` |
| `user_post_rewards` | BUX rewards earned | `{user_id, post_id}` |
| `unified_multipliers_v2` | Reward multipliers (SOL + email) | `user_id` |
| `coin_flip_games` | Solana coin flip game sessions | `game_id` |
| `user_lp_balances` | LP token balances (bSOL + bBUX) | `user_id` |
| `x_connections` | X OAuth tokens | `user_id` |
| `share_campaigns` | Retweet campaigns | `post_id` |
| `share_rewards` | Share participation | `{user_id, campaign_id}` |
| `token_prices` | CoinGecko price cache | `token_id` |
| `widget_fs_feed_cache` | FateSwap live-trade snapshot (WIDGETS_ENABLED) | `:singleton` |
| `widget_rt_bots_cache` | RogueTrader bot snapshot (WIDGETS_ENABLED) | `:singleton` |
| `widget_rt_chart_cache` | RogueTrader per-series chart points (WIDGETS_ENABLED) | `{bot_id, tf}` |
| `widget_selections` | Self-selected subject per widget banner | `banner_id` |
| `hr_solana_wallets` | FateSwap revenue share registration (NFT holders) | EVM wallet address |
| `lp_price_history` | LP price snapshots for pool chart | `{vault_type, timestamp}` |

## Legacy Tables (not read, kept for schema compat)

| Table | Replaced By |
|-------|-------------|
| `user_bux_balances` | `user_solana_balances` |
| `user_rogue_balances` | N/A (ROGUE removed) |
| `bux_booster_onchain_games` | `coin_flip_games` |
| `unified_multipliers` | `unified_multipliers_v2` |

## Rules

- **Always use dirty operations** (`dirty_read`, `dirty_write`, `dirty_delete`, `dirty_index_read`).
- **For concurrent updates**: Route writes through a dedicated GenServer to serialize.
- **Modifying table schemas**: Add new fields to END only, create a migration function, scale to 1 server before deploying.
- **NEVER delete `priv/mnesia/*` directories** — contains unrecoverable user data.
- When new Mnesia tables are added, restart both nodes to create them.
