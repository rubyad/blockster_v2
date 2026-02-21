defmodule BlocksterV2.Notifications.Phase2Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.HubFollower

  # ============ Test Helpers ============

  defp create_user(_context \\ %{}) do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    %{user: user}
  end

  defp create_hub(_context \\ %{}) do
    unique = System.unique_integer([:positive])

    {:ok, hub} =
      Blog.create_hub(%{
        name: "Test Hub #{unique}",
        tag_name: "test_hub_#{unique}",
        slug: "test-hub-#{unique}"
      })

    %{hub: hub}
  end

  defp create_user_and_hub(_context \\ %{}) do
    %{user: user} = create_user()
    %{hub: hub} = create_hub()
    %{user: user, hub: hub}
  end

  # ============ Follow/Unfollow Tests ============

  describe "follow_hub/2" do
    test "creates a follow record" do
      %{user: user, hub: hub} = create_user_and_hub()

      assert {:ok, %HubFollower{}} = Blog.follow_hub(user.id, hub.id)
      assert Blog.user_follows_hub?(user.id, hub.id)
    end

    test "sets default notification preferences" do
      %{user: user, hub: hub} = create_user_and_hub()

      {:ok, follower} = Blog.follow_hub(user.id, hub.id)
      assert follower.notify_new_posts == true
      assert follower.notify_events == true
      assert follower.email_notifications == true
      assert follower.in_app_notifications == true
    end

    test "prevents duplicate follows" do
      %{user: user, hub: hub} = create_user_and_hub()

      assert {:ok, _} = Blog.follow_hub(user.id, hub.id)
      assert {:error, _changeset} = Blog.follow_hub(user.id, hub.id)
    end

    test "increments follower count" do
      %{hub: hub} = create_hub()
      %{user: user1} = create_user()
      %{user: user2} = create_user()

      assert Blog.get_hub_follower_count(hub.id) == 0

      Blog.follow_hub(user1.id, hub.id)
      assert Blog.get_hub_follower_count(hub.id) == 1

      Blog.follow_hub(user2.id, hub.id)
      assert Blog.get_hub_follower_count(hub.id) == 2
    end
  end

  describe "unfollow_hub/2" do
    test "removes the follow record" do
      %{user: user, hub: hub} = create_user_and_hub()

      {:ok, _} = Blog.follow_hub(user.id, hub.id)
      assert Blog.user_follows_hub?(user.id, hub.id)

      assert {:ok, _} = Blog.unfollow_hub(user.id, hub.id)
      refute Blog.user_follows_hub?(user.id, hub.id)
    end

    test "returns error if not following" do
      %{user: user, hub: hub} = create_user_and_hub()

      assert {:error, :not_found} = Blog.unfollow_hub(user.id, hub.id)
    end

    test "decrements follower count" do
      %{user: user, hub: hub} = create_user_and_hub()

      Blog.follow_hub(user.id, hub.id)
      assert Blog.get_hub_follower_count(hub.id) == 1

      Blog.unfollow_hub(user.id, hub.id)
      assert Blog.get_hub_follower_count(hub.id) == 0
    end
  end

  describe "toggle_hub_follow/2" do
    test "follows if not following" do
      %{user: user, hub: hub} = create_user_and_hub()

      assert {:ok, :followed} = Blog.toggle_hub_follow(user.id, hub.id)
      assert Blog.user_follows_hub?(user.id, hub.id)
    end

    test "unfollows if already following" do
      %{user: user, hub: hub} = create_user_and_hub()

      Blog.follow_hub(user.id, hub.id)
      assert {:ok, :unfollowed} = Blog.toggle_hub_follow(user.id, hub.id)
      refute Blog.user_follows_hub?(user.id, hub.id)
    end

    test "toggles back and forth correctly" do
      %{user: user, hub: hub} = create_user_and_hub()

      assert {:ok, :followed} = Blog.toggle_hub_follow(user.id, hub.id)
      assert Blog.user_follows_hub?(user.id, hub.id)

      assert {:ok, :unfollowed} = Blog.toggle_hub_follow(user.id, hub.id)
      refute Blog.user_follows_hub?(user.id, hub.id)

      assert {:ok, :followed} = Blog.toggle_hub_follow(user.id, hub.id)
      assert Blog.user_follows_hub?(user.id, hub.id)
    end
  end

  describe "user_follows_hub?/2" do
    test "returns false when not following" do
      %{user: user, hub: hub} = create_user_and_hub()
      refute Blog.user_follows_hub?(user.id, hub.id)
    end

    test "returns true when following" do
      %{user: user, hub: hub} = create_user_and_hub()
      Blog.follow_hub(user.id, hub.id)
      assert Blog.user_follows_hub?(user.id, hub.id)
    end
  end

  describe "get_user_followed_hub_ids/1" do
    test "returns empty list when no follows" do
      %{user: user} = create_user()
      assert Blog.get_user_followed_hub_ids(user.id) == []
    end

    test "returns hub IDs the user follows" do
      %{user: user} = create_user()
      %{hub: hub1} = create_hub()
      %{hub: hub2} = create_hub()
      %{hub: hub3} = create_hub()

      Blog.follow_hub(user.id, hub1.id)
      Blog.follow_hub(user.id, hub3.id)

      followed_ids = Blog.get_user_followed_hub_ids(user.id)
      assert length(followed_ids) == 2
      assert hub1.id in followed_ids
      assert hub3.id in followed_ids
      refute hub2.id in followed_ids
    end
  end

  describe "get_hub_follower_user_ids/1" do
    test "returns empty list when no followers" do
      %{hub: hub} = create_hub()
      assert Blog.get_hub_follower_user_ids(hub.id) == []
    end

    test "returns user IDs that follow the hub" do
      %{hub: hub} = create_hub()
      %{user: user1} = create_user()
      %{user: user2} = create_user()
      %{user: user3} = create_user()

      Blog.follow_hub(user1.id, hub.id)
      Blog.follow_hub(user2.id, hub.id)

      follower_ids = Blog.get_hub_follower_user_ids(hub.id)
      assert length(follower_ids) == 2
      assert user1.id in follower_ids
      assert user2.id in follower_ids
      refute user3.id in follower_ids
    end
  end

  describe "get_hub_followers_with_preferences/1" do
    test "returns follower records with notification prefs" do
      %{user: user, hub: hub} = create_user_and_hub()

      Blog.follow_hub(user.id, hub.id)

      followers = Blog.get_hub_followers_with_preferences(hub.id)
      assert length(followers) == 1

      follower = hd(followers)
      assert follower.user_id == user.id
      assert follower.notify_new_posts == true
      assert follower.email_notifications == true
    end
  end

  # ============ Cross-User Isolation Tests ============

  describe "follow isolation" do
    test "users have independent follows" do
      %{hub: hub} = create_hub()
      %{user: user1} = create_user()
      %{user: user2} = create_user()

      Blog.follow_hub(user1.id, hub.id)

      assert Blog.user_follows_hub?(user1.id, hub.id)
      refute Blog.user_follows_hub?(user2.id, hub.id)
    end

    test "unfollowing doesn't affect other users" do
      %{hub: hub} = create_hub()
      %{user: user1} = create_user()
      %{user: user2} = create_user()

      Blog.follow_hub(user1.id, hub.id)
      Blog.follow_hub(user2.id, hub.id)

      Blog.unfollow_hub(user1.id, hub.id)

      refute Blog.user_follows_hub?(user1.id, hub.id)
      assert Blog.user_follows_hub?(user2.id, hub.id)
    end
  end

  # ============ Multiple Hub Tests ============

  describe "following multiple hubs" do
    test "user can follow multiple hubs" do
      %{user: user} = create_user()
      %{hub: hub1} = create_hub()
      %{hub: hub2} = create_hub()
      %{hub: hub3} = create_hub()

      Blog.follow_hub(user.id, hub1.id)
      Blog.follow_hub(user.id, hub2.id)
      Blog.follow_hub(user.id, hub3.id)

      followed_ids = Blog.get_user_followed_hub_ids(user.id)
      assert length(followed_ids) == 3
    end

    test "unfollowing one hub doesn't affect others" do
      %{user: user} = create_user()
      %{hub: hub1} = create_hub()
      %{hub: hub2} = create_hub()

      Blog.follow_hub(user.id, hub1.id)
      Blog.follow_hub(user.id, hub2.id)

      Blog.unfollow_hub(user.id, hub1.id)

      refute Blog.user_follows_hub?(user.id, hub1.id)
      assert Blog.user_follows_hub?(user.id, hub2.id)
    end
  end
end
