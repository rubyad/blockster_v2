defmodule BlocksterV2.Plinko.PlinkoMathTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.PlinkoGame

  # ============ Payout Table Integrity ============

  describe "payout tables" do
    test "all 9 tables are defined" do
      tables = PlinkoGame.payout_tables()
      assert map_size(tables) == 9

      for i <- 0..8 do
        assert Map.has_key?(tables, i), "Missing payout table for config #{i}"
      end
    end

    test "8-row configs have exactly 9 values" do
      tables = PlinkoGame.payout_tables()
      assert length(tables[0]) == 9
      assert length(tables[1]) == 9
      assert length(tables[2]) == 9
    end

    test "12-row configs have exactly 13 values" do
      tables = PlinkoGame.payout_tables()
      assert length(tables[3]) == 13
      assert length(tables[4]) == 13
      assert length(tables[5]) == 13
    end

    test "16-row configs have exactly 17 values" do
      tables = PlinkoGame.payout_tables()
      assert length(tables[6]) == 17
      assert length(tables[7]) == 17
      assert length(tables[8]) == 17
    end
  end

  describe "payout table symmetry" do
    test "all 9 tables are symmetric" do
      tables = PlinkoGame.payout_tables()

      for {config, table} <- tables do
        len = length(table)

        for k <- 0..(div(len, 2) - 1) do
          assert Enum.at(table, k) == Enum.at(table, len - 1 - k),
                 "Config #{config}: position #{k} (#{Enum.at(table, k)}) != position #{len - 1 - k} (#{Enum.at(table, len - 1 - k)})"
        end
      end
    end
  end

  describe "payout table values match contract" do
    test "8-Low" do
      assert PlinkoGame.payout_tables()[0] ==
               [56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 56000]
    end

    test "8-Medium" do
      assert PlinkoGame.payout_tables()[1] ==
               [130000, 30000, 13000, 7000, 4000, 7000, 13000, 30000, 130000]
    end

    test "8-High" do
      assert PlinkoGame.payout_tables()[2] ==
               [360000, 40000, 15000, 3000, 0, 3000, 15000, 40000, 360000]
    end

    test "12-Low" do
      assert PlinkoGame.payout_tables()[3] ==
               [110000, 30000, 16000, 14000, 11000, 10000, 5000, 10000, 11000, 14000, 16000, 30000, 110000]
    end

    test "12-Medium" do
      assert PlinkoGame.payout_tables()[4] ==
               [330000, 110000, 40000, 20000, 11000, 6000, 3000, 6000, 11000, 20000, 40000, 110000, 330000]
    end

    test "12-High" do
      assert PlinkoGame.payout_tables()[5] ==
               [4050000, 180000, 70000, 20000, 7000, 2000, 0, 2000, 7000, 20000, 70000, 180000, 4050000]
    end

    test "16-Low" do
      assert PlinkoGame.payout_tables()[6] ==
               [160000, 90000, 20000, 14000, 14000, 12000, 11000, 10000, 5000, 10000, 11000, 12000, 14000, 14000, 20000, 90000, 160000]
    end

    test "16-Medium" do
      assert PlinkoGame.payout_tables()[7] ==
               [1100000, 410000, 100000, 50000, 30000, 15000, 10000, 5000, 3000, 5000, 10000, 15000, 30000, 50000, 100000, 410000, 1100000]
    end

    test "16-High" do
      assert PlinkoGame.payout_tables()[8] ==
               [10000000, 1500000, 330000, 100000, 33000, 20000, 3000, 2000, 0, 2000, 3000, 20000, 33000, 100000, 330000, 1500000, 10000000]
    end
  end

  describe "max multiplier per config" do
    test "8-Low max = 56000" do
      assert Enum.max(PlinkoGame.payout_tables()[0]) == 56000
    end

    test "8-Med max = 130000" do
      assert Enum.max(PlinkoGame.payout_tables()[1]) == 130000
    end

    test "8-High max = 360000" do
      assert Enum.max(PlinkoGame.payout_tables()[2]) == 360000
    end

    test "12-Low max = 110000" do
      assert Enum.max(PlinkoGame.payout_tables()[3]) == 110000
    end

    test "12-Med max = 330000" do
      assert Enum.max(PlinkoGame.payout_tables()[4]) == 330000
    end

    test "12-High max = 4050000" do
      assert Enum.max(PlinkoGame.payout_tables()[5]) == 4_050_000
    end

    test "16-Low max = 160000" do
      assert Enum.max(PlinkoGame.payout_tables()[6]) == 160000
    end

    test "16-Med max = 1100000" do
      assert Enum.max(PlinkoGame.payout_tables()[7]) == 1_100_000
    end

    test "16-High max = 10000000" do
      assert Enum.max(PlinkoGame.payout_tables()[8]) == 10_000_000
    end
  end

  # ============ Result Calculation (Deterministic) ============

  describe "calculate_result/6" do
    @server_seed "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
    @nonce 0
    @bet_amount 100
    @user_id 42

    test "produces deterministic results for same inputs" do
      {:ok, result1} = PlinkoGame.calculate_result(@server_seed, @nonce, 0, @bet_amount, "BUX", @user_id)
      {:ok, result2} = PlinkoGame.calculate_result(@server_seed, @nonce, 0, @bet_amount, "BUX", @user_id)

      assert result1.ball_path == result2.ball_path
      assert result1.landing_position == result2.landing_position
      assert result1.payout == result2.payout
      assert result1.payout_bp == result2.payout_bp
    end

    test "produces different results for different server seeds" do
      seed2 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      {:ok, result1} = PlinkoGame.calculate_result(@server_seed, @nonce, 0, @bet_amount, "BUX", @user_id)
      {:ok, result2} = PlinkoGame.calculate_result(seed2, @nonce, 0, @bet_amount, "BUX", @user_id)

      # Very unlikely to get identical paths from different seeds
      assert result1.ball_path != result2.ball_path || result1.server_seed != result2.server_seed
    end

    test "ball_path length equals rows for 8-row config" do
      {:ok, result} = PlinkoGame.calculate_result(@server_seed, @nonce, 0, @bet_amount, "BUX", @user_id)
      assert length(result.ball_path) == 8
    end

    test "ball_path length equals rows for 12-row config" do
      {:ok, result} = PlinkoGame.calculate_result(@server_seed, @nonce, 3, @bet_amount, "BUX", @user_id)
      assert length(result.ball_path) == 12
    end

    test "ball_path length equals rows for 16-row config" do
      {:ok, result} = PlinkoGame.calculate_result(@server_seed, @nonce, 6, @bet_amount, "BUX", @user_id)
      assert length(result.ball_path) == 16
    end

    test "ball_path contains only :left and :right atoms" do
      for config <- 0..8 do
        {:ok, result} = PlinkoGame.calculate_result(@server_seed, @nonce, config, @bet_amount, "BUX", @user_id)

        for direction <- result.ball_path do
          assert direction in [:left, :right],
                 "Config #{config}: unexpected direction #{inspect(direction)}"
        end
      end
    end

    test "landing_position equals count of :right in ball_path" do
      for config <- 0..8 do
        {:ok, result} = PlinkoGame.calculate_result(@server_seed, @nonce, config, @bet_amount, "BUX", @user_id)
        right_count = Enum.count(result.ball_path, &(&1 == :right))
        assert result.landing_position == right_count
      end
    end

    test "landing_position is between 0 and rows (inclusive)" do
      for config <- 0..8 do
        {rows, _} = PlinkoGame.configs()[config]
        {:ok, result} = PlinkoGame.calculate_result(@server_seed, @nonce, config, @bet_amount, "BUX", @user_id)
        assert result.landing_position >= 0
        assert result.landing_position <= rows
      end
    end

    test "payout_bp matches payout_table lookup at landing_position" do
      for config <- 0..8 do
        {:ok, result} = PlinkoGame.calculate_result(@server_seed, @nonce, config, @bet_amount, "BUX", @user_id)
        table = PlinkoGame.payout_tables()[config]
        expected_bp = Enum.at(table, result.landing_position)
        assert result.payout_bp == expected_bp
      end
    end

    test "payout = div(bet_amount * payout_bp, 10000)" do
      {:ok, result} = PlinkoGame.calculate_result(@server_seed, @nonce, 0, @bet_amount, "BUX", @user_id)
      expected_payout = div(@bet_amount * result.payout_bp, 10000)
      assert result.payout == expected_payout
    end

    test "outcome is :won when payout > bet_amount" do
      # Find a seed/config that produces a win
      # Use config 0 (8-Low), bet 10 — many positions pay > 1x
      for seed_byte <- 0..255 do
        seed = String.duplicate(String.pad_leading(Integer.to_string(seed_byte, 16), 2, "0"), 32)
        {:ok, result} = PlinkoGame.calculate_result(seed, 0, 0, 10, "BUX", 1)

        if result.payout > 10 do
          assert result.outcome == :won
          assert result.won == true
        end
      end
    end

    test "outcome is :lost when payout < bet_amount" do
      for seed_byte <- 0..255 do
        seed = String.duplicate(String.pad_leading(Integer.to_string(seed_byte, 16), 2, "0"), 32)
        {:ok, result} = PlinkoGame.calculate_result(seed, 0, 0, 10, "BUX", 1)

        if result.payout < 10 do
          assert result.outcome == :lost
          assert result.won == false
        end
      end
    end

    test "outcome is :push when payout == bet_amount" do
      # 8-Low position 3 and 5 have 10000 bp (1.0x), so bet 10 -> payout 10
      for seed_byte <- 0..255 do
        seed = String.duplicate(String.pad_leading(Integer.to_string(seed_byte, 16), 2, "0"), 32)
        {:ok, result} = PlinkoGame.calculate_result(seed, 0, 0, 10, "BUX", 1)

        if result.payout == 10 do
          assert result.outcome == :push
          assert result.won == false
        end
      end
    end
  end

  describe "calculate_result edge cases" do
    test "0x payout (8-High center, position 4) returns payout = 0 and outcome = :lost" do
      # 8-High config 2, position 4 has 0 bp multiplier
      # We need to find a seed that lands at position 4 for 8 rows = exactly 4 rights
      # Manually construct: need combined seed where first 8 bytes have exactly 4 >= 128
      for seed_byte <- 0..255 do
        seed = String.duplicate(String.pad_leading(Integer.to_string(seed_byte, 16), 2, "0"), 32)
        {:ok, result} = PlinkoGame.calculate_result(seed, 0, 2, 100, "BUX", 1)

        if result.landing_position == 4 do
          assert result.payout == 0
          assert result.payout_bp == 0
          assert result.outcome == :lost
        end
      end
    end

    test "different user_id produces different client_seed and potentially different result" do
      seed = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
      {:ok, result1} = PlinkoGame.calculate_result(seed, 0, 0, 100, "BUX", 1)
      {:ok, result2} = PlinkoGame.calculate_result(seed, 0, 0, 100, "BUX", 2)

      # Different user_id changes client_seed, so combined seed differs
      # Results should differ (statistically near-certain)
      assert result1.ball_path != result2.ball_path
    end

    test "different bet_amount produces different result for same seed" do
      seed = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
      {:ok, result1} = PlinkoGame.calculate_result(seed, 0, 0, 100, "BUX", 1)
      {:ok, result2} = PlinkoGame.calculate_result(seed, 0, 0, 200, "BUX", 1)

      assert result1.ball_path != result2.ball_path
    end

    test "different config_index produces different result for same seed" do
      seed = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
      {:ok, result1} = PlinkoGame.calculate_result(seed, 0, 0, 100, "BUX", 1)
      {:ok, result2} = PlinkoGame.calculate_result(seed, 0, 3, 100, "BUX", 1)

      # Different config means different client_seed AND different rows
      assert result1.ball_path != result2.ball_path
    end
  end

  # ============ Byte-to-Direction Mapping ============

  describe "byte threshold" do
    # These tests verify the exact byte threshold used in ball path generation
    # by constructing seeds that produce known combined hashes

    test "byte values 0-127 map to :left, 128-255 map to :right" do
      # Use a known seed and verify that the mapping is consistent
      seed = "0000000000000000000000000000000000000000000000000000000000000000"
      {:ok, result} = PlinkoGame.calculate_result(seed, 0, 0, 100, "BUX", 1)

      # Reconstruct the combined hash
      input = "1:100:BUX:0"
      client_seed = :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)
      combined = :crypto.hash(:sha256, "#{seed}:#{client_seed}:0")

      # Verify each byte maps correctly
      for i <- 0..7 do
        byte = :binary.at(combined, i)
        direction = Enum.at(result.ball_path, i)

        if byte < 128 do
          assert direction == :left, "Byte #{byte} at row #{i} should be :left"
        else
          assert direction == :right, "Byte #{byte} at row #{i} should be :right"
        end
      end
    end
  end

  # ============ House Edge Verification ============

  describe "house edge (statistical)" do
    # For each config, compute expected value using exact binomial probabilities:
    # EV = sum over k: C(N,k)/2^N * multiplier[k] / 10000
    # Expected value should be between 0.98 and 1.0

    test "all 9 configs have house edge between 0% and 2%" do
      for config <- 0..8 do
        {rows, _risk} = PlinkoGame.configs()[config]
        table = PlinkoGame.payout_tables()[config]
        n = rows

        ev =
          for k <- 0..n do
            # Binomial probability: C(n,k) / 2^n
            prob = binomial_coeff(n, k) / :math.pow(2, n)
            multiplier = Enum.at(table, k) / 10000.0
            prob * multiplier
          end
          |> Enum.sum()

        assert ev >= 0.98 and ev <= 1.0,
               "Config #{config}: expected value #{Float.round(ev, 4)} outside [0.98, 1.0]"
      end
    end
  end

  # ============ Config Mapping ============

  describe "configs" do
    test "config 0 = {8, :low}" do
      assert PlinkoGame.configs()[0] == {8, :low}
    end

    test "config 1 = {8, :medium}" do
      assert PlinkoGame.configs()[1] == {8, :medium}
    end

    test "config 2 = {8, :high}" do
      assert PlinkoGame.configs()[2] == {8, :high}
    end

    test "config 3 = {12, :low}" do
      assert PlinkoGame.configs()[3] == {12, :low}
    end

    test "config 4 = {12, :medium}" do
      assert PlinkoGame.configs()[4] == {12, :medium}
    end

    test "config 5 = {12, :high}" do
      assert PlinkoGame.configs()[5] == {12, :high}
    end

    test "config 6 = {16, :low}" do
      assert PlinkoGame.configs()[6] == {16, :low}
    end

    test "config 7 = {16, :medium}" do
      assert PlinkoGame.configs()[7] == {16, :medium}
    end

    test "config 8 = {16, :high}" do
      assert PlinkoGame.configs()[8] == {16, :high}
    end

    test "invalid config index returns nil" do
      assert PlinkoGame.configs()[9] == nil
      assert PlinkoGame.configs()[-1] == nil
    end
  end

  # ============ Token Address Mapping ============

  describe "token_address/1" do
    test "BUX returns correct address" do
      assert PlinkoGame.token_address("BUX") == "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8"
    end

    test "ROGUE returns zero address" do
      assert PlinkoGame.token_address("ROGUE") == "0x0000000000000000000000000000000000000000"
    end
  end

  # ============ Helpers ============

  defp binomial_coeff(n, k) when k < 0 or k > n, do: 0
  defp binomial_coeff(_n, 0), do: 1
  defp binomial_coeff(n, n), do: 1

  defp binomial_coeff(n, k) do
    k = min(k, n - k)

    if k == 0 do
      1
    else
      Enum.reduce(1..k//1, 1, fn i, acc ->
        div(acc * (n - i + 1), i)
      end)
    end
  end
end
