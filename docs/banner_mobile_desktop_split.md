# Shop Banner: Separate Desktop and Mobile Versions

## Overview

The shop page has an editable banner component (`FullWidthBannerComponent`) that allows admins to customize the hero image, text overlay, and button. Currently, a single set of settings is used for both desktop and mobile views.

**Goal**: Allow admins to configure desktop and mobile banners independently so that changes to one don't affect the other.

## Current Implementation

### Files Involved
- `lib/blockster_v2_web/live/post_live/full_width_banner_component.ex` - LiveComponent logic
- `lib/blockster_v2_web/live/post_live/full_width_banner_component.html.heex` - Template
- `lib/blockster_v2/site_settings.ex` - Key-value storage for settings

### How Settings Are Stored
Settings are stored in the `site_settings` table with keys like:
- `shop_page_banner` - Banner image URL
- `shop_page_banner_position` - Image position (e.g., "50% 50%")
- `shop_page_banner_zoom` - Zoom level
- `shop_page_banner_overlay_text` - Text content
- `shop_page_banner_overlay_position` - Text box position
- `shop_page_banner_button_text` - Button label
- `shop_page_banner_button_url` - Button link
- `shop_page_banner_height` - Banner height in pixels
- etc.

### Current Display Logic
The template uses responsive classes to show different heights:
```html
<div class="h-[280px] md:h-[600px]">
```
But all other content (image, text, button positions) is shared.

## Proposed Implementation

### 1. Settings Key Structure

Add a `_mobile` suffix for mobile-specific settings:

**Desktop (existing keys - unchanged):**
- `shop_page_banner`
- `shop_page_banner_position`
- `shop_page_banner_overlay_text`
- etc.

**Mobile (new keys):**
- `shop_page_banner_mobile`
- `shop_page_banner_mobile_position`
- `shop_page_banner_mobile_overlay_text`
- etc.

### 2. Component Changes (`full_width_banner_component.ex`)

#### A. Load Both Versions in `update/2`
```elixir
def update(assigns, socket) do
  banner_key = Map.get(assigns, :banner_key, "shop_landing_banner")
  settings = SiteSettings.get_by_prefix(banner_key)

  # Load desktop settings (original keys)
  desktop = load_banner_settings(settings, banner_key, "")

  # Load mobile settings (with _mobile suffix)
  # Falls back to desktop values if mobile not configured
  mobile = load_banner_settings(settings, banner_key, "_mobile", desktop)

  {:ok,
   socket
   |> assign(assigns)
   |> assign(:banner_key, banner_key)
   |> assign(:desktop, desktop)
   |> assign(:mobile, mobile)
   |> assign(:editing_version, :desktop)}
end
```

#### B. Add Helper for Loading Settings
```elixir
defp load_banner_settings(settings, banner_key, suffix, defaults \\ nil) do
  key = "#{banner_key}#{suffix}"

  %{
    banner_url: settings[key] || defaults[:banner_url] || @default_banner,
    banner_position: settings["#{key}_position"] || defaults[:banner_position] || "50% 50%",
    # ... all other settings
  }
end
```

#### C. Update Event Handlers
Event handlers need to know which version they're updating:

```elixir
def handle_event("update_position", %{"position" => position, "version" => version}, socket) do
  banner_key = socket.assigns.banner_key
  suffix = if version == "mobile", do: "_mobile", else: ""
  position_key = "#{banner_key}#{suffix}_position"

  case SiteSettings.set(position_key, position) do
    {:ok, _} ->
      # Update the correct version in assigns
      {:noreply, update_version_setting(socket, version, :banner_position, position)}
    {:error, _} ->
      {:noreply, socket}
  end
end
```

### 3. Template Changes (`full_width_banner_component.html.heex`)

#### A. Show Two Separate Banners
Display desktop version on `md:` (768px+), mobile version on smaller screens:

```heex
<%!-- Desktop Banner (hidden on mobile) --%>
<section class="hidden md:block w-full relative overflow-hidden">
  <%= render_banner(@desktop, @id, "desktop", assigns) %>
</section>

<%!-- Mobile Banner (hidden on desktop) --%>
<section class="md:hidden w-full relative overflow-hidden">
  <%= render_banner(@mobile, @id, "mobile", assigns) %>
</section>
```

