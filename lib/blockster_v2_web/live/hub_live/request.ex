defmodule BlocksterV2Web.HubLive.Request do
  @moduledoc """
  Public-facing hub request form at `/hubs/request`.

  Top Web3 projects fill in a 10-question application; on submit we email
  the team via `BlocksterV2.Emails.HubRequestEmail` and swap the form for
  a confirmation card.
  """

  use BlocksterV2Web, :live_view

  require Logger

  alias BlocksterV2.Emails.HubRequestEmail
  alias BlocksterV2.Mailer

  @required_fields ~w(project_name website_url contact_name contact_email x_handle telegram_handle category description)

  @partners [
    {"MoonPay", "moonpay.com"},
    {"TRON", "tron.network"},
    {"Binance", "binance.com"},
    {"Bybit", "bybit.com"},
    {"KuCoin", "kucoin.com"},
    {"Bitget", "bitget.com"},
    {"Solana", "solana.com"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Launch Your Hub on Blockster")
     |> assign(:submitted, false)
     |> assign(:form_error, nil)
     |> assign(:partners, @partners)}
  end

  @impl true
  def handle_event("submit", params, socket) do
    case validate(params) do
      :ok ->
        params
        |> HubRequestEmail.admin_notification()
        |> Mailer.deliver()
        |> case do
          {:ok, _} ->
            Logger.info("Hub request submitted: #{params["project_name"]} (#{params["contact_email"]})")

          {:error, reason} ->
            Logger.error("Hub request email failed for #{params["project_name"]}: #{inspect(reason)}")
        end

        {:noreply, assign(socket, submitted: true, form_error: nil)}

      {:error, message} ->
        {:noreply, assign(socket, form_error: message)}
    end
  end

  defp validate(params) do
    missing =
      Enum.filter(@required_fields, fn field ->
        case Map.get(params, field) do
          nil -> true
          "" -> true
          _ -> false
        end
      end)

    if missing == [] do
      :ok
    else
      {:error, "Please fill in all required fields."}
    end
  end
end
