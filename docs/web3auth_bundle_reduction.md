# Web3Auth Bundle Reduction Plan

**Source:** investigation 2026-04-28, follow-up to `docs/performance_audit_2026_04_24.md` §2.

**Baseline (from audit):** `app.js` ships **1.91 MB gzipped** / **6.86 MB uncompressed**. Web3Auth + transitive deps (React 19, react-dom, react-i18next, i18next, MPC-core-kit) dominate. Console emits "Download the React DevTools…" and "i18next is made possible by our own product, Locize" on every page load — both libraries are bundled but unused by Blockster's UI.

**Key insight:** Blockster has its **own custom sign-in UI** (`login_live.ex` — email/code state machine + wallet selector). Web3Auth is invoked non-modally via `connectTo(WALLET_ADAPTERS.AUTH, { loginProvider, ... })` — the modal UI is never displayed. `@web3auth/modal` is currently bundled only to provide the `WALLET_CONNECTORS` enum and network config.

**Current import pattern:** `assets/js/hooks/web3auth_hook.js` already lazy-loads the SDK via `_ensureSdk()` (dynamic `import("@web3auth/modal")` on first login attempt), but esbuild bundles all transitive deps into the main `app.js` regardless — dynamic imports only delay execution, they don't tree-shake transitive package contents that are reachable from any code path.

---

## Recommendations (prioritized)

### #1 — Swap `@web3auth/modal` → `@web3auth/no-modal`

- **What:** Replace `@web3auth/modal` with `@web3auth/no-modal` in `assets/package.json`. Update imports in `assets/js/hooks/web3auth_hook.js`. The `no-modal` package is the signing provider underneath the modal — same auth flow, no React-based modal UI.
- **Verify:** Confirm `WALLET_CONNECTORS` enum + network config are exported from `no-modal` (or pull them from `@web3auth/auth` / `@web3auth/base`).
- **Save:** ~300 KB gzipped (drops the React-based modal UI tree).
- **Effort:** 2-3 hours.
- **Risk:** Medium. Test all five sign-in paths: email OTP (Custom JWT), Telegram (Custom JWT), Google/Apple/X (popup OAuth). Verify `provider.request({method: "solana_privateKey"})` still works for signing across all paths.
- **Files touched:** `assets/package.json`, `assets/js/hooks/web3auth_hook.js`, possibly `assets/js/app.js`.

### #2 — Externalize React + react-dom via esbuild config

- **What:** Add `--external:react`, `--external:react-dom`, `--external:react-i18next` to esbuild build args in `mix.exs` or `config/config.exs` (wherever esbuild is configured).
- **Pre-condition:** Confirm no Blockster JS imports React. `grep -rn "from .react.\|from .react-dom." assets/js/ | grep -v node_modules` should be empty. (Agent already spot-checked: pass.)
- **Save:** ~400-500 KB gzipped.
- **Effort:** 1 hour.
- **Risk:** Medium. If `@web3auth/no-modal` (or whatever the post-#1 dep is) depends on React being present at runtime, externalizing will break sign-in. Build will emit a runtime error instead of silently failing — easy to catch.
- **Combine with #1:** If #1 is done first and `@web3auth/no-modal` is React-free, #2 becomes trivial. If #1 is skipped, this fights against `@web3auth/modal`'s React dependency and may not be feasible.

### #3 — Externalize i18next + react-i18next

- **What:** Add `--external:i18next`, `--external:react-i18next` to esbuild build args. Same mechanism as #2.
- **Pre-condition:** Verify Web3Auth's wallet-selector UI either isn't displayed (post-#1) or can be configured to skip locale bundling.
- **Save:** ~150-200 KB gzipped.
- **Effort:** 1 hour.
- **Risk:** Low. Test wallet sign-in flows end-to-end after the change.
- **Combine with #1+#2:** All three together would clean ~700-900 KB gzipped from the bundle.

---

## Combined impact

| | Saves (gz) | Cumulative (gz) | Effort |
|---|---:|---:|---|
| Baseline | — | 1.91 MB | — |
| After #1 | ~300 KB | ~1.61 MB | 2-3 h |
| After #1+#2 | ~700-800 KB | ~1.15-1.25 MB | 3-4 h |
| After #1+#2+#3 | ~850-1000 KB | ~0.95-1.05 MB | 4-5 h |

Realistic: cut the bundle roughly in half (~50 % reduction) across the three changes.

---

## Test plan (do once, run after each change)

1. Email sign-in (new account) — Custom JWT path, in-app OTP.
2. Email sign-in (returning, legacy reclaim) — `LegacyMerge.merge_legacy_into!` should still fire.
3. Telegram sign-in via widget — Custom JWT path, verifier `blockster-telegram`.
4. Google OAuth sign-in — popup path, MPC re-derives same pubkey.
5. Apple OAuth sign-in — same as Google.
6. X OAuth sign-in — same as Google.
7. Wallet Standard (Phantom/Solflare/Backpack) — non-Web3Auth path, must still work.
8. Returning Web3Auth user reconnect (silent) — `_silentReconnect` in `web3auth_hook.js`.
9. Returning OAuth user with dead session — Reconnect pill should appear (NOT a modal).
10. Sign + send a real Solana transaction (Coin Flip bet on `/play`) — verifies signing flow end-to-end.

For each: signed-in cleanly, balance loads, can sign a SOL transfer.

---

## Out of scope

- **TipTap lazy-load** — explicitly excluded by user.
- **Stale `app-21f441de…js` deletion** — already done (file gone from disk as of 2026-04-28).
- **Deeper Web3Auth alternatives** (e.g., dropping Web3Auth entirely for direct MPC integration). Not in scope; would require rebuilding social login from scratch.
