defmodule BlocksterV2Web.OnboardingLive.StepFilterTest do
  @moduledoc """
  Unit tests for Phase 6 onboarding step filtering.

  Verifies that web3auth_* users skip the step matching the identity they
  signed in with (email / x) and all web3auth_* users skip migrate_email
  since they are new accounts.
  """
  use ExUnit.Case, async: true

  alias BlocksterV2Web.OnboardingLive.Index

  describe "build_steps_for_user/1" do
    # `migrate_email` was retired — existing Blockster accounts now reclaim
    # via the Web3Auth email flow (server-side merge), not via a wallet
    # connect + email OTP step. No flow exposes that step anymore.

    test "wallet user sees full base flow without migrate_email" do
      user = %{auth_method: "wallet"}
      steps = Index.build_steps_for_user(user)

      assert "welcome" in steps
      refute "migrate_email" in steps
      assert "email" in steps
      assert "x" in steps
      assert "complete" in steps
    end

    test "legacy email user sees the same base flow" do
      user = %{auth_method: "email"}
      steps = Index.build_steps_for_user(user)

      refute "migrate_email" in steps
      assert "email" in steps
      assert "x" in steps
    end

    test "web3auth_email user skips only email" do
      user = %{auth_method: "web3auth_email"}
      steps = Index.build_steps_for_user(user)

      refute "email" in steps
      assert "x" in steps
      assert "phone" in steps
      assert "complete" in steps
    end

    test "web3auth_x user skips only x" do
      user = %{auth_method: "web3auth_x"}
      steps = Index.build_steps_for_user(user)

      refute "x" in steps
      assert "email" in steps
      assert "phone" in steps
    end

    test "web3auth_telegram user sees every step" do
      user = %{auth_method: "web3auth_telegram"}
      steps = Index.build_steps_for_user(user)

      assert "email" in steps
      assert "x" in steps
      assert "phone" in steps
    end

    test "unknown auth method falls back to full flow" do
      user = %{auth_method: "mystery"}
      steps = Index.build_steps_for_user(user)

      assert "email" in steps
      assert "x" in steps
    end

    test "nil user falls back to full flow" do
      assert "welcome" in Index.build_steps_for_user(nil)
      refute "migrate_email" in Index.build_steps_for_user(nil)
    end

    test "preserves ordering: welcome first, complete last" do
      for auth <- ~w(wallet web3auth_email web3auth_x web3auth_telegram) do
        steps = Index.build_steps_for_user(%{auth_method: auth})
        assert List.first(steps) == "welcome"
        assert List.last(steps) == "complete"
      end
    end
  end

  describe "next_unfilled_step/2 respects auth-method filter" do
    test "web3auth_email user from welcome never lands on email step" do
      user = %{
        id: 1,
        auth_method: "web3auth_email",
        username: "adam",
        phone_verified: true,
        email_verified: true
      }

      next = Index.next_unfilled_step(user, "welcome")
      refute next == "email"
    end

    test "web3auth_x user from welcome skips x step when walking forward" do
      user = %{
        id: 1,
        auth_method: "web3auth_x",
        username: "adam",
        phone_verified: true,
        email_verified: true
      }

      # With phone + email + username filled, the only remaining step is complete
      # (x is filtered out for this auth_method).
      assert Index.next_unfilled_step(user, "profile") == "complete"
    end
  end
end
