# Auth session contract

The minimal session-key set that every LiveView assumes, and the code
paths that populate it. One source of truth for resolving `current_user`
across SIWS, Web3Auth, and dev-login. Supports GLOBAL-01 triage — any
mismatch between these shapes is the likely cause of the admin
"must be logged in" flash.

## TL;DR

- The ONLY session key that drives authentication is `"wallet_address"`.
- Phoenix stores `put_session(:wallet_address, _)` under the BINARY key
  `"wallet_address"` regardless of whether the caller used an atom or a
  binary — so `session["wallet_address"]` always works in consumers.
- There is no `user_token` check in the current code (legacy EVM path
  was removed). Any `user_token` written by dev-login is ignored.

## Session keys by source

| Source | Writes | Notes |
|---|---|---|
| SIWS (`POST /api/auth/session`) | `"wallet_address"` | Called from the LiveView after the wallet signature verifies. See `auth_controller.ex:142`. |
| Web3Auth email / OAuth | `"wallet_address"` | Same `/api/auth/session` endpoint. The Web3Auth-derived Solana pubkey IS the user's `wallet_address` (email ownership = account ownership). See CLAUDE.md § Social Login. |
| `/dev/login-as/:id` | `"wallet_address"` + `:user_token` | Dev-only convenience controller. The extra `:user_token` is ignored by UserAuth (no consumer reads it). See `dev_login_controller.ex:34`. |
| Legacy EVM `user_token` | — | Retired. `UserAuth.mount_current_user/2` comment: "Solana wallet session is the only auth path. Legacy EVM user_token sessions are ignored." |

All three write the SAME primary key. Diverging here is the red flag —
if a dev-login helper ever writes something OTHER than
`"wallet_address"`, the admin flash bug surface returns.

## Resolution — static mount vs connected mount

`BlocksterV2Web.UserAuth.on_mount/4` (mounted in `live_session` scope
via `user_auth.ex`) runs BOTH on the initial HTTP render (static
mount, `connected?(socket) == false`) AND again on the WebSocket
upgrade (connected mount, `connected?(socket) == true`).

Resolution rules:

```elixir
defp restore_from_wallet(socket, session) do
  wallet = session["wallet_address"] || get_wallet_from_connect_params(socket)

  case wallet do
    nil -> nil
    address -> Accounts.get_user_by_wallet_address(address)
  end
end

defp get_wallet_from_connect_params(socket) do
  if connected?(socket) do
    case get_connect_params(socket) do
      %{"wallet_address" => addr} when is_binary(addr) and addr != "" -> addr
      _ -> nil
    end
  else
    nil
  end
end
```

Two lookups:

1. **Session cookie** (`session["wallet_address"]`) — always available,
   both mounts.
2. **LiveSocket connect params** (`get_connect_params(socket)["wallet_address"]`) —
   ONLY on connected mount. Comes from the browser's LocalStorage via
   `assets/js/app.js`'s `new LiveSocket("/live", ... { params: { wallet_address: … } })`.

The session cookie is the SOURCE OF TRUTH. LocalStorage is a
fallback for the edge case where the browser has a stale cookie but
still holds the wallet — typically right after a session-cookie
rotation or a cross-tab disconnect.

## The GLOBAL-01 flash scenario

"Admin clicks Dashboard → flash of 'must be logged in' → Connect
Wallet brief appearance → UI snaps back to logged-in state."

The symptom is a flicker on the STATIC mount: `current_user` is `nil`
for the first HTTP render, `AdminAuth.on_mount` sees no user and
halts with the flash + redirect, then the WebSocket upgrades, the
connected mount resolves `current_user` from connect_params, and the
flash vanishes. Net: the user sees a 50-200ms error flash even though
their session is actually fine.

Hypotheses (unconfirmed without browser repro):

1. **Session cookie not yet persisted** — SIWS just posted to
   `/api/auth/session`, the response Set-Cookie landed, but the
   browser's next navigation (push_navigate) went out a tick too
   early with the OLD cookie jar. Fix: have the LV receive a
   confirmation event from the POST's response before navigating.
2. **Cookie truly absent** — maybe the user's browser has cookies
   disabled, or the session cookie expired mid-session. Fix: the
   fallback to `connect_params["wallet_address"]` on connected mount
   already handles this for connected mount; static mount has no
   equivalent. Could stash a client-side duplicate signed token that
   the first HTTP request sends as a header, letting the static
   mount plug recover the wallet. Bigger change.
3. **AdminAuth halting too eagerly** — the flash + redirect on the
   STATIC mount happens before the websocket gets a chance. If we
   defer the "no user" halt until the connected mount has had a
   chance to run, the flash disappears for the common case. Risk:
   real unauthenticated users could briefly see the admin page
   chrome before the halt — unacceptable for admin-only pages, fine
   for soft auth gates.

## Tests that pin this contract

- `test/blockster_v2_web/live/coin_flip_live_test.exs:log_in_user/2`
  writes both `:user_token` + `"wallet_address"` — matches dev-login
  shape.
- Tests that only write `"wallet_address"` match SIWS shape and
  exercise the same UserAuth path.
- If a future test writes ONLY `:user_token`, it should fail
  UserAuth resolution — and it does, because `user_token` is ignored.

## Operational guidance

- If a user reports the admin flash bug: first check their browser's
  cookies for `_blockster_key` (the session cookie name). Confirm
  `wallet_address` is present in the session. Then check their
  LocalStorage for a `wallet_address` entry. Mismatch = cookie is
  stale; clear session or wait for re-auth.
- Don't write additional session keys (`user_token`, auth_method,
  etc.) as part of fixing flash bugs. The single-key invariant keeps
  the contract tight.
- Don't downgrade AdminAuth's eager halt without a tight feature
  flag + explicit product call.

## See also

- [docs/bug_audit_2026_04_22.md § GLOBAL-01](bug_audit_2026_04_22.md)
- [docs/web3auth_integration.md](web3auth_integration.md) §4
- `lib/blockster_v2_web/live/user_auth.ex`
- `lib/blockster_v2_web/live/admin_auth.ex`
- `lib/blockster_v2_web/controllers/auth_controller.ex`
- `lib/blockster_v2_web/controllers/dev_login_controller.ex`
