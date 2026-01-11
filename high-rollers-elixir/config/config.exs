# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# Load .env file FIRST (before any config) so env vars are available
# This runs at compile-time, before dev.exs/test.exs are loaded
if Mix.env() in [:dev, :test] do
  dotenv_path = Path.join([__DIR__, "..", ".env"])

  if File.exists?(dotenv_path) do
    dotenv_path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.each(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          # Handle quoted values with possible inline comments
          clean_value =
            case Regex.run(~r/^\s*"([^"]*)"/, value) do
              [_, quoted_value] -> quoted_value
              nil ->
                case Regex.run(~r/^\s*'([^']*)'/, value) do
                  [_, quoted_value] -> quoted_value
                  nil -> value |> String.split("#", parts: 2) |> List.first() |> String.trim()
                end
            end
          System.put_env(String.trim(key), clean_value)
        _ -> :ok
      end
    end)
  end
end

# General application configuration
import Config

config :high_rollers,
  generators: [timestamp_type: :utc_datetime],

  # Arbitrum NFT contract
  nft_contract_address: "0x7176d2edd83aD037bd94b7eE717bd9F661F560DD",
  arbitrum_rpc_url: "https://snowy-little-cloud.arbitrum-mainnet.quiknode.pro/f4051c078b1e168f278c0780d1d12b817152c84d",

  # Rogue Chain NFTRewarder
  nft_rewarder_address: "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594",
  rogue_rpc_url: "https://rpc.roguechain.io/rpc",

  # Hostess data
  mint_price: "320000000000000000",  # 0.32 ETH in wei
  max_supply: 2700

# Configure the endpoint
config :high_rollers, HighRollersWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HighRollersWeb.ErrorHTML, json: HighRollersWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: HighRollers.PubSub,
  live_view: [signing_salt: "Vaf9Mc9u"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  high_rollers: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  high_rollers: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Hammer rate limiting backend (ETS)
config :hammer,
  backend: {Hammer.Backend.ETS, [
    expiry_ms: 60_000 * 60,       # 1 hour
    cleanup_interval_ms: 60_000 * 10  # 10 minutes
  ]}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
