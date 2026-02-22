import Config

# Load .env file in development and test environments
if config_env() in [:dev, :test] do
  dotenv_path = Path.join([__DIR__, "..", ".env"])

  if File.exists?(dotenv_path) do
    # Read and parse the .env file
    dotenv_path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.each(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          # Remove quotes if present
          clean_value = String.trim(value, "\"")
          System.put_env(key, clean_value)

        _ ->
          :ok
      end
    end)
  end
end

# S3 Configuration for image uploads
# The S3 bucket and region can be configured via environment variables
config :blockster_v2,
  s3_bucket: System.get_env("AWS_S3_BUCKET") || System.get_env("S3_BUCKET") || "your-bucket-name",
  s3_region: System.get_env("AWS_REGION") || "us-east-1",
  thirdweb_client_id: System.get_env("THIRDWEB_CLIENT_ID"),
  aws_access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  google_maps_api_key: System.get_env("GOOGLE_MAPS_API_KEY"),
  bux_minter_url: System.get_env("BUX_MINTER_URL"),
  bux_minter_secret: System.get_env("BUX_MINTER_SECRET"),
  # Skip fingerprint check - defaults to true in dev, false in prod (set SKIP_FINGERPRINT_CHECK=true to enable)
  skip_fingerprint_check: System.get_env("SKIP_FINGERPRINT_CHECK") == "true" || config_env() == :dev,
  # FingerprintJS Server API key for server-side event verification
  fingerprintjs_server_api_key: System.get_env("FINGERPRINTJS_SERVER_API_KEY"),
  env: config_env(),
  x_api: [
    client_id: System.get_env("X_CLIENT_ID"),
    client_secret: System.get_env("X_CLIENT_SECRET"),
    callback_url: System.get_env("X_CALLBACK_URL")
  ],
  app_url:
    System.get_env("APP_URL") ||
      if(config_env() == :prod,
        do: "https://blockster.com",
        else: "http://localhost:4000"
      ),
  twilio_account_sid: System.get_env("TWILIO_ACCOUNT_SID"),
  twilio_auth_token: System.get_env("TWILIO_AUTH_TOKEN"),
  twilio_verify_service_sid: System.get_env("TWILIO_VERIFY_SERVICE_SID"),
  # Helio payments (card/crypto checkout)
  helio_api_key: System.get_env("HELIO_API_KEY"),
  helio_secret_key: System.get_env("HELIO_SECRET_KEY"),
  helio_paylink_id: System.get_env("HELIO_PAYLINK_ID"),
  helio_webhook_secret: System.get_env("HELIO_WEBHOOK_SECRET"),
  # Telegram fulfillment notifications
  telegram_bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
  telegram_fulfillment_channel_id: System.get_env("TELEGRAM_FULFILLMENT_CHANNEL_ID"),
  # Email fulfillment notifications
  fulfillment_email: System.get_env("FULFILLMENT_EMAIL") || "fulfillment@blockster.com",
  # Shop treasury wallet (receives ROGUE payments)
  shop_treasury_address: System.get_env("SHOP_TREASURY_ADDRESS"),
  ai_ads_manager: [
    enabled: System.get_env("AI_ADS_MANAGER_ENABLED", "false") == "true",
    ads_service_url: System.get_env("ADS_SERVICE_URL", "https://ads-manager.fly.dev"),
    ads_service_secret: System.get_env("ADS_SERVICE_SECRET"),
    anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")
  ],
  content_automation: [
    enabled: System.get_env("CONTENT_AUTOMATION_ENABLED", "false") == "true",
    anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
    x_bearer_token: System.get_env("X_BEARER_TOKEN"),
    unsplash_access_key: System.get_env("UNSPLASH_ACCESS_KEY"),
    google_cse_api_key: System.get_env("GOOGLE_CSE_API_KEY"),
    google_cse_cx: System.get_env("GOOGLE_CSE_CX"),
    bing_image_api_key: System.get_env("BING_IMAGE_API_KEY"),
    posts_per_day: String.to_integer(System.get_env("CONTENT_POSTS_PER_DAY", "10")),
    content_model: System.get_env("CONTENT_CLAUDE_MODEL", "claude-opus-4-6"),
    topic_model: System.get_env("TOPIC_CLAUDE_MODEL", "claude-haiku-4-5-20251001"),
    brand_x_user_id: (case System.get_env("BRAND_X_USER_ID") do
      nil -> nil
      "" -> nil
      val -> String.to_integer(val)
    end),
    feed_poll_interval: :timer.minutes(5),
    topic_analysis_interval: :timer.minutes(15)
  ]

# Mnesia configuration
# In production, Mnesia data is stored in /data/mnesia/blockster (Fly.io persistent volume)
# IMPORTANT: Use static path "blockster" (not node name) so data persists across deployments
# Each Fly.io machine has its own volume, so each gets its own copy of the Mnesia data
# In development, it's stored in priv/mnesia/{node_name} for each node
mnesia_dir =
  if config_env() == :prod do
    "/data/mnesia/blockster"
  else
    # For dev, use separate directory per node to allow multi-node testing
    node_name = node() |> Atom.to_string() |> String.split("@") |> List.first()
    Path.join(["priv", "mnesia", node_name])
  end

config :mnesia, dir: String.to_charlist(mnesia_dir)

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/blockster_v2 start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :blockster_v2, BlocksterV2Web.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :blockster_v2, BlocksterV2.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # Required for PGBouncer transaction mode (MPG uses PGBouncer)
    prepare: :unnamed,
    # Keep idle connections alive - prevents PGBouncer from killing them
    idle_interval: 15_000,
    # Connection pool health settings - help detect and recover from connection issues
    queue_target: 50,
    queue_interval: 1000,
    # Timeout settings to detect dead connections faster
    timeout: 15000,
    connect_timeout: 15000,
    handshake_timeout: 15000,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :blockster_v2, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :blockster_v2, BlocksterV2Web.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    check_origin: [
      "https://blockster.com",
      "https://www.blockster.com",
      "https://blockster-v2.fly.dev",
      "https://v2.blockster.com",
      "http://blockster.com",
      "http://www.blockster.com"
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :blockster_v2, BlocksterV2Web.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :blockster_v2, BlocksterV2Web.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production, configure the mailer to use SendGrid
  config :blockster_v2, BlocksterV2.Mailer,
    adapter: Swoosh.Adapters.Sendgrid,
    api_key: System.get_env("SENDGRID_API_KEY")

  # Override app_url with PHX_HOST if set
  app_host = System.get_env("PHX_HOST") || "blockster.com"
  config :blockster_v2, app_url: "https://#{app_host}"
end
