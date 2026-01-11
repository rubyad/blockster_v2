defmodule HighRollersWeb.HealthController do
  @moduledoc """
  Health check endpoints for load balancer integration and orchestrator readiness probes.
  """
  use HighRollersWeb, :controller

  @doc """
  GET /api/health

  Basic health check - returns 200 if app is running.
  Used by load balancers and orchestrators.
  """
  def check(conn, _params) do
    json(conn, %{status: "ok", timestamp: DateTime.utc_now()})
  end

  @doc """
  GET /api/health/ready

  Readiness check - returns 200 only if all dependencies are ready.
  Used by Kubernetes/Fly.io to determine if instance can receive traffic.
  """
  def ready(conn, _params) do
    checks = %{
      mnesia: check_mnesia(),
      arbitrum_rpc: check_rpc(:arbitrum),
      rogue_rpc: check_rpc(:rogue),
      admin_queue: check_admin_queue()
    }

    all_healthy = Enum.all?(checks, fn {_k, v} -> v == :ok end)

    if all_healthy do
      json(conn, %{status: "ready", checks: format_checks(checks)})
    else
      conn
      |> put_status(503)
      |> json(%{status: "not_ready", checks: format_checks(checks)})
    end
  end

  @doc """
  GET /api/health/live

  Liveness check - returns 200 if app process is alive.
  Failing this causes orchestrator to restart the instance.
  """
  def live(conn, _params) do
    # Simple check - if we can respond, we're alive
    json(conn, %{status: "alive"})
  end

  # ===== Health Checks =====

  defp check_mnesia do
    case :mnesia.system_info(:is_running) do
      :yes -> :ok
      _ -> :error
    end
  end

  defp check_rpc(:arbitrum) do
    case HighRollers.Contracts.NFTContract.get_block_number() do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  defp check_rpc(:rogue) do
    case HighRollers.Contracts.NFTRewarder.get_block_number() do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  defp check_admin_queue do
    try do
      _count = HighRollers.AdminTxQueue.pending_count()
      :ok
    rescue
      _ -> :error
    catch
      :exit, _ -> :error
    end
  end

  defp format_checks(checks) do
    Map.new(checks, fn {k, v} -> {k, v == :ok} end)
  end
end
