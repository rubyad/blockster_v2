# Plan: Remove Hub Tokens - Keep Only BUX and ROGUE

> **STATUS: ✅ COMPLETED - January 2026**
>
> This plan has been fully implemented. All hub-specific tokens have been removed from the application.
> Users now only earn and use **BUX** tokens for reading/sharing articles and shop discounts.
> **ROGUE** (native chain token) is used for betting in BUX Booster.

## Overview

This plan removes all hub-specific tokens (moonBUX, neoBUX, solBUX, rogueBUX, flareBUX, nftBUX, nolchaBUX, spaceBUX, tronBUX, tranBUX, blocksterBUX) from the application. Users will only earn and use **BUX** tokens for reading/sharing articles and shop discounts. **ROGUE** (native chain token) remains for betting in BUX Booster.

### Tokens Being Removed
| Token | Contract Address |
|-------|------------------|
| moonBUX | `0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5` |
| neoBUX | `0x423656448374003C2cfEaFF88D5F64fb3A76487C` |
| rogueBUX | `0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3` |
| flareBUX | `0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8` |
| nftBUX | `0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED` |
| nolchaBUX | `0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642` |
| solBUX | `0x92434779E281468611237d18AdE20A4f7F29DB38` |
| spaceBUX | `0xAcaCa77FbC674728088f41f6d978F0194cf3d55A` |
| tronBUX | `0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665` |
| tranBUX | `0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96` |
| blocksterBUX | `0x133Faa922052aE42485609E14A1565551323CdbE` |

