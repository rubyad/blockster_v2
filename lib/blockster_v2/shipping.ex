defmodule BlocksterV2.Shipping do
  @moduledoc """
  Flat-rate shipping tiers with US focus and worldwide coverage.
  """

  @us_countries ["US", "United States", "USA", "United States of America"]

  @rates %{
    us_standard: %{
      key: "us_standard",
      label: "Standard Shipping",
      description: "5-7 business days",
      cost: Decimal.new("5.99"),
      zone: :us
    },
    us_express: %{
      key: "us_express",
      label: "Express Shipping",
      description: "2-3 business days",
      cost: Decimal.new("14.99"),
      zone: :us
    },
    intl_standard: %{
      key: "intl_standard",
      label: "International Standard",
      description: "10-20 business days",
      cost: Decimal.new("15.99"),
      zone: :international
    },
    intl_express: %{
      key: "intl_express",
      label: "International Express",
      description: "5-10 business days",
      cost: Decimal.new("29.99"),
      zone: :international
    }
  }

  @doc "Detect shipping zone from country string."
  def detect_zone(country) when is_binary(country) do
    normalized = country |> String.trim() |> String.downcase()

    if Enum.any?(@us_countries, fn c -> String.downcase(c) == normalized end) do
      :us
    else
      :international
    end
  end

  def detect_zone(_), do: :international

  @doc "Get available shipping rates for a zone."
  def rates_for_zone(zone) do
    @rates
    |> Enum.filter(fn {_key, rate} -> rate.zone == zone end)
    |> Enum.map(fn {_key, rate} -> rate end)
    |> Enum.sort_by(& &1.cost)
  end

  @doc "Get a specific rate by key string."
  def get_rate(key) when is_binary(key) do
    case String.to_existing_atom(key) do
      atom -> Map.get(@rates, atom)
    end
  rescue
    ArgumentError -> nil
  end

  def get_rate(_), do: nil

  @doc "Get all rates."
  def all_rates, do: @rates
end
