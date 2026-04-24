defmodule BlocksterV2Web.ShopComponents do
  @moduledoc """
  Shared UI for shop listings and product pages. Currently holds the SOL-first
  price block used by the grid (index) and the product detail page.
  """

  use Phoenix.Component

  alias BlocksterV2.Shop.Pricing

  @doc """
  Renders a SOL-primary price with a USD equivalent below. Handles discounted
  pricing when a product has BUX/hub-token max discount configured — the
  struck-through amount is the full SOL price, primary is post-discount SOL.
  """
  attr :product, :map, required: true
  attr :sol_usd, :float, required: true
  attr :align, :string, default: "center", values: ~w(center left right)
  attr :size, :string, default: "md", values: ~w(sm md)

  def product_price_block(assigns) do
    effective = effective_usd(assigns.product)

    assigns =
      assigns
      |> assign(:sol_primary, Pricing.usd_to_sol(effective, assigns.sol_usd))
      |> assign(:sol_original, Pricing.usd_to_sol(assigns.product.price, assigns.sol_usd))
      |> assign(:effective_usd, effective)
      |> assign(:align_cls, align_cls(assigns.align))
      |> assign(:primary_size_cls, primary_size_cls(assigns.size))

    ~H"""
    <div class={["flex flex-col mb-3", @align_cls]}>
      <%= if @product.total_max_discount > 0 do %>
        <span class="text-[10px] text-neutral-400 line-through font-mono">{Pricing.format_sol(@sol_original)} SOL</span>
        <span class={["font-mono font-bold text-[#141414] leading-none", @primary_size_cls]}>{Pricing.format_sol(@sol_primary)} SOL</span>
        <span class="text-[10px] text-neutral-500 font-medium mt-0.5">
          ≈ {Pricing.format_usd(@effective_usd)} · with BUX
        </span>
      <% else %>
        <span class={["font-mono font-bold text-[#141414] leading-none", @primary_size_cls]}>{Pricing.format_sol(@sol_primary)} SOL</span>
        <span class="text-[10px] text-neutral-500 font-medium mt-0.5">
          ≈ {Pricing.format_usd(@effective_usd)}
        </span>
      <% end %>
    </div>
    """
  end

  defp effective_usd(%{total_max_discount: d, max_discounted_price: dp}) when d > 0, do: dp
  defp effective_usd(%{price: p}), do: p

  defp align_cls("left"), do: "items-start"
  defp align_cls("right"), do: "items-end"
  defp align_cls(_), do: "items-center"

  defp primary_size_cls("sm"), do: "text-[16px]"
  defp primary_size_cls(_), do: "text-[20px]"

  @doc """
  SOL-primary price with USD `≈` secondary. The canonical one-liner across
  /shop, /shop/:slug, /cart, /checkout — every surface that should read
  "2.50 SOL ≈ $220.00" renders through this. Per the 2026-04-22 product call,
  SOL is the settlement currency and the primary display everywhere except
  /wallet (WALLET-03: wallet stays LIVE-rate, not session-snapshotted).

  Inputs are a USD amount (Decimal OR float) and the current SOL/USD rate
  (float). SOL is derived from `(usd / rate)`. Shape lets callers pass
  whatever Decimal shape their schema stores without converting first.

  Size variants match the DS totals block: `:total` for the big number, `:line`
  for a subtotal/shipping-fee row, `:tiny` for an inline badge.
  """
  attr :usd, :any, required: true, doc: "USD amount (Decimal, float, or integer)"
  attr :rate, :float, required: true, doc: "SOL/USD rate snapshot"
  attr :size, :atom, default: :total, values: ~w(total line tiny)a
  attr :align, :string, default: "right", values: ~w(left right)
  attr :class, :string, default: ""

  def sol_usd_dual(assigns) do
    usd_float = to_float(assigns.usd)
    sol = if assigns.rate > 0, do: usd_float / assigns.rate, else: 0.0
    free? = usd_float <= 0.0 or sol <= 0.0

    assigns =
      assigns
      |> assign(:sol, sol)
      |> assign(:usd_float, usd_float)
      |> assign(:free?, free?)
      |> assign(:primary_cls, dual_primary_cls(assigns.size))
      |> assign(:secondary_cls, dual_secondary_cls(assigns.size))
      |> assign(:align_cls, if(assigns.align == "left", do: "items-start", else: "items-end"))

    ~H"""
    <div class={["flex flex-col", @align_cls, @class]}>
      <%= if @free? do %>
        <span class={@primary_cls}>FREE</span>
        <span class={@secondary_cls}>≈ $0.00</span>
      <% else %>
        <span class={@primary_cls}>{Pricing.format_sol_precise(@sol)} SOL</span>
        <span class={@secondary_cls}>≈ {Pricing.format_usd(@usd_float)}</span>
      <% end %>
    </div>
    """
  end

  defp dual_primary_cls(:total), do: "font-mono font-bold text-[22px] text-[#141414] leading-none"
  defp dual_primary_cls(:line), do: "font-mono font-bold text-[14px] text-[#141414]"
  defp dual_primary_cls(:tiny), do: "font-mono font-medium text-[12px] text-[#141414]"

  defp dual_secondary_cls(:total), do: "mt-1 text-[11px] text-neutral-500 font-mono"
  defp dual_secondary_cls(:line), do: "text-[11px] text-neutral-500 font-mono"
  defp dual_secondary_cls(:tiny), do: "text-[10px] text-neutral-500 font-mono"

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n / 1.0
  defp to_float(_), do: 0.0
end
