defmodule BlocksterV2.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BlocksterV2Web.Telemetry,
      BlocksterV2.Repo,
      {DNSCluster, query: Application.get_env(:blockster_v2, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BlocksterV2.PubSub},
      # Mnesia initialization (after DNSCluster so nodes are connected)
      {BlocksterV2.MnesiaInitializer, []},
      # Time tracking GenServer
      {BlocksterV2.TimeTracker, %{}},
      # Hub logo cache (ETS-based, for header dropdown)
      {BlocksterV2.HubLogoCache, []},
      # Start to serve requests, typically the last entry
      BlocksterV2Web.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BlocksterV2.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BlocksterV2Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