**Breakpoint behavior:**
| Device | Width | Shows |
|--------|-------|-------|
| Phone | < 768px | Mobile banner |
| Tablet portrait | 768px+ | Desktop banner |
| Tablet landscape | 1024px+ | Desktop banner |
| Desktop | 1024px+ | Desktop banner |

#### B. Admin Controls: Version Toggle
Add a toggle to switch between editing desktop and mobile:

```heex
<%= if assigns[:current_user] && @current_user.is_admin do %>
  <div class="admin-controls">
    <!-- Version Toggle -->
    <div class="flex gap-2 mb-2">
      <button
        phx-click="set_editing_version"
        phx-value-version="desktop"
        class={if @editing_version == :desktop, do: "bg-black text-white", else: "bg-gray-200"}>
        Desktop
      </button>
      <button
        phx-click="set_editing_version"
        phx-value-version="mobile"
        class={if @editing_version == :mobile, do: "bg-black text-white", else: "bg-gray-200"}>
        Mobile
      </button>
    </div>
    <!-- Rest of admin controls -->
  </div>
<% end %>
```

#### C. Edit Modal: Show Version Label
Make it clear which version is being edited:

```heex
<h3 class="text-xl font-bold">
  Edit Banner (<%= if @editing_version == :desktop, do: "Desktop", else: "Mobile" %>)
</h3>
```

### 4. JavaScript Hook Updates

The drag/resize hooks need to pass the version being edited:

```javascript
// In BannerDrag hook
this.pushEventTo(this.el.dataset.target, "update_position", {
  position: newPosition,
  version: this.el.dataset.version  // "desktop" or "mobile"
});
```

### 5. Migration Strategy

**No database migration needed** - we're just adding new keys to the existing key-value store.

**Backwards compatible:**
- Existing settings continue to work as desktop settings
- Mobile settings default to desktop values if not set
- No data loss

### 6. Admin Workflow

1. Admin visits shop page
2. Sees toggle: **Desktop** | Mobile
3. Edits desktop banner (existing behavior)
4. Clicks "Mobile" toggle
5. Sees mobile preview
6. Edits mobile banner independently
7. Both versions saved separately

## Files to Modify

| File | Changes |
|------|---------|
| `full_width_banner_component.ex` | Load/save both versions, add version toggle handler |
| `full_width_banner_component.html.heex` | Two banner sections, version toggle UI, pass version to hooks |
| `assets/js/app.js` | Update hooks to pass version parameter |

## Testing Checklist

- [ ] Desktop banner displays correctly on desktop
- [ ] Mobile banner displays correctly on mobile
- [ ] Admin can toggle between desktop/mobile editing
- [ ] Changes to desktop don't affect mobile
- [ ] Changes to mobile don't affect desktop
- [ ] New mobile settings fall back to desktop values initially
- [ ] All drag/resize/upload features work for both versions
- [ ] Edit modal shows correct version label

## Estimated Changes

- **full_width_banner_component.ex**: ~100 lines added/modified
- **full_width_banner_component.html.heex**: ~50 lines added/modified
- **assets/js/app.js**: ~10 lines added

## Alternative Approaches Considered

### Option A: CSS-only approach
Use same settings but different CSS positioning for mobile.
- **Rejected**: Doesn't allow truly independent content (different images, text, etc.)

### Option B: Duplicate component
Create `MobileBannerComponent` and `DesktopBannerComponent`.
- **Rejected**: Code duplication, harder to maintain

### Option C: Single component with version parameter (chosen)
One component that handles both versions with a suffix system.
- **Chosen**: Clean, backwards compatible, no code duplication

---

## Implementation Checklist

### Phase 1: Component Logic (`full_width_banner_component.ex`) ✅ COMPLETE

