defmodule BlocksterV2Web.BannersAdminLive do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Ads
  alias BlocksterV2.Ads.Banner

  @placements [
    {"Listings — Top (Desktop) [home/category/tag]", "homepage_top_desktop"},
    {"Listings — Top (Mobile) [home/category/tag]", "homepage_top_mobile"},
    {"Listings — Inline (between posts on home/category/tag)", "homepage_inline"},
    {"Article — Inline 1 (⅓ mark)", "article_inline_1"},
    {"Article — Inline 2 (⅔ mark)", "article_inline_2"},
    {"Article — Inline 3 (end)", "article_inline_3"},
    {"Article — Left Sidebar", "sidebar_left"},
    {"Article — Right Sidebar", "sidebar_right"},
    {"Article — Bottom", "article_bottom"},
    {"Video Player — Top", "video_player_top"},
    {"Mobile — Top", "mobile_top"},
    {"Mobile — Mid", "mobile_mid"},
    {"Mobile — Bottom", "mobile_bottom"}
  ]

  @templates [
    {"Image (upload a banner image)", "image"},
    {"Dark Gradient (dark card with heading, description, CTA)", "dark_gradient"},
    {"Portrait (image + dark panel with heading, CTA)", "portrait"},
    {"Split Card (white card with text left, colored panel right)", "split_card"},
    {"Follow Bar (compact dark bar with icon + heading)", "follow_bar"},
    {"Luxury Watch (editorial — brand · watch · model · price)", "luxury_watch"},
    {"Luxury Watch — Compact Full (whole image visible · image-driven height)", "luxury_watch_compact_full"},
    {"Luxury Watch — Skyscraper (200 × tall sidebar)", "luxury_watch_skyscraper"},
    {"Luxury Watch — Banner (full-width horizontal leaderboard)", "luxury_watch_banner"},
    {"Luxury Watch — Split (info left, watch panel right)", "luxury_watch_split"},
    {"Luxury Car (landscape hero · year/model · spec row · price)", "luxury_car"},
    {"Luxury Car — Skyscraper (200 × tall sidebar)", "luxury_car_skyscraper"},
    {"Luxury Car — Banner (full-width horizontal leaderboard)", "luxury_car_banner"},
    {"Jet Card — Compact (narrower · trimmed jet image · 560px)", "jet_card_compact"},
    {"Jet Card — Skyscraper (200 × tall sidebar)", "jet_card_skyscraper"}
  ]

  # Which params each template supports
  @template_params %{
    "dark_gradient" => ~w(heading description cta_text brand_name brand_color icon_url bg_color bg_color_end),
    "portrait" => ~w(heading subtitle cta_text brand_name image_url image_fit image_bg_color bg_color bg_color_end accent_color),
    "split_card" => ~w(heading description cta_text brand_name brand_color icon_url badge panel_color panel_color_end stat_label_top stat_value stat_label_bottom),
    "follow_bar" => ~w(heading brand_color icon_url),
    "luxury_watch" =>
      ~w(brand_name image_url image_bg_color model_name reference price_usd tagline cta_text
         spec_1_label spec_1_value spec_2_label spec_2_value
         spec_3_label spec_3_value spec_4_label spec_4_value
         bg_color bg_color_end accent_color text_color),
    "luxury_watch_compact_full" =>
      ~w(brand_name image_url image_bg_color model_name reference price_usd
         bg_color bg_color_end accent_color text_color),
    "luxury_watch_skyscraper" =>
      ~w(brand_name image_url image_bg_color model_name reference price_usd
         bg_color bg_color_end accent_color text_color),
    "luxury_watch_banner" =>
      ~w(brand_name image_url image_bg_color model_name reference price_usd
         bg_color bg_color_end accent_color text_color),
    "luxury_watch_split" =>
      ~w(brand_name image_url image_bg_color model_name reference price_usd cta_text
         bg_color bg_color_end accent_color text_color),
    "luxury_car" =>
      ~w(brand_name badge image_url image_bg_color year model_name trim price_usd cta_text
         spec_1_label spec_1_value spec_2_label spec_2_value
         spec_3_label spec_3_value spec_4_label spec_4_value
         bg_color bg_color_end accent_color text_color),
    "luxury_car_skyscraper" =>
      ~w(brand_name image_url image_bg_color year model_name trim price_usd
         bg_color bg_color_end accent_color text_color),
    "luxury_car_banner" =>
      ~w(brand_name image_url image_bg_color year model_name trim price_usd
         bg_color bg_color_end accent_color text_color),
    "jet_card_compact" =>
      ~w(brand_name badge image_url image_bg_color hours headline aircraft_category
         price_usd cta_text bg_color bg_color_end accent_color text_color),
    "jet_card_skyscraper" =>
      ~w(brand_name image_url image_bg_color hours headline aircraft_category price_usd
         bg_color bg_color_end accent_color text_color),
    "image" => []
  }

  # Enum-typed template params that should render as <select> dropdowns
  # instead of free-form text inputs. Key = param name.
  @enum_params %{
    "image_fit" => %{
      default: "cover",
      hint: "how the image fills the 4:3 image box",
      options: [
        {"Cover (fill, may crop edges)", "cover"},
        {"Contain (fit whole image, may show bars)", "contain"},
        {"Scale down (contain, but never upscale)", "scale-down"}
      ]
    }
  }

  # Real-time widget catalog (Phase 6 admin UI)
  @widget_types [
    {"— none —", ""},
    {"RogueTrader — Skyscraper (200 × 760) — all 30 bots", "rt_skyscraper"},
    {"RogueTrader — Square compact (200 × 200) — 1 bot + sparkline", "rt_square_compact"},
    {"RogueTrader — Sidebar tile (200 × 300) — 1 bot + H/L", "rt_sidebar_tile"},
    {"RogueTrader — Chart landscape (full × 360) — 1 bot + full chart", "rt_chart_landscape"},
    {"RogueTrader — Chart portrait (440 × 640)", "rt_chart_portrait"},
    {"RogueTrader — Full card (full × ~900) — chart + 8-stat grid", "rt_full_card"},
    {"RogueTrader — Ticker (full × 56) — horizontal marquee", "rt_ticker"},
    {"RogueTrader — Leaderboard inline (full × ~480)", "rt_leaderboard_inline"},
    {"FateSwap — Skyscraper (200 × 760) — live trade feed", "fs_skyscraper"},
    {"FateSwap — Square compact (200 × 200) — 1 trade", "fs_square_compact"},
    {"FateSwap — Sidebar tile (200 × 320) — 1 trade detailed", "fs_sidebar_tile"},
    {"FateSwap — Hero portrait (440 × ~720)", "fs_hero_portrait"},
    {"FateSwap — Hero landscape (full × 480)", "fs_hero_landscape"},
    {"FateSwap — Ticker (full × 56)", "fs_ticker"}
  ]

  @rt_self_selecting ~w(rt_chart_landscape rt_chart_portrait rt_full_card rt_square_compact rt_sidebar_tile)
  @fs_self_selecting ~w(fs_hero_portrait fs_hero_landscape fs_square_compact fs_sidebar_tile)

  @rt_selection_modes [
    {"Biggest gainer (default) — max positive change %", "biggest_gainer"},
    {"Biggest mover — max |change %| (gainers or losers)", "biggest_mover"},
    {"Highest AUM — largest sol_balance", "highest_aum"},
    {"Top ranked — rank 1 by lp_price", "top_ranked"},
    {"Fixed — pin a specific bot + timeframe", "fixed"}
  ]

  @fs_selection_modes [
    {"Biggest profit (default) — max positive profit", "biggest_profit"},
    {"Biggest discount — max discount_pct on a buy", "biggest_discount"},
    {"Most recent filled — newest settled filled order", "most_recent_filled"},
    {"Random recent — rotate through last 20", "random_recent"},
    {"Fixed — pin a specific order id", "fixed"}
  ]

  @rt_timeframes ~w(1h 6h 24h 48h 7d)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:banners, Ads.list_banners())
     |> assign(:editing_banner, nil)
     |> assign(:show_new_form, false)
     |> assign(:form, nil)
     |> assign(:placements, @placements)
     |> assign(:templates, @templates)
     |> assign(:template_params, @template_params)
     |> assign(:enum_params, @enum_params)
     |> assign(:widget_types, @widget_types)
     |> assign(:rt_selection_modes, @rt_selection_modes)
     |> assign(:fs_selection_modes, @fs_selection_modes)
     |> assign(:rt_timeframes, @rt_timeframes)
     |> assign(:selected_template, "image")
     |> assign(:selected_widget_type, "")
     |> assign(:selected_widget_config, %{})}
  end

  @impl true
  def handle_event("show_new_form", _, socket) do
    changeset = Banner.changeset(%Banner{is_active: true}, %{})

    {:noreply,
     socket
     |> assign(:show_new_form, true)
     |> assign(:editing_banner, nil)
     |> assign(:selected_template, "image")
     |> assign(:selected_widget_type, "")
     |> assign(:selected_widget_config, %{})
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("cancel", _, socket) do
    {:noreply,
     socket
     |> assign(:show_new_form, false)
     |> assign(:editing_banner, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    banner = Ads.get_banner!(id)
    changeset = Banner.changeset(banner, %{})

    {:noreply,
     socket
     |> assign(:editing_banner, banner)
     |> assign(:show_new_form, false)
     |> assign(:selected_template, banner.template || "image")
     |> assign(:selected_widget_type, banner.widget_type || "")
     |> assign(:selected_widget_config, banner.widget_config || %{})
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"banner" => params}, socket) do
    base = socket.assigns.editing_banner || %Banner{}
    selected_template = params["template"] || socket.assigns.selected_template
    selected_widget_type = params["widget_type"] || socket.assigns.selected_widget_type
    selected_widget_config = params["widget_config"] || socket.assigns.selected_widget_config || %{}

    # Normalise: clear widget_config when widget_type is blank so we don't carry stale keys
    selected_widget_config =
      if selected_widget_type in [nil, ""], do: %{}, else: selected_widget_config

    params =
      params
      |> Map.put("widget_type", if(selected_widget_type == "", do: nil, else: selected_widget_type))
      |> Map.put("widget_config", selected_widget_config)

    changeset =
      base
      |> Banner.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_template, selected_template)
     |> assign(:selected_widget_type, selected_widget_type)
     |> assign(:selected_widget_config, selected_widget_config)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"banner" => params}, socket) do
    params = normalize_widget_params(params)

    if socket.assigns.editing_banner do
      case Ads.update_banner(socket.assigns.editing_banner, params) do
        {:ok, _banner} ->
          {:noreply,
           socket
           |> put_flash(:info, "Banner updated")
           |> assign(:banners, Ads.list_banners())
           |> assign(:editing_banner, nil)
           |> assign(:form, nil)}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    else
      case Ads.create_banner(params) do
        {:ok, _banner} ->
          {:noreply,
           socket
           |> put_flash(:info, "Banner created")
           |> assign(:banners, Ads.list_banners())
           |> assign(:show_new_form, false)
           |> assign(:form, nil)}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    banner = Ads.get_banner!(id)

    case Ads.toggle_active(banner) do
      {:ok, _} ->
        {:noreply, assign(socket, :banners, Ads.list_banners())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update banner")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    banner = Ads.get_banner!(id)

    case Ads.delete_banner(banner) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Banner deleted")
         |> assign(:banners, Ads.list_banners())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete banner")}
    end
  end

  # Coerces blank widget_type to nil and drops widget_config on non-widget rows
  defp normalize_widget_params(params) do
    case params["widget_type"] do
      nil -> Map.put_new(params, "widget_config", %{})
      "" -> params |> Map.put("widget_type", nil) |> Map.put("widget_config", %{})
      _ -> Map.put_new(params, "widget_config", %{})
    end
  end

  @doc false
  def widget_family(type) when is_binary(type) do
    cond do
      type in @rt_self_selecting -> :rt_self
      type in @fs_self_selecting -> :fs_self
      String.starts_with?(type, "rt_") -> :rt_all
      String.starts_with?(type, "fs_") -> :fs_all
      true -> :none
    end
  end

  def widget_family(_), do: :none

  defp selection_modes_for(type) do
    case widget_family(type) do
      :rt_self -> @rt_selection_modes
      :fs_self -> @fs_selection_modes
      _ -> []
    end
  end

  defp default_selection_for(:rt_self), do: "biggest_gainer"
  defp default_selection_for(:fs_self), do: "biggest_profit"
  defp default_selection_for(_), do: nil

  # Renders the widget preview inside the admin form using cached tracker data.
  # If no data is cached (WIDGETS_ENABLED=false in dev), the widget's own skeleton
  # or empty-state is shown — which is also useful as admin feedback.
  defp render_widget_preview(assigns) do
    preview_banner = %Banner{
      id: -1,
      name: "admin preview",
      placement: "sidebar_right",
      widget_type: assigns.selected_widget_type,
      widget_config: assigns.selected_widget_config || %{},
      is_active: true
    }

    bots = BlocksterV2.Widgets.RogueTraderBotsTracker.get_bots()
    trades = BlocksterV2.Widgets.FateSwapFeedTracker.get_trades()

    subject =
      case widget_family(assigns.selected_widget_type) do
        :rt_self -> BlocksterV2.Widgets.WidgetSelector.pick_rt(bots, preview_banner)
        :fs_self -> BlocksterV2.Widgets.WidgetSelector.pick_fs(trades, preview_banner)
        _ -> nil
      end

    chart_data =
      case subject do
        {bot_id, tf} when is_binary(bot_id) and is_binary(tf) ->
          %{{bot_id, tf} => BlocksterV2.Widgets.RogueTraderChartTracker.get_series(bot_id, tf)}

        _ ->
          %{}
      end

    selections = if subject, do: %{preview_banner.id => subject}, else: %{}

    preview_assigns = %{
      banner: preview_banner,
      bots: bots,
      trades: trades,
      selections: selections,
      chart_data: chart_data,
      tracker_errors: BlocksterV2.Widgets.TrackerStatus.errors()
    }

    BlocksterV2Web.WidgetComponents.widget_or_ad(preview_assigns)
  end

  defp placement_label(value) do
    case Enum.find(@placements, fn {_label, v} -> v == value end) do
      {label, _} -> label
      nil -> value
    end
  end

  defp param_placeholder("heading"), do: "Buy SOL instantly"
  defp param_placeholder("description"), do: "The fastest way to get SOL into your wallet"
  defp param_placeholder("cta_text"), do: "Get Started"
  defp param_placeholder("brand_name"), do: "Moonpay"
  defp param_placeholder("brand_color"), do: "#7D00FF"
  defp param_placeholder("icon_url"), do: "https://..."
  defp param_placeholder("image_url"), do: "https://..."
  defp param_placeholder("bg_color"), do: "#0a1838"
  defp param_placeholder("bg_color_end"), do: "#142a6b"
  defp param_placeholder("accent_color"), do: "#FF6B35"
  defp param_placeholder("subtitle"), do: "Secondary heading"
  defp param_placeholder("badge"), do: "New"
  defp param_placeholder("panel_color"), do: "#7D00FF"
  defp param_placeholder("panel_color_end"), do: "#4A00B8"
  defp param_placeholder("stat_label_top"), do: "APY"
  defp param_placeholder("stat_value"), do: "12.5%"
  defp param_placeholder("stat_label_bottom"), do: "Est. annual"
  defp param_placeholder("image_bg_color"), do: "#0a1838 (fallback when image is contain-mode)"
  defp param_placeholder("model_name"), do: "Rolex Day-Date 36"
  defp param_placeholder("reference"), do: "Reference 18078 · c. 1988"
  defp param_placeholder("tagline"), do: "A watch you'll pass down."
  defp param_placeholder("price_usd"), do: "23500 (USD; SOL value is shown live from the price tracker)"
  defp param_placeholder("text_color"), do: "#E8E4DD"
  defp param_placeholder("spec_1_label"), do: "Case"
  defp param_placeholder("spec_1_value"), do: "36mm"
  defp param_placeholder("spec_2_label"), do: "Dial"
  defp param_placeholder("spec_2_value"), do: "Bark"
  defp param_placeholder("spec_3_label"), do: "Band"
  defp param_placeholder("spec_3_value"), do: "18k Gold"
  defp param_placeholder("spec_4_label"), do: "Year"
  defp param_placeholder("spec_4_value"), do: "c. 1988"
  defp param_placeholder(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <BlocksterV2Web.DesignSystem.header
      current_user={@current_user}
      active="home"
      bux_balance={Map.get(assigns, :bux_balance, 0)}
      token_balances={Map.get(assigns, :token_balances, %{})}
      cart_item_count={Map.get(assigns, :cart_item_count, 0)}
      unread_notification_count={Map.get(assigns, :unread_notification_count, 0)}
      notification_dropdown_open={Map.get(assigns, :notification_dropdown_open, false)}
      recent_notifications={Map.get(assigns, :recent_notifications, [])}
      search_query={Map.get(assigns, :search_query, "")}
      search_results={Map.get(assigns, :search_results, [])}
      show_search_results={Map.get(assigns, :show_search_results, false)}
      connecting={Map.get(assigns, :connecting, false)}
    />
    <div class="min-h-screen bg-[#fafaf9] pt-8 pb-12">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
            <div>
              <h1 class="text-2xl font-bold text-gray-900">Ad Banners</h1>
              <p class="mt-1 text-sm text-gray-600">
                Manage banner ads shown in article sidebars and mobile placements.
              </p>
            </div>
            <%= unless @show_new_form || @editing_banner do %>
              <button
                phx-click="show_new_form"
                class="bg-gray-900 hover:bg-black text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer"
              >
                New Banner
              </button>
            <% end %>
          </div>

          <%= if @show_new_form || @editing_banner do %>
            <div id="banner-form" phx-hook="ScrollIntoView" class="px-6 py-4 border-b border-gray-200 bg-gray-50">
              <h2 class="text-lg font-semibold text-gray-900 mb-4">
                {if @editing_banner, do: "Edit Banner", else: "New Banner"}
              </h2>
              <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-4">
                <%!-- Top-of-form error summary so submit failures are never silent. --%>
                <%= if @form.source.action && @form.errors != [] do %>
                  <div class="rounded-lg border border-red-200 bg-red-50 px-4 py-3">
                    <div class="text-sm font-semibold text-red-800 mb-1">
                      Banner could not be saved — fix the highlighted fields:
                    </div>
                    <ul class="text-xs text-red-700 list-disc list-inside space-y-0.5">
                      <%= for {field, {msg, _}} <- @form.errors do %>
                        <li><span class="font-medium">{Phoenix.Naming.humanize(field)}</span>: {msg}</li>
                      <% end %>
                    </ul>
                  </div>
                <% end %>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Name</label>
                    <input
                      type="text"
                      name="banner[name]"
                      value={@form[:name].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                      placeholder="Internal name (e.g. Acme Q2 Right Sidebar)"
                      required
                    />
                    <%= if @form[:name].errors != [] do %>
                      <p class="mt-1 text-sm text-red-600">
                        {Enum.map(@form[:name].errors, fn {msg, _} -> msg end) |> Enum.join(", ")}
                      </p>
                    <% end %>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Placement</label>
                    <select
                      name="banner[placement]"
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900 cursor-pointer"
                      required
                    >
                      <option value="">Select a placement…</option>
                      <%= for {label, value} <- @placements do %>
                        <option value={value} selected={@form[:placement].value == value}>
                          {label}
                        </option>
                      <% end %>
                    </select>
                    <%= if @form[:placement].errors != [] do %>
                      <p class="mt-1 text-sm text-red-600">
                        {Enum.map(@form[:placement].errors, fn {msg, _} -> msg end) |> Enum.join(", ")}
                      </p>
                    <% end %>
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    Banner Image
                    <%= if @selected_widget_type in [nil, ""] do %>
                      <span class="text-red-600 font-normal">*</span>
                      <span class="text-xs font-normal text-gray-500">— required for template ads</span>
                    <% else %>
                      <span class="text-xs font-normal text-gray-500">— ignored for widget banners</span>
                    <% end %>
                  </label>
                  <div class="flex items-start gap-4">
                    <img
                      id="banner_image_preview"
                      src={@form[:image_url].value || ""}
                      alt="Banner preview"
                      class={[
                        "h-28 w-auto max-w-[240px] object-contain rounded border border-gray-200 bg-gray-50",
                        if(@form[:image_url].value in [nil, ""], do: "hidden", else: "")
                      ]}
                    />
                    <div class="flex-1 space-y-2">
                      <input
                        type="file"
                        id="banner_image_file"
                        phx-hook="BannerAdminUpload"
                        data-input="banner_image_url_input"
                        data-preview="banner_image_preview"
                        accept="image/*"
                        class="block w-full text-sm text-gray-700 file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-gray-900 file:text-white hover:file:bg-black file:cursor-pointer cursor-pointer"
                      />
                      <p class="text-xs text-gray-500">
                        PNG, JPG, GIF, or WebP. Max 25MB. Animated GIFs supported.
                      </p>
                      <input
                        type="hidden"
                        id="banner_image_url_input"
                        name="banner[image_url]"
                        value={@form[:image_url].value}
                      />
                      <%= if @form[:image_url].value not in [nil, ""] do %>
                        <p class="text-xs text-gray-600 break-all">
                          <span class="font-medium">URL:</span> {@form[:image_url].value}
                        </p>
                      <% end %>
                      <%= if @form[:image_url].errors != [] do %>
                        <p class="mt-1 text-sm text-red-600">
                          {Enum.map(@form[:image_url].errors, fn {msg, _} -> msg end) |> Enum.join(", ")}
                        </p>
                      <% end %>
                    </div>
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Link URL</label>
                  <input
                    type="url"
                    name="banner[link_url]"
                    value={@form[:link_url].value}
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                    placeholder="https://example.com"
                  />
                </div>

                <%!-- Widget Type (real-time widget catalog) --%>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Widget Type</label>
                  <select
                    name="banner[widget_type]"
                    id="banner_widget_type"
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900 cursor-pointer"
                  >
                    <%= for {label, value} <- @widget_types do %>
                      <option value={value} selected={@selected_widget_type == value}>
                        {label}
                      </option>
                    <% end %>
                  </select>
                  <p class="text-xs text-gray-500 mt-1">
                    Leave as "none" for a regular image/template ad. Widget banners stream live data from RogueTrader + FateSwap.
                  </p>
                </div>

                <%!-- Widget Config (shown only when widget_type != "") --%>
                <% widget_family = widget_family(@selected_widget_type) %>
                <%= if widget_family in [:rt_self, :fs_self] do %>
                  <% modes = selection_modes_for(@selected_widget_type) %>
                  <% current_selection = @selected_widget_config["selection"] || default_selection_for(widget_family) %>
                  <div class="border border-purple-200 rounded-lg p-4 bg-purple-50 space-y-3">
                    <h3 class="text-sm font-semibold text-gray-900">
                      Widget Config
                      <span class="font-normal text-gray-500">— {@selected_widget_type}</span>
                    </h3>
                    <div>
                      <label class="block text-xs font-medium text-gray-600 mb-1">Selection mode</label>
                      <select
                        name="banner[widget_config][selection]"
                        class="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900 cursor-pointer"
                      >
                        <%= for {label, value} <- modes do %>
                          <option value={value} selected={current_selection == value}>{label}</option>
                        <% end %>
                      </select>
                    </div>

                    <%= if current_selection == "fixed" and widget_family == :rt_self do %>
                      <div class="grid grid-cols-2 gap-3">
                        <div>
                          <label class="block text-xs font-medium text-gray-600 mb-1">Bot ID / slug</label>
                          <input
                            type="text"
                            name="banner[widget_config][bot_id]"
                            value={@selected_widget_config["bot_id"] || ""}
                            placeholder="kronos"
                            class="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-lg"
                          />
                        </div>
                        <div>
                          <label class="block text-xs font-medium text-gray-600 mb-1">Timeframe</label>
                          <select
                            name="banner[widget_config][timeframe]"
                            class="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-lg cursor-pointer"
                          >
                            <%= for tf <- @rt_timeframes do %>
                              <option value={tf} selected={@selected_widget_config["timeframe"] == tf}>{String.upcase(tf)}</option>
                            <% end %>
                          </select>
                        </div>
                      </div>
                    <% end %>

                    <%= if current_selection == "fixed" and widget_family == :fs_self do %>
                      <div>
                        <label class="block text-xs font-medium text-gray-600 mb-1">Order ID (UUID)</label>
                        <input
                          type="text"
                          name="banner[widget_config][order_id]"
                          value={@selected_widget_config["order_id"] || ""}
                          placeholder="ord-abcd-…"
                          class="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-lg"
                        />
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if @selected_widget_type not in [nil, ""] do %>
                  <%!-- Live preview --%>
                  <div class="border border-gray-200 rounded-lg p-4 bg-[#f3f3f2]">
                    <div class="text-xs font-semibold text-gray-700 uppercase tracking-wider mb-3">
                      Live Preview
                    </div>
                    {render_widget_preview(assigns)}
                  </div>
                <% end %>

                <%!-- Template type --%>
                <div class={if @selected_widget_type not in [nil, ""], do: "opacity-50 pointer-events-none", else: ""}>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Template Style</label>
                  <select
                    name="banner[template]"
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900 cursor-pointer"
                  >
                    <%= for {label, value} <- @templates do %>
                      <option value={value} selected={@selected_template == value}>
                        {label}
                      </option>
                    <% end %>
                  </select>
                  <p class="text-xs text-gray-500 mt-1">
                    "Image" uses the uploaded banner image. Other templates build styled ads from the parameters below.
                    <%= if @selected_widget_type not in [nil, ""] do %>
                      <span class="text-purple-700 font-medium">
                        · Ignored while a Widget Type is selected.
                      </span>
                    <% end %>
                  </p>
                </div>

                <%!-- Template params (shown when template != "image") --%>
                <% current_params = if(@form[:params].value, do: @form[:params].value, else: %{}) %>
                <% param_fields = Map.get(@template_params, @selected_template, []) %>
                <%= if param_fields != [] do %>
                  <div class="border border-gray-200 rounded-lg p-4 bg-white space-y-3">
                    <h3 class="text-sm font-semibold text-gray-900 mb-2">
                      Template Parameters
                      <span class="font-normal text-gray-500">— {@selected_template}</span>
                    </h3>
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                      <%= for field <- param_fields do %>
                        <% is_color = String.contains?(field, "color") %>
                        <% is_upload = field in ["icon_url", "image_url"] %>
                        <% is_select = Map.has_key?(@enum_params, field) %>
                        <div class={if(is_upload, do: "md:col-span-2", else: "")}>
                          <label class="block text-xs font-medium text-gray-600 mb-1">
                            {field |> String.replace("_", " ") |> String.capitalize()}
                            <%= if is_upload do %>
                              <span class="font-normal text-gray-400">— upload or paste URL</span>
                            <% end %>
                            <%= if is_select do %>
                              <span class="font-normal text-gray-400">— {@enum_params[field].hint}</span>
                            <% end %>
                          </label>
                          <%= cond do %>
                            <% is_select -> %>
                              <select
                                name={"banner[params][#{field}]"}
                                class="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-lg cursor-pointer"
                              >
                                <%= for {label, value} <- @enum_params[field].options do %>
                                  <option value={value} selected={(current_params[field] || @enum_params[field].default) == value}>{label}</option>
                                <% end %>
                              </select>
                            <% is_upload -> %>
                              <%!-- File upload + URL input + preview for icon/image fields --%>
                              <div class="flex items-start gap-3">
                                <% upload_id = "param_#{field}_file" %>
                                <% input_id = "param_#{field}_input" %>
                                <% preview_id = "param_#{field}_preview" %>
                                <img
                                  id={preview_id}
                                  src={current_params[field] || ""}
                                  alt="Preview"
                                  class={[
                                    "h-12 w-12 object-contain rounded border border-gray-200 bg-gray-50 flex-shrink-0",
                                    if(current_params[field] in [nil, ""], do: "hidden", else: "")
                                  ]}
                                />
                                <div class="flex-1 space-y-1.5">
                                  <input
                                    type="file"
                                    id={upload_id}
                                    phx-hook="BannerAdminUpload"
                                    data-input={input_id}
                                    data-preview={preview_id}
                                    accept="image/*"
                                    class="block w-full text-xs text-gray-700 file:mr-3 file:py-1 file:px-3 file:rounded-lg file:border-0 file:text-xs file:font-medium file:bg-gray-900 file:text-white hover:file:bg-black file:cursor-pointer cursor-pointer"
                                  />
                                  <input
                                    type="text"
                                    id={input_id}
                                    name={"banner[params][#{field}]"}
                                    value={current_params[field] || ""}
                                    placeholder={param_placeholder(field)}
                                    class="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                                  />
                                </div>
                              </div>
                            <% true -> %>
                              <%!-- Regular text input (with color swatch for color fields) --%>
                              <div class={if(is_color, do: "flex items-center gap-2", else: "")}>
                                <input
                                  type="text"
                                  name={"banner[params][#{field}]"}
                                  value={current_params[field] || ""}
                                  placeholder={param_placeholder(field)}
                                  class="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                                />
                                <%= if is_color do %>
                                  <% color_val = current_params[field] || "#7D00FF" %>
                                  <div class="w-7 h-7 rounded border border-gray-300 flex-shrink-0" style={"background: #{color_val}"}></div>
                                <% end %>
                              </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Sort Order</label>
                    <input
                      type="number"
                      name="banner[sort_order]"
                      value={@form[:sort_order].value || 0}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                      placeholder="0"
                      min="0"
                    />
                    <p class="text-xs text-gray-500 mt-1">Lower = shown first</p>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Dimensions</label>
                    <input
                      type="text"
                      name="banner[dimensions]"
                      value={@form[:dimensions].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                      placeholder="300x600"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
                    <input
                      type="date"
                      name="banner[start_date]"
                      value={@form[:start_date].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">End Date</label>
                    <input
                      type="date"
                      name="banner[end_date]"
                      value={@form[:end_date].value}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-900 focus:border-gray-900"
                    />
                  </div>
                </div>

                <div class="flex items-center gap-2">
                  <input
                    type="hidden"
                    name="banner[is_active]"
                    value="false"
                  />
                  <input
                    type="checkbox"
                    id="banner_is_active"
                    name="banner[is_active]"
                    value="true"
                    checked={@form[:is_active].value in [true, "true"]}
                    class="h-4 w-4 rounded border-gray-300 text-gray-900 focus:ring-gray-900 cursor-pointer"
                  />
                  <label for="banner_is_active" class="text-sm text-gray-700 cursor-pointer">
                    Active
                  </label>
                </div>

                <div class="flex gap-3">
                  <button
                    type="submit"
                    class="bg-gray-900 hover:bg-black text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer"
                  >
                    {if @editing_banner, do: "Update Banner", else: "Create Banner"}
                  </button>
                  <button
                    type="button"
                    phx-click="cancel"
                    class="bg-gray-200 hover:bg-gray-300 text-gray-700 px-4 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            </div>
          <% end %>

          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Preview
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Name
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Placement
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Template
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Stats
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= if @banners == [] do %>
                  <tr>
                    <td colspan="7" class="px-6 py-12 text-center text-sm text-gray-500">
                      No banners yet. Click "New Banner" to add one.
                    </td>
                  </tr>
                <% end %>
                <%= for banner <- @banners do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if banner.image_url do %>
                        <img
                          src={banner.image_url}
                          alt={banner.name}
                          class="h-12 w-auto max-w-[120px] object-contain rounded border border-gray-200"
                        />
                      <% else %>
                        <div class="h-12 w-20 bg-gray-100 rounded border border-dashed border-gray-300 flex items-center justify-center text-xs text-gray-400">
                          No image
                        </div>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="text-sm font-medium text-gray-900">{banner.name}</div>
                      <%= if banner.link_url do %>
                        <a
                          href={banner.link_url}
                          target="_blank"
                          class="text-xs text-blue-600 hover:underline truncate max-w-[200px] block"
                        >
                          {banner.link_url}
                        </a>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                        {placement_label(banner.placement)}
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if banner.widget_type do %>
                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-[#0A0A0F] text-[#CAFC00]">
                          {banner.widget_type}
                        </span>
                      <% else %>
                        <span class={[
                          "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                          if(banner.template in ["dark_gradient", "portrait", "split_card", "follow_bar"],
                            do: "bg-purple-100 text-purple-800",
                            else: "bg-gray-100 text-gray-600"
                          )
                        ]}>
                          {banner.template || "image"}
                        </span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <button
                        phx-click="toggle_active"
                        phx-value-id={banner.id}
                        class={[
                          "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium cursor-pointer",
                          if(banner.is_active,
                            do: "bg-green-100 text-green-800 hover:bg-green-200",
                            else: "bg-gray-100 text-gray-600 hover:bg-gray-200"
                          )
                        ]}
                      >
                        {if banner.is_active, do: "Active", else: "Inactive"}
                      </button>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-xs text-gray-600">
                      <div>{banner.impressions} impr.</div>
                      <div>{banner.clicks} clicks</div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <div class="flex gap-3">
                        <button
                          phx-click="edit"
                          phx-value-id={banner.id}
                          class="text-blue-600 hover:text-blue-800 font-medium cursor-pointer"
                        >
                          Edit
                        </button>
                        <button
                          phx-click="delete"
                          phx-value-id={banner.id}
                          data-confirm="Delete this banner permanently?"
                          class="text-red-600 hover:text-red-800 font-medium cursor-pointer"
                        >
                          Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div class="px-6 py-4 bg-gray-50 border-t border-gray-200">
            <p class="text-sm text-gray-600">
              Total banners: <span class="font-semibold">{length(@banners)}</span>
            </p>
          </div>
        </div>
      </div>
    </div>
    <BlocksterV2Web.DesignSystem.footer />
    """
  end
end