### Tokens Being Kept
| Token | Contract Address | Purpose |
|-------|------------------|---------|
| BUX | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` | Reading/sharing rewards, shop discounts |
| ROGUE | Native chain token (no address) | BUX Booster betting |

---

## Phase 1: Backend Changes

### 1.1 BUX Minter Service (Node.js)

**File:** `bux-minter/index.js`

**Changes:**
1. **Remove hub token addresses** (lines ~100-120)
   - Keep only `BUX` address in `TOKEN_ADDRESSES` object
   - Remove: moonBUX, neoBUX, rogueBUX, flareBUX, nftBUX, nolchaBUX, solBUX, spaceBUX, tronBUX, tranBUX

2. **Simplify `/aggregated-balances/:address` endpoint** (lines ~288-325)
   - Only fetch BUX and ROGUE balances
   - Remove aggregate calculation (aggregate = BUX balance now)
   - Return: `{ BUX: number, ROGUE: number }`

3. **Update `/balance/:address` endpoint**
   - Remove token parameter support for hub tokens
   - Only accept `BUX` or default to BUX

4. **Update `/mint` endpoint**
   - Remove token validation for hub tokens
   - Only allow minting BUX

---

### 1.2 Elixir BuxMinter Module

**File:** `lib/blockster_v2/bux_minter.ex`

**Changes:**
1. **Update `valid_tokens/0`** (line 16)
   ```elixir
   # FROM:
   def valid_tokens, do: ~w(BUX moonBUX neoBUX rogueBUX flareBUX nftBUX nolchaBUX solBUX spaceBUX tronBUX tranBUX)

   # TO:
   def valid_tokens, do: ~w(BUX)
   ```

2. **Simplify `mint_bux/7`** (lines 34-106)
   - Remove `token` parameter (always BUX)
   - Remove `hub_id` parameter for hub token tracking
   - Update function signature: `mint_bux(wallet_address, amount, user_id, post_id, reward_type)`

3. **Simplify `get_balance/2`** (lines 123-150)
   - Remove `token` parameter (always BUX)
   - Update function signature: `get_balance(wallet_address)`

4. **Simplify `sync_user_balances/2`** (lines 215-245)
   - Only sync BUX and ROGUE balances
   - Remove hub token syncing

5. **Simplify `get_aggregated_balances/1`** (lines 186-214)
   - Only fetch BUX and ROGUE
   - Remove aggregate calculation

---

### 1.3 EngagementTracker Module

**File:** `lib/blockster_v2/engagement_tracker.ex`

**Changes:**
1. **Simplify `@token_field_indices`** (lines 1224-1236)
   ```elixir
   # FROM:
   @token_field_indices %{
     "BUX" => 5,
     "moonBUX" => 6,
     "neoBUX" => 7,
     "rogueBUX" => 8,
     "flareBUX" => 9,
     "nftBUX" => 10,
     "nolchaBUX" => 11,
     "solBUX" => 12,
     "spaceBUX" => 13,
     "tronBUX" => 14,
     "tranBUX" => 15
   }

   # TO:
   @token_field_indices %{
     "BUX" => 5
   }
   ```

2. **Simplify `get_user_token_balances/1`** (lines 1459-1510)
   - Only return `%{"BUX" => balance, "ROGUE" => rogue_balance}`
   - Remove hub token balance retrieval
   - Remove aggregate key (BUX IS the balance now)

3. **Simplify `update_user_token_balance/4`** (lines 1260-1312)
   - Remove hub token support
   - Only allow updating BUX balance

4. **Remove hub BUX tracking functions** (lines 1564-1696)
   - Remove or deprecate: `add_hub_bux_earned/2`, `broadcast_hub_bux_update/2`, `subscribe_to_hub_bux/1`, `subscribe_to_all_hub_bux_updates/0`, `get_hub_bux_balance/1`, `get_hub_bux_balances/1`, `get_all_hub_bux_balances/0`

5. **Simplify `calculate_aggregate_balance/1`** (lines 1397-1402)
   - Can be removed entirely (aggregate = BUX balance)

---

### 1.4 Mnesia Tables

**File:** `lib/blockster_v2/mnesia_initializer.ex`

**NOTE:** Cannot remove fields from existing Mnesia tables in production without migration. Leave fields in place but unused.

**Changes:**
1. **Document unused fields** in `user_bux_balances` table (lines 155-175)
   - Add comments noting indices 6-15 are deprecated and unused
   - Fields will remain 0.0 for all users

2. **`hub_bux_points` table** (lines 189-199)
   - Can be deprecated/ignored but don't delete
   - Stop writing to this table

---

## Phase 2: LiveView & Template Changes

### 2.1 Header/Navigation Balance Display

**File:** `lib/blockster_v2_web/components/layouts.ex`

**Changes (lines 200-235):**
1. **Remove "other tokens" from dropdown** - Only show BUX and ROGUE
   ```elixir
   # FROM:
   rogue_balance = Map.get(@token_balances, "ROGUE", 0)
   bux_balance = Map.get(@token_balances, "BUX", 0)
   other_tokens = Enum.filter(@token_balances, fn {k, v} ->
     k not in ["aggregate", "ROGUE", "BUX"] && is_number(v) && v > 0
   end) |> Enum.sort_by(fn {_, v} -> v end, :desc)
   display_tokens = [{"ROGUE", rogue_balance}, {"BUX", bux_balance}] ++ other_tokens

   # TO:
   rogue_balance = Map.get(@token_balances, "ROGUE", 0)
   bux_balance = Map.get(@token_balances, "BUX", 0)
   display_tokens = [{"ROGUE", rogue_balance}, {"BUX", bux_balance}]
   ```

2. **Remove "Total BUX" aggregate row** (lines 226-235)
   - Since BUX is the only token, no need for aggregate
   - Just show BUX balance directly

3. **Update main balance display** (line 234)
   - Show BUX balance, not aggregate
   - Change label from "Total BUX" to just "BUX"

4. **Mobile menu** - Apply same changes (lines ~400-450)

---

### 2.2 Post Show Page (Reading Rewards)

**File:** `lib/blockster_v2_web/live/post_live/show.ex`

**Changes:**
1. **Remove `get_hub_token/1` function** (lines 183-184)
   - Always use "BUX" regardless of hub

2. **Remove `@hub_token` assign** (line 130)
   - Replace with hardcoded "BUX"

3. **Update minting calls** (lines 268-272, 473-476)
   ```elixir
   # FROM:
   hub_token = socket.assigns.hub_token
   case BuxMinter.mint_bux(wallet, recorded_bux, user_id, post_id, :read, hub_token, socket.assigns.post.hub_id) do

   # TO:
   case BuxMinter.mint_bux(wallet, recorded_bux, user_id, post_id, :read) do
   ```

**File:** `lib/blockster_v2_web/live/post_live/show.html.heex`

**Changes:**
1. **Replace all `@hub_token` references with "BUX"** (lines 8, 14, 37, 42, 50, 55, 56, 61, 161, 177, 182, 195, 205, 373, 374, 381, 408, 414, 435)
2. **Replace `@hub_logo` with Blockster logo** (or keep hub logos for branding but rewards are BUX)
   - Keep hub logos for visual branding on hub posts
   - But text shows "BUX" not hub token name

---

### 2.3 Member Show Page

**File:** `lib/blockster_v2_web/live/member_live/show.ex`

**Changes:**
1. **Simplify `build_token_logo_map/0`** (lines 148-160)
   - Only need BUX and ROGUE logos
   ```elixir
   defp build_token_logo_map do
     %{
       "BUX" => "https://ik.imagekit.io/blockster/blockster-icon.png",
       "ROGUE" => "https://ik.imagekit.io/blockster/rogue-logo.png"
     }
   end
   ```

2. **Simplify activity enrichment** (lines 108-116)
   - Always set `token: "BUX"` regardless of hub

**File:** `lib/blockster_v2_web/live/member_live/show.html.heex`

**Changes (lines 65-127):**
1. **Simplify token dropdown** - Only show BUX and ROGUE
2. **Remove "Total BUX" row** - Just show individual balances
3. **Update card header** from "BUX Balances" to "Token Balances" or "BUX Balance"

---

### 2.4 Hub Index Page

**File:** `lib/blockster_v2_web/live/hub_live/index.ex`

**Changes:**
1. **Remove hub BUX subscription** (lines 14, 52-55)
   - Remove `subscribe_to_all_hub_bux_updates()`
   - Remove `handle_info({:hub_bux_update, ...})`

2. **Remove `hub_bux_balances` assign** (lines 19, 25)

3. **Remove `get_hub_bux/2` function** (lines 69-70)

**File:** `lib/blockster_v2_web/live/hub_live/index.html.heex`

**Changes (line 140):**
1. **Replace hub token display with "BUX"**
   ```elixir
   # FROM:
   <span>{Number.Delimit.number_to_delimited(get_hub_bux(@hub_bux_balances, hub.id), precision: 2)} {hub.token || "BUX"}</span>

   # TO:
   <span>BUX</span>  # Or remove the token badge entirely
   ```

---

### 2.5 Hub Show Page

**File:** `lib/blockster_v2_web/live/hub_live/show.ex`

**Changes:**
1. **Remove hub BUX subscription** (line 22)
2. **Remove `hub_bux_balance` assign** (lines 26, 40)
3. **Remove `handle_info({:hub_bux_update, ...})` handler** (lines 157-162)

**File:** `lib/blockster_v2_web/live/hub_live/show.html.heex`

**Changes (line 72):**
1. **Replace hub token display with "BUX"**
   ```elixir
   # FROM:
   <span>{@hub_bux_balance} {@hub.token || "BUX"}</span>

   # TO:
   <span>BUX</span>  # Or remove entirely
   ```

---

### 2.6 Hub Admin Form

**File:** `lib/blockster_v2_web/live/hub_live/form_component.html.heex`

**Changes (lines 43-60):**
1. **Remove token name field** from hub admin form
   - Hubs no longer have custom tokens
   - Or keep field but mark as deprecated/unused

---

### 2.7 Shop Product Pages

**File:** `lib/blockster_v2_web/live/shop_live/show.ex`

**Changes:**
1. **Remove hub token balance fetching** (lines 57-71)
   ```elixir
   # FROM:
   {user_bux_balance, user_hub_token_balance} = if user_id do
     bux = Map.get(token_balances, "BUX", 0) |> to_float()
     hub = if product.hub_token do
       Map.get(token_balances, product.hub_token, 0) |> to_float()
     else
       0.0
     end
     {bux, hub}
   else
     {0.0, 0.0}
   end

   # TO:
   user_bux_balance = if user_id do
     Map.get(token_balances, "BUX", 0) |> to_float()
   else
     0.0
   end
   ```

2. **Remove `user_hub_token_balance` assign** (line 104)

3. **Remove `combined_balance` calculation** (line 71)
   - Just use `user_bux_balance`

4. **Simplify discount calculation** (lines 76-91)
   - Only use `bux_max_discount`, ignore `hub_token_max_discount`

5. **Remove hub token allocation logic** (line 91)
   - No need to prioritize hub tokens

**File:** `lib/blockster_v2_web/live/shop_live/show.html.heex`

**Changes:**
1. **Remove hub token display in discount section** (lines 292-305)
2. **Remove hub token input in allocation section** (lines 376-399)
3. **Simplify token input** - Only BUX input needed (lines 319-420)
4. **Remove `TokenAllocationDropdown` hook usage** (line 320)
   - Single token input doesn't need dropdown

**File:** `lib/blockster_v2_web/live/shop_live/index.ex`

**Changes:**
1. **Remove `hub_token_max_discount` from product cards** (lines 63, 101, 277-487)

---

### 2.8 Product Admin Form

**File:** `lib/blockster_v2_web/live/product_live/form.ex`

**Changes (line 800):**
1. **Remove hub token max discount field**
   - Or keep but mark as deprecated

**File:** `lib/blockster_v2_web/live/products_admin_live.ex`

**Changes (line 168):**
1. **Remove hub token max discount display from admin list**

---

### 2.9 BUX Booster Page

**File:** `lib/blockster_v2_web/live/bux_booster_live.ex`

**No major changes needed** - Already only uses BUX and ROGUE.

**Minor changes:**
1. **Update `balances` initialization** (lines 31, 43)
   - Only need `%{"BUX" => 0, "ROGUE" => 0}`

2. **Remove aggregate balance calculations** (lines 1367-1378, 1495-1503)
   - No aggregate needed when only BUX exists

---

### 2.10 Shared Components

**File:** `lib/blockster_v2_web/components/shared_components.ex`

**Changes (lines 27-67):**
1. **Simplify `token_badge` component**
   - Always show BUX icon/badge
   - Remove hub token logic

---

## Phase 3: JavaScript Changes

### 3.1 Remove TokenAllocationDropdown Hook

**File:** `assets/js/app.js`

**Changes (lines 133-145, 295):**
1. **Remove `TokenAllocationDropdown` hook** - No longer needed
2. **Remove from hooks registration**

---

### 3.2 BuxBoosterOnchain Hook

**File:** `assets/js/bux_booster_onchain.js`

**No major changes needed** - Already only uses BUX and ROGUE.

---

## Phase 4: Database Changes

### 4.1 Product Schema

**File:** `lib/blockster_v2/shop/product.ex`

**Changes:**
1. **Deprecate `hub_token_max_discount` field** (line 18)
   - Keep field but set default to 0 and ignore in logic
   - Add `# Deprecated - hub tokens removed` comment

