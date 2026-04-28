defmodule BlocksterV2Web.WalletAuthEvents do
  @moduledoc """
  Shared wallet auth event handlers for all LiveViews.
  Injected via the `live_view` macro in BlocksterV2Web.

  Uses @before_compile for handle_event fallbacks and attach_hook for
  handle_info interception. This ensures wallet events work in all LiveViews
  without conflicting with module-level handlers.
  """

  defmacro __using__(_opts) do
    quote do
      @before_compile BlocksterV2Web.WalletAuthEvents

      def __wallet_auth_attach_hook__(socket) do
        view = socket.view

        Phoenix.LiveView.attach_hook(socket, :wallet_auth, :handle_info, fn
          {:wallet_authenticated, wallet_address, is_new_from_auth}, socket ->
            if BlocksterV2Web.WalletAuthEvents.has_custom_wallet_handler?(view) do
              {:cont, socket}
            else
              # NOTE: do NOT call get_or_create_user_by_wallet here — the user was
              # already created by AuthController.create_session during the
              # persist_session HTTP call. Calling get_or_create again would always
              # return is_new=false (because the user now exists), which is why we
              # rely on `is_new_from_auth` passed through the JS session_persisted
              # event for the onboarding redirect decision.
              case BlocksterV2.Accounts.get_user_by_wallet_address(wallet_address) do
                nil ->
                  {:halt, socket}

                user ->
                  is_new = is_new_from_auth == true
                  BlocksterV2.BuxMinter.sync_user_balances_async(user.id, wallet_address, force: true)
                  token_balances = BlocksterV2.EngagementTracker.get_user_token_balances(user.id)

                  prev_user_id = case socket.assigns[:current_user] do
                    %{id: id} -> id
                    _ -> nil
                  end

                  already_signed_in_here? = prev_user_id != nil
                  user_changed? = already_signed_in_here? and prev_user_id != user.id
                  same_user_reauth? = already_signed_in_here? and prev_user_id == user.id

                  socket =
                    socket
                    |> Phoenix.Component.assign(:current_user, user)
                    |> Phoenix.Component.assign(:wallet_address, wallet_address)
                    |> Phoenix.Component.assign(:token_balances, token_balances)
                    |> Phoenix.Component.assign(:bux_balance, Map.get(token_balances, "BUX", 0))

                  cond do
                    is_new ->
                      # Brand new wallet → walk through onboarding. Use redirect/2
                      # (full HTTP reload) so the new session cookie is read fresh
                      # by the next mount instead of relying on the stale
                      # WebSocket-cached session map.
                      {:halt, Phoenix.LiveView.redirect(socket, to: "/onboarding")}

                    user_changed? ->
                      # Switched accounts mid-session → hard reload to wipe all
                      # LiveView assigns (rewards, multipliers, balances) and to
                      # re-read the now-updated session cookie.
                      {:halt, Phoenix.LiveView.redirect(socket, to: "/")}

                    same_user_reauth? ->
                      # Same user as the LiveView already has — this fires
                      # when a silent wallet-reconnect re-enters the full auth
                      # path despite the session already being valid. Just
                      # sync assigns; redirecting here would reload the page,
                      # re-trigger auto-reconnect, and loop forever.
                      {:halt, socket}

                    true ->
                      # Fresh sign-in (no prior current_user) — the WebSocket's
                      # session map was captured BEFORE login, so any
                      # subsequent live-navigate to a different page would
                      # re-mount with a stale session and lose current_user.
                      # Force a full HTTP reload so the new session cookie is
                      # picked up fresh. Land on the homepage — small UX cost
                      # vs staying on the current page, but guarantees every
                      # downstream page sees the signed-in user.
                      {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
                  end
              end
            end

          _other, socket ->
            {:cont, socket}
        end)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      # ── Wallet Detection ──

      def handle_event("wallets_detected", %{"wallets" => wallets}, socket) do
        {:noreply, assign(socket, :detected_wallets, wallets)}
      end

      # ── Wallet Selector Modal ──

      def handle_event("show_wallet_selector", _, socket) do
        {:noreply, assign(socket, show_wallet_selector: true, connecting: false, connecting_wallet_name: nil)}
      end

      def handle_event("open_wallet_modal", _, socket) do
        {:noreply, assign(socket, show_wallet_selector: true, connecting: false, connecting_wallet_name: nil)}
      end

      def handle_event("hide_wallet_selector", _, socket) do
        {:noreply, assign(socket, show_wallet_selector: false, connecting_wallet_name: nil)}
      end

      # Pushed by the Web3Auth JS hook when a returning user's Web3Auth session
      # has expired and silent reconnect failed. OAuth (X / Google / Apple)
      # users' wallets are keyed to the OAuth provider's MPC verifier — we
      # can't re-derive the keypair server-side. Set a flag so the layout
      # renders a "Reconnect wallet" pill that swaps in for the normal user
      # pill. We deliberately do NOT open the modal here — that's done on
      # explicit user click via `start_wallet_reauth` below.
      def handle_event("web3auth_reauth_required", %{"provider" => provider}, socket) do
        {:noreply,
         socket
         |> assign(:needs_wallet_reauth, true)
         |> assign(:reauth_provider, if(provider == "", do: nil, else: provider))}
      end

      # Triggered by the Reconnect-wallet pill. Dispatches to the original
      # provider's start_*_login if known; otherwise opens the wallet modal
      # so the user can pick.
      def handle_event("start_wallet_reauth", _params, socket) do
        case socket.assigns[:reauth_provider] do
          "twitter" ->
            {:noreply,
             socket
             |> assign(:connecting, true)
             |> assign(:connecting_provider, "twitter")
             |> push_event("start_web3auth_login", %{provider: "twitter"})}

          "google" ->
            {:noreply,
             socket
             |> assign(:connecting, true)
             |> assign(:connecting_provider, "google")
             |> push_event("start_web3auth_login", %{provider: "google"})}

          "telegram" ->
            {:noreply,
             socket
             |> assign(:connecting, true)
             |> assign(:connecting_provider, "telegram")
             |> push_event("start_telegram_widget", %{})}

          _ ->
            # Unknown / not stashed — let the user pick from the modal.
            {:noreply,
             socket
             |> assign(:show_wallet_selector, true)
             |> assign(:connecting, false)
             |> assign(:connecting_wallet_name, nil)}
        end
      end

      # ── Wallet Connection ──

      def handle_event("select_wallet", %{"name" => wallet_name}, socket) do
        socket =
          socket
          |> assign(:show_wallet_selector, false)
          |> assign(:connecting, true)
          |> assign(:connecting_wallet_name, wallet_name)
          |> push_event("request_connect", %{wallet_name: wallet_name})

        {:noreply, socket}
      end

      def handle_event("wallet_connected", %{"pubkey" => pubkey}, socket) do
        if BlocksterV2Web.WalletAuthEvents.valid_pubkey?(pubkey) do
          if connected?(socket) do
            {:ok, challenge} = BlocksterV2.Auth.SolanaAuth.generate_challenge(pubkey)

            socket =
              socket
              |> assign(:auth_challenge, %{pubkey: pubkey, message: challenge.message, nonce: challenge.nonce})
              |> push_event("request_sign", %{message: challenge.message, nonce: challenge.nonce})

            {:noreply, socket}
          else
            {:noreply, socket}
          end
        else
          {:noreply, assign(socket, connecting: false) |> put_flash(:error, "Invalid wallet address")}
        end
      end

      def handle_event("wallet_connected", _params, socket) do
        {:noreply, assign(socket, connecting: false)}
      end

      # ── Signature Verification ──

      def handle_event("signature_submitted", %{"signature" => signature}, socket) do
        challenge = socket.assigns.auth_challenge

        if challenge do
          case BlocksterV2.Auth.SolanaAuth.verify_signature(challenge.pubkey, challenge.message, signature) do
            {:ok, wallet_address} ->
              socket =
                socket
                |> assign(:wallet_address, wallet_address)
                |> assign(:connecting, false)
                |> assign(:auth_challenge, nil)
                # Wait for `session_persisted` before firing :wallet_authenticated.
                # This prevents a race where push_navigate to a different
                # live_session loads /onboarding before the session cookie
                # has been written by the JS hook.
                |> assign(:pending_wallet_auth, wallet_address)
                |> push_event("persist_session", %{wallet_address: wallet_address})

              {:noreply, socket}

            {:error, _reason} ->
              socket =
                socket
                |> assign(:connecting, false)
                |> assign(:auth_challenge, nil)
                |> put_flash(:error, "Signature verification failed")

              {:noreply, socket}
          end
        else
          {:noreply, assign(socket, connecting: false)}
        end
      end

      # JS confirms the session cookie has been written — now safe to load the
      # user and (if needed) push_navigate. `is_new_user` was returned by
      # AuthController.create_session and forwarded here by JS so we can
      # authoritatively decide whether to redirect to /onboarding.
      def handle_event("session_persisted", %{"wallet_address" => wallet_address} = params, socket) do
        is_new_user = Map.get(params, "is_new_user", false) == true

        case socket.assigns[:pending_wallet_auth] do
          ^wallet_address ->
            send(self(), {:wallet_authenticated, wallet_address, is_new_user})
            {:noreply, assign(socket, :pending_wallet_auth, nil)}

          _ ->
            {:noreply, socket}
        end
      end

      # ── Wallet Auto-Reconnect (skip SIWS) ──

      def handle_event("wallet_reconnected", %{"pubkey" => pubkey}, socket) do
        if BlocksterV2Web.WalletAuthEvents.valid_pubkey?(pubkey) do
          already_signed_in_here? =
            case socket.assigns[:current_user] do
              %{wallet_address: ^pubkey} -> true
              _ -> false
            end

          if already_signed_in_here? do
            # Silent-reconnect case: the LiveView mounted with current_user
            # already loaded from the session cookie, AND the reconnected
            # wallet matches that user. Just sync the wallet_address assign
            # and stop — pushing persist_session here would kick off a
            # `session_persisted → :wallet_authenticated → redirect(to: "/")`
            # chain that reloads the page, which on re-mount triggers
            # another auto-reconnect… i.e. an infinite reload loop.
            {:noreply,
             socket
             |> assign(:wallet_address, pubkey)
             |> assign(:connecting, false)}
          else
            # No session yet (or session cookie was invalidated) — run the
            # full persist flow so the cookie gets (re-)minted and the
            # LiveView picks up current_user on the next mount.
            socket =
              socket
              |> assign(:wallet_address, pubkey)
              |> assign(:connecting, false)
              |> assign(:pending_wallet_auth, pubkey)
              |> push_event("persist_session", %{wallet_address: pubkey})

            {:noreply, socket}
          end
        else
          {:noreply, socket}
        end
      end

      # ── Wallet Error ──

      def handle_event("wallet_error", %{"error" => error}, socket) do
        {:noreply, socket |> assign(:connecting, false) |> assign(:connecting_wallet_name, nil) |> put_flash(:error, error)}
      end

      # ── Web3Auth Social Login ──
      #
      # UI entry points from the sign-in modal (wallet_components.ex). Each
      # button pushes a `start_web3auth_login` event down to the Web3Auth JS
      # hook with the right provider key. On success the hook sends
      # `web3auth_authenticated` back with { wallet_address, id_token, ... }
      # which we POST to /api/auth/web3auth/session to mint a session cookie.

      def handle_event("start_email_login", %{"email" => email}, socket) do
        email = String.trim(email || "")

        cond do
          email == "" ->
            {:noreply, put_flash(socket, :error, "Enter your email.")}

          not BlocksterV2Web.WalletAuthEvents.valid_email?(email) ->
            {:noreply, put_flash(socket, :error, "That doesn't look like a valid email.")}

          true ->
            case BlocksterV2.Auth.EmailOtpStore.send_otp(email) do
              {:ok, _ttl} ->
                socket =
                  socket
                  |> assign(:email_prefill, email)
                  |> assign(:email_otp_stage, :enter_code)
                  |> assign(:email_otp_error, nil)
                  |> assign(:email_otp_resend_cooldown, 60)

                # Tick down the resend cooldown so the UI can render a live timer.
                Process.send_after(self(), :email_otp_cooldown_tick, 1000)
                {:noreply, socket}

              {:error, {:rate_limited, seconds}} ->
                socket =
                  socket
                  |> assign(:email_prefill, email)
                  |> assign(:email_otp_stage, :enter_code)
                  |> assign(:email_otp_resend_cooldown, seconds)
                  |> assign(:email_otp_error, "Please wait #{seconds}s before requesting another code.")

                Process.send_after(self(), :email_otp_cooldown_tick, 1000)
                {:noreply, socket}
            end
        end
      end

      def handle_event("start_email_login", _params, socket) do
        {:noreply, put_flash(socket, :error, "Enter your email.")}
      end

      # User entered the code in the modal. Verify + issue a JWT, then
      # hand it to the Web3Auth hook via the CUSTOM connector path.
      def handle_event("verify_email_otp", %{"code" => code}, socket) do
        email = socket.assigns[:email_prefill]
        code = String.trim(code || "")

        cond do
          email in [nil, ""] ->
            {:noreply, assign(socket, :email_otp_error, "Enter your email first.")}

          String.length(code) < 4 ->
            {:noreply, assign(socket, :email_otp_error, "Enter the 6-digit code from your email.")}

          true ->
            case BlocksterV2.Auth.EmailOtpStore.verify_otp(email, code) do
              {:ok, normalized_email} ->
                claims = %{
                  "sub" => normalized_email,
                  "email" => normalized_email,
                  "email_verified" => true
                }

                id_token = BlocksterV2.Auth.Web3AuthSigning.sign_id_token(claims)

                socket =
                  socket
                  |> assign(:email_otp_stage, nil)
                  |> assign(:email_otp_error, nil)
                  |> assign(:connecting, true)
                  |> assign(:connecting_provider, "email")
                  |> push_event("start_web3auth_jwt_login", %{
                    provider: "email",
                    id_token: id_token,
                    verifier_id: "blockster-email",
                    verifier_id_field: "sub"
                  })

                {:noreply, socket}

              {:error, :invalid_code} ->
                {:noreply, assign(socket, :email_otp_error, "Invalid code. Try again.")}

              {:error, :expired} ->
                {:noreply,
                 socket
                 |> assign(:email_otp_stage, :enter_email)
                 |> assign(:email_otp_error, "Code expired. Request a new one.")}

              {:error, :not_found} ->
                {:noreply,
                 socket
                 |> assign(:email_otp_stage, :enter_email)
                 |> assign(:email_otp_error, "No code pending. Request a new one.")}

              {:error, {:locked, _seconds}} ->
                {:noreply,
                 socket
                 |> assign(:email_otp_stage, :enter_email)
                 |> assign(:email_otp_error, "Too many attempts. Try again in a few minutes.")}
            end
        end
      end

      # Go back to the email entry stage (e.g. typo'd email). Keeps the
      # OTP server-side — it'll expire on its own ttl.
      def handle_event("email_otp_back", _params, socket) do
        {:noreply,
         socket
         |> assign(:email_otp_stage, :enter_email)
         |> assign(:email_otp_error, nil)}
      end

      # Resend code — same path as submitting a new email, with the
      # rate-limit enforced server-side.
      def handle_event("resend_email_otp", _params, socket) do
        email = socket.assigns[:email_prefill]

        if is_binary(email) and email != "" do
          handle_event("start_email_login", %{"email" => email}, socket)
        else
          {:noreply, assign(socket, :email_otp_error, "Enter your email.")}
        end
      end

      def handle_info(:email_otp_cooldown_tick, socket) do
        remaining = (socket.assigns[:email_otp_resend_cooldown] || 0) - 1

        if remaining > 0 do
          Process.send_after(self(), :email_otp_cooldown_tick, 1000)
          {:noreply, assign(socket, :email_otp_resend_cooldown, remaining)}
        else
          {:noreply, assign(socket, :email_otp_resend_cooldown, 0)}
        end
      end

      def handle_event("start_x_login", _params, socket) do
        socket =
          socket
          |> assign(:connecting, true)
          |> assign(:connecting_provider, "twitter")
          |> push_event("start_web3auth_login", %{provider: "twitter"})

        {:noreply, socket}
      end

      def handle_event("start_google_login", _params, socket) do
        socket =
          socket
          |> assign(:connecting, true)
          |> assign(:connecting_provider, "google")
          |> push_event("start_web3auth_login", %{provider: "google"})

        {:noreply, socket}
      end

      def handle_event("start_telegram_login", _params, socket) do
        # Telegram requires a two-step flow: widget → /api/auth/telegram/verify
        # returns a Blockster JWT → THEN start_web3auth_login with that JWT.
        # The modal's Telegram button currently flags the intent; the widget
        # embed + verification dance lands fully wired in Phase 5.1 (TODO).
        # For now we show the connecting state and let the user cancel.
        socket =
          socket
          |> assign(:connecting, true)
          |> assign(:connecting_provider, "telegram")
          |> push_event("start_telegram_widget", %{})

        {:noreply, socket}
      end

      # The Web3Auth JS hook sends this back when it has a valid id_token + pubkey.
      # Forward to the AuthController which validates the JWT and sets the
      # session cookie. We fetch the result server-side (via a Task) rather
      # than trusting the client to round-trip HTTP — this keeps the tx
      # signing flow consistent with the wallet path.
      def handle_event("web3auth_authenticated", params, socket) do
        wallet_address = params["wallet_address"]
        id_token = params["id_token"]
        provider = params["provider"] || "email"

        cond do
          not is_binary(wallet_address) or wallet_address == "" ->
            {:noreply, assign(socket, connecting: false, connecting_provider: nil)
              |> put_flash(:error, "Web3Auth did not return a wallet address.")}

          not is_binary(id_token) or id_token == "" ->
            {:noreply, assign(socket, connecting: false, connecting_provider: nil)
              |> put_flash(:error, "Web3Auth did not return an ID token.")}

          true ->
            # Stash for server-side session mint via persist_web3auth_session
            # JS event (mirrors the wallet path's persist_session hook — the
            # JS hook POSTs to /api/auth/web3auth/session so the session cookie
            # lands before we route to /onboarding).
            socket =
              socket
              |> assign(:pending_wallet_auth, wallet_address)
              |> assign(:pending_web3auth_provider, provider)
              |> push_event("persist_web3auth_session", %{
                wallet_address: wallet_address,
                id_token: id_token,
                provider: provider
              })

            {:noreply, socket}
        end
      end

      # JS hook confirms /api/auth/web3auth/session returned success and set
      # the session cookie. Now safe to fire :wallet_authenticated (same
      # downstream path as the wallet flow — onboarding redirect etc.).
      #
      # `wallet_address` here is the CANONICAL wallet from the server response
      # (what the user is actually logged in as). `derived_pubkey` is the
      # Web3Auth-derived pubkey from the JWT. These differ when the server
      # matched the user by email into an existing account — in that case
      # the derived pubkey is orphaned and we route the session through the
      # canonical one.
      def handle_event("web3auth_session_persisted", %{"wallet_address" => wallet_address} = params, socket) do
        is_new_user = Map.get(params, "is_new_user", false) == true
        derived_pubkey = Map.get(params, "derived_pubkey", wallet_address)

        # Accept if pending matches either the derived pubkey (normal path)
        # or the canonical wallet (email-collision path).
        pending = socket.assigns[:pending_wallet_auth]

        if pending == derived_pubkey or pending == wallet_address do
          send(self(), {:wallet_authenticated, wallet_address, is_new_user})

          {:noreply,
           socket
           |> assign(:pending_wallet_auth, nil)
           |> assign(:pending_web3auth_provider, nil)
           |> assign(:connecting, false)
           |> assign(:connecting_provider, nil)
           |> assign(:show_wallet_selector, false)
           |> assign(:needs_wallet_reauth, false)
           |> assign(:reauth_provider, nil)}
        else
          {:noreply, socket}
        end
      end

      def handle_event("web3auth_error", %{"error" => error}, socket) do
        # Keep the wallet selector open so the user can retry immediately
        # without navigating away. Web3Auth failures are often transient
        # (backend 502s, popup blockers) — a visible modal + flash is a
        # better recovery path than silently returning to the page.
        {:noreply,
         socket
         |> assign(:connecting, false)
         |> assign(:connecting_provider, nil)
         |> assign(:show_wallet_selector, true)
         |> put_flash(:error, error)}
      end

      # Telegram widget payload arrives here after user approves in the
      # Telegram Login Widget popup. We POST it to /api/auth/telegram/verify
      # from JS — this handler is the LiveView side of that chain, retained
      # for future expansion (e.g., Cloudflare tunnel verification status).
      def handle_event("telegram_widget_payload", %{"payload" => _payload}, socket) do
        # The JS hook handles the full HTTP roundtrip + eventual connectTo;
        # we only assign connecting state here so UI reflects it.
        {:noreply, assign(socket, connecting: true, connecting_provider: "telegram")}
      end

      # ── Disconnect ──

      def handle_event("disconnect_wallet", _, socket) do
        socket =
          socket
          |> assign(:wallet_address, nil)
          |> assign(:current_user, nil)
          |> assign(:sol_balance, nil)
          |> assign(:bux_balance, nil)
          |> assign(:connecting, false)
          |> assign(:connecting_provider, nil)
          |> assign(:auth_challenge, nil)
          |> push_event("request_disconnect", %{})
          |> push_event("clear_session", %{})

        # Hard reload so the cleared session cookie is re-read and all
        # per-user LiveView assigns (rewards, multipliers, balances) don't
        # leak across logins.
        {:noreply, redirect(socket, to: "/")}
      end

      def handle_event("wallet_disconnected", _, socket) do
        socket =
          socket
          |> assign(:wallet_address, nil)
          |> assign(:current_user, nil)
          |> assign(:sol_balance, nil)
          |> assign(:bux_balance, nil)
          |> assign(:connecting, false)
          |> assign(:auth_challenge, nil)

        # Same reason as disconnect_wallet — full reset.
        {:noreply, redirect(socket, to: "/")}
      end

      # ── Balance Async Handlers ──

      def handle_async(:fetch_sol_balance, {:ok, balance}, socket) when is_number(balance) do
        {:noreply, assign(socket, :sol_balance, balance)}
      end

      def handle_async(:fetch_sol_balance, _, socket), do: {:noreply, socket}

      def handle_async(:fetch_bux_balance, {:ok, balance}, socket) when is_number(balance) do
        {:noreply, assign(socket, :bux_balance, balance)}
      end

      def handle_async(:fetch_bux_balance, _, socket), do: {:noreply, socket}
    end
  end

  @doc false
  # LiveViews that define their own handle_info({:wallet_authenticated, _}) handler
  @custom_wallet_handler_views []

  def has_custom_wallet_handler?(view), do: view in @custom_wallet_handler_views

  def valid_pubkey?(pubkey) when is_binary(pubkey) do
    byte_size(pubkey) >= 32 and byte_size(pubkey) <= 44
  end

  def valid_pubkey?(_), do: false

  @doc """
  Loose email validation — good enough to reject obvious garbage before we
  round-trip to Web3Auth's `EMAIL_PASSWORDLESS` endpoint (which does the
  authoritative check). Not RFC 5322 compliant; intentionally so.
  """
  def valid_email?(email) when is_binary(email) do
    String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
  end

  def valid_email?(_), do: false

  @doc """
  Build the Web3Auth config map the wallet_selector_modal passes down to the
  JS hook via data attributes. Reads from env with dev fallbacks. Returns
  an empty map with `client_id: ""` when `SOCIAL_LOGIN_ENABLED` is off so the
  modal hides the social section entirely.
  """
  def web3auth_config do
    enabled = String.trim(System.get_env("SOCIAL_LOGIN_ENABLED", "false")) == "true"

    if enabled do
      %{
        client_id: clean_env("WEB3AUTH_CLIENT_ID"),
        rpc_url: clean_env("SOLANA_RPC_URL") |> default_rpc_url(),
        chain_id: clean_env("WEB3AUTH_CHAIN_ID") |> default_chain_id(),
        network: clean_env("WEB3AUTH_NETWORK") |> default_network(),
        telegram_verifier_id: clean_env("WEB3AUTH_TELEGRAM_VERIFIER_ID"),
        telegram_bot_username: clean_env("TELEGRAM_LOGIN_BOT_USERNAME"),
        telegram_bot_id: telegram_bot_id_from_token()
      }
    else
      %{client_id: ""}
    end
  end

  # Telegram's Login.auth({bot_id, …}, callback) widget popup needs the
  # numeric bot ID, which is the substring before ":" in the bot token.
  # Derive it server-side and expose via data attribute so we never ship
  # the bot token itself to the client. Mirrors the env-var precedence
  # used by AuthController.telegram_verify/2.
  defp telegram_bot_id_from_token do
    token =
      clean_env("BLOCKSTER_V2_BOT_TOKEN")
      |> case do
        "" -> clean_env("TELEGRAM_V2_BOT_TOKEN")
        v -> v
      end
      |> case do
        "" -> Application.get_env(:blockster_v2, :telegram_v2_bot_token) || ""
        v -> v
      end

    case String.split(token, ":", parts: 2) do
      [id, _secret] when id != "" -> id
      _ -> ""
    end
  end

  defp clean_env(key) do
    (System.get_env(key) || "")
    |> String.trim()
    |> String.trim("\"")
    |> String.trim("'")
    |> String.trim()
  end

  defp default_chain_id(""),
    do: prod_required_env_or_dev_default("WEB3AUTH_CHAIN_ID", "0x67", "0x65 for Solana mainnet")

  defp default_chain_id(id), do: id

  defp default_network(""),
    do:
      prod_required_env_or_dev_default(
        "WEB3AUTH_NETWORK",
        "SAPPHIRE_DEVNET",
        "SAPPHIRE_MAINNET"
      )

  defp default_network(net), do: net

  # Web3Auth requires a concrete RPC URL at init time (Web3Auth.init() constructs
  # `new URL(rpcTarget)`; empty string throws `Invalid URL`). Dev fallback matches
  # the QuickNode devnet endpoint used by the settler service and the Phase 0
  # prototype. In prod, `SOLANA_RPC_URL` MUST be set via fly secrets — we raise
  # rather than silently fall back to devnet.
  defp default_rpc_url(""),
    do:
      prod_required_env_or_dev_default(
        "SOLANA_RPC_URL",
        "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/",
        "your QuickNode mainnet RPC URL"
      )

  defp default_rpc_url(url), do: url

  # In :prod, an unset env var is a deploy bug — raise loudly so misconfig
  # surfaces immediately instead of silently routing mainnet traffic to devnet.
  # In :dev/:test, fall back to the dev default so local work keeps working.
  defp prod_required_env_or_dev_default(env_name, dev_default, mainnet_hint) do
    if Application.get_env(:blockster_v2, :env) == :prod do
      raise """
      #{env_name} is required in production but was empty.
      Set via: flyctl secrets set #{env_name}="#{mainnet_hint}" --stage --app blockster-v2
      """
    else
      dev_default
    end
  end

  @doc """
  Returns true when social login should be shown in the UI. Driven by env.
  """
  def social_login_enabled? do
    String.trim(System.get_env("SOCIAL_LOGIN_ENABLED", "false")) == "true"
  end

  def default_assigns do
    [
      detected_wallets: [],
      show_wallet_selector: false,
      connecting: false,
      connecting_wallet_name: nil,
      connecting_provider: nil,
      email_prefill: nil,
      email_otp_stage: nil,
      email_otp_error: nil,
      email_otp_resend_cooldown: 0,
      pending_web3auth_provider: nil,
      auth_challenge: nil,
      wallet_address: nil,
      sol_balance: nil,
      bux_balance: nil
    ]
  end
end
