defmodule BlocksterV2.Blog.CuratedPost do
  @moduledoc """
  Schema for curated posts - used for temporary admin curation on the homepage.

  Position is a global position in the homepage feed (1, 2, 3, etc.).
  Curated posts override the natural chronological position of posts.
  All curation is cleared when a new post is published.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "curated_posts" do
    field :position, :integer

    belongs_to :post, BlocksterV2.Blog.Post

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(curated_post, attrs) do
    curated_post
    |> cast(attrs, [:position, :post_id])
    |> validate_required([:position, :post_id])
    |> validate_number(:position, greater_than: 0)
    |> unique_constraint(:position)
  end
end