2. **Remove from changeset** (lines 67, 87)
   - Or keep but don't validate

---

### 4.2 Hub Schema

**File:** `lib/blockster_v2/blog/hub.ex` (if exists)

**Changes:**
1. **Deprecate `token` field**
   - Keep field but mark as unused
   - Hubs can keep token field for historical data but it's not used for rewards

---

## Phase 5: Smart Contract Changes

### 5.1 BuxBoosterGame Configuration

**Files:**
- `contracts/bux-booster-game/scripts/configure-tokens.js`
- `contracts/bux-booster-game/scripts/deploy.js`
- `contracts/bux-booster-game/scripts/deploy-transparent.js`
- `contracts/bux-booster-game/scripts/deploy-direct.js`

**Changes:**
1. **Remove hub token addresses from scripts**
   - Only configure BUX token for betting (ROGUE is native, not configured)

---

## Phase 6: Documentation Updates

### 6.1 Files to Update

1. **`claude.md`** - Remove hub token references, update token list
2. **`docs/bux_token.md`** - Simplify to only BUX and ROGUE
3. **`docs/bux_minter.md`** - Update API endpoints
4. **`docs/rewards_system.md`** - Remove multi-token reward logic
5. **`docs/rogue_integration.md`** - Update balance display section
6. **`docs/bux_booster.md`** - Already uses only BUX/ROGUE

