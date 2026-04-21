# THROWAWAY — Phase 0 Web3Auth prototype. Delete once Phase 5 ships.
defmodule BlocksterV2Web.TestWeb3AuthLive do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    client_id = clean_env("WEB3AUTH_CLIENT_ID")

    # Prototype fallback — project QuickNode devnet RPC (same as settler).
    # Production code reads SOLANA_RPC_URL from env; this test page shouldn't
    # block on that being set.
    rpc_url =
      case clean_env("SOLANA_RPC_URL") do
        "" ->
          "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/"

        url ->
          url
      end

    # Generate a per-load ephemeral "settler" keypair the browser will use to
    # partial-sign two-signer test transactions. We hand the secret to the JS
    # hook via data attributes — this is only safe because the route is
    # dev-only and the keypair is disposable.
    {settler_pubkey, settler_secret_b58} = generate_settler_keypair()

    {:ok,
     assign(socket,
       client_id: client_id,
       rpc_url: rpc_url,
       settler_pubkey: settler_pubkey,
       settler_secret_b58: settler_secret_b58,
       telegram_verifier_id: clean_env("WEB3AUTH_TELEGRAM_VERIFIER_ID")
     )}
  end

  # Defensive: .env parsing in config/runtime.exs sometimes leaves residual
  # quotes or whitespace when the file was saved with trailing padding or
  # pasted from a source that wrapped the value. Strip both.
  defp clean_env(key) do
    (System.get_env(key) || "")
    |> String.trim()
    |> String.trim("\"")
    |> String.trim("'")
    |> String.trim()
  end

  defp generate_settler_keypair do
    seed = :crypto.strong_rand_bytes(32)
    {pubkey, _priv} = :crypto.generate_key(:eddsa, :ed25519, seed)
    full_secret = seed <> pubkey
    {Base58.encode(pubkey), Base58.encode(full_secret)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-8 font-mono">
      <h1 class="text-2xl font-bold mb-2">Web3Auth devnet prototype</h1>
      <p class="text-sm text-gray-500 mb-6">
        Throwaway test page for Phase 0. Verifies email / Google / Apple / X / Telegram-JWT
        produce a Solana pubkey and can sign two-signer devnet transactions.
      </p>

      <%= if @client_id == "" do %>
        <div class="mb-6 p-4 border border-red-300 bg-red-50 rounded text-sm">
          <strong>Missing <code>WEB3AUTH_CLIENT_ID</code>.</strong>
          Create a project at
          <a href="https://dashboard.web3auth.io/" class="underline" target="_blank" rel="noopener">
            dashboard.web3auth.io
          </a>
          (Sapphire Devnet, Solana chain), paste the client ID into <code>.env</code>, then restart
          <code>bin/dev</code>.
        </div>
      <% end %>

      <div
        id="test-web3auth-root"
        phx-hook="TestWeb3Auth"
        data-client-id={@client_id}
        data-rpc-url={@rpc_url}
        data-settler-pubkey={@settler_pubkey}
        data-settler-secret={@settler_secret_b58}
        data-telegram-verifier-id={@telegram_verifier_id}
      >
        <div class="mb-4 text-sm">
          <div>settler pubkey (fund this with ~0.01 SOL on devnet): <code class="bg-gray-100 px-1 rounded">{@settler_pubkey}</code></div>
          <div id="tw-status" class="mt-2 text-gray-700">(disconnected)</div>
        </div>

        <div class="flex flex-wrap items-center gap-2 mb-4">
          <input
            id="tw-email-input"
            type="email"
            placeholder="you@example.com"
            autocomplete="email"
            class="px-3 py-2 border border-gray-300 rounded text-sm w-64"
          />
          <button type="button" class="px-3 py-2 bg-gray-900 text-white rounded cursor-pointer" data-provider="email">
            Continue with Email
          </button>
          <button type="button" class="px-3 py-2 bg-gray-900 text-white rounded cursor-pointer" data-provider="google">
            Google
          </button>
          <button type="button" class="px-3 py-2 bg-gray-900 text-white rounded cursor-pointer" data-provider="apple">
            Apple
          </button>
          <button type="button" class="px-3 py-2 bg-gray-900 text-white rounded cursor-pointer" data-provider="twitter">
            X (Twitter)
          </button>
          <button type="button" class="px-3 py-2 bg-gray-900 text-white rounded cursor-pointer" data-provider="telegram">
            Telegram (JWT)
          </button>
        </div>

        <div class="flex flex-wrap gap-2 mb-6">
          <button id="tw-sign-message" type="button" class="tw-action px-3 py-2 bg-gray-100 text-gray-900 rounded cursor-pointer disabled:opacity-40" disabled>
            Sign message
          </button>
          <button id="tw-self-transfer" type="button" class="tw-action px-3 py-2 bg-gray-100 text-gray-900 rounded cursor-pointer disabled:opacity-40" disabled>
            Self-transfer 1 lamport
          </button>
          <button id="tw-two-signer" type="button" class="tw-action px-3 py-2 bg-gray-100 text-gray-900 rounded cursor-pointer disabled:opacity-40" disabled>
            Two-signer tx (settler as fee payer)
          </button>
          <button id="tw-logout" type="button" class="tw-action px-3 py-2 bg-gray-100 text-gray-900 rounded cursor-pointer disabled:opacity-40" disabled>
            Log out
          </button>
        </div>

        <div id="tw-log" class="p-3 bg-gray-50 border border-gray-200 rounded text-xs h-80 overflow-auto"></div>
      </div>
    </div>
    """
  end
end
