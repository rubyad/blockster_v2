defmodule BlocksterV2.Repo.Migrations.AddVideoFieldsToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :video_url, :string               # YouTube URL (e.g., https://youtube.com/watch?v=abc123)
      add :video_id, :string                # Extracted YouTube ID (e.g., abc123)
      add :video_duration, :integer         # Duration in seconds (from YouTube API)
      add :video_bux_per_minute, :decimal, default: 1.0  # BUX earned per minute of watching
      add :video_max_reward, :decimal       # Maximum BUX earnable from this video (optional cap)
    end

    create index(:posts, [:video_id])
  end
end
