import Config

# Load .env file in development and test environments
if config_env() in [:dev, :test] do
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
          # e.g., ADMIN_PRIVATE_KEY="0x..." # comment
          clean_value =
            case Regex.run(~r/^\s*"([^"]*)"/, value) do
              [_, quoted_value] ->
                # Value was in double quotes, extract just the quoted content
                quoted_value

              nil ->
                case Regex.run(~r/^\s*'([^']*)'/, value) do
                  [_, quoted_value] ->
                    # Value was in single quotes
                    quoted_value

                  nil ->
                    # No quotes - take everything before # (inline comment)
                    value
                    |> String.split("#", parts: 2)
                    |> List.first()
                    |> String.trim()
                end
            end

          System.put_env(String.trim(key), clean_value)

        _ ->
          :ok
      end
    end)
  end
end

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
#     PHX_SERVER=true bin/high_rollers start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :high_rollers, HighRollersWeb.Endpoint, server: true
end

config :high_rollers, HighRollersWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
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

  host = System.get_env("PHX_HOST") || "high-rollers.fly.dev"

  config :high_rollers, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :high_rollers, HighRollersWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Production secrets from environment variables (set via Fly.io secrets)
  # flyctl secrets set ADMIN_PRIVATE_KEY=0x...
  # flyctl secrets set AFFILIATE_LINKER_PRIVATE_KEY=0x...
  config :high_rollers,
    admin_private_key: System.get_env("ADMIN_PRIVATE_KEY"),
    affiliate_linker_private_key: System.get_env("AFFILIATE_LINKER_PRIVATE_KEY"),
    default_affiliate: System.get_env("DEFAULT_AFFILIATE") || "0x0000000000000000000000000000000000000000"

  # Mnesia directory on Fly.io volume
  config :mnesia, dir: String.to_charlist("/data/mnesia/high_rollers")
else
  # Development: use project-local Mnesia
  node_name = node() |> Atom.to_string() |> String.split("@") |> List.first()
  config :mnesia, dir: String.to_charlist("priv/mnesia/#{node_name}")
end
