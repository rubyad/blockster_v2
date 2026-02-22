defmodule BlocksterV2.AdsManager.Config do
  @moduledoc """
  Runtime configuration helpers for the AI Ads Manager.
  Reads from Application config (set in config/runtime.exs via env vars).
  """

  alias BlocksterV2.Notifications.SystemConfig

  defp get(key, default \\ nil) do
    Application.get_env(:blockster_v2, :ai_ads_manager, [])
    |> Keyword.get(key, default)
  end

  def enabled?, do: get(:enabled, false)
  def ads_service_url, do: get(:ads_service_url, "http://localhost:3001")
  def ads_service_secret, do: get(:ads_service_secret)
  def anthropic_api_key, do: get(:anthropic_api_key)

  # SystemConfig-backed settings (AI Manager writes, everything reads)
  def autonomy_level, do: SystemConfig.get("ads_autonomy_level", "manual")
  def daily_budget_limit, do: SystemConfig.get("ads_daily_budget_limit", 50)
  def monthly_budget_limit, do: SystemConfig.get("ads_monthly_budget_limit", 1500)
  def approval_threshold, do: SystemConfig.get("ads_approval_threshold", 25)
  def ai_ads_enabled?, do: SystemConfig.get("ai_ads_enabled", false)

  # Hard ceiling — code-level, cannot be overridden via SystemConfig
  def hard_ceiling_monthly, do: 3000
end
