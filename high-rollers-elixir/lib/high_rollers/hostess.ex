defmodule HighRollers.Hostess do
  @moduledoc """
  Static hostess metadata and configuration.
  Hostess types are immutable - determined at mint time.
  """

  @hostesses [
    %{index: 0, name: "Penelope Fatale", rarity: "0.5%", multiplier: 100,
      image: "https://ik.imagekit.io/blockster/penelope.jpg",
      description: "The rarest of them all - a true high roller's dream"},
    %{index: 1, name: "Mia Siren", rarity: "1%", multiplier: 90,
      image: "https://ik.imagekit.io/blockster/mia.jpg",
      description: "Her song lures the luckiest players"},
    %{index: 2, name: "Cleo Enchante", rarity: "3.5%", multiplier: 80,
      image: "https://ik.imagekit.io/blockster/cleo.jpg",
      description: "Egyptian royalty meets casino glamour"},
    %{index: 3, name: "Sophia Spark", rarity: "7.5%", multiplier: 70,
      image: "https://ik.imagekit.io/blockster/sophia.jpg",
      description: "Electrifying presence at every table"},
    %{index: 4, name: "Luna Mirage", rarity: "12.5%", multiplier: 60,
      image: "https://ik.imagekit.io/blockster/luna.jpg",
      description: "Mysterious as the moonlit casino floor"},
    %{index: 5, name: "Aurora Seductra", rarity: "25%", multiplier: 50,
      image: "https://ik.imagekit.io/blockster/aurora.jpg",
      description: "Lights up every room she enters"},
    %{index: 6, name: "Scarlett Ember", rarity: "25%", multiplier: 40,
      image: "https://ik.imagekit.io/blockster/scarlett.jpg",
      description: "Red hot luck follows her everywhere"},
    %{index: 7, name: "Vivienne Allure", rarity: "25%", multiplier: 30,
      image: "https://ik.imagekit.io/blockster/vivienne.jpg",
      description: "Classic elegance with a winning touch"}
  ]

  def all, do: @hostesses
  def get(index) when index >= 0 and index <= 7, do: Enum.at(@hostesses, index)
  def get(_), do: nil

  def multiplier(index), do: get(index)[:multiplier] || 30
  def name(index), do: get(index)[:name] || "Unknown"
  def multipliers, do: [100, 90, 80, 70, 60, 50, 40, 30]

  @doc """
  Returns all hostesses with their current mint counts.
  Queries NFTStore for counts by hostess_index.
  """
  def all_with_counts do
    counts = HighRollers.NFTStore.get_counts_by_hostess()

    Enum.map(@hostesses, fn hostess ->
      count = Map.get(counts, hostess.index, 0)
      Map.put(hostess, :count, count)
    end)
  end

  @doc """
  Returns ImageKit-optimized image URL for a hostess.
  """
  def image(index) do
    case get(index) do
      nil -> nil
      hostess -> hostess.image
    end
  end

  @doc """
  Returns ImageKit-optimized thumbnail URL (128x128) for a hostess.
  """
  def thumbnail(index) do
    case image(index) do
      nil -> nil
      url -> "#{url}?tr=w-128,h-128,fo-auto"
    end
  end
end
