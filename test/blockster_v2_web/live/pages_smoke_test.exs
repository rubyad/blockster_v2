defmodule BlocksterV2Web.PagesSmokeTest do
  @moduledoc """
  Cross-cutting smoke + stress tests — load every public redesign page as
  anonymous / wallet / web3auth users and verify nothing crashes. Catches
  the class of bugs where a template calls a helper that raises on an
  input type the helper doesn't handle (integer vs float, nil, etc).

  This file exists because the page-specific test files use exact-string
  assertions that drift with copy changes. These tests DON'T assert copy
  — they only assert "the LiveView mounts + renders without raising".

  When a new page is added to :redesign live_session, add it to @pages.
  """

  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Repo

  # Pages mounted in `:redesign` live_session with no required params.
  @pages [
    {"/", "home"},
    {"/hubs", "hubs"},
    {"/play", "play"},
    {"/pool", "pool"},
    {"/pool/sol", "pool detail SOL"},
    {"/pool/bux", "pool detail BUX"},
    {"/airdrop", "airdrop"},
    {"/shop", "shop"},
    {"/cart", "cart"},
    {"/wallet", "wallet"},
    {"/notifications", "notifications"},
    {"/notifications/settings", "notification settings"},
    {"/media-kit", "media kit"},
    {"/privacy", "privacy"},
    {"/terms", "terms"},
    {"/cookies", "cookies"}
  ]

  setup :setup_mnesia

  setup do
    System.put_env("WALLET_SELF_CUSTODY_ENABLED", "true")
    on_exit(fn -> System.delete_env("WALLET_SELF_CUSTODY_ENABLED") end)
    :ok
  end

  # Production pages depend on several Mnesia tables. In production these are
  # always live; in the test env (GenServers disabled) they must be created
  # before a page can mount. This mirrors setup_mnesia in the airdrop test
  # but adds the pool + shop tables the other pages need.
  defp setup_mnesia(_ctx) do
    :mnesia.start()

    tables = [
      {:user_solana_balances, [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance]},
      {:user_bux_balances,
       [:user_id, :user_smart_wallet, :updated_at, :aggregate_bux_balance, :bux_balance,
        :moonbux_balance, :neobux_balance, :roguebux_balance, :flarebux_balance, :nftbux_balance,
        :nolchabux_balance, :solbux_balance, :spacebux_balance, :tronbux_balance, :tranbux_balance]},
      {:user_rogue_balances,
       [:user_id, :user_smart_wallet, :updated_at, :rogue_balance_rogue_chain,
        :rogue_balance_arbitrum]},
      {:shop_product_slots, [:slot_number, :product_id]},
      {:user_pool_positions,
       [:id, :user_id, :vault_type, :total_cost, :total_lp, :realized_gain,
        :updated_at]},
      {:token_prices,
       [:token_id, :symbol, :usd_price, :usd_24h_change, :last_updated]},
      {:unified_multipliers_v2,
       [:user_id, :x_score, :x_multiplier, :phone_multiplier, :sol_multiplier,
        :email_multiplier, :overall_multiplier, :last_updated, :created_at]},
      {:user_lp_balances,
       [:user_id, :wallet_address, :updated_at, :bsol_balance, :bbux_balance]},
      # Referrals.get_referrer_stats/1 is called on mount of
      # /notifications/referrals and /member/:slug; without these tables
      # the mount raises. In production the MnesiaInitializer GenServer
      # creates them; in test env GenServers are off so we set them up
      # inline. Attribute lists must match mnesia_initializer.ex exactly.
      {:referral_stats,
       [:user_id, :total_referrals, :verified_referrals, :total_bux_earned,
        :total_rogue_earned, :updated_at]},
      {:referral_earnings,
       [:id, :referrer_id, :referrer_wallet, :referee_wallet, :earning_type,
        :amount, :token, :tx_hash, :commitment_hash, :timestamp]}
    ]

    for {table, attrs} <- tables do
      opts =
        [attributes: attrs, type: table_type(table), ram_copies: [node()]] ++
          case table_indexes(table) do
            [] -> []
            idx -> [index: idx]
          end

      case :mnesia.create_table(table, opts) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, _}} -> :ok
        {:aborted, other} -> raise "Mnesia table creation failed: #{inspect(other)}"
      end
    end

    :ok
  end

  # referral_earnings is a bag in production with an index on referrer_id —
  # Referrals.list_referral_earnings/2 uses it. Every other table here is
  # the default `:set` with no secondary indexes.
  defp table_type(:referral_earnings), do: :bag
  defp table_type(_), do: :set

  # Must mirror mnesia_initializer.ex — referral_earnings has both
  # :referrer_id (for list_referral_earnings) and :commitment_hash (for
  # dedup in record_bet_loss_earning) indexes. Missing :commitment_hash
  # was the root cause of a cascade of ReferralsTest failures when this
  # table was created here first.
  defp table_indexes(:referral_earnings), do: [:referrer_id, :commitment_hash]
  defp table_indexes(_), do: []

  defp rand_pubkey do
    :crypto.strong_rand_bytes(32)
    |> Base.encode32(case: :lower, padding: false)
    |> String.replace(~r/[0il]/, "A")
    |> String.slice(0, 44)
  end

  defp rand_evm do
    "0x" <> (:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower))
  end

  defp create_web3auth_user do
    unique_id = System.unique_integer([:positive])

    attrs = %{
      "wallet_address" => rand_pubkey(),
      "email" => "smoke_w3a_#{unique_id}@example.com",
      "username" => "smokew3a#{unique_id}",
      "auth_method" => "web3auth_email"
    }

    User.web3auth_registration_changeset(attrs) |> Repo.insert!()
  end

  defp create_wallet_user do
    unique_id = System.unique_integer([:positive])

    %User{}
    |> User.changeset(%{
      wallet_address: rand_evm(),
      email: "smoke_wallet_#{unique_id}@example.com",
      username: "smokewallet#{unique_id}",
      auth_method: "wallet"
    })
    |> Repo.insert!()
  end

  # ── Anonymous visitor ──────────────────────────────────────────

  for {path, name} <- @pages do
    # /wallet requires auth — anon users get redirected. Skip the assert-renders
    # check for it; anon redirect is the correct behavior.
    unless path == "/wallet" do
      test "anonymous can reach #{name} (#{path}) without crashing", %{conn: conn} do
        case live(conn, unquote(path)) do
          {:ok, _view, _html} ->
            :ok

          {:error, {:live_redirect, _}} ->
            :ok

          {:error, {:redirect, _}} ->
            :ok

          other ->
            flunk("Expected page #{unquote(name)} to mount or redirect, got: #{inspect(other)}")
        end
      end
    end
  end

  # ── Signed-in: Web3Auth user ───────────────────────────────────

  for {path, name} <- @pages do
    test "web3auth user can reach #{name} (#{path}) without crashing", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      case live(conn, unquote(path)) do
        {:ok, _view, _html} -> :ok
        {:error, {:live_redirect, _}} -> :ok
        {:error, {:redirect, _}} -> :ok
        other -> flunk("Expected #{unquote(name)} to mount or redirect, got: #{inspect(other)}")
      end
    end
  end

  # ── Signed-in: wallet user ─────────────────────────────────────

  for {path, name} <- @pages do
    test "wallet user can reach #{name} (#{path}) without crashing", %{conn: conn} do
      user = create_wallet_user()
      conn = log_in_user(conn, user)

      case live(conn, unquote(path)) do
        {:ok, _view, _html} -> :ok
        {:error, {:live_redirect, _}} -> :ok
        {:error, {:redirect, _}} -> :ok
        other -> flunk("Expected #{unquote(name)} to mount or redirect, got: #{inspect(other)}")
      end
    end
  end

  # ── Format-helper crash class (exercise the render path) ──────

  describe "header renders with edge-case balance values" do
    # BlocksterV2Web.DesignSystem.header is rendered on every redesign page.
    # Its helpers format BUX/SOL balances. A crash in any helper crashes
    # every page at once — this block verifies edge-case inputs don't.
    for amount <- [0, 0.0, 1_000_000, 0.00001, 1234.56, 0.5, 1.0] do
      test "header renders with BUX balance = #{amount}", %{conn: conn} do
        user = create_web3auth_user()
        conn = log_in_user(conn, user)
        {:ok, view, _html} = live(conn, ~p"/")

        :sys.replace_state(view.pid, fn state ->
          assigns = Map.put(state.socket.assigns, :bux_balance, unquote(amount))
          %{state | socket: %{state.socket | assigns: assigns}}
        end)

        # Force a re-render — if the helper crashes, this raises
        html = render(view)
        assert is_binary(html)
      end
    end

    test "header renders with token_balances containing integer values", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/")

      :sys.replace_state(view.pid, fn state ->
        assigns = Map.put(state.socket.assigns, :token_balances, %{"SOL" => 0, "BUX" => 0})
        %{state | socket: %{state.socket | assigns: assigns}}
      end)

      assert is_binary(render(view))
    end

    test "user dropdown renders with weird wallet_address", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/")

      # Corrupt the wallet_address on the current_user assign — should still
      # render (with "—" or similar fallback) rather than crash.
      for bad_addr <- [nil, "", "ab"] do
        :sys.replace_state(view.pid, fn state ->
          cu = Map.put(state.socket.assigns.current_user, :wallet_address, bad_addr)
          assigns = Map.put(state.socket.assigns, :current_user, cu)
          %{state | socket: %{state.socket | assigns: assigns}}
        end)

        assert is_binary(render(view)), "crashed on wallet_address=#{inspect(bad_addr)}"
      end
    end
  end

  describe "wallet page renders with edge-case assigns" do
    test "bux balance pubsub with integer 0 doesn't crash", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      send(view.pid, {:bux_balance_updated, 0})
      assert is_binary(render(view))

      send(view.pid, {:bux_balance_updated, 999_999})
      assert is_binary(render(view))
    end

    test "form field changes preserve each other", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      html =
        view
        |> form("form[phx-submit='review_send']", %{
          to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
          amount: "0.5"
        })
        |> render_change()

      assert html =~ ~s|value="9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"|
      assert html =~ ~s|value="0.5"|
    end
  end
end
