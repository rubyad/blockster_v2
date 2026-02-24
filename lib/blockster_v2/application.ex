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
        # Serialized pool writer for race-condition-free pool operations
        {BlocksterV2.PostBuxPoolWriter, []},
        # Time tracking GenServer
        {BlocksterV2.TimeTracker, %{}},
        # Hub logo cache (ETS-based, for header dropdown)
        {BlocksterV2.HubLogoCache, []},
        # BuxBooster bet settlement checker (runs every minute to settle stuck bets)
        {BlocksterV2.BuxBoosterBetSettler, []},
        # Token price tracker (polls CoinGecko every 10 minutes)
        {BlocksterV2.PriceTracker, []},
        # Wallet multiplier refresher (daily at 3 AM UTC)
        {BlocksterV2.WalletMultiplierRefresher, []},
        # Referral reward poller (polls Rogue Chain for ReferralRewardPaid events)
        {BlocksterV2.ReferralRewardPoller, []},
        # Shop checkout: serialized BUX balance deductions
        {BlocksterV2.Shop.BalanceManager, []},
        # Shop checkout: process held affiliate payouts (hourly)
        {BlocksterV2.Orders.AffiliatePayoutWorker, []},
        # Shop checkout: expire stale unpaid orders (every 5 min)
        {BlocksterV2.Orders.OrderExpiryWorker, []}
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

    # Oban job processing
    oban_children = [{Oban, Application.fetch_env!(:blockster_v2, Oban)}]

    # Seed SystemConfig defaults (idempotent — only writes if table is empty)
    if Application.get_env(:blockster_v2, :start_genservers, true) do
      Task.start(fn ->
        # Small delay to ensure Repo is ready
        Process.sleep(1_000)
        BlocksterV2.Notifications.SystemConfig.seed_defaults()
      end)
    end

    # Notification EventProcessor (after Oban, uses GlobalSingleton)
    notification_children = if Application.get_env(:blockster_v2, :start_genservers, true) do
      [{BlocksterV2.Notifications.EventProcessor, []}]
    else
      []
    end

    # AI Ads Manager (behind feature flag)
    ads_manager_children =
      if Application.get_env(:blockster_v2, :ai_ads_manager, [])[:enabled] do
        [{BlocksterV2.AdsManager, []}]
      else
        []
      end

    # Bot reader system (behind feature flag)
    bot_system_children =
      if Application.get_env(:blockster_v2, :bot_system, [])[:enabled] do
        [{BlocksterV2.BotSystem.BotCoordinator, []}]
      else
        []
      end

    # Endpoint always starts last
    children = base_children ++ genserver_children ++ content_automation_children ++ oban_children ++ notification_children ++ ads_manager_children ++ bot_system_children ++ [BlocksterV2Web.Endpoint]

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
