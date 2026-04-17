defmodule BlocksterV2Web.Widgets.CfHelpers do
  @moduledoc """
  Shared helpers for coin flip widgets (both demo and live).
  Handles game data formatting, chip rendering helpers, USD conversion,
  and wallet truncation.
  """

  alias BlocksterV2.PriceTracker

  @sol_logo "https://ik.imagekit.io/blockster/solana-sol-logo.png"
  @blockster_icon "https://ik.imagekit.io/blockster/blockster-icon.png"

  # Multipliers from CoinFlipGame (BPS / 10000)
  @multipliers %{
    -4 => 10200,
    -3 => 10500,
    -2 => 11300,
    -1 => 13200,
    1 => 19800,
    2 => 39600,
    3 => 79200,
    4 => 158400,
    5 => 316800
  }

  @doc "Format a game map from CoinFlipGame.get_recent_games_by_vault into display data."
  def format_cf_game(game) do
    sol_price = get_sol_price()
    flip_count = length(game.predictions || [])
    mode = if game.difficulty > 0, do: :win_all, else: :win_one
    multiplier = Map.get(@multipliers, game.difficulty, 10000) / 10000
    won = game.type == "win"
    net = if won, do: (game.payout || 0) - game.bet_amount, else: -game.bet_amount

    %{
      won: won,
      mode: mode,
      flip_count: flip_count,
      multiplier: multiplier,
      predictions: game.predictions || [],
      results: game.results || [],
      bet_amount: game.bet_amount,
      payout: game.payout || 0,
      net: net,
      wallet_short: truncate_wallet(game.wallet),
      usd_stake: sol_to_usd(game.bet_amount, sol_price),
      usd_net: sol_to_usd(net, sol_price),
      settled_at: game.created_at
    }
  end

  def get_sol_price do
    case PriceTracker.get_price("SOL") do
      {:ok, %{usd_price: p}} when is_number(p) -> p
      _ -> nil
    end
  catch
    :exit, _ -> nil
  end

  def sol_to_usd(_amount, nil), do: nil
  def sol_to_usd(amount, price) when is_number(amount) and is_number(price) do
    amount * price
  end
  def sol_to_usd(_, _), do: nil

  def format_usd(nil), do: ""
  def format_usd(value) when is_number(value) do
    abs_val = abs(value)
    formatted = if abs_val >= 1000, do: format_number_with_commas(abs_val), else: :erlang.float_to_binary(abs_val * 1.0, decimals: 2)
    prefix = if value >= 0, do: "", else: "-"
    "#{prefix}$#{formatted}"
  end

  def format_sol(amount) when is_number(amount) do
    if amount >= 1000 do
      format_number_with_commas(amount)
    else
      :erlang.float_to_binary(amount * 1.0, decimals: 2)
    end
  end
  def format_sol(_), do: "0.00"

  def format_net_sol(amount) when is_number(amount) do
    prefix = if amount >= 0, do: "+", else: "-"
    "#{prefix}#{format_sol(abs(amount))}"
  end
  def format_net_sol(_), do: "0.00"

  def format_net_usd(nil), do: ""
  def format_net_usd(value) when is_number(value) do
    abs_val = abs(value)
    formatted = if abs_val >= 1000, do: format_number_with_commas(abs_val), else: :erlang.float_to_binary(abs_val * 1.0, decimals: 2)
    prefix = if value >= 0, do: "+", else: "-"
    "#{prefix}$#{formatted}"
  end

  defp format_number_with_commas(number) when is_number(number) do
    int_part = trunc(number)
    dec_part = :erlang.float_to_binary(number - int_part, decimals: 2) |> String.slice(1..-1//1)
    formatted_int = int_part |> Integer.to_string() |> add_commas()
    "#{formatted_int}#{dec_part}"
  end

  defp add_commas(str) do
    str
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  def truncate_wallet(nil), do: "..."
  def truncate_wallet(wallet) when is_binary(wallet) and byte_size(wallet) >= 8 do
    "#{String.slice(wallet, 0, 3)}...#{String.slice(wallet, -3, 3)}"
  end
  def truncate_wallet(wallet) when is_binary(wallet), do: wallet

  def mode_label(:win_all), do: "Win All"
  def mode_label(:win_one), do: "Win One"
  def mode_label(_), do: ""

  def mode_desc(:win_all), do: "all must match"
  def mode_desc(:win_one), do: "any match wins"
  def mode_desc(_), do: ""

  @doc "Returns :heads or :tails for a prediction/result value"
  def chip_side(val) when val in [:h, "h", 0], do: :heads
  def chip_side(_), do: :tails

  def chip_emoji(:heads), do: "\u{1F680}"
  def chip_emoji(:tails), do: "\u{1F4A9}"

  @doc "Check if a prediction matched its result at a given index"
  def matched?(predictions, results, index) do
    pred = Enum.at(predictions, index)
    res = Enum.at(results, index)
    pred != nil and res != nil and pred == res
  end

  def sol_logo, do: @sol_logo
  def blockster_icon, do: @blockster_icon

  @doc "Demo difficulty configs: {mode, flips, multiplier, stake, picks, results, active_flips}"
  def demo_configs do
    [
      {:winall, 1, 1.98,  1.0,  [:h],               [:h],               1},
      {:winall, 2, 3.96,  0.5,  [:h, :h],            [:h, :h],            2},
      {:winall, 3, 7.92,  0.5,  [:h, :t, :h],        [:h, :t, :h],        3},
      {:winall, 4, 15.84, 0.25, [:h, :t, :h, :t],    [:h, :t, :h, :t],    4},
      {:winall, 5, 31.68, 0.10, [:h, :t, :h, :t, :h],[:h, :t, :h, :t, :h],5},
      {:winone, 2, 1.32,  2.0,  [:h, :h],            [:t, :h],            2},
      {:winone, 3, 1.13,  5.0,  [:h, :h, :h],        [:t, :t, :h],        3},
      {:winone, 4, 1.05,  10.0, [:h, :h, :h, :h],    [:t, :t, :h],        3},
      {:winone, 5, 1.02,  10.0, [:h, :h, :h, :h, :h],[:t, :t, :h],        3}
    ]
  end

  def demo_mode_label(:winall), do: "Win All"
  def demo_mode_label(:winone), do: "Win One"

  @doc "Duration in seconds for each demo difficulty panel animation"
  def demo_durations do
    [9, 13, 17, 21, 25, 13, 17, 17, 17]
  end
end
