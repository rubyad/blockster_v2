defmodule BlocksterV2.Repo.Migrations.RemoveTimestampsFromPostTags do
  use Ecto.Migration

  def change do
    alter table(:post_tags) do
      remove :inserted_at
      remove :updated_at
    end
  end
end
