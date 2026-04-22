defmodule BlocksterV2.SettlerRetry do
  @moduledoc """
  Shared retry policy for settler-driven on-chain operations.

  Callers pass an error reason + an attempt number; this module returns:
  - `:retry` — transient or unknown; try again after `backoff_delay/1` seconds.
  - `:transient` — known-transient (RPC timeout, blockhash stale); same as
    `:retry` but never counts toward the terminal attempt cap.
  - `:terminal` — structurally unrecoverable; dead-letter via
    `park_dead_letter/3` and stop retrying.

  Backoff schedule `[10, 30, 90, 270, 810, 900]` seconds with a 15-min cap,
  matching the audit's GLOBAL-02 prescription.

  The module is stateless — callers own their own retry-state store. For
  convenience, `park_dead_letter/3` writes a row to the Mnesia
  `:settler_dead_letters` table (see
  `BlocksterV2.MnesiaInitializer`), which the admin review UI reads from.
  """

  require Logger

  @backoff_schedule [10, 30, 90, 270, 810, 900]
  @backoff_cap_seconds 900
  @terminal_attempt_cap 3

  @type classification :: :retry | :transient | :terminal
  @type operation_type :: :coin_flip | :bux_mint | :payment_intent | :airdrop_claim
  @type reason :: any()

  @doc """
  Returns the backoff schedule (seconds) used by the retry state machine.
  Exposed so tests can assert the contract without depending on the
  private constant.
  """
  def backoff_schedule, do: @backoff_schedule

  @doc "Cap on consecutive attempts before an unknown error is treated as terminal."
  def terminal_attempt_cap, do: @terminal_attempt_cap

  @doc """
  Classify an error reason into :retry | :transient | :terminal.

  Unknown / unmatched reasons default to `:retry` — the caller's attempt
  counter decides when to give up.
  """
  @spec classify(reason) :: classification
  def classify(:manual_review), do: :terminal
  def classify({:error, :manual_review}), do: :terminal
  def classify({:commitment_mismatch, _, _}), do: :terminal

  def classify(reason) when is_binary(reason) do
    cond do
      String.contains?(reason, "InvalidServerSeed") -> :terminal
      String.contains?(reason, "0x178a") -> :terminal
      String.contains?(reason, "AccountNotInitialized") -> :terminal
      String.contains?(reason, "AccountNotFound") -> :terminal
      String.contains?(reason, "InstructionError") -> :terminal
      String.contains?(reason, "commitment_mismatch") -> :terminal
      String.contains?(reason, "TransportError") -> :transient
      String.contains?(reason, "timeout") -> :transient
      String.contains?(reason, "BlockhashNotFound") -> :transient
      String.contains?(reason, "connection") -> :transient
      String.contains?(reason, "ECONNREFUSED") -> :transient
      true -> :retry
    end
  end

  def classify(reason) when is_tuple(reason) or is_atom(reason) or is_map(reason) do
    classify(inspect(reason))
  end

  def classify(_), do: :retry

  @doc """
  Returns the backoff delay (seconds) for a given 0-indexed attempt
  number. Past the schedule length, returns the cap.

      iex> BlocksterV2.SettlerRetry.backoff_delay(0)
      10
      iex> BlocksterV2.SettlerRetry.backoff_delay(3)
      270
      iex> BlocksterV2.SettlerRetry.backoff_delay(99)
      900
  """
  @spec backoff_delay(non_neg_integer) :: pos_integer
  def backoff_delay(attempt) when is_integer(attempt) and attempt >= 0 do
    case Enum.at(@backoff_schedule, attempt) do
      nil -> @backoff_cap_seconds
      n when is_integer(n) -> n
    end
  end

  def backoff_delay(_), do: Enum.at(@backoff_schedule, 0)

  @doc """
  Decide whether a `:retry` classification has exhausted the cap and
  should be upgraded to `:terminal`. `:transient` errors are never
  counted toward the cap.

  Returns `:terminal` if attempt_count >= cap, otherwise `:retry`.
  """
  def maybe_upgrade_to_terminal(attempt_count) when is_integer(attempt_count) do
    if attempt_count >= @terminal_attempt_cap, do: :terminal, else: :retry
  end

  @doc """
  Record a bet / operation that's been given up on. Writes to the Mnesia
  `:settler_dead_letters` table so the admin review UI can surface it.

  `payload` is a map captured for debugging — serialised as an Erlang
  term in the Mnesia row. Keep it small.

  Returns `:ok` on success. Swallows Mnesia errors so dead-lettering
  never crashes the caller — the settle path is already failing; losing
  the dead-letter record would only make things worse.
  """
  @spec park_dead_letter(operation_type, binary | atom, map) :: :ok
  def park_dead_letter(operation_type, operation_id, payload \\ %{})

  def park_dead_letter(operation_type, operation_id, payload)
      when is_atom(operation_type) and (is_binary(operation_id) or is_atom(operation_id)) and
             is_map(payload) do
    now = System.system_time(:second)
    reason = Map.get(payload, :reason) || Map.get(payload, "reason") || "unspecified"
    attempt_count = Map.get(payload, :attempt_count) || Map.get(payload, "attempt_count") || 0

    key = {operation_type, to_string(operation_id)}

    record = {
      :settler_dead_letters,
      key,
      operation_type,
      to_string(operation_id),
      inspect(reason),
      attempt_count,
      now,
      now,
      payload
    }

    :mnesia.dirty_write(record)
    Logger.warning(
      "[SettlerRetry] Dead-lettered #{operation_type}:#{operation_id} after #{attempt_count} attempts — reason: #{inspect(reason)}"
    )
    :ok
  rescue
    e ->
      Logger.error("[SettlerRetry] Failed to park dead-letter: #{inspect(e)}")
      :ok
  catch
    :exit, reason ->
      Logger.error("[SettlerRetry] park_dead_letter exited: #{inspect(reason)}")
      :ok
  end

  def park_dead_letter(_, _, _), do: :ok

  @doc """
  List all dead-lettered operations for the admin review UI. Returns an
  empty list if the table doesn't exist (e.g. test env without
  mnesia_initializer running).
  """
  def list_dead_letters do
    :mnesia.dirty_match_object({:settler_dead_letters, :_, :_, :_, :_, :_, :_, :_, :_})
    |> Enum.map(&dead_letter_record_to_map/1)
    |> Enum.sort_by(& &1.last_failed_at, :desc)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc "Count dead-lettered operations, grouped by operation_type."
  def count_by_type do
    list_dead_letters()
    |> Enum.group_by(& &1.operation_type)
    |> Enum.into(%{}, fn {type, entries} -> {type, length(entries)} end)
  end

  @doc "Remove a dead-letter row — used by admin after manual review resolves the bet."
  def resolve(operation_type, operation_id) do
    key = {operation_type, to_string(operation_id)}
    :mnesia.dirty_delete({:settler_dead_letters, key})
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp dead_letter_record_to_map(
         {:settler_dead_letters, _key, operation_type, operation_id, reason, attempt_count,
          first_failed_at, last_failed_at, payload}
       ) do
    %{
      operation_type: operation_type,
      operation_id: operation_id,
      reason: reason,
      attempt_count: attempt_count,
      first_failed_at: first_failed_at,
      last_failed_at: last_failed_at,
      payload: payload
    }
  end
end
