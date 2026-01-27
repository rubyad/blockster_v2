defmodule BlocksterV2.TwilioClientBehaviour do
  @moduledoc """
  Behaviour for Twilio client operations.
  Allows mocking in tests.
  """

  @callback send_verification_code(phone_number :: String.t()) ::
    {:ok, verification_sid :: String.t()} | {:error, reason :: any()}

  @callback check_verification_code(verification_sid :: String.t(), code :: String.t()) ::
    {:ok, :verified} | {:error, reason :: any()}

  @callback lookup_phone_number(phone_number :: String.t()) ::
    {:ok, %{
      country_code: String.t(),
      carrier_name: String.t() | nil,
      line_type: String.t() | nil,
      fraud_flags: map()
    }} | {:error, reason :: any()}
end
