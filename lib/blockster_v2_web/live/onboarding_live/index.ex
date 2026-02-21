defmodule BlocksterV2Web.OnboardingLive.Index do
  @moduledoc """
  LiveView for the new user onboarding flow.

  Guides new users through 8 steps:
  1. Welcome - Introduction to Blockster
  2. Redeem - Show BUX redemption options
  3. Profile - Prompt to complete profile for earning power boost
  4. Phone - Connect phone for verification bonus
  5. Wallet - Connect wallet to receive on-chain rewards
  6. X - Connect X account for sharing rewards
  7. Complete - Show final earning power summary
  8. ROGUE - Optional upsell for ROGUE token holders
  """

  use BlocksterV2Web, :live_view
  alias BlocksterV2.UnifiedMultiplier
  alias BlocksterV2.PhoneVerification
  alias BlocksterV2.Wallets

  # All valid steps in order
  @steps ["welcome", "redeem", "profile", "phone", "wallet", "x", "complete", "rogue"]
  @total_steps length(@steps)

  @impl true
  def mount(_params, _session, socket) do
    # Require authenticated user
    case socket.assigns[:current_user] do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/login")}

      user ->
        # Get phone verification status (includes country_code for already verified users)
        {:ok, phone_status} = PhoneVerification.get_verification_status(user.id)

        # Check if external wallet is connected
        connected_wallet = Wallets.get_connected_wallet(user.id)

        # If wallet is connected, ensure multiplier is up to date
        if connected_wallet do
          UnifiedMultiplier.update_wallet_multiplier(user.id)
        end

        # Get user's current multipliers for display (after wallet update if any)
        multipliers = UnifiedMultiplier.get_user_multipliers(user.id)

        socket =
          socket
          |> assign(page_title: "Welcome to Blockster")
          |> assign(user: user)
          |> assign(multipliers: multipliers)
          |> assign(current_step: "welcome")
          |> assign(step_index: 0)
          |> assign(total_steps: @total_steps)
          # Phone verification state (adapted from PhoneVerificationModalComponent)
          |> assign(phone_step_state: :enter_phone)
          |> assign(phone_number: "")
          |> assign(phone_error: nil)
          |> assign(phone_success: nil)
          |> assign(phone_countdown: nil)
          |> assign(verification_result: nil)
          |> assign(phone_country_code: phone_status[:country_code])
          # External wallet connection state
          |> assign(connected_wallet: connected_wallet)

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    step = Map.get(params, "step", "welcome")

    # Validate step
    step_index = Enum.find_index(@steps, &(&1 == step))

    if step_index do
      {:noreply,
       socket
       |> assign(current_step: step)
       |> assign(step_index: step_index)
       |> assign(page_title: step_title(step))}
    else
      # Invalid step, redirect to welcome
      {:noreply, push_patch(socket, to: ~p"/onboarding/welcome")}
    end
  end

  # =============================================================================
  # Phone Verification Events (adapted from PhoneVerificationModalComponent)
  # =============================================================================

  @impl true
  def handle_event("submit_phone", %{"phone_number" => phone} = params, socket) do
    user_id = socket.assigns.user.id
    sms_opt_in = Map.get(params, "sms_opt_in") == "true"

    case PhoneVerification.send_verification_code(user_id, phone, sms_opt_in) do
      {:ok, _verification} ->
        # Start countdown timer for resend button
        Process.send_after(self(), {:countdown_tick, 60}, 1000)

        {:noreply,
         socket
         |> assign(:phone_step_state, :enter_code)
         |> assign(:phone_number, phone)
         |> assign(:phone_countdown, 60)
         |> assign(:phone_error, nil)
         |> assign(:phone_success, "Code sent to #{format_phone_display(phone)}")}

      {:error, %Ecto.Changeset{errors: errors}} ->
        error_msg = errors |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end) |> Enum.join(", ")
        {:noreply, assign(socket, :phone_error, error_msg)}

      {:error, reason} when is_binary(reason) ->
        {:noreply, assign(socket, :phone_error, reason)}

      {:error, _} ->
        {:noreply, assign(socket, :phone_error, "Failed to send verification code. Please try again.")}
    end
  end

  @impl true
  def handle_event("submit_code", %{"code" => code}, socket) do
    user_id = socket.assigns.user.id

    case PhoneVerification.verify_code(user_id, code) do
      {:ok, verification} ->
        # Refresh user and multipliers after verification
        user = BlocksterV2.Accounts.get_user(user_id)
        multipliers = UnifiedMultiplier.get_user_multipliers(user_id)

        {:noreply,
         socket
         |> assign(:phone_step_state, :success)
         |> assign(:verification_result, verification)
         |> assign(:phone_error, nil)
         |> assign(:user, user)
         |> assign(:multipliers, multipliers)}

      {:error, reason} when is_binary(reason) ->
        {:noreply, assign(socket, :phone_error, reason)}

      {:error, _} ->
        {:noreply, assign(socket, :phone_error, "Invalid verification code. Please try again.")}
    end
  end

  @impl true
  def handle_event("resend_code", _params, socket) do
    handle_event("submit_phone", %{"phone_number" => socket.assigns.phone_number, "sms_opt_in" => "true"}, socket)
  end

  @impl true
  def handle_event("change_phone", _params, socket) do
    {:noreply,
     socket
     |> assign(:phone_step_state, :enter_phone)
     |> assign(:phone_error, nil)
     |> assign(:phone_success, nil)}
  end

  @impl true
  def handle_info({:countdown_tick, remaining}, socket) do
    if remaining > 0 do
      Process.send_after(self(), {:countdown_tick, remaining - 1}, 1000)
      {:noreply, assign(socket, :phone_countdown, remaining - 1)}
    else
      {:noreply, assign(socket, :phone_countdown, nil)}
    end
  end

  # =============================================================================
  # External Wallet Connection Events
  # =============================================================================

  @impl true
  def handle_event("connect_metamask", _params, socket) do
    {:noreply, push_event(socket, "connect_wallet", %{provider: "metamask"})}
  end

  @impl true
  def handle_event("connect_coinbase", _params, socket) do
    {:noreply, push_event(socket, "connect_wallet", %{provider: "coinbase"})}
  end

  @impl true
  def handle_event("connect_walletconnect", _params, socket) do
    {:noreply, push_event(socket, "connect_wallet", %{provider: "walletconnect"})}
  end

  @impl true
  def handle_event("connect_phantom", _params, socket) do
    {:noreply, push_event(socket, "connect_wallet", %{provider: "phantom"})}
  end

  @impl true
  def handle_event("wallet_connected", %{"address" => address, "provider" => provider, "chain_id" => chain_id}, socket) do
    user_id = socket.assigns.user.id

    case Wallets.connect_wallet(%{
      user_id: user_id,
      wallet_address: address,
      provider: provider,
      chain_id: chain_id
    }) do
      {:ok, connected_wallet} ->
        # Recalculate wallet multiplier based on connected wallet balances
        UnifiedMultiplier.update_wallet_multiplier(user_id)
        # Refresh multipliers after wallet connection
        multipliers = UnifiedMultiplier.get_user_multipliers(user_id)

        {:noreply,
         socket
         |> assign(:connected_wallet, connected_wallet)
         |> assign(:multipliers, multipliers)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to connect wallet. Please try again.")}
    end
  end

  @impl true
  def handle_event("wallet_connection_error", %{"error" => error}, socket) do
    {:noreply, put_flash(socket, :error, "Connection failed: #{error}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white flex flex-col">
      <!-- Progress dots -->
      <div class="pt-8 pb-4 px-6">
        <.progress_dots current={@step_index} total={@total_steps} />
      </div>

      <!-- Main content area - centered -->
      <div class="flex-1 flex flex-col items-center justify-center px-6 pb-12">
        <div class="w-full max-w-md">
          <%= case @current_step do %>
            <% "welcome" -> %>
              <.welcome_step />
            <% "redeem" -> %>
              <.redeem_step />
            <% "profile" -> %>
              <.profile_step multipliers={@multipliers} />
            <% "phone" -> %>
              <.phone_step
                user={@user}
                multipliers={@multipliers}
                phone_step_state={@phone_step_state}
                phone_number={@phone_number}
                phone_error={@phone_error}
                phone_success={@phone_success}
                phone_countdown={@phone_countdown}
                verification_result={@verification_result}
                phone_country_code={@phone_country_code}
              />
            <% "wallet" -> %>
              <.wallet_step user={@user} connected_wallet={@connected_wallet} multipliers={@multipliers} />
            <% "x" -> %>
              <.x_step user={@user} multipliers={@multipliers} />
            <% "complete" -> %>
              <.complete_step user={@user} multipliers={@multipliers} connected_wallet={@connected_wallet} />
            <% "rogue" -> %>
              <.rogue_step user={@user} />
            <% _ -> %>
              <.welcome_step />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # =============================================================================
  # Step Components
  # =============================================================================

  defp welcome_step(assigns) do
    ~H"""
    <div class="text-center space-y-8">
      <!-- Logo with pulse animation -->
      <div class="flex justify-center">
        <div class="animate-pulse">
          <img
            src="https://ik.imagekit.io/blockster/blockster-icon.png"
            alt="Blockster"
            class="w-20 h-20"
          />
        </div>
      </div>

      <!-- Headlines -->
      <div class="space-y-4">
        <h1 class="font-haas_medium_65 text-3xl md:text-4xl text-black">
          Welcome to Blockster
        </h1>
        <p class="font-haas_roman_55 text-lg text-gray-600">
          Read, watch and share daily stories to earn BUX
        </p>
      </div>

      <!-- CTA Button -->
      <div class="pt-8">
        <.link
          patch={~p"/onboarding/redeem"}
          class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
        >
          Next
        </.link>
      </div>
    </div>
    """
  end

  defp redeem_step(assigns) do
    ~H"""
    <div class="text-center space-y-8">
      <!-- Icons row -->
      <div class="flex justify-center gap-6">
        <div class="flex flex-col items-center space-y-2 animate-fade-in" style="animation-delay: 0ms">
          <div class="w-16 h-16 flex items-center justify-center bg-[#CAFC00] rounded-xl">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="currentColor"
              class="w-8 h-8 text-black"
            >
              <path
                fill-rule="evenodd"
                d="M7.5 6v.75H5.513c-.96 0-1.764.724-1.865 1.679l-1.263 12A1.875 1.875 0 0 0 4.25 22.5h15.5a1.875 1.875 0 0 0 1.865-2.071l-1.263-12a1.875 1.875 0 0 0-1.865-1.679H16.5V6a4.5 4.5 0 1 0-9 0ZM12 3a3 3 0 0 0-3 3v.75h6V6a3 3 0 0 0-3-3Zm-3 8.25a3 3 0 1 0 6 0v-.75a.75.75 0 0 1 1.5 0v.75a4.5 4.5 0 1 1-9 0v-.75a.75.75 0 0 1 1.5 0v.75Z"
                clip-rule="evenodd"
              />
            </svg>
          </div>
          <span class="text-xs text-gray-500">Shop</span>
        </div>

        <div
          class="flex flex-col items-center space-y-2 animate-fade-in"
          style="animation-delay: 100ms"
        >
          <div class="w-16 h-16 flex items-center justify-center bg-[#CAFC00] rounded-xl">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="currentColor"
              class="w-8 h-8 text-black"
            >
              <path
                fill-rule="evenodd"
                d="M9.315 7.584C12.195 3.883 16.695 1.5 21.75 1.5a.75.75 0 0 1 .75.75c0 5.056-2.383 9.555-6.084 12.436A6.75 6.75 0 0 1 9.75 22.5a.75.75 0 0 1-.75-.75v-4.131A15.838 15.838 0 0 1 6.382 15H2.25a.75.75 0 0 1-.75-.75 6.75 6.75 0 0 1 7.815-6.666ZM15 6.75a2.25 2.25 0 1 0 0 4.5 2.25 2.25 0 0 0 0-4.5Z"
                clip-rule="evenodd"
              />
              <path d="M5.26 17.242a.75.75 0 1 0-.897-1.203 5.243 5.243 0 0 0-2.05 5.022.75.75 0 0 0 .625.627 5.243 5.243 0 0 0 5.022-2.051.75.75 0 1 0-1.202-.897 3.744 3.744 0 0 1-3.008 1.51c0-1.23.592-2.323 1.51-3.008Z" />
            </svg>
          </div>
          <span class="text-xs text-gray-500">Games</span>
        </div>

        <div
          class="flex flex-col items-center space-y-2 animate-fade-in"
          style="animation-delay: 200ms"
        >
          <div class="w-16 h-16 flex items-center justify-center bg-[#CAFC00] rounded-xl">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="currentColor"
              class="w-8 h-8 text-black"
            >
              <path
                fill-rule="evenodd"
                d="M9 4.5a.75.75 0 0 1 .721.544l.813 2.846a3.75 3.75 0 0 0 2.576 2.576l2.846.813a.75.75 0 0 1 0 1.442l-2.846.813a3.75 3.75 0 0 0-2.576 2.576l-.813 2.846a.75.75 0 0 1-1.442 0l-.813-2.846a3.75 3.75 0 0 0-2.576-2.576l-2.846-.813a.75.75 0 0 1 0-1.442l2.846-.813A3.75 3.75 0 0 0 7.466 7.89l.813-2.846A.75.75 0 0 1 9 4.5ZM18 1.5a.75.75 0 0 1 .728.568l.258 1.036c.236.94.97 1.674 1.91 1.91l1.036.258a.75.75 0 0 1 0 1.456l-1.036.258c-.94.236-1.674.97-1.91 1.91l-.258 1.036a.75.75 0 0 1-1.456 0l-.258-1.036a2.625 2.625 0 0 0-1.91-1.91l-1.036-.258a.75.75 0 0 1 0-1.456l1.036-.258a2.625 2.625 0 0 0 1.91-1.91l.258-1.036A.75.75 0 0 1 18 1.5ZM16.5 15a.75.75 0 0 1 .712.513l.394 1.183c.15.447.5.799.948.948l1.183.395a.75.75 0 0 1 0 1.422l-1.183.395c-.447.15-.799.5-.948.948l-.395 1.183a.75.75 0 0 1-1.422 0l-.395-1.183a1.5 1.5 0 0 0-.948-.948l-1.183-.395a.75.75 0 0 1 0-1.422l1.183-.395c.447-.15.799-.5.948-.948l.395-1.183A.75.75 0 0 1 16.5 15Z"
                clip-rule="evenodd"
              />
            </svg>
          </div>
          <span class="text-xs text-gray-500">Airdrop</span>
        </div>
      </div>

      <!-- Headlines -->
      <div class="space-y-4">
        <h1 class="font-haas_medium_65 text-3xl md:text-4xl text-black">
          Redeem BUX
        </h1>
        <p class="font-haas_roman_55 text-lg text-gray-600">
          For cool merch, games and airdrops
        </p>
      </div>

      <!-- CTA Button -->
      <div class="pt-8">
        <.link
          patch={~p"/onboarding/profile"}
          class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
        >
          Next
        </.link>
      </div>
    </div>
    """
  end

  defp profile_step(assigns) do
    # Calculate potential max multiplier
    max_multiplier = UnifiedMultiplier.max_overall()
    current = assigns.multipliers.overall_multiplier

    assigns = assign(assigns, max_multiplier: max_multiplier, current_multiplier: current)

    ~H"""
    <div class="text-center space-y-8">
      <!-- Headline with 20x highlight -->
      <div class="space-y-4">
        <h1 class="font-haas_medium_65 text-3xl md:text-4xl text-black leading-tight">
          Earn up to <span class="bg-[#CAFC00] px-2 py-1 rounded">20x</span> more BUX
        </h1>
        <p class="font-haas_roman_55 text-lg text-gray-600">
          Complete your profile to boost your earning power
        </p>
      </div>

      <!-- CTAs -->
      <div class="pt-8 space-y-4">
        <.link
          patch={~p"/onboarding/phone"}
          class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
        >
          Let's Go
        </.link>

        <.link
          navigate={~p"/"}
          class="block w-full text-gray-500 font-haas_roman_55 py-2 text-center hover:underline cursor-pointer"
        >
          I'll do this later
        </.link>
      </div>
    </div>
    """
  end

  defp phone_step(assigns) do
    # Check if phone already verified (from user record)
    phone_verified = assigns.user.phone_verified || false
    assigns = assign(assigns, phone_verified: phone_verified)

    ~H"""
    <div class="text-center space-y-6">
      <!-- Step indicator -->
      <div class="text-sm text-gray-400 font-haas_roman_55">
        Step 1 of 3
      </div>

      <!-- Icon -->
      <div class="flex justify-center">
        <div class="w-16 h-16 flex items-center justify-center bg-[#CAFC00] rounded-xl">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="currentColor"
            class="w-8 h-8 text-black"
          >
            <path d="M10.5 18.75a.75.75 0 0 0 0 1.5h3a.75.75 0 0 0 0-1.5h-3Z" />
            <path
              fill-rule="evenodd"
              d="M8.25 1.5A2.25 2.25 0 0 0 6 3.75v16.5a2.25 2.25 0 0 0 2.25 2.25h7.5A2.25 2.25 0 0 0 18 20.25V3.75A2.25 2.25 0 0 0 15.75 1.5h-7.5Zm7.5 1.5h-7.5a.75.75 0 0 0-.75.75v16.5c0 .414.336.75.75.75h7.5a.75.75 0 0 0 .75-.75V3.75a.75.75 0 0 0-.75-.75Z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
      </div>

      <!-- Headlines -->
      <div class="space-y-3">
        <h1 class="font-haas_medium_65 text-2xl md:text-3xl text-black">
          Connect Your Phone
        </h1>
        <p class="font-haas_roman_55 text-base text-gray-600">
          Verify to boost your BUX earnings
        </p>
      </div>

      <%= cond do %>
        <% @phone_verified -> %>
          <!-- Already verified state (from previous session) -->
          <div class="pt-4 space-y-4">
            <!-- Verified badge -->
            <div class="inline-flex items-center gap-2 px-4 py-2 bg-green-50 border border-green-200 rounded-full">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-green-600">
                <path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" />
              </svg>
              <span class="font-haas_medium_65 text-green-800">
                Phone Verified
              </span>
            </div>

            <!-- Multiplier boost display -->
            <div class="bg-gray-50 rounded-xl p-4 text-left">
              <div class="flex items-center justify-between">
                <span class="text-sm text-gray-600">Phone Multiplier</span>
                <span class="font-haas_medium_65 text-lg text-black">
                  <%= :erlang.float_to_binary(@multipliers.phone_multiplier / 1, decimals: 1) %>x
                </span>
              </div>
            </div>
          </div>

          <div class="pt-4">
            <.link
              patch={~p"/onboarding/wallet"}
              class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
            >
              Continue
            </.link>
          </div>

        <% @phone_step_state == :enter_phone -> %>
          <!-- STEP 1: Phone Number Entry -->
          <form phx-submit="submit_phone" class="text-left space-y-4 pt-4">
            <div>
              <label class="block text-sm font-haas_medium_65 text-gray-700 mb-2">
                Phone Number
              </label>
              <input
                id="phone-number-input"
                type="tel"
                name="phone_number"
                placeholder="+1 234-567-8900"
                value={@phone_number}
                class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-black focus:border-transparent"
                required
                autofocus
                phx-hook="PhoneNumberFormatter"
              />
              <p class="text-xs text-gray-700 mt-1">
                <strong>Include your country code:</strong> 1 (US/CA), 44 (UK), 91 (India)
              </p>
            </div>

            <!-- SMS Opt-in Checkbox -->
            <div>
              <label class="flex items-start cursor-pointer">
                <input
                  type="checkbox"
                  name="sms_opt_in"
                  value="true"
                  checked
                  class="mt-1 w-4 h-4 text-black border-gray-300 rounded focus:ring-black cursor-pointer"
                />
                <span class="ml-3 text-sm text-gray-700">
                  Send me special offers and promos via SMS
                </span>
              </label>
            </div>

            <%= if @phone_error do %>
              <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg text-sm">
                <%= @phone_error %>
              </div>
            <% end %>

            <div class="pt-2 space-y-3">
              <button
                type="submit"
                class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
              >
                Send Code
              </button>

              <.link
                patch={~p"/onboarding/wallet"}
                class="block w-full text-gray-500 font-haas_roman_55 py-2 text-center hover:underline cursor-pointer"
              >
                Skip for now
              </.link>
            </div>
          </form>

        <% @phone_step_state == :enter_code -> %>
          <!-- STEP 2: Code Entry -->
          <div class="pt-4 space-y-4">
            <%= if @phone_success do %>
              <div class="bg-green-50 border border-green-200 text-green-700 px-4 py-3 rounded-lg text-sm">
                <%= @phone_success %>
              </div>
            <% end %>

            <form phx-submit="submit_code" class="text-left space-y-4">
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-700 mb-2">
                  6-Digit Code
                </label>
                <input
                  id="verification-code-input"
                  type="text"
                  name="code"
                  placeholder="123456"
                  inputmode="numeric"
                  maxlength="6"
                  class="w-full px-4 py-3 text-2xl text-center border border-gray-300 rounded-lg focus:ring-2 focus:ring-black focus:border-transparent tracking-widest font-mono"
                  autofocus
                />
              </div>

              <%= if @phone_error do %>
                <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg text-sm">
                  <%= @phone_error %>
                </div>
              <% end %>

              <button
                type="submit"
                class="w-full bg-black text-white font-haas_medium_65 py-4 rounded-full hover:bg-gray-800 transition-colors cursor-pointer"
              >
                Verify Code
              </button>
            </form>

            <!-- Resend / Change Options -->
            <div class="flex justify-between text-sm pt-3 border-t border-gray-200">
              <button
                phx-click="resend_code"
                disabled={@phone_countdown && @phone_countdown > 0}
                class={"text-black hover:underline cursor-pointer #{if @phone_countdown && @phone_countdown > 0, do: "opacity-50 cursor-not-allowed"}"}
              >
                <%= if @phone_countdown && @phone_countdown > 0 do %>
                  Resend in <%= @phone_countdown %>s
                <% else %>
                  Resend Code
                <% end %>
              </button>
              <button
                phx-click="change_phone"
                class="text-gray-600 hover:underline cursor-pointer"
              >
                Change Number
              </button>
            </div>

            <div class="text-xs text-gray-500 text-center">
              Code expires in 10 minutes
            </div>
          </div>

        <% @phone_step_state == :success -> %>
          <!-- STEP 3: Success -->
          <div class="pt-4 space-y-4">
            <!-- Verified badge -->
            <div class="inline-flex items-center gap-2 px-4 py-2 bg-green-50 border border-green-200 rounded-full">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-green-600">
                <path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" />
              </svg>
              <span class="font-haas_medium_65 text-green-800">
                Phone Verified
              </span>
            </div>

            <!-- Phone number display -->
            <%= if @verification_result do %>
              <div class="text-sm text-gray-500 font-mono">
                <%= format_phone_display(@phone_number) %>
              </div>
            <% end %>

            <!-- Multiplier boost display -->
            <div class="bg-gray-50 rounded-xl p-4 text-left">
              <div class="flex items-center justify-between">
                <span class="text-sm text-gray-600">Phone Multiplier</span>
                <span class="font-haas_medium_65 text-lg text-black">
                  <%= if @verification_result, do: "#{@verification_result.geo_multiplier}x", else: "#{:erlang.float_to_binary(@multipliers.phone_multiplier / 1, decimals: 1)}x" %>
                </span>
              </div>
            </div>
          </div>

          <div class="pt-4">
            <.link
              patch={~p"/onboarding/wallet"}
              class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
            >
              Continue
            </.link>
          </div>
      <% end %>
    </div>
    """
  end

  defp wallet_step(assigns) do
    ~H"""
    <div class="text-center space-y-6" id="wallet-step" phx-hook="ConnectWalletHook">
      <!-- Step indicator -->
      <div class="text-sm text-gray-400 font-haas_roman_55">
        Step 2 of 3
      </div>

      <!-- Icon - solid wallet with lime background -->
      <div class="flex justify-center">
        <div class="w-16 h-16 bg-[#CAFC00] rounded-xl flex items-center justify-center">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-8 h-8 text-black">
            <path d="M2.273 5.625A4.483 4.483 0 0 1 5.25 4.5h13.5c1.141 0 2.183.425 2.977 1.125A3 3 0 0 0 18.75 3H5.25a3 3 0 0 0-2.977 2.625ZM2.273 8.625A4.483 4.483 0 0 1 5.25 7.5h13.5c1.141 0 2.183.425 2.977 1.125A3 3 0 0 0 18.75 6H5.25a3 3 0 0 0-2.977 2.625ZM5.25 9a3 3 0 0 0-3 3v6a3 3 0 0 0 3 3h13.5a3 3 0 0 0 3-3v-6a3 3 0 0 0-3-3H15a.75.75 0 0 0-.75.75 2.25 2.25 0 0 1-4.5 0A.75.75 0 0 0 9 9H5.25Z" />
          </svg>
        </div>
      </div>

      <!-- Headlines -->
      <div class="space-y-3">
        <h1 class="font-haas_medium_65 text-2xl md:text-3xl text-black">
          Connect Your Wallet
        </h1>
        <p class="font-haas_roman_55 text-base text-gray-600">
          Connect wallet to boost your BUX earnings
        </p>
      </div>

      <%= if @connected_wallet do %>
        <!-- Already connected state with multiplier -->
        <div class="pt-4 space-y-4">
          <!-- Connected badge -->
          <div class="inline-flex items-center gap-2 px-4 py-2 bg-green-50 border border-green-200 rounded-full">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-green-600">
              <path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" />
            </svg>
            <span class="font-haas_medium_65 text-green-800">
              <%= String.capitalize(@connected_wallet.provider) %> Connected
            </span>
          </div>

          <!-- Wallet address -->
          <div class="text-sm text-gray-500 font-mono">
            <%= String.slice(@connected_wallet.wallet_address, 0..5) %>...<%= String.slice(@connected_wallet.wallet_address, -4..-1) %>
          </div>

          <!-- Multiplier boost display -->
          <div class="bg-gray-50 rounded-xl p-4 text-left">
            <div class="flex items-center justify-between">
              <span class="text-sm text-gray-600">Wallet Multiplier</span>
              <span class="font-haas_medium_65 text-lg text-black">
                <%= format_multiplier(@multipliers.wallet_multiplier) %>
              </span>
            </div>
            <p class="text-xs text-gray-500 mt-1">
              Hold ETH or stablecoins to increase up to 3.6x
            </p>
          </div>
        </div>

        <div class="pt-4">
          <.link
            patch={~p"/onboarding/x"}
            class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
          >
            Continue
          </.link>
        </div>
      <% else %>
        <!-- Connect wallet options -->
        <div class="pt-4 space-y-4">
          <div class="grid grid-cols-2 gap-3">
            <button
              phx-click="connect_metamask"
              class="flex items-center justify-center gap-2 px-4 py-3 bg-white hover:bg-gray-50 border-2 border-gray-200 rounded-xl cursor-pointer transition-all hover:border-orange-400"
            >
              <img src="https://upload.wikimedia.org/wikipedia/commons/3/36/MetaMask_Fox.svg" alt="MetaMask" class="w-6 h-6" />
              <span class="font-haas_medium_65 text-sm text-black">MetaMask</span>
            </button>

            <button
              phx-click="connect_coinbase"
              class="flex items-center justify-center gap-2 px-4 py-3 bg-white hover:bg-gray-50 border-2 border-gray-200 rounded-xl cursor-pointer transition-all hover:border-blue-400"
            >
              <img src="https://ik.imagekit.io/blockster/coinbase-logo.png" alt="Coinbase" class="w-6 h-6" />
              <span class="font-haas_medium_65 text-sm text-black">Coinbase</span>
            </button>

            <button
              phx-click="connect_walletconnect"
              class="flex items-center justify-center gap-2 px-4 py-3 bg-white hover:bg-gray-50 border-2 border-gray-200 rounded-xl cursor-pointer transition-all hover:border-blue-500"
            >
              <img src="https://ik.imagekit.io/blockster/wallet-connect.png" alt="WalletConnect" class="w-6 h-6" />
              <span class="font-haas_medium_65 text-sm text-black">WalletConnect</span>
            </button>

            <button
              phx-click="connect_phantom"
              class="flex items-center justify-center gap-2 px-4 py-3 bg-white hover:bg-gray-50 border-2 border-gray-200 rounded-xl cursor-pointer transition-all hover:border-purple-400"
            >
              <img src="https://avatars.githubusercontent.com/u/78782331?s=280&v=4" alt="Phantom" class="w-6 h-6 rounded" />
              <span class="font-haas_medium_65 text-sm text-black">Phantom</span>
            </button>
          </div>

          <.link
            patch={~p"/onboarding/x"}
            class="block w-full text-gray-500 font-haas_roman_55 py-2 text-center hover:underline cursor-pointer"
          >
            Skip for now
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  defp x_step(assigns) do
    # Check if X already connected
    x_connected = assigns.multipliers.x_score > 0
    assigns = assign(assigns, x_connected: x_connected)

    ~H"""
    <div class="text-center space-y-6">
      <!-- Step indicator -->
      <div class="text-sm text-gray-400 font-haas_roman_55">
        Step 3 of 3
      </div>

      <!-- X Logo in lime box -->
      <div class="flex justify-center">
        <div class="w-16 h-16 bg-[#CAFC00] rounded-xl flex items-center justify-center">
          <span class="text-3xl font-bold text-black">𝕏</span>
        </div>
      </div>

      <!-- Headlines -->
      <div class="space-y-3">
        <h1 class="font-haas_medium_65 text-2xl md:text-3xl text-black">
          Connect Your X Account
        </h1>
        <p class="font-haas_roman_55 text-base text-gray-600">
          Share stories to earn BUX
        </p>
      </div>

      <%= if @x_connected do %>
        <!-- Already connected state -->
        <div class="pt-4">
          <div class="flex items-center justify-center gap-2 text-green-600">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="2"
              stroke="currentColor"
              class="w-6 h-6"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
              />
            </svg>
            <span class="font-haas_medium_65">
              X Connected (<%= format_multiplier(@multipliers.x_multiplier) %>)
            </span>
          </div>
        </div>

        <div class="pt-6">
          <.link
            patch={~p"/onboarding/complete"}
            class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
          >
            Continue
          </.link>
        </div>
      <% else %>
        <!-- Connect X UI -->
        <div class="pt-4 space-y-4">
          <.link
            href={~p"/auth/x"}
            class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
          >
            Connect X
          </.link>

          <.link
            patch={~p"/onboarding/complete"}
            class="block w-full text-gray-500 font-haas_roman_55 py-2 text-center hover:underline cursor-pointer"
          >
            Skip for now
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  defp complete_step(assigns) do
    multipliers = assigns.multipliers

    assigns =
      assign(assigns,
        phone_connected: multipliers.phone_multiplier > 0.5,
        wallet_connected: assigns.connected_wallet != nil,
        x_connected: multipliers.x_score > 0
      )

    ~H"""
    <div class="text-center space-y-6">
      <!-- Checkmark with success animation -->
      <div class="flex justify-center">
        <div class="w-16 h-16 flex items-center justify-center text-green-500 animate-scale-in">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
            class="w-16 h-16"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
            />
          </svg>
        </div>
      </div>

      <!-- Headline -->
      <h1 class="font-haas_medium_65 text-2xl md:text-3xl text-black">
        You're All Set!
      </h1>

      <!-- Earning Power Display -->
      <div class="space-y-2">
        <div class="inline-block bg-[#CAFC00] rounded-xl px-8 py-4">
          <span class="text-5xl font-haas_medium_65 text-black">
            <%= format_multiplier(@multipliers.overall_multiplier) %>
          </span>
        </div>
        <div class="text-gray-500 font-haas_roman_55">
          BUX Earning Power
        </div>
      </div>

      <!-- Breakdown -->
      <div class="text-left max-w-xs mx-auto space-y-2 text-sm">
        <!-- Phone -->
        <div class="flex items-center gap-2">
          <%= if @phone_connected do %>
            <span class="text-green-500">✓</span>
          <% else %>
            <span class="text-gray-300">○</span>
          <% end %>
          <span>Phone</span>
          <span class="ml-auto text-black font-haas_medium_65">
            <%= format_multiplier(@multipliers.phone_multiplier) %>
          </span>
        </div>

        <!-- Wallet -->
        <div class="flex items-center gap-2">
          <%= if @wallet_connected do %>
            <span class="text-green-500">✓</span>
          <% else %>
            <span class="text-gray-300">○</span>
          <% end %>
          <span>Wallet</span>
          <span class="ml-auto text-black font-haas_medium_65">
            <%= format_multiplier(@multipliers.wallet_multiplier) %>
          </span>
        </div>

        <!-- X -->
        <div class="flex items-center gap-2">
          <%= if @x_connected do %>
            <span class="text-green-500">✓</span>
          <% else %>
            <span class="text-gray-300">○</span>
          <% end %>
          <span>X</span>
          <span class="ml-auto text-black font-haas_medium_65">
            <%= format_multiplier(@multipliers.x_multiplier) %>
          </span>
        </div>
      </div>

      <!-- CTA -->
      <div class="pt-6">
        <.link
          patch={~p"/onboarding/rogue"}
          class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
        >
          Start Earning BUX
        </.link>
      </div>
    </div>
    """
  end

  defp rogue_step(assigns) do
    ~H"""
    <div class="text-center space-y-6">
      <!-- ROGUE Token Logo -->
      <div class="flex justify-center">
        <img
          src="https://ik.imagekit.io/blockster/rogue-white-in-indigo-logo.png"
          alt="ROGUE"
          class="w-16 h-16 rounded-xl"
        />
      </div>

      <!-- Headlines -->
      <div class="space-y-3">
        <h1 class="font-haas_medium_65 text-2xl md:text-3xl text-black whitespace-nowrap">Psst. Hold ROGUE to Earn More!</h1>
        <.link
          navigate={~p"/member/#{@user.smart_wallet_address}?tab=rogue"}
          class="font-haas_roman_55 text-base text-blue-500 hover:underline cursor-pointer"
        >
          Hold ROGUE to boost your BUX earnings
        </.link>
      </div>

      <!-- CTA -->
      <div class="pt-4">
        <.link
          navigate={~p"/"}
          class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-gray-800 transition-colors cursor-pointer"
        >
          Start Earning BUX
        </.link>
      </div>
    </div>
    """
  end

  # =============================================================================
  # Shared Components
  # =============================================================================

  defp progress_dots(assigns) do
    ~H"""
    <div class="flex justify-center gap-2">
      <%= for i <- 0..(@total - 1) do %>
        <div class={[
          "w-2 h-2 rounded-full transition-colors",
          cond do
            i < @current -> "bg-gray-900"
            i == @current -> "bg-black"
            true -> "border border-gray-300"
          end
        ]}>
        </div>
      <% end %>
    </div>
    """
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp step_title("welcome"), do: "Welcome to Blockster"
  defp step_title("redeem"), do: "Redeem BUX"
  defp step_title("profile"), do: "Complete Profile"
  defp step_title("phone"), do: "Connect Phone"
  defp step_title("wallet"), do: "Connect Wallet"
  defp step_title("x"), do: "Connect X"
  defp step_title("complete"), do: "All Set!"
  defp step_title("rogue"), do: "ROGUE Token"
  defp step_title(_), do: "Onboarding"

  defp format_multiplier(value) when is_float(value) do
    "#{Float.round(value, 1)}x"
  end

  defp format_multiplier(value) when is_integer(value) do
    "#{value}.0x"
  end

  defp format_multiplier(%Decimal{} = value) do
    "#{Decimal.round(value, 1)}x"
  end

  defp format_multiplier(value) when is_number(value) do
    "#{Float.round(value / 1, 1)}x"
  end

  defp format_multiplier(_), do: "1.0x"

  # Format phone number for display (adapted from PhoneVerificationModalComponent)
  defp format_phone_display(phone) do
    case Regex.run(~r/^\+(\d{1,3})(\d{3})(\d{3})(\d{4})/, phone) do
      [_, country, area, prefix, line] ->
        "+#{country} (#{area}) #{prefix}-#{line}"
      _ ->
        phone
    end
  end
end
