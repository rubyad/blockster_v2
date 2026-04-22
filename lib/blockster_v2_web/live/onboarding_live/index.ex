defmodule BlocksterV2Web.OnboardingLive.Index do
  @moduledoc """
  LiveView for the new user onboarding flow.

  Guides new users through 7 steps:
  1. Welcome - Introduction to Blockster
  2. Redeem - Show BUX redemption options
  3. Profile - Prompt to complete profile for earning power boost
  4. Phone - Connect phone for verification bonus
  5. Email - Verify email for 4x boost (0.5x → 2x)
  6. X - Connect X account for sharing rewards
  7. Complete - Show final earning power summary
  """

  use BlocksterV2Web, :live_view
  alias BlocksterV2.UnifiedMultiplier
  alias BlocksterV2.PhoneVerification
  alias BlocksterV2.Accounts.EmailVerification

  # All valid steps in order. The legacy `migrate_email` step is retired —
  # existing Blockster users reclaim their account by signing in with the
  # Web3Auth email flow (the merge happens server-side in Accounts), not
  # by connecting a wallet and then entering an email. New wallet users go
  # straight from welcome → redeem with no migration prompt.
  #
  # The runtime step list is filtered per user based on `auth_method` —
  # Web3Auth social users skip the step that corresponds to the identity
  # they already signed in with (Phase 6).
  @base_steps ["welcome", "redeem", "profile", "phone", "email", "x", "complete"]

  @impl true
  def mount(_params, _session, socket) do
    # Require authenticated user
    case socket.assigns[:current_user] do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/login")}

      user ->
        # Get phone verification status (includes country_code for already verified users)
        {:ok, phone_status} = PhoneVerification.get_verification_status(user.id)

        # Recalculate multipliers from source data so the displayed values are always
        # fresh (don't trust the cached Mnesia record — it may pre-date a multiplier
        # config change like the email floor going from 1.0x → 0.5x).
        multipliers = UnifiedMultiplier.refresh_multipliers(user.id)

        steps = build_steps_for_user(user)

        socket =
          socket
          |> assign(page_title: "Welcome to Blockster")
          |> assign(user: user)
          |> assign(multipliers: multipliers)
          |> assign(current_step: "welcome")
          |> assign(step_index: 0)
          |> assign(steps: steps)
          |> assign(total_steps: length(steps))
          # Phone verification state (adapted from PhoneVerificationModalComponent)
          |> assign(phone_step_state: :enter_phone)
          |> assign(phone_number: "")
          |> assign(phone_error: nil)
          |> assign(phone_success: nil)
          |> assign(phone_countdown: nil)
          |> assign(verification_result: nil)
          |> assign(phone_country_code: phone_status[:country_code])
          # Email verification state
          |> assign(email_step_state: :enter_email)
          |> assign(email_address: user.email || "")
          |> assign(email_error: nil)
          |> assign(email_success: nil)
          |> assign(email_countdown: nil)
          # Migration branch state (welcome → "I'm new" / "I have an account")
          |> assign(migration_intent: nil)
          |> assign(migrate_email_step_state: :enter_email)
          |> assign(migrate_email_address: "")
          |> assign(migrate_email_error: nil)
          |> assign(migrate_email_success: nil)
          |> assign(migrate_email_countdown: nil)
          |> assign(merge_summary: nil)

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    step = Map.get(params, "step", "welcome")
    steps = socket.assigns[:steps] || @base_steps

    # Validate step — must be in this user's filtered step list. If the URL
    # references a step this user skipped (e.g., social user deep-linking to
    # /onboarding/email), bounce them to the next step they actually need.
    case Enum.find_index(steps, &(&1 == step)) do
      nil ->
        {:noreply, push_patch(socket, to: ~p"/onboarding/welcome")}

      step_index ->
        {:noreply,
         socket
         |> assign(current_step: step)
         |> assign(step_index: step_index)
         |> assign(page_title: step_title(step))}
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

  # =============================================================================
  # Email Verification Events
  # =============================================================================

  @impl true
  def handle_event("submit_email", %{"email" => email}, socket) do
    user = socket.assigns.user

    case EmailVerification.send_verification_code(user, email) do
      {:ok, updated_user} ->
        Process.send_after(self(), {:email_countdown_tick, 60}, 1000)

        pending = updated_user.pending_email || updated_user.email

        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:email_step_state, :enter_code)
         |> assign(:email_address, pending)
         |> assign(:email_countdown, 60)
         |> assign(:email_error, nil)
         |> assign(:email_success, "Code sent to #{pending}")}

      {:error, %Ecto.Changeset{errors: errors}} ->
        error_msg = errors |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end) |> Enum.join(", ")
        {:noreply, assign(socket, :email_error, error_msg)}

      {:error, _} ->
        {:noreply, assign(socket, :email_error, "Failed to send verification code. Please try again.")}
    end
  end

  @impl true
  def handle_event("submit_email_code", %{"code" => code}, socket) do
    user = socket.assigns.user

    case EmailVerification.verify_code(user, code) do
      {:ok, verified_user, info} ->
        # Refresh multipliers — verify_code already calls update_email_multiplier
        multipliers = UnifiedMultiplier.get_user_multipliers(verified_user.id)

        {:noreply,
         socket
         |> assign(:email_step_state, :success)
         |> assign(:email_error, nil)
         |> assign(:user, verified_user)
         |> assign(:multipliers, multipliers)
         |> assign(:merge_summary, info[:summary])}

      {:error, :invalid_code} ->
        {:noreply, assign(socket, :email_error, "Invalid verification code. Please try again.")}

      {:error, :code_expired} ->
        {:noreply, assign(socket, :email_error, "Code expired. Please request a new one.")}

      {:error, :no_code_sent} ->
        {:noreply, assign(socket, :email_error, "No code sent yet. Please request one first.")}

      {:error, :email_taken} ->
        {:noreply,
         socket
         |> assign(:email_step_state, :enter_email)
         |> assign(
           :email_error,
           "This email is already used by another active account. Please use a different email."
         )}

      {:error, _} ->
        {:noreply, assign(socket, :email_error, "Verification failed. Please try again.")}
    end
  end

  @impl true
  def handle_event("resend_email_code", _params, socket) do
    handle_event("submit_email", %{"email" => socket.assigns.email_address}, socket)
  end

  @impl true
  def handle_event("change_email", _params, socket) do
    {:noreply,
     socket
     |> assign(:email_step_state, :enter_email)
     |> assign(:email_error, nil)
     |> assign(:email_success, nil)}
  end

  # =============================================================================
  # Welcome Step → Redeem
  # =============================================================================
  # Legacy account reclaim used to live here (welcome → migrate_email →
  # OTP → merge). That path is retired: existing Blockster users reclaim
  # their account by signing in with their email via Web3Auth, which runs
  # the merge server-side before they ever hit onboarding. So welcome now
  # always routes to redeem regardless of the payload.

  @impl true
  def handle_event("set_migration_intent", _params, socket) do
    {:noreply,
     socket
     |> assign(:migration_intent, :new)
     |> push_patch(to: ~p"/onboarding/redeem")}
  end

  @impl true
  def handle_event("send_migration_code", %{"email" => email}, socket) do
    user = socket.assigns.user

    case EmailVerification.send_verification_code(user, email) do
      {:ok, updated_user} ->
        Process.send_after(self(), {:migrate_countdown_tick, 60}, 1000)
        pending = updated_user.pending_email || updated_user.email

        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:migrate_email_step_state, :enter_code)
         |> assign(:migrate_email_address, pending)
         |> assign(:migrate_email_countdown, 60)
         |> assign(:migrate_email_error, nil)
         |> assign(:migrate_email_success, "Code sent to #{pending}")}

      {:error, %Ecto.Changeset{errors: errors}} ->
        error_msg = errors |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end) |> Enum.join(", ")
        {:noreply, assign(socket, :migrate_email_error, error_msg)}

      {:error, _} ->
        {:noreply, assign(socket, :migrate_email_error, "Failed to send verification code. Please try again.")}
    end
  end

  @impl true
  def handle_event("verify_migration_code", %{"code" => code}, socket) do
    user = socket.assigns.user

    case EmailVerification.verify_code(user, code) do
      {:ok, verified_user, info} ->
        multipliers = UnifiedMultiplier.get_user_multipliers(verified_user.id)

        {:noreply,
         socket
         |> assign(:migrate_email_step_state, :success)
         |> assign(:migrate_email_error, nil)
         |> assign(:user, verified_user)
         |> assign(:multipliers, multipliers)
         |> assign(:merge_summary, info[:summary])}

      {:error, :invalid_code} ->
        {:noreply, assign(socket, :migrate_email_error, "Invalid verification code. Please try again.")}

      {:error, :code_expired} ->
        {:noreply, assign(socket, :migrate_email_error, "Code expired. Please request a new one.")}

      {:error, :no_code_sent} ->
        {:noreply, assign(socket, :migrate_email_error, "No code sent yet. Please request one first.")}

      {:error, :email_taken} ->
        {:noreply,
         socket
         |> assign(:migrate_email_step_state, :enter_email)
         |> assign(
           :migrate_email_error,
           "This email is already used by another active account. Please use a different email."
         )}

      {:error, _} ->
        {:noreply, assign(socket, :migrate_email_error, "Verification failed. Please try again.")}
    end
  end

  @impl true
  def handle_event("resend_migration_code", _params, socket) do
    handle_event("send_migration_code", %{"email" => socket.assigns.migrate_email_address}, socket)
  end

  @impl true
  def handle_event("change_migration_email", _params, socket) do
    {:noreply,
     socket
     |> assign(:migrate_email_step_state, :enter_email)
     |> assign(:migrate_email_error, nil)
     |> assign(:migrate_email_success, nil)}
  end

  @impl true
  def handle_event("continue_after_merge", _params, socket) do
    next = next_unfilled_step(socket.assigns.user, "migrate_email")
    {:noreply, push_patch(socket, to: ~p"/onboarding/#{next}")}
  end

  # =============================================================================
  # Async Info Handlers
  # =============================================================================

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
  def handle_info({:email_countdown_tick, remaining}, socket) do
    if remaining > 0 do
      Process.send_after(self(), {:email_countdown_tick, remaining - 1}, 1000)
      {:noreply, assign(socket, :email_countdown, remaining - 1)}
    else
      {:noreply, assign(socket, :email_countdown, nil)}
    end
  end

  @impl true
  def handle_info({:migrate_countdown_tick, remaining}, socket) do
    if remaining > 0 do
      Process.send_after(self(), {:migrate_countdown_tick, remaining - 1}, 1000)
      {:noreply, assign(socket, :migrate_email_countdown, remaining - 1)}
    else
      {:noreply, assign(socket, :migrate_email_countdown, nil)}
    end
  end

  # Swoosh test adapter delivers `{:email, email}` to the spawning process.
  # Since `Task.start` runs inside the LiveView, that message can land in our
  # handle_info — silently ignore.
  @impl true
  def handle_info({:email, _swoosh_email}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#fafaf9] flex flex-col">
      <%!-- Progress bar --%>
      <div class="pt-6 pb-4 px-6">
        <.progress_bar current={@step_index} total={@total_steps} />
      </div>

      <%!-- Main content area - centered --%>
      <div class="flex-1 flex flex-col items-center justify-center px-4 sm:px-6 pb-12">
        <div class="w-full max-w-md">
          <div class="bg-white rounded-2xl shadow-[0_1px_3px_rgba(0,0,0,0.04)] border border-neutral-100 p-6 sm:p-8">
            <%= case @current_step do %>
              <% "welcome" -> %>
                <.welcome_step />
              <% "migrate_email" -> %>
                <.migrate_email_step
                  user={@user}
                  migrate_email_step_state={@migrate_email_step_state}
                  migrate_email_address={@migrate_email_address}
                  migrate_email_error={@migrate_email_error}
                  migrate_email_success={@migrate_email_success}
                  migrate_email_countdown={@migrate_email_countdown}
                  merge_summary={@merge_summary}
                />
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
                  skip_to={next_step_in_flow("phone", @steps)}
                />
              <% "email" -> %>
                <.email_step
                  user={@user}
                  multipliers={@multipliers}
                  email_step_state={@email_step_state}
                  email_address={@email_address}
                  email_error={@email_error}
                  email_success={@email_success}
                  email_countdown={@email_countdown}
                  skip_to={next_step_in_flow("email", @steps)}
                />
              <% "x" -> %>
                <.x_step
                  user={@user}
                  multipliers={@multipliers}
                  skip_to={next_step_in_flow("x", @steps)}
                />
              <% "complete" -> %>
                <.complete_step user={@user} multipliers={@multipliers} />
              <% _ -> %>
                <.welcome_step />
            <% end %>
          </div>
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
    <div class="text-center space-y-6">
      <%!-- Logo --%>
      <div class="flex justify-center">
        <div class="w-14 h-14 rounded-2xl bg-[#CAFC00] flex items-center justify-center">
          <img
            src="https://ik.imagekit.io/blockster/blockster-icon.png"
            alt="Blockster"
            class="w-9 h-9"
          />
        </div>
      </div>

      <%!-- Headlines --%>
      <div class="space-y-3">
        <h1 class="text-[26px] font-bold tracking-[-0.022em] leading-tight text-[#141414]">
          Welcome to Blockster
        </h1>
        <p class="text-[15px] text-[#6B7280] leading-relaxed">
          A few quick steps and you'll be earning BUX for reading.
        </p>
      </div>

      <%!-- Single CTA — legacy account reclaim now happens automatically
           when a user signs in with their old email via Web3Auth, so the
           onboarding flow just starts here for everyone. --%>
      <div class="pt-4">
        <button
          type="button"
          phx-click="set_migration_intent"
          phx-value-intent="new"
          class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
        >
          Get started
        </button>
      </div>
    </div>
    """
  end

  defp migrate_email_step(assigns) do
    ~H"""
    <div class="text-center space-y-5">
      <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-[#9CA3AF]">Welcome back</div>

      <div class="flex justify-center">
        <div class="w-14 h-14 flex items-center justify-center bg-[#CAFC00] rounded-2xl">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-7 h-7 text-black">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75" />
          </svg>
        </div>
      </div>

      <div class="space-y-2">
        <h1 class="text-[26px] font-bold tracking-[-0.022em] leading-tight text-[#141414]">
          Restore your account
        </h1>
        <p class="text-[15px] text-[#6B7280] leading-relaxed">
          Enter the email address you used on your previous Blockster account.
          We'll move your BUX, username and connections to this Solana wallet.
        </p>
      </div>

      <%= cond do %>
        <% @migrate_email_step_state == :enter_email -> %>
          <form phx-submit="send_migration_code" class="text-left space-y-4 pt-2">
            <div>
              <label class="block text-[13px] font-medium text-[#343434] mb-2">
                Previous email
              </label>
              <input
                id="migrate-email-input"
                type="email"
                name="email"
                placeholder="you@example.com"
                value={@migrate_email_address}
                class="w-full px-4 py-3 bg-white border border-neutral-200 rounded-xl text-[15px] text-[#141414] placeholder-[#d4d4d2] focus:ring-2 focus:ring-[#0a0a0a] focus:border-transparent outline-none transition-all"
                required
                autofocus
              />
            </div>

            <%= if @migrate_email_error do %>
              <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl text-[13px]">
                <%= @migrate_email_error %>
              </div>
            <% end %>

            <div class="pt-1 space-y-3">
              <button
                type="submit"
                class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
              >
                Send Code
              </button>

              <.link
                patch={~p"/onboarding/redeem"}
                class="block w-full text-[#9CA3AF] text-[13px] py-2 text-center hover:text-[#6B7280] transition-colors cursor-pointer"
              >
                I don't have an account
              </.link>
            </div>
          </form>

        <% @migrate_email_step_state == :enter_code -> %>
          <div class="pt-2 space-y-4">
            <%= if @migrate_email_success do %>
              <div class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded-xl text-[13px]">
                <%= @migrate_email_success %>
              </div>
            <% end %>

            <form phx-submit="verify_migration_code" class="text-left space-y-4">
              <div>
                <label class="block text-[13px] font-medium text-[#343434] mb-2">
                  6-Digit Code
                </label>
                <input
                  id="migrate-email-code-input"
                  type="text"
                  name="code"
                  placeholder="123456"
                  inputmode="numeric"
                  maxlength="6"
                  class="w-full px-4 py-3 text-2xl text-center bg-white border border-neutral-200 rounded-xl text-[#141414] placeholder-[#d4d4d2] focus:ring-2 focus:ring-[#0a0a0a] focus:border-transparent tracking-widest font-mono outline-none transition-all"
                  autofocus
                />
              </div>

              <%= if @migrate_email_error do %>
                <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl text-[13px]">
                  <%= @migrate_email_error %>
                </div>
              <% end %>

              <button
                type="submit"
                class="w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl hover:bg-[#1a1a22] transition-colors cursor-pointer"
              >
                Verify Code
              </button>
            </form>

            <div class="flex justify-between text-[13px] pt-3 border-t border-neutral-100">
              <button
                phx-click="resend_migration_code"
                disabled={@migrate_email_countdown && @migrate_email_countdown > 0}
                class={"text-[#141414] hover:underline cursor-pointer #{if @migrate_email_countdown && @migrate_email_countdown > 0, do: "opacity-40 cursor-not-allowed"}"}
              >
                <%= if @migrate_email_countdown && @migrate_email_countdown > 0 do %>
                  Resend in <span class="font-mono"><%= @migrate_email_countdown %>s</span>
                <% else %>
                  Resend Code
                <% end %>
              </button>
              <button
                phx-click="change_migration_email"
                class="text-[#6B7280] hover:underline cursor-pointer"
              >
                Change Email
              </button>
            </div>
          </div>

        <% @migrate_email_step_state == :success -> %>
          <div class="pt-2 space-y-4">
            <div class="inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 border border-emerald-200 rounded-full">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-emerald-600">
                <path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" />
              </svg>
              <span class="font-medium text-emerald-800">Email Verified</span>
            </div>

            <%= if @merge_summary do %>
              <div class="bg-[#fafaf9] rounded-xl p-4 text-left space-y-2 text-[13px]">
                <div class="font-medium text-base text-[#141414]">Welcome back!</div>
                <%= if @merge_summary[:bux_claimed] && @merge_summary[:bux_claimed] > 0 do %>
                  <div class="flex items-center gap-2">
                    <span class="text-emerald-600">✓</span>
                    <span class="text-[#6B7280]">BUX restored:</span>
                    <span class="font-medium font-mono text-[#141414]"><%= :erlang.float_to_binary(@merge_summary[:bux_claimed] / 1, decimals: 2) %></span>
                  </div>
                <% end %>
                <%= if @merge_summary[:username_transferred] do %>
                  <div class="flex items-center gap-2">
                    <span class="text-emerald-600">✓</span>
                    <span class="text-[#343434]">Username restored</span>
                  </div>
                <% end %>
                <%= if @merge_summary[:phone_transferred] do %>
                  <div class="flex items-center gap-2">
                    <span class="text-emerald-600">✓</span>
                    <span class="text-[#343434]">Phone restored</span>
                  </div>
                <% end %>
                <%= if @merge_summary[:x_transferred] do %>
                  <div class="flex items-center gap-2">
                    <span class="text-emerald-600">✓</span>
                    <span class="text-[#343434]">X account restored</span>
                  </div>
                <% end %>
                <%= if @merge_summary[:telegram_transferred] do %>
                  <div class="flex items-center gap-2">
                    <span class="text-emerald-600">✓</span>
                    <span class="text-[#343434]">Telegram restored</span>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="bg-[#fafaf9] rounded-xl p-4 text-left text-[13px] text-[#6B7280]">
                Email verified — no legacy account found, but you're all set.
              </div>
            <% end %>

            <div class="pt-2">
              <button
                type="button"
                phx-click="continue_after_merge"
                class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
              >
                Continue
              </button>
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  defp redeem_step(assigns) do
    ~H"""
    <div class="text-center space-y-6">
      <%!-- Icons row --%>
      <div class="flex justify-center gap-5">
        <div class="flex flex-col items-center space-y-2 animate-fade-in" style="animation-delay: 0ms">
          <div class="w-14 h-14 flex items-center justify-center bg-[#CAFC00] rounded-2xl">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-7 h-7 text-black">
              <path fill-rule="evenodd" d="M7.5 6v.75H5.513c-.96 0-1.764.724-1.865 1.679l-1.263 12A1.875 1.875 0 0 0 4.25 22.5h15.5a1.875 1.875 0 0 0 1.865-2.071l-1.263-12a1.875 1.875 0 0 0-1.865-1.679H16.5V6a4.5 4.5 0 1 0-9 0ZM12 3a3 3 0 0 0-3 3v.75h6V6a3 3 0 0 0-3-3Zm-3 8.25a3 3 0 1 0 6 0v-.75a.75.75 0 0 1 1.5 0v.75a4.5 4.5 0 1 1-9 0v-.75a.75.75 0 0 1 1.5 0v.75Z" clip-rule="evenodd" />
            </svg>
          </div>
          <span class="text-[11px] font-medium text-[#6B7280]">Shop</span>
        </div>

        <div class="flex flex-col items-center space-y-2 animate-fade-in" style="animation-delay: 100ms">
          <div class="w-14 h-14 flex items-center justify-center bg-[#CAFC00] rounded-2xl">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-7 h-7 text-black">
              <path fill-rule="evenodd" d="M9.315 7.584C12.195 3.883 16.695 1.5 21.75 1.5a.75.75 0 0 1 .75.75c0 5.056-2.383 9.555-6.084 12.436A6.75 6.75 0 0 1 9.75 22.5a.75.75 0 0 1-.75-.75v-4.131A15.838 15.838 0 0 1 6.382 15H2.25a.75.75 0 0 1-.75-.75 6.75 6.75 0 0 1 7.815-6.666ZM15 6.75a2.25 2.25 0 1 0 0 4.5 2.25 2.25 0 0 0 0-4.5Z" clip-rule="evenodd" />
              <path d="M5.26 17.242a.75.75 0 1 0-.897-1.203 5.243 5.243 0 0 0-2.05 5.022.75.75 0 0 0 .625.627 5.243 5.243 0 0 0 5.022-2.051.75.75 0 1 0-1.202-.897 3.744 3.744 0 0 1-3.008 1.51c0-1.23.592-2.323 1.51-3.008Z" />
            </svg>
          </div>
          <span class="text-[11px] font-medium text-[#6B7280]">Games</span>
        </div>

        <div class="flex flex-col items-center space-y-2 animate-fade-in" style="animation-delay: 200ms">
          <div class="w-14 h-14 flex items-center justify-center bg-[#CAFC00] rounded-2xl">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-7 h-7 text-black">
              <path fill-rule="evenodd" d="M9 4.5a.75.75 0 0 1 .721.544l.813 2.846a3.75 3.75 0 0 0 2.576 2.576l2.846.813a.75.75 0 0 1 0 1.442l-2.846.813a3.75 3.75 0 0 0-2.576 2.576l-.813 2.846a.75.75 0 0 1-1.442 0l-.813-2.846a3.75 3.75 0 0 0-2.576-2.576l-2.846-.813a.75.75 0 0 1 0-1.442l2.846-.813A3.75 3.75 0 0 0 7.466 7.89l.813-2.846A.75.75 0 0 1 9 4.5ZM18 1.5a.75.75 0 0 1 .728.568l.258 1.036c.236.94.97 1.674 1.91 1.91l1.036.258a.75.75 0 0 1 0 1.456l-1.036.258c-.94.236-1.674.97-1.91 1.91l-.258 1.036a.75.75 0 0 1-1.456 0l-.258-1.036a2.625 2.625 0 0 0-1.91-1.91l-1.036-.258a.75.75 0 0 1 0-1.456l1.036-.258a2.625 2.625 0 0 0 1.91-1.91l.258-1.036A.75.75 0 0 1 18 1.5ZM16.5 15a.75.75 0 0 1 .712.513l.394 1.183c.15.447.5.799.948.948l1.183.395a.75.75 0 0 1 0 1.422l-1.183.395c-.447.15-.799.5-.948.948l-.395 1.183a.75.75 0 0 1-1.422 0l-.395-1.183a1.5 1.5 0 0 0-.948-.948l-1.183-.395a.75.75 0 0 1 0-1.422l1.183-.395c.447-.15.799-.5.948-.948l.395-1.183A.75.75 0 0 1 16.5 15Z" clip-rule="evenodd" />
            </svg>
          </div>
          <span class="text-[11px] font-medium text-[#6B7280]">Airdrop</span>
        </div>
      </div>

      <%!-- Headlines --%>
      <div class="space-y-2">
        <h1 class="text-[26px] font-bold tracking-[-0.022em] leading-tight text-[#141414]">
          Redeem BUX
        </h1>
        <p class="text-[15px] text-[#6B7280] leading-relaxed">
          For cool merch, games and airdrops
        </p>
      </div>

      <%!-- CTA --%>
      <div class="pt-4">
        <.link
          patch={~p"/onboarding/profile"}
          class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
        >
          Next
        </.link>
      </div>
    </div>
    """
  end

  defp profile_step(assigns) do
    max_multiplier = UnifiedMultiplier.max_overall()
    current = assigns.multipliers.overall_multiplier
    assigns = assign(assigns, max_multiplier: max_multiplier, current_multiplier: current)

    ~H"""
    <div class="text-center space-y-6">
      <div class="space-y-3">
        <h1 class="text-[26px] font-bold tracking-[-0.022em] leading-tight text-[#141414]">
          Earn up to <span class="bg-[#CAFC00] px-2 py-0.5 rounded-lg">20x</span> more BUX
        </h1>
        <p class="text-[15px] text-[#6B7280] leading-relaxed">
          Complete your profile to boost your earning power
        </p>
      </div>

      <div class="pt-4 space-y-3">
        <.link
          patch={~p"/onboarding/phone"}
          class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
        >
          Let's Go
        </.link>

        <.link
          navigate={~p"/"}
          class="block w-full text-[#9CA3AF] text-[13px] py-2 text-center hover:text-[#6B7280] transition-colors cursor-pointer"
        >
          I'll do this later
        </.link>
      </div>
    </div>
    """
  end

  defp phone_step(assigns) do
    phone_verified = assigns.user.phone_verified || false
    assigns = assign(assigns, phone_verified: phone_verified)

    ~H"""
    <div class="text-center space-y-5">
      <%!-- Step indicator --%>
      <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-[#9CA3AF]">
        Step 1 of 3
      </div>

      <%!-- Icon --%>
      <div class="flex justify-center">
        <div class="w-14 h-14 flex items-center justify-center bg-[#CAFC00] rounded-2xl">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-7 h-7 text-black">
            <path d="M10.5 18.75a.75.75 0 0 0 0 1.5h3a.75.75 0 0 0 0-1.5h-3Z" />
            <path fill-rule="evenodd" d="M8.25 1.5A2.25 2.25 0 0 0 6 3.75v16.5a2.25 2.25 0 0 0 2.25 2.25h7.5A2.25 2.25 0 0 0 18 20.25V3.75A2.25 2.25 0 0 0 15.75 1.5h-7.5Zm7.5 1.5h-7.5a.75.75 0 0 0-.75.75v16.5c0 .414.336.75.75.75h7.5a.75.75 0 0 0 .75-.75V3.75a.75.75 0 0 0-.75-.75Z" clip-rule="evenodd" />
          </svg>
        </div>
      </div>

      <%!-- Headlines --%>
      <div class="space-y-2">
        <h1 class="text-[26px] font-bold tracking-[-0.022em] leading-tight text-[#141414]">
          Connect Your Phone
        </h1>
        <p class="text-[15px] text-[#6B7280] leading-relaxed">
          Verify to boost your BUX earnings
        </p>
      </div>

      <%= cond do %>
        <% @phone_verified -> %>
          <%!-- Already verified state --%>
          <div class="pt-2 space-y-4">
            <div class="inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 border border-emerald-200 rounded-full">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-emerald-600">
                <path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" />
              </svg>
              <span class="font-medium text-emerald-800">Phone Verified</span>
            </div>

            <div class="bg-[#fafaf9] rounded-xl p-4 text-left">
              <div class="flex items-center justify-between">
                <span class="text-[13px] text-[#6B7280]">Phone Multiplier</span>
                <span class="font-medium text-lg font-mono text-[#141414]">
                  <%= :erlang.float_to_binary(@multipliers.phone_multiplier / 1, decimals: 1) %>x
                </span>
              </div>
            </div>
          </div>

          <div class="pt-2">
            <.link
              patch={~p"/onboarding/email"}
              class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
            >
              Continue
            </.link>
          </div>

        <% @phone_step_state == :enter_phone -> %>
          <%!-- Phone Number Entry --%>
          <form phx-submit="submit_phone" class="text-left space-y-4 pt-2">
            <div>
              <label class="block text-[13px] font-medium text-[#343434] mb-2">
                Phone Number
              </label>
              <input
                id="phone-number-input"
                type="tel"
                name="phone_number"
                placeholder="+1 234-567-8900"
                value={@phone_number}
                class="w-full px-4 py-3 bg-white border border-neutral-200 rounded-xl text-[15px] text-[#141414] placeholder-[#d4d4d2] focus:ring-2 focus:ring-[#0a0a0a] focus:border-transparent outline-none transition-all"
                required
                autofocus
                phx-hook="PhoneNumberFormatter"
              />
              <p class="text-[11px] text-[#6B7280] mt-1.5">
                <span class="font-medium text-[#343434]">Include your country code:</span> 1 (US/CA), 44 (UK), 91 (India)
              </p>
            </div>

            <%!-- SMS Opt-in --%>
            <div>
              <label class="flex items-start cursor-pointer">
                <input
                  type="checkbox"
                  name="sms_opt_in"
                  value="true"
                  checked
                  class="mt-0.5 w-4 h-4 text-[#0a0a0a] border-neutral-300 rounded focus:ring-[#0a0a0a] cursor-pointer"
                />
                <span class="ml-3 text-[13px] text-[#6B7280]">
                  Send me special offers and promos via SMS
                </span>
              </label>
            </div>

            <%= if @phone_error do %>
              <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl text-[13px]">
                <%= @phone_error %>
              </div>
            <% end %>

            <div class="pt-1 space-y-3">
              <button
                type="submit"
                class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
              >
                Send Code
              </button>

              <.link
                patch={~p"/onboarding/#{@skip_to}"}
                class="block w-full text-[#9CA3AF] text-[13px] py-2 text-center hover:text-[#6B7280] transition-colors cursor-pointer"
              >
                Skip for now
              </.link>
            </div>
          </form>

        <% @phone_step_state == :enter_code -> %>
          <%!-- Code Entry --%>
          <div class="pt-2 space-y-4">
            <%= if @phone_success do %>
              <div class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded-xl text-[13px]">
                <%= @phone_success %>
              </div>
            <% end %>

            <form phx-submit="submit_code" class="text-left space-y-4">
              <div>
                <label class="block text-[13px] font-medium text-[#343434] mb-2">
                  6-Digit Code
                </label>
                <input
                  id="verification-code-input"
                  type="text"
                  name="code"
                  placeholder="123456"
                  inputmode="numeric"
                  maxlength="6"
                  class="w-full px-4 py-3 text-2xl text-center bg-white border border-neutral-200 rounded-xl text-[#141414] placeholder-[#d4d4d2] focus:ring-2 focus:ring-[#0a0a0a] focus:border-transparent tracking-widest font-mono outline-none transition-all"
                  autofocus
                />
              </div>

              <%= if @phone_error do %>
                <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl text-[13px]">
                  <%= @phone_error %>
                </div>
              <% end %>

              <button
                type="submit"
                class="w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl hover:bg-[#1a1a22] transition-colors cursor-pointer"
              >
                Verify Code
              </button>
            </form>

            <div class="flex justify-between text-[13px] pt-3 border-t border-neutral-100">
              <button
                phx-click="resend_code"
                disabled={@phone_countdown && @phone_countdown > 0}
                class={"text-[#141414] hover:underline cursor-pointer #{if @phone_countdown && @phone_countdown > 0, do: "opacity-40 cursor-not-allowed"}"}
              >
                <%= if @phone_countdown && @phone_countdown > 0 do %>
                  Resend in <span class="font-mono"><%= @phone_countdown %>s</span>
                <% else %>
                  Resend Code
                <% end %>
              </button>
              <button
                phx-click="change_phone"
                class="text-[#6B7280] hover:underline cursor-pointer"
              >
                Change Number
              </button>
            </div>

            <div class="text-[11px] text-[#9CA3AF] text-center">
              Code expires in 10 minutes
            </div>
          </div>

        <% @phone_step_state == :success -> %>
          <%!-- Success --%>
          <div class="pt-2 space-y-4">
            <div class="inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 border border-emerald-200 rounded-full">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-emerald-600">
                <path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" />
              </svg>
              <span class="font-medium text-emerald-800">Phone Verified</span>
            </div>

            <%= if @verification_result do %>
              <div class="text-[13px] text-[#6B7280] font-mono">
                <%= format_phone_display(@phone_number) %>
              </div>
            <% end %>

            <div class="bg-[#fafaf9] rounded-xl p-4 text-left">
              <div class="flex items-center justify-between">
                <span class="text-[13px] text-[#6B7280]">Phone Multiplier</span>
                <span class="font-medium text-lg font-mono text-[#141414]">
                  <%= if @verification_result, do: "#{@verification_result.geo_multiplier}x", else: "#{:erlang.float_to_binary(@multipliers.phone_multiplier / 1, decimals: 1)}x" %>
                </span>
              </div>
            </div>
          </div>

          <div class="pt-2">
            <.link
              patch={~p"/onboarding/email"}
              class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
            >
              Continue
            </.link>
          </div>
      <% end %>
    </div>
    """
  end

  defp email_step(assigns) do
    email_verified = assigns.user.email_verified || false
    assigns = assign(assigns, email_verified: email_verified)

    ~H"""
    <div class="text-center space-y-5">
      <%!-- Step indicator --%>
      <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-[#9CA3AF]">
        Step 2 of 3
      </div>

      <%!-- Icon --%>
      <div class="flex justify-center">
        <div class="w-14 h-14 flex items-center justify-center bg-[#CAFC00] rounded-2xl">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-7 h-7 text-black">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75" />
          </svg>
        </div>
      </div>

      <%!-- Headlines --%>
      <div class="space-y-2">
        <h1 class="text-[26px] font-bold tracking-[-0.022em] leading-tight text-[#141414]">
          Verify Your Email
        </h1>
        <p class="text-[15px] text-[#6B7280] leading-relaxed">
          Boost your earnings from <span class="font-medium text-[#141414]">0.5x</span> to <span class="font-medium text-[#141414]">2x</span>
        </p>
      </div>

      <%= cond do %>
        <% @email_verified -> %>
          <%!-- Already verified state --%>
          <div class="pt-2 space-y-4">
            <div class="inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 border border-emerald-200 rounded-full">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-emerald-600">
                <path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" />
              </svg>
              <span class="font-medium text-emerald-800">Email Verified</span>
            </div>

            <%= if @user.email do %>
              <div class="text-[13px] text-[#6B7280]"><%= @user.email %></div>
            <% end %>

            <div class="bg-[#fafaf9] rounded-xl p-4 text-left">
              <div class="flex items-center justify-between">
                <span class="text-[13px] text-[#6B7280]">Email Multiplier</span>
                <span class="font-medium text-lg font-mono text-[#141414]">
                  <%= :erlang.float_to_binary(@multipliers.email_multiplier / 1, decimals: 1) %>x
                </span>
              </div>
            </div>
          </div>

          <div class="pt-2">
            <.link
              patch={~p"/onboarding/x"}
              class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
            >
              Continue
            </.link>
          </div>

        <% @email_step_state == :enter_email -> %>
          <%!-- Email Entry --%>
          <form phx-submit="submit_email" class="text-left space-y-4 pt-2">
            <div>
              <label class="block text-[13px] font-medium text-[#343434] mb-2">
                Email Address
              </label>
              <input
                id="email-input"
                type="email"
                name="email"
                placeholder="you@example.com"
                value={@email_address}
                class="w-full px-4 py-3 bg-white border border-neutral-200 rounded-xl text-[15px] text-[#141414] placeholder-[#d4d4d2] focus:ring-2 focus:ring-[#0a0a0a] focus:border-transparent outline-none transition-all"
                required
                autofocus
              />
              <p class="text-[11px] text-[#9CA3AF] mt-1.5">
                We'll send a 6-digit code to verify it's yours
              </p>
            </div>

            <%= if @email_error do %>
              <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl text-[13px]">
                <%= @email_error %>
              </div>
            <% end %>

            <div class="pt-1 space-y-3">
              <button
                type="submit"
                class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
              >
                Send Code
              </button>

              <.link
                patch={~p"/onboarding/#{@skip_to}"}
                class="block w-full text-[#9CA3AF] text-[13px] py-2 text-center hover:text-[#6B7280] transition-colors cursor-pointer"
              >
                Skip for now
              </.link>
            </div>
          </form>

        <% @email_step_state == :enter_code -> %>
          <%!-- Code Entry --%>
          <div class="pt-2 space-y-4">
            <%= if @email_success do %>
              <div class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded-xl text-[13px]">
                <%= @email_success %>
              </div>
            <% end %>

            <form phx-submit="submit_email_code" class="text-left space-y-4">
              <div>
                <label class="block text-[13px] font-medium text-[#343434] mb-2">
                  6-Digit Code
                </label>
                <input
                  id="email-verification-code-input"
                  type="text"
                  name="code"
                  placeholder="123456"
                  inputmode="numeric"
                  maxlength="6"
                  class="w-full px-4 py-3 text-2xl text-center bg-white border border-neutral-200 rounded-xl text-[#141414] placeholder-[#d4d4d2] focus:ring-2 focus:ring-[#0a0a0a] focus:border-transparent tracking-widest font-mono outline-none transition-all"
                  autofocus
                />
              </div>

              <%= if @email_error do %>
                <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl text-[13px]">
                  <%= @email_error %>
                </div>
              <% end %>

              <button
                type="submit"
                class="w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl hover:bg-[#1a1a22] transition-colors cursor-pointer"
              >
                Verify Code
              </button>
            </form>

            <div class="flex justify-between text-[13px] pt-3 border-t border-neutral-100">
              <button
                phx-click="resend_email_code"
                disabled={@email_countdown && @email_countdown > 0}
                class={"text-[#141414] hover:underline cursor-pointer #{if @email_countdown && @email_countdown > 0, do: "opacity-40 cursor-not-allowed"}"}
              >
                <%= if @email_countdown && @email_countdown > 0 do %>
                  Resend in <span class="font-mono"><%= @email_countdown %>s</span>
                <% else %>
                  Resend Code
                <% end %>
              </button>
              <button
                phx-click="change_email"
                class="text-[#6B7280] hover:underline cursor-pointer"
              >
                Change Email
              </button>
            </div>

            <div class="text-[11px] text-[#9CA3AF] text-center">
              Code expires in 10 minutes
            </div>
          </div>

        <% @email_step_state == :success -> %>
          <%!-- Success --%>
          <div class="pt-2 space-y-4">
            <div class="inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 border border-emerald-200 rounded-full">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-emerald-600">
                <path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" />
              </svg>
              <span class="font-medium text-emerald-800">Email Verified</span>
            </div>

            <%= if @user.email do %>
              <div class="text-[13px] text-[#6B7280]"><%= @user.email %></div>
            <% end %>

            <div class="bg-[#fafaf9] rounded-xl p-4 text-left">
              <div class="flex items-center justify-between">
                <span class="text-[13px] text-[#6B7280]">Email Multiplier</span>
                <span class="font-medium text-lg font-mono text-[#141414]">
                  <%= :erlang.float_to_binary(@multipliers.email_multiplier / 1, decimals: 1) %>x
                </span>
              </div>
            </div>
          </div>

          <div class="pt-2">
            <.link
              patch={~p"/onboarding/x"}
              class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
            >
              Continue
            </.link>
          </div>
      <% end %>
    </div>
    """
  end

  defp x_step(assigns) do
    x_connected = assigns.multipliers.x_score > 0
    assigns = assign(assigns, x_connected: x_connected)

    ~H"""
    <div class="text-center space-y-5">
      <%!-- Step indicator --%>
      <div class="text-[10px] font-bold tracking-[0.16em] uppercase text-[#9CA3AF]">
        Step 3 of 3
      </div>

      <%!-- X Logo in lime box --%>
      <div class="flex justify-center">
        <div class="w-14 h-14 bg-[#CAFC00] rounded-2xl flex items-center justify-center">
          <span class="text-3xl font-bold text-black">𝕏</span>
        </div>
      </div>

      <%!-- Headlines --%>
      <div class="space-y-2">
        <h1 class="text-[26px] font-bold tracking-[-0.022em] leading-tight text-[#141414]">
          Connect Your X Account
        </h1>
        <p class="text-[15px] text-[#6B7280] leading-relaxed">
          Share stories to earn BUX
        </p>
      </div>

      <%= if @x_connected do %>
        <%!-- Already connected state --%>
        <div class="pt-2">
          <div class="inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 border border-emerald-200 rounded-full">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-emerald-600">
              <path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" />
            </svg>
            <span class="font-medium text-emerald-800">
              X Connected (<%= format_multiplier(@multipliers.x_multiplier) %>)
            </span>
          </div>
        </div>

        <div class="pt-4">
          <.link
            patch={~p"/onboarding/complete"}
            class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
          >
            Continue
          </.link>
        </div>
      <% else %>
        <%!-- Connect X UI --%>
        <div class="pt-4 space-y-3">
          <.link
            href={~p"/auth/x"}
            class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
          >
            Connect X
          </.link>

          <.link
            patch={~p"/onboarding/#{@skip_to}"}
            class="block w-full text-[#9CA3AF] text-[13px] py-2 text-center hover:text-[#6B7280] transition-colors cursor-pointer"
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
        email_verified: multipliers.email_multiplier > 0.5,
        sol_connected: multipliers.sol_multiplier > 0,
        x_connected: multipliers.x_score > 0
      )

    ~H"""
    <div class="text-center space-y-5">
      <%!-- Checkmark --%>
      <div class="flex justify-center">
        <div class="w-14 h-14 flex items-center justify-center rounded-full bg-emerald-50 border border-emerald-200">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-7 h-7 text-emerald-600">
            <path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" />
          </svg>
        </div>
      </div>

      <%!-- Headline --%>
      <h1 class="text-[26px] font-bold tracking-[-0.022em] text-[#141414]">
        You're All Set!
      </h1>

      <%!-- Earning Power Display --%>
      <div class="space-y-2">
        <div class="inline-block bg-[#CAFC00] rounded-xl px-8 py-4">
          <span class="text-4xl font-bold font-mono text-black">
            <%= format_multiplier(@multipliers.overall_multiplier) %>
          </span>
        </div>
        <div class="text-[13px] text-[#6B7280]">
          BUX Earning Power
        </div>
      </div>

      <%!-- Breakdown --%>
      <div class="text-left max-w-[280px] mx-auto space-y-2.5">
        <div class="flex items-center gap-2.5 text-[14px]">
          <%= if @phone_connected do %>
            <span class="w-5 h-5 rounded-full bg-emerald-100 flex items-center justify-center flex-shrink-0">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3 h-3 text-emerald-600">
                <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clip-rule="evenodd" />
              </svg>
            </span>
          <% else %>
            <span class="w-5 h-5 rounded-full border-2 border-neutral-200 flex-shrink-0"></span>
          <% end %>
          <span class="text-[#343434]">Phone</span>
          <span class="ml-auto font-medium font-mono text-[#141414]">
            <%= format_multiplier(@multipliers.phone_multiplier) %>
          </span>
        </div>

        <div class="flex items-center gap-2.5 text-[14px]">
          <%= if @email_verified do %>
            <span class="w-5 h-5 rounded-full bg-emerald-100 flex items-center justify-center flex-shrink-0">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3 h-3 text-emerald-600">
                <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clip-rule="evenodd" />
              </svg>
            </span>
          <% else %>
            <span class="w-5 h-5 rounded-full border-2 border-neutral-200 flex-shrink-0"></span>
          <% end %>
          <span class="text-[#343434]">Email</span>
          <span class="ml-auto font-medium font-mono text-[#141414]">
            <%= format_multiplier(@multipliers.email_multiplier) %>
          </span>
        </div>

        <div class="flex items-center gap-2.5 text-[14px]">
          <%= if @sol_connected do %>
            <span class="w-5 h-5 rounded-full bg-emerald-100 flex items-center justify-center flex-shrink-0">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3 h-3 text-emerald-600">
                <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clip-rule="evenodd" />
              </svg>
            </span>
          <% else %>
            <span class="w-5 h-5 rounded-full border-2 border-neutral-200 flex-shrink-0"></span>
          <% end %>
          <span class="text-[#343434]">SOL</span>
          <span class="ml-auto font-medium font-mono text-[#141414]">
            <%= format_multiplier(@multipliers.sol_multiplier) %>
          </span>
        </div>

        <div class="flex items-center gap-2.5 text-[14px]">
          <%= if @x_connected do %>
            <span class="w-5 h-5 rounded-full bg-emerald-100 flex items-center justify-center flex-shrink-0">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3 h-3 text-emerald-600">
                <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clip-rule="evenodd" />
              </svg>
            </span>
          <% else %>
            <span class="w-5 h-5 rounded-full border-2 border-neutral-200 flex-shrink-0"></span>
          <% end %>
          <span class="text-[#343434]">X</span>
          <span class="ml-auto font-medium font-mono text-[#141414]">
            <%= format_multiplier(@multipliers.x_multiplier) %>
          </span>
        </div>
      </div>

      <%!-- CTA --%>
      <div class="pt-4">
        <.link
          navigate={~p"/"}
          class="block w-full bg-[#0a0a0a] text-white font-medium py-3.5 rounded-xl text-center hover:bg-[#1a1a22] transition-colors cursor-pointer"
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

  defp progress_bar(assigns) do
    ~H"""
    <div class="flex justify-center gap-1.5 max-w-xs mx-auto">
      <%= for i <- 0..(@total - 1) do %>
        <div class={[
          "h-1 flex-1 rounded-full transition-all duration-300",
          if(i <= @current, do: "bg-[#0a0a0a]", else: "bg-neutral-200")
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
  defp step_title("migrate_email"), do: "Restore your account"
  defp step_title("redeem"), do: "Redeem BUX"
  defp step_title("profile"), do: "Complete Profile"
  defp step_title("phone"), do: "Connect Phone"
  defp step_title("email"), do: "Verify Email"
  defp step_title("x"), do: "Connect X"
  defp step_title("complete"), do: "All Set!"
  defp step_title(_), do: "Onboarding"

  @doc false
  # Walks the user's filtered step list from the step AFTER `current_step`
  # and returns the first one that hasn't been filled by the user's current
  # state. Used after a merge (or whenever we want to fast-forward past
  # steps the user has already completed via the legacy reclaim flow).
  def next_unfilled_step(user, current_step) do
    steps = build_steps_for_user(user)
    current_idx = Enum.find_index(steps, &(&1 == current_step)) || 0

    steps
    |> Enum.drop(current_idx + 1)
    |> Enum.find("complete", fn step -> step_unfilled?(step, user) end)
  end

  @doc """
  Return the next step in the user's filtered step list after `current_step`.
  Falls back to `"complete"` if `current_step` is unknown or at the end.
  Used by "Skip for now" links so they route through steps that actually
  exist for this user's auth_method (Web3Auth users have some steps
  filtered out).
  """
  def next_step_in_flow(current_step, steps) when is_list(steps) do
    case Enum.find_index(steps, &(&1 == current_step)) do
      nil -> "complete"
      idx -> Enum.at(steps, idx + 1, "complete")
    end
  end

  @doc """
  Filter the base step list based on the user's `auth_method`.

  Web3Auth social users signed in with an identity already — we don't
  re-verify it here. Email Web3Auth users skip the email step; X Web3Auth
  users skip the X step. All Web3Auth users skip `migrate_email` (they are
  new users with no legacy account to reclaim).

  Wallet users (Phantom et al) see the full legacy flow unchanged.
  """
  def build_steps_for_user(nil), do: @base_steps

  def build_steps_for_user(user) do
    auth = Map.get(user, :auth_method, "wallet")

    skip =
      case auth do
        "web3auth_email" -> ["email"]
        "web3auth_x" -> ["x"]
        _ -> []
      end

    Enum.reject(@base_steps, &(&1 in skip))
  end

  defp step_unfilled?("welcome", _user), do: false
  defp step_unfilled?("migrate_email", _user), do: false
  defp step_unfilled?("redeem", _user), do: true
  defp step_unfilled?("profile", user), do: is_nil(user.username) or user.username == ""
  defp step_unfilled?("phone", user), do: !user.phone_verified
  defp step_unfilled?("email", user), do: !user.email_verified
  defp step_unfilled?("x", user) do
    case BlocksterV2.EngagementTracker.get_x_connection_by_user(user.id) do
      nil -> true
      _ -> false
    end
  rescue
    _ -> true
  catch
    :exit, _ -> true
  end
  defp step_unfilled?("complete", _user), do: true
  defp step_unfilled?(_, _), do: true

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
