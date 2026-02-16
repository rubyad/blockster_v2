defmodule BlocksterV2.ContentAutomation.FeedStoreSchedulingTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.ContentAutomation.FeedStore
  import BlocksterV2.ContentAutomation.Factory

  defp create_author(_) do
    {:ok, user} =
      %BlocksterV2.Accounts.User{}
      |> Ecto.Changeset.change(%{
        email: "sched_author#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
      })
      |> Repo.insert()

    %{author: user}
  end

  describe "update_queue_entry_scheduled_at/2" do
    setup [:create_author]

    test "persists scheduled_at datetime", %{author: author} do
      entry = insert_queue_entry(%{status: "approved", author_id: author.id})
      scheduled = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      {:ok, updated} = FeedStore.update_queue_entry(entry.id, %{scheduled_at: scheduled})

      assert updated.scheduled_at == scheduled
    end

    test "overwrites previous scheduled_at", %{author: author} do
      first = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      second = DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.truncate(:second)

      entry = insert_queue_entry(%{status: "approved", author_id: author.id, scheduled_at: first})

      {:ok, updated} = FeedStore.update_queue_entry(entry.id, %{scheduled_at: second})
      assert updated.scheduled_at == second
    end
  end

  describe "approved entries ready to publish" do
    setup [:create_author]

    test "approved entries with past scheduled_at are returned by get_queue_entries", %{author: author} do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      insert_queue_entry(%{status: "approved", author_id: author.id, scheduled_at: past})

      entries = FeedStore.get_queue_entries(status: "approved")
      assert length(entries) >= 1
    end

    test "approved entries with nil scheduled_at are returned by get_queue_entries", %{author: author} do
      insert_queue_entry(%{status: "approved", author_id: author.id, scheduled_at: nil})

      entries = FeedStore.get_queue_entries(status: "approved")
      assert length(entries) >= 1
    end

    test "non-approved entries are excluded", %{author: author} do
      insert_queue_entry(%{status: "pending", author_id: author.id})

      entries = FeedStore.get_queue_entries(status: "approved")
      assert Enum.all?(entries, &(&1.status == "approved"))
    end
  end
end
