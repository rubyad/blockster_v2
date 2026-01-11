defmodule HighRollersWeb.Router do
  use HighRollersWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HighRollersWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug HighRollersWeb.Plugs.RateLimit, limit: 100, window_ms: 60_000
  end

  # Rate-limited API for sensitive operations (withdrawals)
  pipeline :api_sensitive do
    plug :accepts, ["json"]
    plug HighRollersWeb.Plugs.RateLimit, limit: 10, window_ms: 60_000
  end

  # ===== Wallet Session API (needs browser pipeline for session access) =====
  scope "/api/wallet", HighRollersWeb do
    pipe_through [:browser]

    post "/connect", WalletController, :connect
    post "/disconnect", WalletController, :disconnect
    post "/balance", WalletController, :update_balance
  end

  # ===== API Routes (for JavaScript client) =====
  scope "/api", HighRollersWeb do
    pipe_through :api

    # Affiliate linking - called when wallet connects
    post "/link-affiliate", AffiliateController, :link
    get "/buyer-affiliate/:buyer", AffiliateController, :get_buyer_affiliate

    # Health checks
    get "/health", HealthController, :check
    get "/health/ready", HealthController, :ready
    get "/health/live", HealthController, :live
  end

  # ===== LiveView Routes =====
  scope "/", HighRollersWeb do
    pipe_through :browser

    # All routes use the same live session for shared state (wallet, etc.)
    # Layout :app provides header, hero, tabs, footer - wallet state comes from WalletHook
    live_session :default,
      on_mount: [{HighRollersWeb.WalletHook, :default}],
      layout: {HighRollersWeb.Layouts, :app} do
      live "/", MintLive, :index           # Default/home - mint tab
      live "/mint", MintLive, :index       # Explicit mint route
      live "/sales", SalesLive, :index     # Live sales tab
      live "/affiliates", AffiliatesLive, :index
      live "/my-nfts", MyNftsLive, :index  # Requires wallet (enforced in mount)
      live "/revenues", RevenuesLive, :index
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:high_rollers, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HighRollersWeb.Telemetry
    end
  end
end
