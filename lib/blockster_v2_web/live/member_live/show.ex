defmodule BlocksterV2Web.MemberLive.Show do
  use BlocksterV2Web, :live_view

  require Logger

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Accounts
  alias BlocksterV2.BuxMinter
  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.Notifications
  alias BlocksterV2.UnifiedMultiplier
  alias BlocksterV2.RogueMultiplier
  alias BlocksterV2.Social
  alias BlocksterV2.Blog
  alias BlocksterV2.Wallets
  alias BlocksterV2.Referrals

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(active_tab: "activity", time_period: "24h", show_multiplier_dropdown: false)
     |> assign(show_phone_modal: false)
     |> assign(countdown: nil)}
  end

  @impl true
  def handle_params(%{"slug" => slug_or_address} = params, _url, socket) do
    # Allow tab to be set via URL query parameter (e.g., /member/xxx?tab=settings)
    tab_from_url = params["tab"]
    valid_tabs = ["activity", "rogue", "wallet", "refer", "settings", "following", "event", "airdrop"]
    initial_tab = if tab_from_url in valid_tabs, do: tab_from_url, else: socket.assigns[:active_tab] || "activity"

    case Accounts.get_user_by_slug_or_address(slug_or_address) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Member not found")
         |> push_navigate(to: ~p"/")}

      member ->
        # SECURITY: Member page is private - only the owner can view it
        # Redirect to home if trying to view someone else's member page
        is_own_profile = socket.assigns[:current_user] && socket.assigns.current_user.id == member.id

        if !is_own_profile do
          {:noreply,
           socket
           |> put_flash(:error, "You can only view your own member page")
           |> push_navigate(to: ~p"/")}
        else
          # Preload phone_verification association
          member = BlocksterV2.Repo.preload(member, :phone_verification)

          # V2 Unified Multiplier System - refresh from source data to ensure accuracy
          # This recalculates from x_connections, user table, and Mnesia tables (no external API calls)
          unified_multipliers = UnifiedMultiplier.refresh_multipliers(member.id)
          rogue_multiplier_data = RogueMultiplier.calculate_rogue_multiplier(member.id)

          # Legacy multiplier details for backwards compatibility
          multiplier_details = EngagementTracker.get_user_multiplier_details(member.id)

          # Fetch on-chain BUX balance and update Mnesia (async to not block page load)
          maybe_refresh_bux_balance(member)

          # Check if user just signed up
          is_new_user = is_new_user?(member)

          # Load connected wallet and balances (always own profile at this point)
          connected_wallet = Wallets.get_connected_wallet(member.id)
          wallet_balances = if connected_wallet, do: Wallets.get_user_balances(member.id), else: nil
          recent_transfers = Wallets.list_user_transfers(member.id, limit: 10)

          # Auto-reconnect to hardware wallet if user has one connected
          socket = if connected?(socket) && connected_wallet do
            push_event(socket, "auto_reconnect_wallet", %{
              provider: connected_wallet.provider,
              expected_address: connected_wallet.wallet_address
            })
          else
            socket
          end

          # Process pending anonymous claims if connected
          # This will load activities internally after processing claims
          socket = if connected?(socket) do
            process_pending_claims(socket, member)
          else
            socket
            |> assign(:claimed_rewards, [])
            |> assign(:total_claimed, 0)
          end

          # Load activities AFTER processing claims (or load fresh if no claims)
          # If claims were processed, this ensures we get the updated data
          all_activities = load_member_activities(member.id)
          time_period = socket.assigns[:time_period] || "24h"
          filtered_activities = filter_activities_by_period(all_activities, time_period)
          total_bux = calculate_total_bux(filtered_activities)

          # Load referral data
          wallet_address = member.smart_wallet_address
          referral_link = generate_referral_link(wallet_address)
          referral_stats = Referrals.get_referrer_stats(member.id)
          referrals = Referrals.list_referrals(member.id, limit: 20)
          referral_earnings = Referrals.list_referral_earnings(member.id, limit: 50)

          # Subscribe to real-time referral updates
          if connected?(socket) do
            Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "referral:#{member.id}")
          end

          # Following tab: load subscribed hubs
          followed_hubs = Blog.get_user_followed_hubs_enriched(member.id)

          # Settings tab: X connection for Connected Accounts section
          x_connection = Social.get_x_connection_for_user(member.id)

          {:noreply,
           socket
           |> assign(:page_title, member.username || "Member")
           |> assign(:member, member)
           |> assign(:active_tab, initial_tab)
           |> assign(:all_activities, all_activities)
           |> assign(:activities, filtered_activities)
           |> assign(:total_bux, total_bux)
           |> assign(:time_period, time_period)
           # V2 Unified Multiplier System
           |> assign(:unified_multipliers, unified_multipliers)
           |> assign(:rogue_multiplier_data, rogue_multiplier_data)
           |> assign(:overall_multiplier, unified_multipliers.overall_multiplier)
           |> assign(:x_multiplier, unified_multipliers.x_multiplier)
           |> assign(:x_score, unified_multipliers.x_score)
           |> assign(:phone_multiplier, unified_multipliers.phone_multiplier)
           |> assign(:rogue_multiplier, unified_multipliers.rogue_multiplier)
           |> assign(:wallet_multiplier, unified_multipliers.wallet_multiplier)
           # Legacy multiplier details for backwards compatibility
           |> assign(:multiplier_details, multiplier_details)
           # NOTE: Do NOT assign :token_balances here - it's set by BuxBalanceHook from current_user
           # Assigning it here would overwrite the logged-in user's header balances
           |> assign(:is_new_user, is_new_user)
           |> assign(:is_own_profile, is_own_profile)
           |> assign(:connected_wallet, connected_wallet)
           |> assign(:wallet_balances, wallet_balances)
           |> assign(:recent_transfers, recent_transfers)
           |> assign(:pending_transfer, nil)
           |> assign(:transfer_pending, false)
           # Referral system
           |> assign(:referral_link, referral_link)
           |> assign(:referral_stats, referral_stats)
           |> assign(:referrals, referrals)
           |> assign(:referral_earnings, referral_earnings)
           # Following tab
           |> assign(:followed_hubs, followed_hubs)
           # Settings tab
           |> assign(:x_connection, x_connection)
           |> assign(:telegram_connected, member.telegram_user_id != nil)
           |> assign(:telegram_username, member.telegram_username)
           |> assign(:editing_username, false)
           |> assign(:username_form, %{"username" => member.username})}
        end
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> assign(:show_multiplier_dropdown, false)}
  end

  @impl true
  def handle_event("switch_tab_select", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> assign(:show_multiplier_dropdown, false)}
  end

  @impl true
  def handle_event("toggle_multiplier_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_multiplier_dropdown, !socket.assigns.show_multiplier_dropdown)}
  end

  @impl true
  def handle_event("close_multiplier_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_multiplier_dropdown, false)}
  end

  # Following tab - Unfollow hub
  @impl true
  def handle_event("unfollow_hub", %{"hub-id" => hub_id_str}, socket) do
    hub_id = String.to_integer(hub_id_str)
    user_id = socket.assigns.current_user.id

    case Blog.unfollow_hub(user_id, hub_id) do
      {:ok, _} ->
        followed_hubs = Blog.get_user_followed_hubs_enriched(user_id)
        {:noreply,
         socket
         |> assign(:followed_hubs, followed_hubs)
         |> put_flash(:info, "Unfollowed hub")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unfollow hub")}
    end
  end

  # Settings tab - Username editing
  @impl true
  def handle_event("edit_username", _params, socket) do
    {:noreply, assign(socket, :editing_username, true)}
  end

  @impl true
  def handle_event("cancel_edit_username", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_username, false)
     |> assign(:username_form, %{"username" => socket.assigns.member.username})}
  end

  @impl true
  def handle_event("connect_telegram", _params, socket) do
    member = socket.assigns.member
    token = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    case BlocksterV2.Accounts.update_user(member, %{telegram_connect_token: token}) do
      {:ok, _} ->
        bot_url = "https://t.me/BlocksterPostsBot?start=#{token}"
        {:noreply, redirect(socket, external: bot_url)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to generate Telegram link")}
    end
  end

  @impl true
  def handle_event("update_username_form", %{"username" => username}, socket) do
    {:noreply, assign(socket, :username_form, %{"username" => username})}
  end

  @impl true
  def handle_event("save_username", %{"username" => username}, socket) do
    member = socket.assigns.member

    case Accounts.update_user(member, %{username: username}) do
      {:ok, updated_member} ->
        BlocksterV2.UserEvents.track(member.id, "profile_updated", %{field: "username"})
        {:noreply,
         socket
         |> assign(:member, updated_member)
         |> assign(:editing_username, false)
         |> assign(:username_form, %{"username" => updated_member.username})
         |> put_flash(:info, "Username updated successfully!")}

      {:error, changeset} ->
        error_message = cond do
          changeset.errors[:slug] ->
            "This username is already taken (generates the same profile URL as another user). Please choose a different username."
          changeset.errors[:username] ->
            "This username is already taken. Please choose a different one."
          true ->
            "Failed to update username"
        end
        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  @impl true
  def handle_event("set_time_period", %{"period" => period}, socket) do
    filtered_activities = filter_activities_by_period(socket.assigns.all_activities, period)
    total_bux = calculate_total_bux(filtered_activities)

    {:noreply,
     socket
     |> assign(:time_period, period)
     |> assign(:activities, filtered_activities)
     |> assign(:total_bux, total_bux)}
  end

  @impl true
  def handle_event("open_phone_verification", _params, socket) do
    {:noreply, assign(socket, :show_phone_modal, true)}
  end

  # Wallet Connection Events
  @impl true
  def handle_event("connect_" <> provider, _params, socket) when provider in ["metamask", "coinbase", "walletconnect", "phantom"] do
    # Push event to JavaScript hook to initiate wallet connection
    {:noreply, push_event(socket, "connect_wallet", %{provider: provider})}
  end

  @impl true
  def handle_event("wallet_connected", %{"address" => address, "provider" => provider, "chain_id" => chain_id}, socket) do
    user_id = socket.assigns.current_user.id

    # Save connected wallet to database
    case Wallets.connect_wallet(%{
      user_id: user_id,
      wallet_address: address,
      provider: provider,
      chain_id: chain_id
    }) do
      {:ok, connected_wallet} ->
        # Trigger balance fetch immediately after connection
        socket_with_wallet = assign(socket, :connected_wallet, connected_wallet)

        {:noreply,
         socket_with_wallet
         |> push_event("fetch_hardware_wallet_balances", %{address: address})
         |> put_flash(:info, "Wallet connected successfully! Fetching balances...")}

      {:error, changeset} ->
        error_msg = case changeset.errors do
          [{:user_id, {"can only connect one wallet at a time", _}}] ->
            "You already have a wallet connected. Please disconnect it first."
          _ ->
            "Failed to connect wallet. Please try again."
        end

        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  @impl true
  def handle_event("wallet_connection_error", %{"error" => error, "provider" => _provider}, socket) do
    {:noreply, put_flash(socket, :error, "Connection failed: #{error}")}
  end

  @impl true
  def handle_event("disconnect_wallet", _params, socket) do
    user_id = socket.assigns.current_user.id

    case Wallets.disconnect_wallet(user_id) do
      {:ok, _} ->
        # Clear balances from Mnesia
        Wallets.clear_balances(user_id)

        # Push event to JavaScript to disconnect wallet on frontend
        {:noreply,
         socket
         |> assign(:connected_wallet, nil)
         |> assign(:wallet_balances, nil)
         |> push_event("disconnect_wallet", %{})
         |> put_flash(:info, "Wallet disconnected successfully")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No wallet connected")}
    end
  end

  @impl true
  def handle_event("wallet_disconnected", _params, socket) do
    # JavaScript confirmation that wallet was disconnected on frontend
    # The actual database disconnect already happened in "disconnect_wallet" event
    {:noreply, socket}
  end

  @impl true
  def handle_event("copy_address", _params, socket) do
    # JavaScript will handle the actual copying via clipboard API
    {:noreply, put_flash(socket, :info, "Address copied to clipboard!")}
  end

  # Balance Fetching Events
  @impl true
  def handle_event("refresh_balances", _params, socket) do
    case socket.assigns[:connected_wallet] do
      nil ->
        {:noreply, put_flash(socket, :error, "No wallet connected")}

      wallet ->
        {:noreply,
         socket
         |> push_event("fetch_hardware_wallet_balances", %{address: wallet.wallet_address})
         |> put_flash(:info, "Refreshing balances...")}
    end
  end

  @impl true
  def handle_event("hardware_wallet_balances_fetched", %{"balances" => balances}, socket) do
    user_id = socket.assigns.current_user.id
    wallet = socket.assigns.connected_wallet

    # Convert string keys to atoms for the balance maps
    balances_with_atoms = Enum.map(balances, fn balance ->
      %{
        symbol: balance["symbol"],
        chain_id: balance["chain_id"],
        balance: balance["balance"],
        address: balance["address"],
        decimals: balance["decimals"]
      }
    end)

    # Store balances in Mnesia
    case Wallets.store_balances(user_id, wallet.wallet_address, balances_with_atoms) do
      {:ok, count} ->
        # Update last_balance_sync_at in Postgres
        Wallets.mark_balance_synced(user_id)

        # Get grouped balances for display
        grouped_balances = Wallets.get_user_balances(user_id)

        {:noreply,
         socket
         |> assign(:wallet_balances, grouped_balances)
         |> put_flash(:info, "Balances refreshed successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to store balances: #{reason}")}
    end
  end

  @impl true
  def handle_event("balance_fetch_error", %{"error" => error}, socket) do
    {:noreply, put_flash(socket, :error, "Failed to fetch balances: #{error}")}
  end

  # Auto-reconnect Events
  @impl true
  def handle_event("wallet_reconnected", %{"address" => address, "provider" => _provider}, socket) do
    # Wallet successfully reconnected - trigger balance fetch
    {:noreply, push_event(socket, "fetch_hardware_wallet_balances", %{address: address})}
  end

  @impl true
  def handle_event("wallet_reconnect_failed", %{"provider" => _provider, "error" => _error}, socket) do
    # Auto-reconnect failed silently - user can manually reconnect if needed
    # Don't show error message since this was an automatic background operation
    {:noreply, socket}
  end

  @impl true
  def handle_event("wallet_address_mismatch", %{"expected" => expected, "actual" => actual, "provider" => provider}, socket) do
    user_id = socket.assigns.current_user.id

    # Address mismatch - disconnect from database and show warning
    Wallets.disconnect_wallet(user_id)
    Wallets.clear_balances(user_id)

    {:noreply,
     socket
     |> assign(:connected_wallet, nil)
     |> assign(:wallet_balances, nil)
     |> put_flash(:error, "Wallet address mismatch detected. Your #{String.capitalize(provider)} wallet address changed from #{String.slice(expected, 0..5)}...#{String.slice(expected, -4..-1)} to #{String.slice(actual, 0..5)}...#{String.slice(actual, -4..-1)}. Please reconnect your wallet.")}
  end

  # Transfer initiation handlers

  def handle_event("initiate_transfer_to_blockster", %{"amount" => amount_str}, socket) do
    user = socket.assigns.current_user
    connected_wallet = socket.assigns.connected_wallet

    if connected_wallet do
      case Float.parse(amount_str) do
        {amount, _} when amount > 0 ->
          # Trigger JavaScript to execute transfer from hardware wallet
          {:noreply,
           push_event(socket, "transfer_to_blockster", %{
             amount: amount,
             blockster_wallet: user.smart_wallet_address
           })}

        _ ->
          {:noreply, put_flash(socket, :error, "Invalid amount")}
      end
    else
      {:noreply, put_flash(socket, :error, "No wallet connected")}
    end
  end

  def handle_event("initiate_transfer_from_blockster", %{"amount" => amount_str}, socket) do
    user = socket.assigns.current_user
    connected_wallet = socket.assigns.connected_wallet

    if connected_wallet do
      case Float.parse(amount_str) do
        {amount, _} when amount > 0 ->
          # Check Blockster wallet has sufficient balance
          blockster_rogue = EngagementTracker.get_user_token_balances(user.id)["ROGUE"] || 0.0

          if amount <= blockster_rogue do
            # Set pending state immediately for UI feedback, then trigger JavaScript
            {:noreply,
             socket
             |> assign(:transfer_pending, true)
             |> push_event("transfer_from_blockster", %{
               amount: amount,
               to_address: connected_wallet.wallet_address,
               from_address: user.smart_wallet_address
             })}
          else
            {:noreply, put_flash(socket, :error, "Insufficient ROGUE balance in Blockster wallet")}
          end

        _ ->
          {:noreply, put_flash(socket, :error, "Invalid amount")}
      end
    else
      {:noreply, put_flash(socket, :error, "No wallet connected")}
    end
  end

  # Transfer event handlers

  def handle_event("transfer_submitted", %{
    "tx_hash" => tx_hash,
    "amount" => amount,
    "from_address" => from_address,
    "to_address" => to_address,
    "direction" => direction,
    "token" => token,
    "chain_id" => chain_id
  }, socket) do
    user_id = socket.assigns.current_user.id

    # Create transfer record in database
    case Wallets.create_transfer(%{
      user_id: user_id,
      from_address: from_address,
      to_address: to_address,
      amount: Decimal.new(to_string(amount)),
      token_symbol: token,
      chain_id: chain_id,
      direction: direction,
      tx_hash: tx_hash,
      status: "pending"
    }) do
      {:ok, transfer} ->
        Logger.info("[MemberLive] Transfer submitted: #{tx_hash} (#{direction})")

        {:noreply,
         socket
         |> put_flash(:info, "Transfer of #{amount} #{token} submitted. Waiting for confirmation...")
         |> assign(:pending_transfer, transfer)
         |> assign(:transfer_pending, false)}

      {:error, changeset} ->
        Logger.error("[MemberLive] Failed to create transfer record: #{inspect(changeset)}")
        {:noreply,
         socket
         |> put_flash(:error, "Failed to record transfer")
         |> assign(:transfer_pending, false)}
    end
  end

  def handle_event("transfer_confirmed", %{
    "tx_hash" => tx_hash,
    "block_number" => block_number,
    "gas_used" => gas_used,
    "amount" => amount,
    "direction" => direction,
    "status" => status
  }, socket) do
    user_id = socket.assigns.current_user.id

    # Update transfer status in database
    case Wallets.confirm_transfer(tx_hash, block_number) do
      {:ok, _transfer} ->
        Logger.info("[MemberLive] Transfer confirmed: #{tx_hash} at block #{block_number}")

        # Trigger balance refresh for both hardware wallet and Blockster wallet
        if socket.assigns.connected_wallet do
          # This will fetch fresh balances from blockchain and update Mnesia
          send(self(), :refresh_hardware_balances)
        end

        # Also refresh Blockster wallet balance from blockchain
        send(self(), :refresh_blockster_balance)

        # Reload transfer history
        recent_transfers = Wallets.list_user_transfers(user_id, limit: 10)

        {:noreply,
         socket
         |> put_flash(:info, "Transfer confirmed! #{amount} ROGUE transferred successfully.")
         |> assign(:pending_transfer, nil)
         |> assign(:transfer_pending, false)
         |> assign(:recent_transfers, recent_transfers)}

      {:error, :not_found} ->
        Logger.warning("[MemberLive] Transfer not found: #{tx_hash}")
        {:noreply, socket}
    end
  end

  def handle_event("transfer_error", %{"error" => error, "direction" => direction}, socket) do
    Logger.error("[MemberLive] Transfer failed (#{direction}): #{error}")

    {:noreply,
     socket
     |> put_flash(:error, "Transfer failed: #{error}")
     |> assign(:pending_transfer, nil)
     |> assign(:transfer_pending, false)}
  end

  # Referral Events

  @impl true
  def handle_event("copy_referral_link", _params, socket) do
    referral_link = socket.assigns.referral_link
    {:noreply, push_event(socket, "copy_to_clipboard", %{text: referral_link})}
  end

  @impl true
  def handle_event("load_more_earnings", _params, socket) do
    current_earnings = socket.assigns.referral_earnings
    user_id = socket.assigns.member.id
    offset = length(current_earnings)

    more_earnings = Referrals.list_referral_earnings(user_id, limit: 50, offset: offset)

    if Enum.empty?(more_earnings) do
      {:reply, %{end_reached: true}, socket}
    else
      {:noreply, assign(socket, :referral_earnings, current_earnings ++ more_earnings)}
    end
  end

  @impl true
  def handle_info({:referral_earning, earning}, socket) do
    current_earnings = socket.assigns.referral_earnings
    current_stats = socket.assigns.referral_stats

    # Convert earning to map format
    new_earning = %{
      id: Ecto.UUID.generate(),
      earning_type: earning.type,
      amount: earning.amount,
      token: earning.token,
      tx_hash: Map.get(earning, :tx_hash),
      timestamp: DateTime.from_unix!(earning.timestamp),
      referee_wallet: earning.referee_wallet
    }

    # Prepend new earning to list
    updated_earnings = [new_earning | current_earnings]

    # Update stats
    updated_stats = case earning.token do
      "BUX" ->
        %{current_stats | total_bux_earned: current_stats.total_bux_earned + earning.amount}
      "ROGUE" ->
        %{current_stats | total_rogue_earned: current_stats.total_rogue_earned + earning.amount}
      _ ->
        current_stats
    end

    {:noreply,
     socket
     |> assign(:referral_earnings, updated_earnings)
     |> assign(:referral_stats, updated_stats)}
  end

  @impl true
  def handle_info({:close_phone_verification_modal}, socket) do
    {:noreply, assign(socket, :show_phone_modal, false)}
  end

  @impl true
  def handle_info({:refresh_user_data}, socket) do
    # Reload member data to get updated phone verification status
    member = Accounts.get_user(socket.assigns.member.id)
    member = BlocksterV2.Repo.preload(member, :phone_verification, force: true)

    # Recalculate multipliers since phone verification affects them
    unified_multipliers = UnifiedMultiplier.get_user_multipliers(member.id)
    rogue_multiplier_data = RogueMultiplier.calculate_rogue_multiplier(member.id)

    {:noreply,
     socket
     |> assign(:member, member)
     |> assign(:unified_multipliers, unified_multipliers)
     |> assign(:rogue_multiplier_data, rogue_multiplier_data)
     |> assign(:overall_multiplier, unified_multipliers.overall_multiplier)
     |> assign(:x_multiplier, unified_multipliers.x_multiplier)
     |> assign(:x_score, unified_multipliers.x_score)
     |> assign(:phone_multiplier, unified_multipliers.phone_multiplier)
     |> assign(:rogue_multiplier, unified_multipliers.rogue_multiplier)
     |> assign(:wallet_multiplier, unified_multipliers.wallet_multiplier)}
  end

  @impl true
  def handle_info({:redirect_to_home}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:countdown_tick, seconds}, socket) do
    if seconds > 0 do
      Process.send_after(self(), {:countdown_tick, seconds - 1}, 1000)
      {:noreply, assign(socket, :countdown, seconds)}
    else
      {:noreply, assign(socket, :countdown, nil)}
    end
  end

  @impl true
  def handle_info(:refresh_hardware_balances, socket) do
    # Trigger JavaScript to refresh hardware wallet balances
    {:noreply, push_event(socket, "refresh_balances_after_transfer", %{})}
  end

  def handle_info(:refresh_blockster_balance, socket) do
    user_id = socket.assigns.current_user.id
    wallet_address = socket.assigns.current_user.smart_wallet_address

    Logger.info("[MemberLive] Refreshing Blockster balance for wallet: #{wallet_address}")

    # Fetch fresh ROGUE balance from blockchain via BUX Minter (use aggregated endpoint which includes ROGUE)
    case BuxMinter.get_aggregated_balances(wallet_address) do
      {:ok, %{balances: balances}} ->
        Logger.info("[MemberLive] BUX Minter returned balances: #{inspect(balances)}")
        rogue_balance = Map.get(balances, "ROGUE", 0.0)
        Logger.info("[MemberLive] Extracted ROGUE balance: #{rogue_balance}")
        EngagementTracker.update_user_rogue_balance(user_id, wallet_address, rogue_balance, :rogue_chain)
        Logger.info("[MemberLive] Updated Mnesia with ROGUE balance: #{rogue_balance}")

        # Refresh token_balances from Mnesia and update socket
        token_balances = EngagementTracker.get_user_token_balances(user_id)
        Logger.info("[MemberLive] Refreshed token_balances from Mnesia: #{inspect(token_balances)}")
        {:noreply, assign(socket, :token_balances, token_balances)}

      {:error, reason} ->
        Logger.error("[MemberLive] Failed to fetch ROGUE balance: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  # Load activities from Mnesia tables (post reads, video watches, X shares) and notifications
  defp load_member_activities(user_id) do
    # Get post read rewards from Mnesia
    read_activities = EngagementTracker.get_all_user_post_rewards(user_id)

    # Get video watch rewards from Mnesia
    video_activities = get_user_video_activities(user_id)

    # Get X share rewards from Mnesia
    share_activities = Social.list_user_share_rewards(user_id)

    # Get notification activities from PostgreSQL
    notification_activities = Notifications.list_notification_activities(user_id)

    # Combine and sort by timestamp (most recent first)
    (enrich_read_activities_with_post_info(read_activities) ++
     enrich_read_activities_with_post_info(video_activities) ++
     share_activities ++
     notification_activities)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  # Get user video watch activities from Mnesia
  defp get_user_video_activities(user_id) do
    # Pattern matches on user_id at index 1
    pattern = {:user_video_engagement, :_, user_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

    records = :mnesia.dirty_match_object(pattern)

    # Convert records to activity list
    records
    |> Enum.filter(fn record ->
      total_bux = elem(record, 8)  # total_bux_earned at index 8
      total_bux && total_bux > 0
    end)
    |> Enum.flat_map(fn record ->
      post_id = elem(record, 3)
      total_bux = elem(record, 8)
      video_tx_ids = elem(record, 16)  # List of transaction maps
      updated_at = elem(record, 15)

      # Convert unix timestamp to DateTime
      timestamp = DateTime.from_unix!(updated_at)

      # Get first transaction hash if available
      tx_id = case video_tx_ids do
        [%{tx_hash: hash} | _] -> hash
        _ -> nil
      end

      [%{
        type: :video,
        label: "Video Watched",
        amount: total_bux,
        post_id: post_id,
        tx_id: tx_id,
        timestamp: timestamp
      }]
    end)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  # Add post title/slug to read and video activities
  defp enrich_read_activities_with_post_info(activities) do
    # Get all unique post IDs from read activities
    post_ids =
      activities
      |> Enum.map(& &1.post_id)
      |> Enum.uniq()

    # Fetch posts
    posts = Blog.get_posts_by_ids(post_ids)
    posts_map = Map.new(posts, fn post -> {post.id, post} end)

    # Enrich read activities with post info (always BUX - hub tokens removed)
    Enum.map(activities, fn activity ->
      post = Map.get(posts_map, activity.post_id)

      Map.merge(activity, %{
        post_title: post && post.title,
        post_slug: post && post.slug,
        token: "BUX"
      })
    end)
  end

  defp filter_activities_by_period(activities, period) do
    cutoff = get_cutoff_time(period)

    case cutoff do
      nil -> activities
      time -> Enum.filter(activities, fn a -> DateTime.compare(a.timestamp, time) != :lt end)
    end
  end

  defp get_cutoff_time("24h"), do: DateTime.add(DateTime.utc_now(), -24, :hour)
  defp get_cutoff_time("7d"), do: DateTime.add(DateTime.utc_now(), -7, :day)
  defp get_cutoff_time("30d"), do: DateTime.add(DateTime.utc_now(), -30, :day)
  defp get_cutoff_time("all"), do: nil

  defp calculate_total_bux(activities) do
    activities
    |> Enum.filter(fn a -> (a[:token] || "BUX") == "BUX" end)
    |> Enum.map(& &1.amount)
    |> Enum.filter(&is_number/1)
    |> Enum.sum()
  end

  # Fetch all on-chain token balances via BalanceAggregator and update Mnesia (async)
  defp maybe_refresh_bux_balance(%{id: user_id, smart_wallet_address: wallet})
       when is_binary(wallet) and wallet != "" do
    BuxMinter.sync_user_balances_async(user_id, wallet)
  end

  defp maybe_refresh_bux_balance(_member), do: :ok

  # Check if user is new (account created within last 30 minutes for claim processing)
  defp is_new_user?(user) do
    account_age_seconds = NaiveDateTime.diff(NaiveDateTime.utc_now(), user.inserted_at, :second)
    account_age_seconds < 300  # 5 minutes
  end

  # Process pending anonymous claims from localStorage
  defp process_pending_claims(socket, member) do
    require Logger

    try do
      pending_claims_raw = get_connect_params(socket)["pending_claims"]

      # Convert map to list if needed (JavaScript sends array as map with numeric keys)
      pending_claims = case pending_claims_raw do
        claims when is_map(claims) -> Map.values(claims)
        claims when is_list(claims) -> claims
        _ -> []
      end

      Logger.info("Processing claims for user #{member.id}: #{length(pending_claims)} claims, is_new_user: #{is_new_user?(member)}")
      Logger.debug("Pending claims data: #{inspect(pending_claims)}")

      if length(pending_claims) > 0 && is_new_user?(member) do
        # Process each claim
        results = Enum.map(pending_claims, fn claim ->
          process_single_claim(member, claim)
        end)

        # Filter successful claims
        successful_claims = Enum.filter(results, fn
          {:ok, _, _} -> true
          _ -> false
        end)

        if length(successful_claims) > 0 do
          total_claimed = successful_claims
            |> Enum.map(fn {:ok, amount, _type} -> amount end)
            |> Enum.sum()

          # Determine claim types for message
          claim_types = successful_claims
            |> Enum.map(fn {:ok, _amount, type} -> type end)
            |> Enum.uniq()

          claim_type_text = cond do
            Enum.member?(claim_types, "read") && Enum.member?(claim_types, "video") ->
              "reading and watching videos"
            Enum.member?(claim_types, "video") ->
              "watching videos"
            true ->
              "reading"
          end

          # Reload activities to show newly claimed rewards
          all_activities = load_member_activities(member.id)
          time_period = socket.assigns[:time_period] || "24h"
          filtered_activities = filter_activities_by_period(all_activities, time_period)
          total_bux = calculate_total_bux(filtered_activities)

          socket
          |> assign(:claimed_rewards, successful_claims)
          |> assign(:total_claimed, total_claimed)
          |> assign(:claim_type_text, claim_type_text)
          |> assign(:all_activities, all_activities)
          |> assign(:activities, filtered_activities)
          |> assign(:total_bux, total_bux)
          |> put_flash(:info, "Successfully claimed #{Float.round(total_claimed, 2)} BUX from #{length(successful_claims)} post(s)!")
        else
          Logger.warning("No successful claims for user #{member.id}")
          socket
          |> assign(:claimed_rewards, [])
          |> assign(:total_claimed, 0)
          |> assign(:claim_type_text, nil)
        end
      else
        socket
        |> assign(:claimed_rewards, [])
        |> assign(:total_claimed, 0)
        |> assign(:claim_type_text, nil)
      end
    rescue
      e ->
        Logger.error("Error processing pending claims for user #{member.id}: #{inspect(e)}")
        Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")

        socket
        |> assign(:claimed_rewards, [])
        |> assign(:total_claimed, 0)
        |> assign(:claim_type_text, nil)
        |> put_flash(:error, "An error occurred while processing your rewards. Please contact support.")
    end
  end

  # Process a single anonymous claim
  defp process_single_claim(user, claim) do
    require Logger

    # Safely extract and convert post_id
    post_id = try do
      case claim["postId"] do
        id when is_integer(id) -> id
        id when is_binary(id) -> String.to_integer(id)
        _ -> nil
      end
    rescue
      e ->
        Logger.error("Error converting postId: #{inspect(e)}, claim: #{inspect(claim)}")
        nil
    end

    # Safely extract claim type
    claim_type = claim["type"]

    # Safely extract and convert earned_amount
    earned_amount = try do
      case claim["earnedAmount"] do
        amount when is_float(amount) -> amount
        amount when is_integer(amount) -> amount * 1.0
        amount when is_binary(amount) -> String.to_float(amount)
        _ -> nil
      end
    rescue
      e ->
        Logger.error("Error converting earnedAmount: #{inspect(e)}, claim: #{inspect(claim)}")
        nil
    end

    Logger.info("Processing claim for user #{user.id}: type=#{claim_type}, post_id=#{post_id}, amount=#{earned_amount}")

    # Return early if any required field is missing
    if is_nil(post_id) or is_nil(claim_type) or is_nil(earned_amount) do
      Logger.error("Missing required fields in claim: #{inspect(claim)}")
      {:error, "Invalid claim data"}
    else
      wallet_address = user.smart_wallet_address

      # Check if user already received reward for this post
      already_rewarded = already_rewarded?(user.id, post_id, claim_type)
      Logger.info("Already rewarded check for user #{user.id}, post #{post_id}, type #{claim_type}: #{already_rewarded}")

      if already_rewarded do
        {:error, "Already rewarded for this post"}
      else
        if wallet_address && wallet_address != "" do
          case claim_type do
            "read" ->
              # Mint BUX for reading
              case BuxMinter.mint_bux(wallet_address, earned_amount, user.id, post_id, :read, "BUX") do
                {:ok, %{"transactionHash" => tx_hash}} ->
                  # Record in Mnesia with transaction hash
                  EngagementTracker.record_read_reward(user.id, post_id, earned_amount, tx_hash)
                  # Deduct from pool
                  EngagementTracker.deduct_from_pool_guaranteed(post_id, earned_amount)
                  {:ok, earned_amount, "read"}

                {:error, reason} ->
                  {:error, reason}
              end

            "video" ->
              # Mint BUX for video watching
              case BuxMinter.mint_bux(wallet_address, earned_amount, user.id, post_id, :video_watch, "BUX") do
                {:ok, %{"transactionHash" => tx_hash}} ->
                  # Get earnable_time from claim (stored at root level, not in metrics)
                  earnable_time = claim["earnableTime"] || 0

                  # First ensure video engagement record exists
                  EngagementTracker.record_video_view(user.id, post_id)

                  # Then update with the session data
                  EngagementTracker.update_video_engagement_session(user.id, post_id, %{
                    session_bux: earned_amount,
                    session_earnable_time: earnable_time,
                    tx_hash: tx_hash,
                    new_high_water_mark: earnable_time  # Use earnable time as HWM since we watched that much
                  })

                  # Deduct from pool (same as read rewards)
                  EngagementTracker.deduct_from_pool_guaranteed(post_id, earned_amount)

                  {:ok, earned_amount, "video"}

                {:error, reason} ->
                  {:error, reason}
              end

            _ ->
              {:error, "Unknown claim type"}
          end
        else
          {:error, "No wallet address"}
        end
      end
    end
  end

  # Check if user already received a reward for this post
  defp already_rewarded?(user_id, post_id, claim_type) do
    case claim_type do
      "read" ->
        # Check user_post_rewards table for read rewards
        case :mnesia.dirty_read({:user_post_rewards, {user_id, post_id}}) do
          [_record] -> true
          [] -> false
        end

      "video" ->
        # Check user_video_engagement table for video rewards
        case :mnesia.dirty_read({:user_video_engagement, {user_id, post_id}}) do
          [record] ->
            # Check if total_bux_earned field has value (index 8)
            total_bux = elem(record, 8)
            total_bux != nil && total_bux > 0

          [] ->
            false
        end

      _ ->
        false
    end
  end

  # Referral Helper Functions

  defp generate_referral_link(wallet_address) when is_binary(wallet_address) do
    base_url = BlocksterV2Web.Endpoint.url()
    "#{base_url}/?ref=#{wallet_address}"
  end
  defp generate_referral_link(_), do: nil

  def format_referral_number(number) when is_float(number) do
    if number == trunc(number) do
      Integer.to_string(trunc(number))
    else
      :erlang.float_to_binary(number, decimals: 2)
    end
  end
  def format_referral_number(number) when is_integer(number), do: Integer.to_string(number)
  def format_referral_number(_), do: "0"

  def truncate_wallet(nil), do: "-"
  def truncate_wallet(wallet) when is_binary(wallet) and byte_size(wallet) > 10 do
    "#{String.slice(wallet, 0..5)}...#{String.slice(wallet, -4..-1)}"
  end
  def truncate_wallet(wallet), do: wallet

  def earning_type_label(:signup), do: "Signup"
  def earning_type_label(:phone_verified), do: "Phone Verified"
  def earning_type_label(:bux_bet_loss), do: "BUX Bet"
  def earning_type_label(:rogue_bet_loss), do: "ROGUE Bet"
  def earning_type_label(:shop_purchase), do: "Shop Purchase"
  def earning_type_label(_), do: "Other"

  def earning_type_style(:signup), do: "bg-green-100 text-green-800"
  def earning_type_style(:phone_verified), do: "bg-blue-100 text-blue-800"
  def earning_type_style(:bux_bet_loss), do: "bg-purple-100 text-purple-800"
  def earning_type_style(:rogue_bet_loss), do: "bg-indigo-100 text-indigo-800"
  def earning_type_style(:shop_purchase), do: "bg-orange-100 text-orange-800"
  def earning_type_style(_), do: "bg-gray-100 text-gray-800"

  def format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  def is_recent_earning?(datetime) do
    now = DateTime.utc_now()
    DateTime.diff(now, datetime, :second) < 300  # 5 minutes
  end

  defp format_amount(amount) do
    float =
      cond do
        is_struct(amount, Decimal) -> Decimal.to_float(amount)
        is_number(amount) -> amount * 1.0
        true -> 0.0
      end

    [whole, frac] = :erlang.float_to_binary(float, decimals: 2) |> String.split(".")

    formatted =
      whole
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    "#{formatted}.#{frac}"
  end
end