---

## Phase 7: Testing Checklist

### 7.1 Functionality Tests

- [x] Reading article earns BUX (not hub token)
- [x] Sharing article earns BUX (not hub token)
- [x] Header dropdown shows only BUX and ROGUE
- [x] Member page shows only BUX and ROGUE balances
- [x] Hub index page shows "Earn BUX" badge
- [x] Hub show page shows "Earn BUX" badge
- [x] Shop product pages show only BUX discount
- [x] Shop checkout uses only BUX for discount
- [x] BUX Booster still works with BUX and ROGUE
- [x] Balance sync fetches only BUX and ROGUE

### 7.2 UI/UX Tests

- [x] No hub token names visible anywhere (except historical data)
- [x] All "Earning moonBUX" etc. messages replaced with "Earning BUX"
- [x] Token dropdown simplified and cleaner
- [x] Shop discount UI simplified

---

## Migration Strategy

### Step 1: Backend First
1. Update BUX Minter service
2. Update Elixir modules (BuxMinter, EngagementTracker)
3. Deploy backend changes

### Step 2: Frontend Second
1. Update LiveViews and templates
2. Update JavaScript hooks
3. Deploy frontend changes

### Step 3: Cleanup
1. Update documentation
2. Run full test suite
3. Monitor for any issues

