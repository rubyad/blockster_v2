defmodule BlocksterV2Web.Admin.Web3AuthSfaTestLive do
  @moduledoc """
  Phase 0 parity test for the Web3Auth SFA mobile migration.

  An admin enters a user id or email; the LiveView mints a fresh JWT (same
  shape `BlocksterV2Web.AuthController.refresh_web3auth_jwt/2` produces in
  production) and renders the `Web3AuthSfaTest` JS hook with the JWT plus
  verifier config. The hook calls `@toruslabs/customauth`'s `getTorusKey`
  in the browser, derives the Solana pubkey via SFA's iframe-free path,
  and pushes it back via `sfa_derived_pubkey`. The LiveView compares the
  derived pubkey against `user.wallet_address` (the modal-derived pubkey
  from production sign-in) and renders MATCH or MISMATCH.

  Match across the email + Telegram verifier set means SFA can replace
  modal on mobile without breaking on-chain wallet bindings. See
  `docs/web3auth_sfa_migration.md` for the full plan and decision gate.

  Admin-only — gated by `live_session :admin` -> `BlocksterV2Web.AdminAuth`.
  """
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Accounts
  alias BlocksterV2.Auth.Web3AuthSigning
  alias BlocksterV2Web.WalletAuthEvents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:lookup_input, "")
     |> assign(:user, nil)
     |> assign(:test_payload, nil)
     |> assign(:result, nil)
     |> assign(:error, nil)
     |> assign(:web3auth_config, WalletAuthEvents.web3auth_config())}
  end

  @impl true
  def handle_event("lookup_user", %{"lookup_input" => input}, socket) do
    {:noreply, run_lookup(socket, input)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:lookup_input, "")
     |> assign(:user, nil)
     |> assign(:test_payload, nil)
     |> assign(:result, nil)
     |> assign(:error, nil)}
  end

  def handle_event("sfa_derived_pubkey", %{"address" => address}, socket) do
    expected = socket.assigns.user && socket.assigns.user.wallet_address

    {:noreply,
     socket
     |> assign(:result, build_result(address, expected))
     |> assign(:error, nil)}
  end

  def handle_event("sfa_derived_pubkey", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:result, nil)
     |> assign(:error, "SFA error: #{error}")}
  end

  defp run_lookup(socket, input) do
    case find_user(input) do
      {:ok, user} ->
        case build_test_payload(user) do
          {:ok, payload} ->
            socket
            |> assign(:lookup_input, input)
            |> assign(:user, user)
            |> assign(:test_payload, payload)
            |> assign(:result, nil)
            |> assign(:error, nil)

          {:error, reason} ->
            socket
            |> assign(:lookup_input, input)
            |> assign(:user, user)
            |> assign(:test_payload, nil)
            |> assign(:result, nil)
            |> assign(:error, reason)
        end

      {:error, :not_found} ->
        socket
        |> assign(:lookup_input, input)
        |> assign(:user, nil)
        |> assign(:test_payload, nil)
        |> assign(:result, nil)
        |> assign(:error, "No user found for: #{inspect(input)}")
    end
  end

  @doc """
  Look up a user by id (numeric string) or by email. Public for testability.
  """
  def find_user(input) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      trimmed == "" ->
        {:error, :not_found}

      String.contains?(trimmed, "@") ->
        case Accounts.get_user_by_email(trimmed) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      true ->
        case Integer.parse(trimmed) do
          {id, ""} ->
            case Accounts.get_user(id) do
              nil -> {:error, :not_found}
              user -> {:ok, user}
            end

          _ ->
            {:error, :not_found}
        end
    end
  end

  def find_user(_), do: {:error, :not_found}

  @doc """
  Build the JWT + verifier config payload to hand to the SFA hook. Mirrors
  the JWT shape `BlocksterV2Web.AuthController.refresh_web3auth_jwt/2`
  produces in production, so SFA derives the same Solana pubkey production
  would for the same user (which is the whole point of the parity test).

  Public for testability.
  """
  def build_test_payload(%{auth_method: "web3auth_email", email: email})
      when is_binary(email) and email != "" do
    normalized = String.downcase(String.trim(email))

    claims = %{
      "sub" => normalized,
      "email" => normalized,
      "email_verified" => true
    }

    id_token = Web3AuthSigning.sign_id_token(claims)

    {:ok,
     %{
       id_token: id_token,
       verifier: "blockster-email",
       verifier_id: normalized
     }}
  end

  def build_test_payload(%{auth_method: "web3auth_telegram", telegram_user_id: tg_id} = user)
      when is_binary(tg_id) and tg_id != "" do
    claims = %{
      "sub" => tg_id,
      "telegram_user_id" => tg_id,
      "telegram_username" => Map.get(user, :telegram_username)
    }

    id_token = Web3AuthSigning.sign_id_token(claims)

    {:ok,
     %{
       id_token: id_token,
       verifier: "blockster-telegram",
       verifier_id: tg_id
     }}
  end

  def build_test_payload(%{auth_method: method}) do
    {:error,
     "User auth_method=#{inspect(method)} not supported. Only web3auth_email and " <>
       "web3auth_telegram can be JWT-minted server-side. OAuth users (X / Google / " <>
       "Apple) would need a captured live JWT — not yet supported here."}
  end

  def build_test_payload(_), do: {:error, "Invalid user"}

  @doc """
  Compute the parity-result struct for a derived address vs the user's
  expected wallet_address. Public for testability.
  """
  def build_result(address, expected) when is_binary(address) do
    %{
      address: address,
      expected: expected,
      match: is_binary(expected) and address == expected
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <BlocksterV2Web.DesignSystem.header current_user={@current_user} />
    <div class="max-w-3xl mx-auto py-8 px-4 pt-28">
      <h1 class="text-2xl font-haas_medium_65 mb-2">Web3Auth SFA Parity Test</h1>
      <p class="text-sm text-gray-600 mb-6">
        Phase 0 of the SFA mobile migration. Pick an existing Web3Auth-signed-in user
        (email or Telegram) and verify the SFA-derived Solana pubkey matches the
        pubkey stored on their account. Match means SFA can replace modal on mobile
        without breaking wallet bindings. Mismatch means a cutover is required (legacy
        reclaim handles it). See <code class="bg-gray-100 px-1 py-0.5 rounded">docs/web3auth_sfa_migration.md</code>.
      </p>

      <form phx-submit="lookup_user" class="flex gap-2 mb-6">
        <input
          type="text"
          name="lookup_input"
          value={@lookup_input}
          placeholder="user id or email"
          class="flex-1 border border-gray-300 rounded-lg px-3 py-2 font-haas_roman_55"
          autocomplete="off"
        />
        <button
          type="submit"
          class="bg-gray-900 text-white rounded-lg px-4 py-2 font-haas_medium_65 cursor-pointer"
        >
          Lookup
        </button>
        <%= if @user do %>
          <button
            type="button"
            phx-click="clear"
            class="bg-gray-100 text-gray-900 rounded-lg px-4 py-2 font-haas_medium_65 cursor-pointer"
          >
            Clear
          </button>
        <% end %>
      </form>

      <%= if @error and is_nil(@user) do %>
        <div class="bg-red-50 border border-red-200 text-red-800 rounded-lg p-4 mb-6">
          {@error}
        </div>
      <% end %>

      <%= if @user do %>
        <div class="border border-gray-200 rounded-lg p-4 mb-6">
          <h2 class="text-lg font-haas_medium_65 mb-3">User</h2>
          <dl class="grid grid-cols-[140px_1fr] gap-y-1 text-sm">
            <dt class="text-gray-500">id</dt>
            <dd>{@user.id}</dd>
            <dt class="text-gray-500">email</dt>
            <dd>{@user.email || "—"}</dd>
            <dt class="text-gray-500">auth_method</dt>
            <dd><code class="bg-gray-100 px-1 py-0.5 rounded">{@user.auth_method}</code></dd>
            <dt class="text-gray-500">wallet_address</dt>
            <dd>
              <code class="bg-gray-100 px-1 py-0.5 rounded text-xs">{@user.wallet_address}</code>
            </dd>
            <%= if @user.telegram_user_id do %>
              <dt class="text-gray-500">telegram_user_id</dt>
              <dd>{@user.telegram_user_id}</dd>
            <% end %>
          </dl>
        </div>
      <% end %>

      <%= if @user and @error do %>
        <div class="bg-red-50 border border-red-200 text-red-800 rounded-lg p-4 mb-6">
          {@error}
        </div>
      <% end %>

      <%= if @test_payload do %>
        <div class="border border-gray-200 rounded-lg p-4 mb-6">
          <h2 class="text-lg font-haas_medium_65 mb-3">SFA Test</h2>
          <p class="text-sm text-gray-600 mb-3">
            Verifier <code class="bg-gray-100 px-1 py-0.5 rounded">{@test_payload.verifier}</code>
            · sub <code class="bg-gray-100 px-1 py-0.5 rounded">{@test_payload.verifier_id}</code>
            · network
            <code class="bg-gray-100 px-1 py-0.5 rounded">{@web3auth_config[:network] || "—"}</code>
          </p>
          <%= if @web3auth_config[:client_id] in [nil, ""] do %>
            <div class="bg-yellow-50 border border-yellow-200 text-yellow-900 rounded-lg p-3 text-sm">
              WEB3AUTH_CLIENT_ID is not configured (SOCIAL_LOGIN_ENABLED off, or env var
              missing). SFA test cannot run. Set the secret and reload.
            </div>
          <% else %>
            <div
              id="sfa-test-hook"
              phx-hook="Web3AuthSfaTest"
              data-id-token={@test_payload.id_token}
              data-verifier={@test_payload.verifier}
              data-verifier-id={@test_payload.verifier_id}
              data-client-id={@web3auth_config[:client_id]}
              data-network={@web3auth_config[:network]}
            >
            </div>
            <%= if @result do %>
              <div class={[
                "rounded-lg p-4 mt-3",
                if(@result.match,
                  do: "bg-green-50 border border-green-200 text-green-900",
                  else: "bg-red-50 border border-red-200 text-red-900"
                )
              ]}>
                <p class="font-haas_medium_65 mb-2">
                  {if @result.match, do: "MATCH", else: "MISMATCH"}
                </p>
                <dl class="grid grid-cols-[100px_1fr] gap-y-1 text-sm">
                  <dt class="text-gray-700">expected</dt>
                  <dd>
                    <code class="bg-white px-1 py-0.5 rounded text-xs">
                      {@result.expected || "—"}
                    </code>
                  </dd>
                  <dt class="text-gray-700">derived</dt>
                  <dd>
                    <code class="bg-white px-1 py-0.5 rounded text-xs">{@result.address}</code>
                  </dd>
                </dl>
              </div>
            <% else %>
              <p class="text-sm text-gray-500 mt-3">
                Running SFA derivation…
              </p>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
