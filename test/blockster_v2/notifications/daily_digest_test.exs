defmodule BlocksterV2.Notifications.DailyDigestTest do
  use BlocksterV2.DataCase, async: false
  use Oban.Testing, repo: BlocksterV2.Repo

  alias BlocksterV2.{Notifications, Repo, Blog}
  alias BlocksterV2.Workers.DailyDigestWorker
  alias BlocksterV2.Notifications.EmailLog

  # ============ Test Helpers ============

  defp create_user(attrs \\ %{}) do
    wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"

    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: wallet,
        chain_id: 560013
      })

    email = Map.get(attrs, :email, "user_#{user.id}@test.com")
    username = Map.get(attrs, :username, "TestUser#{user.id}")

    user
    |> Ecto.Changeset.change(%{email: email, username: username})
    |> Repo.update!()
  end

  defp create_user_with_prefs(user_attrs \\ %{}, pref_overrides \\ %{}) do
    user = create_user(user_attrs)
    {:ok, prefs} = Notifications.get_or_create_preferences(user.id)

    if pref_overrides != %{} do
      {:ok, prefs} = Notifications.update_preferences(user.id, pref_overrides)
      {user, prefs}
    else
      {user, prefs}
    end
  end

  defp create_hub do
    n = System.unique_integer([:positive])

    {:ok, hub} =
      Blog.create_hub(%{
        name: "Test Hub #{n}",
        slug: "test-hub-#{n}",
        tag_name: "test#{n}",
        description: "A test hub"
      })

    hub
  end

  defp create_post(hub, attrs \\ %{}) do
    {user, _prefs} = create_user_with_prefs()
    n = System.unique_integer([:positive])

    default_attrs = %{
      title: "Test Post #{n}",
      slug: "test-post-#{n}",
      excerpt: "This is a test post excerpt.",
      published_at: DateTime.utc_now() |> DateTime.truncate(:second),
      hub_id: hub.id,
      author_id: user.id
    }

    {:ok, post} = Blog.create_post(Map.merge(default_attrs, attrs))
    post
  end

  # ============ Batch Job Tests ============
  # Note: batch perform calls Oban.insert for per-user jobs. In inline test mode,
  # those inner inserts execute on a separate DB connection outside the sandbox.
  # So we test batch logic via per-user perform instead.

  describe "batch perform (cron trigger)" do
    test "returns :ok with no published posts" do
      # No posts exist — batch should return :ok without enqueuing anything
      result = perform_job(DailyDigestWorker, %{})
      assert result == :ok
    end

    test "enqueue_digest inserts a batch job" do
      # enqueue_digest is the public API for triggering the batch
      assert {:ok, %Oban.Job{args: args}} = DailyDigestWorker.enqueue_digest()
      assert args == %{}
    end
  end

  # ============ Per-User Job Tests ============

  describe "per-user perform" do
    test "sends email and creates email_log with metadata" do
      hub = create_hub()
      post = create_post(hub)
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(DailyDigestWorker, %{user_id: user.id, post_ids: [post.id]})
      assert result == :ok

      logs = Repo.all(from(el in EmailLog, where: el.user_id == ^user.id and el.email_type == "daily_digest"))
      assert length(logs) == 1

      log = hd(logs)
      assert log.metadata["post_ids"] == [post.id]
      assert log.subject =~ "Daily Digest"
    end

    test "dedup: second run with same posts skips (no new email)" do
      hub = create_hub()
      post = create_post(hub)
      {user, _prefs} = create_user_with_prefs()

      # First send
      assert :ok == perform_job(DailyDigestWorker, %{user_id: user.id, post_ids: [post.id]})

      # Second send with same post IDs
      assert :ok == perform_job(DailyDigestWorker, %{user_id: user.id, post_ids: [post.id]})

      # Should only have 1 email log, not 2
      logs = Repo.all(from(el in EmailLog, where: el.user_id == ^user.id and el.email_type == "daily_digest"))
      assert length(logs) == 1
    end

    test "dedup: second run with new posts sends only the new ones" do
      hub = create_hub()
      post1 = create_post(hub, %{published_at: ~U[2026-01-01 00:00:00Z]})
      post2 = create_post(hub, %{published_at: ~U[2026-01-02 00:00:00Z]})
      post3 = create_post(hub, %{published_at: ~U[2026-01-03 00:00:00Z]})
      {user, _prefs} = create_user_with_prefs()

      # First send with posts 1 and 2
      assert :ok == perform_job(DailyDigestWorker, %{user_id: user.id, post_ids: [post1.id, post2.id]})

      # Second send includes post3 as new, plus the already-sent post1 and post2
      assert :ok == perform_job(DailyDigestWorker, %{user_id: user.id, post_ids: [post1.id, post2.id, post3.id]})

      logs =
        Repo.all(
          from(el in EmailLog,
            where: el.user_id == ^user.id and el.email_type == "daily_digest",
            order_by: [asc: el.sent_at]
          )
        )

      assert length(logs) == 2

      # Second log should only contain post3
      second_log = Enum.at(logs, 1)
      assert second_log.metadata["post_ids"] == [post3.id]
    end

    test "respects email_daily_digest: false preference" do
      hub = create_hub()
      post = create_post(hub)
      {user, _prefs} = create_user_with_prefs(%{}, %{email_daily_digest: false})

      result = perform_job(DailyDigestWorker, %{user_id: user.id, post_ids: [post.id]})
      assert result == :ok

      logs = Repo.all(from(el in EmailLog, where: el.user_id == ^user.id and el.email_type == "daily_digest"))
      assert logs == []
    end

    test "respects email_enabled: false preference" do
      hub = create_hub()
      post = create_post(hub)
      {user, _prefs} = create_user_with_prefs(%{}, %{email_enabled: false})

      result = perform_job(DailyDigestWorker, %{user_id: user.id, post_ids: [post.id]})
      assert result == :ok

      logs = Repo.all(from(el in EmailLog, where: el.user_id == ^user.id and el.email_type == "daily_digest"))
      assert logs == []
    end

    test "skips users without email" do
      hub = create_hub()
      post = create_post(hub)

      # Create user without email
      wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
      {:ok, user} = BlocksterV2.Accounts.create_user_from_wallet(%{wallet_address: wallet, chain_id: 560013})
      {:ok, _prefs} = Notifications.get_or_create_preferences(user.id)

      result = perform_job(DailyDigestWorker, %{user_id: user.id, post_ids: [post.id]})
      assert result == :ok

      logs = Repo.all(from(el in EmailLog, where: el.user_id == ^user.id and el.email_type == "daily_digest"))
      assert logs == []
    end

    test "rate limiter returns :defer during quiet hours" do
      hub = create_hub()
      _post = create_post(hub)
      {user, _prefs} = create_user_with_prefs(%{}, %{quiet_hours_start: ~T[00:00:00], quiet_hours_end: ~T[23:59:00]})

      # Verify the rate limiter returns :defer (quiet hours cover almost all day)
      assert :defer = BlocksterV2.Notifications.RateLimiter.can_send?(user.id, :email, "daily_digest")
    end
  end

  # ============ Public API Tests ============

  describe "enqueue_digest/0" do
    test "public function creates a job" do
      assert {:ok, job} = DailyDigestWorker.enqueue_digest()
      assert job.worker == "BlocksterV2.Workers.DailyDigestWorker"
    end
  end
end
