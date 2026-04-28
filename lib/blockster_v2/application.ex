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

    # Ignore SIGUSR1 — Fly.io's init sends this signal to child processes
    # during deployment, which by default causes the BEAM to write a crash dump and exit
    :os.set_signal(:sigusr1, :ignore)

    # Initialize BuxMinter sync deduplication ETS table early
    BlocksterV2.BuxMinter.init_dedup_table()

    # Base children that always start
    base_children = [
      BlocksterV2Web.Telemetry,
      BlocksterV2.Repo,
      {DNSCluster, query: Application.get_env(:blockster_v2, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BlocksterV2.PubSub},
      BlocksterV2.Auth.NonceStore,
      BlocksterV2.Auth.Web3AuthSigning,
      BlocksterV2.Auth.EmailOtpStore
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
        # Coin Flip bet settlement checker (Solana, runs every minute)
        {BlocksterV2.CoinFlipBetSettler, []},
        # Token price tracker (polls CoinGecko every 10 minutes)
        {BlocksterV2.PriceTracker, []},
        # LP price snapshot recorder (every 10s for pool charts)
        {BlocksterV2.LpPriceTracker, []},
        # WalletMultiplierRefresher removed in Solana migration (Phase 5)
        # SOL multiplier refresh happens on profile visit + periodic sync
        # Referral reward poller (polls Rogue Chain for ReferralRewardPaid events)
        {BlocksterV2.ReferralRewardPoller, []},
        # Shop checkout: serialized BUX balance deductions
        {BlocksterV2.Shop.BalanceManager, []},
        # Shop checkout: process held affiliate payouts (hourly)
        {BlocksterV2.Orders.AffiliatePayoutWorker, []},
        # Shop checkout: expire stale unpaid orders (every 5 min)
        {BlocksterV2.Orders.OrderExpiryWorker, []},
        # Shop checkout: surface orders stuck in :bux_pending past 15-min
        # intent window (SHOP-14) — logs + PubSub broadcast, no state mutation
        {BlocksterV2.Orders.BuxBurnWatcher, []},
        # Shop checkout: poll settler for SOL payment intent funding (every 10s)
        {BlocksterV2.PaymentIntentWatcher, []},
        # Airdrop: auto-settle rounds when countdown expires
        {BlocksterV2.Airdrop.Settler, []}
      ]
    else
      []
    end

    # Content automation pipeline (behind feature flag).
    # Also gated on :start_genservers — test env never starts these.
    content_automation_children =
      if Application.get_env(:blockster_v2, :content_automation, [])[:enabled] and
           Application.get_env(:blockster_v2, :start_genservers, true) do
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

    # AI Ads Manager (behind feature flag).
    # Also gated on :start_genservers — test env never starts it.
    ads_manager_children =
      if Application.get_env(:blockster_v2, :ai_ads_manager, [])[:enabled] and
           Application.get_env(:blockster_v2, :start_genservers, true) do
        [{BlocksterV2.AdsManager, []}]
      else
        []
      end

    # Hourly promo scheduler is DEACTIVATED by default. To re-enable, set
    # HOURLY_PROMO_ENABLED=true (runtime config) AND toggle the
    # `hourly_promo_enabled` SystemConfig flag true via /admin/promo.
    # See docs/social_login_plan.md §Appendix: Hourly promo deactivation.
    hourly_promo_children =
      if Application.get_env(:blockster_v2, :hourly_promo, [])[:enabled] and
           Application.get_env(:blockster_v2, :start_genservers, true) do
        [{BlocksterV2.TelegramBot.HourlyPromoScheduler, []}]
      else
        []
      end

    # Bot reader system (behind feature flag).
    # Also gated on :start_genservers so the test env never starts the
    # coordinator regardless of BOT_SYSTEM_ENABLED in .env — see test.exs.
    # Without this, BotCoordinator.init schedules :initialize after 30s,
    # fires during the test suite, and DB-write Tasks crash mid-test when
    # the sandbox owner exits, taking the Repo down with the supervisor.
    bot_system_children =
      if Application.get_env(:blockster_v2, :bot_system, [])[:enabled] and
           Application.get_env(:blockster_v2, :start_genservers, true) do
        [{BlocksterV2.BotSystem.BotCoordinator, []}]
      else
        []
      end

    # Real-time sister-app widget pollers (behind WIDGETS_ENABLED flag).
    # Also gated on :start_genservers so test env never starts them — the
    # pollers tick forever and try to broadcast on PubSub even after the
    # test's PubSub registry shuts down, taking the supervisor with them.
    widgets_children =
      if Application.get_env(:blockster_v2, :widgets, [])[:enabled] and
           Application.get_env(:blockster_v2, :start_genservers, true) do
        [
          {BlocksterV2.Widgets.FateSwapFeedTracker, []},
          {BlocksterV2.Widgets.RogueTraderBotsTracker, []},
          {BlocksterV2.Widgets.RogueTraderChartTracker, []}
        ]
      else
        []
      end

    # Endpoint always starts last
    children = base_children ++ genserver_children ++ content_automation_children ++ oban_children ++ notification_children ++ ads_manager_children ++ hourly_promo_children ++ bot_system_children ++ widgets_children ++ [BlocksterV2Web.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options.
    #
    # In test env we raise max_restarts so transient orphan-task crashes
    # (Task.start callsites that survive past the test sandbox owner) can't
    # exhaust the supervisor's default 3-in-5s budget and take the Repo +
    # PubSub + EmailOtpStore down with it. Default budget is fine in prod —
    # if a base_child genuinely flaps in production we want to fail fast.
    # We piggyback on :start_genservers (false in test, true everywhere else)
    # rather than a separate flag.
    max_restarts =
      if Application.get_env(:blockster_v2, :start_genservers, true), do: 3, else: 1_000

    opts = [strategy: :one_for_one, name: BlocksterV2.Supervisor, max_restarts: max_restarts]
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
