defmodule BlocksterV2Web.DesignSystem.ProfileAvatarTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "profile_avatar/1" do
    test "renders initials uppercase" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.profile_avatar initials="mv" />
        """)

      assert html =~ "ds-profile-avatar"
      assert html =~ ~r/>\s*MV\s*</
    end

    test "applies the lime ring when ring={true}" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.profile_avatar initials="MV" ring />
        """)

      assert html =~ "ring-2"
      assert html =~ "ring-[#CAFC00]"
    end

    test "no ring when ring is false (default)" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.profile_avatar initials="MV" />
        """)

      refute html =~ "ring-[#CAFC00]"
    end

    test "renders different size classes" do
      for {size, klass} <- [
            {"sm", "w-8 h-8"},
            {"md", "w-10 h-10"},
            {"lg", "w-14 h-14"},
            {"xl", "w-20 h-20"},
            {"2xl", "w-28 h-28"}
          ] do
        assigns = %{size: size}

        html =
          rendered_to_string(~H"""
          <.profile_avatar initials="MV" size={@size} />
          """)

        assert html =~ klass, "expected #{size} profile avatar to use class #{klass}"
      end
    end
  end
end
