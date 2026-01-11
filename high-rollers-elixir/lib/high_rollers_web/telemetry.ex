defmodule HighRollersWeb.Telemetry do
  @moduledoc """
  Telemetry and observability for High Rollers NFT application.

  ## Telemetry Events

  All GenServers and critical paths emit telemetry events:

  | Event | Measurements | Metadata | Description |
  |-------|--------------|----------|-----------|
  | `[:high_rollers, :rpc, :call]` | `duration` | `method`, `url`, `result` | RPC call latency |
  | `[:high_rollers, :rpc, :retry]` | `attempt` | `method`, `url`, `error` | RPC retry attempt |
  | `[:high_rollers, :arbitrum_poller, :poll]` | `duration`, `events_count` | `from_block`, `to_block` | Arbitrum polling |
  | `[:high_rollers, :rogue_poller, :poll]` | `duration`, `events_count` | `from_block`, `to_block` | Rogue Chain polling |
  | `[:high_rollers, :earnings_syncer, :sync]` | `duration`, `nfts_synced` | `batch_size` | Earnings sync |
  | `[:high_rollers, :admin_tx, :send]` | `duration` | `action`, `result`, `tx_hash` | Admin tx sent |
  | `[:high_rollers, :admin_tx, :queue_depth]` | `count` | - | Pending admin txs |
  | `[:high_rollers, :mnesia, :table_size]` | `count` | `table` | Mnesia table size |
  """
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # ===== Phoenix Metrics =====
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # ===== Phoenix LiveView Metrics =====
      summary("phoenix.live_view.mount.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.handle_event.stop.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # ===== RPC Metrics =====
      summary("high_rollers.rpc.call.duration",
        unit: {:native, :millisecond},
        tags: [:method, :result]
      ),
      counter("high_rollers.rpc.retry.attempt",
        tags: [:method, :error]
      ),

      # ===== Poller Metrics =====
      summary("high_rollers.arbitrum_poller.poll.duration",
        unit: {:native, :millisecond}
      ),
      counter("high_rollers.arbitrum_poller.poll.events_count"),
      summary("high_rollers.rogue_poller.poll.duration",
        unit: {:native, :millisecond}
      ),
      counter("high_rollers.rogue_poller.poll.events_count"),

      # ===== Earnings Syncer Metrics =====
      summary("high_rollers.earnings_syncer.sync.duration",
        unit: {:native, :millisecond}
      ),
      last_value("high_rollers.earnings_syncer.sync.nfts_synced"),

      # ===== Admin TX Metrics =====
      summary("high_rollers.admin_tx.send.duration",
        unit: {:native, :millisecond},
        tags: [:action]
      ),
      last_value("high_rollers.admin_tx.queue_depth.count"),
      last_value("high_rollers.admin_tx.dead_letter.count"),

      # ===== Mnesia Metrics =====
      last_value("high_rollers.mnesia.table_size.count",
        tags: [:table]
      ),

      # ===== VM Metrics =====
      summary("vm.memory.total", unit: {:byte, :megabyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :measure_admin_tx_queue, []},
      {__MODULE__, :measure_mnesia_tables, []}
    ]
  end

  @doc """
  Measure AdminTxQueue pending and dead letter counts.
  Called periodically by telemetry_poller.
  """
  def measure_admin_tx_queue do
    # Check if AdminTxQueue is available and running
    if Code.ensure_loaded?(HighRollers.AdminTxQueue) do
      try do
        pending = HighRollers.AdminTxQueue.pending_count()
        dead_letter = HighRollers.AdminTxQueue.dead_letter_count()

        :telemetry.execute(
          [:high_rollers, :admin_tx, :queue_depth],
          %{count: pending},
          %{}
        )

        :telemetry.execute(
          [:high_rollers, :admin_tx, :dead_letter],
          %{count: dead_letter},
          %{}
        )
      rescue
        _ -> :ok  # Ignore errors if AdminTxQueue not ready
      end
    end
  end

  @doc """
  Measure Mnesia table sizes.
  Called periodically by telemetry_poller.
  """
  def measure_mnesia_tables do
    tables = [:hr_nfts, :hr_users, :hr_reward_events, :hr_reward_withdrawals,
              :hr_affiliate_earnings, :hr_pending_mints, :hr_admin_ops, :hr_stats]

    for table <- tables do
      try do
        size = :mnesia.table_info(table, :size)
        :telemetry.execute(
          [:high_rollers, :mnesia, :table_size],
          %{count: size},
          %{table: table}
        )
      rescue
        _ -> :ok  # Table may not exist yet during startup
      end
    end
  end
end
