# Shop Product Slots System

## Progress Summary

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ COMPLETED | Dismantle old SiteSettings-based system |
| Phase 2 | ✅ COMPLETED | Add Mnesia table definition |
| Phase 3 | ✅ COMPLETED | Create ShopSlots context module |
| Phase 4 | ✅ COMPLETED | Rewrite LiveView mount |
| Phase 5 | ✅ COMPLETED | Rewrite event handlers |
| Phase 6 | ✅ COMPLETED | Rewrite template |
| Phase 7 | 🔄 IN PROGRESS | Test & verify |
| Phase 8 | ⬜ TODO | Cleanup & deploy |

**Last Updated**: Feb 2, 2026

**Key Files Changed**:
- `lib/blockster_v2_web/live/shop_live/index.ex` - LiveView controller
- `lib/blockster_v2_web/live/shop_live/index.html.heex` - Template
- `lib/blockster_v2/shop_slots.ex` - NEW: Mnesia context module
- `lib/blockster_v2/mnesia_initializer.ex` - Added table definition

---

## Overview

A simple slot-based product display system where each card position is independently managed. Admin can assign any product to any slot without affecting other slots.

---

## Step 0: Dismantle Current Broken System

**The current system is fundamentally broken.** It uses SiteSettings to store a comma-separated list of product IDs, with complex list manipulation that causes products to appear in wrong positions. This must be completely removed before implementing the new system.

### 0.1 Remove SiteSettings References

**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

**Delete these lines from mount function:**
```elixir
# DELETE: Load curated product placements from SiteSettings
placements_setting = SiteSettings.get("shop_page_product_placements", "")
curated_product_ids = parse_product_ids(placements_setting)
```

**Delete these socket assigns from mount:**
```elixir
# DELETE these assigns:
|> assign(:curated_product_ids, curated_product_ids)
```

### 0.2 Remove Broken Helper Functions

**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

**Delete entire functions:**

```elixir
# DELETE: parse_product_ids/1 (lines 61-69)
defp parse_product_ids(""), do: []
defp parse_product_ids(nil), do: []
defp parse_product_ids(setting) do
  setting
  |> String.split(",")
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
end

# DELETE: build_display_order/2 (lines 71-86)
defp build_display_order(curated_ids, all_products) do
  curated =
    curated_ids
    |> Enum.map(fn id -> Enum.find(all_products, &(to_string(&1.id) == id)) end)
    |> Enum.reject(&is_nil/1)

  curated_id_set = MapSet.new(curated_ids)
  remaining = Enum.reject(all_products, fn p ->
    to_string(p.id) in curated_id_set
  end)

  curated ++ remaining
end

# DELETE: update_curated_ids/3 (lines 282-294)
defp update_curated_ids(existing_ids, slot, new_id) do
  padded = existing_ids ++ List.duplicate("", max(0, slot + 1 - length(existing_ids)))

  padded
  |> List.replace_at(slot, new_id)
  |> Enum.filter(&(&1 != ""))
  |> Enum.uniq()
end
```

### 0.3 Remove Broken Event Handler

**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

**Delete or gut the select_product_for_slot handler (lines 234-253):**
```elixir
# DELETE this entire handler - will be rewritten:
@impl true
def handle_event("select_product_for_slot", %{"id" => product_id}, socket) do
  slot = socket.assigns.picking_slot
  curated_ids = socket.assigns.curated_product_ids

  new_curated_ids = update_curated_ids(curated_ids, slot, product_id)

  SiteSettings.set("shop_page_product_placements", Enum.join(new_curated_ids, ","))

  display_products = build_display_order(new_curated_ids, socket.assigns.all_products)

  {:noreply,
   socket
   |> assign(:curated_product_ids, new_curated_ids)
   |> assign(:products, Enum.map(display_products, &transform_product/1))
   |> assign(:show_product_picker, false)
   |> assign(:picking_slot, nil)}
end
```

### 0.4 Remove SiteSettings Alias

**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

**Delete this line (around line 5):**
```elixir
# DELETE:
alias BlocksterV2.SiteSettings
```

