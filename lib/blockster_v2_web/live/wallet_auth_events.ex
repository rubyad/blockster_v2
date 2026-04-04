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
          {:wallet_authenticated, wallet_address}, socket ->
            if BlocksterV2Web.WalletAuthEvents.has_custom_wallet_handler?(view) do
              {:cont, socket}
            else
              case BlocksterV2.Accounts.get_or_create_user_by_wallet(wallet_address) do
                {:ok, user, _session, _is_new} ->
                  BlocksterV2.BuxMinter.sync_user_balances_async(user.id, wallet_address, force: true)
                  token_balances = BlocksterV2.EngagementTracker.get_user_token_balances(user.id)

                  {:halt,
                   socket
                   |> Phoenix.Component.assign(:current_user, user)
                   |> Phoenix.Component.assign(:wallet_address, wallet_address)
                   |> Phoenix.Component.assign(:token_balances, token_balances)}

                {:error, _reason} ->
                  {:halt, socket}
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
        detected = socket.assigns[:detected_wallets] || []

        cond do
          length(detected) == 1 ->
            wallet_name = hd(detected)["name"] || hd(detected)[:name]

            socket =
              socket
              |> assign(:connecting, true)
              |> push_event("request_connect", %{wallet_name: wallet_name})

            {:noreply, socket}

          length(detected) == 0 ->
            socket =
              socket
              |> assign(:connecting, true)
              |> push_event("discover_and_connect", %{})

            {:noreply, socket}

          true ->
            {:noreply, assign(socket, :show_wallet_selector, true)}
        end
      end

      def handle_event("open_wallet_modal", _, socket) do
        {:noreply, assign(socket, show_wallet_selector: true, connecting: false)}
      end

      def handle_event("hide_wallet_selector", _, socket) do
        {:noreply, assign(socket, :show_wallet_selector, false)}
      end

      # ── Wallet Connection ──

      def handle_event("select_wallet", %{"name" => wallet_name}, socket) do
        socket =
          socket
          |> assign(:show_wallet_selector, false)
          |> assign(:connecting, true)
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
                |> push_event("persist_session", %{wallet_address: wallet_address})

              send(self(), {:wallet_authenticated, wallet_address})
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

      # ── Wallet Auto-Reconnect (skip SIWS) ──

      def handle_event("wallet_reconnected", %{"pubkey" => pubkey}, socket) do
        if BlocksterV2Web.WalletAuthEvents.valid_pubkey?(pubkey) do
          socket =
            socket
            |> assign(:wallet_address, pubkey)
            |> assign(:connecting, false)
            |> push_event("persist_session", %{wallet_address: pubkey})

          send(self(), {:wallet_authenticated, pubkey})
          {:noreply, socket}
        else
          {:noreply, socket}
        end
      end

      # ── Wallet Error ──

      def handle_event("wallet_error", %{"error" => error}, socket) do
        {:noreply, socket |> assign(:connecting, false) |> put_flash(:error, error)}
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
          |> assign(:auth_challenge, nil)
          |> push_event("request_disconnect", %{})
          |> push_event("clear_session", %{})

        {:noreply, socket}
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

        {:noreply, socket}
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

  def default_assigns do
    [
      detected_wallets: [],
      show_wallet_selector: false,
      connecting: false,
      auth_challenge: nil,
      wallet_address: nil,
      sol_balance: nil,
      bux_balance: nil
    ]
  end
end
