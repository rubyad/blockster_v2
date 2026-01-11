defmodule Mix.Tasks.ResetPoller do
  @moduledoc """
  Reset poller blocks to trigger a full backfill.

  Usage:
    mix reset_poller
  """
  use Mix.Task

  @shortdoc "Reset poller blocks to beginning for full backfill"

  @impl Mix.Task
  def run(_args) do
    # Set Mnesia directory
    Application.put_env(:mnesia, :dir, ~c"priv/mnesia/hr1")

    # Start Mnesia
    :mnesia.start()
    :timer.sleep(500)

    # Wait for tables
    :mnesia.wait_for_tables([:hr_poller_state], 5000)

    # Set blocks
    :mnesia.dirty_write({:hr_poller_state, :arbitrum, 289_000_000})
    :mnesia.dirty_write({:hr_poller_state, :rogue, 108_000_000})

    # Verify
    [{_, _, arb}] = :mnesia.dirty_read(:hr_poller_state, :arbitrum)
    [{_, _, rogue}] = :mnesia.dirty_read(:hr_poller_state, :rogue)

    IO.puts("Set Arbitrum to: #{arb}")
    IO.puts("Set Rogue to: #{rogue}")
    IO.puts("\nNow start hr1 with: elixir --sname hr1 -S mix phx.server")

    :mnesia.stop()
  end
end
