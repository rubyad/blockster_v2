defmodule BlocksterV2.SocialXReclaimTest do
  @moduledoc """
  Tests for the X account reclaim path in `BlocksterV2.Social.upsert_x_connection/2`.
  When a new Solana user OAuth-connects an X account that's already linked to a
  deactivated legacy user, the lock + Mnesia row should transfer.
  """
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Social
  alias BlocksterV2.Repo

  setup_all do
    tables = [
      {:x_connections, :set,
        [:user_id, :x_user_id, :x_username, :x_name, :x_profile_image_url,
         :access_token_encrypted, :refresh_token_encrypted, :token_expires_at,
         :scopes, :connected_at, :x_score, :followers_count, :following_count,
         :tweet_count, :listed_count, :avg_engagement_rate, :original_tweets_analyzed,
         :account_created_at, :score_calculated_at, :updated_at],
        [:x_user_id, :x_username]},
      {:x_oauth_states, :set, [:state, :user_id, :code_verifier, :redirect_path, :expires_at], []}
    ]

    for {name, type, attributes, index} <- tables do
      case :mnesia.create_table(name, [
        type: type,
        attributes: attributes,
        index: index,
        ram_copies: [node()]
      ]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^name}} -> :ok
      end
    end

    :ok
  end

  defp create_user(attrs \\ %{}) do
    base = %{
      wallet_address: "Wallet" <> Integer.to_string(System.unique_integer([:positive])),
      auth_method: "wallet"
    }

    attrs = Map.merge(base, attrs)

    {:ok, user} =
      %User{}
      |> User.changeset(attrs)
      |> Repo.insert()

    user
  end

  defp set_locked_x(user, x_user_id) do
    {:ok, updated} =
      user
      |> Ecto.Changeset.change(%{locked_x_user_id: x_user_id})
      |> Repo.update()

    updated
  end

  defp deactivate(user) do
    {:ok, updated} =
      user
      |> User.changeset(%{is_active: false})
      |> Repo.update()

    updated
  end

  defp clear_x_table do
    try do
      :mnesia.clear_table(:x_connections)
      :ok
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end

  setup do
    clear_x_table()
    :ok
  end

  test "fresh X account connects normally (no existing lock)" do
    user = create_user()

    attrs = %{
      x_user_id: "fresh_x_id",
      x_username: "fresh",
      x_name: "Fresh",
      access_token: "token",
      connected_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    assert {:ok, _conn} = Social.upsert_x_connection(user.id, attrs)

    reloaded = Repo.get!(User, user.id)
    assert reloaded.locked_x_user_id == "fresh_x_id"
  end

  test "X account already locked to a DEACTIVATED legacy user is reclaimed" do
    legacy = create_user() |> set_locked_x("xid_reclaim")

    # Insert a Mnesia row for the legacy user
    :mnesia.dirty_write({
      :x_connections,
      legacy.id,
      "xid_reclaim",
      "legacy_handle",
      "Legacy Name",
      nil,
      nil,
      nil,
      nil,
      [],
      System.system_time(:second),
      120,  # x_score
      500,
      200,
      100,
      0,
      0.05,
      30,
      nil,
      nil,
      System.system_time(:second)
    })

    legacy = deactivate(legacy)
    _ = legacy

    new_user = create_user()

    attrs = %{
      x_user_id: "xid_reclaim",
      x_username: "new_handle",
      x_name: "New Name",
      access_token: "new_token",
      connected_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    assert {:ok, _conn} = Social.upsert_x_connection(new_user.id, attrs)

    # Lock moved to new user
    reloaded_new = Repo.get!(User, new_user.id)
    assert reloaded_new.locked_x_user_id == "xid_reclaim"

    # Mnesia row moved
    [record] = :mnesia.dirty_read({:x_connections, new_user.id})
    assert elem(record, 1) == new_user.id
    assert :mnesia.dirty_read({:x_connections, legacy.id}) == []
  end

  test "X account locked to an ACTIVE other user is blocked" do
    other = create_user() |> set_locked_x("xid_active_block")

    new_user = create_user()

    attrs = %{
      x_user_id: "xid_active_block",
      x_username: "blocked",
      x_name: "Blocked",
      access_token: "tok",
      connected_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    assert {:error, :x_account_locked} = Social.upsert_x_connection(new_user.id, attrs)

    # Other user keeps the lock
    reloaded_other = Repo.get!(User, other.id)
    assert reloaded_other.locked_x_user_id == "xid_active_block"

    # New user has nothing
    reloaded_new = Repo.get!(User, new_user.id)
    assert reloaded_new.locked_x_user_id == nil
  end
end
