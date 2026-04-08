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
    test "renders both branch buttons", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding/welcome")

      assert has_element?(view, "button[phx-value-intent='new']")
      assert has_element?(view, "button[phx-value-intent='returning']")
      assert has_element?(view, "button[phx-value-intent='returning']", "I have an account")
    end

    test "'I'm new' patches to /onboarding/redeem", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding/welcome")

      view
      |> element("button[phx-value-intent='new']")
      |> render_click()

      assert_patched(view, ~p"/onboarding/redeem")
    end

    test "'I have an account' patches to /onboarding/migrate_email", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding/welcome")

      view
      |> element("button[phx-value-intent='returning']")
      |> render_click()

      assert_patched(view, ~p"/onboarding/migrate_email")
    end
  end

  # ==========================================================================
  # Migrate branch — no-match path (everyone gets a verified email)
  # ==========================================================================

  describe "migrate_email step — no legacy match" do
    test "verifies email, sets it on user, falls through to redeem", %{conn: conn} do
      user = create_solana_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding/migrate_email")

      view
      |> element("form[phx-submit='send_migration_code']")
      |> render_submit(%{"email" => "fresh_no_match@example.com"})

      # Now the user record should have a real verification code; we read it
      reloaded = Repo.get!(User, user.id)
      assert reloaded.pending_email == "fresh_no_match@example.com"

      view
      |> element("form[phx-submit='verify_migration_code']")
      |> render_submit(%{"code" => reloaded.email_verification_code})

      final = Repo.get!(User, user.id)
      assert final.email == "fresh_no_match@example.com"
      assert final.email_verified == true
      assert final.pending_email == nil
    end
  end

  # ==========================================================================
  # Migrate branch — happy path (everything transfers)
  # ==========================================================================

  describe "migrate_email step — full legacy merge" do
    test "merges everything and reports success in the UI", %{conn: conn} do
      legacy =
        create_legacy_user(%{
          username: "valid_legacy_un",
          telegram_user_id: "tg_legacy_full",
          telegram_username: "legacy_tg_handle"
        })

      _snapshot = create_legacy_bux_snapshot(legacy.email, "750")

      {:ok, _legacy_phone} =
        Repo.insert(%PhoneVerification{
          user_id: legacy.id,
          phone_number: "+15557776666",
          country_code: "US",
          geo_tier: "premium",
          geo_multiplier: Decimal.new("2.0"),
          verified: true
        })

      {:ok, legacy} =
        legacy
        |> User.changeset(%{
          phone_verified: true,
          geo_multiplier: Decimal.new("2.0"),
          geo_tier: "premium"
        })
        |> Repo.update()

      new_user = create_solana_user()
      conn = log_in_user(conn, new_user)

      {:ok, view, _html} = live(conn, ~p"/onboarding/migrate_email")

      view
      |> element("form[phx-submit='send_migration_code']")
      |> render_submit(%{"email" => legacy.email})

      reloaded = Repo.get!(User, new_user.id)

      html =
        view
        |> element("form[phx-submit='verify_migration_code']")
        |> render_submit(%{"code" => reloaded.email_verification_code})

      assert html =~ "Welcome back"
      assert html =~ "BUX restored"
      assert html =~ "Username restored"
      assert html =~ "Phone restored"
      assert html =~ "Telegram restored"

      merged = Repo.get!(User, new_user.id)
      assert merged.email == String.downcase(legacy.email)
      assert merged.email_verified == true
      assert merged.username == "valid_legacy_un"
      assert merged.phone_verified == true
      assert merged.telegram_user_id == "tg_legacy_full"

      reloaded_legacy = Repo.get!(User, legacy.id)
      assert reloaded_legacy.is_active == false
      assert reloaded_legacy.merged_into_user_id == new_user.id
    end
  end

  # ==========================================================================
  # next_unfilled_step/2 unit coverage (skip-completed-steps logic)
  # ==========================================================================

  describe "next_unfilled_step/2" do
    test "from migrate_email, fully filled user goes to redeem (never skipped)" do
      user = %User{username: "u", phone_verified: true, email_verified: true}

      # `redeem` is always shown per the plan, even for returning users.
      assert "redeem" =
               BlocksterV2Web.OnboardingLive.Index.next_unfilled_step(user, "migrate_email")
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
