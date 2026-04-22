defmodule BlocksterV2.PoolPositions do
  @moduledoc """
  Per-user cost-basis tracking for bankroll pool LP positions.

  Uses Average Cost Basis (ACB): one running `total_cost` + `total_lp` per
  `{user_id, vault_type}`. On every confirmed deposit/withdraw we update:

    * deposit(amount, lp_price):
        lp_received = amount / lp_price
        total_cost  += amount
        total_lp    += lp_received

    * withdraw(lp_burned, lp_price):
        avg_cost_per_lp = total_cost / total_lp
        cost_removed    = lp_burned * avg_cost_per_lp
        realized_gain   += (lp_burned * lp_price) - cost_removed
        total_cost      -= cost_removed
        total_lp        -= lp_burned

  Pre-existing LP holders (who deposited before this module shipped) get
  seeded on first render with `cost = lp * current_lp_price`, which makes
  unrealized P/L appear flat initially and accurate from the next tx forward.

  Mnesia dirty ops only — writes serialize naturally because a single user
  can only confirm one pool tx at a time from the UI.
  """

  require Logger

  @table :user_pool_positions
  @epsilon 1.0e-9

  @doc "Reads position for a user+vault, or nil if no row exists."
  @spec get(integer(), String.t()) :: map() | nil
  def get(user_id, vault_type) when is_integer(user_id) and vault_type in ["sol", "bux"] do
    case :mnesia.dirty_read(@table, {user_id, vault_type}) do
      [] ->
        nil

      [{@table, _id, _uid, _vault, total_cost, total_lp, realized_gain, updated_at}] ->
        %{
          total_cost: total_cost,
          total_lp: total_lp,
          realized_gain: realized_gain,
          updated_at: updated_at
        }
    end
  rescue
    e ->
      Logger.warning("[PoolPositions] get failed: #{inspect(e)}")
      nil
  end

  @doc """
  Seeds a position row for a pre-existing LP holder who has on-chain LP
  but no cost-basis row yet. Treats "now" as their cost basis. No-op if a
  row already exists OR if they have zero LP.
  """
  @spec seed_if_missing(integer(), String.t(), number(), number()) :: :ok
  def seed_if_missing(user_id, vault_type, current_lp, current_lp_price)
      when is_integer(user_id) and vault_type in ["sol", "bux"] do
    cond do
      not is_number(current_lp) or current_lp <= @epsilon ->
        :ok

      not is_number(current_lp_price) or current_lp_price <= 0 ->
        :ok

      get(user_id, vault_type) != nil ->
        :ok

      true ->
        write(user_id, vault_type, current_lp * current_lp_price, current_lp, 0.0)
        :ok
    end
  end

  @doc """
  Records a confirmed deposit of `amount` underlying tokens at `lp_price`.
  Creates the row if missing.
  """
  @spec record_deposit(integer(), String.t(), number(), number()) :: :ok
  def record_deposit(user_id, vault_type, amount, lp_price)
      when is_integer(user_id) and vault_type in ["sol", "bux"] and
             is_number(amount) and is_number(lp_price) and amount > 0 and lp_price > 0 do
    lp_received = amount / lp_price

    case get(user_id, vault_type) do
      nil ->
        write(user_id, vault_type, amount, lp_received, 0.0)

      %{total_cost: tc, total_lp: tl, realized_gain: rg} ->
        write(user_id, vault_type, tc + amount, tl + lp_received, rg)
    end

    :ok
  rescue
    e ->
      Logger.warning("[PoolPositions] record_deposit failed: #{inspect(e)}")
      :ok
  end

  def record_deposit(_, _, _, _), do: :ok

  @doc """
  Records a confirmed withdraw of `lp_burned` LP tokens at `lp_price`.
  Proportional share of cost basis is removed, remainder contributes to
  realized gain. No-op if no prior row exists (can't realize from nothing).
  """
  @spec record_withdraw(integer(), String.t(), number(), number()) :: :ok
  def record_withdraw(user_id, vault_type, lp_burned, lp_price)
      when is_integer(user_id) and vault_type in ["sol", "bux"] and
             is_number(lp_burned) and is_number(lp_price) and lp_burned > 0 and lp_price > 0 do
    case get(user_id, vault_type) do
      nil ->
        :ok

      %{total_cost: tc, total_lp: tl, realized_gain: rg} when tl <= @epsilon ->
        Logger.warning(
          "[PoolPositions] withdraw recorded but total_lp is ~0 (user_id=#{user_id}, vault=#{vault_type}) — skipping"
        )

        _ = {tc, rg}
        :ok

      %{total_cost: tc, total_lp: tl, realized_gain: rg} ->
        lp_burned_clamped = min(lp_burned, tl)
        avg_cost_per_lp = tc / tl
        cost_removed = lp_burned_clamped * avg_cost_per_lp
        proceeds = lp_burned_clamped * lp_price
        realized_delta = proceeds - cost_removed

        new_cost = tc - cost_removed
        new_lp = tl - lp_burned_clamped

        # Avoid floating-point residuals on full withdraw
        {new_cost, new_lp} =
          if new_lp <= @epsilon, do: {0.0, 0.0}, else: {new_cost, new_lp}

        write(user_id, vault_type, new_cost, new_lp, rg + realized_delta)
    end

    :ok
  rescue
    e ->
      Logger.warning("[PoolPositions] record_withdraw failed: #{inspect(e)}")
      :ok
  end

  def record_withdraw(_, _, _, _), do: :ok

  @doc """
  Returns %{cost_basis, current_value, unrealized_pnl, realized_gain} for a
  user+vault, using `current_lp` + `current_lp_price` for valuation. Returns
  nil if no row exists (caller can choose to seed first).
  """
  @spec summary(integer(), String.t(), number(), number()) :: map() | nil
  def summary(user_id, vault_type, current_lp, current_lp_price) do
    case get(user_id, vault_type) do
      nil ->
        nil

      %{total_cost: tc, realized_gain: rg} ->
        value = (is_number(current_lp) && is_number(current_lp_price) && current_lp * current_lp_price) || 0.0

        %{
          cost_basis: tc,
          current_value: value,
          unrealized_pnl: value - tc,
          realized_gain: rg
        }
    end
  end

  # ── Private helpers ──

  defp write(user_id, vault_type, total_cost, total_lp, realized_gain) do
    now = System.system_time(:second)
    key = {user_id, vault_type}

    record =
      {@table, key, user_id, vault_type, total_cost / 1.0, total_lp / 1.0, realized_gain / 1.0, now}

    :mnesia.dirty_write(record)
  end
end
