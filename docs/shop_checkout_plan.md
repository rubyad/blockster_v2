# Shop Checkout System - Implementation Plan

> **Status**: Phase 1 Complete — Phase 2 Next
> **Created**: 2026-02-16
> **Branch**: `feat/shop-checkout`
> **Scope**: Complete checkout system with Helio payments, BUX/ROGUE discounts, affiliate system, and order fulfillment

---

## Implementation Progress

### Phase 1: Foundation (Backend) — COMPLETE (2026-02-16)

**All items done. 45 tests passing. Migrations applied to dev DB.**

#### Files Created (18 new files)

**Migrations:**
- `priv/repo/migrations/20260216200000_create_carts_and_cart_items.exs`
- `priv/repo/migrations/20260216200001_create_orders_and_order_items.exs`
- `priv/repo/migrations/20260216200002_create_affiliate_payouts.exs`
- `priv/repo/migrations/20260216200003_create_product_configs.exs`

**Schemas:**
- `lib/blockster_v2/cart/cart.ex` — Cart schema (binary_id PK, unique user_id)
- `lib/blockster_v2/cart/cart_item.ex` — CartItem (product + variant + bux_tokens_to_redeem)
- `lib/blockster_v2/orders/order.ex` — Order (6 changesets: create, shipping, bux_payment, rogue_payment, helio_payment, status)
- `lib/blockster_v2/orders/order_item.ex` — OrderItem (denormalized product snapshot)
- `lib/blockster_v2/orders/affiliate_payout.ex` — AffiliatePayout (multi-currency, held status for card)
- `lib/blockster_v2/shop/product_config.ex` — ProductConfig (sizes, colors, checkout_enabled)

**Contexts:**
- `lib/blockster_v2/cart.ex` — Cart context (get_or_create, add/update/remove items, calculate_totals, validate)
- `lib/blockster_v2/orders.ex` — Orders context (create_order_from_cart, payment processing, affiliates, generate_order_number)

**GenServer Workers:**
- `lib/blockster_v2/shop/balance_manager.ex` — Serialized BUX deductions (GlobalSingleton)
- `lib/blockster_v2/orders/affiliate_payout_worker.ex` — Hourly held payout processor (GlobalSingleton)
- `lib/blockster_v2/orders/order_expiry_worker.ex` — 5-min stale order expiry (GlobalSingleton)

**Tests:**
- `test/blockster_v2/shop/checkout_test.exs` — 45 tests covering all schemas, cart context, orders context, and ProductConfig CRUD

#### Files Modified (5 existing files)
- `lib/blockster_v2/shop/product.ex` — Added `has_one :product_config`
- `lib/blockster_v2/shop.ex` — Added `ProductConfig` alias + 4 CRUD functions (get, create, update, change)
- `lib/blockster_v2/bux_minter.ex` — Added `:shop_affiliate` and `:shop_refund` to valid reward types guard
- `lib/blockster_v2/application.ex` — Added BalanceManager, AffiliatePayoutWorker, OrderExpiryWorker to genserver_children
- `lib/blockster_v2_web/router.ex` — Added routes: `/cart`, `/checkout/:order_id`, `/admin/orders`, `/admin/orders/:id`, `/api/helio/webhook`

#### Implementation Notes / Bugs Fixed
- **Ecto nil comparison bug**: `add_to_cart` originally used `ci.variant_id == ^vid` which fails when `vid` is nil (Ecto forbids `== nil` in queries). Fixed by splitting into two query branches using `is_nil(ci.variant_id)`.
- **Mnesia not available in test**: `get_current_rogue_rate` crashed with `{:aborted, {:no_exists, [:token_prices, "rogue"]}}` in tests. Fixed by adding `rescue` + `catch :exit` fallback.
- **ROGUE fallback price**: Updated from `$0.20` to `$0.00006` to match current market value.
- **Cart preload depth**: `preload_items` needed `product: [:images, :variants]` (not just `:product`) so `create_order_from_cart` can snapshot product images and variant prices.
- **Alias conflict in tests**: `BlocksterV2.Cart` (context module) and `BlocksterV2.Cart.Cart` (schema) both alias to `Cart`. Used `alias BlocksterV2.Cart, as: CartContext` in tests.

