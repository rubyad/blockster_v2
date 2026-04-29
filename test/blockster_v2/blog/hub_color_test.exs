defmodule BlocksterV2.Blog.HubColorTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.Blog.HubColor

  describe "gradient/1" do
    test "uses DB colors when both are set" do
      hub = %{slug: "bitcoin", color_primary: "#F7931A", color_secondary: "#E67F0A"}
      assert HubColor.gradient(hub) == {"#F7931A", "#E67F0A"}
    end

    test "falls back to derived colors when both are nil" do
      hub = %{slug: "bitcoin", color_primary: nil, color_secondary: nil}
      {p, s} = HubColor.gradient(hub)
      # Hex format
      assert p =~ ~r/^#[0-9A-F]{6}$/
      assert s =~ ~r/^#[0-9A-F]{6}$/
      # Both differ — secondary is darker
      refute p == s
    end

    test "falls back when either color is empty string" do
      assert {p, s} = HubColor.gradient(%{slug: "x", color_primary: "", color_secondary: "#000000"})
      # Empty primary triggers derive — the result must NOT be %{color_secondary}
      refute s == "#000000"
      refute p == ""
    end

    test "deterministic — same slug always yields same gradient" do
      hub1 = %{slug: "ethereum", color_primary: nil, color_secondary: nil}
      hub2 = %{slug: "ethereum", color_primary: nil, color_secondary: nil}
      assert HubColor.gradient(hub1) == HubColor.gradient(hub2)
    end

    test "different slugs yield different gradients" do
      a = HubColor.gradient(%{slug: "alpha", color_primary: nil, color_secondary: nil})
      b = HubColor.gradient(%{slug: "beta", color_primary: nil, color_secondary: nil})
      refute a == b
    end

    test "uses :name when :slug is missing" do
      assert {p, s} = HubColor.gradient(%{name: "Some Hub"})
      assert p =~ ~r/^#[0-9A-F]{6}$/
      assert s =~ ~r/^#[0-9A-F]{6}$/
    end

    test "handles hub with no slug or name without crashing" do
      assert {p, s} = HubColor.gradient(%{})
      assert p =~ ~r/^#[0-9A-F]{6}$/
      assert s =~ ~r/^#[0-9A-F]{6}$/
    end
  end

  describe "primary/1" do
    test "returns just the primary half of the gradient" do
      hub = %{slug: "x", color_primary: "#ABCDEF", color_secondary: "#FEDCBA"}
      assert HubColor.primary(hub) == "#ABCDEF"
    end
  end
end
