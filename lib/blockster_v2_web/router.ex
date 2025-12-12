defmodule BlocksterV2Web.Router do
  use BlocksterV2Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BlocksterV2Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BlocksterV2Web.Plugs.V2RedirectPlug
    plug BlocksterV2Web.Plugs.AuthPlug
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug BlocksterV2Web.Plugs.AuthPlug
  end

  scope "/", BlocksterV2Web do
    pipe_through :browser

    live_session :admin,
      on_mount: [BlocksterV2Web.SearchHook, BlocksterV2Web.UserAuth, BlocksterV2Web.BuxBalanceHook, BlocksterV2Web.AdminAuth],
      layout: {BlocksterV2Web.Layouts, :app} do
      live "/admin", AdminLive, :index
      live "/admin/posts", PostsAdminLive, :index
      live "/admin/waitlist", WaitlistAdminLive, :index
      live "/admin/events", EventsAdminLive, :index
      live "/admin/events/new", EventLive.Form, :new
      live "/admin/events/:id/edit", EventLive.Form, :edit
      live "/admin/campaigns", CampaignsAdminLive, :index
      live "/hub/:slug/admin", HubLive.HubAdmin, :index
    end

    live_session :authenticated,
      on_mount: [BlocksterV2Web.SearchHook, BlocksterV2Web.UserAuth, BlocksterV2Web.BuxBalanceHook],
      layout: {BlocksterV2Web.Layouts, :app} do
      live "/profile", UserProfileLive, :index
    end

    live_session :author_new,
      on_mount: [BlocksterV2Web.SearchHook, {BlocksterV2Web.UserAuth, :default}, BlocksterV2Web.BuxBalanceHook, {BlocksterV2Web.AuthorAuth, :require_author}],
      layout: {BlocksterV2Web.Layouts, :app} do
      live "/new", PostLive.Form, :new
    end

    live_session :author_edit,
      on_mount: [BlocksterV2Web.SearchHook, {BlocksterV2Web.UserAuth, :default}, BlocksterV2Web.BuxBalanceHook, {BlocksterV2Web.AuthorAuth, :check_post_ownership}],
      layout: {BlocksterV2Web.Layouts, :app} do
      live "/:slug/edit", PostLive.Form, :edit
    end

    # Waitlist routes (minimal root layout only) - must come before catch-all /:slug route
    live_session :waitlist,
      layout: {BlocksterV2Web.Layouts, :root} do
      live "/waitlist", WaitlistLive, :index
    end

    # Waitlist verification (controller route)
    get "/waitlist/verify", WaitlistController, :verify

    # X (Twitter) OAuth routes
    get "/auth/x", XAuthController, :authorize
    get "/auth/x/callback", XAuthController, :callback
    delete "/auth/x/disconnect", XAuthController, :disconnect

    live_session :default,
      on_mount: [BlocksterV2Web.SearchHook, BlocksterV2Web.UserAuth, BlocksterV2Web.BuxBalanceHook],
      layout: {BlocksterV2Web.Layouts, :app} do
      live "/", PostLive.Index, :index
      live "/login", LoginLive, :index
      live "/how-it-works", PostLive.HowItWorks, :index
      live "/events", EventLive.Index, :index
      live "/event/:slug", EventLive.Show, :show
      live "/hubs", HubLive.Index, :index
      live "/hubs/admin", HubLive.Admin, :index
      live "/hubs/admin/new", HubLive.Admin, :new
      live "/hubs/admin/:id/edit", HubLive.Admin, :edit
      live "/hub/:slug", HubLive.Show, :show
      live "/category/:category", PostLive.Category, :show
      live "/tag/:tag", PostLive.Tag, :show
      live "/shop-landing", ShopLive.Landing, :index
      live "/shop", ShopLive.Index, :index
      live "/shop/:slug", ShopLive.Show, :show
      live "/member/:slug", MemberLive.Show, :show
      live "/:slug", PostLive.Show, :show
    end
  end

  # Other scopes may use custom stacks.
  scope "/api", BlocksterV2Web do
    pipe_through :api

    post "/s3/presigned-url", S3Controller, :presigned_url

    # Authentication endpoints
    post "/auth/wallet/verify", AuthController, :verify_wallet
    post "/auth/email/verify", AuthController, :verify_email
    post "/auth/logout", AuthController, :logout
    get "/auth/me", AuthController, :me
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:blockster_v2, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BlocksterV2Web.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
