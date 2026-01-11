defmodule HighRollers.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # 1. Telemetry first
      HighRollersWeb.Telemetry,

      # 2. HTTP client pool (before anything that makes HTTP calls)
      {Finch, name: HighRollers.Finch},

      # 3. PubSub for real-time updates (before anything that broadcasts)
      {Phoenix.PubSub, name: HighRollers.PubSub},

      # 4. Mnesia initialization
      {HighRollers.MnesiaInitializer, []},

      # 5. Price cache (polls BlocksterV2 API every minute)
      {HighRollers.PriceCache, []},

      # 6. NFTStore (write serializer for hr_nfts)
      {HighRollers.NFTStore, []},

      # 6. AdminTxQueue (must start before pollers that enqueue ops)
      {HighRollers.AdminTxQueue, []},

      # 7. Blockchain pollers
      {HighRollers.ArbitrumEventPoller, []},
      {HighRollers.RogueRewardPoller, []},

      # 8. Background sync services
      {HighRollers.EarningsSyncer, []},
      {HighRollers.OwnershipReconciler, []},
      {HighRollers.AffiliateLinkRetrier, []},

      # Phoenix endpoint last
      HighRollersWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HighRollers.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HighRollersWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