### 0.5 Clear Old SiteSettings Data (Optional)

**In IEx console** (after deployment):
```elixir
# Clear the broken curated placements data
BlocksterV2.SiteSettings.delete("shop_page_product_placements")
```

### Why The Old System Was Broken

1. **`Enum.filter(&(&1 != ""))` removed empty slots** - This compacted the list, shifting all positions after any empty slot

2. **`Enum.uniq()` kept first occurrence** - If you tried to move a product to a new slot, it stayed in its original position because uniq keeps the first one

3. **Display index ≠ curated index** - The template used display position (index in rendered list) but the backend tried to manipulate curated IDs list positions. These don't align when:
   - Some curated IDs point to deleted/invalid products (filtered out by `Enum.reject(&is_nil/1)`)
   - Empty slots exist in the curated list

4. **No atomic slot updates** - Changing one slot triggered list manipulation that affected other slots

---

## Key Principles

1. **Each slot is independent** - Changing one slot never affects another
2. **No uniqueness constraints** - Same product can appear in multiple slots
3. **Empty by default** - New slots show empty placeholder cards until admin assigns a product
4. **Mnesia-backed** - Slot assignments stored in Mnesia for fast reads
5. **Position is absolute** - Slot 17 is always slot 17, regardless of what's in slots 1-16

---

## Data Model

### Mnesia Table: `shop_product_slots`

```elixir
# Table definition in MnesiaInitializer
:mnesia.create_table(:shop_product_slots, [
  attributes: [:slot_number, :product_id],
  disc_copies: [node()],
  type: :set
])
```

| Field | Type | Description |
|-------|------|-------------|
| `slot_number` | integer | Primary key. 0-indexed slot position |
| `product_id` | string \| nil | UUID of assigned product, or nil if empty |

### Example Data

```
Slot 0  -> "abc-123-uuid"  (Product A)
Slot 1  -> "def-456-uuid"  (Product B)
Slot 2  -> nil             (Empty - shows placeholder)
Slot 3  -> "abc-123-uuid"  (Product A again - duplicates OK)
Slot 4  -> "ghi-789-uuid"  (Product C)
...
Slot 16 -> "xyz-999-uuid"  (Product X)
```

---

## Implementation Steps

### Step 1: Add Mnesia Table Definition

**File**: `lib/blockster_v2/mnesia_initializer.ex`

**Action**: Add `shop_product_slots` table to the tables list in `ensure_tables_exist/0`

```elixir
defp ensure_tables_exist do
  tables = [
    # ... existing tables ...
    {:shop_product_slots, [
      attributes: [:slot_number, :product_id],
      disc_copies: [node()],
      type: :set
    ]}
  ]
  # ... rest of function
end
```

**Why**: Mnesia table must be defined before it can be used. The `:set` type ensures one record per slot_number.

---

### Step 2: Create ShopSlots Context Module

**File**: `lib/blockster_v2/shop_slots.ex` (NEW FILE)

**Action**: Create a new module with these functions:

```elixir
defmodule BlocksterV2.ShopSlots do
  @moduledoc """
  Manages shop product slot assignments in Mnesia.
  Each slot is independent - assigning a product to one slot
  does not affect any other slot.
  """

  @doc """
  Get the product_id assigned to a specific slot.
  Returns nil if slot is empty or not yet assigned.
  """
  def get_slot(slot_number) when is_integer(slot_number) do
    case :mnesia.dirty_read({:shop_product_slots, slot_number}) do
      [{:shop_product_slots, ^slot_number, product_id}] -> product_id
      [] -> nil
    end
  end

  @doc """
  Get all slot assignments as a map of %{slot_number => product_id}.
  Only returns slots that have been assigned (not empty ones).
  """
  def get_all_slots do
    :mnesia.dirty_match_object({:shop_product_slots, :_, :_})
    |> Enum.reduce(%{}, fn {:shop_product_slots, slot_number, product_id}, acc ->
      Map.put(acc, slot_number, product_id)
    end)
  end

  @doc """
  Assign a product to a specific slot.
  Overwrites any existing assignment for that slot.
  Does NOT affect any other slots.
  """
  def set_slot(slot_number, product_id) when is_integer(slot_number) do
    :mnesia.dirty_write({:shop_product_slots, slot_number, product_id})
    :ok
  end

  @doc """
  Clear a slot (set to empty/nil).
  """
  def clear_slot(slot_number) when is_integer(slot_number) do
    :mnesia.dirty_write({:shop_product_slots, slot_number, nil})
    :ok
  end

  @doc """
  Build display list for a given number of slots.
  Returns list of {slot_number, product_id_or_nil} tuples.
  """
  def build_display_list(total_slots) do
    slot_map = get_all_slots()

    Enum.map(0..(total_slots - 1), fn slot_number ->
      {slot_number, Map.get(slot_map, slot_number)}
    end)
  end
end
```

