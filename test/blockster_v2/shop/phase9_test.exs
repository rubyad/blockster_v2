defmodule BlocksterV2.Shop.Phase9Test do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Cart, as: CartContext
  alias BlocksterV2.Orders
  alias BlocksterV2.Orders.{Order, AffiliatePayout}
  alias BlocksterV2.Referrals
  alias BlocksterV2.Shop
  alias BlocksterV2.Accounts.User

  # ============================================================================
  # Test Setup — ensure Mnesia tables + BalanceManager running
  # ============================================================================

  setup do
    :mnesia.start()

    # BUX balances table (required by BalanceManager / get_user_token_balances)
    bux_attrs = [
      :user_id, :user_smart_wallet, :updated_at, :aggregate_bux_balance,
      :bux_balance, :moonbux_balance, :neobux_balance, :roguebux_balance,
      :flarebux_balance, :nftbux_balance, :nolchabux_balance, :solbux_balance,
      :spacebux_balance, :tronbux_balance, :tranbux_balance
    ]

    create_or_clear_table(:user_bux_balances, bux_attrs, :set)

    # ROGUE balances table
    create_or_clear_table(:user_rogue_balances,
      [:user_id, :user_smart_wallet, :updated_at, :rogue_balance_rogue_chain, :rogue_balance_arbitrum],
      :set
    )

    # Referral earnings table (bag type — allows multiple records per user)
    create_or_clear_table(:referral_earnings,
      [:id, :referrer_id, :referrer_wallet, :referee_wallet, :earning_type, :amount, :token, :tx_hash, :commitment_hash, :timestamp],
      :bag,
      [:referrer_id, :referrer_wallet, :referee_wallet, :commitment_hash]
    )

    # Referral stats table
    create_or_clear_table(:referral_stats,
      [:user_id, :total_referrals, :verified_referrals, :total_bux_earned, :total_rogue_earned, :updated_at],
      :set
    )

    # Referrals table (for get_referrer_by_referee_wallet lookups)
    create_or_clear_table(:referrals,
      [:user_id, :referrer_id, :referrer_wallet, :referee_wallet, :referred_at, :on_chain_synced],
      :set,
      [:referrer_id, :referrer_wallet, :referee_wallet]
    )

    # Start BalanceManager
    case GenServer.start_link(BlocksterV2.Shop.BalanceManager, %{}, name: {:global, BlocksterV2.Shop.BalanceManager}) do
      {:ok, pid} -> on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  defp create_or_clear_table(name, attrs, type, indices \\ []) do
    case :mnesia.create_table(name, [
           attributes: attrs,
           ram_copies: [node()],
           type: type,
           index: indices
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, ^name}} ->
        case :mnesia.add_table_copy(name, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, ^name, _}} -> :ok
        end
        :mnesia.clear_table(name)
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "user#{unique_id}@example.com",
      username: "user#{unique_id}",
      auth_method: "wallet"
    }

    %User{}
    |> User.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp create_product(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      title: "Test Product #{unique_id}",
      handle: "test-product-#{unique_id}",
      status: "active",
      bux_max_discount: 50
    }

    {:ok, product} = Shop.create_product(Map.merge(default_attrs, attrs))
    product
  end

  defp create_variant(product, attrs \\ %{}) do
    default_attrs = %{
      product_id: product.id,
      price: Decimal.new("50.00"),
      title: "Default",
      inventory_quantity: 10,
      inventory_policy: "deny"
    }

    {:ok, variant} = Shop.create_variant(Map.merge(default_attrs, attrs))
    variant
  end

  defp create_order_for_user(user, opts \\ []) do
    product = create_product(%{title: Keyword.get(opts, :product_title, "Test Sneakers")})
    variant = create_variant(product, %{price: Decimal.new("100.00"), title: Keyword.get(opts, :variant_title, "Size 10")})

    {:ok, _} =
      CartContext.add_to_cart(user.id, product.id, %{
        variant_id: variant.id,
        quantity: Keyword.get(opts, :quantity, 1),
        bux_tokens_to_redeem: 0
      })

    cart = CartContext.get_or_create_cart(user.id)
    {:ok, order} = Orders.create_order_from_cart(cart, user)

    {:ok, order} =
      Orders.update_order_shipping(order, %{
        shipping_name: "John Doe",
        shipping_email: "john@example.com",
        shipping_address_line1: "123 Main St",
        shipping_city: "New York",
        shipping_state: "NY",
        shipping_postal_code: "10001",
        shipping_country: "US"
      })

    {:ok, order} = Orders.update_order(order, %{status: "paid"})
    Orders.get_order(order.id)
  end

  defp create_referred_user(referrer) do
    buyer = create_user()

    buyer
    |> Ecto.Changeset.change(%{referrer_id: referrer.id})
    |> Repo.update!()
  end

  # ============================================================================
  # Commission Calculation Tests
  # ============================================================================

  describe "BUX commission (5%)" do
    test "creates BUX payout with correct 5% commission" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      # Set BUX tokens burned on the order
      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{bux_tokens_burned: 2000})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id)
      bux_payout = Enum.find(payouts, &(&1.currency == "BUX"))

      assert bux_payout != nil
      assert Decimal.equal?(bux_payout.commission_rate, Decimal.new("0.05"))
      # 5% of 2000 = 100
      assert Decimal.equal?(bux_payout.commission_amount, Decimal.new("100"))
      assert bux_payout.referrer_id == referrer.id
    end

    test "BUX payout is immediately paid when referrer has wallet" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{bux_tokens_burned: 1000})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id and p.currency == "BUX")
      payout = List.first(payouts)

      # BUX payouts are marked paid immediately (minting happens via BuxMinter)
      assert payout.status == "paid"
      assert payout.paid_at != nil
    end
  end

  describe "ROGUE commission (5%)" do
    test "creates ROGUE payout with correct 5% commission" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{rogue_tokens_sent: Decimal.new("500.0")})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id)
      rogue_payout = Enum.find(payouts, &(&1.currency == "ROGUE"))

      assert rogue_payout != nil
      # 5% of 500 = 25
      assert Decimal.equal?(rogue_payout.commission_amount, Decimal.new("25.0"))
      assert rogue_payout.referrer_id == referrer.id
    end

    test "ROGUE payout starts with pending status" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{rogue_tokens_sent: Decimal.new("100.0")})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id and p.currency == "ROGUE")
      payout = List.first(payouts)

      assert payout.status == "pending"
    end
  end

  describe "Helio commission (5%)" do
    test "creates Helio crypto payout with correct 5% commission" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("60.00"),
          helio_payment_currency: "USDC"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id)
      helio_payout = Enum.find(payouts, &(&1.currency == "USDC"))

      assert helio_payout != nil
      # 5% of 60 = 3
      assert Decimal.equal?(helio_payout.commission_amount, Decimal.new("3.0000"))
      assert helio_payout.status == "pending"
    end

    test "card payment creates held payout with 30-day hold" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("50.00"),
          helio_payment_currency: "CARD"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id)
      card_payout = Enum.find(payouts, &(&1.currency == "CARD"))

      assert card_payout != nil
      assert card_payout.status == "held"
      assert card_payout.held_until != nil

      # held_until should be approximately 30 days from now
      diff = DateTime.diff(card_payout.held_until, DateTime.utc_now(), :day)
      assert diff >= 29 and diff <= 31
    end

    test "card payout has commission_usd_value set" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("80.00"),
          helio_payment_currency: "CARD"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id)
      card_payout = Enum.find(payouts, &(&1.currency == "CARD"))

      # 5% of 80 = 4
      assert Decimal.equal?(card_payout.commission_usd_value, Decimal.new("4.0000"))
    end
  end

  # ============================================================================
  # Multi-currency order creates multiple payouts
  # ============================================================================

  describe "multi-currency payouts" do
    test "order with BUX + ROGUE + Helio creates 3 separate payouts" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{
          bux_tokens_burned: 1000,
          bux_discount_amount: Decimal.new("10.00"),
          rogue_tokens_sent: Decimal.new("200.0"),
          rogue_payment_amount: Decimal.new("40.00")
        })
        |> Repo.update()

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("50.00"),
          helio_payment_currency: "USDC"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id)

      assert length(payouts) == 3
      currencies = Enum.map(payouts, & &1.currency) |> Enum.sort()
      assert currencies == ["BUX", "ROGUE", "USDC"]
    end
  end

  # ============================================================================
  # No-referrer order creates no payouts
  # ============================================================================

  describe "no-referrer order" do
    test "order without referrer_id creates no payouts" do
      buyer = create_user()
      order = create_order_for_user(buyer)

      # Ensure no referrer
      assert is_nil(order.referrer_id)

      # process_paid_order checks referrer_id before calling create_affiliate_payouts
      Orders.process_paid_order(order)
      Process.sleep(100)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id)
      assert Enum.empty?(payouts)
    end

    test "order with zero payments creates no payouts even with referrer" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      # Order has referrer_id but no BUX burned, no ROGUE sent, no Helio payment
      # Default values are 0 for all payment amounts
      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id)
      assert Enum.empty?(payouts)
    end
  end

  # ============================================================================
  # AffiliatePayoutWorker Tests
  # ============================================================================

  describe "AffiliatePayoutWorker" do
    test "worker module exists and exports start_link/1" do
      Code.ensure_loaded!(BlocksterV2.Orders.AffiliatePayoutWorker)
      assert function_exported?(BlocksterV2.Orders.AffiliatePayoutWorker, :start_link, 1)
    end

    test "processes held payouts past hold date" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      # Create a held payout with held_until in the past
      {:ok, payout} =
        %AffiliatePayout{}
        |> AffiliatePayout.changeset(%{
          order_id: order.id,
          referrer_id: referrer.id,
          currency: "USDC",
          basis_amount: Decimal.new("100.00"),
          commission_rate: Decimal.new("0.05"),
          commission_amount: Decimal.new("5.00"),
          status: "held",
          held_until: DateTime.add(DateTime.utc_now(), -1, :day)
        })
        |> Repo.insert()

      assert payout.status == "held"

      # Simulate what the worker does: query held payouts past their hold date
      now = DateTime.utc_now()
      eligible = Repo.all(
        from p in AffiliatePayout,
          where: p.status == "held",
          where: p.held_until <= ^now
      )

      assert length(eligible) >= 1
      assert Enum.any?(eligible, &(&1.id == payout.id))
    end

    test "does not process held payouts still within hold period" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      # Create a held payout with held_until in the future
      {:ok, payout} =
        %AffiliatePayout{}
        |> AffiliatePayout.changeset(%{
          order_id: order.id,
          referrer_id: referrer.id,
          currency: "CARD",
          basis_amount: Decimal.new("50.00"),
          commission_rate: Decimal.new("0.05"),
          commission_amount: Decimal.new("2.50"),
          status: "held",
          held_until: DateTime.add(DateTime.utc_now(), 29, :day)
        })
        |> Repo.insert()

      # Query same as worker does
      now = DateTime.utc_now()
      eligible = Repo.all(
        from p in AffiliatePayout,
          where: p.status == "held",
          where: p.held_until <= ^now
      )

      refute Enum.any?(eligible, &(&1.id == payout.id))
    end
  end

  # ============================================================================
  # execute_affiliate_payout Tests
  # ============================================================================

  describe "execute_affiliate_payout/1" do
    test "marks payout as paid for USDC/card currencies" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, payout} =
        %AffiliatePayout{}
        |> AffiliatePayout.changeset(%{
          order_id: order.id,
          referrer_id: referrer.id,
          currency: "USDC",
          basis_amount: Decimal.new("100.00"),
          commission_rate: Decimal.new("0.05"),
          commission_amount: Decimal.new("5.00"),
          status: "held",
          held_until: DateTime.add(DateTime.utc_now(), -1, :day)
        })
        |> Repo.insert()

      {:ok, updated} = Orders.execute_affiliate_payout(payout)

      assert updated.status == "paid"
      assert updated.paid_at != nil
    end

    test "handles SOL currency payouts" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, payout} =
        %AffiliatePayout{}
        |> AffiliatePayout.changeset(%{
          order_id: order.id,
          referrer_id: referrer.id,
          currency: "SOL",
          basis_amount: Decimal.new("10.00"),
          commission_rate: Decimal.new("0.05"),
          commission_amount: Decimal.new("0.50"),
          status: "pending"
        })
        |> Repo.insert()

      {:ok, updated} = Orders.execute_affiliate_payout(payout)

      assert updated.status == "paid"
    end
  end

  # ============================================================================
  # Mnesia referral_earnings Recording Tests
  # ============================================================================

  describe "Mnesia referral_earnings recording" do
    test "BUX payout records :shop_purchase earning in Mnesia" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{bux_tokens_burned: 2000})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      # Check Mnesia for the earning
      earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      shop_earnings = Enum.filter(earnings, fn record -> elem(record, 5) == :shop_purchase end)

      assert length(shop_earnings) == 1
      earning = List.first(shop_earnings)

      assert elem(earning, 2) == referrer.id
      assert elem(earning, 5) == :shop_purchase
      # 5% of 2000 = 100 (stored as float)
      assert elem(earning, 6) == 100.0
      assert elem(earning, 7) == "BUX"
    end

    test "ROGUE payout records :shop_purchase earning in Mnesia" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{rogue_tokens_sent: Decimal.new("400.0")})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      shop_earnings = Enum.filter(earnings, fn record ->
        elem(record, 5) == :shop_purchase and elem(record, 7) == "ROGUE"
      end)

      assert length(shop_earnings) == 1
      earning = List.first(shop_earnings)

      # 5% of 400 = 20
      assert_in_delta elem(earning, 6), 20.0, 0.01
      assert elem(earning, 7) == "ROGUE"
    end

    test "Helio payout records :shop_purchase earning in Mnesia" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("80.00"),
          helio_payment_currency: "USDC"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      shop_earnings = Enum.filter(earnings, fn record ->
        elem(record, 5) == :shop_purchase and elem(record, 7) == "USDC"
      end)

      assert length(shop_earnings) == 1
      earning = List.first(shop_earnings)

      # 5% of 80 = 4
      assert_in_delta elem(earning, 6), 4.0, 0.01
      assert elem(earning, 7) == "USDC"
    end

    test "multi-currency order records 3 separate Mnesia earnings" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{
          bux_tokens_burned: 1000,
          rogue_tokens_sent: Decimal.new("200.0")
        })
        |> Repo.update()

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("50.00"),
          helio_payment_currency: "SOL"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      shop_earnings = Enum.filter(earnings, fn record -> elem(record, 5) == :shop_purchase end)

      assert length(shop_earnings) == 3

      tokens = Enum.map(shop_earnings, fn record -> elem(record, 7) end) |> Enum.sort()
      assert tokens == ["BUX", "ROGUE", "SOL"]
    end

    test "earnings contain correct referrer and referee wallets" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{bux_tokens_burned: 500})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      earning = List.first(earnings)

      # referrer_wallet at index 3, referee_wallet at index 4
      assert elem(earning, 3) == String.downcase(referrer.smart_wallet_address)
      assert elem(earning, 4) == String.downcase(buyer.smart_wallet_address)
    end

    test "no Mnesia earning recorded when order has no referrer" do
      buyer = create_user()
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{bux_tokens_burned: 1000})
        |> Repo.update()

      order = Orders.get_order(order.id)

      # process_paid_order skips affiliate creation when no referrer_id
      Orders.process_paid_order(order)
      Process.sleep(100)

      # No earnings should exist
      all_earnings = :mnesia.dirty_match_object({:referral_earnings, :_, :_, :_, :_, :shop_purchase, :_, :_, :_, :_, :_})
      assert Enum.empty?(all_earnings)
    end
  end

  # ============================================================================
  # Referrals.record_shop_purchase_earning Tests
  # ============================================================================

  describe "Referrals.record_shop_purchase_earning/1" do
    test "records earning with correct fields" do
      {:ok, id} = Referrals.record_shop_purchase_earning(%{
        referrer_id: 42,
        referrer_wallet: "0xReferrer123",
        referee_wallet: "0xBuyer456",
        amount: 150,
        token: "BUX"
      })

      assert is_binary(id)

      earnings = :mnesia.dirty_index_read(:referral_earnings, 42, :referrer_id)
      assert length(earnings) == 1

      earning = List.first(earnings)
      assert elem(earning, 2) == 42
      assert elem(earning, 3) == "0xreferrer123"
      assert elem(earning, 4) == "0xbuyer456"
      assert elem(earning, 5) == :shop_purchase
      assert elem(earning, 6) == 150.0
      assert elem(earning, 7) == "BUX"
    end

    test "converts Decimal amounts to float" do
      {:ok, _} = Referrals.record_shop_purchase_earning(%{
        referrer_id: 43,
        referrer_wallet: "0xWallet1",
        referee_wallet: "0xWallet2",
        amount: Decimal.new("25.50"),
        token: "USDC"
      })

      earnings = :mnesia.dirty_index_read(:referral_earnings, 43, :referrer_id)
      earning = List.first(earnings)

      assert is_float(elem(earning, 6))
      assert_in_delta elem(earning, 6), 25.5, 0.01
    end

    test "updates referral_stats for BUX earnings" do
      Referrals.record_shop_purchase_earning(%{
        referrer_id: 44,
        referrer_wallet: "0xWallet",
        referee_wallet: "0xBuyer",
        amount: 200,
        token: "BUX"
      })

      stats = Referrals.get_referrer_stats(44)
      assert stats.total_bux_earned == 200.0
    end

    test "updates referral_stats for ROGUE earnings" do
      Referrals.record_shop_purchase_earning(%{
        referrer_id: 45,
        referrer_wallet: "0xWallet",
        referee_wallet: "0xBuyer",
        amount: 50.5,
        token: "ROGUE"
      })

      stats = Referrals.get_referrer_stats(45)
      assert_in_delta stats.total_rogue_earned, 50.5, 0.01
    end

    test "USDC earnings don't affect BUX/ROGUE stats" do
      Referrals.record_shop_purchase_earning(%{
        referrer_id: 46,
        referrer_wallet: "0xWallet",
        referee_wallet: "0xBuyer",
        amount: Decimal.new("10.00"),
        token: "USDC"
      })

      stats = Referrals.get_referrer_stats(46)
      assert stats.total_bux_earned == 0.0
      assert stats.total_rogue_earned == 0.0
    end

    test "downcases wallet addresses" do
      {:ok, _} = Referrals.record_shop_purchase_earning(%{
        referrer_id: 47,
        referrer_wallet: "0xABCDEF123456",
        referee_wallet: "0x789ABC000DEF",
        amount: 100,
        token: "BUX"
      })

      earnings = :mnesia.dirty_index_read(:referral_earnings, 47, :referrer_id)
      earning = List.first(earnings)

      assert elem(earning, 3) == "0xabcdef123456"
      assert elem(earning, 4) == "0x789abc000def"
    end

    test "handles nil wallets gracefully" do
      {:ok, _} = Referrals.record_shop_purchase_earning(%{
        referrer_id: 48,
        referrer_wallet: nil,
        referee_wallet: nil,
        amount: 50,
        token: "BUX"
      })

      earnings = :mnesia.dirty_index_read(:referral_earnings, 48, :referrer_id)
      assert length(earnings) == 1
      earning = List.first(earnings)
      assert elem(earning, 3) == ""
      assert elem(earning, 4) == ""
    end
  end

  # ============================================================================
  # Referral earnings display (member page) Tests
  # ============================================================================

  describe "member page earnings display" do
    test "earning_type_label returns 'Shop Purchase' for :shop_purchase" do
      assert BlocksterV2Web.MemberLive.Show.earning_type_label(:shop_purchase) == "Shop Purchase"
    end

    test "earning_type_style returns orange styling for :shop_purchase" do
      assert BlocksterV2Web.MemberLive.Show.earning_type_style(:shop_purchase) == "bg-orange-100 text-orange-800"
    end

    test "list_referral_earnings returns shop_purchase earnings" do
      Referrals.record_shop_purchase_earning(%{
        referrer_id: 50,
        referrer_wallet: "0xWallet",
        referee_wallet: "0xBuyer",
        amount: 75,
        token: "BUX"
      })

      earnings = Referrals.list_referral_earnings(50)
      assert length(earnings) == 1

      earning = List.first(earnings)
      assert earning.earning_type == :shop_purchase
      assert earning.amount == 75.0
      assert earning.token == "BUX"
    end

    test "list_referral_earnings shows multiple currency shop purchases" do
      Referrals.record_shop_purchase_earning(%{
        referrer_id: 51,
        referrer_wallet: "0xWallet",
        referee_wallet: "0xBuyer",
        amount: 100,
        token: "BUX"
      })

      Referrals.record_shop_purchase_earning(%{
        referrer_id: 51,
        referrer_wallet: "0xWallet",
        referee_wallet: "0xBuyer",
        amount: 10.5,
        token: "ROGUE"
      })

      Referrals.record_shop_purchase_earning(%{
        referrer_id: 51,
        referrer_wallet: "0xWallet",
        referee_wallet: "0xBuyer",
        amount: Decimal.new("5.00"),
        token: "USDC"
      })

      earnings = Referrals.list_referral_earnings(51)
      assert length(earnings) == 3

      tokens = Enum.map(earnings, & &1.token) |> Enum.sort()
      assert tokens == ["BUX", "ROGUE", "USDC"]
    end
  end

  # ============================================================================
  # AffiliatePayout Schema Validation Tests
  # ============================================================================

  describe "AffiliatePayout schema" do
    test "valid changeset with all required fields" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      changeset = AffiliatePayout.changeset(%AffiliatePayout{}, %{
        order_id: order.id,
        referrer_id: referrer.id,
        currency: "BUX",
        basis_amount: Decimal.new("1000"),
        commission_rate: Decimal.new("0.05"),
        commission_amount: Decimal.new("50")
      })

      assert changeset.valid?
    end

    test "validates currency inclusion" do
      changeset = AffiliatePayout.changeset(%AffiliatePayout{}, %{
        order_id: Ecto.UUID.generate(),
        referrer_id: 1,
        currency: "INVALID",
        basis_amount: Decimal.new("100"),
        commission_rate: Decimal.new("0.05"),
        commission_amount: Decimal.new("5")
      })

      refute changeset.valid?
      assert errors_on(changeset)[:currency]
    end

    test "validates status inclusion" do
      changeset = AffiliatePayout.changeset(%AffiliatePayout{}, %{
        order_id: Ecto.UUID.generate(),
        referrer_id: 1,
        currency: "BUX",
        basis_amount: Decimal.new("100"),
        commission_rate: Decimal.new("0.05"),
        commission_amount: Decimal.new("5"),
        status: "invalid_status"
      })

      refute changeset.valid?
      assert errors_on(changeset)[:status]
    end

    test "commission_rate must be positive and <= 1" do
      changeset = AffiliatePayout.changeset(%AffiliatePayout{}, %{
        order_id: Ecto.UUID.generate(),
        referrer_id: 1,
        currency: "BUX",
        basis_amount: Decimal.new("100"),
        commission_rate: Decimal.new("1.5"),
        commission_amount: Decimal.new("5")
      })

      refute changeset.valid?
      assert errors_on(changeset)[:commission_rate]
    end
  end

  # ============================================================================
  # process_paid_order integration with affiliates
  # ============================================================================

  describe "process_paid_order affiliate integration" do
    test "process_paid_order creates payouts for referred buyer" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{bux_tokens_burned: 500})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.process_paid_order(order)
      Process.sleep(200)

      payouts = Repo.all(from p in AffiliatePayout, where: p.order_id == ^order.id)
      assert length(payouts) == 1
      assert List.first(payouts).currency == "BUX"
    end

    test "process_paid_order records Mnesia earnings for referred buyer" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer)

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{bux_tokens_burned: 800})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.process_paid_order(order)
      Process.sleep(200)

      earnings = :mnesia.dirty_index_read(:referral_earnings, referrer.id, :referrer_id)
      shop_earnings = Enum.filter(earnings, fn record -> elem(record, 5) == :shop_purchase end)

      assert length(shop_earnings) == 1
      # 5% of 800 = 40
      assert elem(List.first(shop_earnings), 6) == 40.0
    end
  end
end
