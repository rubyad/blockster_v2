defmodule BlocksterV2Web.AdsAdminLive.CampaignNew do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.AdsManager.CampaignManager

  @steps ["basics", "targeting", "creatives", "budget", "review"]

  @impl true
  def mount(_params, _session, socket) do
    accounts = CampaignManager.list_accounts()

    {:ok,
     socket
     |> assign(:page_title, "New Ad Campaign")
     |> assign(:step, "basics")
     |> assign(:steps, @steps)
     |> assign(:accounts, accounts)
     |> assign(:saving, false)
     |> assign(:form_data, %{
       "name" => "",
       "platform" => "x",
       "objective" => "traffic",
       "content_type" => "general",
       "content_id" => "",
       "account_id" => "",
       "admin_notes" => "",
       "budget_daily" => "10.00",
       "budget_lifetime" => "",
       "scheduled_start" => "",
       "scheduled_end" => "",
       "targeting_geo" => "",
       "targeting_interests" => "",
       "targeting_age_min" => "18",
       "targeting_age_max" => "65",
       "targeting_gender" => "all"
     })
     |> assign(:creatives, [default_creative()])
     |> assign(:creative_counter, 1)}
  end

  @impl true
  def handle_event("set_step", %{"step" => step}, socket) when step in @steps do
    {:noreply, assign(socket, :step, step)}
  end

  def handle_event("next_step", _params, socket) do
    current_idx = Enum.find_index(@steps, &(&1 == socket.assigns.step))
    next_step = Enum.at(@steps, current_idx + 1, socket.assigns.step)
    {:noreply, assign(socket, :step, next_step)}
  end

  def handle_event("prev_step", _params, socket) do
    current_idx = Enum.find_index(@steps, &(&1 == socket.assigns.step))
    prev_step = Enum.at(@steps, max(current_idx - 1, 0), socket.assigns.step)
    {:noreply, assign(socket, :step, prev_step)}
  end

  def handle_event("update_form", params, socket) do
    form_data = Map.merge(socket.assigns.form_data, sanitize_params(params))
    {:noreply, assign(socket, :form_data, form_data)}
  end

  def handle_event("add_creative", _params, socket) do
    counter = socket.assigns.creative_counter + 1
    creatives = socket.assigns.creatives ++ [default_creative(counter)]
    {:noreply, socket |> assign(:creatives, creatives) |> assign(:creative_counter, counter)}
  end

  def handle_event("remove_creative", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    creatives = List.delete_at(socket.assigns.creatives, idx)
    creatives = if creatives == [], do: [default_creative()], else: creatives
    {:noreply, assign(socket, :creatives, creatives)}
  end

  def handle_event("update_creative", %{"idx" => idx_str} = params, socket) do
    idx = String.to_integer(idx_str)
    creative = Enum.at(socket.assigns.creatives, idx, %{})
    updated = Map.merge(creative, Map.drop(params, ["idx"]))
    creatives = List.replace_at(socket.assigns.creatives, idx, updated)
    {:noreply, assign(socket, :creatives, creatives)}
  end

  def handle_event("create_campaign", _params, socket) do
    form = socket.assigns.form_data

    targeting_config = %{
      geo: parse_csv(form["targeting_geo"]),
      interests: parse_csv(form["targeting_interests"]),
      age_min: parse_int(form["targeting_age_min"]),
      age_max: parse_int(form["targeting_age_max"]),
      gender: form["targeting_gender"]
    }

    account_id = case form["account_id"] do
      "" -> nil
      id -> String.to_integer(id)
    end

    attrs = %{
      name: form["name"],
      platform: form["platform"],
      objective: form["objective"],
      content_type: form["content_type"],
      content_id: parse_int_or_nil(form["content_id"]),
      account_id: account_id,
      budget_daily: parse_decimal(form["budget_daily"]),
      budget_lifetime: parse_decimal(form["budget_lifetime"]),
      targeting_config: targeting_config,
      admin_notes: form["admin_notes"],
      scheduled_start: parse_datetime(form["scheduled_start"]),
      scheduled_end: parse_datetime(form["scheduled_end"])
    }

    case CampaignManager.create_from_admin(attrs, socket.assigns.current_user.id) do
      {:ok, campaign} ->
        # Add creatives
        Enum.each(socket.assigns.creatives, fn creative ->
          if creative["headline"] != "" || creative["body"] != "" do
            CampaignManager.add_creative(campaign, %{
              platform: form["platform"],
              type: creative["type"] || "image",
              headline: creative["headline"],
              body: creative["body"],
              cta_text: creative["cta_text"],
              image_url: creative["image_url"],
              video_url: creative["video_url"],
              hashtags: parse_csv(creative["hashtags"]),
              source: "admin",
              admin_override: true
            })
          end
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Campaign created successfully")
         |> push_navigate(to: ~p"/admin/ads/campaigns")}

      {:error, changeset} ->
        errors = format_errors(changeset)
        {:noreply, put_flash(socket, :error, "Failed to create campaign: #{errors}")}
    end
  end

  defp default_creative(n \\ 1) do
    %{
      "id" => n,
      "type" => "image",
      "headline" => "",
      "body" => "",
      "cta_text" => "Learn More",
      "image_url" => "",
      "video_url" => "",
      "hashtags" => ""
    }
  end

  defp sanitize_params(params) do
    params
    |> Map.drop(["_target", "_csrf_token"])
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp parse_csv(nil), do: []
  defp parse_csv(""), do: []
  defp parse_csv(str), do: str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(str) when is_binary(str), do: String.to_integer(str)
  defp parse_int(n), do: n

  defp parse_int_or_nil(nil), do: nil
  defp parse_int_or_nil(""), do: nil
  defp parse_int_or_nil(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil
  defp parse_decimal(str) when is_binary(str), do: Decimal.new(str)

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil
  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str <> ":00Z") do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 pt-24 pb-12">
        <%!-- Header --%>
        <div class="flex items-center gap-4 mb-8">
          <.link navigate={~p"/admin/ads/campaigns"} class="w-10 h-10 bg-white rounded-xl flex items-center justify-center shadow-sm border border-gray-100 hover:bg-gray-50 cursor-pointer">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-600" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" /></svg>
          </.link>
          <h1 class="text-2xl font-haas_medium_65 text-[#141414]">New Ad Campaign</h1>
        </div>

        <%!-- Step Navigation --%>
        <div class="flex items-center gap-2 mb-8">
          <%= for {step, idx} <- Enum.with_index(@steps) do %>
            <button
              phx-click="set_step"
              phx-value-step={step}
              class={"flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-haas_medium_65 cursor-pointer transition-colors #{if @step == step, do: "bg-gray-900 text-white", else: "bg-white text-gray-600 border border-gray-200 hover:bg-gray-50"}"}
            >
              <span class="w-5 h-5 rounded-full flex items-center justify-center text-xs bg-white/20"><%= idx + 1 %></span>
              <%= String.capitalize(step) %>
            </button>
          <% end %>
        </div>

        <form phx-change="update_form" phx-submit="create_campaign">
          <%!-- Step 1: Basics --%>
          <div class={if @step != "basics", do: "hidden"}>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 space-y-5">
              <h2 class="text-lg font-haas_medium_65 text-[#141414]">Campaign Basics</h2>

              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Campaign Name</label>
                <input type="text" name="name" value={@form_data["name"]} placeholder="e.g. Q1 X Traffic Push" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Platform</label>
                  <select name="platform" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
                    <option value="x" selected={@form_data["platform"] == "x"}>X (Twitter)</option>
                    <option value="meta" selected={@form_data["platform"] == "meta"}>Meta (Facebook/Instagram)</option>
                    <option value="tiktok" selected={@form_data["platform"] == "tiktok"}>TikTok</option>
                    <option value="telegram" selected={@form_data["platform"] == "telegram"}>Telegram</option>
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Objective</label>
                  <select name="objective" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
                    <option value="traffic" selected={@form_data["objective"] == "traffic"}>Traffic</option>
                    <option value="signups" selected={@form_data["objective"] == "signups"}>Signups</option>
                    <option value="purchases" selected={@form_data["objective"] == "purchases"}>Purchases</option>
                    <option value="engagement" selected={@form_data["objective"] == "engagement"}>Engagement</option>
                  </select>
                </div>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Content Type</label>
                  <select name="content_type" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
                    <option value="general" selected={@form_data["content_type"] == "general"}>General</option>
                    <option value="post" selected={@form_data["content_type"] == "post"}>Blog Post</option>
                    <option value="product" selected={@form_data["content_type"] == "product"}>Shop Product</option>
                    <option value="game" selected={@form_data["content_type"] == "game"}>BUX Booster</option>
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Content ID <span class="text-gray-400 text-xs">(optional)</span></label>
                  <input type="text" name="content_id" value={@form_data["content_id"]} placeholder="Post or product ID" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
              </div>

              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Platform Account</label>
                <select name="account_id" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
                  <option value="">Auto-select</option>
                  <%= for account <- @accounts do %>
                    <option value={account.id} selected={@form_data["account_id"] == to_string(account.id)}>
                      <%= String.capitalize(account.platform) %> — <%= account.account_name %>
                    </option>
                  <% end %>
                </select>
              </div>

              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Admin Notes <span class="text-gray-400 text-xs">(optional)</span></label>
                <textarea name="admin_notes" rows="2" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="Internal notes about this campaign..."><%= @form_data["admin_notes"] %></textarea>
              </div>

              <div class="flex justify-end">
                <button type="button" phx-click="next_step" class="px-6 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">
                  Next: Targeting →
                </button>
              </div>
            </div>
          </div>

          <%!-- Step 2: Targeting --%>
          <div class={if @step != "targeting", do: "hidden"}>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 space-y-5">
              <h2 class="text-lg font-haas_medium_65 text-[#141414]">Targeting</h2>

              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Geo Targeting <span class="text-gray-400 text-xs">(comma-separated country codes)</span></label>
                <input type="text" name="targeting_geo" value={@form_data["targeting_geo"]} placeholder="e.g. US, CA, GB, AU" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
              </div>

              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Interests <span class="text-gray-400 text-xs">(comma-separated)</span></label>
                <input type="text" name="targeting_interests" value={@form_data["targeting_interests"]} placeholder="e.g. crypto, blockchain, defi, web3, gaming" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
              </div>

              <div class="grid grid-cols-3 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Min Age</label>
                  <input type="number" name="targeting_age_min" value={@form_data["targeting_age_min"]} min="13" max="65" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Max Age</label>
                  <input type="number" name="targeting_age_max" value={@form_data["targeting_age_max"]} min="13" max="65" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Gender</label>
                  <select name="targeting_gender" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
                    <option value="all" selected={@form_data["targeting_gender"] == "all"}>All</option>
                    <option value="male" selected={@form_data["targeting_gender"] == "male"}>Male</option>
                    <option value="female" selected={@form_data["targeting_gender"] == "female"}>Female</option>
                  </select>
                </div>
              </div>

              <div class="flex justify-between">
                <button type="button" phx-click="prev_step" class="px-6 py-2.5 bg-[#F5F6FB] rounded-xl text-sm font-haas_medium_65 text-gray-700 hover:bg-gray-200 cursor-pointer">
                  ← Back
                </button>
                <button type="button" phx-click="next_step" class="px-6 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">
                  Next: Creatives →
                </button>
              </div>
            </div>
          </div>

          <%!-- Step 3: Creatives --%>
          <div class={if @step != "creatives", do: "hidden"}>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 space-y-5">
              <div class="flex items-center justify-between">
                <h2 class="text-lg font-haas_medium_65 text-[#141414]">Creatives</h2>
                <button type="button" phx-click="add_creative" class="px-4 py-2 bg-[#F5F6FB] rounded-xl text-sm font-haas_medium_65 text-gray-700 hover:bg-gray-200 cursor-pointer">
                  + Add Variant
                </button>
              </div>

              <p class="text-xs text-gray-500 font-haas_roman_55">Add one or more creative variants. Multiple variants will be A/B tested automatically.</p>

              <%= for {creative, idx} <- Enum.with_index(@creatives) do %>
                <div class="p-4 bg-[#F5F6FB] rounded-xl space-y-4">
                  <div class="flex items-center justify-between">
                    <span class="text-sm font-haas_medium_65 text-gray-700">Variant <%= idx + 1 %></span>
                    <%= if length(@creatives) > 1 do %>
                      <button type="button" phx-click="remove_creative" phx-value-idx={idx} class="text-xs text-red-500 hover:text-red-700 cursor-pointer font-haas_medium_65">Remove</button>
                    <% end %>
                  </div>

                  <div>
                    <label class="block text-xs font-haas_medium_65 text-gray-600 mb-1">Type</label>
                    <select phx-change="update_creative" phx-value-idx={idx} name="type" class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
                      <option value="image" selected={creative["type"] == "image"}>Image</option>
                      <option value="video" selected={creative["type"] == "video"}>Video</option>
                      <option value="carousel" selected={creative["type"] == "carousel"}>Carousel</option>
                      <option value="text" selected={creative["type"] == "text"}>Text Only</option>
                    </select>
                  </div>

                  <div>
                    <label class="block text-xs font-haas_medium_65 text-gray-600 mb-1">Headline</label>
                    <input type="text" phx-change="update_creative" phx-value-idx={idx} name="headline" value={creative["headline"]} placeholder="Ad headline" class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                  </div>

                  <div>
                    <label class="block text-xs font-haas_medium_65 text-gray-600 mb-1">Body Copy</label>
                    <textarea phx-change="update_creative" phx-value-idx={idx} name="body" rows="3" class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="Ad body text..."><%= creative["body"] %></textarea>
                  </div>

                  <div class="grid grid-cols-2 gap-3">
                    <div>
                      <label class="block text-xs font-haas_medium_65 text-gray-600 mb-1">CTA Text</label>
                      <input type="text" phx-change="update_creative" phx-value-idx={idx} name="cta_text" value={creative["cta_text"]} class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                    </div>
                    <div>
                      <label class="block text-xs font-haas_medium_65 text-gray-600 mb-1">Hashtags <span class="text-gray-400">(comma-separated)</span></label>
                      <input type="text" phx-change="update_creative" phx-value-idx={idx} name="hashtags" value={creative["hashtags"]} placeholder="#crypto, #web3" class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                    </div>
                  </div>

                  <%= if creative["type"] in ["image", "carousel"] do %>
                    <div>
                      <label class="block text-xs font-haas_medium_65 text-gray-600 mb-1">Image URL</label>
                      <input type="text" phx-change="update_creative" phx-value-idx={idx} name="image_url" value={creative["image_url"]} placeholder="https://ik.imagekit.io/blockster/..." class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                    </div>
                  <% end %>

                  <%= if creative["type"] == "video" do %>
                    <div>
                      <label class="block text-xs font-haas_medium_65 text-gray-600 mb-1">Video URL</label>
                      <input type="text" phx-change="update_creative" phx-value-idx={idx} name="video_url" value={creative["video_url"]} placeholder="https://..." class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                    </div>
                  <% end %>
                </div>
              <% end %>

              <div class="flex justify-between">
                <button type="button" phx-click="prev_step" class="px-6 py-2.5 bg-[#F5F6FB] rounded-xl text-sm font-haas_medium_65 text-gray-700 hover:bg-gray-200 cursor-pointer">
                  ← Back
                </button>
                <button type="button" phx-click="next_step" class="px-6 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">
                  Next: Budget →
                </button>
              </div>
            </div>
          </div>

          <%!-- Step 4: Budget --%>
          <div class={if @step != "budget", do: "hidden"}>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 space-y-5">
              <h2 class="text-lg font-haas_medium_65 text-[#141414]">Budget & Schedule</h2>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Daily Budget (USD)</label>
                  <input type="text" name="budget_daily" value={@form_data["budget_daily"]} placeholder="10.00" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Lifetime Budget <span class="text-gray-400 text-xs">(optional)</span></label>
                  <input type="text" name="budget_lifetime" value={@form_data["budget_lifetime"]} placeholder="500.00" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Start Date <span class="text-gray-400 text-xs">(optional)</span></label>
                  <input type="datetime-local" name="scheduled_start" value={@form_data["scheduled_start"]} class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">End Date <span class="text-gray-400 text-xs">(optional)</span></label>
                  <input type="datetime-local" name="scheduled_end" value={@form_data["scheduled_end"]} class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
              </div>

              <div class="flex justify-between">
                <button type="button" phx-click="prev_step" class="px-6 py-2.5 bg-[#F5F6FB] rounded-xl text-sm font-haas_medium_65 text-gray-700 hover:bg-gray-200 cursor-pointer">
                  ← Back
                </button>
                <button type="button" phx-click="next_step" class="px-6 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">
                  Next: Review →
                </button>
              </div>
            </div>
          </div>

          <%!-- Step 5: Review --%>
          <div class={if @step != "review", do: "hidden"}>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 space-y-5">
              <h2 class="text-lg font-haas_medium_65 text-[#141414]">Review Campaign</h2>

              <div class="grid grid-cols-2 gap-4">
                <div class="p-4 bg-[#F5F6FB] rounded-xl">
                  <div class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider mb-1">Campaign</div>
                  <div class="text-sm font-haas_medium_65 text-[#141414]"><%= @form_data["name"] || "—" %></div>
                </div>
                <div class="p-4 bg-[#F5F6FB] rounded-xl">
                  <div class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider mb-1">Platform</div>
                  <div class="text-sm font-haas_medium_65 text-[#141414]"><%= platform_label(@form_data["platform"]) %></div>
                </div>
                <div class="p-4 bg-[#F5F6FB] rounded-xl">
                  <div class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider mb-1">Objective</div>
                  <div class="text-sm font-haas_medium_65 text-[#141414]"><%= String.capitalize(@form_data["objective"] || "—") %></div>
                </div>
                <div class="p-4 bg-[#F5F6FB] rounded-xl">
                  <div class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider mb-1">Daily Budget</div>
                  <div class="text-sm font-haas_medium_65 text-[#141414]">$<%= @form_data["budget_daily"] || "0" %>/day</div>
                </div>
              </div>

              <div class="p-4 bg-[#F5F6FB] rounded-xl">
                <div class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider mb-2">Targeting</div>
                <div class="text-sm font-haas_roman_55 text-gray-700 space-y-1">
                  <%= if @form_data["targeting_geo"] != "" do %>
                    <div>Geo: <%= @form_data["targeting_geo"] %></div>
                  <% end %>
                  <%= if @form_data["targeting_interests"] != "" do %>
                    <div>Interests: <%= @form_data["targeting_interests"] %></div>
                  <% end %>
                  <div>Age: <%= @form_data["targeting_age_min"] %>–<%= @form_data["targeting_age_max"] %>, Gender: <%= @form_data["targeting_gender"] %></div>
                </div>
              </div>

              <div class="p-4 bg-[#F5F6FB] rounded-xl">
                <div class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider mb-2">Creatives (<%= length(@creatives) %> variant<%= if length(@creatives) != 1, do: "s" %>)</div>
                <div class="space-y-2">
                  <%= for {creative, idx} <- Enum.with_index(@creatives) do %>
                    <div class="text-sm font-haas_roman_55 text-gray-700">
                      <span class="font-haas_medium_65">V<%= idx + 1 %>:</span>
                      <%= creative["headline"] || "No headline" %>
                      <span class="text-gray-400">(<%= creative["type"] %>)</span>
                    </div>
                  <% end %>
                </div>
              </div>

              <div class="flex justify-between">
                <button type="button" phx-click="prev_step" class="px-6 py-2.5 bg-[#F5F6FB] rounded-xl text-sm font-haas_medium_65 text-gray-700 hover:bg-gray-200 cursor-pointer">
                  ← Back
                </button>
                <button type="submit" class="px-8 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">
                  Create Campaign
                </button>
              </div>
            </div>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp platform_label("x"), do: "X (Twitter)"
  defp platform_label("meta"), do: "Meta (Facebook/Instagram)"
  defp platform_label("tiktok"), do: "TikTok"
  defp platform_label("telegram"), do: "Telegram"
  defp platform_label(p), do: p
end