**Why**: Encapsulates all Mnesia operations. Simple API: `get_slot/1`, `set_slot/2`, `build_display_list/1`.

---

### Step 3: Rewrite ShopLive.Index Mount Function

**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

**Action**: Replace current mount with:

```elixir
alias BlocksterV2.ShopSlots

@impl true
def mount(_params, _session, socket) do
  # Load all active products (for product picker and filtering)
  all_products = Shop.list_active_products(preload: [:images, :variants, :hub, :artist_record, :categories])

  # Total slots = total active products
  total_slots = length(all_products)

  # Build products map for quick lookup by ID
  products_by_id = Map.new(all_products, fn p -> {to_string(p.id), p} end)

  # Get slot assignments and build display list
  display_slots = build_display_slots(total_slots, products_by_id)

  # Extract dynamic filters (same as before)
  categories_with_products = extract_categories(all_products)
  hubs_with_products = extract_hubs(all_products)
  brands_with_products = extract_brands(all_products)

  {:ok,
   socket
   |> assign(:page_title, "Shop - Browse Products")
   |> assign(:all_products, all_products)
   |> assign(:products_by_id, products_by_id)
   |> assign(:total_slots, total_slots)
   |> assign(:display_slots, display_slots)
   |> assign(:categories_with_products, categories_with_products)
   |> assign(:hubs_with_products, hubs_with_products)
   |> assign(:brands_with_products, brands_with_products)
   |> assign(:active_filter, nil)
   |> assign(:filtered_products, nil)
   |> assign(:show_product_picker, false)
   |> assign(:picking_slot, nil)
   |> assign(:show_mobile_filters, false)}
end

# Build display slots list: [{slot_number, product_or_nil}, ...]
defp build_display_slots(total_slots, products_by_id) do
  ShopSlots.build_display_list(total_slots)
  |> Enum.map(fn {slot_number, product_id} ->
    product = if product_id, do: Map.get(products_by_id, product_id), else: nil
    transformed = if product, do: transform_product(product), else: nil
    {slot_number, transformed}
  end)
end

# Keep existing transform_product/1 function

defp extract_categories(products) do
  products
  |> Enum.flat_map(fn p -> p.categories || [] end)
  |> Enum.uniq_by(& &1.id)
  |> Enum.sort_by(& &1.name)
end

defp extract_hubs(products) do
  products
  |> Enum.map(& &1.hub)
  |> Enum.reject(&is_nil/1)
  |> Enum.uniq_by(& &1.id)
  |> Enum.sort_by(& &1.name)
end

defp extract_brands(products) do
  products
  |> Enum.map(& &1.vendor)
  |> Enum.reject(&is_nil/1)
  |> Enum.reject(&(&1 == ""))
  |> Enum.uniq()
  |> Enum.sort()
end
```

**Why**:
- `total_slots` = number of active products (determines how many cards to show)
- `display_slots` = list of `{slot_number, product_or_nil}` tuples
- `products_by_id` = map for O(1) product lookup when building display

---

### Step 4: Update Event Handler for Product Selection

**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

**Action**: Replace `select_product_for_slot` handler:

