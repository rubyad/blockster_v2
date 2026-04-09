defmodule BlocksterV2Web.DesignSystem.AuthorAvatarTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "author_avatar/1" do
    test "renders the initials in uppercase" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.author_avatar initials="mv" />
        """)

      assert html =~ "ds-author-avatar"
      # Whitespace inside the div is from HEEx pretty-printing — match content only
      assert html =~ ~r/>\s*MV\s*</
    end

    test "default size is medium" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.author_avatar initials="JC" />
        """)

      assert html =~ "w-9 h-9"
    end

    test "renders different size classes for each size" do
      for {size, klass} <- [
            {"xs", "w-6 h-6"},
            {"sm", "w-7 h-7"},
            {"md", "w-9 h-9"},
            {"lg", "w-12 h-12"},
            {"xl", "w-16 h-16"}
          ] do
        assigns = %{size: size}

        html =
          rendered_to_string(~H"""
          <.author_avatar initials="MV" size={@size} />
          """)

        assert html =~ klass, "expected #{size} avatar to use class #{klass}"
      end
    end
  end
end
