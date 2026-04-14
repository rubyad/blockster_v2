defmodule BlocksterV2.Widgets.ClickRouterTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.Widgets.ClickRouter

  describe "url_for/2" do
    test "routes {bot_id, tf} to RogueTrader /bot/:id" do
      assert ClickRouter.url_for(1, {"kronos", "7d"}) == "https://roguetrader.io/bot/kronos"
      assert ClickRouter.url_for(99, {"apollo", "1h"}) == "https://roguetrader.io/bot/apollo"
    end

    test "routes binary order_id to FateSwap /orders/:id" do
      assert ClickRouter.url_for(1, "abc-123") == "https://fateswap.io/orders/abc-123"
    end

    test "routes :rt atom to RogueTrader homepage" do
      assert ClickRouter.url_for(1, :rt) == "https://roguetrader.io"
    end

    test "routes :fs atom to FateSwap homepage" do
      assert ClickRouter.url_for(1, :fs) == "https://fateswap.io"
    end

    test "string 'rt' and 'fs' map to homepages" do
      assert ClickRouter.url_for(1, "rt") == "https://roguetrader.io"
      assert ClickRouter.url_for(1, "fs") == "https://fateswap.io"
    end

    test "empty/bad inputs fall back to /" do
      assert ClickRouter.url_for(1, nil) == "/"
      assert ClickRouter.url_for(1, "") == "/"
      assert ClickRouter.url_for(1, {"", "7d"}) == "/"
      assert ClickRouter.url_for(1, {nil, "7d"}) == "/"
    end
  end

  test "url_for/1 arity works identically" do
    assert ClickRouter.url_for({"kronos", "24h"}) == "https://roguetrader.io/bot/kronos"
    assert ClickRouter.url_for("xyz") == "https://fateswap.io/orders/xyz"
    assert ClickRouter.url_for(:rt) == "https://roguetrader.io"
  end
end
