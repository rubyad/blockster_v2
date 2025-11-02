defmodule BlocksterV2Web.LoginLive do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Redirect if already logged in
    if socket.assigns[:current_user] do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      socket =
        socket
        |> assign(page_title: "Connect Wallet")
        |> assign(ui_state: :wallet_selection)
        |> assign(pending_email: nil)

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("show_email_form", _params, socket) do
    {:noreply, assign(socket, ui_state: :email_input)}
  end

  @impl true
  def handle_event("show_code_input", %{"email" => email}, socket) do
    socket =
      socket
      |> assign(ui_state: :code_input)
      |> assign(pending_email: email)

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_loading", _params, socket) do
    {:noreply, assign(socket, ui_state: :loading)}
  end

  @impl true
  def handle_event("back_to_wallets", _params, socket) do
    socket =
      socket
      |> assign(ui_state: :wallet_selection)
      |> assign(pending_email: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("back_to_email", _params, socket) do
    {:noreply, assign(socket, ui_state: :email_input)}
  end
end
