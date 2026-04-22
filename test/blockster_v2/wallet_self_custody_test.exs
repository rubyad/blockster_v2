defmodule BlocksterV2.WalletSelfCustodyTest do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Repo
  alias BlocksterV2.WalletSelfCustody

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])
    # Build a unique base58-looking pubkey so each test user gets a
    # distinct wallet_address. Solana pubkeys are 32-44 base58 chars.
    pubkey =
      :crypto.strong_rand_bytes(32)
      |> Base.encode32(case: :lower, padding: false)
      |> String.replace(~r/[0il]/, "A")
      |> String.slice(0, 44)

    default_attrs = %{
      "wallet_address" => pubkey,
      "email" => "wallet_test_#{unique_id}@example.com",
      "username" => "walletuser#{unique_id}",
      "auth_method" => "web3auth_email"
    }

    merged = Map.merge(default_attrs, Map.new(attrs, fn {k, v} -> {to_string(k), v} end))

    User.web3auth_registration_changeset(merged) |> Repo.insert!()
  end

  describe "log_event/3" do
    test "persists a valid event with metadata" do
      user = create_user()

      assert {:ok, event} =
               WalletSelfCustody.log_event(user.id, :withdrawal_initiated,
                 metadata: %{amount: "0.5", to: "ABCD"},
                 ip: "127.0.0.1",
                 user_agent: "test"
               )

      assert event.user_id == user.id
      assert event.event_type == "withdrawal_initiated"
      assert event.metadata["amount"] == "0.5"
      assert event.metadata["to"] == "ABCD"
      assert event.ip_address == "127.0.0.1"
    end

    test "accepts string event types too" do
      user = create_user()
      assert {:ok, event} = WalletSelfCustody.log_event(user.id, "key_exported")
      assert event.event_type == "key_exported"
    end

    test "rejects unknown event types" do
      user = create_user()

      assert {:error, changeset} =
               WalletSelfCustody.log_event(user.id, :totally_invalid_type)

      assert {"is invalid", _} = changeset.errors[:event_type]
    end

    test "rejects metadata containing private key material" do
      user = create_user()

      assert {:error, changeset} =
               WalletSelfCustody.log_event(user.id, :key_exported,
                 metadata: %{private_key: "leaked"}
               )

      assert Keyword.has_key?(changeset.errors, :metadata)
    end

    test "rejects metadata with secretKey / seed / mnemonic" do
      user = create_user()

      for banned <- ~w(secret_key seed mnemonic secretKey privateKey) do
        assert {:error, changeset} =
                 WalletSelfCustody.log_event(user.id, :key_exported,
                   metadata: %{banned => "leaked"}
                 )

        assert Keyword.has_key?(changeset.errors, :metadata),
               "expected #{banned} to be rejected"
      end
    end
  end

  describe "list_recent_for_user/2" do
    test "returns events newest-first, limited" do
      user = create_user()

      {:ok, _} = WalletSelfCustody.log_event(user.id, :withdrawal_initiated)
      Process.sleep(1100)
      {:ok, _} = WalletSelfCustody.log_event(user.id, :withdrawal_confirmed)
      Process.sleep(1100)
      {:ok, _} = WalletSelfCustody.log_event(user.id, :key_exported)

      events = WalletSelfCustody.list_recent_for_user(user.id, 10)
      assert length(events) == 3
      assert Enum.map(events, & &1.event_type) == [
               "key_exported",
               "withdrawal_confirmed",
               "withdrawal_initiated"
             ]
    end

    test "respects the limit" do
      user = create_user()

      for _ <- 1..5 do
        WalletSelfCustody.log_event(user.id, :withdrawal_initiated)
      end

      assert length(WalletSelfCustody.list_recent_for_user(user.id, 2)) == 2
    end

    test "only returns events for that user" do
      user_a = create_user()
      user_b = create_user()

      {:ok, _} = WalletSelfCustody.log_event(user_a.id, :withdrawal_initiated)
      {:ok, _} = WalletSelfCustody.log_event(user_b.id, :key_exported)

      assert [%{event_type: "withdrawal_initiated"}] =
               WalletSelfCustody.list_recent_for_user(user_a.id, 10)

      assert [%{event_type: "key_exported"}] =
               WalletSelfCustody.list_recent_for_user(user_b.id, 10)
    end
  end

  describe "count_recent_for_user/3" do
    test "counts events of one type within the window" do
      user = create_user()

      for _ <- 1..3 do
        WalletSelfCustody.log_event(user.id, :key_exported)
      end

      {:ok, _} = WalletSelfCustody.log_event(user.id, :withdrawal_initiated)

      assert WalletSelfCustody.count_recent_for_user(user.id, :key_exported, 60) == 3
      assert WalletSelfCustody.count_recent_for_user(user.id, :withdrawal_initiated, 60) == 1
      assert WalletSelfCustody.count_recent_for_user(user.id, :withdrawal_failed, 60) == 0
    end
  end
end
