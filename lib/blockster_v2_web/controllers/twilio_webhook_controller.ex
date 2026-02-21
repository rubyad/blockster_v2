defmodule BlocksterV2Web.TwilioWebhookController do
  @moduledoc """
  Handles Twilio SMS webhook callbacks.
  Processes opt-out (STOP) and opt-in (START) messages to update user preferences.
  """

  use BlocksterV2Web, :controller

  alias BlocksterV2.{Repo, Notifications}
  alias BlocksterV2.Accounts.{User, PhoneVerification}
  import Ecto.Query

  require Logger

  @doc """
  Handle incoming Twilio SMS status/reply webhook.
  Twilio sends POST with params including From, Body, OptOutType, etc.
  """
  def handle(conn, params) do
    phone_number = params["From"]
    body = params["Body"] |> to_string() |> String.trim() |> String.upcase()
    opt_out_type = params["OptOutType"]

    Logger.info("[TwilioWebhook] Received: phone=#{phone_number}, body=#{body}, opt_out=#{opt_out_type}")

    cond do
      opt_out_type in ["STOP", "STOP ALL"] || body in ["STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT"] ->
        handle_opt_out(phone_number)

      opt_out_type == "START" || body in ["START", "YES", "UNSTOP"] ->
        handle_opt_in(phone_number)

      true ->
        :ok
    end

    # Twilio expects 200 with empty TwiML
    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, "<Response></Response>")
  end

  defp handle_opt_out(phone_number) when is_binary(phone_number) do
    case get_user_by_phone(phone_number) do
      nil ->
        Logger.info("[TwilioWebhook] No user found for phone #{phone_number}")

      {user, verification} ->
        Logger.info("[TwilioWebhook] Opting out user #{user.id} from SMS")

        # Update phone verification record
        verification
        |> Ecto.Changeset.change(%{sms_opt_in: false})
        |> Repo.update!()

        # Update user record
        user
        |> Ecto.Changeset.change(%{sms_opt_in: false})
        |> Repo.update!()

        # Update notification preferences
        Notifications.update_preferences(user.id, %{sms_enabled: false})
    end
  end

  defp handle_opt_out(_), do: :ok

  defp handle_opt_in(phone_number) when is_binary(phone_number) do
    case get_user_by_phone(phone_number) do
      nil ->
        Logger.info("[TwilioWebhook] No user found for phone #{phone_number}")

      {user, verification} ->
        Logger.info("[TwilioWebhook] Opting in user #{user.id} for SMS")

        verification
        |> Ecto.Changeset.change(%{sms_opt_in: true})
        |> Repo.update!()

        user
        |> Ecto.Changeset.change(%{sms_opt_in: true})
        |> Repo.update!()

        Notifications.update_preferences(user.id, %{sms_enabled: true})
    end
  end

  defp handle_opt_in(_), do: :ok

  defp get_user_by_phone(phone_number) do
    case Repo.one(from pv in PhoneVerification, where: pv.phone_number == ^phone_number and pv.verified == true) do
      nil -> nil
      verification ->
        user = Repo.get(User, verification.user_id)
        if user, do: {user, verification}, else: nil
    end
  end
end
