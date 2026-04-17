defmodule BlocksterV2.Ads do
  @moduledoc """
  The Ads context for managing ad banners.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.Ads.Banner

  @doc """
  Returns all banners ordered by name.
  """
  def list_banners do
    Banner
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Returns only active banners ordered by name.
  """
  def list_active_banners do
    Banner
    |> where([b], b.is_active == true)
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Returns active banners for a specific placement.
  """
  def list_active_banners_by_placement(placement) do
    Banner
    |> where([b], b.is_active == true and b.placement == ^placement)
    |> order_by([b], [asc: b.sort_order, asc: b.name])
    |> Repo.all()
  end

  @doc """
  Returns all active banners that have a widget_type set.

  Used by the real-time widget pollers (WidgetSelector) to determine which
  banners need a fresh self-selection pick on every poll cycle.
  """
  def list_widget_banners do
    Banner
    |> where([b], b.is_active == true and not is_nil(b.widget_type))
    |> Repo.all()
  end

  @doc """
  Returns the ad class of a banner — a coarse family identifier used by the
  homepage + article-inline rotators to prevent the same class appearing in
  adjacent slots.

  Classes are prefix-based: any `rt_*` widget is `:rt`, any `cf_*` widget is
  `:cf`, any `fs_*` is `:fs`, any template containing `luxury_car` is `:car`,
  etc. Unrecognised banners fall through to `{:widget, name}` or
  `{:template, name}` so they still dedupe self-consistently.
  """
  # Same-brand ads using different templates (e.g. Moonpay's dark_gradient
  # "Buy SOL" and split_card "Bottom CTA") dedupe together — checked before
  # the generic widget/template classifications below.
  def banner_class(%{params: %{"brand_name" => "Moonpay"}}), do: :moonpay

  def banner_class(%{widget_type: t}) when is_binary(t) and t != "" do
    cond do
      String.starts_with?(t, "rt_") -> :rt
      String.starts_with?(t, "cf_") -> :cf
      String.starts_with?(t, "fs_") -> :fs
      true -> {:widget, t}
    end
  end

  def banner_class(%{template: t}) when is_binary(t) and t != "" do
    cond do
      String.contains?(t, "luxury_car") -> :car
      String.contains?(t, "jet_card") -> :jet
      String.contains?(t, "luxury_watch") -> :watch
      true -> {:template, t}
    end
  end

  def banner_class(%{link_url: url}) when is_binary(url) and url != "", do: url
  def banner_class(%{id: id}), do: id

  @doc """
  Builds a rotation sequence for homepage / inline ad slots that satisfies
  two rules:

    1. Each slot is a **random banner** from its class group (so with 10
       watches at the same placement, different watches show in different
       slots on the same page).
    2. Ad classes rotate round-robin in a random order that's fixed for the
       page mount — so **no class repeats within any K-slot window**, where
       K = number of distinct classes in the pool (typically 5).

  Given a pool of `N` banners spanning `K` classes and a desired output
  `length`, returns a list of `length` banner maps. Class cycle is shuffled
  fresh per mount, and within each class slot the specific banner is
  re-picked from the class group (so Rolex Submariner might appear at slot
  4, Day-Date 40 at slot 9, GMT at slot 14, etc.).

  The default length of 20 is plenty for typical infinite-scroll sessions —
  modulo wrap-around still lands on the same class cycle so the no-repeat
  rule holds indefinitely.
  """
  def random_class_rotated_pool(banners, length \\ 20) do
    groups = Enum.group_by(banners, &banner_class/1)

    case Map.keys(groups) do
      [] ->
        []

      classes ->
        # Extend the cycle to a multiple of class count so modulo wrap in
        # the render layer doesn't cause same-class collisions at the boundary.
        cycle_size = Kernel.length(classes)
        final_length = div(length + cycle_size - 1, cycle_size) * cycle_size
        class_order = Enum.shuffle(classes)

        for slot <- 0..(final_length - 1) do
          class = Enum.at(class_order, rem(slot, cycle_size))
          Enum.random(groups[class])
        end
    end
  end

  @doc """
  Gets a single banner. Raises if not found.
  """
  def get_banner!(id), do: Repo.get!(Banner, id)

  @doc """
  Creates a banner.
  """
  def create_banner(attrs \\ %{}) do
    %Banner{}
    |> Banner.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a banner.
  """
  def update_banner(%Banner{} = banner, attrs) do
    banner
    |> Banner.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a banner.
  """
  def delete_banner(%Banner{} = banner) do
    Repo.delete(banner)
  end

  @doc """
  Atomically increments the impressions count for a banner.
  Accepts either a %Banner{} struct or an integer id.
  """
  def increment_impressions(%Banner{id: id}), do: increment_impressions(id)

  def increment_impressions(id) when is_integer(id) do
    case Repo.update_all(
           from(b in Banner, where: b.id == ^id, select: b),
           inc: [impressions: 1]
         ) do
      {1, [updated]} -> {:ok, updated}
      {0, _} -> {:error, :not_found}
    end
  end

  @doc """
  Atomically increments the clicks count for a banner.
  Accepts either a %Banner{} struct or an integer id.
  """
  def increment_clicks(%Banner{id: id}), do: increment_clicks(id)

  def increment_clicks(id) when is_integer(id) do
    case Repo.update_all(
           from(b in Banner, where: b.id == ^id, select: b),
           inc: [clicks: 1]
         ) do
      {1, [updated]} -> {:ok, updated}
      {0, _} -> {:error, :not_found}
    end
  end

  @doc """
  Toggles the is_active flag on a banner.
  """
  def toggle_active(%Banner{} = banner) do
    banner
    |> Banner.changeset(%{is_active: !banner.is_active})
    |> Repo.update()
  end
end
