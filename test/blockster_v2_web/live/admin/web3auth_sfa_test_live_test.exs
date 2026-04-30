defmodule BlocksterV2Web.Admin.Web3AuthSfaTestLiveTest do
  @moduledoc """
  Phase 0 parity-test admin LV. Mirrors `BannersAdminWidgetTest` —
  full LiveView session testing is gated behind the admin auth pipeline
  (UserAuth + AdminAuth + several other on_mount hooks), so here we
  cover the public helpers the LV uses for lookup, JWT building, and
  result comparison.
  """
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Repo
  alias BlocksterV2Web.Admin.Web3AuthSfaTestLive

  describe "find_user/1" do
    test "empty string returns :not_found" do
      assert Web3AuthSfaTestLive.find_user("") == {:error, :not_found}
    end

    test "whitespace-only returns :not_found" do
      assert Web3AuthSfaTestLive.find_user("   ") == {:error, :not_found}
    end

    test "non-binary input returns :not_found" do
      assert Web3AuthSfaTestLive.find_user(nil) == {:error, :not_found}
      assert Web3AuthSfaTestLive.find_user(123) == {:error, :not_found}
      assert Web3AuthSfaTestLive.find_user(%{}) == {:error, :not_found}
    end

    test "looks up by email when input contains @" do
      user = insert_user(email: "find-by-email@example.com")
      assert {:ok, found} = Web3AuthSfaTestLive.find_user("find-by-email@example.com")
      assert found.id == user.id
    end

    test "email lookup returns :not_found if no user matches" do
      assert Web3AuthSfaTestLive.find_user("nobody@example.com") == {:error, :not_found}
    end

    test "looks up by id when input is purely numeric" do
      user = insert_user(email: "find-by-id@example.com")
      assert {:ok, found} = Web3AuthSfaTestLive.find_user(Integer.to_string(user.id))
      assert found.id == user.id
    end

    test "id lookup returns :not_found for unknown id" do
      assert Web3AuthSfaTestLive.find_user("999999999") == {:error, :not_found}
    end

    test "id lookup returns :not_found for trailing junk" do
      assert Web3AuthSfaTestLive.find_user("123junk") == {:error, :not_found}
    end
  end

  describe "build_test_payload/1" do
    test "builds payload for web3auth_email user, normalizing email" do
      user = %{auth_method: "web3auth_email", email: "  Test@Example.com  "}

      assert {:ok, payload} = Web3AuthSfaTestLive.build_test_payload(user)
      assert payload.verifier == "blockster-email"
      assert payload.verifier_id == "test@example.com"
      assert is_binary(payload.id_token)

      claims = decoded_claims(payload.id_token)
      assert claims["sub"] == "test@example.com"
      assert claims["email"] == "test@example.com"
      assert claims["email_verified"] == true
      assert claims["iss"] == "blockster"
      assert claims["aud"] == "blockster-web3auth"
    end

    test "builds payload for web3auth_telegram user" do
      user = %{
        auth_method: "web3auth_telegram",
        telegram_user_id: "12345678",
        telegram_username: "alice"
      }

      assert {:ok, payload} = Web3AuthSfaTestLive.build_test_payload(user)
      assert payload.verifier == "blockster-telegram"
      assert payload.verifier_id == "12345678"

      claims = decoded_claims(payload.id_token)
      assert claims["sub"] == "12345678"
      assert claims["telegram_user_id"] == "12345678"
      assert claims["telegram_username"] == "alice"
    end

    test "telegram payload tolerates nil username" do
      user = %{
        auth_method: "web3auth_telegram",
        telegram_user_id: "999",
        telegram_username: nil
      }

      assert {:ok, payload} = Web3AuthSfaTestLive.build_test_payload(user)
      claims = decoded_claims(payload.id_token)
      assert claims["sub"] == "999"
      # nil username is preserved (Web3Auth verifier doesn't require it)
      assert Map.get(claims, "telegram_username") == nil
    end

    test "rejects wallet auth_method" do
      assert {:error, msg} = Web3AuthSfaTestLive.build_test_payload(%{auth_method: "wallet"})
      assert msg =~ "wallet"
    end

    test "rejects unknown auth_method" do
      assert {:error, msg} =
               Web3AuthSfaTestLive.build_test_payload(%{auth_method: "something_else"})

      assert msg =~ "something_else"
    end

    test "rejects email user with nil email" do
      user = %{auth_method: "web3auth_email", email: nil}
      assert {:error, msg} = Web3AuthSfaTestLive.build_test_payload(user)
      assert msg =~ "web3auth_email"
    end

    test "rejects email user with empty email" do
      user = %{auth_method: "web3auth_email", email: ""}
      assert {:error, _} = Web3AuthSfaTestLive.build_test_payload(user)
    end

    test "rejects telegram user with nil telegram_user_id" do
      user = %{
        auth_method: "web3auth_telegram",
        telegram_user_id: nil,
        telegram_username: nil
      }

      assert {:error, _} = Web3AuthSfaTestLive.build_test_payload(user)
    end

    test "rejects non-map input" do
      assert {:error, _} = Web3AuthSfaTestLive.build_test_payload(nil)
      assert {:error, _} = Web3AuthSfaTestLive.build_test_payload("not a user")
    end
  end

  describe "build_result/2" do
    test "matching pubkeys flagged as match" do
      result = Web3AuthSfaTestLive.build_result("AbCdEf123", "AbCdEf123")
      assert result.match == true
      assert result.address == "AbCdEf123"
      assert result.expected == "AbCdEf123"
    end

    test "different pubkeys flagged as mismatch" do
      result = Web3AuthSfaTestLive.build_result("derived", "expected")
      assert result.match == false
      assert result.address == "derived"
      assert result.expected == "expected"
    end

    test "nil expected does not match" do
      result = Web3AuthSfaTestLive.build_result("derived", nil)
      assert result.match == false
      assert result.address == "derived"
      assert result.expected == nil
    end

    test "case-sensitive comparison" do
      result = Web3AuthSfaTestLive.build_result("aaaa", "AAAA")
      assert result.match == false
    end
  end

  # ----------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------

  defp insert_user(attrs) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      wallet_address: random_solana_pubkey(),
      email: "sfa_test_#{unique_id}@example.com",
      username: "sfauser#{unique_id}",
      auth_method: "wallet",
      phone_verified: true
    }

    merged =
      default_attrs
      |> Map.merge(Map.new(attrs))

    %User{}
    |> User.changeset(merged)
    |> Repo.insert!()
  end

  # 32 random bytes Base58-encoded — close enough to a Solana pubkey for
  # uniqueness in tests; we never actually verify the bytes against any
  # on-chain state here.
  defp random_solana_pubkey do
    32
    |> :crypto.strong_rand_bytes()
    |> Base58.encode()
  end

  defp decoded_claims(jwt) do
    [_header, payload, _signature] = String.split(jwt, ".")

    payload
    |> Base.url_decode64!(padding: false)
    |> Jason.decode!()
  end
end
