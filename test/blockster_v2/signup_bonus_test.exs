defmodule BlocksterV2.SignupBonusTest do
  use BlocksterV2.DataCase

  alias BlocksterV2.{Accounts.User, Repo, SignupBonus}

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default = %{
      wallet_address: "wallet_#{unique_id}",
      smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "user#{unique_id}@example.com",
      username: "user#{unique_id}",
      auth_method: "wallet",
      phone_verified: false,
      geo_multiplier: Decimal.new("0.5"),
      geo_tier: "unverified",
      sms_opt_in: true
    }

    %User{}
    |> User.changeset(Map.merge(default, attrs))
    |> Repo.insert!()
  end

  describe "grant_to_new_user/1" do
    test "stamps signup_bonus_granted_at on first call" do
      user = create_user()
      assert is_nil(user.signup_bonus_granted_at)

      assert :ok = SignupBonus.grant_to_new_user(user)

      reloaded = Repo.get!(User, user.id)
      refute is_nil(reloaded.signup_bonus_granted_at)
    end

    test "returns :already_granted on second call (idempotent)" do
      user = create_user()
      :ok = SignupBonus.grant_to_new_user(user)

      reloaded = Repo.get!(User, user.id)
      assert :already_granted = SignupBonus.grant_to_new_user(reloaded)
    end

    test "rejects users without a wallet address" do
      user = %User{id: 1, wallet_address: nil}
      assert {:error, :no_wallet} = SignupBonus.grant_to_new_user(user)

      user2 = %User{id: 2, wallet_address: ""}
      assert {:error, :no_wallet} = SignupBonus.grant_to_new_user(user2)
    end

    test "rejects bot users" do
      user = %User{id: 1, wallet_address: "wallet_1", is_bot: true}
      assert {:error, :bot_user} = SignupBonus.grant_to_new_user(user)
    end
  end
end
