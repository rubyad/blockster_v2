defmodule BlocksterV2.Migration.LegacyMergeTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Accounts.{User, PhoneVerification, UserFingerprint}
  alias BlocksterV2.BuxMinterStub
  alias BlocksterV2.Migration.LegacyBuxMigration
  alias BlocksterV2.Migration.LegacyMerge
  alias BlocksterV2.Orders.{Order, AffiliatePayout}
  alias BlocksterV2.Repo

  setup_all do
    # Mnesia tables that downstream code (UnifiedMultiplier, EngagementTracker)
    # touches as a side effect of merge_legacy_into!.
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
    # Reset the BUX minter stub for each test.
    BuxMinterStub.reset()
    BuxMinterStub.set_response({:ok, %{"signature" => "test_signature_xyz"}})
    :ok
  end

  # ==========================================================================
  # Helpers
  # ==========================================================================

  defp create_new_user(attrs \\ %{}) do
    base = %{
      wallet_address: "SolanaWallet" <> unique_suffix(),
      auth_method: "wallet",
      pending_email: nil
    }

    attrs = Map.merge(base, attrs)

    {:ok, user} =
      %User{}
      |> User.changeset(attrs)
      |> Repo.insert()

    user
  end

  defp create_legacy_user(attrs \\ %{}) do
    base = %{
      wallet_address: "0xLegacyWallet" <> unique_suffix(),
      smart_wallet_address: "0xLegacySmart" <> unique_suffix(),
      email: "legacy_#{unique_suffix()}@example.com",
      username: "legacy_user_#{unique_suffix()}",
      auth_method: "email"
    }

    attrs = Map.merge(base, attrs)

    # `locked_x_user_id` is not in User.changeset cast list, so set it via a
    # direct change after insert.
    {locked_x, attrs} = Map.pop(attrs, :locked_x_user_id)

    {:ok, user} =
      %User{}
      |> User.changeset(attrs)
      |> Repo.insert()

    if locked_x do
      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{locked_x_user_id: locked_x})
        |> Repo.update()

      user
    else
      user
    end
  end

  defp set_pending_email(user, email) do
    {:ok, updated} =
      user
      |> User.changeset(%{pending_email: email})
      |> Repo.update()

    updated
  end

  defp create_legacy_bux_snapshot(email, amount) do
    {:ok, migration} =
      Repo.insert(%LegacyBuxMigration{
        email: String.downcase(email),
        legacy_bux_balance: Decimal.new("#{amount}"),
        legacy_wallet_address: "0xLegacyEvm" <> unique_suffix()
      })

    migration
  end

  defp unique_suffix do
    System.unique_integer([:positive]) |> Integer.to_string()
  end

  defp insert_x_connection(user_id) do
    record = {
      :x_connections,
      user_id,
      "x_user_#{user_id}",  # x_user_id
      "x_username_#{user_id}",  # x_username
      "X Name #{user_id}",  # x_name
      nil,  # x_profile_image_url
      nil,  # access_token_encrypted
      nil,  # refresh_token_encrypted
      nil,  # token_expires_at
      [],   # scopes
      System.system_time(:second),  # connected_at
      150,  # x_score
      1000, # followers_count
      500,  # following_count
      200,  # tweet_count
      0,    # listed_count
      0.05, # avg_engagement_rate
      50,   # original_tweets_analyzed
      nil,  # account_created_at
      nil,  # score_calculated_at
      System.system_time(:second)  # updated_at
    }

    :mnesia.dirty_write(record)
    :ok
  end

  # ==========================================================================
  # Tests
  # ==========================================================================

  describe "merge_legacy_into!/2 - happy path" do
    test "merges email, username, BUX, phone — everything transfers" do
      legacy = create_legacy_user(%{username: "fully_loaded_legacy"})
      _snapshot = create_legacy_bux_snapshot(legacy.email, "1000")

      # Phone on legacy
      {:ok, _legacy_phone} =
        Repo.insert(%PhoneVerification{
          user_id: legacy.id,
          phone_number: "+15551234567",
          country_code: "US",
          geo_tier: "premium",
          geo_multiplier: Decimal.new("2.0"),
          verified: true
        })

      # legacy_user.phone_verified
      {:ok, legacy} =
        legacy
        |> User.changeset(%{
          phone_verified: true,
          geo_multiplier: Decimal.new("2.0"),
          geo_tier: "premium"
        })
        |> Repo.update()

      new_user =
        create_new_user(%{
          wallet_address: "NewSolWallet" <> unique_suffix()
        })
        |> set_pending_email(legacy.email)

      assert {:ok, %{user: merged, summary: summary}} =
               LegacyMerge.merge_legacy_into!(new_user, legacy)

      assert merged.email == String.downcase(legacy.email)
      assert merged.email_verified == true
      assert merged.pending_email == nil
      assert merged.username == "fully_loaded_legacy"
      assert merged.slug != nil
      assert merged.phone_verified == true

      # Legacy is deactivated and stripped of unique fields
      reloaded_legacy = Repo.get!(User, legacy.id)
      assert reloaded_legacy.is_active == false
      assert reloaded_legacy.merged_into_user_id == new_user.id
      assert reloaded_legacy.email == nil
      assert reloaded_legacy.legacy_email == String.downcase(legacy.email)
      assert reloaded_legacy.username == "deactivated_#{legacy.id}"
      assert reloaded_legacy.smart_wallet_address == nil

      # BUX mint was called
      assert [call] = BuxMinterStub.calls()
      assert call.wallet_address == new_user.wallet_address
      assert call.amount == 1000.0
      assert call.reward_type == :legacy_migration

      # Snapshot is marked migrated
      snapshot = Repo.get_by(LegacyBuxMigration, email: String.downcase(legacy.email))
      assert snapshot.migrated == true
      assert snapshot.mint_tx_signature == "test_signature_xyz"
      assert snapshot.new_wallet_address == new_user.wallet_address

      # Phone row was transferred
      transferred_phone = Repo.get_by(PhoneVerification, phone_number: "+15551234567")
      assert transferred_phone.user_id == new_user.id

      assert summary.bux_claimed == 1000.0
      assert summary.username_transferred == true
      assert summary.phone_transferred == true
    end

    test "merges X connection (legacy has X, new doesn't)" do
      legacy = create_legacy_user(%{locked_x_user_id: "x_user_xyz"})
      insert_x_connection(legacy.id)

      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert summary.x_transferred == true

      # Mnesia row should now point at the new user
      [record] = :mnesia.dirty_read({:x_connections, new_user.id})
      assert elem(record, 1) == new_user.id

      # Legacy row should be gone
      assert :mnesia.dirty_read({:x_connections, legacy.id}) == []

      # locked_x_user_id moved
      reloaded_new = Repo.get!(User, new_user.id)
      assert reloaded_new.locked_x_user_id == "x_user_xyz"
    end

    test "drops legacy X when new user already has X" do
      legacy = create_legacy_user()
      insert_x_connection(legacy.id)

      new_user = create_new_user() |> set_pending_email(legacy.email)
      insert_x_connection(new_user.id)

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert summary.x_transferred == false

      # Both rows: legacy deleted, new preserved
      assert :mnesia.dirty_read({:x_connections, legacy.id}) == []
      assert [_] = :mnesia.dirty_read({:x_connections, new_user.id})
    end

    test "transfers Telegram when new user has none" do
      legacy =
        create_legacy_user(%{
          telegram_user_id: "tg_legacy_123",
          telegram_username: "tg_legacy_handle"
        })

      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{user: merged, summary: summary}} =
               LegacyMerge.merge_legacy_into!(new_user, legacy)

      assert summary.telegram_transferred == true
      assert merged.telegram_user_id == "tg_legacy_123"
      assert merged.telegram_username == "tg_legacy_handle"

      reloaded_legacy = Repo.get!(User, legacy.id)
      assert reloaded_legacy.telegram_user_id == nil
    end

    test "leaves new user's Telegram alone when both have one" do
      legacy =
        create_legacy_user(%{
          telegram_user_id: "tg_legacy_dup",
          telegram_username: "legacy_tg"
        })

      new_user =
        create_new_user(%{
          telegram_user_id: "tg_new_dup",
          telegram_username: "new_tg"
        })
        |> set_pending_email(legacy.email)

      assert {:ok, %{user: merged, summary: summary}} =
               LegacyMerge.merge_legacy_into!(new_user, legacy)

      assert summary.telegram_transferred == false
      assert merged.telegram_user_id == "tg_new_dup"
    end

    test "transfers phone when new user has none" do
      legacy = create_legacy_user()

      {:ok, _} =
        Repo.insert(%PhoneVerification{
          user_id: legacy.id,
          phone_number: "+15553334444",
          country_code: "US",
          geo_tier: "premium",
          geo_multiplier: Decimal.new("2.0"),
          verified: true
        })

      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{user: merged, summary: summary}} =
               LegacyMerge.merge_legacy_into!(new_user, legacy)

      assert summary.phone_transferred == true
      assert merged.phone_verified == true
      assert Decimal.equal?(merged.geo_multiplier, Decimal.new("2.0"))
    end

    test "leaves phone alone when new user already has one" do
      legacy = create_legacy_user()
      legacy_phone_number = "+15554445555"

      {:ok, _} =
        Repo.insert(%PhoneVerification{
          user_id: legacy.id,
          phone_number: legacy_phone_number,
          country_code: "US",
          geo_tier: "premium",
          geo_multiplier: Decimal.new("2.0")
        })

      new_user = create_new_user() |> set_pending_email(legacy.email)

      {:ok, _} =
        Repo.insert(%PhoneVerification{
          user_id: new_user.id,
          phone_number: "+15555556666",
          country_code: "GB",
          geo_tier: "premium",
          geo_multiplier: Decimal.new("2.0")
        })

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert summary.phone_transferred == false

      # Legacy phone row still belongs to legacy_user
      legacy_phone = Repo.get_by(PhoneVerification, phone_number: legacy_phone_number)
      assert legacy_phone.user_id == legacy.id
    end
  end

  describe "merge_legacy_into!/2 - BUX claim edge cases" do
    test "no merge BUX is claimed when there is no snapshot row" do
      legacy = create_legacy_user()
      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert summary.bux_claimed == 0.0
      assert BuxMinterStub.calls() == []
    end

    test "zero balance snapshot does not call mint" do
      legacy = create_legacy_user()
      _snapshot = create_legacy_bux_snapshot(legacy.email, "0")
      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert summary.bux_claimed == 0.0
      assert BuxMinterStub.calls() == []
    end

    test "settler mint failure rolls back the entire merge" do
      legacy =
        create_legacy_user(%{username: "rolled_back_legacy"})
        |> Map.put(:_keep, true)

      _snapshot = create_legacy_bux_snapshot(legacy.email, "500")

      new_user = create_new_user() |> set_pending_email(legacy.email)

      BuxMinterStub.set_response({:error, :settler_unreachable})

      assert {:error, {:bux_mint_failed, :settler_unreachable}} =
               LegacyMerge.merge_legacy_into!(new_user, legacy)

      # Legacy user should still be active and unchanged
      reloaded_legacy = Repo.get!(User, legacy.id)
      assert reloaded_legacy.is_active == true
      assert reloaded_legacy.username == "rolled_back_legacy"

      # New user should not have email/username transferred
      reloaded_new = Repo.get!(User, new_user.id)
      assert reloaded_new.email == nil
      assert reloaded_new.username != "rolled_back_legacy"

      # Snapshot row should not be marked migrated
      snapshot = Repo.get_by(LegacyBuxMigration, email: String.downcase(legacy.email))
      assert snapshot.migrated == false
    end

    test "already-migrated snapshot is a no-op (no double mint)" do
      legacy = create_legacy_user()

      {:ok, _migration} =
        Repo.insert(%LegacyBuxMigration{
          email: String.downcase(legacy.email),
          legacy_bux_balance: Decimal.new("750"),
          legacy_wallet_address: "0xOld",
          new_wallet_address: "SomeOtherWallet",
          mint_tx_signature: "old_sig",
          migrated: true,
          migrated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert summary.bux_claimed == 0.0
      assert BuxMinterStub.calls() == []
    end
  end

  describe "merge_legacy_into!/2 - content & social FK rewrites" do
    test "rewrites authored posts, hub follows, event organizing & attendance, orders" do
      legacy = create_legacy_user(%{is_author: true})
      new_user = create_new_user() |> set_pending_email(legacy.email)

      hub = insert_hub()

      # 5 posts authored by legacy
      for i <- 1..5 do
        insert_post(legacy.id, hub.id, "Title #{i}", "slug-#{unique_suffix()}-#{i}")
      end

      # 2 events organized by legacy
      e1 = insert_event(legacy.id, "Event A")
      e2 = insert_event(legacy.id, "Event B")

      # 1 event attendance
      Repo.insert_all("event_attendees", [
        %{user_id: legacy.id, event_id: e1.id, inserted_at: DateTime.utc_now() |> DateTime.truncate(:second), updated_at: DateTime.utc_now() |> DateTime.truncate(:second)}
      ])

      # 3 hub follows
      hub2 = insert_hub()
      hub3 = insert_hub()

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all("hub_followers", [
        %{user_id: legacy.id, hub_id: hub.id, inserted_at: now, updated_at: now},
        %{user_id: legacy.id, hub_id: hub2.id, inserted_at: now, updated_at: now},
        %{user_id: legacy.id, hub_id: hub3.id, inserted_at: now, updated_at: now}
      ])

      # 4 orders
      for i <- 1..4 do
        insert_order(legacy.id, "ORD-#{unique_suffix()}-#{i}")
      end

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)

      assert summary.content.posts == 5
      assert summary.content.events == 2
      assert summary.content.event_attendees == 1
      assert summary.content.hub_followers == 3
      assert summary.content.orders == 4

      # Spot checks
      assert Repo.aggregate(from(p in BlocksterV2.Blog.Post, where: p.author_id == ^new_user.id), :count) == 5
      assert Repo.aggregate(from(e in BlocksterV2.Events.Event, where: e.organizer_id == ^new_user.id), :count) == 2
      assert Repo.aggregate(from(o in Order, where: o.user_id == ^new_user.id), :count) == 4

      # Make sure legacy IDs are gone
      assert Repo.aggregate(from(p in BlocksterV2.Blog.Post, where: p.author_id == ^legacy.id), :count) == 0
      _ = e2  # silence
    end
  end

  describe "merge_legacy_into!/2 - referrals" do
    test "copies inbound referrer onto new user when new has none" do
      referrer = create_legacy_user(%{username: "ref_#{unique_suffix()}"})

      legacy =
        create_legacy_user(%{
          referrer_id: referrer.id,
          referred_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{user: merged, summary: summary}} =
               LegacyMerge.merge_legacy_into!(new_user, legacy)

      assert merged.referrer_id == referrer.id
      assert summary.referrals.inbound_copied == true
    end

    test "does not copy inbound when legacy has none" do
      legacy = create_legacy_user()
      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert summary.referrals.inbound_copied == false
    end

    test "does not overwrite an existing inbound referrer on the new user" do
      original_referrer = create_legacy_user(%{username: "orig_#{unique_suffix()}"})
      other_referrer = create_legacy_user(%{username: "other_#{unique_suffix()}"})

      legacy = create_legacy_user(%{referrer_id: other_referrer.id})

      new_user =
        create_new_user(%{referrer_id: original_referrer.id})
        |> set_pending_email(legacy.email)

      assert {:ok, %{user: merged}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert merged.referrer_id == original_referrer.id
    end

    test "reassigns outbound referees from legacy to new user" do
      legacy = create_legacy_user()

      _r1 = create_legacy_user(%{referrer_id: legacy.id})
      _r2 = create_legacy_user(%{referrer_id: legacy.id})
      _r3 = create_legacy_user(%{referrer_id: legacy.id})

      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)

      assert summary.referrals.referees == 3
      assert Repo.aggregate(from(u in User, where: u.referrer_id == ^new_user.id), :count) == 3
    end

    test "reassigns order-level referrer attribution" do
      legacy = create_legacy_user()
      _o1 = insert_order_with_referrer(legacy.id)
      _o2 = insert_order_with_referrer(legacy.id)

      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert summary.referrals.order_referrer_updates == 2
    end

    test "reassigns affiliate payouts" do
      legacy = create_legacy_user()
      order = insert_order_with_referrer(legacy.id)

      {:ok, _} =
        Repo.insert(%AffiliatePayout{
          order_id: order.id,
          referrer_id: legacy.id,
          currency: "BUX",
          basis_amount: Decimal.new("100"),
          commission_amount: Decimal.new("5"),
          status: "pending"
        })

      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert summary.referrals.affiliate_payouts == 1

      payout = Repo.one(from p in AffiliatePayout, where: p.referrer_id == ^new_user.id)
      assert payout != nil
    end
  end

  describe "merge_legacy_into!/2 - fingerprints" do
    test "transfers user_fingerprint rows" do
      legacy = create_legacy_user()
      new_user = create_new_user() |> set_pending_email(legacy.email)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for i <- 1..2 do
        {:ok, _} =
          Repo.insert(%UserFingerprint{
            user_id: legacy.id,
            fingerprint_id: "fp_#{unique_suffix()}_#{i}",
            first_seen_at: now,
            last_seen_at: now,
            is_primary: i == 1
          })
      end

      assert {:ok, %{summary: summary}} = LegacyMerge.merge_legacy_into!(new_user, legacy)
      assert summary.fingerprints_transferred == 2

      assert Repo.aggregate(from(f in UserFingerprint, where: f.user_id == ^new_user.id), :count) == 2
      assert Repo.aggregate(from(f in UserFingerprint, where: f.user_id == ^legacy.id), :count) == 0
    end
  end

  describe "merge_legacy_into!/2 - guards" do
    test "rejects merging a user into itself" do
      user = create_legacy_user()
      assert {:error, :same_user} = LegacyMerge.merge_legacy_into!(user, user)
    end

    test "rejects merging a bot legacy user" do
      bot = create_legacy_user(%{is_bot: true})
      new_user = create_new_user() |> set_pending_email(bot.email)
      assert {:error, :legacy_is_bot} = LegacyMerge.merge_legacy_into!(new_user, bot)
    end

    test "rejects merging an already-deactivated legacy user" do
      legacy = create_legacy_user()

      {:ok, deactivated} =
        legacy
        |> User.changeset(%{is_active: false})
        |> Repo.update()

      new_user = create_new_user() |> set_pending_email(deactivated.email)
      assert {:error, :legacy_already_deactivated} = LegacyMerge.merge_legacy_into!(new_user, deactivated)
    end

    test "rejects merging an active Solana wallet user (not a legacy holder)" do
      # An active wallet user is NOT a valid merge target.
      {:ok, active_wallet_user} =
        %User{}
        |> User.changeset(%{
          wallet_address: "ActiveWallet" <> unique_suffix(),
          username: "active_wallet_#{unique_suffix()}",
          auth_method: "wallet",
          email: "active@example.com"
        })
        |> Repo.insert()

      new_user = create_new_user() |> set_pending_email("active@example.com")

      assert {:error, :not_a_legacy_holder} =
               LegacyMerge.merge_legacy_into!(new_user, active_wallet_user)
    end
  end

  describe "merge_legacy_into!/2 - username collision invariant" do
    test "two active users can never both have the same username after merge" do
      legacy = create_legacy_user(%{username: "shared_handle_#{unique_suffix()}"})
      new_user = create_new_user() |> set_pending_email(legacy.email)

      assert {:ok, %{user: merged}} = LegacyMerge.merge_legacy_into!(new_user, legacy)

      active_count =
        Repo.aggregate(
          from(u in User,
            where: u.username == ^merged.username and u.is_active == true
          ),
          :count
        )

      assert active_count == 1
    end
  end

  # ==========================================================================
  # Test fixtures for content models
  # ==========================================================================

  defp insert_hub do
    suffix = unique_suffix()

    {:ok, hub} =
      Repo.insert(%BlocksterV2.Blog.Hub{
        name: "Hub #{suffix}",
        slug: "hub-#{suffix}",
        tag_name: "hub_tag_#{suffix}",
        description: "Test hub"
      })

    hub
  end

  defp insert_post(author_id, hub_id, title, slug) do
    {:ok, post} =
      Repo.insert(%BlocksterV2.Blog.Post{
        author_id: author_id,
        hub_id: hub_id,
        title: title,
        slug: slug,
        content: %{}
      })

    post
  end

  defp insert_event(organizer_id, title) do
    {:ok, event} =
      Repo.insert(%BlocksterV2.Events.Event{
        organizer_id: organizer_id,
        title: title,
        slug: "event-#{unique_suffix()}",
        description: "test",
        date: Date.utc_today(),
        time: ~T[12:00:00]
      })

    event
  end

  defp insert_order(user_id, order_number) do
    {:ok, order} =
      Repo.insert(%Order{
        user_id: user_id,
        order_number: order_number,
        subtotal: Decimal.new("100"),
        total_paid: Decimal.new("100"),
        status: "pending"
      })

    order
  end

  defp insert_order_with_referrer(referrer_id) do
    user = create_legacy_user()

    {:ok, order} =
      Repo.insert(%Order{
        user_id: user.id,
        referrer_id: referrer_id,
        order_number: "ORD-#{unique_suffix()}",
        subtotal: Decimal.new("100"),
        total_paid: Decimal.new("100"),
        status: "pending"
      })

    order
  end
end
