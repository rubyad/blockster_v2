defmodule BlocksterV2.EmailMultiplierTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.EmailMultiplier

  describe "calculate/1" do
    test "returns 2.0x for verified email" do
      assert EmailMultiplier.calculate(%{email_verified: true}) == 2.0
    end

    test "returns 0.5x for unverified email" do
      assert EmailMultiplier.calculate(%{email_verified: false}) == 0.5
    end

    test "returns 0.5x for nil email_verified" do
      assert EmailMultiplier.calculate(%{email_verified: nil}) == 0.5
    end

    test "returns 0.5x for nil input" do
      assert EmailMultiplier.calculate(nil) == 0.5
    end

    test "returns 0.5x for empty map" do
      assert EmailMultiplier.calculate(%{}) == 0.5
    end

    test "returns 0.5x for string input" do
      assert EmailMultiplier.calculate("user") == 0.5
    end

    test "works with full user struct that has email_verified field" do
      user = %{id: 1, email: "test@example.com", email_verified: true, name: "Test"}
      assert EmailMultiplier.calculate(user) == 2.0
    end

    test "works with full user struct that has false email_verified" do
      user = %{id: 1, email: "test@example.com", email_verified: false, name: "Test"}
      assert EmailMultiplier.calculate(user) == 0.5
    end
  end

  describe "calculate_for_user/1" do
    test "returns 0.5x for non-integer user_id" do
      assert EmailMultiplier.calculate_for_user(nil) == 0.5
      assert EmailMultiplier.calculate_for_user("123") == 0.5
      assert EmailMultiplier.calculate_for_user(%{}) == 0.5
    end

    test "returns 0.5x for non-existent user" do
      # User ID that doesn't exist in the database
      assert EmailMultiplier.calculate_for_user(999_999_999) == 0.5
    end
  end

  describe "verified_multiplier/0 and unverified_multiplier/0" do
    test "returns correct verified multiplier" do
      assert EmailMultiplier.verified_multiplier() == 2.0
    end

    test "returns correct unverified multiplier" do
      assert EmailMultiplier.unverified_multiplier() == 0.5
    end
  end
end
