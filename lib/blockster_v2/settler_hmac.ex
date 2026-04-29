defmodule BlocksterV2.SettlerHmac do
  @moduledoc """
  HMAC-SHA256 auth header builder for settler API requests.

  The settler service uses an HMAC middleware
  (`contracts/blockster-settler/src/middleware/hmac-auth.ts`) that expects:

    * `x-timestamp` — unix seconds (must be within 5-minute window)
    * `x-signature` — `hex(hmac_sha256(secret, "<timestamp>.<body>"))`

  where `<body>` is whatever the settler sees as `JSON.stringify(req.body)`
  AFTER `express.json()` middleware has run. In practice:

    * POST application/json with a body  →  the parsed JSON re-serialized
    * GET / no body / no Content-Type    →  `"{}"` (express.json default)

  This replaces the legacy `Authorization: Bearer ...` pattern used to
  authenticate against the EVM `bux-minter.fly.dev`. All Solana-era
  main-app → settler HTTP calls must use these headers, otherwise the
  settler responds 401 "Missing authentication headers" and the call
  silently fails. Discovered in production when the email-reclaim
  legacy-BUX mint never landed on-chain — the settler call was 401'ing
  but the caller swallowed the error.

  ## Usage

      # POST: hash over the body string we send.
      body = Jason.encode!(%{wallet_address: w, amount: 100})
      headers = SettlerHmac.headers(body, secret)
      # → [{"Content-Type", "application/json"}, {"x-timestamp", ...},
      #    {"x-signature", ...}]

      # GET (no body): hash over "{}" so we match the settler's view of
      # `req.body` after express.json's empty-body default.
      headers = SettlerHmac.headers("{}", secret)
  """

  @doc """
  Returns the auth headers for a settler request whose `body_str` will be
  what the settler sees as `JSON.stringify(req.body)` after parsing.
  """
  def headers(body_str, secret)
      when is_binary(body_str) and is_binary(secret) and secret != "" do
    timestamp = System.system_time(:second) |> Integer.to_string()
    payload = "#{timestamp}.#{body_str}"

    signature =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    [
      {"Content-Type", "application/json"},
      {"x-timestamp", timestamp},
      {"x-signature", signature}
    ]
  end

  def headers(body_str, _) when is_binary(body_str) do
    # No secret configured — main app is in dev mode talking to a settler
    # in dev mode that bypasses HMAC. Returning Content-Type only is enough
    # for that path; in prod the secret is always set.
    [{"Content-Type", "application/json"}]
  end
end
