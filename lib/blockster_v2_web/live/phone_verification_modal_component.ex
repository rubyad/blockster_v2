defmodule BlocksterV2Web.PhoneVerificationModalComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.PhoneVerification

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:step, fn -> :enter_phone end)
     |> assign_new(:phone_number, fn -> "" end)
     |> assign_new(:error_message, fn -> nil end)
     |> assign_new(:success_message, fn -> nil end)
     |> assign_new(:countdown, fn -> nil end)}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    send(self(), {:close_phone_verification_modal})
    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("submit_phone", %{"phone_number" => phone} = params, socket) do
    user_id = socket.assigns.current_user.id
    sms_opt_in = Map.get(params, "sms_opt_in") == "true"

    case PhoneVerification.send_verification_code(user_id, phone, sms_opt_in) do
      {:ok, _verification} ->
        # Start countdown timer for resend button (runs in parent LiveView)
        Process.send_after(self(), {:countdown_tick, 60}, 1000)

        {:noreply,
         socket
         |> assign(:step, :enter_code)
         |> assign(:phone_number, phone)
         |> assign(:countdown, 60)
         |> assign(:error_message, nil)
         |> assign(:success_message, "Code sent to #{format_phone_number(phone)}")}

      {:error, %Ecto.Changeset{errors: errors}} ->
        error_msg = errors |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end) |> Enum.join(", ")
        {:noreply, assign(socket, :error_message, error_msg)}

      {:error, reason} when is_binary(reason) ->
        {:noreply, assign(socket, :error_message, reason)}

      {:error, _} ->
        {:noreply, assign(socket, :error_message, "Failed to send verification code. Please try again.")}
    end
  end

  @impl true
  def handle_event("submit_code", %{"code" => code}, socket) do
    user_id = socket.assigns.current_user.id

    case PhoneVerification.verify_code(user_id, code) do
      {:ok, verification} ->
        {:noreply,
         socket
         |> assign(:step, :success)
         |> assign(:verification, verification)
         |> assign(:error_message, nil)}

      {:error, reason} when is_binary(reason) ->
        {:noreply, assign(socket, :error_message, reason)}

      {:error, _} ->
        {:noreply, assign(socket, :error_message, "Invalid verification code. Please try again.")}
    end
  end

  @impl true
  def handle_event("resend_code", _params, socket) do
    handle_event("submit_phone", %{"phone_number" => socket.assigns.phone_number}, socket)
  end

  @impl true
  def handle_event("change_phone", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :enter_phone)
     |> assign(:error_message, nil)
     |> assign(:success_message, nil)}
  end

  @impl true
  def handle_event("close_success", _params, socket) do
    send(self(), {:close_phone_verification_modal})
    send(self(), {:refresh_user_data})
    {:noreply, socket}
  end

  # Helper to format phone number for display
  defp format_phone_number(phone) do
    # Format +12345678900 as +1 (234) 567-8900
    case Regex.run(~r/^\+(\d{1,3})(\d{3})(\d{3})(\d{4})/, phone) do
      [_, country, area, prefix, line] ->
        "+#{country} (#{area}) #{prefix}-#{line}"
      _ ->
        phone
    end
  end
end
