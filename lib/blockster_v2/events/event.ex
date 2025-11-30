defmodule BlocksterV2.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :title, :string
    field :slug, :string
    field :address, :string
    field :city, :string
    field :country, :string
    field :date, :date
    field :time, :time
    field :unix_time, :integer
    field :price, :decimal
    field :ticket_supply, :integer
    field :status, :string, default: "draft"
    field :description, :string
    field :featured_image, :string

    belongs_to :organizer, BlocksterV2.Accounts.User
    belongs_to :hub, BlocksterV2.Blog.Hub

    many_to_many :attendees, BlocksterV2.Accounts.User,
      join_through: "event_attendees",
      on_replace: :delete

    many_to_many :tags, BlocksterV2.Blog.Tag,
      join_through: "event_tags",
      on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :title,
      :slug,
      :address,
      :city,
      :country,
      :date,
      :time,
      :unix_time,
      :price,
      :ticket_supply,
      :status,
      :description,
      :featured_image,
      :organizer_id,
      :hub_id
    ])
    |> validate_required([:title, :slug, :organizer_id])
    |> unique_constraint(:slug)
    |> validate_inclusion(:status, ["draft", "published", "cancelled"])
    |> maybe_generate_slug()
  end

  defp maybe_generate_slug(changeset) do
    if get_field(changeset, :slug) do
      changeset
    else
      case get_change(changeset, :title) do
        nil ->
          changeset

        title ->
          slug = title |> String.downcase() |> String.replace(~r/[^\w-]+/, "-")
          put_change(changeset, :slug, slug)
      end
    end
  end
end
