defmodule BlocksterV2.TelegramBot.TelegramGroupMessengerTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.TelegramBot.{TelegramGroupMessenger, PromoEngine}

  describe "send_group_message/2" do
    test "returns {:error, :missing_config} when bot token is nil" do
      # In test env, bot token and channel ID are not configured
      original_token = Application.get_env(:blockster_v2, :telegram_v2_bot_token)
      original_channel = Application.get_env(:blockster_v2, :telegram_v2_channel_id)

      Application.put_env(:blockster_v2, :telegram_v2_bot_token, nil)
      Application.put_env(:blockster_v2, :telegram_v2_channel_id, nil)

      assert {:error, :missing_config} = TelegramGroupMessenger.send_group_message("<b>Test</b>")

      # Restore
      if original_token, do: Application.put_env(:blockster_v2, :telegram_v2_bot_token, original_token)
      if original_channel, do: Application.put_env(:blockster_v2, :telegram_v2_channel_id, original_channel)
    end

    test "returns {:error, :missing_config} when channel ID is nil" do
      original_token = Application.get_env(:blockster_v2, :telegram_v2_bot_token)
      original_channel = Application.get_env(:blockster_v2, :telegram_v2_channel_id)

      Application.put_env(:blockster_v2, :telegram_v2_bot_token, "fake_token")
      Application.put_env(:blockster_v2, :telegram_v2_channel_id, nil)

      assert {:error, :missing_config} = TelegramGroupMessenger.send_group_message("<b>Test</b>")

      # Restore
      if original_token do
        Application.put_env(:blockster_v2, :telegram_v2_bot_token, original_token)
      else
        Application.delete_env(:blockster_v2, :telegram_v2_bot_token)
      end
      if original_channel, do: Application.put_env(:blockster_v2, :telegram_v2_channel_id, original_channel)
    end
  end

  describe "announce_promo/1" do
    test "sends the promo announcement_html" do
      promo = %{announcement_html: "<b>Test Promo</b>"}
      # Will fail gracefully when no token configured
      result = TelegramGroupMessenger.announce_promo(promo)
      assert match?({:ok, _}, result) or result == {:error, :missing_config}
    end

    test "sends actual promo announcements without crashing" do
      # Generate a real promo from each category and verify announce doesn't crash
      for {category, templates} <- PromoEngine.all_templates() do
        template = hd(templates)
        promo = %{
          id: "test_#{category}",
          category: category,
          template: template,
          name: template.name,
          announcement_html: template[:announcement] || "<b>#{template.name}</b>",
          started_at: DateTime.utc_now(),
          expires_at: DateTime.utc_now() |> DateTime.add(3600)
        }

        result = TelegramGroupMessenger.announce_promo(promo)
        assert match?({:ok, _}, result) or result == {:error, :missing_config},
          "announce_promo crashed for #{category}/#{template.name}: #{inspect(result)}"
      end
    end
  end

  describe "announce_results/1" do
    test "sends giveaway results HTML" do
      promo = %{
        name: "BUX Rain",
        category: :giveaway,
        results: {:ok, [{1, "alice", 500}, {2, "bob", 300}]}
      }
      html = PromoEngine.format_results_html(promo, %{name: "Next Test"})
      assert html =~ "GIVEAWAY WINNERS"

      result = TelegramGroupMessenger.announce_results(html)
      assert match?({:ok, _}, result) or result == {:error, :missing_config}
    end

    test "sends competition results HTML" do
      promo = %{
        name: "Bet Count Champion",
        category: :competition,
        results: {:ok, [{1, "player1", 750}, {2, "player2", 450}, {3, "player3", 300}]}
      }
      html = PromoEngine.format_results_html(promo, nil)
      assert html =~ "RESULTS"
      assert html =~ "@player1"

      result = TelegramGroupMessenger.announce_results(html)
      assert match?({:ok, _}, result) or result == {:error, :missing_config}
    end
  end

  describe "send_update/1" do
    test "sends budget exhausted message" do
      msg = "<b>Daily Rewards Complete!</b>\n\nToday's BUX budget has been distributed!"
      result = TelegramGroupMessenger.send_update(msg)
      assert match?({:ok, _}, result) or result == {:error, :missing_config}
    end
  end
end
