defmodule BlocksterV2.Notifications.Phase14Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Notifications
  alias BlocksterV2.Notifications.TriggerEngine

  # ============ Test Helpers ============

  defp create_user(_context \\ %{}) do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    %{user: user}
  end

  # ============ TriggerEngine Tests ============

  describe "TriggerEngine.bux_milestone_trigger/3" do
    test "fires when balance hits a milestone" do
      %{user: user} = create_user()

      result =
        TriggerEngine.bux_milestone_trigger(
          {user.id, "bux_earned", %{"new_balance" => "5200"}},
          nil,
          %{}
        )

      assert {:fire, "bux_milestone", data} = result
      assert data.milestone == 5_000
    end

    test "skips when no new_balance in metadata" do
      %{user: user} = create_user()

      result =
        TriggerEngine.bux_milestone_trigger(
          {user.id, "bux_earned", %{}},
          nil,
          %{}
        )

      assert result == :skip
    end

    test "skips when balance is too far past milestone" do
      %{user: user} = create_user()

      result =
        TriggerEngine.bux_milestone_trigger(
          {user.id, "bux_earned", %{"new_balance" => "6000"}},
          nil,
          %{}
        )

      assert result == :skip
    end

    test "skips when milestone already celebrated" do
      %{user: user} = create_user()

      # Create existing milestone notification
      Notifications.create_notification(user.id, %{
        type: "bux_milestone",
        category: "rewards",
        title: "Hit 5k!",
        metadata: %{"milestone" => "5000"}
      })

      result =
        TriggerEngine.bux_milestone_trigger(
          {user.id, "bux_earned", %{"new_balance" => "5100"}},
          nil,
          %{}
        )

      assert result == :skip
    end
  end

  describe "TriggerEngine.evaluate_triggers/3" do
    test "fires bux milestone notification" do
      %{user: user} = create_user()

      fired =
        TriggerEngine.evaluate_triggers(user.id, "bux_earned", %{
          "new_balance" => "10200"
        })

      assert "bux_milestone" in fired

      # Verify notification was created
      notifications = Notifications.list_notifications(user.id)
      assert Enum.any?(notifications, fn n -> n.type == "bux_milestone" end)
    end

    test "returns empty list when no triggers match" do
      %{user: user} = create_user()
      fired = TriggerEngine.evaluate_triggers(user.id, "article_view")
      assert fired == []
    end
  end

  describe "TriggerEngine deduplication" do
    test "does not fire duplicate BUX milestone" do
      %{user: user} = create_user()

      # First trigger
      fired1 =
        TriggerEngine.evaluate_triggers(user.id, "bux_earned", %{
          "new_balance" => "1200"
        })

      assert "bux_milestone" in fired1

      # Same milestone again should not fire
      fired2 =
        TriggerEngine.evaluate_triggers(user.id, "bux_earned", %{
          "new_balance" => "1300"
        })

      refute "bux_milestone" in fired2
    end
  end
end
