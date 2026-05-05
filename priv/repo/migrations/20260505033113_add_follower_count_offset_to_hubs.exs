defmodule BlocksterV2.Repo.Migrations.AddFollowerCountOffsetToHubs do
  use Ecto.Migration

  def up do
    alter table(:hubs) do
      add :follower_count_offset, :integer, default: 0, null: false
    end

    flush()

    execute("""
      DELETE FROM hub_followers hf
      USING users u
      WHERE hf.user_id = u.id
        AND u.is_bot = true
        AND hf.notify_new_posts = false
        AND hf.notify_events = false
        AND hf.email_notifications = false
        AND hf.in_app_notifications = false
    """)
  end

  def down do
    alter table(:hubs) do
      remove :follower_count_offset
    end
  end
end
