defmodule BlocksterV2Web.DesignPreviewLive do
  @moduledoc """
  Dev-only LiveView that renders every component in
  `BlocksterV2Web.DesignSystem` so the user can eyeball them in the browser
  before any page rebuilds start.

  Mounted at `/dev/design-preview` and only when `:dev_routes` is enabled in
  config (so it never ships to production).
  """

  use BlocksterV2Web, :live_view
  use BlocksterV2Web.DesignSystem

  @impl true
  def mount(_params, _session, socket) do
    # Two fake users so we can render both header variants on the same page.
    fake_user = %{
      username: "marcus",
      wallet_address: "7xQk8mPa3vNb9aBcD2eFgH6jKlMn4qRsTuVwXyZ",
      slug: "marcus",
      is_author: true,
      is_admin: true
    }

    {:ok,
     socket
     |> assign(:page_title, "Design preview · Wave 0")
     |> assign(:fake_user, fake_user), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Design preview · Wave 0</title>

        <%!-- Load the Google Fonts the design system depends on. JetBrains Mono
              is not loaded globally yet (added later when pages start using
              the new components in production), so the preview imports it
              inline. --%>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        <link
          href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />

        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}></script>

        <style>
          :root {
            --bg-page: #fafaf9;
            --text-primary: #141414;
            --text-body: #343434;
            --text-muted: #6b7280;
            --text-faint: #9ca3af;
            --blockster-lime: #cafc00;
          }
          html, body {
            background: var(--bg-page);
            color: var(--text-primary);
            font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif;
            -webkit-font-smoothing: antialiased;
            text-rendering: optimizeLegibility;
          }
          .font-mono {
            font-family: 'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, monospace;
            font-variant-numeric: tabular-nums;
          }

          /* The wordmark — keep these styles in sync with design_system.md */
          .ds-logo {
            font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif;
            font-weight: 800;
            text-transform: uppercase;
            letter-spacing: 0.06em;
            line-height: 1;
            color: #141414;
          }
          .ds-logo--dark { color: #e8e4dd; }
          .ds-logo__o {
            display: inline-block;
            width: 0.78em;
            height: 0.78em;
            object-fit: contain;
            margin: 0 0.04em;
            vertical-align: middle;
            flex-shrink: 0;
          }

          .ds-author-avatar {
            background: linear-gradient(135deg, #1a1a22 0%, #2a2a35 100%);
            box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.08), 0 2px 8px rgba(0, 0, 0, 0.12);
          }
          .ds-profile-avatar {
            background: linear-gradient(135deg, #1a1a22 0%, #2a2a35 50%, #0a0a0a 100%);
          }

          .ds-post-card { transition: transform 0.25s ease, box-shadow 0.25s ease, border-color 0.25s ease; }

          .preview-section {
            border-top: 1px solid rgba(0, 0, 0, 0.08);
            padding: 56px 0;
          }
          .preview-section:first-of-type { border-top: 0; }
          .preview-label {
            font-family: 'JetBrains Mono', ui-monospace, monospace;
            font-size: 11px;
            letter-spacing: 0.16em;
            text-transform: uppercase;
            color: #9ca3af;
            margin-bottom: 18px;
          }
          .preview-meta { color: #6b7280; font-size: 13px; margin-bottom: 24px; max-width: 720px; }
          .preview-card {
            background: white;
            border: 1px dashed rgba(0, 0, 0, 0.12);
            border-radius: 16px;
            padding: 28px;
          }
          .preview-card.dark { background: #0a0a0a; }
        </style>
      </head>
      <body>
        <%!-- ── Logged-in header at the very top ── --%>
        <.header
          current_user={@fake_user}
          active="home"
          bux_balance={12_450}
          cart_item_count={3}
          unread_notification_count={5}
        />

        <main class="max-w-[1280px] mx-auto px-6">
          <section class="preview-section">
            <div class="preview-label">design preview · wave 0 foundation components</div>
            <h1 class="font-bold tracking-[-0.022em] leading-[0.96] text-[44px] md:text-[64px] mb-3 text-[#141414]">
              The 11 Wave 0 components
            </h1>
            <p class="preview-meta">
              Dev-only page mounted at <code class="font-mono text-[12px]">/dev/design-preview</code>.
              Renders every component in <code class="font-mono text-[12px]">BlocksterV2Web.DesignSystem</code>
              so we can eyeball them through real Tailwind before Wave 1 starts touching pages.
              Each section is wrapped in a dashed frame so it's clear what the component is doing
              vs. the surrounding layout.
            </p>
          </section>

          <%!-- ── 1 · Logo ── --%>
          <section class="preview-section">
            <div class="preview-label">01 · &lt;.logo /&gt;</div>
            <div class="preview-card">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-8 items-end">
                <div class="space-y-6">
                  <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-400 mb-2">Light · scaling test</div>
                  <div class="space-y-5">
                    <.logo size="12px" />
                    <.logo size="16px" />
                    <.logo size="22px" />
                    <.logo size="32px" />
                    <.logo size="48px" />
                    <.logo size="64px" />
                    <.logo size="96px" />
                  </div>
                </div>
                <div class="bg-[#0a0a0a] rounded-2xl p-8 space-y-5">
                  <div class="text-[10px] uppercase tracking-[0.14em] text-white/40 mb-2">Dark variant</div>
                  <.logo size="22px" variant="dark" />
                  <.logo size="32px" variant="dark" />
                  <.logo size="48px" variant="dark" />
                  <.logo size="64px" variant="dark" />
                </div>
              </div>
            </div>
          </section>

          <%!-- ── 2 · Eyebrow ── --%>
          <section class="preview-section">
            <div class="preview-label">02 · &lt;.eyebrow /&gt;</div>
            <div class="preview-card">
              <div class="space-y-6">
                <div>
                  <.eyebrow>Most read this week</.eyebrow>
                  <h3 class="text-[28px] font-bold tracking-tight text-[#141414] mt-2">Trending</h3>
                </div>
                <div>
                  <.eyebrow class="text-[#a16207]">One thing left</.eyebrow>
                  <h3 class="text-[18px] font-bold text-[#141414] mt-1">Verify your phone to unlock 2x BUX</h3>
                </div>
              </div>
            </div>
          </section>

          <%!-- ── 3 · Chip ── --%>
          <section class="preview-section">
            <div class="preview-label">03 · &lt;.chip /&gt;</div>
            <div class="preview-card">
              <div class="flex items-center gap-2 flex-wrap">
                <.chip variant="active">All</.chip>
                <.chip>DeFi</.chip>
                <.chip>L2s</.chip>
                <.chip>AI × Crypto</.chip>
                <.chip>Stables</.chip>
                <.chip>RWA</.chip>
                <.chip>Privacy</.chip>
              </div>
            </div>
          </section>

          <%!-- ── 4 · Author avatar ── --%>
          <section class="preview-section">
            <div class="preview-label">04 · &lt;.author_avatar /&gt;</div>
            <div class="preview-card">
              <div class="flex items-end gap-6 flex-wrap">
                <div class="flex flex-col items-center gap-2">
                  <.author_avatar initials="MV" size="xs" />
                  <span class="text-[10px] font-mono text-neutral-500">xs · w-6</span>
                </div>
                <div class="flex flex-col items-center gap-2">
                  <.author_avatar initials="MV" size="sm" />
                  <span class="text-[10px] font-mono text-neutral-500">sm · w-7</span>
                </div>
                <div class="flex flex-col items-center gap-2">
                  <.author_avatar initials="MV" size="md" />
                  <span class="text-[10px] font-mono text-neutral-500">md · w-9</span>
                </div>
                <div class="flex flex-col items-center gap-2">
                  <.author_avatar initials="MV" size="lg" />
                  <span class="text-[10px] font-mono text-neutral-500">lg · w-12</span>
                </div>
                <div class="flex flex-col items-center gap-2">
                  <.author_avatar initials="MV" size="xl" />
                  <span class="text-[10px] font-mono text-neutral-500">xl · w-16</span>
                </div>
              </div>
            </div>
          </section>

          <%!-- ── 5 · Profile avatar ── --%>
          <section class="preview-section">
            <div class="preview-label">05 · &lt;.profile_avatar /&gt;</div>
            <div class="preview-card">
              <div class="flex items-end gap-6 flex-wrap">
                <div class="flex flex-col items-center gap-2">
                  <.profile_avatar initials="MV" size="sm" />
                  <span class="text-[10px] font-mono text-neutral-500">sm</span>
                </div>
                <div class="flex flex-col items-center gap-2">
                  <.profile_avatar initials="MV" size="md" ring />
                  <span class="text-[10px] font-mono text-neutral-500">md · ring</span>
                </div>
                <div class="flex flex-col items-center gap-2">
                  <.profile_avatar initials="MV" size="lg" />
                  <span class="text-[10px] font-mono text-neutral-500">lg</span>
                </div>
                <div class="flex flex-col items-center gap-2">
                  <.profile_avatar initials="MV" size="xl" />
                  <span class="text-[10px] font-mono text-neutral-500">xl</span>
                </div>
                <div class="flex flex-col items-center gap-2">
                  <.profile_avatar initials="MV" size="2xl" />
                  <span class="text-[10px] font-mono text-neutral-500">2xl</span>
                </div>
              </div>
            </div>
          </section>

          <%!-- ── 6 · Why Earn BUX banner ── --%>
          <section class="preview-section">
            <div class="preview-label">06 · &lt;.why_earn_bux_banner /&gt;</div>
            <div class="preview-card !p-0 overflow-hidden">
              <.why_earn_bux_banner />
            </div>
            <p class="preview-meta mt-4">
              In production this lives directly under <code class="font-mono text-[12px]">&lt;.header /&gt;</code> and is
              already shown as part of section 11 below. Banner is repeated here only so the
              copy is visible in isolation.
            </p>
          </section>

          <%!-- ── 7 · Page hero (Variant A) ── --%>
          <section class="preview-section">
            <div class="preview-label">07 · &lt;.page_hero variant="A" /&gt;</div>
            <div class="preview-card">
              <.page_hero
                eyebrow="The library"
                title="Browse hubs"
                description="Every brand on Blockster, sorted by activity. Follow the ones you care about and the trending posts will appear in your home feed."
              >
                <:stat label="Active hubs" value="142" />
                <:stat label="Posts today" value="48" sub="+12 vs yesterday" />
                <:stat label="BUX in pool" value="2.4M" />
              </.page_hero>
            </div>

            <div class="preview-card mt-6">
              <.page_hero
                eyebrow="Smaller variant"
                title="Pool detail"
                title_size="md"
                description="The same hero with title_size=md instead of xl, and only two stats so the right column compresses."
              >
                <:stat label="TVL" value="$182k" />
                <:stat label="LP price" value="1.0042" sub="+0.42% 24h" />
              </.page_hero>
            </div>
          </section>

          <%!-- ── 8 · Stat card ── --%>
          <section class="preview-section">
            <div class="preview-label">08 · &lt;.stat_card /&gt;</div>
            <div class="preview-card">
              <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <.stat_card label="BUX Balance" value="12,450" unit="BUX" sub="≈ $124.50 redeemable">
                  <:icon>
                    <img
                      src="https://ik.imagekit.io/blockster/blockster-icon.png"
                      alt=""
                      class="w-5 h-5 rounded-full"
                    />
                  </:icon>
                  <:footer>
                    <span class="text-neutral-500">Today</span>
                    <span class="font-mono font-bold text-[#22C55E]">+ 245 BUX</span>
                  </:footer>
                </.stat_card>

                <.stat_card label="Read streak" value="14" unit="days" sub="Best: 22 days" icon_bg="#7D00FF">
                  <:icon>
                    <svg class="w-5 h-5 text-white" viewBox="0 0 24 24" fill="currentColor">
                      <path d="M12 2l2.39 4.83L20 8l-3.5 3.41L17.5 17 12 14.17 6.5 17l1-5.59L4 8l5.61-1.17z" />
                    </svg>
                  </:icon>
                </.stat_card>

                <.stat_card label="Multiplier" value="3.2x" sub="phone · sol · email">
                  <:icon>
                    <svg class="w-5 h-5 text-black" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round">
                      <path d="M13 2 3 14h9l-1 8 10-12h-9z" />
                    </svg>
                  </:icon>
                </.stat_card>
              </div>
            </div>
          </section>

          <%!-- ── 9 · Post card ── --%>
          <section class="preview-section">
            <div class="preview-label">09 · &lt;.post_card /&gt;</div>
            <div class="preview-card">
              <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <.post_card
                  href="#"
                  image="https://picsum.photos/seed/blockster-preview-1/640/360"
                  hub_name="Moonpay"
                  hub_color="#7D00FF"
                  title="The quiet revolution of on-chain liquidity pools"
                  author="Marcus Verren"
                  read_minutes={8}
                  bux_reward={45}
                />
                <.post_card
                  href="#"
                  image="https://picsum.photos/seed/blockster-preview-2/640/360"
                  hub_name="Solana"
                  hub_color="#00FFA3"
                  title="Token-2022 extensions are quietly eating the SPL standard"
                  author="Jamie Chen"
                  read_minutes={6}
                  bux_reward={30}
                />
                <.post_card
                  href="#"
                  image="https://picsum.photos/seed/blockster-preview-3/640/360"
                  hub_name="Ethereum"
                  hub_color="#627EEA"
                  title="The model attribution problem: who gets paid when an LLM cites your post?"
                  author="Iris Chen"
                  read_minutes={12}
                  bux_reward={65}
                />
              </div>
            </div>
          </section>

          <%!-- ── 10 · Header (anonymous variant) ── --%>
          <section class="preview-section">
            <div class="preview-label">10 · &lt;.header current_user={nil} /&gt; · anonymous variant</div>
            <p class="preview-meta">
              The logged-in variant of the header is at the very top of this page (sticky).
              Below is the anonymous variant — the one a wallet-less visitor sees on
              <code class="font-mono text-[12px]">/</code>. Connect Wallet replaces the BUX
              pill + bell + cart + avatar cluster.
            </p>
            <div class="preview-card !p-0 overflow-hidden">
              <.header current_user={nil} active="home" />
            </div>
          </section>

          <%!-- ── 11 · Footer ── --%>
          <section class="preview-section">
            <div class="preview-label">11 · &lt;.footer /&gt;</div>
            <p class="preview-meta">
              The footer is rendered at full width below — outside the dashed preview frame
              because the footer is supposed to bleed to the page edges.
            </p>
          </section>
        </main>

        <.footer />
      </body>
    </html>
    """
  end
end