```elixir
@impl true
def handle_event("select_product_for_slot", %{"id" => product_id}, socket) do
  slot = socket.assigns.picking_slot

  # Save to Mnesia - this ONLY affects this one slot
  ShopSlots.set_slot(slot, product_id)

  # Rebuild display slots
  display_slots = build_display_slots(
    socket.assigns.total_slots,
    socket.assigns.products_by_id
  )

  {:noreply,
   socket
   |> assign(:display_slots, display_slots)
   |> assign(:show_product_picker, false)
   |> assign(:picking_slot, nil)}
end
```

**Why**: Single Mnesia write for one slot. No filtering, no uniqueness checks, no list manipulation.

---

### Step 5: Update Filter Event Handlers

**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

**Action**: Filters should show filtered products, View All shows slot-based display:

```elixir
@impl true
def handle_event("filter_by_category", %{"slug" => slug, "name" => name}, socket) do
  filtered = socket.assigns.all_products
  |> Enum.filter(fn p -> Enum.any?(p.categories || [], &(&1.slug == slug)) end)
  |> Enum.map(&transform_product/1)

  {:noreply,
   socket
   |> assign(:active_filter, {:category, slug, name})
   |> assign(:filtered_products, filtered)
   |> assign(:show_mobile_filters, false)}
end

@impl true
def handle_event("filter_by_hub", %{"slug" => slug, "name" => name}, socket) do
  filtered = socket.assigns.all_products
  |> Enum.filter(fn p -> p.hub && p.hub.slug == slug end)
  |> Enum.map(&transform_product/1)

  {:noreply,
   socket
   |> assign(:active_filter, {:hub, slug, name})
   |> assign(:filtered_products, filtered)
   |> assign(:show_mobile_filters, false)}
end

@impl true
def handle_event("filter_by_brand", %{"brand" => brand}, socket) do
  filtered = socket.assigns.all_products
  |> Enum.filter(fn p -> p.vendor == brand end)
  |> Enum.map(&transform_product/1)

  {:noreply,
   socket
   |> assign(:active_filter, {:brand, brand})
   |> assign(:filtered_products, filtered)
   |> assign(:show_mobile_filters, false)}
end

@impl true
def handle_event("clear_all_filters", _params, socket) do
  {:noreply,
   socket
   |> assign(:active_filter, nil)
   |> assign(:filtered_products, nil)
   |> assign(:show_mobile_filters, false)}
end
```

**Why**:
- When filter active: show `@filtered_products` (regular product list)
- When no filter (View All): show `@display_slots` (slot-based with empty placeholders)

---

### Step 6: Update Template for Slot-Based Display

**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

**Action**: Replace product grid with conditional rendering:

```heex
<main class="flex-1 min-w-0">
  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4 md:gap-6">
    <%= if @active_filter == nil do %>
      <%!-- VIEW ALL MODE: Show slot-based cards --%>
      <%= for {slot_number, product} <- @display_slots do %>
        <div class="relative group">
          <%!-- Admin Cog Icon - Always visible on slots --%>
          <%= if @current_user && @current_user.is_admin do %>
            <button
              phx-click="open_product_picker"
              phx-value-slot={slot_number}
              class="absolute top-3 right-3 z-20 opacity-0 group-hover:opacity-100 transition-opacity bg-white rounded-full p-2 shadow-md hover:shadow-lg cursor-pointer"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-600" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd" />
              </svg>
            </button>
          <% end %>

          <%= if product do %>
            <%!-- Product Card (existing card markup) --%>
            <.link navigate={~p"/shop/#{product.slug}"} class="rounded-lg border border-gray-200 bg-white hover:shadow-lg transition-shadow cursor-pointer block">
              <%!-- ... existing product card content ... --%>
            </.link>
          <% else %>
            <%!-- Empty Slot Placeholder --%>
            <div class="rounded-lg border-2 border-dashed border-gray-300 bg-gray-50 aspect-square flex items-center justify-center">
              <div class="text-center text-gray-400">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-12 w-12 mx-auto mb-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
                <p class="text-sm font-haas_roman_55">Slot <%= slot_number + 1 %></p>
                <p class="text-xs">Click cog to assign</p>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    <% else %>
      <%!-- FILTERED MODE: Show filtered products (no empty slots) --%>
      <%= for product <- @filtered_products do %>
        <div class="relative group">
          <.link navigate={~p"/shop/#{product.slug}"} class="rounded-lg border border-gray-200 bg-white hover:shadow-lg transition-shadow cursor-pointer block">
            <%!-- ... existing product card content ... --%>
          </.link>
        </div>
      <% end %>

      <%!-- Empty state for filtered results --%>
      <%= if @filtered_products == [] do %>
        <div class="col-span-full text-center py-12">
          <p class="text-gray-500 mb-4">No products found</p>
          <button phx-click="clear_all_filters" class="text-blue-500 hover:underline cursor-pointer">
            View All Products
          </button>
        </div>
      <% end %>
    <% end %>
  </div>
</main>
```

