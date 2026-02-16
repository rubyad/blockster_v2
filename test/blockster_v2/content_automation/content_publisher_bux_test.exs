defmodule BlocksterV2.ContentAutomation.ContentPublisherBuxTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.ContentAutomation.ContentPublisher

  # Helper to build a TipTap doc with a specific word count
  defp doc_with_words(count) do
    words = 1..count |> Enum.map(fn _ -> "word" end) |> Enum.join(" ")

    %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => words}]}
      ]
    }
  end

  describe "calculate_bux/1" do
    test "short article (100 words): 1 min -> 2 BUX reward, 1000 BUX pool" do
      content = doc_with_words(100)
      {reward, pool} = ContentPublisher.calculate_bux(content)

      # 100/250 = 0.4 -> max(1, 0.4) = 1 -> trunc(1 * 2) = 2
      assert reward == 2
      # max(1000, 2 * 500) = 1000
      assert pool == 1000
    end

    test "medium article (500 words): 2 min -> 4 BUX reward, 2000 BUX pool" do
      content = doc_with_words(500)
      {reward, pool} = ContentPublisher.calculate_bux(content)

      # 500/250 = 2.0 -> trunc(2 * 2) = 4
      assert reward == 4
      # max(1000, 4 * 500) = 2000
      assert pool == 2000
    end

    test "long article (1000 words): 4 min -> 8 BUX reward, 4000 BUX pool" do
      content = doc_with_words(1000)
      {reward, pool} = ContentPublisher.calculate_bux(content)

      # 1000/250 = 4.0 -> trunc(4 * 2) = 8
      assert reward == 8
      # max(1000, 8 * 500) = 4000
      assert pool == 4000
    end

    test "very long article (2500 words): capped at 10 BUX, 5000 BUX pool" do
      content = doc_with_words(2500)
      {reward, pool} = ContentPublisher.calculate_bux(content)

      # 2500/250 = 10.0 -> trunc(10 * 2) = 20 -> min(20, 10) = 10
      assert reward == 10
      # max(1000, 10 * 500) = 5000
      assert pool == 5000
    end

    test "minimum reward is 1 BUX" do
      content = doc_with_words(50)
      {reward, _pool} = ContentPublisher.calculate_bux(content)

      # 50/250 = 0.2 -> max(1, 0.2) = 1 -> trunc(1 * 2) = 2 -> max(1, 2) = 2
      # Actually min word count floor means min 1 read minute -> 2 BUX
      assert reward >= 1
    end

    test "maximum reward is 10 BUX" do
      content = doc_with_words(5000)
      {reward, _pool} = ContentPublisher.calculate_bux(content)

      assert reward == 10
    end

    test "empty content (0 words): 1 min minimum -> 2 BUX reward, 1000 BUX pool" do
      content = %{"type" => "doc", "content" => []}
      {reward, pool} = ContentPublisher.calculate_bux(content)

      # 0/250 = 0 -> max(1, 0) = 1 -> trunc(1 * 2) = 2
      assert reward == 2
      # max(1000, 2 * 500) = 1000
      assert pool == 1000
    end

    test "returns {base_reward, pool_size} tuple" do
      content = doc_with_words(500)
      result = ContentPublisher.calculate_bux(content)

      assert is_tuple(result)
      assert tuple_size(result) == 2
      {reward, pool} = result
      assert is_integer(reward)
      assert is_integer(pool)
    end

    test "pool = max(1000, reward * 500)" do
      # For a tiny article, pool floor is 1000
      content_small = doc_with_words(100)
      {reward_small, pool_small} = ContentPublisher.calculate_bux(content_small)
      assert pool_small == max(1000, reward_small * 500)

      # For a larger article, pool scales
      content_large = doc_with_words(1000)
      {reward_large, pool_large} = ContentPublisher.calculate_bux(content_large)
      assert pool_large == max(1000, reward_large * 500)
    end
  end
end
