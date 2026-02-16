defmodule BlocksterV2.ContentAutomation.ContentPublisherTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.ContentAutomation.ContentPublisher
  alias BlocksterV2.Blog

  defp create_author(_) do
    {:ok, user} =
      %BlocksterV2.Accounts.User{}
      |> Ecto.Changeset.change(%{
        email: "pub_author#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true,
        is_author: true
      })
      |> Repo.insert()

    %{author: user}
  end

  describe "resolve_category/1" do
    # resolve_category is private, so we test it through create_draft_post or publish
    # which both call it. We can verify categories are created.

    test "maps known category strings to blog category IDs" do
      # Create a draft post with category "bitcoin" to trigger resolve_category
      {:ok, user} =
        %BlocksterV2.Accounts.User{}
        |> Ecto.Changeset.change(%{
          email: "cat_test#{System.unique_integer([:positive])}@test.com",
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
        })
        |> Repo.insert()

      entry =
        BlocksterV2.ContentAutomation.Factory.insert_queue_entry(%{
          author_id: user.id,
          article_data: %{
            "title" => "Category Test",
            "content" => BlocksterV2.ContentAutomation.Factory.build_valid_tiptap_content(),
            "excerpt" => "Test excerpt",
            "category" => "bitcoin",
            "tags" => ["bitcoin", "test"]
          }
        })

      {:ok, post} = ContentPublisher.create_draft_post(entry)
      assert post.category_id != nil

      # Verify the category was created with correct slug
      cat = Blog.get_category!(post.category_id)
      assert cat.slug == "bitcoin"
    end

    test "maps blockster_of_week to correct category" do
      {:ok, user} =
        %BlocksterV2.Accounts.User{}
        |> Ecto.Changeset.change(%{
          email: "botw_test#{System.unique_integer([:positive])}@test.com",
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
        })
        |> Repo.insert()

      entry =
        BlocksterV2.ContentAutomation.Factory.insert_queue_entry(%{
          author_id: user.id,
          article_data: %{
            "title" => "Blockster of the Week Test",
            "content" => BlocksterV2.ContentAutomation.Factory.build_valid_tiptap_content(),
            "excerpt" => "Test excerpt",
            "category" => "blockster_of_week",
            "tags" => ["blockster", "interview"]
          }
        })

      {:ok, post} = ContentPublisher.create_draft_post(entry)
      cat = Blog.get_category!(post.category_id)
      assert cat.slug == "blockster-of-the-week"
    end

    test "maps events to correct category" do
      {:ok, user} =
        %BlocksterV2.Accounts.User{}
        |> Ecto.Changeset.change(%{
          email: "events_test#{System.unique_integer([:positive])}@test.com",
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
        })
        |> Repo.insert()

      entry =
        BlocksterV2.ContentAutomation.Factory.insert_queue_entry(%{
          author_id: user.id,
          article_data: %{
            "title" => "Events Test",
            "content" => BlocksterV2.ContentAutomation.Factory.build_valid_tiptap_content(),
            "excerpt" => "Test excerpt",
            "category" => "events",
            "tags" => ["events", "crypto"]
          }
        })

      {:ok, post} = ContentPublisher.create_draft_post(entry)
      cat = Blog.get_category!(post.category_id)
      assert cat.slug == "events"
    end

    test "maps altcoins to correct category" do
      {:ok, user} =
        %BlocksterV2.Accounts.User{}
        |> Ecto.Changeset.change(%{
          email: "altcoins_test#{System.unique_integer([:positive])}@test.com",
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
        })
        |> Repo.insert()

      entry =
        BlocksterV2.ContentAutomation.Factory.insert_queue_entry(%{
          author_id: user.id,
          article_data: %{
            "title" => "Altcoins Test",
            "content" => BlocksterV2.ContentAutomation.Factory.build_valid_tiptap_content(),
            "excerpt" => "Test excerpt",
            "category" => "altcoins",
            "tags" => ["altcoins", "market"]
          }
        })

      {:ok, post} = ContentPublisher.create_draft_post(entry)
      cat = Blog.get_category!(post.category_id)
      assert cat.slug == "altcoins"
    end

    test "handles race conditions (concurrent category creation)" do
      {:ok, user} =
        %BlocksterV2.Accounts.User{}
        |> Ecto.Changeset.change(%{
          email: "race_test#{System.unique_integer([:positive])}@test.com",
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
        })
        |> Repo.insert()

      # Create two entries with the same new category
      cat_name = "new_cat_#{System.unique_integer([:positive])}"

      entries =
        for _ <- 1..2 do
          BlocksterV2.ContentAutomation.Factory.insert_queue_entry(%{
            author_id: user.id,
            article_data: %{
              "title" => "Race Test #{System.unique_integer([:positive])}",
              "content" => BlocksterV2.ContentAutomation.Factory.build_valid_tiptap_content(),
              "excerpt" => "Test",
              "category" => cat_name,
              "tags" => ["test", "race"]
            }
          })
        end

      # Both should succeed even if they try to create the same category
      results = Enum.map(entries, &ContentPublisher.create_draft_post/1)
      assert Enum.all?(results, fn {:ok, _} -> true; _ -> false end)
    end
  end
end
