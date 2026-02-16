import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :blockster_v2, BlocksterV2.Repo,
  username: System.get_env("DATABASE_USER") || System.get_env("USER") || "postgres",
  password: System.get_env("DATABASE_PASSWORD") || "postgres",
  hostname: "localhost",
  database: "blockster_v2_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :blockster_v2, BlocksterV2Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "nVYS3JIDRVfFWg+hhdD6su50pQ1syz/s3UHAOaYb6keDabG6SVvWTTCIMaBwafgv",
  server: false

# In test we don't send emails
config :blockster_v2, BlocksterV2.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable GenServers that could interfere with tests
config :blockster_v2, :start_genservers, false

# Use mock Twilio client in tests
config :blockster_v2, :twilio_client, TwilioClientMock

# Use mock Claude client in tests
config :blockster_v2, :claude_client, BlocksterV2.ContentAutomation.ClaudeClientMock

# Use mock X API client in tests
config :blockster_v2, :x_api_client, BlocksterV2.Social.XApiClientMock
