defmodule BlocksterV2.Notifications.OfferSelector do
  @moduledoc """
  Generates personalized offer for a user based on their shopping behavior.
  Returns offer type + content for emails and notifications.
  """

  alias BlocksterV2.UserEvents

  @doc """
  Select the best offer type for a user based on their profile.
  Returns {offer_type, data} tuple.

  Offer types:
  - :cart_reminder — they have items in cart
  - :product_highlight — viewed products but never carted
  - :cross_sell — previous buyer
  - :bux_spend — BUX-rich but never purchased
  - :trending — default fallback
  """
  def select_offer(user_id) do
    profile = UserEvents.get_profile(user_id) || default_profile()

    cond do
      has_carted_items?(profile) ->
        {:cart_reminder, %{
          product_ids: profile.carted_not_purchased,
          message: "Still in your cart"
        }}

      has_viewed_products?(profile) and profile.purchase_count == 0 ->
        {:product_highlight, %{
          product_ids: Enum.take(profile.viewed_products_last_30d, 3),
          message: "Trending products you viewed"
        }}

      profile.purchase_count > 0 ->
        {:cross_sell, %{
          message: "Based on your previous purchase"
        }}

      bux_rich?(profile) and profile.purchase_count == 0 ->
        {:bux_spend, %{
          bux_balance: profile.bux_balance,
          message: "Your BUX can get you..."
        }}

      true ->
        {:trending, %{
          message: "Trending in the shop"
        }}
    end
  end

  @doc """
  Generate urgency message based on offer context.
  """
  def urgency_message(:cart_reminder, _data), do: "Complete your order"
  def urgency_message(:product_highlight, _data), do: "Popular right now"
  def urgency_message(:cross_sell, _data), do: "You might also like"
  def urgency_message(:bux_spend, %{bux_balance: balance}) do
    "Spend your #{format_bux(balance)} BUX"
  end
  def urgency_message(_, _), do: "Check out the shop"

  # ============ Private ============

  defp has_carted_items?(profile) do
    (profile.carted_not_purchased || []) != []
  end

  defp has_viewed_products?(profile) do
    (profile.viewed_products_last_30d || []) != []
  end

  defp bux_rich?(profile) do
    balance = profile.bux_balance || Decimal.new("0")
    Decimal.compare(balance, Decimal.new("5000")) == :gt
  end

  defp format_bux(nil), do: "0"
  defp format_bux(balance) do
    balance |> Decimal.to_integer() |> Integer.to_string() |> add_commas()
  rescue
    _ -> Decimal.to_string(balance)
  end

  defp add_commas(str) when byte_size(str) <= 3, do: str
  defp add_commas(str) do
    {prefix, last3} = String.split_at(str, -3)
    add_commas(prefix) <> "," <> last3
  end

  defp default_profile do
    %BlocksterV2.Notifications.UserProfile{
      carted_not_purchased: [],
      viewed_products_last_30d: [],
      purchase_count: 0,
      bux_balance: Decimal.new("0")
    }
  end
end
