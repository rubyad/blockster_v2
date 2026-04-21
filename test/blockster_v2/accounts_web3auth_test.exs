defmodule BlocksterV2.AccountsWeb3AuthTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Accounts
  alias BlocksterV2.Accounts.User

  setup do
    # user_betting_stats is a Mnesia table the accounts code writes on signup.
    # Create or clear it before each run so the tests don't bleed state.
    case :mnesia.create_table(:user_betting_stats,
           attributes: [
             :user_id,
             :wallet_address,
             :bux_total_bets,
             :bux_wins,
             :bux_losses,
             :bux_total_wagered,
             :bux_total_winnings,
             :bux_total_losses,
             :bux_net_pnl,
             :rogue_total_bets,
             :rogue_wins,
             :rogue_losses,
             :rogue_total_wagered,
             :rogue_total_winnings,
             :rogue_total_losses,
             :rogue_net_pnl,
             :first_bet_at,
             :last_bet_at,
             :updated_at,
             :onchain_stats_cache
           ],
           ram_copies: [node()],
           type: :set,
           index: [:bux_total_wagered, :rogue_total_wagered]
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :user_betting_stats}} -> :mnesia.clear_table(:user_betting_stats)
    end

    :ok
  end

  defp claims(overrides \\ %{}) do
    Map.merge(
      %{
        solana_pubkey: "FUWYT33RLgmCtGsSHvtv2avKLpDFovFDQSnuGjN5wDyP",
        email: "alice@example.com",
        name: "Alice",
        profile_image: "https://example.com/alice.png",
        verifier: "web3auth",
        aggregate_verifier: "web3auth-auth0-email-passwordless-sapphire-devnet",
        auth_connection: "email_passwordless",
        verifier_id: "alice@example.com",
        user_id: "alice@example.com",
        x_user_id: nil,
        telegram_user_id: nil,
        telegram_username: nil
      },
      overrides
    )
  end

  describe "get_or_create_user_by_web3auth/1" do
    test "creates a new web3auth_email user on first login" do
      assert {:ok, %User{} = user, _session, is_new_user?} =
               Accounts.get_or_create_user_by_web3auth(claims())

      assert is_new_user? == true
      assert user.wallet_address == "FUWYT33RLgmCtGsSHvtv2avKLpDFovFDQSnuGjN5wDyP"
      assert user.auth_method == "web3auth_email"
      assert user.email == "alice@example.com"
      assert user.email_verified == true
      assert user.social_avatar_url == "https://example.com/alice.png"
      assert user.web3auth_verifier == "web3auth"
    end

    test "creates a web3auth_x user with x_user_id populated" do
      assert {:ok, %User{} = user, _session, true} =
               Accounts.get_or_create_user_by_web3auth(
                 claims(%{
                   auth_connection: "twitter",
                   solana_pubkey: "DWY2b8csW3zMnLAso9Aijw7JEuDAGSshnBhrCCKKN5Ua",
                   x_user_id: "1831802560593661952",
                   verifier: "web3auth",
                   aggregate_verifier: "web3auth-auth0-twitter-sapphire-devnet",
                   email: nil
                 })
               )

      assert user.auth_method == "web3auth_x"
      assert user.x_user_id == "1831802560593661952"
      assert user.email_verified == false
    end

    test "creates a web3auth_telegram user with telegram fields" do
      assert {:ok, %User{} = user, _session, true} =
               Accounts.get_or_create_user_by_web3auth(
                 claims(%{
                   auth_connection: "custom",
                   solana_pubkey: "TeleGramPubKey11111111111111111111111111111",
                   verifier: "blockster-telegram",
                   aggregate_verifier: "custom-blockster-telegram",
                   email: nil,
                   telegram_user_id: "12345",
                   telegram_username: "alice_tg"
                 })
               )

      assert user.auth_method == "web3auth_telegram"
      assert user.telegram_user_id == "12345"
      assert user.telegram_username == "alice_tg"
      refute is_nil(user.telegram_connected_at)
    end

    test "returns existing user on repeat login without duplicating" do
      {:ok, _u1, _s1, true} = Accounts.get_or_create_user_by_web3auth(claims())
      {:ok, u2, _s2, is_new_user?} = Accounts.get_or_create_user_by_web3auth(claims())

      assert is_new_user? == false
      assert u2.auth_method == "web3auth_email"
    end

    test "backfills social fields on existing pre-web3auth user" do
      # Simulate a user who logged in via plain wallet connect before
      # web3auth landed. Their social fields should be nil.
      {:ok, pre_existing} =
        Accounts.create_user_from_wallet(%{
          wallet_address: "PreExisting11111111111111111111111111111111",
          username: "oldtimer"
        })

      assert is_nil(pre_existing.social_avatar_url)
      assert is_nil(pre_existing.web3auth_verifier)

      {:ok, updated, _session, is_new_user?} =
        Accounts.get_or_create_user_by_web3auth(
          claims(%{
            solana_pubkey: "PreExisting11111111111111111111111111111111",
            profile_image: "https://example.com/avatar.png"
          })
        )

      assert is_new_user? == false
      assert updated.social_avatar_url == "https://example.com/avatar.png"
      assert updated.web3auth_verifier == "web3auth"
    end

    test "rejects claims missing solana_pubkey" do
      assert {:error, :missing_solana_pubkey} =
               Accounts.get_or_create_user_by_web3auth(claims(%{solana_pubkey: nil}))
    end
  end
end
