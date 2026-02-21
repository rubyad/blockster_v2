defmodule BlocksterV2Web.ContentAutomationLive.RequestArticle do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.{AltcoinAnalyzer, AuthorRotator, ContentGenerator, EventRoundup, XProfileFetcher}

  @categories ~w(defi rwa regulation gaming trading token_launches gambling privacy macro_trends investment bitcoin ethereum altcoins nft ai_crypto stablecoins cbdc security_hacks adoption mining fundraising events blockster_of_week)

  @impl true
  def mount(_params, _session, socket) do
    authors = AuthorRotator.personas() |> Enum.map(& &1.username) |> Enum.sort()

    {:ok,
     assign(socket,
       page_title: "Request Article",
       categories: @categories,
       authors: authors,
       form: %{
         "template" => "custom",
         "topic" => "",
         "category" => "defi",
         "instructions" => "",
         "angle" => "",
         "author" => "",
         "content_type" => "opinion",
         "x_handle" => "",
         "role" => "",
         "event_dates" => "",
         "event_url" => "",
         "event_location" => "",
         "sector" => "ai"
       },
       generating: false,
       fetching_x: false,
       fetching_events: false,
       fetching_market_data: false,
       error: nil
     )}
  end

  @impl true
  def handle_event("validate", %{"form" => form_params}, socket) do
    prev_template = socket.assigns.form["template"]
    new_template = form_params["template"]

    # When template changes, auto-set category and content_type
    form_params = case new_template do
      "blockster_of_week" ->
        form_params
        |> Map.put("category", "blockster_of_week")
        |> Map.put("content_type", "opinion")

      "event_preview" ->
        form_params
        |> Map.put("category", "events")
        |> Map.put("content_type", "news")

      "weekly_roundup" ->
        form_params
        |> Map.put("category", "events")
        |> Map.put("content_type", "news")

      "market_movers" ->
        form_params
        |> Map.put("category", "altcoins")
        |> Map.put("content_type", "news")

      "narrative_analysis" ->
        form_params
        |> Map.put("category", "altcoins")
        |> Map.put("content_type", "opinion")

      _ ->
        form_params
    end

    # When switching to certain templates, auto-populate instructions
    socket = cond do
      new_template == "weekly_roundup" && prev_template != "weekly_roundup" ->
        socket
        |> assign(form: form_params, fetching_events: true)
        |> start_async(:fetch_events, fn -> EventRoundup.get_events_for_week() end)

      new_template == "market_movers" && prev_template != "market_movers" ->
        socket
        |> assign(form: form_params, fetching_market_data: true)
        |> start_async(:fetch_market_data, fn ->
          movers = AltcoinAnalyzer.get_movers(:"7d", 10)
          narratives = AltcoinAnalyzer.detect_narratives(:"7d")
          market_data = AltcoinAnalyzer.format_for_prompt(movers, narratives)
          news_context = AltcoinAnalyzer.get_recent_news_for_tokens(movers)
          market_data <> "\n\nRELEVANT NEWS CONTEXT:\n" <> news_context
        end)

      new_template == "narrative_analysis" && prev_template != "narrative_analysis" ->
        sector = form_params["sector"] || "ai"
        socket
        |> assign(form: form_params, fetching_market_data: true)
        |> start_async(:fetch_sector_data, fn ->
          sector_data = AltcoinAnalyzer.get_sector_data(sector)
          movers = %{gainers: sector_data.tokens, losers: [], period: :"7d"}
          narratives = [{sector, %{tokens: sector_data.tokens, avg_change: sector_data.avg_change, count: sector_data.count}}]
          AltcoinAnalyzer.format_for_prompt(movers, narratives)
        end)

      true ->
        assign(socket, form: form_params)
    end

    {:noreply, socket}
  end

  def handle_event("generate", %{"form" => form_params}, socket) do
    template = form_params["template"] || "custom"
    topic = String.trim(form_params["topic"] || "")

    cond do
      topic == "" ->
        {:noreply, assign(socket, error: "#{topic_label(template)} is required")}

      template == "blockster_of_week" ->
        x_handle = String.trim(form_params["x_handle"] || "")

        if x_handle == "" do
          {:noreply, assign(socket, error: "X/Twitter handle is required for Blockster of the Week")}
        else
          # First fetch X profile data, then generate
          socket =
            socket
            |> assign(fetching_x: true, generating: false, error: nil, form: form_params)
            |> start_async(:fetch_x_profile, fn -> XProfileFetcher.fetch_profile_data(x_handle) end)

          {:noreply, socket}
        end

      template == "event_preview" ->
        instructions = String.trim(form_params["instructions"] || "")

        params = %{
          topic: topic,
          category: "events",
          instructions: instructions,
          content_type: "news",
          template: "event_preview",
          event_dates: String.trim(form_params["event_dates"] || ""),
          event_url: String.trim(form_params["event_url"] || ""),
          event_location: String.trim(form_params["event_location"] || "")
        }

        socket =
          socket
          |> assign(generating: true, error: nil, form: form_params)
          |> start_async(:generate, fn -> ContentGenerator.generate_on_demand(params) end)

        {:noreply, socket}

      template == "weekly_roundup" ->
        instructions = String.trim(form_params["instructions"] || "")

        if instructions == "" do
          {:noreply, assign(socket, error: "Event data is required. Switch to this template to auto-populate, or add event details manually.")}
        else
          params = %{
            topic: "What's Coming This Week in Crypto — #{format_week_range()}",
            category: "events",
            instructions: instructions,
            content_type: "news",
            template: "weekly_roundup"
          }

          socket =
            socket
            |> assign(generating: true, error: nil, form: form_params)
            |> start_async(:generate, fn -> ContentGenerator.generate_on_demand(params) end)

          {:noreply, socket}
        end

      template == "market_movers" ->
        instructions = String.trim(form_params["instructions"] || "")

        if instructions == "" do
          {:noreply, assign(socket, error: "Market data is required. Switch to this template to auto-populate, or add market data manually.")}
        else
          params = %{
            topic: "This Week's Biggest Altcoin Moves — #{format_date_range()}",
            category: "altcoins",
            instructions: instructions,
            content_type: "news",
            template: "market_movers"
          }

          socket =
            socket
            |> assign(generating: true, error: nil, form: form_params)
            |> start_async(:generate, fn -> ContentGenerator.generate_on_demand(params) end)

          {:noreply, socket}
        end

      template == "narrative_analysis" ->
        instructions = String.trim(form_params["instructions"] || "")
        sector = form_params["sector"] || "ai"

        if instructions == "" do
          {:noreply, assign(socket, error: "Sector data is required. Switch to this template to auto-populate.")}
        else
          sector_data = AltcoinAnalyzer.get_sector_data(sector)

          params = %{
            topic: "The #{String.capitalize(sector)} Sector Analysis — #{Calendar.strftime(Date.utc_today(), "%B %Y")}",
            category: "altcoins",
            instructions: instructions,
            content_type: "opinion",
            template: "narrative_analysis",
            sector: sector,
            sector_data: sector_data
          }

          socket =
            socket
            |> assign(generating: true, error: nil, form: form_params)
            |> start_async(:generate, fn -> ContentGenerator.generate_on_demand(params) end)

          {:noreply, socket}
        end

      true ->
        instructions = String.trim(form_params["instructions"] || "")

        if instructions == "" do
          {:noreply, assign(socket, error: "Instructions/details are required")}
        else
          params = %{
            topic: topic,
            category: form_params["category"] || "defi",
            instructions: instructions,
            angle: form_params["angle"],
            content_type: form_params["content_type"] || "opinion"
          }

          socket =
            socket
            |> assign(generating: true, error: nil, form: form_params)
            |> start_async(:generate, fn -> ContentGenerator.generate_on_demand(params) end)

          {:noreply, socket}
        end
    end
  end

  # Handle X profile fetch completion
  @impl true
  def handle_async(:fetch_x_profile, {:ok, {:ok, profile_data}}, socket) do
    form = socket.assigns.form
    role = String.trim(form["role"] || "")
    admin_instructions = String.trim(form["instructions"] || "")

    params = %{
      topic: String.trim(form["topic"]),
      category: "blockster_of_week",
      instructions: admin_instructions,
      content_type: "opinion",
      template: "blockster_of_week",
      x_posts_data: profile_data.prompt_text,
      embed_tweets: profile_data.embed_tweets,
      role: role
    }

    socket =
      socket
      |> assign(fetching_x: false, generating: true)
      |> start_async(:generate, fn -> ContentGenerator.generate_on_demand(params) end)

    {:noreply, socket}
  end

  def handle_async(:fetch_x_profile, {:ok, {:error, :no_brand_token}}, socket) do
    {:noreply,
     socket
     |> assign(fetching_x: false, error: "No brand X connection configured. Set BRAND_X_USER_ID and connect the brand's X account.")}
  end

  def handle_async(:fetch_x_profile, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(fetching_x: false, error: "Failed to fetch X profile: #{inspect(reason)}")}
  end

  def handle_async(:fetch_x_profile, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(fetching_x: false, error: "X profile fetch crashed: #{inspect(reason)}")}
  end

  @impl true
  def handle_async(:generate, {:ok, {:ok, entry}}, socket) do
    {:noreply,
     socket
     |> assign(generating: false)
     |> put_flash(:info, "Article generated: \"#{entry.article_data["title"]}\"")
     |> push_navigate(to: ~p"/admin/content/queue/#{entry.id}/edit")}
  end

  def handle_async(:generate, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(generating: false, error: "Generation failed: #{inspect(reason)}")}
  end

  def handle_async(:generate, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(generating: false, error: "Generation crashed: #{inspect(reason)}")}
  end

  # Handle event data fetch for weekly roundup auto-population
  @impl true
  def handle_async(:fetch_events, {:ok, events}, socket) do
    formatted = if events != [] do
      EventRoundup.format_events_for_prompt(events)
    else
      ""
    end

    form = Map.put(socket.assigns.form, "instructions", formatted)
    {:noreply, assign(socket, form: form, fetching_events: false)}
  end

  def handle_async(:fetch_events, {:exit, _reason}, socket) do
    {:noreply, assign(socket, fetching_events: false)}
  end

  # Handle market data fetch for market_movers auto-population
  @impl true
  def handle_async(:fetch_market_data, {:ok, formatted_data}, socket) do
    form = Map.put(socket.assigns.form, "instructions", formatted_data)
    {:noreply, assign(socket, form: form, fetching_market_data: false)}
  end

  def handle_async(:fetch_market_data, {:exit, _reason}, socket) do
    {:noreply, assign(socket, fetching_market_data: false)}
  end

  # Handle sector data fetch for narrative_analysis auto-population
  @impl true
  def handle_async(:fetch_sector_data, {:ok, formatted_data}, socket) do
    form = Map.put(socket.assigns.form, "instructions", formatted_data)
    {:noreply, assign(socket, form: form, fetching_market_data: false)}
  end

  def handle_async(:fetch_sector_data, {:exit, _reason}, socket) do
    {:noreply, assign(socket, fetching_market_data: false)}
  end

  defp topic_label("blockster_of_week"), do: "Person's Name"
  defp topic_label("event_preview"), do: "Event Name"
  defp topic_label("weekly_roundup"), do: "Topic / Headline"
  defp topic_label("market_movers"), do: "Topic / Headline"
  defp topic_label("narrative_analysis"), do: "Topic / Headline"
  defp topic_label(_), do: "Topic / Headline"

  defp is_blockster?(form), do: form["template"] == "blockster_of_week"
  defp is_event_preview?(form), do: form["template"] == "event_preview"
  defp is_weekly_roundup?(form), do: form["template"] == "weekly_roundup"
  defp is_market_movers?(form), do: form["template"] == "market_movers"
  defp is_narrative_analysis?(form), do: form["template"] == "narrative_analysis"
  defp is_event_template?(form), do: is_event_preview?(form) || is_weekly_roundup?(form)
  defp is_market_template?(form), do: is_market_movers?(form) || is_narrative_analysis?(form)

  defp format_week_range do
    today = Date.utc_today()
    week_end = Date.add(today, 7)
    "#{Calendar.strftime(today, "%B %d")} — #{Calendar.strftime(week_end, "%B %d, %Y")}"
  end

  defp format_date_range do
    today = Date.utc_today()
    week_start = Date.add(today, -7)
    "#{Calendar.strftime(week_start, "%B %d")} — #{Calendar.strftime(today, "%B %d, %Y")}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pt-24 px-4 md:px-8 max-w-3xl mx-auto pb-8">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-haas_medium_65 text-gray-900">Request Article</h1>
          <p class="text-gray-500 text-sm mt-1">Generate an article on any topic</p>
        </div>
        <.link navigate={~p"/admin/content"} class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200 cursor-pointer">
          &larr; Dashboard
        </.link>
      </div>

      <%= if @error do %>
        <div class="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
          <p class="text-red-700 text-sm"><%= @error %></p>
        </div>
      <% end %>

      <%= if @generating || @fetching_x || @fetching_events || @fetching_market_data do %>
        <div class="bg-white rounded-lg shadow p-12 text-center">
          <div class="inline-block animate-spin rounded-full h-8 w-8 border-4 border-gray-300 border-t-[#CAFC00] mb-4"></div>
          <p class="text-gray-900 font-haas_medium_65">
            <%= cond do %>
              <% @fetching_x -> %>Fetching X profile & tweets...
              <% @fetching_events -> %>Loading upcoming events...
              <% @fetching_market_data -> %>Fetching market data...
              <% true -> %>Generating article...
            <% end %>
          </p>
          <p class="text-gray-500 text-sm mt-2">
            <%= cond do %>
              <% @fetching_x -> %>Pulling recent posts from X
              <% @fetching_events -> %>Collecting events from all sources
              <% @fetching_market_data -> %>Loading CoinGecko data and recent news
              <% true -> %>This typically takes 30-60 seconds
            <% end %>
          </p>
        </div>
      <% else %>
        <form phx-submit="generate" phx-change="validate" class="space-y-6">
          <%!-- Template Selector --%>
          <div class="bg-white rounded-lg shadow p-6">
            <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">Content Template</label>
            <select
              name="form[template]"
              class="w-full bg-gray-50 border border-gray-300 text-gray-700 rounded-lg px-3 py-3 text-sm cursor-pointer"
            >
              <option value="custom" selected={@form["template"] == "custom"}>Custom Article</option>
              <option value="blockster_of_week" selected={@form["template"] == "blockster_of_week"}>Blockster of the Week</option>
              <option value="event_preview" selected={@form["template"] == "event_preview"}>Event Preview</option>
              <option value="weekly_roundup" selected={@form["template"] == "weekly_roundup"}>Weekly Roundup</option>
              <option value="market_movers" selected={@form["template"] == "market_movers"}>Market Analysis</option>
              <option value="narrative_analysis" selected={@form["template"] == "narrative_analysis"}>Narrative Report</option>
            </select>
            <%= cond do %>
              <% is_blockster?(@form) -> %>
                <p class="text-gray-500 text-xs mt-2">
                  Profile a notable crypto figure using their X posts as primary source material.
                  The system will fetch their recent posts and generate a magazine-style profile.
                </p>
              <% is_event_preview?(@form) -> %>
                <p class="text-gray-500 text-xs mt-2">
                  Generate a standalone preview article for a major upcoming event.
                  Category and content type are auto-set to Events / News.
                </p>
              <% is_weekly_roundup?(@form) -> %>
                <p class="text-gray-500 text-xs mt-2">
                  Generate a weekly roundup of upcoming crypto events.
                  Event data is auto-populated from curated events and RSS feeds.
                </p>
              <% is_market_movers?(@form) -> %>
                <p class="text-gray-500 text-xs mt-2">
                  Generate a data-driven analysis of the week's biggest altcoin movers.
                  Market data is auto-populated from CoinGecko. Category and content type are auto-set to Altcoins / News.
                </p>
              <% is_narrative_analysis?(@form) -> %>
                <p class="text-gray-500 text-xs mt-2">
                  Generate a sector rotation analysis when tokens in a sector move together.
                  Select a sector and data will be auto-populated. Category and content type are auto-set to Altcoins / Opinion.
                </p>
              <% true -> %>
            <% end %>
          </div>

          <%!-- Topic / Person's Name / Event Name --%>
          <%= if !is_weekly_roundup?(@form) && !is_market_movers?(@form) do %>
            <div class="bg-white rounded-lg shadow p-6">
              <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
                <%= topic_label(@form["template"]) %> <span class="text-red-500">*</span>
              </label>
              <input
                type="text"
                name="form[topic]"
                value={@form["topic"]}
                placeholder={cond do
                  is_blockster?(@form) -> "e.g., Vitalik Buterin"
                  is_event_preview?(@form) -> "e.g., ETH Denver 2026"
                  true -> "e.g., Aave V3 launches new WETH market with 8% APY"
                end}
                class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
              />
            </div>
          <% end %>

          <%!-- Blockster-specific fields --%>
          <%= if is_blockster?(@form) do %>
            <div class="bg-white rounded-lg shadow p-6 space-y-4">
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
                  X/Twitter Handle <span class="text-red-500">*</span>
                </label>
                <div class="relative">
                  <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">@</span>
                  <input
                    type="text"
                    name="form[x_handle]"
                    value={@form["x_handle"]}
                    placeholder="VitalikButerin"
                    class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg pl-8 pr-4 py-3 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
                  />
                </div>
                <p class="text-gray-500 text-xs mt-1">Their recent X posts will be fetched as primary source material</p>
              </div>
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
                  Role / Title <span class="text-gray-400 text-xs font-normal">(optional)</span>
                </label>
                <input
                  type="text"
                  name="form[role]"
                  value={@form["role"]}
                  placeholder="e.g., Co-founder of Ethereum, Researcher"
                  class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
                />
              </div>
            </div>
          <% end %>

          <%!-- Event Preview-specific fields --%>
          <%= if is_event_preview?(@form) do %>
            <div class="bg-white rounded-lg shadow p-6 space-y-4">
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
                    Event Date(s) <span class="text-gray-400 text-xs font-normal">(optional)</span>
                  </label>
                  <input
                    type="text"
                    name="form[event_dates]"
                    value={@form["event_dates"]}
                    placeholder="e.g., February 27 — March 1, 2026"
                    class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
                  />
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
                    Location <span class="text-gray-400 text-xs font-normal">(optional)</span>
                  </label>
                  <input
                    type="text"
                    name="form[event_location]"
                    value={@form["event_location"]}
                    placeholder="e.g., Denver, Colorado"
                    class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
                  />
                </div>
              </div>
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
                  Event URL <span class="text-gray-400 text-xs font-normal">(optional)</span>
                </label>
                <input
                  type="text"
                  name="form[event_url]"
                  value={@form["event_url"]}
                  placeholder="https://ethdenver.com"
                  class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
                />
              </div>
            </div>
          <% end %>

          <%!-- Sector dropdown for Narrative Report --%>
          <%= if is_narrative_analysis?(@form) do %>
            <div class="bg-white rounded-lg shadow p-6">
              <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
                Sector <span class="text-red-500">*</span>
              </label>
              <select
                name="form[sector]"
                class="w-full bg-gray-50 border border-gray-300 text-gray-700 rounded-lg px-3 py-3 text-sm cursor-pointer"
              >
                <option value="ai" selected={@form["sector"] == "ai"}>AI / Artificial Intelligence</option>
                <option value="defi" selected={@form["sector"] == "defi"}>DeFi</option>
                <option value="l1" selected={@form["sector"] == "l1"}>Layer 1</option>
                <option value="l2" selected={@form["sector"] == "l2"}>Layer 2</option>
                <option value="gaming" selected={@form["sector"] == "gaming"}>Gaming</option>
                <option value="rwa" selected={@form["sector"] == "rwa"}>Real World Assets</option>
                <option value="meme" selected={@form["sector"] == "meme"}>Meme Coins</option>
                <option value="depin" selected={@form["sector"] == "depin"}>DePIN</option>
              </select>
              <p class="text-gray-500 text-xs mt-1">Select a sector to analyze. Changing this will refresh the market data.</p>
            </div>
          <% end %>

          <%!-- Content Type & Category (hidden for blockster, event, and market templates, auto-set) --%>
          <%= if !is_blockster?(@form) && !is_event_template?(@form) && !is_market_template?(@form) do %>
            <div class="bg-white rounded-lg shadow p-6">
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">Content Type</label>
                  <select
                    name="form[content_type]"
                    class="w-full bg-gray-50 border border-gray-300 text-gray-700 rounded-lg px-3 py-3 text-sm cursor-pointer"
                  >
                    <option value="opinion" selected={@form["content_type"] == "opinion"}>Opinion / Editorial</option>
                    <option value="news" selected={@form["content_type"] == "news"}>News (Factual)</option>
                    <option value="offer" selected={@form["content_type"] == "offer"}>Offer / Opportunity</option>
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">Category</label>
                  <select
                    name="form[category]"
                    class="w-full bg-gray-50 border border-gray-300 text-gray-700 rounded-lg px-3 py-3 text-sm cursor-pointer"
                  >
                    <%= for cat <- @categories do %>
                      <option value={cat} selected={@form["category"] == cat}>
                        <%= String.replace(cat, "_", " ") |> String.capitalize() %>
                      </option>
                    <% end %>
                  </select>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Instructions / Research Brief --%>
          <div class="bg-white rounded-lg shadow p-6">
            <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
              <%= cond do %>
                <% is_blockster?(@form) -> %>
                  Research Brief <span class="text-gray-400 text-xs font-normal">(optional — X posts are the primary source)</span>
                <% is_weekly_roundup?(@form) -> %>
                  Event Data <span class="text-red-500">*</span>
                <% is_event_preview?(@form) -> %>
                  Additional Context <span class="text-gray-400 text-xs font-normal">(optional)</span>
                <% is_market_movers?(@form) -> %>
                  Market Data <span class="text-red-500">*</span>
                <% is_narrative_analysis?(@form) -> %>
                  Sector Data <span class="text-red-500">*</span>
                <% true -> %>
                  Key Details & Instructions <span class="text-red-500">*</span>
              <% end %>
            </label>
            <p class="text-gray-500 text-xs mb-3">
              <%= cond do %>
                <% is_blockster?(@form) -> %>
                  Add any specific context, talking points, or background info you want included.
                  The person's X posts will be automatically fetched and used as the main source.
                <% is_weekly_roundup?(@form) -> %>
                  Auto-populated from curated events and RSS feeds. Edit as needed before generating.
                <% is_event_preview?(@form) -> %>
                  Add background info, key speakers, expected announcements, or any context for this event.
                <% is_market_movers?(@form) -> %>
                  Auto-populated with live CoinGecko data and recent news. Edit as needed before generating.
                <% is_narrative_analysis?(@form) -> %>
                  Auto-populated with sector token data. Edit or add context before generating.
                <% true -> %>
                  Provide specific details, data points, URLs, and context. The more detail you give, the better the article.
              <% end %>
            </p>
            <textarea
              name="form[instructions]"
              rows={cond do
                is_blockster?(@form) -> "5"
                is_weekly_roundup?(@form) -> "12"
                is_market_template?(@form) -> "12"
                true -> "8"
              end}
              placeholder={cond do
                is_blockster?(@form) ->
                  "e.g., Focus on their recent work on Ethereum scaling. They gave a keynote at ETHDenver last week. Known for strong opinions on L2 fragmentation."
                is_weekly_roundup?(@form) ->
                  "Event data will be auto-populated when you select this template..."
                is_event_preview?(@form) ->
                  "e.g., Expected to attract 20,000+ attendees. Keynote speakers include...\nLast year's edition saw major announcements from Uniswap and Polygon."
                is_market_movers?(@form) ->
                  "Market data will be auto-populated when you select this template..."
                is_narrative_analysis?(@form) ->
                  "Sector data will be auto-populated when you select this template..."
                true ->
                  "Include specific facts, numbers, URLs, and context...\n\nExample:\n- Aave V3 just opened a WETH lending market on Arbitrum\n- Current APY: ~8.2% for suppliers\n- TVL: $45M in first 24 hours\n- Blog post: https://governance.aave.com/...\n- Risks: Smart contract risk, variable rate"
              end}
              class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
            ><%= @form["instructions"] %></textarea>
          </div>

          <%!-- Angle (optional, custom articles only) --%>
          <%= if !is_blockster?(@form) && !is_event_template?(@form) && !is_market_template?(@form) do %>
            <div class="bg-white rounded-lg shadow p-6">
              <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
                Angle / Perspective <span class="text-gray-400 text-xs font-normal">(optional)</span>
              </label>
              <textarea
                name="form[angle]"
                rows="3"
                placeholder="e.g., Focus on how this competes with traditional savings accounts. Emphasize the risk/reward tradeoff."
                class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:ring-2 focus:ring-gray-400 focus:border-transparent"
              ><%= @form["angle"] %></textarea>
            </div>
          <% end %>

          <%!-- Author (optional) --%>
          <div class="bg-white rounded-lg shadow p-6">
            <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
              Author Persona <span class="text-gray-400 text-xs font-normal">(optional — auto-selects by category)</span>
            </label>
            <select
              name="form[author]"
              class="w-full bg-gray-50 border border-gray-300 text-gray-700 rounded-lg px-3 py-3 text-sm cursor-pointer"
            >
              <option value="">Auto-select by category</option>
              <%= for author <- @authors do %>
                <option value={author} selected={@form["author"] == author}>
                  <%= author %>
                </option>
              <% end %>
            </select>
          </div>

          <%!-- Hidden fields for template auto-set values --%>
          <%= if is_blockster?(@form) do %>
            <input type="hidden" name="form[category]" value="blockster_of_week" />
            <input type="hidden" name="form[content_type]" value="opinion" />
          <% end %>
          <%= if is_event_template?(@form) do %>
            <input type="hidden" name="form[category]" value="events" />
            <input type="hidden" name="form[content_type]" value="news" />
          <% end %>
          <%!-- Weekly roundup needs a topic auto-generated --%>
          <%= if is_weekly_roundup?(@form) do %>
            <input type="hidden" name="form[topic]" value="weekly_roundup" />
          <% end %>
          <%!-- Market movers needs a topic auto-generated --%>
          <%= if is_market_movers?(@form) do %>
            <input type="hidden" name="form[topic]" value="market_movers" />
          <% end %>
          <%= if is_market_template?(@form) do %>
            <input type="hidden" name="form[category]" value="altcoins" />
            <input type="hidden" name="form[content_type]" value={if is_market_movers?(@form), do: "news", else: "opinion"} />
          <% end %>

          <%!-- Submit --%>
          <div class="flex justify-end">
            <button
              type="submit"
              class="px-6 py-3 bg-gray-900 text-white rounded-lg text-sm font-haas_medium_65 cursor-pointer hover:bg-gray-800"
            >
              <%= cond do %>
                <% is_blockster?(@form) -> %>Generate Profile
                <% is_event_preview?(@form) -> %>Generate Event Preview
                <% is_weekly_roundup?(@form) -> %>Generate Weekly Roundup
                <% is_market_movers?(@form) -> %>Generate Market Analysis
                <% is_narrative_analysis?(@form) -> %>Generate Narrative Report
                <% true -> %>Generate Article
              <% end %>
            </button>
          </div>
        </form>
      <% end %>
    </div>
    """
  end
end
