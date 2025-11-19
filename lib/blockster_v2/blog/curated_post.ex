defmodule BlocksterV2.Blog.CuratedPost do
  use Ecto.Schema
  import Ecto.Changeset

  schema "curated_posts" do
    field :section, :string
    field :position, :integer

    belongs_to :post, BlocksterV2.Blog.Post

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(curated_post, attrs) do
    curated_post
    |> cast(attrs, [:section, :position, :post_id])
    |> validate_required([:section, :position])
    |> validate_inclusion(:section, ["latest_news", "conversations"])
    |> validate_number(:position, greater_than: 0)
    |> validate_position_range()
    |> unique_constraint([:section, :position])
  end

  defp validate_position_range(changeset) do
    section = get_field(changeset, :section)
    position = get_field(changeset, :position)

    case {section, position} do
      {"latest_news", p} when p > 10 ->
        add_error(changeset, :position, "must be between 1 and 10 for latest_news section")

      {"conversations", p} when p > 6 ->
        add_error(changeset, :position, "must be between 1 and 6 for conversations section")

      _ ->
        changeset
    end
  end
end
