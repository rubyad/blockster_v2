defmodule BlocksterV2.AdsManager.PlatformClient do
  @moduledoc """
  HTTP client for the Node.js ad platform microservice.
  All ad platform API calls go through here.
  """

  require Logger

  alias BlocksterV2.AdsManager.Config

  @timeout 30_000

  def create_campaign(params) do
    post("/campaigns", params)
  end

  def get_campaign(platform_campaign_id) do
    get("/campaigns/#{platform_campaign_id}")
  end

  def update_campaign(platform_campaign_id, params) do
    put("/campaigns/#{platform_campaign_id}", params)
  end

  def pause_campaign(platform_campaign_id) do
    post("/campaigns/#{platform_campaign_id}/pause", %{})
  end

  def resume_campaign(platform_campaign_id) do
    post("/campaigns/#{platform_campaign_id}/resume", %{})
  end

  def generate_copy(params) do
    post("/generate/copy", params)
  end

  def upload_creative(params) do
    post("/creatives/upload", params)
  end

  def get_campaign_analytics(platform_campaign_id) do
    get("/analytics/campaign/#{platform_campaign_id}")
  end

  def get_platform_analytics(platform) do
    get("/analytics/#{platform}")
  end

  def get_account_status(account_id) do
    get("/accounts/#{account_id}/status")
  end

  # ============ HTTP Helpers ============

  defp post(path, body) do
    url = "#{Config.ads_service_url()}#{path}"

    case Req.post(url, json: body, headers: auth_headers(), receive_timeout: @timeout) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[PlatformClient] POST #{path} returned #{status}: #{inspect(body)}")
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        Logger.error("[PlatformClient] POST #{path} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get(path) do
    url = "#{Config.ads_service_url()}#{path}"

    case Req.get(url, headers: auth_headers(), receive_timeout: @timeout) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[PlatformClient] GET #{path} returned #{status}: #{inspect(body)}")
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        Logger.error("[PlatformClient] GET #{path} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp put(path, body) do
    url = "#{Config.ads_service_url()}#{path}"

    case Req.put(url, json: body, headers: auth_headers(), receive_timeout: @timeout) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[PlatformClient] PUT #{path} returned #{status}: #{inspect(body)}")
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        Logger.error("[PlatformClient] PUT #{path} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp auth_headers do
    secret = Config.ads_service_secret()
    if secret, do: [{"authorization", "Bearer #{secret}"}], else: []
  end
end
