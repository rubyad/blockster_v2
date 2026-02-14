defmodule BlocksterV2.ContentAutomation.Config do
  @moduledoc """
  Runtime configuration helpers for the content automation pipeline.
  Reads from Application config (set in config/runtime.exs via env vars).
  """

  defp get(key, default \\ nil) do
    Application.get_env(:blockster_v2, :content_automation, [])
    |> Keyword.get(key, default)
  end

  def enabled?, do: get(:enabled, false)
  def anthropic_api_key, do: get(:anthropic_api_key)
  def x_bearer_token, do: get(:x_bearer_token)
  def unsplash_access_key, do: get(:unsplash_access_key)
  def google_cse_api_key, do: get(:google_cse_api_key)
  def google_cse_cx, do: get(:google_cse_cx)
  def bing_image_api_key, do: get(:bing_image_api_key)
  def posts_per_day, do: get(:posts_per_day, 10)
  def content_model, do: get(:content_model, "claude-opus-4-6")
  def topic_model, do: get(:topic_model, "claude-haiku-4-5-20251001")
  def feed_poll_interval, do: get(:feed_poll_interval, :timer.minutes(5))
  def topic_analysis_interval, do: get(:topic_analysis_interval, :timer.minutes(15))
  def brand_x_user_id, do: get(:brand_x_user_id)
end
