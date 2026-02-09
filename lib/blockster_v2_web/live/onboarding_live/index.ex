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
        # Get user's current multipliers for display
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
              />
            <% "wallet" -> %>
              <.wallet_step user={@user} />
            <% "x" -> %>
              <.x_step user={@user} multipliers={@multipliers} />
            <% "complete" -> %>
              <.complete_step user={@user} multipliers={@multipliers} />
            <% "rogue" -> %>
              <.rogue_step />
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
          class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
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
          <div class="w-16 h-16 flex items-center justify-center border border-gray-300 rounded-xl">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-8 h-8"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M15.75 10.5V6a3.75 3.75 0 1 0-7.5 0v4.5m11.356-1.993 1.263 12c.07.665-.45 1.243-1.119 1.243H4.25a1.125 1.125 0 0 1-1.12-1.243l1.264-12A1.125 1.125 0 0 1 5.513 7.5h12.974c.576 0 1.059.435 1.119 1.007ZM8.625 10.5a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Zm7.5 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z"
              />
            </svg>
          </div>
          <span class="text-xs text-gray-500">Shop</span>
        </div>

        <div
          class="flex flex-col items-center space-y-2 animate-fade-in"
          style="animation-delay: 100ms"
        >
          <div class="w-16 h-16 flex items-center justify-center border border-gray-300 rounded-xl">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-8 h-8"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M14.25 6.087c0-.355.186-.676.401-.959.221-.29.349-.634.349-1.003 0-1.036-1.007-1.875-2.25-1.875s-2.25.84-2.25 1.875c0 .369.128.713.349 1.003.215.283.401.604.401.959v0a.64.64 0 0 1-.657.643 48.39 48.39 0 0 1-4.163-.3c.186 1.613.293 3.25.315 4.907a.656.656 0 0 1-.658.663v0c-.355 0-.676-.186-.959-.401a1.647 1.647 0 0 0-1.003-.349c-1.036 0-1.875 1.007-1.875 2.25s.84 2.25 1.875 2.25c.369 0 .713-.128 1.003-.349.283-.215.604-.401.959-.401v0c.31 0 .555.26.532.57a48.039 48.039 0 0 1-.642 5.056c1.518.19 3.058.309 4.616.354a.64.64 0 0 0 .657-.643v0c0-.355-.186-.676-.401-.959a1.647 1.647 0 0 1-.349-1.003c0-1.035 1.008-1.875 2.25-1.875 1.243 0 2.25.84 2.25 1.875 0 .369-.128.713-.349 1.003-.215.283-.4.604-.4.959v0c0 .333.277.599.61.58a48.1 48.1 0 0 0 5.427-.63 48.05 48.05 0 0 0 .582-4.717.532.532 0 0 0-.533-.57v0c-.355 0-.676.186-.959.401-.29.221-.634.349-1.003.349-1.035 0-1.875-1.007-1.875-2.25s.84-2.25 1.875-2.25c.37 0 .713.128 1.003.349.283.215.604.401.96.401v0a.656.656 0 0 0 .658-.663 48.422 48.422 0 0 0-.37-5.36c-1.886.342-3.81.574-5.766.689a.578.578 0 0 1-.61-.58v0Z"
              />
            </svg>
          </div>
          <span class="text-xs text-gray-500">Games</span>
        </div>

        <div
          class="flex flex-col items-center space-y-2 animate-fade-in"
          style="animation-delay: 200ms"
        >
          <div class="w-16 h-16 flex items-center justify-center border border-gray-300 rounded-xl">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-8 h-8"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M21 11.25v8.25a1.5 1.5 0 0 1-1.5 1.5H5.25a1.5 1.5 0 0 1-1.5-1.5v-8.25M12 4.875A2.625 2.625 0 1 0 9.375 7.5H12m0-2.625V7.5m0-2.625A2.625 2.625 0 1 1 14.625 7.5H12m0 0V21m-8.625-9.75h18c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125h-18c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125Z"
              />
            </svg>
          </div>
          <span class="text-xs text-gray-500">Drops</span>
        </div>
      </div>

      <!-- Headlines -->
      <div class="space-y-4">
        <h1 class="font-haas_medium_65 text-3xl md:text-4xl text-black">
          Redeem Your BUX
        </h1>
        <p class="font-haas_roman_55 text-lg text-gray-600">
          Cool merch, games and airdrops
        </p>
      </div>

      <!-- CTA Button -->
      <div class="pt-8">
        <.link
          patch={~p"/onboarding/profile"}
          class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
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
      <!-- Multiplier visualization -->
      <div class="flex flex-col items-center space-y-2">
        <div class="text-gray-400 text-3xl font-haas_medium_65">
          <%= format_multiplier(@current_multiplier) %>
        </div>
        <div class="text-gray-400">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
            class="w-6 h-6 animate-bounce"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 13.5 12 21m0 0-7.5-7.5M12 21V3" />
          </svg>
        </div>
        <div class="text-4xl font-haas_medium_65 text-black">
          <span class="bg-[#CAFC00] px-2 rounded"><%= format_multiplier(@max_multiplier) %></span>
        </div>
      </div>

      <!-- Headlines -->
      <div class="space-y-4">
        <h1 class="font-haas_medium_65 text-3xl md:text-4xl text-black">
          Complete Your Profile
        </h1>
        <p class="font-haas_roman_55 text-lg text-gray-600">
          Increase your earning power by connecting your accounts
        </p>
      </div>

      <!-- CTAs -->
      <div class="pt-8 space-y-4">
        <.link
          patch={~p"/onboarding/phone"}
          class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
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
        <div class="w-16 h-16 flex items-center justify-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="w-12 h-12"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M10.5 1.5H8.25A2.25 2.25 0 0 0 6 3.75v16.5a2.25 2.25 0 0 0 2.25 2.25h7.5A2.25 2.25 0 0 0 18 20.25V3.75a2.25 2.25 0 0 0-2.25-2.25H13.5m-3 0V3h3V1.5m-3 0h3m-3 18.75h3"
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
          Verify to boost earnings
        </p>
        <div class="text-sm font-haas_roman_55">
          <span class="text-gray-400">0.5x</span>
          <span class="mx-2">→</span>
          <span class="text-black font-haas_medium_65">2.0x</span>
          <span class="text-[#CAFC00]"> (premium)</span>
        </div>
      </div>

      <%= cond do %>
        <% @phone_verified -> %>
          <!-- Already verified state (from previous session) -->
          <div class="pt-4">
            <div class="flex items-center justify-center gap-2 text-green-600">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
              </svg>
              <span class="font-haas_medium_65">Phone Verified!</span>
            </div>
          </div>

          <div class="pt-6">
            <.link
              patch={~p"/onboarding/wallet"}
              class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
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
                class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
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
                class="w-full bg-black text-white font-haas_medium_65 py-4 rounded-full hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
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
          <div class="pt-4 space-y-6">
            <div class="flex items-center justify-center gap-2 text-green-600">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-8 h-8">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
              </svg>
              <span class="font-haas_medium_65 text-xl">Phone Verified!</span>
            </div>

            <!-- Multiplier Visualization -->
            <div class="bg-gradient-to-br from-gray-50 to-gray-100 rounded-lg p-6">
              <div class="text-sm text-gray-600 mb-2">Your BUX Earnings Multiplier</div>
              <div class="flex items-center justify-center gap-4 mb-4">
                <div class="text-center">
                  <div class="text-3xl font-haas_medium_65 text-gray-400 line-through">0.5x</div>
                  <div class="text-xs text-gray-500">Before</div>
                </div>
                <svg class="w-6 h-6 text-black" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z" clip-rule="evenodd"/>
                </svg>
                <div class="text-center">
                  <div class="text-3xl font-haas_medium_65 text-black">
                    <%= if @verification_result, do: "#{@verification_result.geo_multiplier}x", else: "2.0x" %>
                  </div>
                  <div class="text-xs text-gray-600">After</div>
                </div>
              </div>

              <%= if @verification_result do %>
                <div class="flex justify-center">
                  <div class="bg-white rounded-lg px-4 py-2">
                    <span class="text-gray-600">Country: </span>
                    <span class="font-haas_medium_65"><%= @verification_result.country_code %></span>
                  </div>
                </div>
              <% end %>
            </div>

            <.link
              patch={~p"/onboarding/wallet"}
              class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
            >
              Continue
            </.link>
          </div>
      <% end %>
    </div>
    """
  end

  defp wallet_step(assigns) do
    # Check if wallet already connected
    wallet_connected = assigns.user.smart_wallet_address != nil
    assigns = assign(assigns, wallet_connected: wallet_connected)

    ~H"""
    <div class="text-center space-y-6">
      <!-- Step indicator -->
      <div class="text-sm text-gray-400 font-haas_roman_55">
        Step 2 of 3
      </div>

      <!-- Icon -->
      <div class="flex justify-center">
        <div class="w-16 h-16 flex items-center justify-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="w-12 h-12"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M21 12a2.25 2.25 0 0 0-2.25-2.25H15a3 3 0 1 1-6 0H5.25A2.25 2.25 0 0 0 3 12m18 0v6a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 18v-6m18 0V9M3 12V9m18 0a2.25 2.25 0 0 0-2.25-2.25H5.25A2.25 2.25 0 0 0 3 9m18 0V6a2.25 2.25 0 0 0-2.25-2.25H5.25A2.25 2.25 0 0 0 3 6v3"
            />
          </svg>
        </div>
      </div>

      <!-- Headlines -->
      <div class="space-y-3">
        <h1 class="font-haas_medium_65 text-2xl md:text-3xl text-black">
          Connect Your Wallet
        </h1>
        <p class="font-haas_roman_55 text-base text-gray-600">
          Receive BUX rewards on-chain
        </p>
      </div>

      <%= if @wallet_connected do %>
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
              <%= String.slice(@user.smart_wallet_address, 0..5) <>
                "..." <> String.slice(@user.smart_wallet_address, -4..-1) %>
            </span>
          </div>
        </div>

        <div class="pt-6">
          <.link
            patch={~p"/onboarding/x"}
            class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
          >
            Continue
          </.link>
        </div>
      <% else %>
        <!-- Connect wallet UI -->
        <div class="pt-4 space-y-4">
          <button
            class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
            phx-click="connect_wallet"
          >
            Connect Wallet
          </button>

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

      <!-- X Logo -->
      <div class="flex justify-center">
        <div class="w-16 h-16 flex items-center justify-center">
          <span class="text-5xl font-bold">𝕏</span>
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
        <div class="text-sm font-haas_roman_55 text-[#CAFC00]">
          Up to 10.0x multiplier
        </div>
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
            class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
          >
            Continue
          </.link>
        </div>
      <% else %>
        <!-- Connect X UI -->
        <div class="pt-4 space-y-4">
          <.link
            href={~p"/auth/x"}
            class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
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
        wallet_connected: assigns.user.smart_wallet_address != nil,
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
        <div class="inline-block border-2 border-black rounded-lg px-6 py-3">
          <span class="text-5xl font-haas_medium_65">
            <%= format_multiplier(@multipliers.overall_multiplier) %>
          </span>
        </div>
        <div class="text-gray-500 font-haas_roman_55">
          Earning Power
        </div>
      </div>

      <!-- Breakdown -->
      <div class="text-left max-w-xs mx-auto space-y-2 text-sm">
        <!-- Phone -->
        <div class="flex items-center gap-2">
          <%= if @phone_connected do %>
            <span class="text-green-500">✓</span>
            <span>Phone</span>
            <span class="ml-auto text-[#CAFC00]">
              +<%= format_multiplier(@multipliers.phone_multiplier - 0.5) %>
            </span>
          <% else %>
            <span class="text-gray-300">○</span>
            <span class="text-gray-400">Phone</span>
            <span class="ml-auto text-gray-400">+1.5x potential</span>
          <% end %>
        </div>

        <!-- Wallet -->
        <div class="flex items-center gap-2">
          <%= if @wallet_connected do %>
            <span class="text-green-500">✓</span>
            <span>Wallet</span>
            <span class="ml-auto text-gray-500">Connected</span>
          <% else %>
            <span class="text-gray-300">○</span>
            <span class="text-gray-400">Wallet</span>
            <span class="ml-auto text-gray-400">Not connected</span>
          <% end %>
        </div>

        <!-- X -->
        <div class="flex items-center gap-2">
          <%= if @x_connected do %>
            <span class="text-green-500">✓</span>
            <span>X</span>
            <span class="ml-auto text-[#CAFC00]">
              +<%= format_multiplier(@multipliers.x_multiplier - 1.0) %>
            </span>
          <% else %>
            <span class="text-gray-300">○</span>
            <span class="text-gray-400">X</span>
            <span class="ml-auto text-gray-400">+9.0x potential</span>
          <% end %>
        </div>
      </div>

      <!-- CTA -->
      <div class="pt-6">
        <.link
          patch={~p"/onboarding/rogue"}
          class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
        >
          Start Earning
        </.link>
      </div>
    </div>
    """
  end

  defp rogue_step(assigns) do
    ~H"""
    <div class="text-center space-y-6">
      <!-- ROGUE Icon with animated glow -->
      <div class="flex justify-center">
        <div class="w-20 h-20 rounded-full bg-[#CAFC00] flex items-center justify-center animate-rogue-glow">
          <span class="text-2xl font-haas_medium_65 text-black">ROGUE</span>
        </div>
      </div>

      <!-- Headlines -->
      <div class="space-y-3">
        <h1 class="font-haas_medium_65 text-2xl md:text-3xl text-black">
          Psst... Want to Earn More?
        </h1>
        <p class="font-haas_roman_55 text-base text-gray-600">
          Hold ROGUE tokens for bonus rewards
        </p>
      </div>

      <!-- Benefits list -->
      <div class="text-left max-w-xs mx-auto space-y-3 text-sm text-gray-600">
        <div class="flex items-center gap-3">
          <span class="text-[#CAFC00]">•</span>
          <span>Extra BUX multiplier</span>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-[#CAFC00]">•</span>
          <span>Exclusive airdrops</span>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-[#CAFC00]">•</span>
          <span>Play BUX Booster</span>
        </div>
      </div>

      <!-- CTAs -->
      <div class="pt-6 space-y-4">
        <a
          href="https://roguechain.io"
          target="_blank"
          class="block w-full bg-black text-white font-haas_medium_65 py-4 rounded-full text-center hover:bg-[#CAFC00] hover:text-black transition-colors cursor-pointer"
        >
          Learn More
        </a>

        <.link
          navigate={~p"/"}
          class="block w-full text-gray-500 font-haas_roman_55 py-2 text-center hover:underline cursor-pointer"
        >
          Maybe Later
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
            i < @current -> "bg-[#CAFC00]"
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
