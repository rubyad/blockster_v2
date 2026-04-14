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
  """
  def increment_impressions(%Banner{} = banner) do
    {1, [updated]} =
      from(b in Banner, where: b.id == ^banner.id, select: b)
      |> Repo.update_all(inc: [impressions: 1])

    {:ok, updated}
  end

  @doc """
  Atomically increments the clicks count for a banner.
  """
  def increment_clicks(%Banner{} = banner) do
    {1, [updated]} =
      from(b in Banner, where: b.id == ^banner.id, select: b)
      |> Repo.update_all(inc: [clicks: 1])

    {:ok, updated}
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
