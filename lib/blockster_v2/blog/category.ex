defmodule BlocksterV2.Blog.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :slug, :string
    field :description, :string

    has_many :posts, BlocksterV2.Blog.Post

    timestamps()
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :description])
    |> validate_required([:name, :slug])
    |> unique_constraint(:name)
    |> unique_constraint(:slug)
  end
end