#### Not Yet Wired (deferred to later phases)
- Inventory decrement in `create_order_from_cart` (plan mentions it in Phase 1 item 10 but code in Appendix H doesn't include it — will add in Phase 3 when cart-to-order flow is fully built)
- `OrderMailer` and `OrderTelegram` modules referenced in `process_paid_order` don't exist yet (Phase 8)
- `BuxMinter.transfer_rogue` referenced in `execute_affiliate_payout` may not exist yet (Phase 9)
- Helio webhook controller not created yet (Phase 7)

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Helio (MoonPay Commerce) Setup & Integration](#2-helio-moonpay-commerce-setup--integration)
3. [Database Schema Changes](#3-database-schema-changes)
4. [Product Variant & Configuration System](#4-product-variant--configuration-system)
5. [Multi-Payment Checkout Flow](#5-multi-payment-checkout-flow)
6. [BUX Payment Mechanics](#6-bux-payment-mechanics)
7. [ROGUE Payment Mechanics](#7-rogue-payment-mechanics)
8. [Helio Payment Integration](#8-helio-payment-integration)
9. [Shop Affiliate System](#9-shop-affiliate-system)
10. [Order Fulfillment (Email + Telegram)](#10-order-fulfillment-email--telegram)
11. [Backend Implementation](#11-backend-implementation)
12. [Frontend Implementation](#12-frontend-implementation)
13. [Admin Interface](#13-admin-interface)
14. [Security Considerations](#14-security-considerations)
15. [Implementation Phases](#15-implementation-phases)

---

## 1. System Overview

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                         BUYER'S BROWSER                              │
│                                                                      │
│  Product Page ──► Cart ──► Checkout ──► Payment Steps ──► Confirm    │
│  (Add to Cart)    (edit)  (shipping)   (BUX → ROGUE → Helio)        │
│                                                                      │
│  JS Hooks: ThirdwebWallet (BUX/ROGUE transfers), HelioCheckout      │
└──────────────┬───────────────────────────┬───────────────────────────┘
               │                           │
               ▼                           ▼
┌──────────────────────────┐   ┌──────────────────────────────────────┐
│   Phoenix LiveView       │   │   Helio (MoonPay Commerce)           │
│   CartLive, CheckoutLive │   │   - Checkout Widget (embedded)       │
│                          │   │   - Charges API (dynamic amounts)    │
│   • Manage cart          │   │   - Webhook → /api/helio/webhook     │
│   • Validate order       │   │   - Supported: SOL, ETH, USDC, BTC  │
│   • Process BUX burn     │   │   - Chains: Solana, Ethereum, Base,  │
│   • Process ROGUE pay    │   │     Polygon, Bitcoin                 │
│   • Create Helio charge  │   │   - Fee: 2% (standard)              │
│   • Record order         │   │   - Card payments: showPayWithCard   │
│   • Track affiliate      │   │                                      │
└────────┬─────────────────┘   └──────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────────┐
│                           DATA LAYER                                 │
│                                                                      │
│   PostgreSQL                    │   Mnesia                           │
│   ┌─────────────────┐          │   ┌──────────────────────┐         │
│   │ carts            │ (new)    │   │ user_bux_balances     │         │
│   │ cart_items        │ (new)    │   │ (BUX balance cache)   │         │
│   │ orders           │ (new)    │   └──────────────────────┘         │
│   │ order_items      │ (new)    │                                    │
│   │ products         │ (exist)  │                                    │
│   │ product_variants │ (exist)  │                                    │
│   │ product_configs  │ (new)    │                                    │
│   └─────────────────┘          │                                    │
└──────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      ORDER FULFILLMENT                               │
│                                                                      │
│   ┌─────────────┐    ┌──────────────────┐    ┌───────────────────┐  │
│   │ Email        │    │ Telegram Bot     │    │ Admin Dashboard   │  │
│   │ (Swoosh)     │    │ (Bot API via Req)│    │ (orders list)     │  │
│   │ → Fulfiller  │    │ → Channel notify │    │ → status updates  │  │
│   └─────────────┘    └──────────────────┘    └───────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Full cart system** — Users can add multiple items to cart, adjust quantities and BUX per item, then checkout the entire cart as one order
2. **BUX per item, ROGUE per order** — BUX discounts are set per item (product-specific caps). ROGUE is a single order-level payment set at checkout (rate locked at that moment)
3. **ROGUE discount** — Paying with ROGUE gives a 10% discount on the ROGUE portion (configurable). If $100 remains after BUX, paying fully with ROGUE costs only $90 worth of ROGUE
4. **Payment order**: BUX discount first → ROGUE payment second → Helio for remainder
5. **Helio handles fiat-equivalent crypto** — Buyer pays remaining USD amount in SOL/ETH/USDC/BTC via Helio
6. **Card payments supported** — Helio's `showPayWithCard: true` allows credit/debit card payments
7. **BUX burns are on-chain** — BUX tokens transferred to a burn/treasury address via smart wallet
8. **ROGUE payments are on-chain** — ROGUE sent from smart wallet to treasury address
9. **Orders stored in PostgreSQL** — Not Mnesia, since orders are permanent business records
10. **Affiliate commissions in same currency** — Referrers earn 5% in each payment currency used: BUX (minted), ROGUE (from treasury), Helio/card (USDC on Ethereum at current rate). Card commissions held 30 days for chargeback protection

---

## 2. Helio (MoonPay Commerce) Setup & Integration

### What is Helio?

Helio (now MoonPay Commerce after Jan 2025 acquisition) is a crypto payment processor that lets merchants accept USDC, SOL, ETH, BTC, and 100+ other currencies. It provides an embeddable checkout widget, REST API for creating charges, and webhooks for payment confirmation.

### Signup & Approval Process

**Good news: No approval process.** Helio is self-serve:

1. Go to [hel.io](https://www.hel.io)
2. Click "Connect" and sign in with a Solana wallet (no username/password needed)
3. Complete optional account settings (email recommended for notifications)
4. Generate API keys from the dashboard
5. Start accepting payments immediately

**Credentials needed:**
- `apiKey` — For client-side widget
- `secretKey` — For server-side API calls (charges, webhooks)
- Webhook shared secret — Generated when creating webhook endpoint

### Fee Structure

| Tier | Transaction Fee | Notes |
|------|----------------|-------|
| Standard | 2% | Free to start, no monthly fees |
| HelioX Premium | 1% | Requires HelioX Pass NFT |
| Custom | Negotiable | For high-volume merchants |
| Swap fee | +0.25% | If buyer pays with non-native token |
| Auto-offramp | +0.50% | If merchant wants fiat settlement |

### Supported Blockchains

| Chain | Mainnet | Testnet |
|-------|---------|---------|
| Solana | Yes | Devnet |
| Ethereum | Yes | Sepolia |
| Base | Yes | Sepolia |
| Polygon | Yes | Mumbai |
| Bitcoin | Yes | Testnet3 |

**Important: Rogue Chain is NOT supported by Helio.** This means:
- Helio handles the fiat-equivalent crypto portion of payment (buyer pays in SOL/USDC/ETH/BTC on supported chains)
- BUX and ROGUE payments happen separately on Rogue Chain via Thirdweb smart wallets
- This is actually clean separation — Helio handles the "real money" part, our system handles the Rogue Chain token part

### Integration Approach: Charges API + Checkout Widget

We will use two Helio features together:

1. **Charges API (server-side)** — Create a charge with the exact remaining USD amount after BUX/ROGUE discounts
2. **Checkout Widget (client-side)** — Embed the widget using the charge token to display the payment UI

**Flow:**
```
1. Server creates charge via POST /chargecontroller_createchargewithapikey
   → Returns chargeToken
2. Client renders <HelioCheckout config={{ chargeToken, onSuccess, onError }} />
3. Buyer completes payment in Helio widget
4. Helio sends webhook to /api/helio/webhook with transaction details
5. Server verifies webhook, marks order as paid
```

### Card Payments (Fiat On-Ramp)

Helio supports **card payments** via the `showPayWithCard: true` widget option. This means buyers can also pay the Helio portion with a credit/debit card — Helio handles the fiat-to-crypto conversion. This is a significant UX win for users who don't hold crypto on supported chains.

### Helio Setup Checklist

- [ ] Create Helio/MoonPay Commerce account (connect Solana wallet)
- [ ] Set up merchant profile with email
- [ ] Generate API key pair (apiKey + secretKey) — **Note: secret key cannot be retrieved after creation**
- [ ] Create a Pay Link with dynamic pricing enabled (needed for Charges API)
- [ ] Create webhook endpoint pointing to `https://blockster-v2.fly.dev/api/helio/webhook`
- [ ] Store credentials as Fly.io secrets: `HELIO_API_KEY`, `HELIO_SECRET_KEY`, `HELIO_WEBHOOK_SECRET`
- [ ] Install `@heliofi/checkout-react` npm package (or use vanilla JS CDN embed)
- [ ] Test on devnet: dashboard at `app.dev.hel.io`, API at `api.dev.hel.io/v1`

---

## 3. Database Schema Changes

### New Table: `carts`

Persistent shopping cart per user (survives browser refresh / re-login).

```elixir
create table(:carts, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :user_id, references(:users), null: false

  timestamps(type: :utc_datetime)
end

create unique_index(:carts, [:user_id])  # One cart per user
```

### New Table: `cart_items`

```elixir
create table(:cart_items, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :cart_id, references(:carts, type: :binary_id, on_delete: :delete_all), null: false
  add :product_id, references(:products, type: :binary_id), null: false
  add :variant_id, references(:product_variants, type: :binary_id)  # nil if no variant options
  add :quantity, :integer, null: false, default: 1

  # Per-item BUX discount (set on product page, adjustable in cart)
  add :bux_tokens_to_redeem, :integer, default: 0

  timestamps(type: :utc_datetime)
end

create index(:cart_items, [:cart_id])
create unique_index(:cart_items, [:cart_id, :product_id, :variant_id],
  name: :cart_items_unique_product_variant)  # Prevent duplicate entries, increment qty instead
```

### New Table: `orders`

An order is created from the cart at checkout. Contains the overall payment/shipping info.

```elixir
create table(:orders, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :order_number, :string, null: false  # Human-readable: "BLK-20260216-XXXX"
  add :user_id, references(:users), null: false

  # Pricing totals (all in USD)
  add :subtotal, :decimal, null: false             # Sum of all order_items subtotals
  add :bux_discount_amount, :decimal, default: 0   # Total USD value of BUX discount
  add :bux_tokens_burned, :integer, default: 0      # Total BUX tokens burned
  add :rogue_payment_amount, :decimal, default: 0  # USD value covered by ROGUE (after ROGUE discount)
  add :rogue_discount_rate, :decimal, default: 0.10  # e.g. 0.10 = 10% discount for paying with ROGUE
  add :rogue_discount_amount, :decimal, default: 0   # USD saved by paying with ROGUE
  add :rogue_tokens_sent, :decimal, default: 0       # Actual ROGUE tokens sent
  add :helio_payment_amount, :decimal, default: 0  # USD amount charged via Helio
  add :helio_payment_currency, :string             # "USDC", "SOL", "ETH", "BTC", "CARD"
  add :total_paid, :decimal, null: false            # Total actually paid by buyer (subtotal minus ROGUE discount)

  # Payment tracking
  add :bux_burn_tx_hash, :string         # Rogue Chain tx hash for BUX burn
  add :rogue_payment_tx_hash, :string    # Rogue Chain tx hash for ROGUE payment
  add :rogue_usd_rate_locked, :decimal   # ROGUE/USD rate locked at checkout start
  add :helio_charge_id, :string          # Helio charge ID
  add :helio_transaction_id, :string     # Helio transaction ID (from webhook)
  add :helio_payer_address, :string      # Wallet that paid via Helio

  # Shipping info
  add :shipping_name, :string, null: false
  add :shipping_email, :string, null: false
  add :shipping_address_line1, :string, null: false
  add :shipping_address_line2, :string
  add :shipping_city, :string, null: false
  add :shipping_state, :string
  add :shipping_postal_code, :string, null: false
  add :shipping_country, :string, null: false
  add :shipping_phone, :string

  # Order status
  add :status, :string, null: false, default: "pending"
  # pending → bux_pending → bux_paid → rogue_pending → rogue_paid → helio_pending → paid → processing → shipped → delivered
  # Also: expired (30min timeout), cancelled, refunded

  # Fulfillment
  add :fulfillment_notified_at, :utc_datetime
  add :notes, :text  # Admin notes

  # Refund tracking (for partial payment failure recovery)
  add :refund_bux_tx_hash, :string
  add :refund_rogue_tx_hash, :string
  add :refunded_at, :utc_datetime

  # Affiliate
  add :referrer_id, references(:users)  # User who referred the buyer
  add :affiliate_commission_rate, :decimal, default: 0.05  # 5%

  timestamps(type: :utc_datetime)
end

create unique_index(:orders, [:order_number])
create index(:orders, [:user_id])
create index(:orders, [:status])
create index(:orders, [:helio_charge_id])
create index(:orders, [:referrer_id])
```

### New Table: `order_items`

Each item in the order, with product snapshot for historical record.

```elixir
create table(:order_items, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false

  # Product snapshot (denormalized — prices/titles frozen at purchase time)
  add :product_id, :binary_id, null: false
  add :product_title, :string, null: false
  add :product_image, :string
  add :variant_id, :binary_id
  add :variant_title, :string  # "L / Black", "Men's US 10", etc.
  add :quantity, :integer, null: false, default: 1
  add :unit_price, :decimal, null: false
  add :subtotal, :decimal, null: false  # unit_price * quantity

  # Per-item BUX discount (from cart)
  add :bux_discount_amount, :decimal, default: 0  # USD value
  add :bux_tokens_redeemed, :integer, default: 0   # BUX count

  # Fulfillment per item (different items might ship separately)
  add :tracking_number, :string
  add :tracking_url, :string
  add :fulfillment_status, :string, default: "unfulfilled"
  # unfulfilled → processing → shipped → delivered

  timestamps(type: :utc_datetime)
end

create index(:order_items, [:order_id])
```

### New Table: `affiliate_payouts`

Tracks each individual affiliate payout per currency per order. One order can produce up to 3 payout records (BUX, ROGUE, Helio currency).

```elixir
create table(:affiliate_payouts, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :order_id, references(:orders, type: :binary_id), null: false
  add :referrer_id, references(:users), null: false

  add :currency, :string, null: false      # "BUX", "ROGUE", "USDC", "SOL", "ETH", "BTC", "CARD"
  add :basis_amount, :decimal, null: false  # The payment amount this commission is based on
  add :commission_rate, :decimal, null: false, default: 0.05
  add :commission_amount, :decimal, null: false  # In the same currency
  add :commission_usd_value, :decimal       # USD equivalent at time of order

  # Payout status
  add :status, :string, null: false, default: "pending"
  # pending → held (chargeback window) → paid → failed
  add :held_until, :utc_datetime           # For card payments: hold until chargeback window passes
  add :paid_at, :utc_datetime
  add :tx_hash, :string                    # On-chain tx hash for BUX/ROGUE/crypto payouts
  add :failure_reason, :string

  timestamps(type: :utc_datetime)
end

create index(:affiliate_payouts, [:order_id])
create index(:affiliate_payouts, [:referrer_id])
create index(:affiliate_payouts, [:status])
```

### New Table: `product_configs`

Per-product settings that control which options and checkout behavior apply.

```elixir
create table(:product_configs, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :product_id, references(:products, type: :binary_id), null: false

  # What variant options this product uses
  add :has_sizes, :boolean, default: false      # T-shirts, hoodies: true
  add :has_colors, :boolean, default: false     # Some products: true
  add :has_custom_option, :boolean, default: false
  add :custom_option_label, :string             # "Engraving text", etc.

  # Size system type (only relevant when has_sizes = true)
  add :size_type, :string, default: "clothing"
  # "clothing" → S, M, L, XL, XXL
  # "mens_shoes" → US 7, 7.5, 8, 8.5, 9, 9.5, 10, 10.5, 11, 11.5, 12, 13, 14
  # "womens_shoes" → US 5, 5.5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10, 11
  # "unisex_shoes" → Shows both men's and women's with converter
  # "one_size" → No size selection needed

  # Available options (stored as arrays for easy admin editing)
  add :available_sizes, {:array, :string}, default: []
  add :available_colors, {:array, :string}, default: []

  # Checkout requirements
  add :requires_shipping, :boolean, default: true
  add :is_digital, :boolean, default: false

  # Affiliate settings (per-product override)
  add :affiliate_commission_rate, :decimal  # Override global 5% rate if set

  # Checkout toggle
  add :checkout_enabled, :boolean, default: false

  timestamps(type: :utc_datetime)
end

create unique_index(:product_configs, [:product_id])
```

---

## 4. Product Variant & Configuration System

### Current State

The existing `product_variants` table already supports Shopify-style options (option1, option2, option3). Variants have prices and inventory tracking. The product page (`ShopLive.Show`) already extracts sizes from `option1` and colors from `option2`.

### Problem

Currently, **all products show size selection** on the product page (line 361-374 of `show.html.heex`). Sunglasses and accessories don't need sizes.

### Solution: Product Config

Each product gets a `product_config` record that defines what options it needs:

| Product Type | has_sizes | size_type | has_colors | Example |
|-------------|-----------|-----------|------------|---------|
| T-Shirt | true | clothing | true | Sizes S-XXL, Colors Black/White |
| Hoodie | true | clothing | true | Sizes S-XXL, Colors Black/Grey |
| Hat | true | one_size or clothing | false | One Size or S/M/L |
| Men's Shoes | true | mens_shoes | true | US 7-14, Colors |
| Women's Shoes | true | womens_shoes | true | US 5-11, Colors |
| Unisex Shoes | true | unisex_shoes | true | Men's + Women's sizing |
| Sunglasses | false | — | true | Colors only |
| Poster | false | — | false | No options |
| Digital | false | — | false | No shipping needed |

### Shoe Size System

Shoes need a different size system than clothing:

```elixir
# Predefined size sets (used as defaults in admin, can be customized per product)
@clothing_sizes ["XS", "S", "M", "L", "XL", "XXL", "3XL"]
@mens_shoe_sizes ["US 7", "US 7.5", "US 8", "US 8.5", "US 9", "US 9.5",
                   "US 10", "US 10.5", "US 11", "US 11.5", "US 12", "US 13", "US 14"]
@womens_shoe_sizes ["US 5", "US 5.5", "US 6", "US 6.5", "US 7", "US 7.5",
                     "US 8", "US 8.5", "US 9", "US 9.5", "US 10", "US 11"]
```

For **unisex shoes**, the product page shows a Men's/Women's toggle and displays the appropriate size range. Under the hood, variants are stored with a prefix: `"M-US 10"` or `"W-US 8"`.

### Admin Workflow

When editing a product in admin:
1. Toggle "Has Sizes" → reveals size type dropdown (Clothing / Men's Shoes / Women's Shoes / Unisex Shoes / One Size)
2. Based on size type, shows checkboxes with the relevant size presets (admin can toggle individual sizes on/off)
3. Toggle "Has Colors" → reveals color picker
4. Toggle "Enable Checkout" → makes Add to Cart button live
5. Set affiliate commission rate override (optional, default 5%)

The admin form auto-creates matching variants. For example, Men's Shoes with sizes [US 9, US 10, US 11] and colors [Black, White]:
- Creates 6 variants: US 9/Black, US 9/White, US 10/Black, US 10/White, US 11/Black, US 11/White
- All share the same price (set at product level)

### Frontend Changes

Modify `show.html.heex` to conditionally render based on config:

```heex
<%!-- Size Selection - adapts to size_type --%>
<%= if @product_config.has_sizes do %>
  <%= case @product_config.size_type do %>
    <% "clothing" -> %>
      <%!-- Standard S/M/L/XL buttons --%>
    <% "mens_shoes" -> %>
      <div class="text-sm font-haas_medium_65 text-zinc-400 mb-2">Men's Shoe Size</div>
      <%!-- Shoe size grid (wider buttons for "US 10.5" etc.) --%>
    <% "womens_shoes" -> %>
      <div class="text-sm font-haas_medium_65 text-zinc-400 mb-2">Women's Shoe Size</div>
      <%!-- Shoe size grid --%>
    <% "unisex_shoes" -> %>
      <%!-- Men's / Women's toggle tabs, then size grid for selected gender --%>
      <div class="flex gap-2 mb-3">
        <button phx-click="set_shoe_gender" phx-value-gender="mens" ...>Men's</button>
        <button phx-click="set_shoe_gender" phx-value-gender="womens" ...>Women's</button>
      </div>
      <%!-- Show relevant size grid based on @shoe_gender --%>
    <% _ -> %>
      <%!-- one_size: no selection needed --%>
  <% end %>
<% end %>

<%!-- Color Selection - only if product has colors --%>
<%= if @product_config.has_colors && Enum.any?(@product.colors) do %>
  <%!-- existing color selector --%>
<% end %>
```

---

## 5. Multi-Payment Checkout Flow

### Complete User Journey

```
┌─────────────────────────────────────────────────────────────────┐
│                    PRODUCT PAGE (/shop/:slug)                    │
│                                                                  │
│  1. User views product with price ($50.00)                      │
│  2. Product has bux_max_discount: 50 (up to 50% off with BUX)  │
│  3. User adjusts BUX slider → wants to use 1,500 BUX ($15)     │
│  4. Selects size/color (if applicable)                          │
│  5. Clicks "Add to Cart" → item + BUX amount saved to cart     │
│  6. Cart icon in navbar shows item count badge                   │
│  7. User can continue shopping or click cart to checkout         │
│  8. (ROGUE payment is set later at checkout, not here)           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                       CART PAGE (/cart)                           │
│                                                                  │
│  Your BUX balance: 5,000                                        │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ [img] Blockster Tee (L / Black)   ×1  [+][-]   $50.00   │   │
│  │       BUX: [1500___] / 2,500 max  (-$15.00)              │   │
│  │       After BUX: $35.00              [Remove]             │   │
│  │ ─────────────────────────────────────────                 │   │
│  │ [img] Rogue Sneakers (Men's US 10) ×1  [+][-]  $89.00   │   │
│  │       BUX: [0_______] / 0 max  (no BUX discount)         │   │
│  │       After BUX: $89.00              [Remove]             │   │
│  │ ═════════════════════════════════════════                 │   │
│  │ Subtotal (2 items):                       $139.00         │   │
│  │ Total BUX discount:      1,500 BUX       -$15.00         │   │
│  │ Remaining:                                $124.00         │   │
│  │                                                           │   │
│  │ BUX allocated: 1,500 / 5,000 available                    │   │
│  │ (ROGUE payment available at checkout)                      │   │
│  │                                                           │   │
│  │                               [Proceed to Checkout →]     │   │
│  └──────────────────────────────────────────────────────────┘   │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                 CHECKOUT PAGE (/checkout/:order_id)              │
│                                                                  │
│  ┌─ STEP 1: Shipping Info ────────────────────────────────────┐ │
│  │  Full Name: [___________]                                   │ │
│  │  Email:     [___________]                                   │ │
│  │  Address:   [___________]                                   │ │
│  │  City:      [___________]  State: [____]  ZIP: [_____]     │ │
│  │  Country:   [dropdown____]                                  │ │
│  │  Phone:     [___________] (optional)                        │ │
│  │                                             [Continue →]    │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─ STEP 2: Payment Summary ──────────────────────────────────┐ │
│  │                                                             │ │
│  │  Order Items:                                               │ │
│  │  ┌──────────────────────────────────────────────────┐      │ │
│  │  │ Blockster Tee (L / Black) × 1      $50.00       │      │ │
│  │  │   BUX: -$15.00 (1,500 BUX)                      │      │ │
│  │  │ Rogue Sneakers (Men's US 10) × 1   $89.00       │      │ │
│  │  │ ─────────────────────────────────────────        │      │ │
│  │  │ Subtotal:                           $139.00      │      │ │
│  │  │ BUX Discount:                       -$15.00      │      │ │
│  │  │ After BUX:                          $124.00      │      │ │
│  │  └──────────────────────────────────────────────────┘      │ │
│  │                                                             │ │
│  │  ┌─ Pay with ROGUE (optional) ─────────────────────┐      │ │
│  │  │ Your ROGUE balance: 150.00 ROGUE                 │      │ │
│  │  │ Cover with ROGUE: $[50____] of $124.00  [Max]    │      │ │
│  │  │ 10% ROGUE discount: -$5.00                       │      │ │
│  │  │ You send: 225 ROGUE ($45.00 at $0.20 — locked)   │      │ │
│  │  └──────────────────────────────────────────────────┘      │ │
│  │                                                             │ │
│  │  ┌─ Payment Breakdown ─────────────────────────────┐      │ │
│  │  │ BUX discount:       1,500 BUX        -$15.00    │      │ │
│  │  │ ROGUE covers:       225 ROGUE         $50.00     │      │ │
│  │  │   ROGUE discount (10%):               -$5.00     │      │ │
│  │  │ Helio payment (crypto or card):       $74.00     │      │ │
│  │  │ ─────────────────────────────────────────        │      │ │
│  │  │ Order total:                          $139.00    │      │ │
│  │  │ You pay:                              $134.00    │      │ │
│  │  └──────────────────────────────────────────────────┘      │ │
│  │                                                             │ │
│  │                              [Proceed to Payment →]         │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─ STEP 3: Execute Payments ─────────────────────────────────┐ │
│  │                                                             │ │
│  │  Step 3a: BUX Payment                                      │ │
│  │  ┌──────────────────────────────────────────────────┐      │ │
│  │  │ ⏳ Burning 1,500 BUX...                          │      │ │
│  │  │ ✅ BUX burned! TX: 0xabc...                      │      │ │
│  │  └──────────────────────────────────────────────────┘      │ │
│  │                                                             │ │
│  │  Step 3b: ROGUE Payment (10% discount applied)              │ │
│  │  ┌──────────────────────────────────────────────────┐      │ │
│  │  │ ⏳ Sending 225 ROGUE ($45 — covers $50)...       │      │ │
│  │  │ ✅ ROGUE sent! TX: 0xdef...                      │      │ │
│  │  └──────────────────────────────────────────────────┘      │ │
│  │                                                             │ │
│  │  Step 3c: Helio Payment ($74.00 remaining)                 │ │
│  │  ┌──────────────────────────────────────────────────┐      │ │
│  │  │ [Helio Checkout Widget - embedded]                │      │ │
│  │  │  Pay $74.00 in SOL / USDC / ETH / BTC             │      │ │
│  │  │  [Connect Wallet]  [Pay with Card]                │      │ │
│  │  └──────────────────────────────────────────────────┘      │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─ STEP 4: Confirmation ─────────────────────────────────────┐ │
│  │  ✅ Order Confirmed! #BLK-20260216-A3F7                    │ │
│  │  2 items purchased — Thank you!                             │ │
│  │  We'll send shipping updates to your email.                 │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Cart Behavior

- **Persistent**: Cart stored in PostgreSQL, survives browser refresh and re-login
- **One cart per user**: Created on first "Add to Cart" action
- **BUX set on product page, adjustable in cart**: User sets BUX slider on the product page before adding to cart. The chosen BUX amount is saved with the cart item. User can adjust BUX per item in the cart before checkout (e.g. to redistribute after adding more items)
  - BUX input per item: capped at product's `bux_max_discount` and user's remaining unallocated BUX balance
  - Cart shows running total of allocated vs available BUX across all items
- **ROGUE set at checkout (not in cart)**: ROGUE is a single order-level payment applied during checkout Step 2. This is because ROGUE has no per-product cap and the price fluctuates — locking the rate at checkout time (not cart time) is safer
- **Quantity management**: +/- buttons in cart, remove button
- **Cart icon in navbar**: Shows item count badge (similar to standard e-commerce)
- **Unauthenticated users**: "Add to Cart" redirects to login, then back to product page
- **Cart → Checkout**: "Proceed to Checkout" creates order + order_items from cart, then redirects to checkout page. Cart is cleared after successful payment
- **Validation on checkout**: Server re-verifies all BUX/ROGUE amounts don't exceed user's actual balances and product discount caps

### Edge Cases & Payment Combinations

All examples assume $50 product, 10% ROGUE discount.

| Scenario | BUX | ROGUE covers | ROGUE discount | ROGUE sent | Helio | Notes |
|----------|-----|-------------|---------------|-----------|-------|-------|
| Full price, no discounts | $0 | $0 | — | 0 | $50 | Standard crypto checkout |
| BUX discount only | $15 | $0 | — | 0 | $35 | BUX burned, rest via Helio |
| BUX + ROGUE + Helio | $15 | $10 | -$1 | $9 worth | $25 | Three-part payment, ROGUE portion discounted |
| BUX + ROGUE covers full | $15 | $35 | -$3.50 | $31.50 worth | $0 | No Helio, skip widget |
| 100% BUX discount | $50 | $0 | — | 0 | $0 | Free with BUX only |
| ROGUE only, full price | $0 | $50 | -$5 | $45 worth | $0 | Full ROGUE, 10% off |
| ROGUE partial, no BUX | $0 | $20 | -$2 | $18 worth | $30 | ROGUE + Helio |

**Key rules:**
- ROGUE discount only applies to the ROGUE portion, not the Helio portion
- If remaining after BUX + ROGUE is $0, skip Helio entirely — order goes straight to "paid"
- Affiliate commission on the ROGUE portion is 5% of the actual ROGUE tokens sent (post-discount amount)

---

## 6. BUX Payment Mechanics

### How BUX Discount Currently Works

From `ShopLive.Show` (line 8-9, 64-69):

```elixir
@token_value_usd 0.01  # 1 BUX = $0.01

# Max BUX tokens = (price × discount_percent / 100) / token_value
# Example: $50 × 50% = $25 discount = 2,500 BUX at $0.01 each
max_bux_tokens = (product_price * bux_discount / 100) / @token_value_usd
```

The user can slide between 0 and `min(max_bux_tokens, user_bux_balance)`.

### BUX Burn Implementation

BUX tokens are ERC-20 on Rogue Chain. To "burn" them for a purchase:

**Option A: Transfer to Treasury (Recommended)**
- Transfer BUX from buyer's smart wallet to a designated treasury address
- Uses Thirdweb SDK `transfer` function via JS hook
- Treasury address is controlled by the project — tokens can be re-distributed or actually burned later
- Simpler, no new smart contract needed

**Option B: Actual Burn (call burn function)**
- If BUX contract has a `burn` function, call it directly
- Tokens destroyed permanently
- May not be desirable if you want to recycle tokens

**Recommended: Option A (Transfer to Treasury)**

### BUX Minter Service Changes Required

The current BUX Minter service (`bux-minter.fly.dev`) only has a `POST /mint` endpoint — there is **no burn or transfer endpoint**. We need to add one:

**Option 1: New `/transfer-bux` endpoint on BUX Minter** — The minter service already has the private key to interact with the BUX token contract. Add an endpoint that transfers BUX from the buyer's smart wallet to treasury. However, the minter's key can't sign transactions for the buyer's wallet.

**Option 2: Client-side transfer via Thirdweb SDK (Recommended)** — The buyer's smart wallet is already connected client-side via Thirdweb. Use the Thirdweb SDK to call `erc20.transfer()` directly from the JS hook. This is the same pattern used in `WalletTransferHook` (`assets/js/wallet_transfer.js`) for ROGUE transfers. No minter service changes needed.

### Optimistic Balance Deduction

The existing `EngagementTracker` already has the exact pattern we need (used by BuxBooster bets):
- `deduct_user_token_balance(user_id, wallet, token, amount)` — Optimistic Mnesia deduction (line 1578)
- `credit_user_token_balance(user_id, wallet, token, amount)` — Refund on failure (line 1604)

For shop checkout: optimistically deduct BUX in Mnesia when checkout starts, then confirm with on-chain transfer. If transfer fails, credit back.

### BUX Payment Flow (Technical)

```
1. Client: User clicks "Proceed to Payment"
2. Server: Validates order, records intended BUX amount
3. Server: Updates order status to "bux_pending"
4. Client: JS Hook calls Thirdweb SDK:

   const contract = await sdk.getContract(BUX_TOKEN_ADDRESS);
   const tx = await contract.erc20.transfer(TREASURY_ADDRESS, buxAmount);

5. Client: Sends tx hash back to server via phx event:
   pushEvent("bux_payment_complete", { tx_hash: tx.hash })

6. Server: Verifies tx on Rogue Chain RPC:
   - Check tx exists and is confirmed
   - Check to_address == TREASURY_ADDRESS
   - Check value >= expected BUX amount
   - Check from_address == buyer's smart wallet

7. Server: Updates order with bux_burn_tx_hash, status → "bux_paid"
8. Server: Syncs user BUX balance (BuxMinter.sync_user_balances_async)
9. Proceed to ROGUE payment (if any) or Helio payment
```

### BUX Treasury Address

Need to designate a treasury address. Options:
- Use an existing project-controlled wallet
- Create a new dedicated wallet for shop revenue
- The Referral Admin address (`0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad`) could work if appropriate

**Decision needed:** Which address to use as BUX treasury.

---

## 7. ROGUE Payment Mechanics

### How ROGUE Works

ROGUE is the **native gas token** on Rogue Chain (like ETH on Ethereum). Users have ROGUE in their Blockster smart wallets.

From `BuxMinter.get_aggregated_balances/1`, ROGUE balances are fetched alongside BUX and cached in Mnesia `user_bux_balances` table.

### ROGUE Discount

**Paying with ROGUE gives a 10% discount on the ROGUE portion.** This incentivizes ROGUE usage and creates demand for the native token.

The discount rate is **configurable** (stored in application config, changeable via Fly.io secrets or admin panel).

**Example:**
- After BUX discounts, $100 remains
- User wants to pay the full $100 with ROGUE
- 10% ROGUE discount: user only needs to cover $90 worth of ROGUE
- At $0.20/ROGUE, that's 450 ROGUE instead of 500 ROGUE
- The $10 discount is absorbed by the shop (it's a promotional incentive)

**Partial ROGUE example:**
- $100 remains, user pays $50 worth with ROGUE
- 10% discount on the ROGUE portion: user sends $45 worth of ROGUE (225 ROGUE at $0.20)
- $5 discount absorbed by shop
- Remaining $50 goes to Helio (no discount on Helio portion)

### ROGUE Discount Configuration

```elixir
# In runtime.exs or application config:
config :blockster_v2, :rogue_payment_discount_rate, 0.10  # 10% — configurable

# Or as Fly.io secret:
# ROGUE_PAYMENT_DISCOUNT_RATE=0.10
```

### ROGUE-to-USD Conversion

ROGUE needs a USD price to calculate payment value. Options:

**Option A: Use `token_prices` Mnesia table (Recommended)**
The `PriceTracker` GenServer already fetches prices from CoinGecko and caches them in Mnesia. If ROGUE has a CoinGecko listing, use that price. If not, set a fixed rate (admin-configurable).

**Option B: Fixed admin-set rate**
Admin sets ROGUE/USD rate in application config. Simpler but requires manual updates.

**Recommended: Option A if ROGUE is on CoinGecko, otherwise Option B with admin config.**

### ROGUE Payment Flow (Technical)

```
1. User specifies ROGUE amount (in USD) on checkout page
2. Server calculates with discount:
   rogue_discount_rate = 0.10  (configurable)
   usd_to_cover = rogue_usd_input  (what the user wants to cover with ROGUE)
   discounted_usd = usd_to_cover * (1 - rogue_discount_rate)  (actual ROGUE value needed)
   rogue_tokens = discounted_usd / rogue_usd_price
   rogue_discount_saved = usd_to_cover - discounted_usd

   Example: User covers $50, discount 10%:
   discounted_usd = $50 * 0.90 = $45
   rogue_tokens = $45 / $0.20 = 225 ROGUE
   rogue_discount_saved = $5

3. Server validates: usd_to_cover <= remaining_after_bux
4. User clicks "Pay with ROGUE"
5. Client: JS Hook sends native ROGUE transfer via Thirdweb SDK:

   // ROGUE is native token, so use wallet.transfer()
   const tx = await wallet.transfer(TREASURY_ADDRESS, rogueAmountInWei);

6. Client: pushEvent("rogue_payment_complete", { tx_hash: tx.hash })
7. Server: Verifies tx on Rogue Chain RPC:
   - Check tx confirmed
   - Check to == TREASURY_ADDRESS
   - Check value >= expected ROGUE amount (the discounted amount in tokens)
   - Check from == buyer's smart wallet
8. Server: Updates order:
   - rogue_payment_amount = usd_to_cover (full USD value covered)
   - rogue_discount_rate = 0.10
   - rogue_discount_amount = rogue_discount_saved
   - rogue_tokens_sent = actual ROGUE tokens
   - rogue_payment_tx_hash = tx_hash
   - status → "rogue_paid"
9. Server: Syncs ROGUE balance
10. Calculate remaining: helio_amount = remaining_after_bux - usd_to_cover
    If helio_amount > 0, show Helio. If 0, mark as "paid"
```

### Price Locking

**Important:** Lock the ROGUE/USD rate when the user enters the payment review step (Step 2), not at checkout mount. Add a 10-minute expiry timer — if the rate expires, re-fetch and re-lock. This prevents price fluctuation attacks:

```elixir
# At checkout creation, lock the rate
order = %Order{
  # ...
  rogue_usd_rate_locked: current_rogue_usd_rate,  # Add this field
}
```

Add `rogue_usd_rate_locked` to the orders table migration.

---

## 8. Helio Payment Integration

### Creating a Helio Charge (Server-Side)

**Important:** The Charges API requires a pre-created Pay Link ID (`paymentRequestId`). Create one Pay Link with dynamic pricing in the Helio dashboard — this acts as a template for all charges. Each charge creates a single-use checkout session against that Pay Link.

When the remaining amount > $0 after BUX + ROGUE:

```elixir
defmodule BlocksterV2.Helio do
  @api_base "https://api.hel.io/v1"

  def create_charge(order) do
    payload = %{
      paymentRequestId: helio_paylink_id(),  # Pre-created Pay Link with dynamic pricing
      requestAmount: Decimal.to_string(order.helio_payment_amount),
      prepareRequestBody: %{
        customerDetails: %{
          additionalJSON: Jason.encode!(%{
            order_id: order.id,
            order_number: order.order_number
          })
        }
      }
    }

    api_key = Application.get_env(:blockster_v2, :helio_api_key)
    secret_key = Application.get_env(:blockster_v2, :helio_secret_key)

    case Req.post("#{@api_base}/charge/api-key?apiKey=#{api_key}",
           json: payload,
           headers: [{"Authorization", "Bearer #{secret_key}"}],
           receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{charge_id: body["id"], page_url: body["pageUrl"]}}
      {:ok, %{status: status, body: body}} ->
        {:error, "Helio error #{status}: #{inspect(body)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp helio_paylink_id, do: Application.get_env(:blockster_v2, :helio_paylink_id)
end
```

### Embedding Helio Checkout Widget (Client-Side)

Add a JS hook that renders the Helio widget when the charge token is available:

```javascript
// assets/js/hooks/helio_checkout.js
const HelioCheckout = {
  mounted() {
    this.renderWidget();

    this.handleEvent("helio_charge_created", ({ charge_token }) => {
      this.chargeToken = charge_token;
      this.renderWidget();
    });
  },

  renderWidget() {
    if (!this.chargeToken) return;

    // Load Helio SDK script if not already loaded
    if (!window.HelioCheckout) {
      const script = document.createElement('script');
      script.src = 'https://cdn.hel.io/checkout.js';
      script.onload = () => this.initCheckout();
      document.head.appendChild(script);
    } else {
      this.initCheckout();
    }
  },

  initCheckout() {
    const container = this.el;

    new window.HelioCheckout({
      chargeToken: this.chargeToken,
      display: "inline",
      theme: { themeMode: "light" },
      primaryColor: "#CAFC00",
      neutralColor: "#141414",
      onSuccess: (event) => {
        this.pushEvent("helio_payment_success", {
          transaction_id: event.transactionId || event.transaction?.id
        });
      },
      onError: (error) => {
        this.pushEvent("helio_payment_error", { error: error.message });
      },
      onCancel: () => {
        this.pushEvent("helio_payment_cancelled", {});
      },
      additionalJSON: {
        order_id: this.el.dataset.orderId,
        order_number: this.el.dataset.orderNumber
      }
    }).render(container);
  }
};

export default HelioCheckout;
```

### Helio Webhook Handler

```elixir
# lib/blockster_v2_web/controllers/helio_webhook_controller.ex
defmodule BlocksterV2Web.HelioWebhookController do
  use BlocksterV2Web, :controller

  def handle(conn, params) do
    # Verify webhook authenticity via Bearer token
    with {:ok, _} <- verify_webhook_token(conn),
         {:ok, order} <- process_webhook(params) do
      json(conn, %{status: "ok"})
    else
      {:error, :unauthorized} ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})
      {:error, reason} ->
        conn |> put_status(400) |> json(%{error: reason})
    end
  end

  defp verify_webhook_token(conn) do
    expected = Application.get_env(:blockster_v2, :helio_webhook_secret)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token == expected -> {:ok, :verified}
      _ -> {:error, :unauthorized}
    end
  end

  defp process_webhook(%{"event" => "CREATED", "transaction" => tx} = params) do
    meta = Jason.decode!(tx["meta"] || "{}")
    order_id = meta["order_id"]

    case BlocksterV2.Orders.get_order(order_id) do
      nil -> {:error, "order not found"}
      %{status: status} when status in ["paid", "processing", "shipped", "delivered"] ->
        {:ok, :already_processed}  # Idempotent — webhook already handled
      order ->
        BlocksterV2.Orders.complete_helio_payment(order, %{
          helio_transaction_id: tx["id"],
          helio_payer_address: tx["senderAddress"]
        })
    end
  end
end
```

### Route for Webhook

```elixir
# In router.ex, add to the API scope:
scope "/api", BlocksterV2Web do
  pipe_through :api
  post "/helio/webhook", HelioWebhookController, :handle
end
```

---

## 9. Shop Affiliate System

### Overview

Referrers earn 5% commission **in the same currency the buyer paid with**. A single order can produce up to 3 separate affiliate payouts if the buyer used BUX + ROGUE + Helio (crypto or card).

This extends the existing referral system which already:
- Tracks `referrer_id` on the `users` table
- Stores referral records in Mnesia
- Pays signup bonuses (100 BUX) and bet-loss commissions (1% BUX, 0.2% ROGUE)

### Already Prepared in Codebase

1. **Earning type `:shop_purchase`** is already defined in the Mnesia schema enum
2. **UI label already exists**: `earning_type_label(:shop_purchase)` returns "Shop Purchase" (in `member_live/show.ex`)
3. **UI styling already exists**: `earning_type_style(:shop_purchase)` returns "bg-orange-100 text-orange-800"
4. **Mnesia lookup ready**: `Mnesia.dirty_read(:referrals, buyer_user_id)` gives us `{referrer_id, referrer_wallet, referee_wallet}`

### Commission Structure: Same Currency as Buyer

| Payment Method | Affiliate Gets 5% In | How It's Paid | Timing |
|---|---|---|---|
| **BUX** (1,500 BUX burned) | **75 BUX** | Minted via BuxMinter to referrer's smart wallet | Immediate |
| **ROGUE** (50 ROGUE sent) | **2.5 ROGUE** | Transferred from treasury to referrer's smart wallet | Immediate |
| **Crypto via Helio** ($25 USDC) | **$1.25 USDC** | Transferred from our Helio receiving wallet | Immediate |
| **Card via Helio** ($25 card) | **$1.25 USDC** | Paid in USDC after chargeback hold | **Held 30 days** |

### Why Same Currency?

The referrer should receive value in the same form it was paid. If someone pays in ROGUE, the referrer gets ROGUE. If someone pays with USDC on Solana, the referrer gets USDC. This avoids us needing to do currency conversions and is more transparent.

### Multi-Payout Example

Buyer purchases $100 order, pays with: 2,000 BUX ($20) + ROGUE covering $20 (10% discount, sends 90 ROGUE at $0.20 = $18) + $60 USDC via Helio.

Affiliate receives 3 separate payouts:
1. **100 BUX** (5% of 2,000 BUX burned) — minted immediately
2. **4.5 ROGUE** (5% of 90 ROGUE sent) — transferred from treasury immediately
3. **$3.00 USDC** (5% of $60) — transferred on Ethereum (batched if under $10 threshold)

If the $60 was paid by **card** instead of crypto, the USDC payout is held for 30 days.

### Chargeback Protection for Card Payments

When the Helio portion is paid by card (`showPayWithCard: true`), there is chargeback risk. Credit card chargebacks can be filed up to 120 days, but most happen within 30 days.

**Policy:**
- Card payment affiliate payouts are created with `status: "held"` and `held_until: now + 30 days`
- A periodic job checks for held payouts past their hold date and pays them out
- If a chargeback occurs before the hold expires, the payout is cancelled (`status: "failed"`)
- BUX and ROGUE portions are still paid immediately (no chargeback risk on-chain)
- Card vs crypto is detected from the Helio webhook payload (payment method field)

```elixir
# Periodic job (runs every hour)
def process_held_payouts do
  now = DateTime.utc_now()

  from(p in AffiliatePayout,
    where: p.status == "held",
    where: p.held_until <= ^now
  )
  |> Repo.all()
  |> Enum.each(&pay_out_affiliate/1)
end
```

### Payout Mechanics by Currency

**BUX Commission:**
```
1. Calculate: 5% of bux_tokens_burned
2. BuxMinter.mint_bux(referrer_wallet, bux_commission, referrer_id, nil, :shop_affiliate)
3. Record in affiliate_payouts table with tx_hash
```

**ROGUE Commission:**
```
1. Calculate: 5% of rogue_tokens_sent
2. Server-side transfer from SHOP_TREASURY_ADDRESS to referrer's smart_wallet_address
   - Use BuxMinter service or direct RPC call to Rogue Chain
   - Treasury must hold sufficient ROGUE balance (funded from buyer payments)
3. Record in affiliate_payouts table with tx_hash
```

**Crypto/Card Commission (Helio portion):**
```
1. Calculate: 5% of helio_payment_amount in USD
2. Always paid as USDC on Ethereum, regardless of which crypto/fiat the buyer used
3. Set minimum payout threshold of $10 — batch smaller commissions weekly to amortize Ethereum gas costs
4. For card payments: create with status "held", held_until: now + 30 days (chargeback protection)
5. Record in affiliate_payouts table
```

### Helio Commission: Always Paid in USDC on Ethereum

Regardless of which crypto or fiat the buyer used via Helio (SOL, ETH, BTC, USDC, card), the affiliate commission for the Helio portion is always paid as **USDC on Ethereum** at the current exchange rate.

This simplifies multi-chain complexity to a single chain + token:
- We hold USDC on Ethereum in a designated affiliate payout wallet
- On payout, convert the 5% commission amount to USDC equivalent at current rate
- Transfer USDC from our payout wallet to referrer's Ethereum address
- Referrer needs an Ethereum address to receive Helio commissions (can be their Blockster smart wallet if it supports Ethereum, or an external wallet they provide)

**For card payments:** Same approach (USDC on Ethereum), but held 30 days first.

### Minimum Payout Threshold

Ethereum gas fees ($2-5 per transfer) can exceed small USDC commissions. To prevent uneconomical payouts:
- BUX and ROGUE commissions: paid immediately (Rogue Chain gas is negligible)
- USDC on Ethereum commissions: batched weekly if individual payout < $10
- Accumulated payouts are released in a single batch transaction to amortize gas

### BuxMinter Changes Required

Add `:shop_affiliate` to the valid reward types in `bux_minter.ex`:

```elixir
# Currently:
when reward_type in [:read, :x_share, :video_watch, :signup, :phone_verified]

# Change to:
when reward_type in [:read, :x_share, :video_watch, :signup, :phone_verified, :shop_affiliate]
```

### Affiliate Link for Shop

The existing referral system uses wallet-based referral links. Referral attribution happens automatically:
- If `buyer.referrer_id` is set (from signup referral), they earn commission
- No special shop-specific referral link needed

---

## 10. Order Fulfillment (Email + Telegram)

### Fulfillment Notification Trigger

When an order is fully paid (status → "paid"):
1. Send notification email to fulfiller
2. Send Telegram message to fulfillment channel
3. Update order: `fulfillment_notified_at = DateTime.utc_now()`

### Email Implementation (Swoosh)

Phoenix already includes Swoosh for email. Create a fulfillment mailer:

```elixir
defmodule BlocksterV2.OrderMailer do
  import Swoosh.Email

  def fulfillment_notification(order) do
    new()
    |> to({"Fulfillment Team", fulfiller_email()})
    |> from({"Blockster Shop", "shop@blockster.com"})
    |> subject("🛒 New Order ##{order.order_number}")
    |> html_body(render_fulfillment_email(order))
    |> text_body(render_fulfillment_text(order))
  end

  defp render_fulfillment_email(order) do
    # order is preloaded with :order_items
    items_html = Enum.map_join(order.order_items, "", fn item ->
      """
      <li>
        <strong>#{item.product_title}</strong>
        #{if item.variant_title, do: " — #{item.variant_title}", else: ""}
        × #{item.quantity}
        ($#{item.unit_price} each)
      </li>
      """
    end)

    """
    <h2>New Order ##{order.order_number}</h2>
    <p><strong>Date:</strong> #{Calendar.strftime(order.inserted_at, "%Y-%m-%d %H:%M UTC")}</p>

    <h3>Items (#{length(order.order_items)})</h3>
    <ul>#{items_html}</ul>

    <h3>Shipping Address</h3>
    <p>
      #{order.shipping_name}<br/>
      #{order.shipping_address_line1}<br/>
      #{if order.shipping_address_line2, do: order.shipping_address_line2 <> "<br/>", else: ""}
      #{order.shipping_city}, #{order.shipping_state} #{order.shipping_postal_code}<br/>
      #{order.shipping_country}<br/>
      #{if order.shipping_phone, do: "Phone: " <> order.shipping_phone, else: ""}
    </p>

    <h3>Payment Summary</h3>
    <table>
      <tr><td>Subtotal:</td><td>$#{order.subtotal}</td></tr>
      <tr><td>BUX Discount:</td><td>-$#{order.bux_discount_amount}</td></tr>
      <tr><td>ROGUE Payment:</td><td>$#{order.rogue_payment_amount}</td></tr>
      <tr><td>Helio Payment:</td><td>$#{order.helio_payment_amount} (#{order.helio_payment_currency || "N/A"})</td></tr>
      <tr><td><strong>Total:</strong></td><td><strong>$#{order.total_paid}</strong></td></tr>
    </table>

    <p><em>Contact: #{order.shipping_email}</em></p>
    """
  end
end
```

### Telegram Bot Implementation

Use Telegram Bot API directly via `Req` (no extra dependency needed):

```elixir
defmodule BlocksterV2.TelegramNotifier do
  @telegram_api "https://api.telegram.org"

  def send_order_notification(order) do
    # order is preloaded with :order_items
    message = format_order_message(order)

    Req.post(
      "#{@telegram_api}/bot#{bot_token()}/sendMessage",
      json: %{
        chat_id: channel_id(),
        text: message,
        parse_mode: "HTML"
      },
      receive_timeout: 10_000
    )
  end

  defp format_order_message(order) do
    items_text = Enum.map_join(order.order_items, "\n", fn item ->
      "  • #{item.product_title}#{if item.variant_title, do: " (#{item.variant_title})", else: ""} ×#{item.quantity} — $#{item.subtotal}"
    end)

    """
    🛒 <b>New Order ##{order.order_number}</b>
    <b>Items:</b> #{length(order.order_items)}
    #{items_text}

    <b>Ship To:</b>
    #{order.shipping_name}
    #{order.shipping_address_line1}
    #{if order.shipping_address_line2, do: order.shipping_address_line2 <> "\n", else: ""}#{order.shipping_city}, #{order.shipping_state} #{order.shipping_postal_code}
    #{order.shipping_country}
    #{if order.shipping_phone, do: "📞 " <> order.shipping_phone, else: ""}

    <b>Payment:</b>
    Subtotal: $#{order.subtotal}
    BUX: -$#{order.bux_discount_amount} (#{order.bux_tokens_burned} BUX)
    ROGUE: -$#{order.rogue_payment_amount} (#{order.rogue_tokens_sent} ROGUE)
    Helio: $#{order.helio_payment_amount} (#{order.helio_payment_currency || "N/A"})
    <b>Total: $#{order.total_paid}</b>

    📧 #{order.shipping_email}
    """
  end

  defp bot_token, do: Application.get_env(:blockster_v2, :telegram_bot_token)
  defp channel_id, do: Application.get_env(:blockster_v2, :telegram_fulfillment_channel_id)
end
```

### Telegram Setup Checklist

- [ ] Create a Telegram bot via @BotFather
- [ ] Get bot token
- [ ] Create a private Telegram channel for fulfillment
- [ ] Add bot to channel as admin
- [ ] Get channel ID (send a message, then fetch via `getUpdates`)
- [ ] Store as Fly.io secrets: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_FULFILLMENT_CHANNEL_ID`

### Combined Fulfillment Notification

```elixir
defmodule BlocksterV2.Orders.Fulfillment do
  def notify(order) do
    tasks = [
      Task.async(fn -> BlocksterV2.OrderMailer.fulfillment_notification(order) |> BlocksterV2.Mailer.deliver() end),
      Task.async(fn -> BlocksterV2.TelegramNotifier.send_order_notification(order) end)
    ]

    Task.await_many(tasks, 15_000)

    BlocksterV2.Orders.update_order(order, %{
      fulfillment_notified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end
end
```

---

## 11. Backend Implementation

### New Modules

```
lib/blockster_v2/
├── cart/
│   ├── cart.ex                # Cart schema
│   └── cart_item.ex           # CartItem schema
├── cart.ex                    # Cart context (add/remove/update items, totals)
├── orders/
│   ├── order.ex               # Order schema
│   ├── order_item.ex          # OrderItem schema
│   ├── affiliate_payout.ex    # AffiliatePayout schema
│   └── fulfillment.ex         # Email + Telegram notification
├── orders.ex                  # Orders context (CRUD, payment processing)
├── helio.ex                   # Helio API client
├── telegram_notifier.ex       # Telegram Bot API client
├── order_mailer.ex            # Swoosh email templates
├── affiliate_payout_worker.ex # Periodic job for held card payouts
├── shop/
│   ├── product_config.ex      # ProductConfig schema (new)
│   └── ... (existing files)
└── shop.ex                    # Existing - add product_config functions

lib/blockster_v2_web/
├── live/
│   ├── cart_live/
│   │   ├── index.ex           # Cart page LiveView
│   │   └── index.html.heex   # Cart template
│   └── checkout_live/
│       ├── index.ex           # Checkout LiveView
│       └── index.html.heex   # Checkout template
├── controllers/
│   └── helio_webhook_controller.ex  # Webhook handler
└── ...
```

### Cart Context (`lib/blockster_v2/cart.ex`)

```elixir
defmodule BlocksterV2.Cart do
  alias BlocksterV2.{Repo, Cart.Cart, Cart.CartItem}
  import Ecto.Query

  def get_or_create_cart(user_id) do
    case Repo.get_by(Cart, user_id: user_id) do
      nil -> %Cart{user_id: user_id} |> Repo.insert()
      cart -> {:ok, cart}
    end
  end

  def add_item(user_id, attrs) do
    {:ok, cart} = get_or_create_cart(user_id)

    # Check for existing item with same product+variant (increment qty)
    case Repo.get_by(CartItem,
      cart_id: cart.id,
      product_id: attrs.product_id,
      variant_id: attrs[:variant_id]
    ) do
      nil ->
        %CartItem{cart_id: cart.id}
        |> CartItem.changeset(attrs)
        |> Repo.insert()
      existing ->
        existing
        |> CartItem.changeset(%{quantity: existing.quantity + (attrs[:quantity] || 1)})
        |> Repo.update()
    end
  end

  def list_items(user_id) do
    case Repo.get_by(Cart, user_id: user_id) do
      nil -> []
      cart ->
        CartItem
        |> where([ci], ci.cart_id == ^cart.id)
        |> preload([ci], [:product, :variant, product: :product_config])
        |> Repo.all()
    end
  end

  def item_count(user_id) do
    case Repo.get_by(Cart, user_id: user_id) do
      nil -> 0
      cart ->
        CartItem
        |> where([ci], ci.cart_id == ^cart.id)
        |> Repo.aggregate(:sum, :quantity) || 0
    end
  end

  def clear_cart(user_id) do
    case Repo.get_by(Cart, user_id: user_id) do
      nil -> :ok
      cart ->
        CartItem |> where([ci], ci.cart_id == ^cart.id) |> Repo.delete_all()
        :ok
    end
  end
end
```

### Orders Context (`lib/blockster_v2/orders.ex`)

```elixir
defmodule BlocksterV2.Orders do
  alias BlocksterV2.{Repo, Orders.Order, Orders.OrderItem, Orders.AffiliatePayout, BuxMinter}

  @doc "Create order + order_items from cart items. Called at 'Proceed to Checkout'."
  def create_order_from_cart(user, cart_items) do
    # Snapshot each cart item
    order_items_attrs = Enum.map(cart_items, fn ci ->
      variant_title = build_variant_title(ci.variant)
      unit_price = ci.variant && ci.variant.price || List.first(ci.product.variants).price
      subtotal = Decimal.mult(unit_price, ci.quantity)
      bux_usd = Decimal.mult(Decimal.new(ci.bux_tokens_to_redeem), Decimal.new("0.01"))

      %{
        product_id: ci.product_id,
        product_title: ci.product.title,
        product_image: get_first_image(ci.product),
        variant_id: ci.variant_id,
        variant_title: variant_title,
        quantity: ci.quantity,
        unit_price: unit_price,
        subtotal: subtotal,
        bux_discount_amount: bux_usd,
        bux_tokens_redeemed: ci.bux_tokens_to_redeem
      }
    end)

    total_subtotal = Enum.reduce(order_items_attrs, Decimal.new(0), &Decimal.add(&1.subtotal, &2))
    total_bux_discount = Enum.reduce(order_items_attrs, Decimal.new(0), &Decimal.add(&1.bux_discount_amount, &2))
    total_bux_tokens = Enum.reduce(order_items_attrs, 0, &(&1.bux_tokens_redeemed + &2))

    Repo.transaction(fn ->
      {:ok, order} = %Order{}
        |> Order.changeset(%{
          order_number: generate_order_number(),
          user_id: user.id,
          subtotal: total_subtotal,
          bux_discount_amount: total_bux_discount,
          bux_tokens_burned: total_bux_tokens,
          helio_payment_amount: Decimal.sub(total_subtotal, total_bux_discount),
          total_paid: total_subtotal,  # Updated after ROGUE discount is applied
          status: "pending",
          referrer_id: user.referrer_id,
          affiliate_commission_rate: Decimal.new("0.05")
        })
        |> Repo.insert()

      # Create order items
      Enum.each(order_items_attrs, fn attrs ->
        %OrderItem{order_id: order.id}
        |> OrderItem.changeset(attrs)
        |> Repo.insert!()
      end)

      order
    end)
  end

  defp process_paid_order(order) do
    order = Repo.preload(order, :order_items)

    # 1. Send fulfillment notifications
    BlocksterV2.Orders.Fulfillment.notify(order)

    # 2. Process affiliate commissions (one per currency used)
    process_affiliate_payouts(order)

    # 3. Broadcast order update to buyer's LiveView
    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "order:#{order.id}", {:order_updated, order})
  end

  @doc "Creates up to 3 affiliate payout records (BUX, ROGUE, Helio currency)"
  defp process_affiliate_payouts(%{referrer_id: nil}), do: :ok
  defp process_affiliate_payouts(order) do
    referrer = Repo.get(BlocksterV2.Accounts.User, order.referrer_id)

    case referrer do
      nil -> :ok
      %{smart_wallet_address: nil} -> :ok
      referrer ->
        rate = order.affiliate_commission_rate || Decimal.new("0.05")
        is_card = order.helio_payment_currency == "CARD"

        payouts = []

        # BUX commission (5% of BUX tokens burned — integer field, wrap in Decimal for math)
        payouts = if order.bux_tokens_burned > 0 do
          bux_commission = Decimal.new(order.bux_tokens_burned) |> Decimal.mult(rate) |> Decimal.round(0) |> Decimal.to_integer()
          [%{currency: "BUX", basis_amount: order.bux_tokens_burned,
                     commission_amount: bux_commission, status: "pending"} | payouts]
        else
          payouts
        end

        # ROGUE commission (5% of ROGUE tokens sent)
        payouts = if Decimal.compare(order.rogue_tokens_sent, 0) == :gt do
          rogue_commission = Decimal.mult(order.rogue_tokens_sent, rate)
          [%{currency: "ROGUE", basis_amount: order.rogue_tokens_sent,
                     commission_amount: rogue_commission, status: "pending"} | payouts]
        else
          payouts
        end

        # Helio commission (5% of helio amount — held if card payment)
        payouts = if Decimal.compare(order.helio_payment_amount, 0) == :gt do
          helio_commission = Decimal.mult(order.helio_payment_amount, rate)
          helio_status = if is_card, do: "held", else: "pending"
          held_until = if is_card, do: DateTime.add(DateTime.utc_now(), 30, :day)
          [%{
            currency: order.helio_payment_currency || "USDC",
            basis_amount: order.helio_payment_amount,
            commission_amount: helio_commission,
            status: helio_status,
            held_until: held_until
          } | payouts]
        else
          payouts
        end

        # Insert and process each payout
        Enum.each(payouts, fn payout_attrs ->
          {:ok, payout} = %AffiliatePayout{order_id: order.id, referrer_id: order.referrer_id}
            |> AffiliatePayout.changeset(Map.put(payout_attrs, :commission_rate, rate))
            |> Repo.insert()

          if payout.status == "pending", do: execute_affiliate_payout(payout, referrer)
        end)
    end
end
```

### Checkout LiveView (`lib/blockster_v2_web/live/checkout_live/index.ex`)

```elixir
defmodule BlocksterV2Web.CheckoutLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.{Orders, Shop, BuxMinter, EngagementTracker}

  @token_value_usd 0.01

  @impl true
  def mount(%{"order_id" => order_id}, _session, socket) do
    order = Orders.get_order(order_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "order:#{order_id}")
    end

    {:ok,
     socket
     |> assign(:order, order)
     |> assign(:step, :shipping)  # :shipping → :review → :payment → :confirmation
     |> assign(:shipping_form, to_form(%{}))
     |> assign_rogue_balance()
    }
  end

  # Handle payment step progression
  # Step 1: Shipping info collected
  # Step 2: Review & set ROGUE amount
  # Step 3: Execute payments in order (BUX → ROGUE → Helio)
  # Step 4: Confirmation
end
```

---

## 12. Frontend Implementation

### New Routes

```elixir
# In router.ex, add to authenticated scope:
live "/cart", CartLive.Index, :index
live "/checkout/:order_id", CheckoutLive.Index, :index
```

### Modified Product Page ("Add to Cart" Button)

Replace the disabled "Shopping Cart Coming Soon" button:

```heex
<%= if @product_config && @product_config.checkout_enabled do %>
  <button
    phx-click="add_to_cart"
    phx-disable-with="Adding..."
    class="w-full bg-gradient-to-b from-[#8AE388] to-[#BAF55F] text-[#141414] font-haas_medium_65 text-lg py-4 px-6 rounded-full transition-all hover:shadow-lg hover:scale-[1.02] active:scale-[0.98] cursor-pointer"
    disabled={requires_size?(@product_config) && is_nil(@selected_size)}
  >
    <%= if requires_size?(@product_config) && is_nil(@selected_size) do %>
      Select a Size
    <% else %>
      Add to Cart — $<%= :erlang.float_to_binary(discounted_price_top, decimals: 2) %>
    <% end %>
  </button>
<% else %>
  <button
    class="w-full bg-gradient-to-b from-[#8AE388] to-[#BAF55F] text-[#141414] font-haas_medium_65 text-lg py-4 px-6 rounded-full transition-all opacity-50 cursor-not-allowed"
    disabled
  >
    Coming Soon
  </button>
<% end %>
```

### "Add to Cart" Handler

```elixir
def handle_event("add_to_cart", _, socket) do
  %{product: product, tokens_to_redeem: bux_tokens, selected_size: size,
    selected_color: color, quantity: qty} = socket.assigns

  config = socket.assigns.product_config

  cond do
    config.has_sizes && is_nil(size) ->
      {:noreply, put_flash(socket, :error, "Please select a size")}
    config.has_colors && is_nil(color) ->
      {:noreply, put_flash(socket, :error, "Please select a color")}
    true ->
      variant = find_variant(product, size, color)
      user = socket.assigns.current_user

      case BlocksterV2.Cart.add_item(user.id, %{
        product_id: product.id,
        variant_id: variant && variant.id,
        quantity: qty,
        bux_tokens_to_redeem: bux_tokens
      }) do
        {:ok, _cart_item} ->
          cart_count = BlocksterV2.Cart.item_count(user.id)
          {:noreply,
           socket
           |> assign(:cart_count, cart_count)
           |> put_flash(:info, "Added to cart!")
          }
        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not add to cart")}
      end
  end
end
```

### Cart Page (`CartLive.Index`)

```elixir
defmodule BlocksterV2Web.CartLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Cart

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    cart_items = Cart.list_items(user.id)  # Preloads product, variant, product_config

    {:ok,
     socket
     |> assign(:cart_items, cart_items)
     |> assign(:totals, Cart.calculate_totals(cart_items))
    }
  end

  # handle_event "update_quantity", "remove_item", "proceed_to_checkout"
  # "proceed_to_checkout" creates order + order_items from cart, redirects to /checkout/:id
end
```

### Cart Icon in Navbar

Add a cart icon with badge to the main layout (accessible from every page):

```heex
<.link navigate={~p"/cart"} class="relative cursor-pointer">
  <.icon name="hero-shopping-cart-solid" class="w-6 h-6 text-zinc-400 hover:text-white" />
  <%= if @cart_count > 0 do %>
    <span class="absolute -top-1 -right-1 bg-[#CAFC00] text-black text-xs font-bold rounded-full w-5 h-5 flex items-center justify-center">
      <%= @cart_count %>
    </span>
  <% end %>
</.link>
```

### JS Hooks Needed

1. **`BuxPaymentHook`** — Handles BUX token transfer via Thirdweb SDK
2. **`RoguePaymentHook`** — Handles ROGUE native transfer via Thirdweb SDK
3. **`HelioCheckoutHook`** — Renders and manages Helio checkout widget
4. Modify existing **`TokenInput`** hook if needed

### Checkout Page Layout

```
┌────────────────────────────────────────────────┐
│  ← Back to Shop          Order #BLK-20260216   │
├────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────┐  ┌────────────────────────────┐  │
│  │ [image]  │  │ Product Title               │  │
│  │          │  │ Size: L / Color: Black       │  │
│  │          │  │ Qty: 1                       │  │
│  │          │  │ $50.00                       │  │
│  └──────────┘  └────────────────────────────┘  │
│                                                 │
│  ────── Step Progress: [1]─[2]─[3]─[4] ──────  │
│                                                 │
│  [Current Step Content]                         │
│                                                 │
└────────────────────────────────────────────────┘
```

> **Important:** Use `phx-disable-with` on ALL payment buttons (BUX burn, ROGUE send, Helio checkout) to prevent double-clicks during on-chain transactions. Example: `phx-disable-with="Processing payment..."`.

---

## 13. Admin Interface

### New Admin Pages

1. **Orders List** (`/admin/orders`) — View all orders with filters (status, date)
2. **Order Detail** (`/admin/orders/:id`) — View full order, update status, add tracking
3. **Product Config** — Added to existing product edit form

### Orders Admin LiveView

```
/admin/orders
┌───────────────────────────────────────────────────────────┐
│ Orders                              [Filter ▼] [Export]    │
├──────┬───────────────┬─────────┬────────┬────────┬───────┤
│ #    │ Items         │ Buyer   │ Total  │ Status │ Date  │
├──────┼───────────────┼─────────┼────────┼────────┼───────┤
│ BLK..│ Tee, Sneakers │ john@.. │ $139   │ 🟡 paid│ 2/16  │
│ BLK..│ Sunglasses    │ jane@.. │ $35    │ 🟢 ship│ 2/15  │
└──────┴───────────────┴─────────┴────────┴────────┴───────┘
```

Order detail page shows all items, per-item fulfillment status, payment breakdown (BUX/ROGUE/Helio), and affiliate payout records.

### Order Status Update

Admin can update order status and add tracking info:
- **Processing** → Order received, being prepared
- **Shipped** → Add tracking number + URL (per item, since items may ship separately)
- **Delivered** → Mark as delivered
- **Cancelled** → With refund handling (manual for now)

### Product Edit: Config Section

Add a new section to `ProductLive.Form`:

```
┌── Product Configuration ──────────────────────────────────────┐
│                                                                │
│  ☑ Enable Checkout                                            │
│                                                                │
│  ☑ Has Sizes                                                  │
│    Size Type: [Clothing ▼]                                     │
│    • Clothing: [☑S] [☑M] [☑L] [☑XL] [☐XXL] [☐3XL]          │
│    • Men's Shoes: [☐US7] [☐US8] [☑US9] [☑US10] [☑US11] ...  │
│    • Women's Shoes: [☐US5] [☐US6] [☑US7] [☑US8] [☑US9] ...  │
│    • Unisex Shoes (shows Men's + Women's toggle on page)       │
│    • One Size                                                  │
│                                                                │
│  ☑ Has Colors   → [☑Black] [☑White] [☐Grey]                  │
│  ☑ Requires Shipping (uncheck for digital)                     │
│                                                                │
│  Affiliate Commission: [5__]% (leave blank = 5%)               │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Admin Routes

```elixir
# Add to admin scope in router.ex:
live "/admin/orders", OrdersAdminLive, :index
live "/admin/orders/:id", OrderAdminLive.Show, :show
```

---

## 14. Security Considerations

### Payment Verification

1. **BUX burn verification** — After JS reports tx_hash:
   - RPC call to Rogue Chain to verify transaction
   - Check `to_address` matches treasury
   - Check `value` matches expected BUX amount
   - Check `from_address` matches buyer's smart wallet
   - Check transaction is confirmed (not pending)

2. **ROGUE payment verification** — Same as BUX but for native transfer

3. **Helio payment verification** — Webhook with Bearer token authentication
   - Verify webhook secret matches
   - Cross-check charge_id with our order record
   - Verify amount matches expected

### Race Conditions

1. **Double-order prevention** — Use database unique constraint on `order_number`
2. **Double-payment prevention** — Check order status before processing each payment step; reject if already processed
3. **BUX balance check** — Re-verify balance server-side before initiating burn (not just client-side)
4. **Concurrent checkout** — Cart → Order conversion is atomic. Old unpaid orders expire (cleanup job after 30 minutes)
5. **Cart concurrency** — Unique index on `(cart_id, product_id, variant_id)` prevents duplicate items

### Inventory Management

The existing `product_variants` table already has `inventory_quantity`, `inventory_policy` ("deny"/"continue"), and `inventory_management` fields. The checkout system must use these:

1. **Add to Cart** — Check `inventory_quantity > 0` or `inventory_policy == "continue"`. Show "Out of Stock" if denied
2. **Create Order** — Decrement `inventory_quantity` atomically inside the `create_order_from_cart` Ecto transaction:
   ```elixir
   # Inside the Repo.transaction in create_order_from_cart:
   Enum.each(order_items_attrs, fn attrs ->
     # Decrement variant inventory
     if attrs.variant_id do
       {1, _} = from(v in ProductVariant,
         where: v.id == ^attrs.variant_id,
         where: v.inventory_quantity >= ^attrs.quantity or v.inventory_policy == "continue"
       ) |> Repo.update_all(inc: [inventory_quantity: -attrs.quantity])
     end
   end)
   ```
3. **Order Expiry/Cancellation** — Re-increment `inventory_quantity` when orders expire or are cancelled
4. **Cart Validation** — On cart page mount, revalidate stock availability and remove/warn about out-of-stock items

### Serialized BUX Balance Deduction

To prevent concurrent BUX double-spend across multiple browser tabs, all BUX balance deductions for shop checkout are routed through a serialized GenServer:

```elixir
defmodule BlocksterV2.Shop.BalanceManager do
  use GenServer

  # Registered globally via GlobalSingleton to ensure one instance across cluster
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: {:global, __MODULE__})
  end

  @doc "Atomically deduct BUX for a checkout. Returns {:ok, new_balance} or {:error, :insufficient}"
  def deduct_bux(user_id, amount) do
    GenServer.call({:global, __MODULE__}, {:deduct_bux, user_id, amount}, 10_000)
  end

  def credit_bux(user_id, amount) do
    GenServer.call({:global, __MODULE__}, {:credit_bux, user_id, amount}, 10_000)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:deduct_bux, user_id, amount}, _from, state) do
    case EngagementTracker.get_user_bux_balance(user_id) do
      balance when balance >= amount ->
        EngagementTracker.deduct_user_token_balance(user_id, nil, "BUX", amount)
        {:reply, {:ok, balance - amount}, state}
      balance ->
        {:reply, {:error, :insufficient, balance}, state}
    end
  end

  def handle_call({:credit_bux, user_id, amount}, _from, state) do
    EngagementTracker.credit_user_token_balance(user_id, nil, "BUX", amount)
    {:reply, :ok, state}
  end
end
```

Add to `application.ex` children list:
```elixir
{BlocksterV2.GlobalSingleton, {BlocksterV2.Shop.BalanceManager, name: {:global, BlocksterV2.Shop.BalanceManager}}},
```

### Cart Validation on Load

When the cart page mounts, revalidate all items against current product data:

```elixir
def validate_cart_items(cart_items) do
  Enum.reduce(cart_items, {[], []}, fn item, {valid, warnings} ->
    product = Repo.get(Product, item.product_id) |> Repo.preload([:product_config, :variants])

    cond do
      is_nil(product) ->
        Cart.remove_item(item.id)
        {valid, ["#{item.product_title} is no longer available" | warnings]}

      not product.product_config.checkout_enabled ->
        Cart.remove_item(item.id)
        {valid, ["#{product.title} is no longer available for purchase" | warnings]}

      item.variant_id && is_nil(Enum.find(product.variants, &(&1.id == item.variant_id))) ->
        Cart.remove_item(item.id)
        {valid, ["#{product.title} variant no longer available" | warnings]}

      true ->
        # Cap BUX to current max
        max_bux = calculate_max_bux(product)
        capped_bux = min(item.bux_tokens_to_redeem, max_bux)
        if capped_bux != item.bux_tokens_to_redeem do
          Cart.update_item_bux(item.id, capped_bux)
        end
        {[%{item | bux_tokens_to_redeem: capped_bux} | valid], warnings}
    end
  end)
end
```

### Anti-Fraud

1. **Require authentication** — Only logged-in users can checkout
2. **Rate limit** — Max 5 orders per user per hour (prevent abuse)
3. **BUX discount cap** — Already enforced by `bux_max_discount` on product
4. **Price locked at order creation** — No TOCTOU on price changes
5. **ROGUE rate locked** — Lock rate at checkout start, not payment time

### Chargeback Protection

Card payments via Helio carry chargeback risk (up to 120 days, most within 30):

1. **Affiliate payouts for card payments are held 30 days** before release
2. **Helio webhook includes payment method** — detect card vs crypto
3. **If chargeback occurs**: Cancel held affiliate payout, mark order as "refunded"
4. **Physical goods**: Already shipped, so chargebacks are a cost of business for the product itself. Only the affiliate commission is protected by the hold
5. **Future consideration**: For high-value card orders, consider requiring phone verification or additional KYC

### Order Expiry

Unpaid orders should expire to prevent inventory lock-up:

```elixir
# Periodic cleanup (every 5 minutes)
def cleanup_expired_orders do
  thirty_min_ago = DateTime.add(DateTime.utc_now(), -30, :minute)

  from(o in Order,
    where: o.status in ["pending", "bux_paid", "rogue_paid", "helio_pending"],
    where: o.inserted_at < ^thirty_min_ago
  )
  |> Repo.update_all(set: [status: "expired"])
end
```

### Partial Payment Recovery

If a later payment step fails after earlier steps succeed (e.g., BUX burned but ROGUE payment fails), the system must be able to refund on-chain payments:

```elixir
defmodule BlocksterV2.Orders.Refund do
  def refund_order(order) do
    # Refund BUX: mint back to user's wallet
    if order.bux_burn_tx_hash && is_nil(order.refund_bux_tx_hash) do
      user = Repo.get(BlocksterV2.Accounts.User, order.user_id)
      {:ok, _} = BuxMinter.mint_bux(
        user.smart_wallet_address,
        order.bux_tokens_burned,
        order.user_id,
        nil,
        :shop_refund
      )
      # Update order with refund tx hash
    end

    # Refund ROGUE: transfer from treasury back to user's wallet
    if order.rogue_payment_tx_hash && is_nil(order.refund_rogue_tx_hash) do
      # Server-side ROGUE transfer from treasury to user's smart wallet
      # Uses the same RPC mechanism as affiliate ROGUE payouts
    end

    Orders.update_order(order, %{status: "refunded", refunded_at: DateTime.utc_now()})
  end
end
```

The order expiry cleanup job should call `refund_order/1` for expired orders that have partial payments:

```elixir
def cleanup_expired_orders do
  thirty_min_ago = DateTime.add(DateTime.utc_now(), -30, :minute)

  expired_orders = from(o in Order,
    where: o.status in ["pending", "bux_pending", "bux_paid", "rogue_pending", "rogue_paid", "helio_pending"],
    where: o.inserted_at < ^thirty_min_ago
  ) |> Repo.all()

  Enum.each(expired_orders, fn order ->
    # Refund any on-chain payments before marking expired
    if order.bux_burn_tx_hash || order.rogue_payment_tx_hash do
      Refund.refund_order(order)
    end

    Orders.update_order(order, %{status: "expired"})
  end)
end
```

---

## 15. Implementation Phases

### Testing Strategy

After completing each phase, write and run tests before moving to the next phase. This ensures each layer is solid before building on top of it. Test categories per phase:

- **Schema phases**: Changeset validation tests (required fields, constraints, enums)
- **Context phases**: Unit tests for context functions (CRUD, calculations, edge cases)
- **LiveView phases**: LiveView integration tests (mount, events, navigation, flash messages)
- **Payment phases**: Mock-based tests for on-chain calls and external APIs (Helio, BuxMinter)
- **Worker phases**: GenServer tests with controlled time (process_held_payouts, order expiry)
- **Admin phases**: Admin LiveView tests with authorization checks

### Phase 1: Foundation (Backend)
**Core database, schemas, and contexts**

1. Create migration for `carts` + `cart_items` tables
2. Create migration for `orders` + `order_items` tables
3. Create migration for `affiliate_payouts` table
4. Create migration for `product_configs` table
5. Create `Cart`, `CartItem` schemas + `Cart` context
6. Create `Order`, `OrderItem`, `AffiliatePayout` schemas + `Orders` context
7. Create `ProductConfig` schema + add CRUD to `Shop` context, add `has_one :product_config` to Product schema
8. Add `:shop_affiliate` and `:shop_refund` to `BuxMinter` valid reward types
9. Add routes: `/cart`, `/checkout/:order_id`, `/api/helio/webhook`, admin routes
10. Wire inventory checks into cart add and order creation flows
11. Add `Shop.BalanceManager` GenServer (serialized BUX deductions)

**Tests**: Schema changeset tests for all 6 schemas. Cart context unit tests (add, remove, update, calculate_totals). Orders context unit tests (create_order_from_cart, generate_order_number). ProductConfig CRUD tests.

### Phase 2: Product Configuration + Shoe Sizes
**Admin form updates + size system**

1. Add product config section to `ProductLive.Form` with size type dropdown
2. Implement shoe size presets (men's US 7-14, women's US 5-11)
3. Create product configs for existing products (migration seed data)
4. Update `ShopLive.Show` to conditionally render size/color based on config
5. Add shoe size grid UI with Men's/Women's toggle for unisex products
6. Replace "Coming Soon" button with "Add to Cart" (enabled/disabled based on `checkout_enabled`)

**Tests**: Admin form tests for product config toggles. ShopLive.Show tests for conditional rendering based on config (sizes shown/hidden, colors shown/hidden). Variant auto-generation from config.

### Phase 3: Cart System
**Cart page + Add to Cart flow**

1. Create `CartLive.Index` LiveView (cart page)
2. Build cart page: item list, quantity +/-, remove, BUX discount per item, totals
3. Add "Add to Cart" handler to `ShopLive.Show`
4. Add cart icon with badge to main navbar layout
5. Implement cart → order conversion ("Proceed to Checkout")
6. Handle unauthenticated users (redirect to login, then back to product)
7. Implement cart validation on load (stale products, price changes, stock checks)

**Tests**: CartLive tests (add item, update quantity, remove, BUX adjustment). Cart validation tests (deleted product, out-of-stock, price change). Cart-to-order conversion test. Unauthenticated redirect test.

### Phase 4: Checkout Page (No Payments Yet)
**Checkout LiveView + template**

1. Create `CheckoutLive.Index` LiveView
2. Build shipping info form (Step 1)
3. Build order review with multi-item pricing breakdown (Step 2)
4. Build ROGUE payment option in review step (with rate locking on step entry)
5. Build payment step skeleton (Step 3)
6. Build confirmation page (Step 4)

**Tests**: CheckoutLive mount test. Shipping form validation tests (required fields, email format). ROGUE discount calculation tests (all edge case combinations from Section 5 table). Step progression tests.

### Phase 5: BUX Payment Integration
**JS hook + server verification**

1. Create `BuxPaymentHook` JS hook (register in app.js)
2. Implement BUX transfer via Thirdweb SDK in hook
3. Server-side: handle `bux_payment_complete` event
4. Server-side: verify BUX transaction on Rogue Chain
5. Update order status flow (use BalanceManager for serialized deduction)
6. Handle 100% BUX discount case (skip Helio)

**Tests**: Mock BUX transfer, test order status transitions (pending -> bux_paid). Test 100% BUX case skips Helio. Test BUX payment error handling and flash messages. Test serialized BUX deduction prevents double-spend.

### Phase 6: ROGUE Payment Integration
**JS hook + price conversion**

1. Implement ROGUE/USD price lookup (PriceTracker or fixed rate)
2. Add ROGUE payment option to checkout review step
3. Create `RoguePaymentHook` JS hook (register in app.js)
4. Implement ROGUE native transfer via Thirdweb SDK
5. Server-side: verify ROGUE transaction
6. Handle BUX + ROGUE covers full price case

**Tests**: ROGUE discount calculation (10% off ROGUE portion). Rate locking at review step. Mock ROGUE transfer, test status transitions. Test BUX + ROGUE covers full price (skip Helio). Test all 7 payment combinations from edge cases table.

### Phase 7: Helio Integration
**API integration + widget + card payments**

1. Set up Helio account and get API keys
2. Create `BlocksterV2.Helio` module (Charges API client)
3. Create `HelioCheckoutHook` JS hook (register in app.js)
4. Implement charge creation flow
5. Set up webhook endpoint + controller (detect card vs crypto from webhook payload)
6. Store `helio_payment_currency` on order (USDC/SOL/ETH/BTC/CARD)
7. Test end-to-end payment flow including card payments

**Tests**: Mock Helio API (charge creation). Webhook controller tests (valid/invalid token, idempotency, card vs crypto detection). Helio charge expiry handling. End-to-end: BUX -> ROGUE -> Helio full flow with mocks.

### Phase 8: Order Fulfillment
**Email + Telegram setup**

1. Create `BlocksterV2.OrderMailer` with Swoosh (multi-item order format)
2. Create `BlocksterV2.TelegramNotifier` module (multi-item order format)
3. Set up Telegram bot + fulfillment channel
4. Create `BlocksterV2.Orders.Fulfillment` coordinator
5. Wire fulfillment to "paid" status transition
6. Test email + Telegram notifications

**Tests**: Swoosh test adapter to verify email content/recipients. Mock Telegram API to verify message format. Test fulfillment_notified_at gets set. Test fulfillment triggers on paid status only.

### Phase 9: Affiliate System
**Multi-currency commission logic + chargeback holds**

1. Implement multi-currency affiliate payout creation (BUX/ROGUE/Helio currency)
2. BUX commission: mint via BuxMinter immediately (5% of actual tokens)
3. ROGUE commission: transfer from treasury immediately (5% of actual tokens sent)
4. Helio crypto/card commission: pay in USDC on Ethereum (batched weekly if under $10, held 30 days for card)
5. Card commission: create with "held" status + 30-day hold
6. Create `AffiliatePayoutWorker` periodic job for releasing held payouts
7. Record earnings in Mnesia `referral_earnings`
8. Update member page to display `:shop_purchase` earnings with currency info

**Tests**: Commission calculation tests for each currency type. Held payout creation for card payments. AffiliatePayoutWorker test (process held payouts past hold date, skip those still in hold). No-referrer order creates no payouts. Referrer validation (deleted/invalid referrer).

### Phase 10: Admin Interface
**Admin LiveViews**

1. Create `OrdersAdminLive` (orders list with filters, multi-item display)
2. Create `OrderAdminLive.Show` (order detail, per-item fulfillment, affiliate payouts)
3. Add tracking number/URL update per order item
4. Add affiliate payout status visibility
5. Add order export (CSV)

**Tests**: Admin authorization (non-admin redirected). Orders list with status filters. Order detail shows correct payment breakdown. Tracking number update per item. Status transitions from admin.

### Phase 11: Polish & Production Prep
**Final integration, cleanup, deployment**

1. Add `OrderExpiryWorker` (30 min TTL, flags partial payments for review)
2. Add partial payment recovery / refund flow for expired orders
3. Add rate limiting for checkout (max 5 orders per user per hour)
4. Clear cart after successful payment
5. End-to-end testing with all payment combinations (BUX only, ROGUE only, Helio only, all three, card, 100% BUX, BUX+ROGUE full coverage)
6. Helio devnet/testnet testing
7. Set up Fly.io secrets for all new env vars
8. Deploy and test in production

**Tests**: OrderExpiryWorker test (expire stale orders, flag partial payments). Rate limiting test. Full integration test suite covering all 7 payment combinations from Section 5 edge cases table. Cart cleared after payment. Refund flow for partially-paid expired orders.

---

## Appendix A: Environment Variables Needed

```bash
# Helio (MoonPay Commerce)
HELIO_API_KEY=xxx
HELIO_SECRET_KEY=xxx
HELIO_WEBHOOK_SECRET=xxx
HELIO_PAYLINK_ID=xxx  # Pre-created Pay Link with dynamic pricing enabled

# Telegram Bot
TELEGRAM_BOT_TOKEN=xxx
TELEGRAM_FULFILLMENT_CHANNEL_ID=xxx

# Shop Treasury
SHOP_TREASURY_ADDRESS=0x...  # Address to receive BUX/ROGUE payments

# ROGUE
ROGUE_USD_PRICE=0.20  # Fallback fixed rate (if not on CoinGecko)
ROGUE_PAYMENT_DISCOUNT_RATE=0.10  # 10% discount for paying with ROGUE (configurable)

# Fulfillment Email
FULFILLMENT_EMAIL=fulfillment@blockster.com
```

## Appendix B: NPM Dependencies

```bash
npm install @heliofi/checkout-react  # or use CDN script tag
```

Alternatively, load the Helio widget via CDN script tag to avoid adding to the JS bundle:
```html
<script src="https://cdn.hel.io/checkout.js"></script>
```

## Appendix C: Key File Locations (Existing)

| File | Purpose |
|------|---------|
| `lib/blockster_v2/shop.ex` | Shop context (products, variants, categories) |
| `lib/blockster_v2/shop/product.ex` | Product schema |
| `lib/blockster_v2/shop/product_variant.ex` | Variant schema (prices, options) |
| `lib/blockster_v2_web/live/shop_live/show.ex` | Product page LiveView |
| `lib/blockster_v2_web/live/shop_live/show.html.heex` | Product page template |
| `lib/blockster_v2/bux_minter.ex` | BUX minting service client |
| `lib/blockster_v2/referrals.ex` | Referral system (Mnesia) |
| `lib/blockster_v2/referral_reward_poller.ex` | On-chain referral event poller |
| `lib/blockster_v2/engagement_tracker.ex` | BUX balance management (Mnesia) |
| `lib/blockster_v2_web/router.ex` | Routes |

---

## Appendix D: Complete Schema Definitions

### D.1 Cart Schema

```elixir
# lib/blockster_v2/cart/cart.ex
defmodule BlocksterV2.Cart.Cart do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "carts" do
    # Users have integer primary keys (default Ecto :id), not binary_id
    belongs_to :user, BlocksterV2.Accounts.User, type: :id
    has_many :cart_items, BlocksterV2.Cart.CartItem, on_delete: :delete_all
    timestamps(type: :utc_datetime)
  end

  def changeset(cart, attrs) do
    cart
    |> cast(attrs, [:user_id])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
```

### D.2 CartItem Schema

```elixir
# lib/blockster_v2/cart/cart_item.ex
defmodule BlocksterV2.Cart.CartItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "cart_items" do
    belongs_to :cart, BlocksterV2.Cart.Cart
    belongs_to :product, BlocksterV2.Shop.Product
    belongs_to :variant, BlocksterV2.Shop.ProductVariant
    field :quantity, :integer, default: 1
    field :bux_tokens_to_redeem, :integer, default: 0
    timestamps(type: :utc_datetime)
  end

  @required_fields [:cart_id, :product_id, :quantity]
  @optional_fields [:variant_id, :bux_tokens_to_redeem]

  def changeset(cart_item, attrs) do
    cart_item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:bux_tokens_to_redeem, greater_than_or_equal_to: 0)
    |> unique_constraint([:cart_id, :product_id, :variant_id], name: :cart_items_cart_id_product_id_variant_id_index)
    |> foreign_key_constraint(:cart_id)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:variant_id)
  end
end
```

### D.3 Order Schema

```elixir
# lib/blockster_v2/orders/order.ex
defmodule BlocksterV2.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "orders" do
    field :order_number, :string
    belongs_to :user, BlocksterV2.Accounts.User, type: :id
    belongs_to :referrer, BlocksterV2.Accounts.User, type: :id

    # Pricing totals (all in USD)
    field :subtotal, :decimal
    field :bux_discount_amount, :decimal, default: Decimal.new("0")
    field :bux_tokens_burned, :integer, default: 0
    field :rogue_payment_amount, :decimal, default: Decimal.new("0")
    field :rogue_discount_rate, :decimal, default: Decimal.new("0.10")
    field :rogue_discount_amount, :decimal, default: Decimal.new("0")
    field :rogue_tokens_sent, :decimal, default: Decimal.new("0")
    field :helio_payment_amount, :decimal, default: Decimal.new("0")
    field :helio_payment_currency, :string
    field :total_paid, :decimal

    # Payment tracking
    field :bux_burn_tx_hash, :string
    field :rogue_payment_tx_hash, :string
    field :rogue_usd_rate_locked, :decimal
    field :helio_charge_id, :string
    field :helio_transaction_id, :string
    field :helio_payer_address, :string

    # Shipping
    field :shipping_name, :string
    field :shipping_email, :string
    field :shipping_address_line1, :string
    field :shipping_address_line2, :string
    field :shipping_city, :string
    field :shipping_state, :string
    field :shipping_postal_code, :string
    field :shipping_country, :string
    field :shipping_phone, :string

    # Status: pending -> bux_pending -> bux_paid -> rogue_pending -> rogue_paid -> helio_pending -> paid -> processing -> shipped -> delivered
    # Also: expired (30min timeout), cancelled, refunded
    field :status, :string, default: "pending"
    field :fulfillment_notified_at, :utc_datetime
    field :notes, :string
    field :affiliate_commission_rate, :decimal, default: Decimal.new("0.05")

    has_many :order_items, BlocksterV2.Orders.OrderItem, on_delete: :delete_all
    has_many :affiliate_payouts, BlocksterV2.Orders.AffiliatePayout, on_delete: :nilify_all
    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(pending bux_pending bux_paid rogue_pending rogue_paid helio_pending paid processing shipped delivered expired cancelled refunded)

  def create_changeset(order, attrs) do
    order
    |> cast(attrs, [:order_number, :user_id, :referrer_id, :subtotal, :bux_discount_amount, :bux_tokens_burned, :total_paid, :rogue_usd_rate_locked, :affiliate_commission_rate])
    |> validate_required([:order_number, :user_id, :subtotal, :total_paid])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:order_number)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:referrer_id)
  end

  def shipping_changeset(order, attrs) do
    order
    |> cast(attrs, [:shipping_name, :shipping_email, :shipping_address_line1, :shipping_address_line2, :shipping_city, :shipping_state, :shipping_postal_code, :shipping_country, :shipping_phone])
    |> validate_required([:shipping_name, :shipping_email, :shipping_address_line1, :shipping_city, :shipping_postal_code, :shipping_country])
    |> validate_format(:shipping_email, ~r/^[^\s]+@[^\s]+$/)
  end

  def bux_payment_changeset(order, attrs) do
    order
    |> cast(attrs, [:bux_burn_tx_hash, :bux_discount_amount, :bux_tokens_burned, :status])
    |> validate_required([:bux_burn_tx_hash])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def rogue_payment_changeset(order, attrs) do
    order
    |> cast(attrs, [:rogue_payment_tx_hash, :rogue_payment_amount, :rogue_discount_rate, :rogue_discount_amount, :rogue_tokens_sent, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def helio_payment_changeset(order, attrs) do
    order
    |> cast(attrs, [:helio_charge_id, :helio_transaction_id, :helio_payer_address, :helio_payment_amount, :helio_payment_currency, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def status_changeset(order, attrs) do
    order
    |> cast(attrs, [:status, :fulfillment_notified_at, :notes])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
```

### D.4 OrderItem Schema

```elixir
# lib/blockster_v2/orders/order_item.ex
defmodule BlocksterV2.Orders.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "order_items" do
    belongs_to :order, BlocksterV2.Orders.Order
    field :product_id, :binary_id
    field :product_title, :string
    field :product_image, :string
    field :variant_id, :binary_id
    field :variant_title, :string
    field :quantity, :integer, default: 1
    field :unit_price, :decimal
    field :subtotal, :decimal
    field :bux_discount_amount, :decimal, default: Decimal.new("0")
    field :bux_tokens_redeemed, :integer, default: 0
    field :tracking_number, :string
    field :tracking_url, :string
    field :fulfillment_status, :string, default: "unfulfilled"
    timestamps(type: :utc_datetime)
  end

  @required_fields [:order_id, :product_id, :product_title, :quantity, :unit_price, :subtotal]
  @optional_fields [:product_image, :variant_id, :variant_title, :bux_discount_amount, :bux_tokens_redeemed, :tracking_number, :tracking_url, :fulfillment_status]

  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> validate_inclusion(:fulfillment_status, ["unfulfilled", "processing", "shipped", "delivered"])
    |> foreign_key_constraint(:order_id)
  end
end
```

### D.5 AffiliatePayout Schema

```elixir
# lib/blockster_v2/orders/affiliate_payout.ex
defmodule BlocksterV2.Orders.AffiliatePayout do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "affiliate_payouts" do
    belongs_to :order, BlocksterV2.Orders.Order
    belongs_to :referrer, BlocksterV2.Accounts.User, type: :id
    field :currency, :string
    field :basis_amount, :decimal
    field :commission_rate, :decimal, default: Decimal.new("0.05")
    field :commission_amount, :decimal
    field :commission_usd_value, :decimal
    field :status, :string, default: "pending"
    field :held_until, :utc_datetime
    field :paid_at, :utc_datetime
    field :tx_hash, :string
    field :failure_reason, :string
    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(pending held paid failed)
  @valid_currencies ~w(BUX ROGUE USDC SOL ETH BTC CARD)
  @required_fields [:order_id, :referrer_id, :currency, :basis_amount, :commission_rate, :commission_amount]
  @optional_fields [:commission_usd_value, :status, :held_until, :paid_at, :tx_hash, :failure_reason]

  def changeset(payout, attrs) do
    payout
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:currency, @valid_currencies)
    |> validate_number(:commission_rate, greater_than: 0, less_than_or_equal_to: 1)
    |> foreign_key_constraint(:order_id)
    |> foreign_key_constraint(:referrer_id)
  end
end
```

### D.6 ProductConfig Schema

```elixir
# lib/blockster_v2/shop/product_config.ex
defmodule BlocksterV2.Shop.ProductConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "product_configs" do
    belongs_to :product, BlocksterV2.Shop.Product
    field :has_sizes, :boolean, default: false
    field :has_colors, :boolean, default: false
    field :has_custom_option, :boolean, default: false
    field :custom_option_label, :string
    field :size_type, :string, default: "clothing"
    field :available_sizes, {:array, :string}, default: []
    field :available_colors, {:array, :string}, default: []
    field :requires_shipping, :boolean, default: true
    field :is_digital, :boolean, default: false
    field :affiliate_commission_rate, :decimal
    timestamps(type: :utc_datetime)
  end

  @valid_size_types ~w(clothing mens_shoes womens_shoes unisex_shoes one_size)

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:product_id, :has_sizes, :has_colors, :has_custom_option, :custom_option_label, :size_type, :available_sizes, :available_colors, :requires_shipping, :is_digital, :affiliate_commission_rate])
    |> validate_required([:product_id])
    |> validate_inclusion(:size_type, @valid_size_types)
    |> unique_constraint(:product_id)
    |> foreign_key_constraint(:product_id)
  end
end
```

**Note:** Add `has_one :product_config, BlocksterV2.Shop.ProductConfig` to the existing `Product` schema in `lib/blockster_v2/shop/product.ex`.

---

## Appendix E: JS Payment Hooks

### E.1 BuxPaymentHook

ERC-20 BUX transfer from smart wallet to shop treasury. Uses Thirdweb v5 `prepareContractCall` pattern (same as `bux_booster_onchain.js`).

```javascript
// assets/js/hooks/bux_payment.js
const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";

export const BuxPaymentHook = {
  mounted() {
    this.treasuryAddress = this.el.dataset.treasuryAddress;

    this.handleEvent("initiate_bux_payment", async ({ amount, order_id }) => {
      try {
        const wallet = window.smartAccount;
        if (!wallet) {
          this.pushEvent("bux_payment_error", { order_id, error: "No wallet connected. Please refresh." });
          return;
        }

        const { prepareContractCall, sendTransaction, waitForReceipt } = await import("thirdweb");
        const { getContract } = await import("thirdweb/contract");

        const buxContract = getContract({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          address: BUX_TOKEN_ADDRESS
        });

        // BUX has 18 decimals
        const amountWei = BigInt(amount) * BigInt(10 ** 18);

        const transferTx = prepareContractCall({
          contract: buxContract,
          method: "function transfer(address to, uint256 amount) returns (bool)",
          params: [this.treasuryAddress, amountWei]
        });

        const result = await sendTransaction({ transaction: transferTx, account: wallet });
        console.log("[BuxPayment] TX submitted:", result.transactionHash);

        const receipt = await waitForReceipt({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          transactionHash: result.transactionHash
        });

        if (receipt.status === "success") {
          this.pushEvent("bux_payment_complete", { order_id, tx_hash: result.transactionHash, amount });
        } else {
          this.pushEvent("bux_payment_error", { order_id, error: "BUX transfer failed on-chain" });
        }
      } catch (error) {
        console.error("[BuxPayment] Error:", error);
        let msg = error.message;
        if (msg?.includes("User rejected") || msg?.includes("user rejected")) msg = "BUX payment cancelled";
        else if (msg?.includes("insufficient")) msg = "Insufficient BUX balance";
        this.pushEvent("bux_payment_error", { order_id, error: msg });
      }
    });
  }
};
```

### E.2 RoguePaymentHook

Native ROGUE transfer from smart wallet to shop treasury. Uses Thirdweb v5 `prepareTransaction` pattern (same as `wallet_transfer.js`).

```javascript
// assets/js/hooks/rogue_payment.js
export const RoguePaymentHook = {
  mounted() {
    this.treasuryAddress = this.el.dataset.treasuryAddress;

    this.handleEvent("initiate_rogue_payment", async ({ amount_wei, amount_display, order_id }) => {
      try {
        const wallet = window.smartAccount;
        if (!wallet) {
          this.pushEvent("rogue_payment_error", { order_id, error: "No wallet connected. Please refresh." });
          return;
        }

        const { prepareTransaction, sendTransaction, waitForReceipt } = await import("thirdweb");

        // amount_wei from server as string to avoid JS precision issues
        const transaction = prepareTransaction({
          to: this.treasuryAddress,
          value: BigInt(amount_wei),
          chain: window.rogueChain,
          client: window.thirdwebClient
        });

        const { transactionHash } = await sendTransaction({ transaction, account: wallet });
        console.log("[RoguePayment] TX submitted:", transactionHash);

        const receipt = await waitForReceipt({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          transactionHash
        });

        if (receipt.status === "success") {
          this.pushEvent("rogue_payment_complete", { order_id, tx_hash: transactionHash, amount_display });
        } else {
          this.pushEvent("rogue_payment_error", { order_id, error: "ROGUE transfer failed on-chain" });
        }
      } catch (error) {
        console.error("[RoguePayment] Error:", error);
        let msg = error.message;
        if (msg?.includes("User rejected") || msg?.includes("user rejected")) msg = "ROGUE payment cancelled";
        else if (msg?.includes("insufficient funds")) msg = "Insufficient ROGUE balance";
        this.pushEvent("rogue_payment_error", { order_id, error: msg });
      }
    });
  }
};
```

**Hook Registration** in `assets/js/app.js`:

```javascript
import { BuxPaymentHook } from "./hooks/bux_payment";
import { RoguePaymentHook } from "./hooks/rogue_payment";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { /* ...existing... */ BuxPaymentHook, RoguePaymentHook }
});
```

---

## Appendix F: LiveView Event Handlers

### F.1 CheckoutLive Event Handlers

```elixir
# lib/blockster_v2_web/live/checkout_live.ex

# Step 1: Shipping
def handle_event("submit_shipping", %{"shipping" => params}, socket) do
  order = socket.assigns.order
  case order |> Order.shipping_changeset(params) |> Repo.update() do
    {:ok, updated} -> {:noreply, socket |> assign(:order, updated) |> assign(:checkout_step, :review)}
    {:error, cs} -> {:noreply, assign(socket, :shipping_changeset, cs)}
  end
end

# Step 2: ROGUE slider
def handle_event("set_rogue_amount", %{"amount" => amount_str}, socket) do
  rogue_usd = parse_decimal(amount_str)
  order = socket.assigns.order
  remaining = Decimal.sub(order.subtotal, order.bux_discount_amount)
  rogue_usd = Decimal.min(rogue_usd, remaining)

  rate = order.rogue_discount_rate
  discounted = Decimal.mult(rogue_usd, Decimal.sub(1, rate))
  tokens = Decimal.div(discounted, order.rogue_usd_rate_locked)
  saved = Decimal.sub(rogue_usd, discounted)
  helio = Decimal.sub(remaining, rogue_usd)

  {:noreply, assign(socket, rogue_usd_amount: rogue_usd, rogue_tokens: tokens, rogue_discount_saved: saved, helio_amount: helio)}
end

# Step 2 -> 3: Proceed to payment
def handle_event("proceed_to_payment", _params, socket) do
  order = socket.assigns.order
  rogue_usd = socket.assigns.rogue_usd_amount
  helio = socket.assigns.helio_amount

  {:ok, order} = order
    |> Order.rogue_payment_changeset(%{rogue_payment_amount: rogue_usd, rogue_discount_amount: socket.assigns.rogue_discount_saved, rogue_tokens_sent: socket.assigns.rogue_tokens})
    |> Repo.update()

  socket =
    if Decimal.gt?(helio, 0) do
      {:ok, order} = order |> Order.helio_payment_changeset(%{helio_payment_amount: helio}) |> Repo.update()
      case BlocksterV2.Helio.create_charge(order) do
        {:ok, %{charge_id: cid}} ->
          {:ok, order} = order |> Order.helio_payment_changeset(%{helio_charge_id: cid}) |> Repo.update()
          socket |> assign(:order, order) |> push_event("helio_charge_created", %{charge_token: cid})
        {:error, reason} -> put_flash(socket, :error, "Payment setup failed: #{reason}")
      end
    else
      assign(socket, :order, order)
    end

  {:noreply, assign(socket, :checkout_step, :payment)}
end

# Step 3a: BUX confirmed
def handle_event("bux_payment_complete", %{"tx_hash" => hash, "order_id" => oid}, socket) do
  order = socket.assigns.order
  if order.id != oid, do: {:noreply, put_flash(socket, :error, "Order mismatch")}, else: (
    {:ok, order} = order |> Order.bux_payment_changeset(%{bux_burn_tx_hash: hash, status: "bux_paid"}) |> Repo.update()
    user = socket.assigns.current_user
    BlocksterV2.BuxMinter.sync_user_balances_async(user.id, user.smart_wallet_address)

    next = cond do
      Decimal.gt?(order.rogue_payment_amount, 0) -> :rogue_payment
      Decimal.gt?(order.helio_payment_amount, 0) -> :helio_payment
      true -> :confirmation
    end

    socket = if next == :rogue_payment do
      wei = order.rogue_tokens_sent |> Decimal.mult(Decimal.new("1000000000000000000")) |> Decimal.round(0)
      push_event(socket, "initiate_rogue_payment", %{amount_wei: Decimal.to_string(wei), amount_display: Decimal.to_string(order.rogue_tokens_sent), order_id: order.id})
    else socket end

    {:noreply, socket |> assign(:order, order) |> assign(:payment_step, next)}
  )
end

def handle_event("bux_payment_error", %{"error" => err}, socket), do: {:noreply, put_flash(socket, :error, "BUX payment failed: #{err}")}

# Step 3b: ROGUE confirmed
def handle_event("rogue_payment_complete", %{"tx_hash" => hash, "order_id" => oid}, socket) do
  order = socket.assigns.order
  if order.id != oid, do: {:noreply, put_flash(socket, :error, "Order mismatch")}, else: (
    {:ok, order} = order |> Order.rogue_payment_changeset(%{rogue_payment_tx_hash: hash, status: "rogue_paid"}) |> Repo.update()
    user = socket.assigns.current_user
    BlocksterV2.BuxMinter.sync_user_balances_async(user.id, user.smart_wallet_address)

    if Decimal.gt?(order.helio_payment_amount, 0) do
      {:noreply, socket |> assign(:order, order) |> assign(:payment_step, :helio_payment)}
    else
      finalize_order(socket, order)
    end
  )
end

def handle_event("rogue_payment_error", %{"error" => err}, socket), do: {:noreply, put_flash(socket, :error, "ROGUE payment failed: #{err}")}

# Step 3c: Helio callbacks
def handle_event("helio_payment_success", %{"transaction_id" => txid}, socket) do
  order = socket.assigns.order
  {:ok, order} = order |> Order.helio_payment_changeset(%{helio_transaction_id: txid, status: "helio_pending"}) |> Repo.update()
  {:noreply, socket |> assign(:order, order) |> assign(:payment_step, :helio_confirming) |> put_flash(:info, "Payment submitted. Waiting for confirmation...")}
end

def handle_event("helio_payment_error", %{"error" => err}, socket), do: {:noreply, put_flash(socket, :error, "Payment failed: #{err}. You can retry.")}
def handle_event("helio_payment_cancelled", _, socket), do: {:noreply, put_flash(socket, :info, "Payment cancelled. You can try again.")}

# PubSub: webhook-driven updates
def handle_info({:order_updated, %{id: oid} = updated}, socket) do
  if socket.assigns.order.id == oid do
    socket = assign(socket, :order, updated)
    socket = if updated.status == "paid", do: socket |> assign(:payment_step, :confirmation) |> put_flash(:info, "Payment confirmed!"), else: socket
    {:noreply, socket}
  else
    {:noreply, socket}
  end
end

defp finalize_order(socket, order) do
  {:ok, order} = order |> Order.status_changeset(%{status: "paid"}) |> Repo.update()
  BlocksterV2.Orders.process_paid_order(order)
  {:noreply, socket |> assign(:order, order) |> assign(:payment_step, :confirmation) |> put_flash(:info, "Order confirmed!")}
end

defp parse_decimal(str) when is_binary(str) do
  case Decimal.parse(str) do
    {d, ""} -> d
    _ -> Decimal.new("0")
  end
end
defp parse_decimal(_), do: Decimal.new("0")
```

### F.2 CartLive Event Handlers

```elixir
# lib/blockster_v2_web/live/cart_live.ex
alias BlocksterV2.Cart

def handle_event("update_quantity", %{"item_id" => id, "action" => action}, socket) do
  item = Enum.find(socket.assigns.cart.cart_items, &(&1.id == id))
  qty = case action do
    "increment" -> item.quantity + 1
    "decrement" -> max(item.quantity - 1, 1)
  end
  {:ok, _} = Cart.update_item_quantity(item, qty)
  {:noreply, reload_cart(socket)}
end

def handle_event("update_bux", %{"item_id" => id, "bux" => bux_str}, socket) do
  item = Enum.find(socket.assigns.cart.cart_items, &(&1.id == id))
  case Cart.update_item_bux(item, String.to_integer(bux_str)) do
    {:ok, _} -> {:noreply, reload_cart(socket)}
    {:error, reason} -> {:noreply, put_flash(socket, :error, reason)}
  end
end

def handle_event("remove_item", %{"item_id" => id}, socket) do
  item = Enum.find(socket.assigns.cart.cart_items, &(&1.id == id))
  {:ok, _} = Cart.remove_item(item)
  {:noreply, reload_cart(socket)}
end

def handle_event("proceed_to_checkout", _, socket) do
  cart = socket.assigns.cart
  user = socket.assigns.current_user
  case Cart.validate_cart_items(cart) do
    :ok ->
      {:ok, order} = BlocksterV2.Orders.create_order_from_cart(cart, user)
      {:noreply, push_navigate(socket, to: ~p"/checkout/#{order.id}")}
    {:error, reasons} ->
      {:noreply, socket |> reload_cart() |> put_flash(:error, Enum.join(reasons, ". "))}
  end
end

defp reload_cart(socket) do
  user = socket.assigns.current_user
  cart = Cart.get_or_create_cart(user.id) |> Cart.preload_items()
  assign(socket, cart: cart, totals: Cart.calculate_totals(cart, user.id))
end
```

---

## Appendix G: Worker Implementations

### G.1 AffiliatePayoutWorker

Global singleton that processes held payouts past chargeback hold date (hourly).

```elixir
# lib/blockster_v2/orders/affiliate_payout_worker.ex
defmodule BlocksterV2.Orders.AffiliatePayoutWorker do
  use GenServer
  require Logger
  import Ecto.Query
  alias BlocksterV2.{Repo, GlobalSingleton}
  alias BlocksterV2.Orders.AffiliatePayout

  @check_interval :timer.hours(1)

  def start_link(opts) do
    case GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _} -> :ignore
    end
  end

  @impl true
  def init(_), do: (schedule(); {:ok, %{}})

  @impl true
  def handle_info(:check, state) do
    now = DateTime.utc_now()
    payouts = from(p in AffiliatePayout, where: p.status == "held", where: p.held_until <= ^now, preload: [:order, :referrer]) |> Repo.all()
    if length(payouts) > 0, do: Logger.info("[AffiliatePayoutWorker] Processing #{length(payouts)} held payouts")

    Enum.each(payouts, fn p ->
      case BlocksterV2.Orders.execute_affiliate_payout(p) do
        {:ok, _} -> Logger.info("[AffiliatePayoutWorker] Paid #{p.id}")
        {:error, r} ->
          Logger.error("[AffiliatePayoutWorker] Failed #{p.id}: #{inspect(r)}")
          p |> Ecto.Changeset.change(%{status: "failed", failure_reason: "#{inspect(r)}"}) |> Repo.update()
      end
    end)
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :check, @check_interval)
end
```

### G.2 OrderExpiryWorker

Global singleton that cancels unpaid orders after 30 minutes (checks every 5 min).

```elixir
# lib/blockster_v2/orders/order_expiry_worker.ex
defmodule BlocksterV2.Orders.OrderExpiryWorker do
  use GenServer
  require Logger
  import Ecto.Query
  alias BlocksterV2.{Repo, GlobalSingleton}
  alias BlocksterV2.Orders.Order

  @check_interval :timer.minutes(5)
  @ttl_minutes 30

  def start_link(opts) do
    case GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _} -> :ignore
    end
  end

  @impl true
  def init(_), do: (schedule(); {:ok, %{}})

  @impl true
  def handle_info(:check, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -@ttl_minutes, :minute)
    stale = from(o in Order, where: o.status in ["pending", "bux_paid", "rogue_paid", "helio_pending"], where: o.inserted_at <= ^cutoff) |> Repo.all()

    if length(stale) > 0, do: Logger.info("[OrderExpiryWorker] Expiring #{length(stale)} stale orders")

    Enum.each(stale, fn order ->
      note = if order.status in ["bux_paid", "rogue_paid", "helio_pending"],
        do: "Auto-expired with partial payment (#{order.status}). Needs manual refund review.",
        else: "Auto-expired after #{@ttl_minutes}m"
      order |> Order.status_changeset(%{status: "cancelled", notes: note}) |> Repo.update()
    end)
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :check, @check_interval)
end
```

**Supervision** -- add to `lib/blockster_v2/application.ex` children list:

```elixir
BlocksterV2.Orders.AffiliatePayoutWorker,
BlocksterV2.Orders.OrderExpiryWorker,
```

---

## Appendix H: Context Functions

### H.1 Orders Context

```elixir
# lib/blockster_v2/orders.ex
defmodule BlocksterV2.Orders do
  import Ecto.Query, warn: false
  alias BlocksterV2.{Repo, Cart}
  alias BlocksterV2.Orders.{Order, OrderItem, AffiliatePayout}
  alias BlocksterV2.Accounts.User
  require Logger

  def get_order(id), do: Order |> Repo.get(id) |> Repo.preload([:order_items, :affiliate_payouts, :user, :referrer])
  def get_order_by_number(num), do: Order |> Repo.get_by(order_number: num) |> Repo.preload([:order_items, :user])
  def list_orders_for_user(uid), do: from(o in Order, where: o.user_id == ^uid, order_by: [desc: o.inserted_at], preload: [:order_items]) |> Repo.all()

  def create_order_from_cart(cart, %User{} = user) do
    cart = Cart.preload_items(cart)
    totals = Cart.calculate_totals(cart, user.id)

    Repo.transaction(fn ->
      {:ok, order} = %Order{} |> Order.create_changeset(%{
        order_number: generate_order_number(), user_id: user.id, referrer_id: user.referrer_id,
        subtotal: totals.subtotal, bux_discount_amount: totals.total_bux_discount,
        bux_tokens_burned: totals.total_bux_tokens, total_paid: totals.subtotal,
        rogue_usd_rate_locked: get_current_rogue_rate()
      }) |> Repo.insert()

      Enum.each(cart.cart_items, fn item ->
        img = List.first(item.product.images)
        %OrderItem{} |> OrderItem.changeset(%{
          order_id: order.id, product_id: item.product.id, product_title: item.product.title,
          product_image: img && img.src, variant_id: item.variant && item.variant.id,
          variant_title: item.variant && item.variant.title, quantity: item.quantity,
          unit_price: if(item.variant, do: item.variant.price, else: List.first(item.product.variants).price),
          subtotal: Cart.item_subtotal(item), bux_tokens_redeemed: item.bux_tokens_to_redeem,
          bux_discount_amount: Cart.item_bux_discount(item)
        }) |> Repo.insert!()
      end)

      get_order(order.id)
    end)
  end

  def update_order(%Order{} = order, attrs), do: order |> Order.status_changeset(attrs) |> Repo.update()

  def complete_helio_payment(%Order{} = order, %{helio_transaction_id: _} = attrs) do
    {:ok, order} = order |> Order.helio_payment_changeset(Map.put(attrs, :status, "paid")) |> Repo.update()
    process_paid_order(order)
    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "order:#{order.id}", {:order_updated, order})
    {:ok, order}
  end

  def process_paid_order(%Order{} = order) do
    order = get_order(order.id)
    Task.start(fn -> BlocksterV2.OrderMailer.fulfillment_notification(order) |> BlocksterV2.Mailer.deliver() end)
    Task.start(fn -> BlocksterV2.OrderTelegram.send_fulfillment_notification(order) end)
    order |> Order.status_changeset(%{fulfillment_notified_at: DateTime.utc_now()}) |> Repo.update()
    if order.referrer_id, do: create_affiliate_payouts(order)
    :ok
  end

  defp create_affiliate_payouts(%Order{} = order) do
    rate = order.affiliate_commission_rate || Decimal.new("0.05")
    referrer = Repo.get(User, order.referrer_id)
    unless referrer do Logger.warning("[Orders] Referrer #{order.referrer_id} not found"); throw(:skip) end

    if order.bux_tokens_burned > 0 do
      comm = Decimal.new(order.bux_tokens_burned) |> Decimal.mult(rate) |> Decimal.round(0) |> Decimal.to_integer()
      {:ok, p} = insert_payout(order, referrer, "BUX", order.bux_tokens_burned, rate, comm)
      if referrer.smart_wallet_address do
        BlocksterV2.BuxMinter.mint_bux(referrer.smart_wallet_address, comm, referrer.id, nil, :shop_affiliate)
        p |> Ecto.Changeset.change(%{status: "paid", paid_at: DateTime.utc_now()}) |> Repo.update()
      end
    end

    if Decimal.gt?(order.rogue_tokens_sent, 0) do
      insert_payout(order, referrer, "ROGUE", order.rogue_tokens_sent, rate, Decimal.mult(order.rogue_tokens_sent, rate))
    end

    if Decimal.gt?(order.helio_payment_amount, 0) do
      comm = Decimal.mult(order.helio_payment_amount, rate)
      is_card = order.helio_payment_currency == "CARD"
      insert_payout(order, referrer, order.helio_payment_currency || "USDC", order.helio_payment_amount, rate, comm,
        %{status: if(is_card, do: "held", else: "pending"), held_until: if(is_card, do: DateTime.add(DateTime.utc_now(), 30, :day)), commission_usd_value: comm})
    end
  catch :skip -> :ok
  end

  defp insert_payout(order, referrer, currency, basis, rate, comm, extra \\ %{}) do
    %AffiliatePayout{} |> AffiliatePayout.changeset(Map.merge(%{
      order_id: order.id, referrer_id: referrer.id, currency: currency,
      basis_amount: basis, commission_rate: rate, commission_amount: comm
    }, extra)) |> Repo.insert()
  end

  def execute_affiliate_payout(%AffiliatePayout{} = p) do
    p = Repo.preload(p, [:referrer, :order])
    result = case p.currency do
      "BUX" -> BlocksterV2.BuxMinter.mint_bux(p.referrer.smart_wallet_address, Decimal.to_integer(Decimal.round(p.commission_amount, 0)), p.referrer.id, nil, :shop_affiliate)
      "ROGUE" ->
        treasury = Application.get_env(:blockster_v2, :shop_treasury_address)
        wei = p.commission_amount |> Decimal.mult(Decimal.new("1e18")) |> Decimal.round(0) |> Decimal.to_string()
        BlocksterV2.BuxMinter.transfer_rogue(treasury, p.referrer.smart_wallet_address, wei)
      c when c in ["USDC","SOL","ETH","BTC","CARD"] -> {:ok, :usdc_payout_queued}
    end
    case result do
      {:ok, %{"txHash" => h}} -> p |> Ecto.Changeset.change(%{status: "paid", paid_at: DateTime.utc_now(), tx_hash: h}) |> Repo.update()
      {:ok, _} -> p |> Ecto.Changeset.change(%{status: "paid", paid_at: DateTime.utc_now()}) |> Repo.update()
      {:error, r} -> {:error, r}
    end
  end

  def generate_order_number do
    date = Date.utc_today() |> Calendar.strftime("%Y%m%d")
    suffix = System.unique_integer([:positive, :monotonic]) |> rem(1_679_616) |> Integer.to_string(36) |> String.upcase() |> String.pad_leading(4, "0")
    "BLK-#{date}-#{suffix}"
  end

  defp get_current_rogue_rate do
    case :mnesia.dirty_read(:token_prices, "rogue") do
      [{:token_prices, "rogue", price, _}] when is_number(price) -> Decimal.from_float(price)
      _ -> Decimal.new(Application.get_env(:blockster_v2, :rogue_usd_price, "0.20"))
    end
  end
end
```

### H.2 Cart Context

```elixir
# lib/blockster_v2/cart.ex
defmodule BlocksterV2.Cart do
  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.Cart.{Cart, CartItem}
  alias BlocksterV2.EngagementTracker

  def get_or_create_cart(user_id) do
    case Repo.get_by(Cart, user_id: user_id) do
      nil -> ({:ok, c} = %Cart{} |> Cart.changeset(%{user_id: user_id}) |> Repo.insert(); c)
      cart -> cart
    end
  end

  def preload_items(%Cart{} = cart), do: Repo.preload(cart, cart_items: {from(ci in CartItem, order_by: ci.inserted_at), [:product, :variant]})
  def preload_items(nil), do: nil

  def add_to_cart(user_id, product_id, attrs \\ %{}) do
    cart = get_or_create_cart(user_id)
    vid = Map.get(attrs, :variant_id)
    qty = Map.get(attrs, :quantity, 1)
    bux = Map.get(attrs, :bux_tokens_to_redeem, 0)

    existing = from(ci in CartItem, where: ci.cart_id == ^cart.id and ci.product_id == ^product_id,
      where: ci.variant_id == ^vid or (is_nil(ci.variant_id) and is_nil(^vid))) |> Repo.one()

    if existing do
      existing |> CartItem.changeset(%{quantity: existing.quantity + qty, bux_tokens_to_redeem: bux}) |> Repo.update()
    else
      %CartItem{} |> CartItem.changeset(%{cart_id: cart.id, product_id: product_id, variant_id: vid, quantity: qty, bux_tokens_to_redeem: bux}) |> Repo.insert()
    end
  end

  def update_item_quantity(%CartItem{} = item, qty) when qty > 0, do: item |> CartItem.changeset(%{quantity: qty}) |> Repo.update()

  def update_item_bux(%CartItem{} = item, bux) do
    item = Repo.preload(item, [:product, :variant])
    price = if item.variant, do: item.variant.price, else: List.first(Repo.preload(item.product, :variants).variants).price
    max_pct = item.product.bux_max_discount || 0
    max_bux = Decimal.mult(price, Decimal.new("#{max_pct}")) |> Decimal.div(1) |> Decimal.round(0) |> Decimal.to_integer()

    cond do
      bux < 0 -> {:error, "BUX amount cannot be negative"}
      bux > max_bux -> {:error, "Maximum #{max_bux} BUX (#{max_pct}% max discount)"}
      true -> item |> CartItem.changeset(%{bux_tokens_to_redeem: bux}) |> Repo.update()
    end
  end

  def remove_item(%CartItem{} = item), do: Repo.delete(item)

  def calculate_totals(%Cart{} = cart, user_id) do
    cart = preload_items(cart)
    items = Enum.map(cart.cart_items, fn item ->
      price = if item.variant, do: item.variant.price, else: List.first(Repo.preload(item.product, :variants).variants).price
      %{item: item, unit_price: price, subtotal: Decimal.mult(price, item.quantity),
        bux_tokens: item.bux_tokens_to_redeem, bux_discount: Decimal.new("#{item.bux_tokens_to_redeem}") |> Decimal.div(100)}
    end)

    subtotal = Enum.reduce(items, Decimal.new("0"), &Decimal.add(&1.subtotal, &2))
    bux_tokens = Enum.reduce(items, 0, &(&1.bux_tokens + &2))
    bux_disc = Enum.reduce(items, Decimal.new("0"), &Decimal.add(&1.bux_discount, &2))

    bux_avail = case EngagementTracker.get_user_token_balances(user_id) do
      b when is_map(b) -> trunc(Map.get(b, "BUX", 0.0))
      _ -> 0
    end

    %{subtotal: subtotal, total_bux_discount: bux_disc, total_bux_tokens: bux_tokens,
      remaining: Decimal.sub(subtotal, bux_disc), bux_available: bux_avail, bux_allocated: bux_tokens, items: items}
  end

  def validate_cart_items(%Cart{} = cart) do
    cart = preload_items(cart)
    errors = Enum.reduce(cart.cart_items, [], fn item, acc ->
      product = Repo.preload(item.product, [:variants])
      cond do
        is_nil(product) -> ["#{item.product_id} no longer available" | acc]
        product.status != "active" -> ["#{product.title} no longer available" | acc]
        item.variant_id && is_nil(item.variant) -> ["Option for #{product.title} no longer available" | acc]
        item.variant && item.variant.inventory_policy == "deny" && item.variant.inventory_quantity < item.quantity ->
          ["#{product.title} (#{item.variant.title}): only #{item.variant.inventory_quantity} in stock" | acc]
        true -> acc
      end
    end)
    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  def item_subtotal(%CartItem{} = item) do
    item = Repo.preload(item, [:product, :variant])
    price = if item.variant, do: item.variant.price, else: List.first(Repo.preload(item.product, :variants).variants).price
    Decimal.mult(price, item.quantity)
  end

  def item_bux_discount(%CartItem{} = item), do: Decimal.new("#{item.bux_tokens_to_redeem}") |> Decimal.div(100)
end
```
