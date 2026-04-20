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
end
