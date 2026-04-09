defmodule BlocksterV2Web.DesignSystem.PageHeroTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "page_hero/1 · Variant A" do
    test "renders eyebrow + title + description" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.page_hero
          eyebrow="The library"
          title="Browse hubs"
          description="Every brand on Blockster, sorted by activity."
        />
        """)

      assert html =~ "ds-page-hero"
      assert html =~ "The library"
      assert html =~ "Browse hubs"
      assert html =~ "Every brand on Blockster, sorted by activity."
    end

    test "renders the title with article-title styling at xl size" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.page_hero title="Hello" />
        """)

      assert html =~ "ds-page-hero__title"
      assert html =~ "text-[44px]"
      assert html =~ "md:text-[80px]"
    end

    test "renders the title at md size when title_size=md" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.page_hero title="Hello" title_size="md" />
        """)

      assert html =~ "text-[36px]"
      assert html =~ "md:text-[52px]"
      refute html =~ "md:text-[80px]"
    end

    test "renders 3-stat band when stats are provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.page_hero title="Browse hubs">
          <:stat label="Active hubs" value="142" />
          <:stat label="Posts today" value="48" sub="+12 vs yesterday" />
          <:stat label="BUX in pool" value="2.4M" />
        </.page_hero>
        """)

      assert html =~ "Active hubs"
      assert html =~ "142"
      assert html =~ "Posts today"
      assert html =~ "+12 vs yesterday"
      assert html =~ "BUX in pool"
      assert html =~ "2.4M"
    end

    test "the stats column is omitted when there are no stats" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.page_hero title="Just a title" />
        """)

      assert html =~ "md:col-span-12"
      refute html =~ "md:col-span-5"
    end

    test "renders cta slot below the title" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.page_hero title="Hello">
          <:cta>
            <button>Click me</button>
          </:cta>
        </.page_hero>
        """)

      assert html =~ "Click me"
    end
  end
end