- [x] **1.1** Add `editing_version: :desktop` to `mount/1` initial assigns
- [x] **1.2** Create `load_banner_settings/4` helper function
  - Takes: settings map, banner_key, suffix, optional defaults
  - Returns: map with all banner settings (banner_url, banner_position, banner_zoom, overlay_text, overlay_text_color, overlay_text_size, overlay_bg_color, overlay_bg_opacity, overlay_border_radius, overlay_position, overlay_width, overlay_height, button_text, button_url, button_bg_color, button_text_color, button_size, button_position, banner_height, show_text, show_button)
- [x] **1.3** Update `update/2` to load both desktop and mobile settings
  - Load desktop: `load_banner_settings(settings, banner_key, "")`
  - Load mobile: `load_banner_settings(settings, banner_key, "_mobile", desktop)` (fallback to desktop)
  - Assign `:desktop` and `:mobile` maps instead of individual assigns
- [x] **1.4** Add `handle_event("set_editing_version", ...)` handler
- [x] **1.5** Create `version_suffix/1` helper (`:desktop` -> `""`, `:mobile` -> `"_mobile"`)
- [x] **1.6** Create `update_version_setting/4` helper to update the correct version's assigns
- [x] **1.7** Update `handle_event("update_banner", ...)` to use version suffix
- [x] **1.8** Update `handle_event("update_position", ...)` to use version suffix
- [x] **1.9** Update `handle_event("update_zoom", ...)` to use version suffix
- [x] **1.10** Update `handle_event("update_overlay_position", ...)` to use version suffix
- [x] **1.11** Update `handle_event("update_overlay_size", ...)` to use version suffix
- [x] **1.12** Update `handle_event("update_button_position", ...)` to use version suffix
- [x] **1.13** Update `handle_event("save_overlay_settings", ...)` to use version suffix

### Phase 2: Template (`full_width_banner_component.html.heex`) ✅ COMPLETE

- [x] **2.1** ~~Create `render_banner/4` function component~~ - Opted for inline rendering in each section for simplicity
- [x] **2.2** Split main section into two: desktop (`hidden md:block`) and mobile (`md:hidden`)
- [x] **2.3** Each section renders its respective banner settings (`@desktop` or `@mobile`)
- [x] **2.4** Add Desktop/Mobile toggle buttons to admin controls panel
  - Style: selected = black bg, white text; unselected = gray bg
  - Position: at top of admin controls, below drag handle
- [x] **2.5** ~~Update admin controls to only show on the version being edited~~ - Made admin controls fixed position, shared between both versions
- [x] **2.6** Add `data-version="desktop"` or `data-version="mobile"` to draggable elements
- [x] **2.7** Update edit modal title to show which version is being edited
- [x] **2.8** ~~Pass version to form submission in edit modal~~ - Server uses `editing_version` from assigns

### Phase 3: JavaScript Hooks ✅ COMPLETE (No changes needed)

- [x] **3.1-3.4** Hooks push events to component, server uses `editing_version` from assigns to determine which version to update. No JS changes required.

### Phase 4: Testing

- [ ] **4.1** Test: Desktop banner displays correctly on screens >= 768px
- [ ] **4.2** Test: Mobile banner displays correctly on screens < 768px
- [ ] **4.3** Test: Version toggle switches which version is being edited
- [ ] **4.4** Test: Dragging banner image updates correct version only
- [ ] **4.5** Test: Dragging text overlay updates correct version only
- [ ] **4.6** Test: Dragging button updates correct version only
- [ ] **4.7** Test: Resizing text box updates correct version only
- [ ] **4.8** Test: Uploading new image updates correct version only
- [ ] **4.9** Test: Edit modal saves to correct version only
- [ ] **4.10** Test: Zoom controls update correct version only
- [ ] **4.11** Test: Mobile version defaults to desktop values when not yet configured
- [ ] **4.12** Test: Non-admin users see correct banner for their viewport (no admin controls)
- [ ] **4.13** Test: Both banners work on shop landing page (`shop_landing_banner` key)
- [ ] **4.14** Test: Both banners work on shop index page (`shop_page_banner` key)

### Phase 5: Deploy

- [ ] **5.1** Commit changes with descriptive message
- [ ] **5.2** Deploy to production
- [ ] **5.3** Verify on production (desktop and mobile)
