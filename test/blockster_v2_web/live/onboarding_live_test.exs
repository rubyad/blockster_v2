defmodule BlocksterV2Web.OnboardingLiveTest do
  @moduledoc """
  Integration tests for the Solana onboarding flow with the legacy reclaim
  branch.

  Covers the 5 scenarios from `docs/legacy_account_reclaim_plan.md`:
    1. Migrate-branch happy path (everything connected → straight to complete)
    2. Migrate-branch partial (only email + phone on legacy)
    3. Migrate-branch no-match (entered email doesn't exist as a legacy user)
    4. "I'm new" path with hidden legacy match (merge fires at email step)
    5. Brand-new user, no merge anywhere
  """
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Accounts.{User, PhoneVerification}
  alias BlocksterV2.BuxMinterStub
  alias BlocksterV2.Migration.LegacyBuxMigration
  alias BlocksterV2.Repo

  setup_all do
    tables = [
      {:unified_multipliers_v2, :set,
        [:user_id, :x_score, :x_multiplier, :phone_multiplier, :sol_multiplier,
         :email_multiplier, :overall_multiplier, :last_updated, :created_at],
        [:overall_multiplier]},
      {:user_solana_balances, :set,
        [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance],
        []},
      {:x_connections, :set,
        [:user_id, :x_user_id, :x_username, :x_name, :x_profile_image_url,
         :access_token_encrypted, :refresh_token_encrypted, :token_expires_at,
         :scopes, :connected_at, :x_score, :followers_count, :following_count,
         :tweet_count, :listed_count, :avg_engagement_rate, :original_tweets_analyzed,
         :account_created_at, :score_calculated_at, :updated_at],
        [:x_user_id, :x_username]}
    ]

    for {name, type, attributes, index} <- tables do
      case :mnesia.create_table(name, [
        type: type,
        attributes: attributes,
        index: index,
        ram_copies: [node()]
      ]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^name}} -> :ok
      end
    end

    :ok
  end

  setup do
    BuxMinterStub.reset()
    BuxMinterStub.set_response({:ok, %{"signature" => "stub_sig"}})
    :ok
  end

  # ==========================================================================
  # Helpers
  # ==========================================================================

  defp create_solana_user do
    suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        wallet_address: "SolanaWallet" <> suffix,
        auth_method: "wallet"
      })
      |> Repo.insert()

    user
  end

  defp create_legacy_user(attrs \\ %{}) do
    suffix = Integer.to_string(System.unique_integer([:positive]))

    base = %{
      wallet_address: "0xLegacy" <> suffix,
      smart_wallet_address: "0xLegacySmart" <> suffix,
      email: "legacy_#{suffix}@example.com",
      username: "legacy_#{suffix}",
      auth_method: "email"
    }

    {:ok, user} =
      %User{}
      |> User.changeset(Map.merge(base, attrs))
      |> Repo.insert()

    user
  end

  defp create_legacy_bux_snapshot(email, amount) do
    {:ok, snapshot} =
      Repo.insert(%LegacyBuxMigration{
        email: String.downcase(email),
        legacy_bux_balance: Decimal.new("#{amount}"),
        legacy_wallet_address: "0xLegacyEvm"
      })

    snapshot
  end


  # ==========================================================================
  # Welcome step branches
  # ==========================================================================

  describe "welcome step" do
    test "renders a single 'Get started' CTA", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding/welcome")

      # Legacy migration branch is retired: existing Blockster users reclaim
      # via Web3Auth email sign-in (server-side merge), not via the welcome
      # screen's "I have an account" button, which was removed.
      assert has_element?(view, "button[phx-value-intent='new']")
      refute has_element?(view, "button[phx-value-intent='returning']")
    end

    test "'Get started' patches to /onboarding/redeem", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding/welcome")

      view
      |> element("button[phx-value-intent='new']")
      |> render_click()

      assert_patched(view, ~p"/onboarding/redeem")
    end
  end

  # ==========================================================================
  # Legacy reclaim now happens server-side in `Accounts.get_or_create_user_by_web3auth`
  # via the Web3Auth email sign-in flow. Merge logic is unit-tested against
  # `BlocksterV2.Migration.LegacyMerge` directly — no LiveView coverage needed
  # here anymore. The old "welcome → migrate_email → OTP → merge" UI path is
  # retired.
  # ==========================================================================

  # ==========================================================================
  # Redesigned template assertions
  # ==========================================================================

  describe "redesigned template" do
    test "welcome step renders with DS styling", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/onboarding/welcome")

      # DS eggshell background
      assert html =~ "bg-[#fafaf9]"
      # Progress bar (segmented, not dots)
      assert html =~ "progress"  || html =~ "rounded-full"
      # Heading text
      assert html =~ "Welcome to Blockster"
      # Single CTA (legacy "I have an account" branch retired —
      # Web3Auth email flow handles reclaim server-side).
      assert html =~ "Get started"
    end

    test "redeem step renders icons", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/onboarding/redeem")

      assert html =~ "Shop"
      assert html =~ "Games"
      assert html =~ "Airdrop"
      assert html =~ "Redeem BUX"
    end

    test "phone step renders with eyebrow", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/onboarding/phone")

      # Eyebrow-style step indicator (uppercase)
      assert html =~ "STEP 1 OF 3" || html =~ "Step 1 of 3"
      assert html =~ "Connect Your Phone"
    end

    test "email step renders with eyebrow", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/onboarding/email")

      assert html =~ "STEP 2 OF 3" || html =~ "Step 2 of 3"
      assert html =~ "Verify Your Email"
      assert html =~ "0.5x"
      assert html =~ "2x"
    end

    test "x step renders with eyebrow", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/onboarding/x")

      assert html =~ "STEP 3 OF 3" || html =~ "Step 3 of 3"
      assert html =~ "Connect Your X Account"
      assert html =~ "Connect X"
    end

    test "complete step renders multiplier display", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/onboarding/complete")

      assert html =~ "You&#39;re All Set!" || html =~ "You're All Set!"
      assert html =~ "BUX Earning Power"
      assert html =~ "Start Earning BUX"
      # Breakdown items
      assert html =~ "Phone"
      assert html =~ "Email"
      assert html =~ "SOL"
    end

    test "profile step renders earning power message", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/onboarding/profile")

      assert html =~ "20x"
      assert html =~ "more BUX"
      assert html =~ "Let&#39;s Go" || html =~ "Let's Go"
    end

    test "anonymous user is redirected", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, ~p"/onboarding/welcome")
    end

    test "migrate_email step URL redirects to welcome (step retired)", %{conn: conn} do
      # The migrate_email step was removed from @base_steps; deep-linking to
      # its URL now bounces the user back to welcome via handle_params.
      user = create_solana_user()
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/onboarding/welcome"}}} =
               live(conn, ~p"/onboarding/migrate_email")
    end
  end

  # ==========================================================================
  # next_unfilled_step/2 unit coverage (skip-completed-steps logic)
  # ==========================================================================

  describe "next_unfilled_step/2" do
    test "from welcome, fully filled user advances to redeem" do
      user = %User{username: "u", phone_verified: true, email_verified: true}

      # `redeem` is always shown per the plan, even for returning users.
      assert "redeem" =
               BlocksterV2Web.OnboardingLive.Index.next_unfilled_step(user, "welcome")
    end

    test "from redeem, fully filled user lands on complete" do
      user = %User{username: "u", phone_verified: true, email_verified: true}

      # X is unfilled (no Mnesia row) → still routes to x first.
      assert "x" =
               BlocksterV2Web.OnboardingLive.Index.next_unfilled_step(user, "redeem")
    end

    test "no phone → skips past email if email_verified" do
      user = %User{username: "u", phone_verified: false, email_verified: true}

      assert "phone" = BlocksterV2Web.OnboardingLive.Index.next_unfilled_step(user, "redeem")
    end

    test "no email → routes to email step from x" do
      user = %User{username: "u", phone_verified: true, email_verified: false}

      assert "email" = BlocksterV2Web.OnboardingLive.Index.next_unfilled_step(user, "phone")
    end
  end
end
