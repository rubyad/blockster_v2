defmodule BlocksterV2.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Add libcluster only in dev mode (production uses DNSCluster)
    # Use compile-time check since Mix is not available in production releases
    libcluster_child =
      if Application.get_env(:blockster_v2, :env) == :dev do
        [{Cluster.Supervisor, [Application.get_env(:libcluster, :topologies, []), [name: BlocksterV2.ClusterSupervisor]]}]
      else
        []
      end

    # Initialize BuxMinter sync deduplication ETS table early
    BlocksterV2.BuxMinter.init_dedup_table()

    # Base children that always start
    base_children = [
      BlocksterV2Web.Telemetry,
      BlocksterV2.Repo,
      {DNSCluster, query: Application.get_env(:blockster_v2, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BlocksterV2.PubSub}
    ] ++ libcluster_child

    # GenServers that should not start in test mode
    genserver_children = if Application.get_env(:blockster_v2, :start_genservers, true) do
      [
        # Mnesia initialization (after cluster discovery so nodes are connected)
        {BlocksterV2.MnesiaInitializer, []},
        # Sorted posts cache (must be after Mnesia initialization)
        {BlocksterV2.SortedPostsCache, []},
        # Serialized pool writer for race-condition-free pool operations
        {BlocksterV2.PostBuxPoolWriter, []},
        # Time tracking GenServer
        {BlocksterV2.TimeTracker, %{}},
        # Hub logo cache (ETS-based, for header dropdown)
        {BlocksterV2.HubLogoCache, []},
        # BuxBooster bet settlement checker (runs every minute to settle stuck bets)
        {BlocksterV2.BuxBoosterBetSettler, []},
        # Plinko bet settlement checker (runs every minute to settle stuck Plinko bets)
        {BlocksterV2.PlinkoSettler, []},
        # Token price tracker (polls CoinGecko every 10 minutes)
        {BlocksterV2.PriceTracker, []},
        # LP-BUX price tracker (polls BUXBankroll every 60s, stores OHLC candles)
        {BlocksterV2.LPBuxPriceTracker, []},
        # Wallet multiplier refresher (daily at 3 AM UTC)
        {BlocksterV2.WalletMultiplierRefresher, []},
        # Referral reward poller (polls Rogue Chain for ReferralRewardPaid events)
        {BlocksterV2.ReferralRewardPoller, []}
      ]
    else
      []
    end

    # Content automation pipeline (behind feature flag)
    content_automation_children =
      if Application.get_env(:blockster_v2, :content_automation, [])[:enabled] do
        [
          {BlocksterV2.ContentAutomation.FeedPoller, []},
          {BlocksterV2.ContentAutomation.TopicEngine, []},
          {BlocksterV2.ContentAutomation.ContentQueue, []}
        ]
      else
        []
      end

    # Endpoint always starts last
    children = base_children ++ genserver_children ++ content_automation_children ++ [BlocksterV2Web.Endpoint]

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
