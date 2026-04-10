# Test baseline · existing-pages redesign release

> Captured at the start of Wave 0 (2026-04-09) so the redesign release can
> follow the rule "no NEW failures relative to the inherited baseline"
> instead of "zero failures across the entire suite," which is impossible
> on this branch right now.

## Why this exists

`feat/solana-migration` already has a meaningful number of pre-existing test
failures before any redesign work began. A clean run of `mix test` produces
between **~100 and ~165 failures** depending on the random seed (most are
flaky / order-dependent). They cluster around:

- The Airdrop suite (settler/balance seeding)
- Bot system tests (Solana wallet rotation)
- Legacy merge tests (settler dependencies)
- Several Shop phase tests (Mnesia setup)
- Onboarding LiveView tests (state propagation)
- Email + phone verification tests (Mnesia setup)
- Pool LiveView tests (settler RPC mocking)

None of these are caused by the redesign. They're environment / fixture
problems that the user has acknowledged ("Existing tests that break due to
DOM changes — fix as encountered. Don't pre-fix." per the redesign release
plan).

## The rule

For every per-page checkpoint and the cutover deploy, the gate is:

> **No NEW test files in the failure set relative to this baseline.**

If a `mix test` run produces failures in a file NOT in the list below, that's
a regression I need to investigate and fix before continuing. If the failures
are all in files already in the baseline, that's the inherited noise floor
and the checkpoint is green.

## Baseline files

Captured by running `mix test` 3 times and unioning the failing test files.
Last refresh: **2026-04-09**, end of Wave 0.

```
test/blockster_v2/accounts/fingerprint_auth_test.exs
test/blockster_v2/airdrop/airdrop_integration_test.exs
test/blockster_v2/airdrop/airdrop_provably_fair_test.exs
test/blockster_v2/airdrop/airdrop_test.exs
test/blockster_v2/blog_test.exs
test/blockster_v2/bot_system/bot_coordinator_test.exs
test/blockster_v2/coin_flip_game_test.exs
test/blockster_v2/content_automation/content_generator_on_demand_test.exs
test/blockster_v2/content_automation/content_generator_prompts_test.exs
test/blockster_v2/content_automation/content_publisher_test.exs
test/blockster_v2/content_automation/x_profile_fetcher_test.exs
test/blockster_v2/lp_balances_test.exs
test/blockster_v2/notifications/daily_digest_test.exs
test/blockster_v2/notifications/event_processor_formulas_test.exs
test/blockster_v2/notifications/formula_evaluator_test.exs
test/blockster_v2/notifications/phase1_test.exs
test/blockster_v2/notifications/phase8_test.exs
test/blockster_v2/notifications/phase11_test.exs
test/blockster_v2/notifications/phase12_test.exs
test/blockster_v2/notifications/phase13_test.exs
test/blockster_v2/notifications/telegram_group_join_test.exs
test/blockster_v2/performance_fixes_test.exs
test/blockster_v2/shop/phase2_test.exs
test/blockster_v2/shop/phase5_test.exs
test/blockster_v2/shop/phase6_test.exs
test/blockster_v2/shop/phase7_test.exs
test/blockster_v2/shop/phase8_test.exs
test/blockster_v2/shop/phase9_test.exs
test/blockster_v2/shop/phase10_test.exs
test/blockster_v2/solana_balances_test.exs
test/blockster_v2/telegram_bot/hourly_promo_scheduler_test.exs
test/blockster_v2_web/controllers/telegram_webhook_controller_test.exs
test/blockster_v2_web/live/airdrop_live_test.exs
test/blockster_v2_web/live/member_live/devices_test.exs
test/blockster_v2_web/live/onboarding_live_test.exs
test/blockster_v2_web/live/post_live/show_test.exs
test/blockster_v2_web/live/pool_detail_live_test.exs
test/blockster_v2_web/live/pool_live_test.exs
```

38 files. The set may grow when later page rebuilds touch tests in already-
listed files, but it should never grow with files OUTSIDE this list. New
file failures = real regression.

## Helper script

To check whether a fresh `mix test` run produces any failures outside the
baseline, run:

```bash
mix test 2>&1 \
  | grep -oE 'test/[a-z_/0-9]+_test\.exs' \
  | sort -u \
  | comm -23 - <(sed -n '/^```$/,/^```$/p' docs/solana/test_baseline_redesign.md | grep '^test/')
```

If the output is empty, no NEW failures. If it lists files, those are the
regressions I need to investigate.

## What's NOT covered by the baseline

- The new `test/blockster_v2_web/components/design_system/` test directory.
  Every test in there must always pass — those are mine and they have no
  baseline-noise excuse.
- Per-page LiveView test files that are extended during their wave (e.g.
  `test/blockster_v2_web/live/page_controller_test.exs` for the homepage).
  The wave's contribution to those tests must always pass, even if the file
  appears in the baseline because of unrelated flaky tests.
- Any test failure with a stack trace pointing into a redesign component
  (`lib/blockster_v2_web/components/design_system.ex`) — even if the test
  file is in the baseline, that specific failure is mine to fix.
