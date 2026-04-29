defmodule BlocksterV2.Blog.HubColor do
  @moduledoc """
  Deterministic gradient picker for hub cards + show-page chrome.

  When the hub has `color_primary` and `color_secondary` set in the DB
  (admin-curated brand colors), use them as-is. When either is nil — the
  default state for hubs created without seed data — derive a stable HSL
  gradient from the hub's slug so every hub still gets a unique, distinct
  color. Same input always produces the same output, so the homepage card
  and the show page header stay visually consistent across renders without
  requiring a DB write.

  The fallback range avoids ultra-bright greens that clash with the
  `#CAFC00` brand accent and avoids near-black/white that wash out white
  text. Saturation/lightness are fixed so all hubs share a similar
  visual weight.
  """

  @doc """
  Returns `{primary_hex, secondary_hex}` for a hub.

  Accepts either a `%Hub{}` struct or any map with `:color_primary`,
  `:color_secondary`, and `:slug` (or `:name` as a slug fallback).
  """
  def gradient(hub) do
    case {nil_or_blank(hub_field(hub, :color_primary)), nil_or_blank(hub_field(hub, :color_secondary))} do
      {{:ok, p}, {:ok, s}} -> {p, s}
      _ -> derive(hub)
    end
  end

  @doc "Returns just the primary color — convenience for places that don't need both."
  def primary(hub) do
    {p, _s} = gradient(hub)
    p
  end

  defp hub_field(hub, key) when is_map(hub), do: Map.get(hub, key) || Map.get(hub, Atom.to_string(key))
  defp hub_field(_, _), do: nil

  defp nil_or_blank(nil), do: :missing
  defp nil_or_blank(""), do: :missing
  defp nil_or_blank(v) when is_binary(v), do: {:ok, v}
  defp nil_or_blank(_), do: :missing

  # Hash the slug into a hue (0–360). Saturation and lightness are fixed so
  # every fallback color sits in the same visual band — no near-white, no
  # near-black, no neon. Secondary is the same hue darkened ~12% lightness.
  defp derive(hub) do
    seed = hub_field(hub, :slug) || hub_field(hub, :name) || ""
    hue = :erlang.phash2(seed, 360)
    primary = hsl_to_hex(hue, 70, 52)
    secondary = hsl_to_hex(hue, 70, 40)
    {primary, secondary}
  end

  # HSL → RGB → hex. h: 0..360, s/l: 0..100.
  defp hsl_to_hex(h, s, l) do
    s_frac = s / 100
    l_frac = l / 100
    c = (1 - abs(2 * l_frac - 1)) * s_frac
    x = c * (1 - abs(:math.fmod(h / 60, 2) - 1))
    m = l_frac - c / 2

    {r, g, b} =
      cond do
        h < 60 -> {c, x, 0.0}
        h < 120 -> {x, c, 0.0}
        h < 180 -> {0.0, c, x}
        h < 240 -> {0.0, x, c}
        h < 300 -> {x, 0.0, c}
        true -> {c, 0.0, x}
      end

    "#" <>
      hex(round((r + m) * 255)) <>
      hex(round((g + m) * 255)) <>
      hex(round((b + m) * 255))
  end

  defp hex(n) do
    n
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
    |> String.upcase()
  end
end