**Why**:
- `@active_filter == nil` = View All mode = show slots with empty placeholders
- `@active_filter != nil` = Filtered mode = show filtered products normally
- Empty slots show placeholder with slot number and "Click cog to assign"

---

### Step 7: Remove Old SiteSettings Code

**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

**Action**: Remove these items:

1. Remove `alias BlocksterV2.SiteSettings`
2. Remove `parse_product_ids/1` function
3. Remove `build_display_order/2` function
4. Remove `update_curated_ids/3` function
5. Remove `:curated_product_ids` assign
6. Remove any references to `shop_page_product_placements` SiteSettings key

**Why**: Old system is completely replaced by Mnesia slots.

---

### Step 8: Restart Nodes to Create Mnesia Table

**Action**: After adding the table definition, restart both dev nodes:

```bash
# Terminal 1
# Stop node1 (Ctrl+C twice)
elixir --sname node1 -S mix phx.server

# Terminal 2
# Stop node2 (Ctrl+C twice)
PORT=4001 elixir --sname node2 -S mix phx.server
```

**Why**: MnesiaInitializer only creates tables on application startup.

---

## Testing Checklist

### Basic Functionality
- [ ] Page loads with N empty slot cards (N = total active products)
- [ ] Each empty slot shows "Slot X" label and placeholder
- [ ] Admin cog icon appears on hover for each slot
- [ ] Clicking cog opens product picker
- [ ] Selecting product in picker assigns it to that specific slot
- [ ] Product picker closes after selection
- [ ] Assigned product displays in its slot
- [ ] Page reload shows same slot assignments

### Independence Verification
- [ ] Assign product A to slot 5
- [ ] Assign product B to slot 10
- [ ] Verify slot 5 still shows product A
- [ ] Assign product A to slot 15 (duplicate)
- [ ] Verify slots 5, 10, 15 all show correct products

### Filter Behavior
- [ ] Click category filter - shows filtered products (not slots)
- [ ] Click hub filter - shows filtered products (not slots)
- [ ] Click brand filter - shows filtered products (not slots)
- [ ] Click "View All" - returns to slot-based view with assignments

### Edge Cases
- [ ] Delete a product from database - slot shows empty (product not found)
- [ ] Empty slot still has working cog icon
- [ ] Re-assigning same slot overwrites previous assignment

---

## Data Flow Summary

```
Page Load / View All:
  1. Load all_products from DB
  2. total_slots = length(all_products)
  3. Read Mnesia: get_all_slots()
  4. Build display_slots: [(0, product_or_nil), (1, product_or_nil), ...]
  5. Render: slot cards with product or placeholder

Admin Assigns Product to Slot N:
  1. Click cog on slot N -> open_product_picker(slot: N)
  2. Select product -> select_product_for_slot(id: UUID)
  3. Mnesia: dirty_write({:shop_product_slots, N, UUID})
  4. Rebuild display_slots
  5. Re-render: slot N now shows selected product

Filter Selected:
  1. Filter all_products by criteria
  2. Set filtered_products = filtered list
  3. Set active_filter = filter info
  4. Render: filtered products (not slots)

View All Selected:
  1. Set active_filter = nil
  2. Set filtered_products = nil
  3. Render: display_slots (slot-based view)
```

---

## Why This Design

1. **Simplicity**: One Mnesia record per slot. No list manipulation, no reordering.

