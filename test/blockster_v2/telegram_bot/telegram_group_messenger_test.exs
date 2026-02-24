defmodule BlocksterV2.TelegramBot.TelegramGroupMessengerTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.TelegramBot.TelegramGroupMessenger

  describe "send_group_message/2" do
    test "does not crash with valid HTML" do
      # In dev env with .env loaded, this will send a real message
      # In CI/prod test, it returns {:error, :missing_config}
      result = TelegramGroupMessenger.send_group_message("<b>Test message - ignore</b>")
      assert match?({:ok, _}, result) or result == {:error, :missing_config}
    end
  end

  describe "announce_promo/1" do
    test "accepts promo struct with announcement_html" do
      promo = %{announcement_html: "<b>Test</b>"}
      result = TelegramGroupMessenger.announce_promo(promo)
      assert match?({:ok, _}, result) or result == {:error, :missing_config}
    end
  end

  describe "send_update/1" do
    test "accepts text updates" do
      result = TelegramGroupMessenger.send_update("<b>Update</b>")
      assert match?({:ok, _}, result) or result == {:error, :missing_config}
    end
  end

  describe "announce_results/1" do
    test "accepts results HTML" do
      result = TelegramGroupMessenger.announce_results("<b>Results</b>")
      assert match?({:ok, _}, result) or result == {:error, :missing_config}
    end
  end
end
