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
    |> validate_inclusion(:section, ["latest_news", "conversations", "posts_three", "posts_four", "posts_five", "posts_six"])
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

      {"posts_three", p} when p > 5 ->
        add_error(changeset, :position, "must be between 1 and 5 for posts_three section")

      {"posts_four", p} when p > 3 ->
        add_error(changeset, :position, "must be between 1 and 3 for posts_four section")

      {"posts_five", p} when p > 6 ->
        add_error(changeset, :position, "must be between 1 and 6 for posts_five section")

      {"posts_six", p} when p > 5 ->
        add_error(changeset, :position, "must be between 1 and 5 for posts_six section")

      _ ->
        changeset
    end
  end
end