2. **Independence**: `set_slot(17, "uuid")` writes one record. Slots 0-16 and 18+ are untouched.

3. **No Uniqueness**: Same product can be in multiple slots. Business decision, not technical constraint.

4. **Empty by Default**: New installations show all empty slots until admin configures.

5. **Fast Reads**: Mnesia dirty_read is O(1). Building display list is O(N) where N = total slots.

6. **Persistence**: Mnesia disc_copies survive restarts. No SiteSettings string parsing.

7. **Scalability**: If you have 100 products, you have 100 slots. Adding products adds slots automatically.

---

## Implementation Checklist

### Phase 1: Dismantle Old System ✅ COMPLETED
**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

- [x] **1.1** Delete `alias BlocksterV2.SiteSettings` (line ~5)
- [x] **1.2** Delete from mount: `placements_setting = SiteSettings.get("shop_page_product_placements", "")`
- [x] **1.3** Delete from mount: `curated_product_ids = parse_product_ids(placements_setting)`
- [x] **1.4** Delete from mount assigns: `|> assign(:curated_product_ids, curated_product_ids)`
- [x] **1.5** Delete entire `parse_product_ids/1` function (3 clauses, ~9 lines)
- [x] **1.6** Delete entire `build_display_order/2` function (~15 lines)
- [x] **1.7** Delete entire `update_curated_ids/3` function (~10 lines)
- [x] **1.8** Delete entire `handle_event("select_product_for_slot", ...)` handler (~20 lines) - will be rewritten

**Implementation Note**: All old SiteSettings code removed. The broken list manipulation logic that caused position shifting is gone.

---

### Phase 2: Add Mnesia Table ✅ COMPLETED
**File**: `lib/blockster_v2/mnesia_initializer.ex`

- [x] **2.1** Find `ensure_tables_exist/0` function
- [x] **2.2** Add to tables list:
  ```elixir
  # Shop product slot assignments (curated product placements)
  %{
    name: :shop_product_slots,
    type: :set,
    attributes: [
      :slot_number,              # PRIMARY KEY - 0-indexed slot position (integer)
      :product_id                # Product UUID (string) or nil for empty slot
    ],
    index: []
  }
  ```
- [x] **2.3** Verify table definition compiles without errors

**Implementation Note**: Used the project's standard map format for table definitions (with `name:`, `type:`, `attributes:`, `index:` keys) to match existing tables in MnesiaInitializer.

---

### Phase 3: Create ShopSlots Context Module ✅ COMPLETED
**File**: `lib/blockster_v2/shop_slots.ex` (NEW FILE)

- [x] **3.1** Create new file `lib/blockster_v2/shop_slots.ex`
- [x] **3.2** Add module definition: `defmodule BlocksterV2.ShopSlots do`
- [x] **3.3** Add `@moduledoc` with description
- [x] **3.4** Implement `get_slot/1`:
  ```elixir
  def get_slot(slot_number) when is_integer(slot_number) do
    case :mnesia.dirty_read({:shop_product_slots, slot_number}) do
      [{:shop_product_slots, ^slot_number, product_id}] -> product_id
      [] -> nil
    end
  end
  ```
- [x] **3.5** Implement `get_all_slots/0`:
  ```elixir
  def get_all_slots do
    :mnesia.dirty_match_object({:shop_product_slots, :_, :_})
    |> Enum.reduce(%{}, fn {:shop_product_slots, slot_number, product_id}, acc ->
      Map.put(acc, slot_number, product_id)
    end)
  end
  ```
- [x] **3.6** Implement `set_slot/2`:
  ```elixir
  def set_slot(slot_number, product_id) when is_integer(slot_number) do
    :mnesia.dirty_write({:shop_product_slots, slot_number, product_id})
    :ok
  end
  ```
- [x] **3.7** Implement `clear_slot/1`:
  ```elixir
  def clear_slot(slot_number) when is_integer(slot_number) do
    :mnesia.dirty_write({:shop_product_slots, slot_number, nil})
    :ok
  end
  ```
