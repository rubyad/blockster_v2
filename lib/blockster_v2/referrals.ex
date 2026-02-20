defmodule BlocksterV2.Referrals do
  @moduledoc """
  Handles referral tracking, rewards, and earnings using Mnesia for storage.

  Referrers earn:
  - 100 BUX when a referred user signs up
  - 100 BUX when a referred user verifies their phone number
  - 1% of every losing BUX bet on BUX Booster by their referrals (paid from smart contract)
  - 0.2% of every losing ROGUE bet on BUX Booster by their referrals (paid from smart contract)
  """
  require Logger

  alias BlocksterV2.{Repo, BuxMinter}
  alias BlocksterV2.Accounts.User

  @signup_reward 100  # BUX
  @phone_verified_reward 100  # BUX

  # ----- Signup Referral Processing -----

  @doc """
  Process a new user signup with a referral code.
  Links the referrer in both Mnesia and PostgreSQL, then mints signup reward.
  """
  def process_signup_referral(new_user, referrer_wallet) when is_binary(referrer_wallet) do
    referrer_wallet = String.downcase(referrer_wallet)

    # Prevent self-referral
    if new_user.smart_wallet_address &&
       String.downcase(new_user.smart_wallet_address) == referrer_wallet do
      {:error, :self_referral}
    else
      # Find referrer by smart wallet address
      case Repo.get_by(User, smart_wallet_address: referrer_wallet) do
        nil ->
          {:error, :referrer_not_found}

        referrer ->
          # Update PostgreSQL user record
          new_user
          |> Ecto.Changeset.change(%{
            referrer_id: referrer.id,
            referred_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.update!()

          # Store in Mnesia (with both wallet addresses for blockchain event matching)
          now = System.system_time(:second)
          referee_wallet = String.downcase(new_user.smart_wallet_address || "")
          referral_record = {:referrals, new_user.id, referrer.id, referrer_wallet, referee_wallet, now, false}
          :mnesia.dirty_write(referral_record)

          # Create earning and mint reward (pass wallets for Mnesia storage)
          create_signup_earning(referrer, new_user, referrer_wallet, referee_wallet)

          # Queue on-chain referrer sync (async)
          sync_referrer_to_contracts(new_user.smart_wallet_address, referrer_wallet)

          {:ok, referrer}
      end
    end
  end

  def process_signup_referral(_new_user, nil), do: {:error, :no_referrer}
  def process_signup_referral(_new_user, ""), do: {:error, :no_referrer}

  defp create_signup_earning(referrer, _referee, referrer_wallet, referee_wallet) do
    now = System.system_time(:second)
    id = Ecto.UUID.generate()

    # Insert Mnesia earning record with wallet addresses (no DB lookup needed later)
    # tx_hash is nil initially, will be updated after mint completes
    earning_record = {:referral_earnings, id, referrer.id, referrer_wallet, referee_wallet,
                      :signup, @signup_reward, "BUX", nil, nil, now}
    :mnesia.dirty_write(earning_record)

    # Update stats
    update_referrer_stats(referrer.id, :signup, @signup_reward, "BUX")

    # Mint BUX to referrer (async, will update tx_hash in Mnesia when complete)
    mint_referral_reward(id, referrer_wallet, @signup_reward, "BUX", referrer.id, :signup)

    # Broadcast real-time update
    broadcast_referral_earning(referrer.id, %{
      type: :signup,
      amount: @signup_reward,
      token: "BUX",
      referee_wallet: referee_wallet,
      timestamp: now
    })
  end

  # ----- Phone Verification Reward -----

  @doc """
  Process phone verification reward for referrer.
  Called from PhoneVerification.verify_code/2 after successful verification.

  Mnesia-only - no PostgreSQL queries.
  """
  def process_phone_verification_reward(user_id) do
    # Check if user has a referrer (from Mnesia)
    case :mnesia.dirty_read(:referrals, user_id) do
      [] ->
        :no_referrer

      [{:referrals, ^user_id, referrer_id, referrer_wallet, referee_wallet, _at, _synced}] ->
        # Check if already rewarded (look for existing phone_verified earning)
        existing = :mnesia.dirty_index_read(:referral_earnings, referrer_id, :referrer_id)
        |> Enum.any?(fn record ->
          elem(record, 5) == :phone_verified and elem(record, 4) == referee_wallet
        end)

        if existing do
          {:error, :already_rewarded}
        else
          create_phone_verification_earning(referrer_id, referrer_wallet, referee_wallet)
        end
    end
  end

  defp create_phone_verification_earning(referrer_id, referrer_wallet, referee_wallet) do
    now = System.system_time(:second)
    id = Ecto.UUID.generate()

    # Store with wallet addresses (no DB lookup needed later)
    # tx_hash is nil initially, will be updated after mint completes
    earning_record = {:referral_earnings, id, referrer_id, referrer_wallet, referee_wallet,
                      :phone_verified, @phone_verified_reward, "BUX", nil, nil, now}
    :mnesia.dirty_write(earning_record)

    update_referrer_stats(referrer_id, :phone_verified, @phone_verified_reward, "BUX")

    # Mint BUX to referrer (async, will update tx_hash in Mnesia when complete)
    mint_referral_reward(id, referrer_wallet, @phone_verified_reward, "BUX", referrer_id, :phone_verified)

    broadcast_referral_earning(referrer_id, %{
      type: :phone_verified,
      amount: @phone_verified_reward,
      token: "BUX",
      referee_wallet: referee_wallet,
      timestamp: now
    })

    {:ok, referrer_id}
  end

  # ----- Bet Loss Earnings (from blockchain events) -----

  @doc """
  Record a bet loss earning from smart contract event.
  Called by ReferralRewardPoller when ReferralRewardPaid event is detected.

  Uses Mnesia-only lookups - no PostgreSQL queries.
  """
  def record_bet_loss_earning(attrs) do
    %{
      referrer_wallet: referrer_wallet,
      referee_wallet: referee_wallet,
      amount: amount,
      token: token,
      commitment_hash: commitment_hash,
      tx_hash: tx_hash
    } = attrs

    referrer_wallet = String.downcase(referrer_wallet)
    referee_wallet = String.downcase(referee_wallet)

    # Check for duplicate (idempotent)
    existing = :mnesia.dirty_index_read(:referral_earnings, commitment_hash, :commitment_hash)
    if existing != [] do
      :duplicate
    else
      # Look up referrer_id from Mnesia (no PostgreSQL!)
      case get_referrer_by_referee_wallet(referee_wallet) do
        {:ok, %{referrer_id: referrer_id, referrer_wallet: stored_referrer_wallet}} ->
          # Verify the referrer wallet matches what blockchain sent
          if stored_referrer_wallet == referrer_wallet do
            now = System.system_time(:second)
            id = Ecto.UUID.generate()
            earning_type = if token == "ROGUE", do: :rogue_bet_loss, else: :bux_bet_loss

            # Store with wallet addresses for display (no DB lookup needed later)
            earning_record = {:referral_earnings, id, referrer_id, referrer_wallet, referee_wallet,
                              earning_type, amount, token, tx_hash, commitment_hash, now}
            :mnesia.dirty_write(earning_record)

            update_referrer_stats(referrer_id, earning_type, amount, token)

            # Broadcast real-time update for earnings table
            broadcast_referral_earning(referrer_id, %{
              type: earning_type,
              amount: amount,
              token: token,
              referee_wallet: referee_wallet,
              tx_hash: tx_hash,
              timestamp: now
            })

            # Sync balances from blockchain and broadcast to update header/member page
            # (the tokens were already sent on-chain by the smart contract)
            BuxMinter.sync_user_balances_async(referrer_id, referrer_wallet, force: true)

            :ok
          else
            Logger.warning("[Referrals] Referrer wallet mismatch: expected #{stored_referrer_wallet}, got #{referrer_wallet}")
            :referrer_mismatch
          end

        :not_found ->
          Logger.warning("[Referrals] No referral found for referee wallet: #{referee_wallet}")
          :referral_not_found
      end
    end
  end

  @doc """
  Same as record_bet_loss_earning but skips broadcast (used during backfill).
  Uses Mnesia-only lookups - no PostgreSQL queries.
  """
  def record_bet_loss_earning_backfill(attrs) do
    %{
      referrer_wallet: referrer_wallet,
      referee_wallet: referee_wallet,
      amount: amount,
      token: token,
      commitment_hash: commitment_hash,
      tx_hash: tx_hash
    } = attrs

    referrer_wallet = String.downcase(referrer_wallet)
    referee_wallet = String.downcase(referee_wallet)

    # Check for duplicate
    existing = :mnesia.dirty_index_read(:referral_earnings, commitment_hash, :commitment_hash)
    if existing != [] do
      :duplicate
    else
      case get_referrer_by_referee_wallet(referee_wallet) do
        {:ok, %{referrer_id: referrer_id, referrer_wallet: stored_referrer_wallet}} ->
          if stored_referrer_wallet == referrer_wallet do
            now = System.system_time(:second)
            id = Ecto.UUID.generate()
            earning_type = if token == "ROGUE", do: :rogue_bet_loss, else: :bux_bet_loss

            earning_record = {:referral_earnings, id, referrer_id, referrer_wallet, referee_wallet,
                              earning_type, amount, token, tx_hash, commitment_hash, now}
            :mnesia.dirty_write(earning_record)

            update_referrer_stats(referrer_id, earning_type, amount, token)
            :ok
          else
            :referrer_mismatch
          end

        :not_found ->
          :referral_not_found
      end
    end
  end

  # ----- Shop Purchase Earnings -----

  @doc """
  Record a shop purchase affiliate earning in Mnesia.
  Called from Orders.create_affiliate_payouts/1 when a referred user makes a purchase.
  Supports BUX, ROGUE, and Helio currencies (USDC, SOL, etc).
  """
  def record_shop_purchase_earning(attrs) do
    %{
      referrer_id: referrer_id,
      referrer_wallet: referrer_wallet,
      referee_wallet: referee_wallet,
      amount: amount,
      token: token
    } = attrs

    referrer_wallet = String.downcase(referrer_wallet || "")
    referee_wallet = String.downcase(referee_wallet || "")

    # Convert Decimal to float if needed (Mnesia stores numbers, not Decimal structs)
    numeric_amount = case amount do
      %Decimal{} -> Decimal.to_float(amount)
      n when is_number(n) -> n * 1.0
      _ -> 0.0
    end

    now = System.system_time(:second)
    id = Ecto.UUID.generate()

    earning_record = {:referral_earnings, id, referrer_id, referrer_wallet, referee_wallet,
                      :shop_purchase, numeric_amount, token, nil, nil, now}
    :mnesia.dirty_write(earning_record)

    update_referrer_stats(referrer_id, :shop_purchase, numeric_amount, token)

    broadcast_referral_earning(referrer_id, %{
      type: :shop_purchase,
      amount: numeric_amount,
      token: token,
      referee_wallet: referee_wallet,
      timestamp: now
    })

    {:ok, id}
  rescue
    e ->
      Logger.error("[Referrals] Failed to record shop purchase earning: #{inspect(e)}")
      {:error, e}
  catch
    :exit, reason ->
      Logger.error("[Referrals] Mnesia error recording shop purchase earning: #{inspect(reason)}")
      {:error, reason}
  end

  # ----- Stats Management -----

  defp update_referrer_stats(referrer_id, earning_type, amount, token) do
    now = System.system_time(:second)

    case :mnesia.dirty_read(:referral_stats, referrer_id) do
      [] ->
        # Create new stats record
        {total_refs, verified, bux, rogue} = case {earning_type, token} do
          {:signup, "BUX"} -> {1, 0, amount, 0.0}
          {:phone_verified, "BUX"} -> {0, 1, amount, 0.0}
          {_, "BUX"} -> {0, 0, amount, 0.0}
          {_, "ROGUE"} -> {0, 0, 0.0, amount}
          {_, _} -> {0, 0, 0.0, 0.0}
        end
        record = {:referral_stats, referrer_id, total_refs, verified, bux, rogue, now}
        :mnesia.dirty_write(record)

      [{:referral_stats, ^referrer_id, total_refs, verified, bux, rogue, _updated}] ->
        {new_refs, new_verified, new_bux, new_rogue} = case {earning_type, token} do
          {:signup, "BUX"} -> {total_refs + 1, verified, bux + amount, rogue}
          {:phone_verified, "BUX"} -> {total_refs, verified + 1, bux + amount, rogue}
          {_, "BUX"} -> {total_refs, verified, bux + amount, rogue}
          {_, "ROGUE"} -> {total_refs, verified, bux, rogue + amount}
          {_, _} -> {total_refs, verified, bux, rogue}
        end
        record = {:referral_stats, referrer_id, new_refs, new_verified, new_bux, new_rogue, now}
        :mnesia.dirty_write(record)
    end
  end

  # ----- Query Functions -----

  @doc """
  Get referrer stats for a user.
  """
  def get_referrer_stats(user_id) do
    case :mnesia.dirty_read(:referral_stats, user_id) do
      [{:referral_stats, ^user_id, total_refs, verified, bux, rogue, _updated}] ->
        %{
          total_referrals: total_refs,
          verified_referrals: verified,
          total_bux_earned: bux,
          total_rogue_earned: rogue
        }
      [] ->
        %{
          total_referrals: 0,
          verified_referrals: 0,
          total_bux_earned: 0.0,
          total_rogue_earned: 0.0
        }
    end
  end

  @doc """
  List all referrals for a user. Mnesia-only - no PostgreSQL queries.
  Returns referee wallet addresses directly (use for UI display).
  """
  def list_referrals(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    # Get all referral records where this user is the referrer
    :mnesia.dirty_index_read(:referrals, user_id, :referrer_id)
    |> Enum.sort_by(fn {:referrals, _, _, _, _, referred_at, _} -> referred_at end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {:referrals, referee_id, referrer_id, _, referee_wallet, referred_at, _} ->
      # Check if referee has verified phone (from referral_earnings)
      # Look for phone_verified earnings for this referrer that match this referee's wallet
      phone_verified = :mnesia.dirty_index_read(:referral_earnings, referrer_id, :referrer_id)
      |> Enum.any?(fn record ->
        elem(record, 5) == :phone_verified and elem(record, 4) == referee_wallet  # earning_type and referee_wallet
      end)

      %{
        referee_id: referee_id,
        referee_wallet: referee_wallet,
        referred_at: DateTime.from_unix!(referred_at),
        phone_verified: phone_verified
      }
    end)
  end

  @doc """
  List referral earnings for a user. Mnesia-only - no PostgreSQL queries.
  Wallet addresses are stored directly in earnings records.
  """
  def list_referral_earnings(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    :mnesia.dirty_index_read(:referral_earnings, user_id, :referrer_id)
    |> Enum.sort_by(fn {:referral_earnings, _, _, _, _, _, _, _, _, _, timestamp} -> timestamp end, :desc)
    |> Enum.drop(offset)
    |> Enum.take(limit)
    |> Enum.map(fn {:referral_earnings, id, _referrer_id, _referrer_wallet, referee_wallet, type, amount, token, tx_hash, _commitment, timestamp} ->
      %{
        id: id,
        earning_type: type,
        amount: amount,
        token: token,
        tx_hash: tx_hash,
        timestamp: DateTime.from_unix!(timestamp),
        referee_wallet: referee_wallet  # Wallet stored directly, no DB lookup!
      }
    end)
  end

  # ----- Wallet Lookup Functions -----

  @doc """
  Look up user_id by smart wallet address using existing Mnesia tables.
  Returns {:ok, user_id} or :not_found
  """
  def get_user_id_by_wallet(wallet_address) when is_binary(wallet_address) do
    wallet = String.downcase(wallet_address)

    # First check :referrals table (has referee_wallet index)
    case :mnesia.dirty_index_read(:referrals, wallet, :referee_wallet) do
      [{:referrals, user_id, _, _, _, _, _} | _] -> {:ok, user_id}
      [] ->
        # Fallback: check :referrals by referrer_wallet
        case :mnesia.dirty_index_read(:referrals, wallet, :referrer_wallet) do
          [{:referrals, _, referrer_id, _, _, _, _} | _] -> {:ok, referrer_id}
          [] -> :not_found
        end
    end
  end

  @doc """
  Look up referrer info by referee's wallet address.
  Returns {:ok, %{referrer_id, referrer_wallet}} or :not_found
  """
  def get_referrer_by_referee_wallet(referee_wallet) when is_binary(referee_wallet) do
    wallet = String.downcase(referee_wallet)

    case :mnesia.dirty_index_read(:referrals, wallet, :referee_wallet) do
      [{:referrals, _user_id, referrer_id, referrer_wallet, _, _, _} | _] ->
        {:ok, %{referrer_id: referrer_id, referrer_wallet: referrer_wallet}}
      [] ->
        :not_found
    end
  end

  # ----- Helper Functions -----

  defp mint_referral_reward(earning_id, _referrer_wallet, amount, token, referrer_id, reason) do
    # Always look up fresh wallet from DB instead of using URL param
    fresh_wallet = case Repo.get(User, referrer_id) do
      %User{smart_wallet_address: addr} when is_binary(addr) and addr != "" ->
        String.downcase(addr)
      _ ->
        Logger.warning("[Referrals] No wallet found for referrer #{referrer_id}, skipping mint")
        nil
    end

    if fresh_wallet do
      Task.start(fn ->
        case BuxMinter.mint_bux(fresh_wallet, amount, referrer_id, nil, reason, token) do
          {:ok, response} ->
            tx_hash = response["transactionHash"]
            if tx_hash do
              update_earning_tx_hash(earning_id, tx_hash)
              Logger.info("[Referrals] Updated earning #{earning_id} with tx_hash: #{tx_hash}")
            end

            BuxMinter.sync_user_balances_async(referrer_id, fresh_wallet, force: true)
          {:error, err} ->
            Logger.error("[Referrals] Failed to mint referral reward: #{inspect(err)}")
        end
      end)
    end
  end

  defp update_earning_tx_hash(earning_id, tx_hash) do
    case :mnesia.dirty_read(:referral_earnings, earning_id) do
      [record] ->
        # Record structure: {:referral_earnings, id, referrer_id, referrer_wallet, referee_wallet,
        #                    type, amount, token, tx_hash, commitment_hash, timestamp}
        # tx_hash is at index 8
        #
        # IMPORTANT: referral_earnings is a :bag table, so dirty_write would add a duplicate.
        # We must delete the old record first, then write the updated one.
        :mnesia.dirty_delete_object(record)
        updated_record = put_elem(record, 8, tx_hash)
        :mnesia.dirty_write(updated_record)
      [] ->
        Logger.warning("[Referrals] Could not find earning record #{earning_id} to update tx_hash")
    end
  end

  defp sync_referrer_to_contracts(player_wallet, referrer_wallet) do
    if player_wallet && player_wallet != "" do
      Task.start(fn ->
        case BuxMinter.set_player_referrer(player_wallet, referrer_wallet) do
          {:ok, _} ->
            # Mark as synced in Mnesia
            player_wallet_lower = String.downcase(player_wallet)
            case :mnesia.dirty_index_read(:referrals, player_wallet_lower, :referee_wallet) do
              [record | _] ->
                updated = put_elem(record, 6, true)  # on_chain_synced at index 6
                :mnesia.dirty_write(updated)
              [] -> :ok
            end
          {:error, reason} ->
            Logger.error("[Referrals] Failed to sync referrer to contracts: #{inspect(reason)}")
        end
      end)
    end
  end

  defp broadcast_referral_earning(referrer_id, payload) do
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "referral:#{referrer_id}",
      {:referral_earning, payload}
    )
  end
end
