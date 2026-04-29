defmodule BlocksterV2.Migration.HubColorBackfill do
  @moduledoc """
  One-shot backfill: populate `color_primary`/`color_secondary` on production
  hubs that were created without them.

  Production hubs were inserted before `seeds_hubs.exs` was run (or via the
  admin UI without colors set), so most have `nil`/`nil` for the gradient
  fields. The runtime fallback in `BlocksterV2.Blog.HubColor.gradient/1` covers
  any hub by deriving a stable HSL from the slug, but for *known branded* hubs
  (Bitcoin, Ethereum, Solana, etc.) the brand colors live in
  `priv/repo/seeds_hubs.exs`. This module copies those into the DB ONLY for
  hubs where both color fields are currently nil — never overwrites
  admin-curated values.

  ## Usage

  Production:

      flyctl ssh console --app blockster-v2 --machine <id> \\
        -C "/app/bin/blockster_v2 rpc 'BlocksterV2.Migration.HubColorBackfill.run() |> IO.inspect()'"

  Local:

      mix run -e "BlocksterV2.Migration.HubColorBackfill.run() |> IO.inspect()"

  Returns `%{updated: n, skipped_existing: n, not_found_in_db: [tag_names]}`.
  Idempotent — re-running after a successful backfill is a no-op (already set
  → skipped).
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Blog.Hub
  require Logger

  # tag_name → {color_primary, color_secondary}, extracted from
  # priv/repo/seeds_hubs.exs on 2026-04-29. Source of truth for the seed file
  # is itself, but inlining here avoids `Code.eval_file/1` brittleness in a
  # release where priv/repo/*.exs may not load cleanly.
  @brand_colors %{
    "Flare" => {"#E84142", "#C42A2B"},
    "Mythical Games" => {"#8B5CF6", "#7C3AED"},
    "Moca Network" => {"#10B981", "#059669"},
    "0G" => {"#3B82F6", "#2563EB"},
    "Space & Time" => {"#6366F1", "#4F46E5"},
    "Story Protocol" => {"#EC4899", "#DB2777"},
    "BNB Chain" => {"#F3BA2F", "#D4A027"},
    "Bitlayer" => {"#F7931A", "#E67F0A"},
    "BTCC" => {"#1E40AF", "#1E3A8A"},
    "Neo" => {"#58BF00", "#4CAF00"},
    "Optimism" => {"#FF0420", "#E00319"},
    "Etherlink" => {"#3B82F6", "#2563EB"},
    "COTI" => {"#00C9FF", "#00B4E6"},
    "Apex Fusion" => {"#8B5CF6", "#7C3AED"},
    "Open Ledger" => {"#10B981", "#059669"},
    "Trust Wallet" => {"#3375BB", "#2A5F9E"},
    "KuCoin" => {"#24AE8F", "#1F9476"},
    "Bybit" => {"#F7A600", "#DD9500"},
    "Binance" => {"#F3BA2F", "#D4A027"},
    "ExtateX" => {"#6366F1", "#4F46E5"},
    "MoonPay" => {"#7B3FE4", "#5B2FC1"},
    "Myriad" => {"#EC4899", "#DB2777"},
    "Maple" => {"#FF6B6B", "#EE5A52"},
    "ETH Women" => {"#B794F4", "#9F7AEA"},
    "Nolcha" => {"#F59E0B", "#D97706"},
    "TRON" => {"#EB0029", "#C70022"},
    "Crypto.com" => {"#103F68", "#0D3252"},
    "Ethereum" => {"#627EEA", "#454A75"},
    "WalletConnect" => {"#3B99FC", "#2A7BC9"},
    "MetaMask" => {"#F6851B", "#E2761B"},
    "Solana" => {"#00FFA3", "#00DC82"},
    "Avalanche" => {"#E84142", "#C42A2B"},
    "Polygon" => {"#8247E5", "#7130D3"},
    "Arbitrum" => {"#28A0F0", "#1E87D4"},
    "Base" => {"#0052FF", "#0041CC"},
    "Cosmos" => {"#2E3148", "#1C1E2E"},
    "Cardano" => {"#0033AD", "#002A8D"},
    "Polkadot" => {"#E6007A", "#CC006C"},
    "Sui" => {"#6FBCF0", "#5AA5D9"},
    "Aptos" => {"#00D9D5", "#00BFB7"},
    "TON" => {"#0088CC", "#0073AD"},
    "Fantom" => {"#1969FF", "#0F4FCC"},
    "Linea" => {"#121212", "#000000"},
    "zkSync" => {"#8C8DFC", "#7172E3"},
    "Mantle" => {"#000000", "#1A1A1A"},
    "Uniswap" => {"#FF007A", "#E6006C"},
    "Aave" => {"#B6509E", "#9D4386"},
    "Curve" => {"#40B4EA", "#349AC4"},
    "MakerDAO" => {"#1AAB9B", "#148E80"},
    "Lido" => {"#00A3FF", "#008CDB"},
    "Bitcoin" => {"#F7931A", "#E67F0A"},
    "Nansen" => {"#9945FF", "#8534E6"},
    "Messari" => {"#1E1E1E", "#0A0A0A"},
    "Glassnode" => {"#4A90E2", "#3A77C2"},
    "Chainalysis" => {"#0045FF", "#0037CC"},
    "Dune Analytics" => {"#FF6B40", "#E65630"},
    "Santiment" => {"#5275FF", "#3F5FE6"},
    "Token Terminal" => {"#627EEA", "#4F67BA"},
    "IntoTheBlock" => {"#4E54C8", "#3F44A3"},
    "DefiLlama" => {"#2F80ED", "#2569CA"},
    "Plasma" => {"#8B5CF6", "#7C3AED"},
    "Robinhood chain" => {"#00C805", "#00A804"},
    "Tempo" => {"#635BFF", "#4E49E6"},
    "Rogue Trader" => {"#FF4500", "#E63D00"}
  }

  def run do
    summary =
      @brand_colors
      |> Enum.reduce(%{updated: 0, skipped_existing: 0, not_found_in_db: []}, fn
        {tag, {primary, secondary}}, acc ->
          # Match on tag_name OR name, case-insensitive — covers admin-renamed hubs.
          query =
            from h in Hub,
              where: fragment("lower(?) = lower(?)", h.tag_name, ^tag) or fragment("lower(?) = lower(?)", h.name, ^tag),
              limit: 1

          case Repo.one(query) do
            nil ->
              %{acc | not_found_in_db: [tag | acc.not_found_in_db]}

            %Hub{color_primary: nil, color_secondary: nil} = hub ->
              hub
              |> Ecto.Changeset.change(%{color_primary: primary, color_secondary: secondary})
              |> Repo.update!()

              Logger.info("[HubColorBackfill] #{tag}: set #{primary} / #{secondary}")
              %{acc | updated: acc.updated + 1}

            %Hub{} ->
              %{acc | skipped_existing: acc.skipped_existing + 1}
          end
      end)

    Map.update!(summary, :not_found_in_db, &Enum.sort/1)
  end
end