- [x] **3.8** Implement `build_display_list/1`:
  ```elixir
  def build_display_list(total_slots) do
    slot_map = get_all_slots()
    Enum.map(0..(total_slots - 1), fn slot_number ->
      {slot_number, Map.get(slot_map, slot_number)}
    end)
  end
  ```
- [x] **3.9** Verify module compiles without errors

**Implementation Note**: Created exactly as documented. Simple API that encapsulates all Mnesia operations. Uses dirty operations for performance.

---

### Phase 4: Rewrite LiveView Mount ✅ COMPLETED
**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

- [x] **4.1** Add alias: `alias BlocksterV2.ShopSlots`
- [x] **4.2** In mount, calculate `total_slots = length(all_products)`
- [x] **4.3** In mount, build products map: `products_by_id = Map.new(all_products, fn p -> {to_string(p.id), p} end)`
- [x] **4.4** In mount, build display slots: `display_slots = build_display_slots(total_slots, products_by_id)`
- [x] **4.5** Add new assigns to socket:
  - [x] `|> assign(:products_by_id, products_by_id)`
  - [x] `|> assign(:total_slots, total_slots)`
  - [x] `|> assign(:display_slots, display_slots)`
  - [x] `|> assign(:filtered_products, nil)`
- [x] **4.6** Remove old assign: `:products` (replaced by `:display_slots` and `:filtered_products`)
- [x] **4.7** Remove old assign: `:filtered_mode` (replaced by checking `@active_filter == nil`)
- [x] **4.8** Add `build_display_slots/2` helper function:
  ```elixir
  defp build_display_slots(total_slots, products_by_id) do
    ShopSlots.build_display_list(total_slots)
    |> Enum.map(fn {slot_number, product_id} ->
      product = if product_id, do: Map.get(products_by_id, product_id), else: nil
      transformed = if product, do: transform_product(product), else: nil
      {slot_number, transformed}
    end)
  end
  ```
- [x] **4.9** Rename/simplify filter extraction helpers:
  - [x] Kept inline in mount (no separate functions needed - simple enough)
- [x] **4.10** Remove old filter helper functions:
  - [x] Removed (were not present in final code)

**Implementation Note**: Also added `slot_assignments` assign and `build_slot_assignments/1` helper for showing which slots each product is assigned to in the product picker modal.

---

### Phase 5: Rewrite Event Handlers ✅ COMPLETED
**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

- [x] **5.1** Rewrite `handle_event("select_product_for_slot", ...)`:
  ```elixir
  @impl true
  def handle_event("select_product_for_slot", %{"id" => product_id}, socket) do
    slot = socket.assigns.picking_slot
    ShopSlots.set_slot(slot, product_id)
    display_slots = build_display_slots(
      socket.assigns.total_slots,
      socket.assigns.products_by_id
    )
    slot_assignments = build_slot_assignments(display_slots)
    {:noreply,
     socket
     |> assign(:display_slots, display_slots)
     |> assign(:slot_assignments, slot_assignments)
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)}
  end
  ```
- [x] **5.2** Update `handle_event("filter_by_category", ...)`:
  - [x] Filter `all_products` inline
  - [x] Transform and assign to `:filtered_products`
  - [x] Remove `:filtered_mode` assign
- [x] **5.3** Update `handle_event("filter_by_hub", ...)`:
  - [x] Filter `all_products` inline
  - [x] Transform and assign to `:filtered_products`
  - [x] Remove `:filtered_mode` assign
- [x] **5.4** Update `handle_event("filter_by_brand", ...)`:
  - [x] Filter `all_products` inline
  - [x] Transform and assign to `:filtered_products`
  - [x] Remove `:filtered_mode` assign
- [x] **5.5** Update `handle_event("clear_all_filters", ...)`:
  - [x] Set `:active_filter` to `nil`
  - [x] Set `:filtered_products` to `nil`
  - [x] Remove rebuild of display order (not needed - display_slots already correct)

**Implementation Note**: Added `slot_assignments` rebuild in `select_product_for_slot` to keep the product picker badges up-to-date after assignment changes.

---

