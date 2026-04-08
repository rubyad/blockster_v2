defmodule BlocksterV2Web.EmailVerificationModalComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.Accounts.EmailVerification

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:step, fn -> :enter_email end)
     |> assign_new(:email_address, fn -> assigns.current_user.email || "" end)
     |> assign_new(:error_message, fn -> nil end)
     |> assign_new(:success_message, fn -> nil end)
     |> assign_new(:countdown, fn -> nil end)}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    send(self(), {:close_email_verification_modal})
    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("submit_email", %{"email" => email}, socket) do
    user = socket.assigns.current_user

    case EmailVerification.send_verification_code(user, email) do
      {:ok, updated_user} ->
        # Reuses parent's :countdown_tick handler (shared with phone modal — only one open at a time)
        Process.send_after(self(), {:countdown_tick, 60}, 1000)

        pending = updated_user.pending_email || updated_user.email

        {:noreply,
         socket
         |> assign(:current_user, updated_user)
         |> assign(:step, :enter_code)
         |> assign(:email_address, pending)
         |> assign(:countdown, 60)
         |> assign(:error_message, nil)
         |> assign(:success_message, "Code sent to #{pending}")}

      {:error, %Ecto.Changeset{errors: errors}} ->
        error_msg = errors |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end) |> Enum.join(", ")
        {:noreply, assign(socket, :error_message, error_msg)}

      {:error, _} ->
        {:noreply, assign(socket, :error_message, "Failed to send verification code. Please try again.")}
    end
  end

  @impl true
  def handle_event("submit_code", %{"code" => code}, socket) do
    user = socket.assigns.current_user

    case EmailVerification.verify_code(user, code) do
      {:ok, verified_user, _info} ->
        {:noreply,
         socket
         |> assign(:step, :success)
         |> assign(:current_user, verified_user)
         |> assign(:error_message, nil)}

      {:error, :invalid_code} ->
        {:noreply, assign(socket, :error_message, "Invalid verification code. Please try again.")}

      {:error, :code_expired} ->
        {:noreply, assign(socket, :error_message, "Code expired. Please request a new one.")}

      {:error, :no_code_sent} ->
        {:noreply, assign(socket, :error_message, "No code sent yet. Please request one first.")}

      {:error, _} ->
        {:noreply, assign(socket, :error_message, "Verification failed. Please try again.")}
    end
  end

  @impl true
  def handle_event("resend_code", _params, socket) do
    handle_event("submit_email", %{"email" => socket.assigns.email_address}, socket)
  end

  @impl true
  def handle_event("change_email", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :enter_email)
     |> assign(:error_message, nil)
     |> assign(:success_message, nil)}
  end

  @impl true
  def handle_event("close_success", _params, socket) do
    send(self(), {:close_email_verification_modal})
    send(self(), {:refresh_user_data})
    {:noreply, socket}
  end
end
