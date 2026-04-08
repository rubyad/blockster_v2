defmodule BlocksterV2.Migration.LegacyMerge do
  @moduledoc """
  Merges a legacy (EVM/email-auth) user into a new Solana-auth user.

  Triggered when a new user verifies an email that matches a legacy user.
  Transfers BUX, username, X, Telegram, phone (if not already held by new user),
  authored content, referrals, fingerprints, and finally deactivates the legacy
  user.

  Engagement history (`user_post_engagement`, `user_post_rewards`) is NOT
  transferred.

  See `docs/legacy_account_reclaim_plan.md` for the full design.
  """

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.{User, PhoneVerification, UserFingerprint}
  alias BlocksterV2.Migration.LegacyBuxMigration
  import Ecto.Query
  require Logger

  @bux_minter Application.compile_env(:blockster_v2, :bux_minter, BlocksterV2.BuxMinter)

  @doc """
  Merges the legacy user into the new user.

  Returns `{:ok, %{user: refreshed_new_user, summary: summary_map}}` on success
  or `{:error, reason}` on failure. The whole merge is wrapped in an Ecto
  transaction; any failure (including a settler mint failure) rolls back the
  full set of changes.

  The summary map describes what was transferred so the UI can show a
  "Welcome back" success card.
  """
  def merge_legacy_into!(%User{} = new_user, %User{} = legacy_user) do
    cond do
      legacy_user.id == new_user.id ->
        {:error, :same_user}

      legacy_user.is_bot ->
        {:error, :legacy_is_bot}

      legacy_user.is_active == false ->
        {:error, :legacy_already_deactivated}

      true ->
        do_merge(new_user, legacy_user)
    end
  end

  defp do_merge(new_user, legacy_user) do
    # Capture the originals BEFORE we deactivate the legacy row, since
    # deactivation NULLs/overwrites several of these fields.
    originals = %{
      email: legacy_user.email,
      username: legacy_user.username,
      slug: legacy_user.slug,
      telegram_user_id: legacy_user.telegram_user_id,
      telegram_username: legacy_user.telegram_username,
      telegram_connected_at: legacy_user.telegram_connected_at,
      telegram_group_joined_at: legacy_user.telegram_group_joined_at,
      locked_x_user_id: legacy_user.locked_x_user_id,
      referrer_id: legacy_user.referrer_id,
      referred_at: legacy_user.referred_at
    }

    Repo.transaction(fn ->
      # 1. Deactivate legacy FIRST so unique slots (email/username/slug/telegram)
      #    are freed before we try to take them on the new user.
      legacy_user = deactivate_legacy_user(legacy_user, new_user.id)

      # 2. Mint legacy BUX to new Solana wallet (rolls back the whole merge on
      #    failure so we never lose state to a half-claim).
      {bux_amount, mint_signature} = maybe_claim_legacy_bux(new_user, originals)

      # 3. Transfer username + slug (legacy slot is now free).
      {new_user, username_transferred} = maybe_transfer_username(new_user, originals)

      # 4. Transfer X connection (Mnesia row + locked_x_user_id).
      x_transferred = maybe_transfer_x_connection(new_user, legacy_user, originals)

      # 5. Transfer Telegram fields.
      {new_user, telegram_transferred} = maybe_transfer_telegram(new_user, originals)

      # 6. Transfer phone (phone_verifications row + user-level fields).
      {new_user, phone_transferred} = maybe_transfer_phone(new_user, legacy_user)

      # 7. Bulk-rewrite content authorship and social FKs.
      content_counts = transfer_content_and_social_fks(new_user, legacy_user)

      # 8. Transfer referrals (inbound + outbound + affiliate attribution).
      {new_user, referral_counts} = transfer_referrals(new_user, legacy_user, originals)

      # 9. Transfer fingerprints (data continuity only).
      fingerprint_count = transfer_fingerprints(new_user, legacy_user)

      # 10. Finalize the new user's email field (writes pending_email -> email).
      new_user = finalize_new_user_email(new_user)

      %{
        user: new_user,
        summary: %{
          legacy_user_id: legacy_user.id,
          bux_claimed: bux_amount,
          mint_signature: mint_signature,
          username_transferred: username_transferred,
          x_transferred: x_transferred,
          telegram_transferred: telegram_transferred,
          phone_transferred: phone_transferred,
          fingerprints_transferred: fingerprint_count,
          content: content_counts,
          referrals: referral_counts
        }
      }
    end)
    |> case do
      {:ok, %{user: user, summary: summary}} ->
        # Refresh multipliers AFTER the transaction commits.
        BlocksterV2.UnifiedMultiplier.refresh_multipliers(user.id)
        refreshed = Repo.get!(User, user.id)
        {:ok, %{user: refreshed, summary: summary}}

      {:error, reason} ->
        Logger.error("[LegacyMerge] Failed to merge legacy user #{legacy_user.id} into new user #{new_user.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # Step 1: Deactivate legacy user
  # ============================================================================

  defp deactivate_legacy_user(legacy_user, new_user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    legacy_user
    |> Ecto.Changeset.change(%{
      is_active: false,
      merged_into_user_id: new_user_id,
      deactivated_at: now,
      email: nil,
      legacy_email: legacy_user.email,
      username: "deactivated_#{legacy_user.id}",
      slug: "deactivated-#{legacy_user.id}",
      smart_wallet_address: nil,
      telegram_user_id: nil,
      telegram_username: nil,
      telegram_connect_token: nil,
      # Free the locked_x_user_id slot so the new user can take it.
      locked_x_user_id: nil
    })
    |> Repo.update!()
  end

  # ============================================================================
  # Step 2: BUX claim
  # ============================================================================

  defp maybe_claim_legacy_bux(new_user, %{email: email}) do
    case email && Repo.get_by(LegacyBuxMigration, email: String.downcase(email)) do
      nil ->
        {0.0, nil}

      false ->
        {0.0, nil}

      %LegacyBuxMigration{migrated: true} ->
        # Defensive — shouldn't happen mid-merge.
        {0.0, nil}

      %LegacyBuxMigration{legacy_bux_balance: bal} = migration ->
        amount = decimal_to_float(bal)

        if amount > 0 do
          mint_legacy_bux(new_user, migration, amount)
        else
          {0.0, nil}
        end
    end
  end

  defp mint_legacy_bux(new_user, migration, amount) do
    case @bux_minter.mint_bux(
           new_user.wallet_address,
           amount,
           new_user.id,
           nil,
           :legacy_migration
         ) do
      {:ok, response} ->
        signature = response["signature"] || response[:signature]
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        migration
        |> Ecto.Changeset.change(%{
          new_wallet_address: new_user.wallet_address,
          mint_tx_signature: signature,
          migrated: true,
          migrated_at: now
        })
        |> Repo.update!()

        Logger.info("[LegacyMerge] Minted #{amount} legacy BUX to #{new_user.wallet_address} (sig: #{inspect(signature)})")

        {amount, signature}

      {:error, reason} ->
        Logger.error("[LegacyMerge] BUX mint failed: #{inspect(reason)}")
        Repo.rollback({:bux_mint_failed, reason})
    end
  end

  # ============================================================================
  # Step 3: Username transfer
  # ============================================================================

  defp maybe_transfer_username(new_user, %{username: legacy_username, slug: legacy_slug}) do
    cond do
      is_nil(legacy_username) or legacy_username == "" ->
        {new_user, false}

      true ->
        new_user =
          new_user
          |> Ecto.Changeset.change(%{
            username: legacy_username,
            slug: legacy_slug
          })
          |> Repo.update!()

        {new_user, true}
    end
  end

  # ============================================================================
  # Step 4: X connection transfer (Mnesia + locked_x_user_id)
  # ============================================================================

  defp maybe_transfer_x_connection(new_user, legacy_user, originals) do
    legacy_id = legacy_user.id
    new_id = new_user.id

    legacy_x = safe_x_connection(legacy_id)
    new_x = safe_x_connection(new_id)

    cond do
      is_nil(legacy_x) and is_nil(originals.locked_x_user_id) ->
        false

      legacy_x && is_nil(new_x) ->
        # Read the legacy raw record and re-write it under the new user's key.
        rewrite_x_connection_user_id(legacy_id, new_id)
        # Move the locked_x_user_id over.
        if originals.locked_x_user_id do
          new_user
          |> Ecto.Changeset.change(%{locked_x_user_id: originals.locked_x_user_id})
          |> Repo.update!()
        end

        true

      legacy_x && new_x ->
        # New user already has X — drop the legacy record.
        try do
          :mnesia.dirty_delete({:x_connections, legacy_id})
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end

        false

      is_nil(legacy_x) and originals.locked_x_user_id ->
        # Edge case: locked but no Mnesia row. Just move the lock.
        if is_nil(new_user.locked_x_user_id) do
          new_user
          |> Ecto.Changeset.change(%{locked_x_user_id: originals.locked_x_user_id})
          |> Repo.update!()

          true
        else
          false
        end

      true ->
        false
    end
  end

  defp safe_x_connection(user_id) do
    try do
      BlocksterV2.EngagementTracker.get_x_connection_by_user(user_id)
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  defp rewrite_x_connection_user_id(from_user_id, to_user_id) do
    try do
      case :mnesia.dirty_read({:x_connections, from_user_id}) do
        [] ->
          :ok

        [record] ->
          # Tuple structure: 0 = :x_connections, 1 = user_id, 2..20 = rest
          new_record = put_elem(record, 1, to_user_id)
          :mnesia.dirty_delete({:x_connections, from_user_id})
          :mnesia.dirty_write(new_record)
          :ok
      end
    rescue
      e ->
        Logger.error("[LegacyMerge] Failed to rewrite x_connection user_id: #{inspect(e)}")
        :ok
    catch
      :exit, _ -> :ok
    end
  end

  # ============================================================================
  # Step 5: Telegram transfer
  # ============================================================================

  defp maybe_transfer_telegram(new_user, originals) do
    case originals.telegram_user_id do
      nil ->
        {new_user, false}

      tg_id ->
        if is_nil(new_user.telegram_user_id) do
          new_user =
            new_user
            |> Ecto.Changeset.change(%{
              telegram_user_id: tg_id,
              telegram_username: originals.telegram_username,
              telegram_connect_token: nil,
              telegram_connected_at: originals.telegram_connected_at,
              telegram_group_joined_at: originals.telegram_group_joined_at
            })
            |> Repo.update!()

          {new_user, true}
        else
          {new_user, false}
        end
    end
  end

  # ============================================================================
  # Step 6: Phone transfer
  # ============================================================================

  defp maybe_transfer_phone(new_user, legacy_user) do
    legacy_phone = Repo.get_by(PhoneVerification, user_id: legacy_user.id)
    new_phone = Repo.get_by(PhoneVerification, user_id: new_user.id)

    cond do
      legacy_phone && is_nil(new_phone) ->
        # Transfer the phone_verifications row.
        legacy_phone
        |> Ecto.Changeset.change(%{user_id: new_user.id})
        |> Repo.update!()

        # Sync user-level phone fields on the new user.
        new_user =
          new_user
          |> Ecto.Changeset.change(%{
            phone_verified: true,
            geo_multiplier: legacy_phone.geo_multiplier,
            geo_tier: legacy_phone.geo_tier
          })
          |> Repo.update!()

        # Clear them on the legacy user.
        legacy_user
        |> Ecto.Changeset.change(%{
          phone_verified: false,
          geo_multiplier: Decimal.new("0.5"),
          geo_tier: "unverified"
        })
        |> Repo.update!()

        {new_user, true}

      true ->
        {new_user, false}
    end
  end

  # ============================================================================
  # Step 7: Content & social FK rewrites
  # ============================================================================

  defp transfer_content_and_social_fks(new_user, legacy_user) do
    legacy_id = legacy_user.id
    new_id = new_user.id

    {posts, _} =
      Repo.update_all(
        from(p in BlocksterV2.Blog.Post, where: p.author_id == ^legacy_id),
        set: [author_id: new_id]
      )

    {events, _} =
      Repo.update_all(
        from(e in BlocksterV2.Events.Event, where: e.organizer_id == ^legacy_id),
        set: [organizer_id: new_id]
      )

    {attendees, _} =
      Repo.update_all(
        from(ea in "event_attendees", where: ea.user_id == ^legacy_id),
        set: [user_id: new_id]
      )

    {hub_followers, _} =
      Repo.update_all(
        from(hf in "hub_followers", where: hf.user_id == ^legacy_id),
        set: [user_id: new_id]
      )

    {orders, _} =
      Repo.update_all(
        from(o in BlocksterV2.Orders.Order, where: o.user_id == ^legacy_id),
        set: [user_id: new_id]
      )

    %{
      posts: posts,
      events: events,
      event_attendees: attendees,
      hub_followers: hub_followers,
      orders: orders
    }
  end

  # ============================================================================
  # Step 8: Referrals
  # ============================================================================

  defp transfer_referrals(new_user, legacy_user, originals) do
    legacy_id = legacy_user.id
    new_id = new_user.id

    # 1. Inbound referrer: legacy was referred by X → copy onto new user
    #    Don't overwrite if the new user already has a referrer.
    new_user =
      if originals.referrer_id && is_nil(new_user.referrer_id) do
        new_user
        |> Ecto.Changeset.change(%{
          referrer_id: originals.referrer_id,
          referred_at: originals.referred_at
        })
        |> Repo.update!()
      else
        new_user
      end

    # 2. Outbound referees: anyone the legacy user referred now points at the
    #    new user.
    {referee_count, _} =
      Repo.update_all(
        from(u in User, where: u.referrer_id == ^legacy_id),
        set: [referrer_id: new_id]
      )

    # 3. Order-level affiliate attribution.
    {order_referrer_count, _} =
      Repo.update_all(
        from(o in BlocksterV2.Orders.Order, where: o.referrer_id == ^legacy_id),
        set: [referrer_id: new_id]
      )

    # 4. Outstanding affiliate payouts.
    {affiliate_count, _} =
      Repo.update_all(
        from(p in BlocksterV2.Orders.AffiliatePayout, where: p.referrer_id == ^legacy_id),
        set: [referrer_id: new_id]
      )

    {new_user,
     %{
       referees: referee_count,
       order_referrer_updates: order_referrer_count,
       affiliate_payouts: affiliate_count,
       inbound_copied: originals.referrer_id != nil
     }}
  end

  # ============================================================================
  # Step 9: Fingerprints
  # ============================================================================

  defp transfer_fingerprints(new_user, legacy_user) do
    {count, _} =
      Repo.update_all(
        from(f in UserFingerprint, where: f.user_id == ^legacy_user.id),
        set: [user_id: new_user.id]
      )

    count
  end

  # ============================================================================
  # Step 10: Finalize new user's email
  # ============================================================================

  defp finalize_new_user_email(new_user) do
    case new_user.pending_email do
      nil ->
        new_user

      email ->
        new_user
        |> Ecto.Changeset.change(%{
          email: email,
          email_verified: true,
          pending_email: nil,
          email_verification_code: nil,
          email_verification_sent_at: nil
        })
        |> Repo.update!()
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(n) when is_number(n), do: n * 1.0
  defp decimal_to_float(_), do: 0.0
end
