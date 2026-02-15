defmodule BlocksterV2Web.ContentAutomationLive.RequestArticle do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.{AuthorRotator, ContentGenerator}

  @categories ~w(defi rwa regulation gaming trading token_launches gambling privacy macro_trends investment bitcoin ethereum altcoins nft ai_crypto stablecoins cbdc security_hacks adoption mining fundraising events)

  @impl true
  def mount(_params, _session, socket) do
    authors = AuthorRotator.personas() |> Enum.map(& &1.username) |> Enum.sort()

    {:ok,
     assign(socket,
       page_title: "Request Article",
       categories: @categories,
       authors: authors,
       form: %{
         "topic" => "",
         "category" => "defi",
         "instructions" => "",
         "angle" => "",
         "author" => "",
         "content_type" => "opinion"
       },
       generating: false,
       error: nil
     )}
  end

  @impl true
  def handle_event("validate", %{"form" => form_params}, socket) do
    {:noreply, assign(socket, form: form_params)}
  end

  def handle_event("generate", %{"form" => form_params}, socket) do
    topic = String.trim(form_params["topic"] || "")
    instructions = String.trim(form_params["instructions"] || "")

    cond do
      topic == "" ->
        {:noreply, assign(socket, error: "Topic is required")}

      instructions == "" ->
        {:noreply, assign(socket, error: "Instructions/details are required")}

      true ->
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

      <%= if @generating do %>
        <div class="bg-white rounded-lg shadow p-12 text-center">
          <div class="inline-block animate-spin rounded-full h-8 w-8 border-4 border-gray-300 border-t-[#CAFC00] mb-4"></div>
          <p class="text-gray-900 font-haas_medium_65">Generating article...</p>
          <p class="text-gray-500 text-sm mt-2">This typically takes 30-60 seconds</p>
        </div>
      <% else %>
        <form phx-submit="generate" phx-change="validate" class="space-y-6">
          <%!-- Topic --%>
          <div class="bg-white rounded-lg shadow p-6">
            <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
              Topic / Headline <span class="text-red-500">*</span>
            </label>
            <input
              type="text"
              name="form[topic]"
              value={@form["topic"]}
              placeholder="e.g., Aave V3 launches new WETH market with 8% APY"
              class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:ring-2 focus:ring-[#CAFC00] focus:border-transparent"
            />
          </div>

          <%!-- Content Type & Category --%>
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

          <%!-- Instructions --%>
          <div class="bg-white rounded-lg shadow p-6">
            <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
              Key Details & Instructions <span class="text-red-500">*</span>
            </label>
            <p class="text-gray-500 text-xs mb-3">
              Provide specific details, data points, URLs, and context. The more detail you give, the better the article.
            </p>
            <textarea
              name="form[instructions]"
              rows="8"
              placeholder={"Include specific facts, numbers, URLs, and context...\n\nExample:\n- Aave V3 just opened a WETH lending market on Arbitrum\n- Current APY: ~8.2% for suppliers\n- TVL: $45M in first 24 hours\n- Blog post: https://governance.aave.com/...\n- Risks: Smart contract risk, variable rate"}
              class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:ring-2 focus:ring-[#CAFC00] focus:border-transparent"
            ><%= @form["instructions"] %></textarea>
          </div>

          <%!-- Angle (optional) --%>
          <div class="bg-white rounded-lg shadow p-6">
            <label class="block text-sm font-haas_medium_65 text-gray-900 mb-2">
              Angle / Perspective <span class="text-gray-400 text-xs font-normal">(optional)</span>
            </label>
            <textarea
              name="form[angle]"
              rows="3"
              placeholder="e.g., Focus on how this competes with traditional savings accounts. Emphasize the risk/reward tradeoff."
              class="w-full bg-gray-50 border border-gray-300 text-gray-900 rounded-lg px-4 py-3 text-sm focus:ring-2 focus:ring-[#CAFC00] focus:border-transparent"
            ><%= @form["angle"] %></textarea>
          </div>

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

          <%!-- Submit --%>
          <div class="flex justify-end">
            <button
              type="submit"
              class="px-6 py-3 bg-[#CAFC00] text-black rounded-lg text-sm font-haas_medium_65 cursor-pointer hover:bg-[#b8e600]"
            >
              Generate Article
            </button>
          </div>
        </form>
      <% end %>
    </div>
    """
  end
end