### Phase 6: Rewrite Template ✅ COMPLETED
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **6.1** Find the product grid `<main>` section
- [x] **6.2** Add conditional: `<%= if @active_filter == nil do %>`
- [x] **6.3** In View All branch, loop over `@display_slots`:
  ```heex
  <%= for {slot_number, product} <- @display_slots do %>
  ```
- [x] **6.4** Change cog button `phx-value-slot` from `index` to `slot_number`
- [x] **6.5** Add slot number display next to cog icon (admin only)
- [x] **6.6** Add conditional for product vs empty slot
- [x] **6.6** Create empty slot placeholder markup with "Click cog to assign" text
- [x] **6.7** Add `<% else %>` branch for filtered mode
- [x] **6.8** In filtered branch, loop over `@filtered_products`
- [x] **6.9** In filtered branch, show product cards without admin cog
- [x] **6.10** Update product picker modal to show current slot assignments:
  - [x] Build `slot_assignments` map in mount: `%{product_id => [slot_numbers]}`
  - [x] Add assign: `|> assign(:slot_assignments, build_slot_assignments(display_slots))`
  - [x] Add helper function `build_slot_assignments/1`
  - [x] In product picker modal, show slot badges on products already assigned
  - [x] Update `slot_assignments` when product is assigned (in `select_product_for_slot` handler)
- [x] **6.11** Add empty state for filtered results
- [x] **6.12** Close conditional: `<% end %>`

**Implementation Note**: Template now has two distinct rendering modes:
1. **View All** (`@active_filter == nil`): Shows slot-based grid with `@display_slots`, empty placeholders for unassigned slots, admin cog with slot number
2. **Filtered** (`@active_filter != nil`): Shows filtered products from `@filtered_products`, no admin cog, no empty slots

---

### Phase 7: Test & Verify 🔄 IN PROGRESS

- [ ] **7.1** Restart both dev nodes to create Mnesia table:
  ```bash
  # Stop both nodes (Ctrl+C twice each)
  # Terminal 1:
  elixir --sname node1 -S mix phx.server
  # Terminal 2:
  PORT=4001 elixir --sname node2 -S mix phx.server
  ```
- [ ] **7.2** Verify page loads with empty slot placeholders
- [ ] **7.3** Click cog on slot 5, select product A - verify product appears in slot 5
- [ ] **7.4** Click cog on slot 10, select product B - verify product appears in slot 10, slot 5 unchanged
- [ ] **7.5** Click cog on slot 17, select product A (duplicate) - verify product appears in slot 17
- [ ] **7.6** Verify slots 5, 10, 17 all show correct products
- [ ] **7.7** Refresh page - verify all assignments persist
- [ ] **7.8** Click category filter - verify filtered products show (no empty slots)
- [ ] **7.9** Click View All - verify slot-based display with assignments
- [ ] **7.10** Test mobile filter drawer works

---

### Phase 8: Cleanup & Deploy

- [ ] **8.1** Run `mix compile --warnings-as-errors` - fix any warnings
- [ ] **8.2** Remove any remaining references to old system:
  - [ ] `curated_product_ids`
  - [ ] `curated_ids`
  - [ ] `shop_page_product_placements`
  - [ ] `SiteSettings`
- [ ] **8.3** Git add, commit, push:
  ```bash
  git add .
  git commit -m "feat: replace broken curated slots with Mnesia-backed independent slots

  - Each slot is independent (changing one never affects another)
  - Same product can appear in multiple slots (no uniqueness constraint)
  - Empty slots show placeholder cards until admin assigns product
  - Slot assignments stored in Mnesia for persistence and fast reads"
  ```
- [ ] **8.4** Deploy to Fly.io:
  ```bash
  flyctl deploy --app blockster-v2
  ```
- [ ] **8.5** Verify in production:
  - [ ] Page loads
  - [ ] Admin can assign products to slots
  - [ ] Assignments persist after page reload
  - [ ] Filters work correctly

---

### Optional: Clear Old SiteSettings Data

**After successful deploy and verification:**

```elixir
# In IEx on production node:
BlocksterV2.SiteSettings.delete("shop_page_product_placements")
```
