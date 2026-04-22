defmodule BlocksterV2Web.DocsComponents do
  @moduledoc """
  Shared gitbook-style components for the /docs site.

  Provides a two-column layout (sidebar + content), typography styles, callouts,
  code blocks, spec tables, and audit-finding cards. All pages under /docs
  render their own `<.header />` and `<.footer />` from the DesignSystem module,
  then wrap their body in `<.docs_shell>`.
  """
  use Phoenix.Component

  alias BlocksterV2Web.DesignSystem

  @nav [
    %{
      group: "Getting started",
      items: [
        %{path: "/docs", label: "Overview"}
      ]
    },
    %{
      group: "Games",
      items: [
        %{path: "/docs/coin-flip", label: "Coin Flip"},
        %{path: "/docs/provably-fair", label: "Provably fair"}
      ]
    },
    %{
      group: "Bankroll",
      items: [
        %{path: "/docs/pools", label: "Pools & LP"}
      ]
    },
    %{
      group: "Technical",
      items: [
        %{path: "/docs/smart-contracts", label: "Smart contracts"}
      ]
    },
    %{
      group: "Security",
      items: [
        %{path: "/docs/security-audit", label: "Security audit"}
      ]
    }
  ]

  def nav, do: @nav

  # ── <.docs_shell /> ────────────────────────────────────────────────────────
  #
  # The outer layout for every /docs/* page. Renders the site header, a
  # two-column body (sticky sidebar on desktop; inline accordion above the
  # content on mobile), and the footer. Child content goes in the default slot.

  attr :current_user, :any, default: nil
  attr :bux_balance, :any, default: 0
  attr :token_balances, :map, default: %{}
  attr :cart_item_count, :integer, default: 0
  attr :unread_notification_count, :integer, default: 0
  attr :notification_dropdown_open, :boolean, default: false
  attr :recent_notifications, :list, default: []
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: []
  attr :show_search_results, :boolean, default: false
  attr :show_search_modal, :boolean, default: false
  attr :connecting, :boolean, default: false
  attr :announcement_banner, :any, default: nil
  attr :active, :string, required: true, doc: "path of the current page, e.g. /docs/coin-flip"
  slot :inner_block, required: true

  def docs_shell(assigns) do
    ~H"""
    <DesignSystem.header
      current_user={@current_user}
      active=""
      bux_balance={@bux_balance}
      token_balances={@token_balances}
      cart_item_count={@cart_item_count}
      unread_notification_count={@unread_notification_count}
      notification_dropdown_open={@notification_dropdown_open}
      recent_notifications={@recent_notifications}
      search_query={@search_query}
      search_results={@search_results}
      show_search_results={@show_search_results}
      show_search_modal={@show_search_modal}
      connecting={@connecting}
      announcement_banner={@announcement_banner}
    />

    <main class="bg-[#F5F6FB] min-h-screen">
      <div class="max-w-[1280px] mx-auto px-4 md:px-6 pt-6 md:pt-10 pb-24">
        <div class="grid grid-cols-12 gap-6 lg:gap-10">
          <%!-- sidebar --%>
          <aside class="col-span-12 lg:col-span-3">
            <.docs_sidebar active={@active} />
          </aside>

          <%!-- main column --%>
          <article class="col-span-12 lg:col-span-9 min-w-0">
            {render_slot(@inner_block)}
          </article>
        </div>
      </div>
    </main>

    <DesignSystem.footer />
    """
  end

  # ── <.docs_sidebar /> ──────────────────────────────────────────────────────

  attr :active, :string, required: true

  def docs_sidebar(assigns) do
    assigns = assign(assigns, :nav, @nav)

    ~H"""
    <nav class="lg:sticky lg:top-24 space-y-6 bg-white rounded-2xl border border-[#E8EAF0] p-5 lg:p-6">
      <div>
        <div class="text-[10px] uppercase tracking-[0.18em] text-[#9AA0AE] font-bold mb-1">
          Blockster
        </div>
        <div class="text-[15px] font-haas_bold_75 text-[#141414]">Documentation</div>
      </div>

      <div :for={group <- @nav} class="space-y-2">
        <div class="text-[10px] uppercase tracking-[0.18em] text-[#9AA0AE] font-bold">
          {group.group}
        </div>
        <ul class="space-y-0.5">
          <li :for={item <- group.items}>
            <.link
              navigate={item.path}
              class={[
                "block rounded-lg px-3 py-1.5 text-[13px] transition-colors cursor-pointer",
                active_cls(item.path, @active)
              ]}
            >
              {item.label}
            </.link>
          </li>
        </ul>
      </div>
    </nav>
    """
  end

  defp active_cls(path, path), do: "bg-[#141414] text-white font-bold"
  defp active_cls(_, _), do: "text-[#515B70] hover:bg-[#F2F3F7] hover:text-[#141414]"

  # ── <.docs_hero /> ─────────────────────────────────────────────────────────

  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :class, :string, default: nil

  def docs_hero(assigns) do
    ~H"""
    <header class={[
      "mb-10 pb-8 border-b border-[#E8EAF0]",
      @class
    ]}>
      <div :if={@eyebrow} class="text-[11px] uppercase tracking-[0.18em] text-[#CAFC00] font-bold mb-3 flex items-center gap-2">
        <span class="w-1.5 h-1.5 rounded-full bg-[#CAFC00]"></span>
        <span class="text-[#515B70]">{@eyebrow}</span>
      </div>
      <h1 class="font-haas_bold_75 text-[32px] md:text-[44px] leading-[1.05] text-[#141414] tracking-tight">
        {@title}
      </h1>
      <p :if={@description} class="mt-4 text-[16px] md:text-[17px] leading-[1.6] text-[#515B70] font-haas_roman_55 max-w-[720px]">
        {@description}
      </p>
    </header>
    """
  end

  # ── <.page_toc /> ──────────────────────────────────────────────────────────
  #
  # Inline table of contents at the top of long pages. Each item jumps to an
  # anchor on the same page.

  attr :items, :list, required: true, doc: "list of %{id:, label:}"

  def page_toc(assigns) do
    ~H"""
    <nav class="mb-12 bg-white border border-[#E8EAF0] rounded-2xl p-5">
      <div class="text-[10px] uppercase tracking-[0.18em] text-[#9AA0AE] font-bold mb-3">
        On this page
      </div>
      <ol class="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-1.5 text-[13px]">
        <li :for={{item, idx} <- Enum.with_index(@items, 1)}>
          <a
            href={"##{item.id}"}
            class="text-[#515B70] hover:text-[#141414] hover:underline transition-colors flex items-baseline gap-2"
          >
            <span class="font-mono text-[11px] text-[#9AA0AE]">{String.pad_leading(to_string(idx), 2, "0")}</span>
            <span>{item.label}</span>
          </a>
        </li>
      </ol>
    </nav>
    """
  end

  # ── <.section /> ───────────────────────────────────────────────────────────
  #
  # Section wrapper with anchor ID + H2 title.

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :eyebrow, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <section id={@id} class={["scroll-mt-24 mb-14", @class]}>
      <div :if={@eyebrow} class="text-[10px] uppercase tracking-[0.18em] text-[#9AA0AE] font-bold mb-2">
        {@eyebrow}
      </div>
      <h2 class="font-haas_bold_75 text-[24px] md:text-[28px] text-[#141414] tracking-tight mb-5">
        {@title}
      </h2>
      <div class={prose_cls()}>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  defp prose_cls do
    "text-[15px] leading-[1.65] text-[#2A2F3A] space-y-4 " <>
      "[&>p]:leading-[1.65] " <>
      "[&>ul]:list-disc [&>ul]:pl-6 [&>ul]:space-y-1.5 [&>ul]:marker:text-[#9AA0AE] " <>
      "[&>ol]:list-decimal [&>ol]:pl-6 [&>ol]:space-y-1.5 [&>ol]:marker:text-[#9AA0AE] " <>
      "[&_a]:text-[#3D5AFE] [&_a]:underline [&_a:hover]:text-[#141414] " <>
      "[&_strong]:font-haas_bold_75 [&_strong]:text-[#141414] " <>
      "[&_code]:bg-[#141414]/[0.06] [&_code]:px-1.5 [&_code]:py-0.5 [&_code]:rounded [&_code]:text-[12.5px] [&_code]:font-mono " <>
      "[&_blockquote]:border-l-4 [&_blockquote]:border-[#CAFC00] [&_blockquote]:pl-4 [&_blockquote]:italic [&_blockquote]:text-[#515B70]"
  end

  # ── <.subsection /> ────────────────────────────────────────────────────────

  attr :id, :string, default: nil
  attr :title, :string, required: true
  slot :inner_block, required: true

  def subsection(assigns) do
    ~H"""
    <div id={@id} class="scroll-mt-24 mt-10 mb-6">
      <h3 class="font-haas_bold_75 text-[18px] md:text-[20px] text-[#141414] tracking-tight mb-3">
        {@title}
      </h3>
      <div class={prose_cls()}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ── <.callout /> ───────────────────────────────────────────────────────────
  #
  # Sidebar-style note. kind: info | warning | danger | success | note

  attr :kind, :string, default: "info", values: ~w(info warning danger success note)
  attr :title, :string, default: nil
  slot :inner_block, required: true

  def callout(assigns) do
    ~H"""
    <aside class={[
      "not-prose my-6 rounded-xl border-l-4 p-5",
      callout_cls(@kind)
    ]}>
      <div class="flex items-start gap-3">
        <div class={["shrink-0 mt-0.5", callout_icon_cls(@kind)]}>
          {callout_icon(%{kind: @kind})}
        </div>
        <div class="flex-1 min-w-0">
          <div :if={@title} class={[
            "text-[11px] uppercase tracking-[0.14em] font-bold mb-1",
            callout_title_cls(@kind)
          ]}>
            {@title}
          </div>
          <div class="text-[14px] leading-[1.6] text-[#2A2F3A] space-y-2 [&_code]:bg-[#141414]/[0.06] [&_code]:px-1 [&_code]:py-0.5 [&_code]:rounded [&_code]:text-[12px] [&_code]:font-mono">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </aside>
    """
  end

  defp callout_cls("info"), do: "bg-[#EEF4FF] border-[#3D5AFE]"
  defp callout_cls("warning"), do: "bg-[#FFF8E1] border-[#F59E0B]"
  defp callout_cls("danger"), do: "bg-[#FFECEC] border-[#E53935]"
  defp callout_cls("success"), do: "bg-[#ECFDF5] border-[#10B981]"
  defp callout_cls("note"), do: "bg-[#F5F6FB] border-[#141414]"

  defp callout_icon_cls("info"), do: "text-[#3D5AFE]"
  defp callout_icon_cls("warning"), do: "text-[#F59E0B]"
  defp callout_icon_cls("danger"), do: "text-[#E53935]"
  defp callout_icon_cls("success"), do: "text-[#10B981]"
  defp callout_icon_cls("note"), do: "text-[#141414]"

  defp callout_title_cls("info"), do: "text-[#3D5AFE]"
  defp callout_title_cls("warning"), do: "text-[#B45309]"
  defp callout_title_cls("danger"), do: "text-[#B91C1C]"
  defp callout_title_cls("success"), do: "text-[#047857]"
  defp callout_title_cls("note"), do: "text-[#141414]"

  attr :kind, :string, required: true

  defp callout_icon(%{kind: "warning"} = assigns) do
    ~H"""
    <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
      <line x1="12" y1="9" x2="12" y2="13"/>
      <line x1="12" y1="17" x2="12.01" y2="17"/>
    </svg>
    """
  end

  defp callout_icon(%{kind: "danger"} = assigns) do
    ~H"""
    <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="12" cy="12" r="10"/>
      <line x1="12" y1="8" x2="12" y2="12"/>
      <line x1="12" y1="16" x2="12.01" y2="16"/>
    </svg>
    """
  end

  defp callout_icon(%{kind: "success"} = assigns) do
    ~H"""
    <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="20 6 9 17 4 12"/>
    </svg>
    """
  end

  defp callout_icon(assigns) do
    ~H"""
    <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="12" cy="12" r="10"/>
      <line x1="12" y1="16" x2="12" y2="12"/>
      <line x1="12" y1="8" x2="12.01" y2="8"/>
    </svg>
    """
  end

  # ── <.code_block /> ────────────────────────────────────────────────────────
  #
  # Code is passed as a plain string attribute (not a slot) so it can contain
  # literal `{` and `}` without tripping HEEx's `{expr}` interpolation.

  attr :code, :string, required: true, doc: "literal source code to render"
  attr :lang, :string, default: nil
  attr :title, :string, default: nil
  attr :class, :string, default: nil

  def code_block(assigns) do
    ~H"""
    <div class={["not-prose my-5 rounded-xl overflow-hidden border border-[#1F2937] bg-[#0A0F1C] text-[#E6E8EE]", @class]}>
      <div :if={@title || @lang} class="flex items-center justify-between px-4 py-2 bg-[#0F172A] border-b border-[#1F2937]">
        <div class="text-[12px] font-mono text-[#CAFC00]">{@title || ""}</div>
        <div :if={@lang} class="text-[10px] uppercase tracking-[0.14em] text-white/40 font-bold">{@lang}</div>
      </div>
      <pre class="px-4 py-4 text-[12.5px] leading-[1.6] overflow-x-auto font-mono whitespace-pre"><code>{@code}</code></pre>
    </div>
    """
  end

  # ── <.kv_table /> ──────────────────────────────────────────────────────────
  #
  # Two-column spec table. rows: list of {key, value} tuples OR list of
  # %{key:, value:, note:}.

  attr :title, :string, default: nil
  attr :rows, :list, required: true

  def kv_table(assigns) do
    ~H"""
    <div class="not-prose my-6 rounded-xl overflow-hidden border border-[#E8EAF0] bg-white">
      <div :if={@title} class="px-5 py-3 bg-[#F5F6FB] border-b border-[#E8EAF0]">
        <div class="text-[11px] uppercase tracking-[0.14em] font-bold text-[#141414]">{@title}</div>
      </div>
      <dl class="divide-y divide-[#E8EAF0]">
        <div :for={row <- @rows} class="grid grid-cols-12 gap-4 px-5 py-3 text-[13.5px]">
          <dt class="col-span-12 md:col-span-4 font-mono text-[12px] text-[#515B70]">{kv_key(row)}</dt>
          <dd class="col-span-12 md:col-span-8 text-[#141414] break-words">{kv_value(row)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  defp kv_key({k, _}), do: k
  defp kv_key(%{key: k}), do: k
  defp kv_value({_, v}), do: v
  defp kv_value(%{value: v}), do: v

  # ── <.spec_table /> ────────────────────────────────────────────────────────
  #
  # Generic table with configurable columns.
  # cols: list of %{key:, label:, width_cls?:}
  # rows: list of maps

  attr :title, :string, default: nil
  attr :cols, :list, required: true
  attr :rows, :list, required: true
  attr :class, :string, default: nil

  def spec_table(assigns) do
    ~H"""
    <div class={["not-prose my-6 rounded-xl overflow-hidden border border-[#E8EAF0] bg-white", @class]}>
      <div :if={@title} class="px-5 py-3 bg-[#F5F6FB] border-b border-[#E8EAF0]">
        <div class="text-[11px] uppercase tracking-[0.14em] font-bold text-[#141414]">{@title}</div>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full text-[13px]">
          <thead class="bg-[#FAFBFE] border-b border-[#E8EAF0]">
            <tr>
              <th
                :for={col <- @cols}
                class="text-left px-4 py-2.5 text-[10px] uppercase tracking-[0.14em] font-bold text-[#515B70]"
              >
                {col.label}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[#E8EAF0]">
            <tr :for={row <- @rows} class="hover:bg-[#FAFBFE]">
              <td
                :for={col <- @cols}
                class={[
                  "px-4 py-3 align-top text-[#141414]",
                  Map.get(col, :mono, false) && "font-mono text-[12px]"
                ]}
              >
                {Map.get(row, col.key) || ""}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # ── <.severity_pill /> ─────────────────────────────────────────────────────

  attr :level, :string, required: true, values: ~w(critical high medium low informational resolved)
  attr :class, :string, default: nil

  def severity_pill(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-bold uppercase tracking-[0.14em]",
      severity_cls(@level),
      @class
    ]}>
      <span class={["w-1.5 h-1.5 rounded-full", severity_dot_cls(@level)]}></span>
      {String.upcase(@level)}
    </span>
    """
  end

  defp severity_cls("critical"), do: "bg-[#FFECEC] text-[#B91C1C] border border-[#F5B5B5]"
  defp severity_cls("high"), do: "bg-[#FFF2E0] text-[#C2410C] border border-[#FCD9B5]"
  defp severity_cls("medium"), do: "bg-[#FFF8E1] text-[#B45309] border border-[#FCE5A6]"
  defp severity_cls("low"), do: "bg-[#EEF4FF] text-[#1E3A8A] border border-[#C7D6FF]"
  defp severity_cls("informational"), do: "bg-[#F5F6FB] text-[#515B70] border border-[#E8EAF0]"
  defp severity_cls("resolved"), do: "bg-[#ECFDF5] text-[#047857] border border-[#BBF7D0]"

  defp severity_dot_cls("critical"), do: "bg-[#B91C1C]"
  defp severity_dot_cls("high"), do: "bg-[#C2410C]"
  defp severity_dot_cls("medium"), do: "bg-[#B45309]"
  defp severity_dot_cls("low"), do: "bg-[#1E3A8A]"
  defp severity_dot_cls("informational"), do: "bg-[#515B70]"
  defp severity_dot_cls("resolved"), do: "bg-[#10B981]"

  # ── <.audit_finding /> ─────────────────────────────────────────────────────
  #
  # Full finding card with ID, title, severity, status, and slots for the body.

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :severity, :string, required: true
  attr :status, :string, default: "open", values: ~w(open acknowledged resolved by_design)
  slot :description, required: true
  slot :impact
  slot :recommendation
  slot :references

  def audit_finding(assigns) do
    ~H"""
    <div id={@id} class="not-prose scroll-mt-24 my-6 rounded-2xl overflow-hidden border border-[#E8EAF0] bg-white">
      <div class="flex items-center justify-between gap-3 px-5 md:px-6 py-4 bg-[#FAFBFE] border-b border-[#E8EAF0]">
        <div class="flex items-center gap-3 min-w-0">
          <span class="font-mono text-[11px] text-[#9AA0AE] shrink-0">{@id}</span>
          <h4 class="font-haas_bold_75 text-[15px] text-[#141414] truncate">{@title}</h4>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <.severity_pill level={@severity} />
          <span class={["text-[10px] uppercase tracking-[0.14em] font-bold", status_cls(@status)]}>
            {status_label(@status)}
          </span>
        </div>
      </div>
      <div class="px-5 md:px-6 py-5 space-y-5 text-[14px] leading-[1.6] text-[#2A2F3A]">
        <div>
          <div class="text-[10px] uppercase tracking-[0.14em] font-bold text-[#9AA0AE] mb-1.5">Description</div>
          <div class="space-y-2">{render_slot(@description)}</div>
        </div>
        <div :if={@impact != []}>
          <div class="text-[10px] uppercase tracking-[0.14em] font-bold text-[#9AA0AE] mb-1.5">Impact</div>
          <div class="space-y-2">{render_slot(@impact)}</div>
        </div>
        <div :if={@recommendation != []}>
          <div class="text-[10px] uppercase tracking-[0.14em] font-bold text-[#9AA0AE] mb-1.5">Recommendation</div>
          <div class="space-y-2">{render_slot(@recommendation)}</div>
        </div>
        <div :if={@references != []} class="pt-3 border-t border-[#E8EAF0]">
          <div class="text-[10px] uppercase tracking-[0.14em] font-bold text-[#9AA0AE] mb-1.5">References</div>
          <div class="text-[12.5px] font-mono text-[#515B70]">{render_slot(@references)}</div>
        </div>
      </div>
    </div>
    """
  end

  defp status_cls("resolved"), do: "text-[#047857]"
  defp status_cls("acknowledged"), do: "text-[#1E3A8A]"
  defp status_cls("by_design"), do: "text-[#515B70]"
  defp status_cls(_), do: "text-[#B91C1C]"

  defp status_label("by_design"), do: "BY DESIGN"
  defp status_label(s), do: String.upcase(s)

  # ── <.stat_row /> ──────────────────────────────────────────────────────────
  #
  # Horizontal band of 3-4 numeric stats for hero/overview pages.

  slot :stat do
    attr :label, :string, required: true
    attr :value, :string, required: true
    attr :sub, :string
  end

  def stat_row(assigns) do
    ~H"""
    <div class="not-prose grid grid-cols-2 md:grid-cols-4 gap-3 my-8">
      <div :for={stat <- @stat} class="bg-white border border-[#E8EAF0] rounded-xl p-4">
        <div class="text-[10px] uppercase tracking-[0.18em] font-bold text-[#9AA0AE] mb-1.5">
          {stat.label}
        </div>
        <div class="font-haas_bold_75 text-[22px] text-[#141414] leading-none">
          {stat.value}
        </div>
        <div :if={Map.get(stat, :sub)} class="text-[12px] text-[#515B70] mt-1.5">
          {stat.sub}
        </div>
      </div>
    </div>
    """
  end

  # ── <.pill /> ──────────────────────────────────────────────────────────────

  attr :tone, :string, default: "neutral", values: ~w(neutral brand warn danger success)
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def pill(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-mono font-bold",
      pill_cls(@tone),
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp pill_cls("brand"), do: "bg-[#CAFC00] text-[#141414]"
  defp pill_cls("warn"), do: "bg-[#FFF8E1] text-[#B45309]"
  defp pill_cls("danger"), do: "bg-[#FFECEC] text-[#B91C1C]"
  defp pill_cls("success"), do: "bg-[#ECFDF5] text-[#047857]"
  defp pill_cls(_), do: "bg-[#F5F6FB] text-[#141414]"

  # ── <.inline_code /> — utility ─────────────────────────────────────────────

  slot :inner_block, required: true

  def inline_code(assigns) do
    ~H"""
    <code class="bg-[#141414]/[0.06] px-1.5 py-0.5 rounded text-[12.5px] font-mono">{render_slot(@inner_block)}</code>
    """
  end

  # ── <.ol_steps /> ──────────────────────────────────────────────────────────
  #
  # Numbered step list with accent styling.

  slot :step, required: true do
    attr :title, :string, required: true
  end

  def ol_steps(assigns) do
    ~H"""
    <ol class="not-prose my-6 space-y-4">
      <li
        :for={{step, idx} <- Enum.with_index(@step, 1)}
        class="flex gap-4 bg-white border border-[#E8EAF0] rounded-xl p-5"
      >
        <div class="shrink-0 w-8 h-8 rounded-lg bg-[#141414] text-white font-haas_bold_75 text-[13px] flex items-center justify-center">
          {idx}
        </div>
        <div class="flex-1 min-w-0">
          <div class="font-haas_bold_75 text-[15px] text-[#141414] mb-1.5">{step.title}</div>
          <div class="text-[14px] leading-[1.6] text-[#2A2F3A] space-y-2">
            {render_slot(step)}
          </div>
        </div>
      </li>
    </ol>
    """
  end
end