---

## Rollback Plan

If issues arise:
1. Revert to previous code version
2. Hub tokens still exist in Mnesia (data not deleted)
3. BUX Minter service can be reverted independently

---

## Files Changed Summary

| File | Type | Changes |
|------|------|---------|
| `bux-minter/index.js` | Backend | Remove hub token addresses, simplify endpoints |
| `lib/blockster_v2/bux_minter.ex` | Backend | Remove hub token support |
| `lib/blockster_v2/engagement_tracker.ex` | Backend | Simplify token handling |
| `lib/blockster_v2/mnesia_initializer.ex` | Backend | Add deprecation comments |
| `lib/blockster_v2_web/components/layouts.ex` | Frontend | Simplify balance dropdown |
| `lib/blockster_v2_web/live/post_live/show.ex` | Frontend | Remove hub token logic |
| `lib/blockster_v2_web/live/post_live/show.html.heex` | Frontend | Replace hub token text |
| `lib/blockster_v2_web/live/member_live/show.ex` | Frontend | Simplify token display |
| `lib/blockster_v2_web/live/member_live/show.html.heex` | Frontend | Simplify dropdown |
| `lib/blockster_v2_web/live/hub_live/index.ex` | Frontend | Remove hub BUX tracking |
| `lib/blockster_v2_web/live/hub_live/index.html.heex` | Frontend | Replace hub tokens |
| `lib/blockster_v2_web/live/hub_live/show.ex` | Frontend | Remove hub BUX tracking |
| `lib/blockster_v2_web/live/hub_live/show.html.heex` | Frontend | Replace hub tokens |
| `lib/blockster_v2_web/live/shop_live/show.ex` | Frontend | Remove hub token discount |
| `lib/blockster_v2_web/live/shop_live/show.html.heex` | Frontend | Simplify discount UI |
| `lib/blockster_v2_web/live/shop_live/index.ex` | Frontend | Remove hub token discount |
| `lib/blockster_v2_web/live/product_live/form.ex` | Frontend | Remove hub token field |
| `lib/blockster_v2_web/components/shared_components.ex` | Frontend | Simplify token badge |
| `lib/blockster_v2/shop/product.ex` | Schema | Deprecate hub token field |
| `assets/js/app.js` | JavaScript | Remove TokenAllocationDropdown |
| `contracts/bux-booster-game/scripts/*.js` | Contracts | Remove hub token config |
| `claude.md` | Docs | Update token documentation |
| `docs/*.md` | Docs | Update various docs |

---

## Estimated Impact

- **Lines of code removed:** ~500-800
- **Complexity reduction:** Significant simplification
- **User impact:** Cleaner UI, simpler token system
- **Performance:** Slightly faster (fewer tokens to fetch/display)

---

## Implementation Notes (January 2026)

### Completed Changes

All phases were completed successfully. Key files modified:

**Backend:**
- `bux-minter/index.js` - Simplified to BUX-only minting
- `lib/blockster_v2/bux_minter.ex` - Removed hub token support
- `lib/blockster_v2/engagement_tracker.ex` - Simplified token tracking

**Frontend:**
- `lib/blockster_v2_web/components/layouts.ex` - Simplified balance dropdown
- `lib/blockster_v2_web/live/post_live/show.ex` - Always mint BUX
- `lib/blockster_v2_web/live/member_live/show.ex` - BUX/ROGUE only
- `lib/blockster_v2_web/live/hub_live/index.ex` - Static "Earn BUX" badge
- `lib/blockster_v2_web/live/hub_live/show.ex` - Static "Earn BUX" badge
- `lib/blockster_v2_web/live/shop_live/show.ex` - BUX-only discounts
- `lib/blockster_v2_web/components/shared_components.ex` - Simplified token_badge

**JavaScript:**
- `assets/js/app.js` - Removed TokenAllocationDropdown hook

**Documentation:**
- `docs/bux_token.md` - Updated with deprecation notice
- `docs/rewards_system.md` - Simplified to BUX-only
- `docs/engagement_tracking.md` - Added deprecation notice
- `docs/bux_minter.md` - Simplified to BUX-only

### Migration Notes

- Mnesia table schema unchanged (hub token fields remain but unused)
- Smart contracts remain unchanged (historical tokens still on Rogue Chain)
- No data migration needed (existing balances unaffected)
- Rollback possible by reverting code changes
