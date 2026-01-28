defmodule BlocksterV2.TwilioClient do
  @moduledoc """
  Twilio API client for phone verification and lookup.
  """

  @behaviour BlocksterV2.TwilioClientBehaviour

  @lookup_url "https://lookups.twilio.com/v2/PhoneNumbers"

  defp get_verify_service_sid, do: Application.get_env(:blockster_v2, :twilio_verify_service_sid)
  defp get_account_sid, do: Application.get_env(:blockster_v2, :twilio_account_sid)
  defp get_auth_token, do: Application.get_env(:blockster_v2, :twilio_auth_token)

  defp base_url, do: "https://verify.twilio.com/v2/Services/#{get_verify_service_sid()}/Verifications"

  @doc """
  Send verification code via Twilio Verify API.
  Returns {:ok, verification_sid} or {:error, reason}.
  """
  def send_verification_code(phone_number) do
    body = URI.encode_query(%{
      "To" => phone_number,
      "Channel" => "sms"
    })

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Authorization", "Basic " <> Base.encode64("#{get_account_sid()}:#{get_auth_token()}")}
    ]

    case HTTPoison.post(base_url(), body, headers) do
      {:ok, %{status_code: 201, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"sid" => sid}} -> {:ok, sid}
          _ -> {:error, "Invalid Twilio response"}
        end

      {:ok, %{status_code: status, body: error_body}} ->
        {:error, "Twilio error (#{status}): #{error_body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  @doc """
  Check verification code via Twilio Verify API.
  Takes phone_number and code (not verification_sid).
  Returns {:ok, :verified} or {:error, reason}.
  """
  def check_verification_code(phone_number, code) do
    url = "https://verify.twilio.com/v2/Services/#{get_verify_service_sid()}/VerificationCheck"

    body = URI.encode_query(%{
      "To" => phone_number,
      "Code" => code
    })

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Authorization", "Basic " <> Base.encode64("#{get_account_sid()}:#{get_auth_token()}")}
    ]

    case HTTPoison.post(url, body, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"status" => "approved"}} -> {:ok, :verified}
          {:ok, %{"status" => status}} -> {:error, "Verification failed: #{status}"}
          _ -> {:error, "Invalid Twilio response"}
        end

      {:ok, %{status_code: status, body: error_body}} ->
        {:error, "Twilio error (#{status}): #{error_body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  @doc """
  Lookup phone number to get country, carrier, and line type.
  Uses Twilio Lookup API v2.
  Returns {:ok, phone_data} or {:error, reason}.
  """
  def lookup_phone_number(phone_number) do
    url = "#{@lookup_url}/#{URI.encode(phone_number)}?Fields=line_type_intelligence"

    headers = [
      {"Authorization", "Basic " <> Base.encode64("#{get_account_sid()}:#{get_auth_token()}")}
    ]

    case HTTPoison.get(url, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, data} ->
            {:ok, %{
              country_code: data["country_code"],
              carrier_name: get_in(data, ["line_type_intelligence", "carrier_name"]),
              line_type: get_in(data, ["line_type_intelligence", "type"]),
              fraud_flags: %{
                error_code: get_in(data, ["line_type_intelligence", "error_code"])
              }
            }}

          _ ->
            {:error, "Invalid Twilio Lookup response"}
        end

      {:ok, %{status_code: 404}} ->
        {:error, "Phone number not found or invalid"}

      {:ok, %{status_code: status, body: error_body}} ->
        {:error, "Twilio Lookup error (#{status}): #{error_body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end
end
