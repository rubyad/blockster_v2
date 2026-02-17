defmodule BlocksterV2.Shop.SizePresets do
  @moduledoc """
  Predefined size sets for different product types.
  Used by admin form (checkboxes) and frontend (size grid display).
  """

  @clothing_sizes ["XS", "S", "M", "L", "XL", "XXL", "3XL"]

  @mens_shoe_sizes [
    "US 7", "US 7.5", "US 8", "US 8.5", "US 9", "US 9.5",
    "US 10", "US 10.5", "US 11", "US 11.5", "US 12", "US 13", "US 14"
  ]

  @womens_shoe_sizes [
    "US 5", "US 5.5", "US 6", "US 6.5", "US 7", "US 7.5",
    "US 8", "US 8.5", "US 9", "US 9.5", "US 10", "US 11"
  ]

  def clothing_sizes, do: @clothing_sizes
  def mens_shoe_sizes, do: @mens_shoe_sizes
  def womens_shoe_sizes, do: @womens_shoe_sizes

  @doc """
  Returns the preset sizes for a given size_type.
  """
  def sizes_for_type("clothing"), do: @clothing_sizes
  def sizes_for_type("mens_shoes"), do: @mens_shoe_sizes
  def sizes_for_type("womens_shoes"), do: @womens_shoe_sizes
  def sizes_for_type("unisex_shoes"), do: @mens_shoe_sizes ++ @womens_shoe_sizes
  def sizes_for_type("one_size"), do: ["One Size"]
  def sizes_for_type(_), do: []

  @doc """
  Returns the men's sizes from a unisex size list.
  Unisex sizes are stored with M- or W- prefix (e.g. "M-US 10", "W-US 8").
  """
  def mens_unisex_sizes(available_sizes) do
    available_sizes
    |> Enum.filter(&String.starts_with?(&1, "M-"))
    |> Enum.map(&String.replace_leading(&1, "M-", ""))
  end

  @doc """
  Returns the women's sizes from a unisex size list.
  """
  def womens_unisex_sizes(available_sizes) do
    available_sizes
    |> Enum.filter(&String.starts_with?(&1, "W-"))
    |> Enum.map(&String.replace_leading(&1, "W-", ""))
  end

  @doc """
  Returns a human-readable label for a size_type.
  """
  def size_type_label("clothing"), do: "Clothing"
  def size_type_label("mens_shoes"), do: "Men's Shoes"
  def size_type_label("womens_shoes"), do: "Women's Shoes"
  def size_type_label("unisex_shoes"), do: "Unisex Shoes"
  def size_type_label("one_size"), do: "One Size"
  def size_type_label(_), do: "Unknown"

  @doc """
  All valid size types as {label, value} tuples for select dropdowns.
  """
  def size_type_options do
    [
      {"Clothing", "clothing"},
      {"Men's Shoes", "mens_shoes"},
      {"Women's Shoes", "womens_shoes"},
      {"Unisex Shoes", "unisex_shoes"},
      {"One Size", "one_size"}
    ]
  end
end
