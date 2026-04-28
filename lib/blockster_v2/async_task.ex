defmodule BlocksterV2.AsyncTask do
  @moduledoc """
  Wraps `Task.start/1` for fire-and-forget DB-touching work. In test env,
  runs synchronously inside the caller's process so the work participates
  in the test's `Ecto.Adapters.SQL.Sandbox` ownership and gets rolled back
  with the test transaction.

  Without this, every `Task.start(fn -> Repo.insert(...) end)` callsite
  spawns an unsupervised process whose DB writes try to use the test's
  sandbox connection. When the test exits, mid-flight inserts crash with
  `DBConnection.ConnectionError: "owner ... exited"`, polluting the
  connection pool and (in pathological runs) taking down the Repo's
  supervision tree mid-suite.

  Production behavior is unchanged: `Task.start` fires and forgets.
  Test-mode behavior MATCHES production fire-and-forget — exits
  (e.g. `:mnesia.abort`), throws, and exceptions are logged and swallowed
  so the caller's process keeps running. Without this, callers that
  invoke `mint_bux` / `record_mint` etc. in test env crash on the missing
  Mnesia tables that aren't initialized in test mode.
  """

  require Logger

  @doc """
  Run a 0-arity function. Returns `:ok` immediately in production;
  blocks until the function completes in test env.
  """
  def run(fun) when is_function(fun, 0) do
    if Application.get_env(:blockster_v2, :async_db_tasks, true) do
      Task.start(fun)
    else
      try do
        fun.()
      rescue
        e ->
          Logger.warning(
            "[AsyncTask] sync run failed: #{inspect(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
          )
      catch
        :exit, reason ->
          Logger.warning("[AsyncTask] sync run exited: #{inspect(reason)}")

        :throw, value ->
          Logger.warning("[AsyncTask] sync run threw: #{inspect(value)}")
      end
    end

    :ok
  end
end
