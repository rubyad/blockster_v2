defmodule BlocksterV2Web.OnboardingModal do
  @moduledoc """
  Multi-step onboarding modal for new Solana wallet users.
  Appears after wallet_authenticated when is_new_user is true.

  Steps: welcome → email verification → legacy BUX claim (conditional) → done
  """
  use Phoenix.Component

  attr :show_onboarding, :boolean, default: false
  attr :onboarding_step, :atom, default: :welcome
  attr :verification_code_sent, :boolean, default: false
  attr :email_error, :string, default: nil
  attr :email_success, :string, default: nil
  attr :legacy_bux_amount, :any, default: nil
  attr :claiming, :boolean, default: false
  attr :claim_success, :boolean, default: false
  attr :resend_cooldown, :integer, default: 0

  def onboarding_modal(assigns) do
    step_number = case assigns.onboarding_step do
      :welcome -> 1
      :email -> 2
      :claim -> 3
      :complete -> 3
      _ -> 1
    end

    total = if assigns.legacy_bux_amount && assigns.legacy_bux_amount > 0, do: 3, else: 2
    assigns = assign(assigns, step_number: step_number, total_steps: total)

    ~H"""
    <%= if @show_onboarding do %>
      <div
        class="fixed inset-0 z-[60] flex items-center justify-center p-4
               bg-black/70 backdrop-blur-md"
        style="animation: obFadeIn 200ms ease-out;"
      >
        <div
          class="relative w-full max-w-md
                 bg-[#0f0f0f] border border-white/[0.06] rounded-2xl
                 shadow-2xl shadow-black/60 overflow-hidden"
          style="animation: obSlideUp 300ms cubic-bezier(0.16, 1, 0.3, 1);"
        >
          <%!-- Progress bar --%>
          <div class="h-[2px] bg-white/[0.04]">
            <div
              class="h-full bg-[#CAFC00]/60 transition-all duration-500 ease-out"
              style={"width: #{@step_number / @total_steps * 100}%"}
            />
          </div>

          <%!-- Step content --%>
          <%= case @onboarding_step do %>
            <% :welcome -> %>
              <.welcome_step />
            <% :email -> %>
              <.email_step
                verification_code_sent={@verification_code_sent}
                email_error={@email_error}
                email_success={@email_success}
                resend_cooldown={@resend_cooldown}
              />
            <% :claim -> %>
              <.claim_step
                legacy_bux_amount={@legacy_bux_amount}
                claiming={@claiming}
                claim_success={@claim_success}
              />
            <% :complete -> %>
              <.complete_step />
            <% _ -> %>
              <.welcome_step />
          <% end %>
        </div>
      </div>

      <style>
        @keyframes obFadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @keyframes obSlideUp {
          from { opacity: 0; transform: translateY(20px) scale(0.96); }
          to { opacity: 1; transform: translateY(0) scale(1); }
        }
        @keyframes obPulse {
          0%, 100% { opacity: 0.4; }
          50% { opacity: 1; }
        }
        @keyframes obShine {
          0% { background-position: -200% center; }
          100% { background-position: 200% center; }
        }
      </style>
    <% end %>
    """
  end

  # ── Step 1: Welcome ──────────────────────────────────────────

  defp welcome_step(assigns) do
    ~H"""
    <div class="px-8 pt-10 pb-8 text-center">
      <%!-- Logo --%>
      <div class="mx-auto mb-6 w-14 h-14 rounded-2xl bg-white/[0.04] border border-white/[0.06]
                  flex items-center justify-center">
        <img
          src="https://ik.imagekit.io/blockster/blockster-icon.png"
          alt="Blockster"
          class="w-9 h-9"
        />
      </div>

      <h2 class="text-[22px] font-haas_medium_65 text-white tracking-tight mb-2">
        Welcome to Blockster
      </h2>

      <p class="text-sm font-haas_roman_55 text-white/40 leading-relaxed mb-8 max-w-xs mx-auto">
        Read articles. Earn BUX. It's that simple.
      </p>

      <%!-- Feature cards --%>
      <div class="space-y-3 mb-8 text-left">
        <div class="flex items-start gap-3.5 p-3.5 rounded-xl bg-white/[0.03] border border-white/[0.04]">
          <div class="w-8 h-8 rounded-lg bg-[#CAFC00]/10 flex items-center justify-center flex-shrink-0 mt-0.5">
            <svg class="w-4 h-4 text-[#CAFC00]" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
          </div>
          <div>
            <div class="text-sm font-haas_medium_65 text-white/90">Earn by reading</div>
            <div class="text-xs font-haas_roman_55 text-white/35 mt-0.5">Every article you read mints BUX to your wallet</div>
          </div>
        </div>

        <div class="flex items-start gap-3.5 p-3.5 rounded-xl bg-white/[0.03] border border-white/[0.04]">
          <div class="w-8 h-8 rounded-lg bg-[#CAFC00]/10 flex items-center justify-center flex-shrink-0 mt-0.5">
            <svg class="w-4 h-4 text-[#CAFC00]" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 01-2.25 2.25h-15a2.25 2.25 0 01-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25m19.5 0v.243a2.25 2.25 0 01-1.07 1.916l-7.5 4.615a2.25 2.25 0 01-2.36 0L3.32 8.91a2.25 2.25 0 01-1.07-1.916V6.75" />
            </svg>
          </div>
          <div>
            <div class="text-sm font-haas_medium_65 text-white/90">
              Verify email for
              <span class="text-[#CAFC00]">2x</span>
              rewards
            </div>
            <div class="text-xs font-haas_roman_55 text-white/35 mt-0.5">Double your BUX earnings with a verified email</div>
          </div>
        </div>
      </div>

      <%!-- Actions --%>
      <button
        phx-click="onboarding_continue"
        class="w-full py-3 rounded-xl text-sm font-haas_medium_65
               bg-white text-[#0f0f0f]
               hover:bg-gray-100 active:scale-[0.98]
               transition-all duration-150 cursor-pointer"
      >
        Continue
      </button>

      <button
        phx-click="onboarding_skip"
        class="mt-3 w-full py-2 text-xs font-haas_roman_55 text-white/25
               hover:text-white/40 transition-colors cursor-pointer"
      >
        Skip for now
      </button>
    </div>
    """
  end

  # ── Step 2: Email Verification ───────────────────────────────

  attr :verification_code_sent, :boolean, default: false
  attr :email_error, :string, default: nil
  attr :email_success, :string, default: nil
  attr :resend_cooldown, :integer, default: 0

  defp email_step(assigns) do
    ~H"""
    <div class="px-8 pt-10 pb-8">
      <%!-- Header --%>
      <div class="text-center mb-8">
        <div class="mx-auto mb-5 w-12 h-12 rounded-xl bg-white/[0.04] border border-white/[0.06]
                    flex items-center justify-center">
          <svg class="w-6 h-6 text-white/60" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 01-2.25 2.25h-15a2.25 2.25 0 01-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25m19.5 0v.243a2.25 2.25 0 01-1.07 1.916l-7.5 4.615a2.25 2.25 0 01-2.36 0L3.32 8.91a2.25 2.25 0 01-1.07-1.916V6.75" />
          </svg>
        </div>

        <h2 class="text-lg font-haas_medium_65 text-white tracking-tight mb-1.5">
          Verify your email
        </h2>
        <p class="text-sm font-haas_roman_55 text-white/35">
          Earn <span class="text-[#CAFC00] font-haas_medium_65">2x BUX</span> on every article
        </p>
      </div>

      <%!-- Error / Success messages --%>
      <%= if @email_error do %>
        <div class="mb-4 px-4 py-2.5 rounded-lg bg-red-500/10 border border-red-500/20">
          <p class="text-xs font-haas_roman_55 text-red-400"><%= @email_error %></p>
        </div>
      <% end %>

      <%= if @email_success do %>
        <div class="mb-4 px-4 py-2.5 rounded-lg bg-emerald-500/10 border border-emerald-500/20">
          <p class="text-xs font-haas_roman_55 text-emerald-400"><%= @email_success %></p>
        </div>
      <% end %>

      <%= if !@verification_code_sent do %>
        <%!-- Email input form --%>
        <form phx-submit="send_verification_code" class="space-y-4">
          <div>
            <input
              type="email"
              name="email"
              placeholder="you@example.com"
              required
              class="w-full px-4 py-3 rounded-xl text-sm font-haas_roman_55
                     bg-white/[0.04] border border-white/[0.08] text-white
                     placeholder-white/20
                     focus:border-white/20 focus:ring-1 focus:ring-white/10 focus:outline-none
                     transition-all duration-150"
            />
          </div>

          <button
            type="submit"
            class="w-full py-3 rounded-xl text-sm font-haas_medium_65
                   bg-white text-[#0f0f0f]
                   hover:bg-gray-100 active:scale-[0.98]
                   transition-all duration-150 cursor-pointer"
          >
            Send verification code
          </button>
        </form>
      <% else %>
        <%!-- Code input form --%>
        <form phx-submit="verify_code" class="space-y-4">
          <div>
            <label class="block text-xs font-haas_roman_55 text-white/30 mb-2">
              Enter the 6-digit code sent to your email
            </label>
            <input
              type="text"
              name="code"
              placeholder="000000"
              maxlength="6"
              pattern="[0-9]{6}"
              inputmode="numeric"
              autocomplete="one-time-code"
              required
              class="w-full px-4 py-3 rounded-xl text-center text-lg font-haas_medium_65 tracking-[0.3em]
                     bg-white/[0.04] border border-white/[0.08] text-white
                     placeholder-white/15
                     focus:border-white/20 focus:ring-1 focus:ring-white/10 focus:outline-none
                     transition-all duration-150"
            />
          </div>

          <button
            type="submit"
            class="w-full py-3 rounded-xl text-sm font-haas_medium_65
                   bg-white text-[#0f0f0f]
                   hover:bg-gray-100 active:scale-[0.98]
                   transition-all duration-150 cursor-pointer"
          >
            Verify
          </button>

          <%!-- Resend --%>
          <div class="text-center">
            <%= if @resend_cooldown > 0 do %>
              <span class="text-xs font-haas_roman_55 text-white/20">
                Resend in <%= @resend_cooldown %>s
              </span>
            <% else %>
              <button
                type="button"
                phx-click="resend_code"
                class="text-xs font-haas_roman_55 text-white/30 hover:text-white/50
                       transition-colors cursor-pointer"
              >
                Didn't receive it? Resend code
              </button>
            <% end %>
          </div>
        </form>
      <% end %>

      <%!-- Skip --%>
      <button
        phx-click="onboarding_skip"
        class="mt-4 w-full py-2 text-xs font-haas_roman_55 text-white/20
               hover:text-white/35 transition-colors cursor-pointer"
      >
        Skip for now
      </button>
    </div>
    """
  end

  # ── Step 3: Legacy BUX Claim ─────────────────────────────────

  attr :legacy_bux_amount, :any, default: nil
  attr :claiming, :boolean, default: false
  attr :claim_success, :boolean, default: false

  defp claim_step(assigns) do
    formatted_bux = if assigns.legacy_bux_amount do
      :erlang.float_to_binary(assigns.legacy_bux_amount / 1.0, decimals: 0)
    else
      "0"
    end

    assigns = assign(assigns, :formatted_bux, formatted_bux)

    ~H"""
    <div class="px-8 pt-10 pb-8 text-center">
      <%= if @claim_success do %>
        <%!-- Success state --%>
        <div class="mx-auto mb-6 w-14 h-14 rounded-2xl bg-emerald-500/10 border border-emerald-500/20
                    flex items-center justify-center">
          <svg class="w-7 h-7 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>

        <h2 class="text-lg font-haas_medium_65 text-white tracking-tight mb-2">
          BUX claimed!
        </h2>
        <p class="text-sm font-haas_roman_55 text-white/40 mb-8">
          <span class="text-[#CAFC00] font-haas_medium_65"><%= @formatted_bux %> BUX</span>
          has been minted to your wallet
        </p>

        <button
          phx-click="onboarding_skip"
          class="w-full py-3 rounded-xl text-sm font-haas_medium_65
                 bg-white text-[#0f0f0f]
                 hover:bg-gray-100 active:scale-[0.98]
                 transition-all duration-150 cursor-pointer"
        >
          Start reading
        </button>
      <% else %>
        <%!-- Claim state --%>
        <div class="mx-auto mb-6 w-14 h-14 rounded-2xl bg-[#CAFC00]/[0.06] border border-[#CAFC00]/10
                    flex items-center justify-center">
          <svg class="w-7 h-7 text-[#CAFC00]/70" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 11.25v8.25a1.5 1.5 0 01-1.5 1.5H5.25a1.5 1.5 0 01-1.5-1.5v-8.25M12 4.875A2.625 2.625 0 109.375 7.5H12m0-2.625V7.5m0-2.625A2.625 2.625 0 1114.625 7.5H12m0 0V21m-8.625-9.75h18c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125h-18c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125z" />
          </svg>
        </div>

        <h2 class="text-lg font-haas_medium_65 text-white tracking-tight mb-2">
          We found your BUX
        </h2>
        <p class="text-sm font-haas_roman_55 text-white/40 mb-6">
          Your previous Blockster account has a balance
        </p>

        <%!-- Balance display --%>
        <div class="mb-8 py-5 rounded-xl bg-white/[0.03] border border-white/[0.05]">
          <div class="text-3xl font-haas_medium_65 text-white tracking-tight">
            <%= @formatted_bux %>
            <span class="text-[#CAFC00]/60 text-lg ml-1">BUX</span>
          </div>
          <div class="text-xs font-haas_roman_55 text-white/25 mt-1.5">
            From your legacy account
          </div>
        </div>

        <button
          phx-click="claim_legacy_bux"
          disabled={@claiming}
          class={"w-full py-3 rounded-xl text-sm font-haas_medium_65
                 transition-all duration-150 cursor-pointer
                 #{if @claiming, do: "bg-white/10 text-white/40", else: "bg-white text-[#0f0f0f] hover:bg-gray-100 active:scale-[0.98]"}"}
        >
          <%= if @claiming do %>
            <span class="inline-flex items-center gap-2">
              <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-20" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3"></circle>
                <path class="opacity-80" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
              </svg>
              Claiming...
            </span>
          <% else %>
            Claim BUX to your wallet
          <% end %>
        </button>

        <button
          phx-click="onboarding_skip"
          class="mt-3 w-full py-2 text-xs font-haas_roman_55 text-white/20
                 hover:text-white/35 transition-colors cursor-pointer"
        >
          Skip
        </button>
      <% end %>
    </div>
    """
  end

  # ── Complete ─────────────────────────────────────────────────

  defp complete_step(assigns) do
    ~H"""
    <div class="px-8 pt-10 pb-8 text-center">
      <div class="mx-auto mb-6 w-14 h-14 rounded-2xl bg-emerald-500/10 border border-emerald-500/20
                  flex items-center justify-center">
        <svg class="w-7 h-7 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      </div>

      <h2 class="text-lg font-haas_medium_65 text-white tracking-tight mb-2">
        You're all set
      </h2>
      <p class="text-sm font-haas_roman_55 text-white/40 mb-8">
        Start reading to earn BUX rewards
      </p>

      <button
        phx-click="onboarding_skip"
        class="w-full py-3 rounded-xl text-sm font-haas_medium_65
               bg-white text-[#0f0f0f]
               hover:bg-gray-100 active:scale-[0.98]
               transition-all duration-150 cursor-pointer"
      >
        Start reading
      </button>
    </div>
    """
  end
end
