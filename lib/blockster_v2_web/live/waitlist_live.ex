defmodule BlocksterV2Web.WaitlistLive do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Waitlist

  @impl true
  def mount(params, _session, socket) do
    # Check for verification token
    status = params["status"]
    message = params["message"]

    ui_state =
      cond do
        status == "success" && message -> :verified
        status == "error" && message -> :error
        true -> :email_input
      end

    # Capture the base URL from the current request
    base_url = get_base_url(socket)

    socket =
      socket
      |> assign(page_title: "Join Blockster Waitlist")
      |> assign(ui_state: ui_state)
      |> assign(message: message)
      |> assign(email: "")
      |> assign(error: nil)
      |> assign(base_url: base_url)

    {:ok, socket}
  end

  defp get_base_url(socket) do
    uri = socket.host_uri || ""

    # If host_uri is not available, construct from endpoint config
    if uri != "" do
      uri
    else
      endpoint_config = Application.get_env(:blockster_v2, BlocksterV2Web.Endpoint, [])
      url_config = endpoint_config[:url] || []
      host = url_config[:host] || "localhost"
      port = url_config[:port] || 443
      scheme = url_config[:scheme] || "https"

      if port in [80, 443] do
        "#{scheme}://#{host}"
      else
        "#{scheme}://#{host}:#{port}"
      end
    end
  end

  @impl true
  def handle_event("join_waitlist", %{"email" => email}, socket) do
    base_url = socket.assigns.base_url

    case Waitlist.create_waitlist_email(%{email: email}) do
      {:ok, waitlist_email} ->
        # Send verification email with the current domain's base URL
        case Waitlist.send_verification_email(waitlist_email, base_url) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(ui_state: :email_sent)
             |> assign(email: email)}

          {:error, _reason} ->
            {:noreply, assign(socket, error: "Failed to send verification email. Please try again.")}
        end

      {:error, %Ecto.Changeset{errors: [email: {"has already been taken", _}]}} ->
        # Email already exists, check if verified
        case Waitlist.get_waitlist_email_by_email(email) do
          %{verified_at: nil} = waitlist_email ->
            # Not verified, resend verification email with the current domain's base URL
            case Waitlist.send_verification_email(waitlist_email, base_url) do
              {:ok, _} ->
                {:noreply,
                 socket
                 |> assign(ui_state: :email_sent)
                 |> assign(email: email)}

              {:error, _reason} ->
                {:noreply, assign(socket, error: "Failed to send verification email. Please try again.")}
            end

          _ ->
            # Already verified
            {:noreply, assign(socket, error: "You're already on the waitlist!")}
        end

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        error_message = errors |> Map.values() |> List.first() |> List.first() || "Invalid email"

        {:noreply, assign(socket, error: "Email #{error_message}")}
    end
  end

  @impl true
  def handle_event("back_to_input", _params, socket) do
    {:noreply,
     socket
     |> assign(ui_state: :email_input)
     |> assign(email: "")
     |> assign(error: nil)
     |> assign(message: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-start md:items-center justify-end relative overflow-hidden pt-12 md:pt-0" style="background-image: url('https://ik.imagekit.io/blockster/email-moon-left.jpg'); background-size: cover; background-position: center;">
      <!-- Background overlay for better text readability -->
      <div class="absolute inset-0 bg-black/10"></div>

      <div class="relative z-10 w-full md:max-w-md mr-0 md:mr-8 lg:mr-32 px-6 py-12 text-center bg-gray-900/30 backdrop-blur-sm rounded-none md:rounded-2xl">
        <!-- Logo or Branding -->
        <div class="mb-8">
          <div class="inline-flex items-center justify-center mb-4">
            <img src="https://ik.imagekit.io/blockster/logo.png" alt="Blockster Logo" class="w-20 h-20 object-contain" />
          </div>
          <h1 class="text-5xl md:text-6xl font-bold text-white mb-4">
            Blockster V2
          </h1>
        </div>

        <!-- Main Content Area -->
        <div :if={@ui_state == :email_input} class="space-y-6">
          <p class="text-xl md:text-2xl text-white/90 mb-8">
            Read and earn $BUX to get crypto airdrops, merch and event passes.
          </p>

          <div class="max-w-md mx-auto">
            <form phx-submit="join_waitlist" class="space-y-4">
              <div class="relative">
                <input
                  type="email"
                  name="email"
                  value={@email}
                  placeholder="Enter your email address"
                  required
                  class="w-full px-6 py-4 text-lg rounded-xl border-2 border-white/20 bg-white/10 backdrop-blur-sm text-white placeholder-white/60 focus:outline-none focus:border-white/40 focus:bg-white/20 transition-all"
                />
              </div>

              <button
                type="submit"
                class="w-full px-8 py-4 bg-white text-black text-lg font-bold rounded-xl hover:bg-green-50 transition-all transform hover:scale-105 shadow-xl"
              >
                Join Waitlist
              </button>

              <div :if={@error} class="p-4 bg-red-500/20 backdrop-blur-sm border border-red-300/30 rounded-lg">
                <p class="text-white text-sm"><%= @error %></p>
              </div>
            </form>
          </div>
        </div>

        <div :if={@ui_state == :email_sent} class="space-y-6">
          <div class="max-w-2xl mx-auto">
            <div class="mb-6">
              <svg
                class="w-20 h-20 mx-auto text-white"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                />
              </svg>
            </div>
            <h2 class="text-4xl font-bold text-white mb-4">Check Your Email!</h2>
            <p class="text-xl text-white/90">
              Thanks for joining the waitlist! We've sent a verification link to
              <span class="font-semibold"><%= @email %></span>
            </p>
            <p class="text-lg text-white/80 mt-4">
              Please verify your email to complete your registration.
            </p>
          </div>
        </div>

        <div :if={@ui_state == :verified} class="space-y-6">
          <div class="max-w-2xl mx-auto">
            <div class="mb-6">
              <svg
                class="w-20 h-20 mx-auto text-white"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
            </div>
            <h2 class="text-4xl font-bold text-white mb-4">You're In!</h2>
            <p class="text-xl text-white/90">
              <%= @message %>
            </p>
            <p class="text-lg text-white/80 mt-4">
              We'll notify you when the new Blockster launches.
            </p>
          </div>
        </div>

        <div :if={@ui_state == :error} class="space-y-6">
          <div class="max-w-2xl mx-auto">
            <div class="mb-6">
              <svg
                class="w-20 h-20 mx-auto text-white"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
            </div>
            <h2 class="text-4xl font-bold text-white mb-4">Oops!</h2>
            <p class="text-xl text-white/90">
              <%= @message %>
            </p>
            <button
              phx-click="back_to_input"
              class="mt-6 px-8 py-3 bg-white text-green-600 font-bold rounded-xl hover:bg-green-50 transition-all"
            >
              Try Again
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
