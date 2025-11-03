defmodule FixTweetType do
  alias BlocksterV2.Repo
  alias BlocksterV2.Blog.Post

  def run do
    posts = Repo.all(Post)
    IO.puts("Updating #{length(posts)} posts...")

    Enum.each(posts, fn post ->
      updated_content = update_tweet_type(post.content)
      if updated_content != post.content do
        post
        |> Ecto.Changeset.change(%{content: updated_content})
        |> Repo.update()
        IO.puts("Updated post #{post.id}")
      end
    end)

    IO.puts("Done!")
  end

  defp update_tweet_type(%{"type" => "doc", "content" => content_list} = content) do
    %{content | "content" => Enum.map(content_list, &update_node_type/1)}
  end
  defp update_tweet_type(content), do: content

  defp update_node_type(%{"type" => "tweetEmbed"} = node) do
    %{node | "type" => "tweet"}
  end
  defp update_node_type(node), do: node
end

FixTweetType.run()
