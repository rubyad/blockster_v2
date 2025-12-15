defmodule BlocksterV2.Blog.SectionSetting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "section_settings" do
    field :section, :string
    field :title, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(section_setting, attrs) do
    section_setting
    |> cast(attrs, [:section, :title])
    |> validate_required([:section, :title])
    |> validate_length(:title, min: 1, max: 100)
    |> unique_constraint(:section)
  end
end
