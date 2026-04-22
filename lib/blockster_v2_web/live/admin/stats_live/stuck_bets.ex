defmodule BlocksterV2Web.Admin.StatsLive.StuckBets do
  @moduledoc """
  Admin review surface for settler-driven operations that the
  SettlerRetry classifier parked in the dead-letter queue.

  Lists every row from `:settler_dead_letters` with its operation type,
  last-failed timestamp, attempt count, and captured context. Admins
  can mark a row resolved after a manual fix (reclaim_expired signed
  by the player, manual mint, etc.).

  Mounted at `/admin/stats/stuck-bets`. Admin-only per the :admin
  router scope.
  """

  use BlocksterV2Web, :live_view

  alias BlocksterV2.SettlerRetry

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Stuck bets / dead-letter queue")
     |> load_rows()}
  end

  @impl true
  def handle_event("resolve", %{"type" => type, "id" => id}, socket) do
    op_type = String.to_existing_atom(type)
    SettlerRetry.resolve(op_type, id)
    {:noreply, load_rows(socket)}
  rescue
    ArgumentError ->
      {:noreply, put_flash(socket, :error, "Unknown operation type: #{inspect(type)}")}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_rows(socket)}
  end

  defp load_rows(socket) do
    rows = SettlerRetry.list_dead_letters()
    counts = SettlerRetry.count_by_type()

    socket
    |> assign(:rows, rows)
    |> assign(:counts, counts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">Stuck bets · dead-letter queue</h1>
          <p class="text-sm text-gray-500 mt-1">
            Operations that hit a terminal error after the retry classifier gave up. Resolve rows after the underlying bet is settled or reclaimed.
          </p>
        </div>
        <button
          type="button"
          phx-click="refresh"
          class="bg-gray-900 text-white px-4 py-2 rounded-full text-sm font-bold hover:bg-gray-700 transition-colors cursor-pointer"
        >
          Refresh
        </button>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <%= for {op_type, count} <- @counts do %>
          <div class="bg-white rounded-xl border border-gray-200 p-4">
            <div class="text-xs font-bold uppercase tracking-wider text-gray-500">{op_type}</div>
            <div class="text-2xl font-mono font-bold text-gray-900 mt-1">{count}</div>
          </div>
        <% end %>
        <%= if @counts == %{} do %>
          <div class="bg-white rounded-xl border border-gray-200 p-4 col-span-full">
            <div class="text-sm text-gray-600">Queue is empty — no stuck operations.</div>
          </div>
        <% end %>
      </div>

      <div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-gray-50 border-b border-gray-200">
            <tr>
              <th class="text-left px-4 py-3 font-bold text-gray-700">Type</th>
              <th class="text-left px-4 py-3 font-bold text-gray-700">Operation ID</th>
              <th class="text-left px-4 py-3 font-bold text-gray-700">Reason</th>
              <th class="text-right px-4 py-3 font-bold text-gray-700">Attempts</th>
              <th class="text-right px-4 py-3 font-bold text-gray-700">Last failed</th>
              <th class="text-right px-4 py-3 font-bold text-gray-700"></th>
            </tr>
          </thead>
          <tbody>
            <%= for row <- @rows do %>
              <tr class="border-b border-gray-100 last:border-b-0">
                <td class="px-4 py-3 font-mono text-xs text-gray-600">{row.operation_type}</td>
                <td class="px-4 py-3 font-mono text-xs text-gray-900" title={row.operation_id}>
                  {truncate(row.operation_id)}
                </td>
                <td class="px-4 py-3 text-xs text-gray-800 max-w-lg truncate" title={row.reason}>
                  {row.reason}
                </td>
                <td class="px-4 py-3 text-right font-mono">{row.attempt_count}</td>
                <td class="px-4 py-3 text-right font-mono text-xs text-gray-500">
                  {format_ts(row.last_failed_at)}
                </td>
                <td class="px-4 py-3 text-right">
                  <button
                    type="button"
                    phx-click="resolve"
                    phx-value-type={Atom.to_string(row.operation_type)}
                    phx-value-id={row.operation_id}
                    data-confirm="Mark this operation resolved and remove it from the queue?"
                    class="text-xs font-bold text-gray-900 hover:text-black hover:underline cursor-pointer"
                  >
                    Resolve
                  </button>
                </td>
              </tr>
            <% end %>
            <%= if @rows == [] do %>
              <tr>
                <td colspan="6" class="px-4 py-8 text-center text-sm text-gray-500">
                  No stuck operations.
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp truncate(s) when is_binary(s) and byte_size(s) > 16 do
    "#{String.slice(s, 0, 6)}…#{String.slice(s, -6, 6)}"
  end

  defp truncate(s), do: s

  defp format_ts(ts) when is_integer(ts) do
    DateTime.from_unix!(ts)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_ts(_), do: "—"
end
