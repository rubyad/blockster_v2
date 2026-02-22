# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :blockster_v2,
  ecto_repos: [BlocksterV2.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :blockster_v2, BlocksterV2Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BlocksterV2Web.ErrorHTML, json: BlocksterV2Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: BlocksterV2.PubSub,
  live_view: [signing_salt: "d8uF2ylg"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :blockster_v2, BlocksterV2.Mailer, adapter: Swoosh.Adapters.Local

# Oban job processing
config :blockster_v2, Oban,
  repo: BlocksterV2.Repo,
  queues: [
    default: 10,
    email_transactional: 5,
    email_marketing: 3,
    email_digest: 2,
    sms: 1,
    ads_management: 3,
    ads_creative: 2,
    ads_analytics: 2
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 6 * * *", BlocksterV2.Workers.AIManagerReviewWorker, args: %{"type" => "daily"}, queue: :default},
       {"0 7 * * 1", BlocksterV2.Workers.AIManagerReviewWorker, args: %{"type" => "weekly"}, queue: :default},
       # Cleanup
       {"0 3 * * *", BlocksterV2.Workers.EventCleanupWorker, queue: :default},
       # AI Ads Manager workers
       {"0 * * * *", BlocksterV2.AdsManager.Workers.PerformanceCheckWorker, queue: :ads_analytics},
       {"0 0 * * *", BlocksterV2.AdsManager.Workers.DailyBudgetResetWorker, queue: :ads_management},
       # Daily digest at 9am UTC
       {"0 9 * * *", BlocksterV2.Workers.DailyDigestWorker, queue: :email_digest}
     ]}
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  blockster_v2: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.join([Path.expand("../assets/node_modules", __DIR__), Path.expand("../deps", __DIR__)], ":")}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  blockster_v2: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
