defmodule BlocksterV2Web.MediaKitLive do
  use BlocksterV2Web, :live_view

  @initial_visible_interviews 9

  # Logo resolution: explicit `logo:` (Blockster hub image) takes priority;
  # otherwise the template falls back to Clearbit → Google favicons using `domain:`.
  @interviews [
    %{id: "ttUn6LpGlmI", brand: "Human Tech", guest: "Shady El Damaty", date: "10 Apr 2026", domain: "human.tech"},
    %{id: "twr5wQk8tmU", brand: "Fateswap", guest: "Adam Todd", date: "2 Apr 2026", domain: "fateswap.io", logo: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/1774451194-487c8e3c22eefd84.jpg"},
    %{id: "E0rB45j_EgA", brand: "Fhenix", guest: "Guy Itzhaki", date: "1 Apr 2026", domain: "fhenix.io"},
    %{id: "4YkWQ--Bvxg", brand: "Pharos Network", guest: "Alex Zhang", date: "31 Mar 2026", domain: "pharosnetwork.xyz"},
    %{id: "toI07PPzeJ0", brand: "Space and Time", guest: "Catherine Daly", date: "30 Mar 2026", domain: "spaceandtime.io", logo: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/1765905747-120152a3ede48c99.jpg"},
    %{id: "t9BQVele1F0", brand: "Huma Tek", guest: "Rahul Ahmed", date: "26 Feb 2026", domain: "huma.finance"},
    %{id: "U6079Qify-k", brand: "Real Fin Official", guest: "Brandon Kazakoff", date: "24 Feb 2026", domain: "realfinance.ai"},
    %{id: "wQgJZvO7B-o", brand: "Midnight", guest: "Fahmi Syed", date: "19 Feb 2026", domain: "midnight.network", logo: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/1771597178-0e31a5956daa5cd6.jpg"},
    %{id: "FUkXB29jTLM", brand: "CertiK", guest: "Angus Lee", date: "17 Feb 2026", domain: "certik.com"},
    %{id: "IDvmkbr4aLg", brand: "Solflare", guest: "Filip Dragoslavic", date: "15 Dec 2025", domain: "solflare.com"},
    %{id: "4HQv0laYbu8", brand: "POPOLOGY", guest: "Joe Rey & Oliver Fuselier", date: "8 Dec 2025", domain: "popology.com"},
    %{id: "RKj4wOzxL3c", brand: "Naoris Protocol", guest: "Youssef El Maddarsi", date: "26 Nov 2025", domain: "naorisprotocol.com"},
    %{id: "AKPVtByCvHU", brand: "EstateX", guest: "Steve Lawrence", date: "13 Oct 2025", domain: "estatex.eu"},
    %{id: "1JSZ1ct520Q", brand: "Bit Layer", guest: "Charlie Hu", date: "10 Oct 2025", domain: "bitlayer.org"},
    %{id: "8zwn_4R1-2s", brand: "Open Ledger", guest: "Ram Kumar", date: "9 Oct 2025", domain: "openledger.xyz"},
    %{id: "22KNDtUC990", brand: "0G Labs", guest: "Michael Heinrich", date: "8 Oct 2025", domain: "0g.ai"},
    %{id: "AV_vH2UaYuY", brand: "Neo Blockchain", guest: "John Wang", date: "7 Oct 2025", domain: "neo.org", logo: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/1765905640-26f230c4be45c8dc.jpg"},
    %{id: "2q2yyTtABfk", brand: "Cartesi", guest: "Felipe Argento", date: "18 Jul 2025", domain: "cartesi.io"},
    %{id: "e5JtNTAK3bo", brand: "Ethical Media Group", guest: "Peter Antico", date: "14 Jul 2025", domain: "ethicalmediagroup.com"},
    %{id: "xN8MS3zzVqs", brand: "Nibiru Chain", guest: "Unique Divine", date: "30 Jun 2025", domain: "nibiru.fi"},
    %{id: "xHC_MgoXt1o", brand: "Datagram", guest: "Jason Brink", date: "13 Jun 2025", domain: "datagram.network"},
    %{id: "meE4wp81roc", brand: "Apex Fusion", guest: "Christopher Greenwood", date: "27 May 2025", domain: "apexfusion.org", logo: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/1770282780-37fa1167dfa2cb5f.jpg"},
    %{id: "KHCi3wvjGGc", brand: "Blocksquare", guest: "Makram Hani", date: "23 May 2025", domain: "blocksquare.io"},
    %{id: "w0M4kh3DgSM", brand: "iExec", guest: "Nathan Chiron", date: "22 May 2025", domain: "iex.ec"},
    %{id: "IawCsAH78mM", brand: "Mercuryo", guest: "Arthur Firstov", date: "20 May 2025", domain: "mercuryo.io"}
  ]

  @brand_assets_zip "https://ik.imagekit.io/blockster/brand/blockster-brand-assets.zip"

  @impl true
  def mount(_params, _session, socket) do
    {visible, hidden} = Enum.split(@interviews, @initial_visible_interviews)

    {:ok,
     socket
     |> assign(:page_title, "Media Kit · Blockster")
     |> assign(:interviews, @interviews)
     |> assign(:visible_interviews, visible)
     |> assign(:hidden_interviews, hidden)
     |> assign(:show_all_interviews, false)
     |> assign(:brand_assets_zip, @brand_assets_zip)}
  end

  @impl true
  def handle_event("show_all_interviews", _params, socket) do
    {:noreply, assign(socket, :show_all_interviews, true)}
  end

  # Prefer a hosted Blockster hub logo when we have one; otherwise Clearbit, with
  # a Google favicon as last-resort fallback via the <img> onerror handler.
  defp interview_logo_src(%{logo: logo}) when is_binary(logo), do: logo
  defp interview_logo_src(%{domain: domain}), do: "https://logo.clearbit.com/#{domain}?size=128"

  defp interview_logo_onerror(%{logo: logo}) when is_binary(logo), do: nil

  defp interview_logo_onerror(%{domain: domain}),
    do: "this.onerror=null;this.src='https://www.google.com/s2/favicons?domain=#{domain}&sz=128'"

  # ── Page-local function components ──────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :sub, :string, default: nil
  attr :tone, :string, default: "neutral"

  def metric_card(assigns) do
    ~H"""
    <div class={[
      "rounded-2xl p-5 shadow-[0_1px_3px_rgba(0,0,0,0.04)] border",
      @tone == "lime" && "bg-[#CAFC00]/20 border-[#CAFC00]/40",
      @tone == "neutral" && "bg-white border-neutral-200/70"
    ]}>
      <div class="text-[10px] font-mono uppercase tracking-[0.14em] text-neutral-500 mb-2">{@label}</div>
      <div class="font-mono text-[26px] md:text-[32px] font-bold tracking-tight text-[#141414] leading-none">{@value}</div>
      <div :if={@sub} class="text-[11px] font-mono text-neutral-500 mt-2">{@sub}</div>
    </div>
    """
  end

  slot :inner_block, required: true

  def region_pill(assigns) do
    ~H"""
    <span class="inline-flex items-center px-2.5 py-1 rounded-full border border-neutral-200 bg-white text-[11px] font-mono text-neutral-600">
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :index, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true
  attr :tone, :string, default: "light"

  def layer_card(assigns) do
    ~H"""
    <div class={[
      "rounded-2xl p-5 md:p-6 border shadow-[0_1px_3px_rgba(0,0,0,0.04)] flex gap-5 items-start",
      @tone == "light" && "bg-white border-neutral-200/70",
      @tone == "dark" && "bg-[#0a0a0a] border-[#0a0a0a] text-white"
    ]}>
      <div class={[
        "font-mono text-[11px] uppercase tracking-[0.16em] shrink-0 pt-1",
        @tone == "light" && "text-neutral-400",
        @tone == "dark" && "text-[#CAFC00]"
      ]}>{@index}</div>
      <div>
        <div class={[
          "text-[17px] md:text-[19px] font-bold tracking-[-0.012em] mb-1.5",
          @tone == "light" && "text-[#141414]",
          @tone == "dark" && "text-white"
        ]}>{@title}</div>
        <p class={[
          "text-[13px] leading-[1.55]",
          @tone == "light" && "text-neutral-600",
          @tone == "dark" && "text-white/60"
        ]}>{@body}</p>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :sub, :string, required: true

  def earn_row(assigns) do
    ~H"""
    <li class="flex items-start gap-3">
      <span class="w-1.5 h-1.5 rounded-full bg-[#CAFC00] mt-2 shrink-0"></span>
      <div>
        <div class="text-[14px] font-bold text-[#141414] leading-tight">{@label}</div>
        <div class="text-[12px] text-neutral-500 mt-0.5 leading-[1.55]">{@sub}</div>
      </div>
    </li>
    """
  end

  attr :preview_bg, :string, required: true
  attr :name, :string, required: true
  attr :desc, :string, required: true
  attr :downloads, :list, required: true
  slot :inner_block, required: true

  def asset_card(assigns) do
    ~H"""
    <article class="bg-white rounded-2xl border border-neutral-200/70 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
      <div class={["min-h-[180px] grid place-items-center p-10", @preview_bg]}>
        {render_slot(@inner_block)}
      </div>
      <div class="p-5 border-t border-neutral-200/70 flex items-center justify-between gap-3 flex-wrap">
        <div>
          <div class="text-[13px] font-bold text-[#141414]">{@name}</div>
          <div class="text-[11px] text-neutral-500 font-mono mt-0.5">{@desc}</div>
        </div>
        <div class="flex items-center gap-1.5 flex-wrap">
          <%= for {label, url} <- @downloads do %>
            <a
              href={url}
              download
              class="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-full border border-neutral-200 bg-white text-[10px] font-mono font-semibold text-neutral-500 hover:bg-[#141414] hover:text-white hover:border-[#141414] transition-colors"
            >{label}</a>
          <% end %>
        </div>
      </div>
    </article>
    """
  end

  attr :interview, :map, required: true

  def interview_card(assigns) do
    ~H"""
    <a
      href={"https://youtu.be/" <> @interview.id}
      target="_blank"
      rel="noopener"
      class="group bg-white rounded-2xl border border-neutral-200/70 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.04)] hover:border-[#141414] transition-colors flex flex-col"
    >
      <div class="relative aspect-video bg-neutral-100 overflow-hidden">
        <img
          src={"https://img.youtube.com/vi/" <> @interview.id <> "/hqdefault.jpg"}
          alt={@interview.brand <> " · " <> @interview.guest}
          class="w-full h-full object-cover group-hover:scale-[1.03] transition-transform duration-500"
          loading="lazy"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-[#0a0a0a]/70 via-transparent to-transparent"></div>
        <div class="absolute bottom-3 left-3 right-3 flex items-center justify-between">
          <span class="inline-flex items-center gap-1.5 bg-white/95 backdrop-blur px-2.5 py-1 rounded-full text-[10px] font-mono font-semibold text-[#141414]">
            <svg class="w-2.5 h-2.5 text-[#FF0033]" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
            Watch interview
          </span>
          <span class="text-[10px] font-mono font-semibold text-white/95 bg-black/35 backdrop-blur px-2 py-1 rounded-full">{@interview.date}</span>
        </div>
      </div>
      <div class="p-4 flex items-center gap-3">
        <div class="min-w-0 flex-1">
          <div class="text-[10px] font-mono uppercase tracking-[0.14em] text-neutral-500 mb-1 truncate">{@interview.brand}</div>
          <div class="text-[15px] font-bold text-[#141414] leading-tight truncate">{@interview.guest}</div>
        </div>
        <img
          src={interview_logo_src(@interview)}
          onerror={interview_logo_onerror(@interview)}
          alt={@interview.brand <> " logo"}
          class="w-10 h-10 object-contain shrink-0"
          loading="lazy"
        />
      </div>
    </a>
    """
  end

  attr :hex, :string, required: true
  attr :name, :string, required: true
  attr :note, :string, required: true
  attr :text_dark, :boolean, default: true

  def color_swatch(assigns) do
    ~H"""
    <div class="rounded-2xl border border-neutral-200/70 overflow-hidden bg-white shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
      <div class="h-24" style={"background-color: #{@hex}"}></div>
      <div class="p-3">
        <div class="text-[13px] font-bold text-[#141414] leading-tight">{@name}</div>
        <div class="font-mono text-[11px] text-neutral-500 mt-0.5">{@hex}</div>
        <div class="text-[10px] text-neutral-400 mt-1">{@note}</div>
      </div>
    </div>
    """
  end
end
