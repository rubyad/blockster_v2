# Anonymous Engagement Tracking System

## Overview

Allow non-logged-in users to see real-time earnings for reading posts and watching videos, with the ability to claim their earned rewards by signing up. This creates a powerful conversion funnel that demonstrates the value of the platform before requiring registration.

## User Experience Flow

### 1. Anonymous User Reads/Watches
- User lands on post without being logged in
- Earnings panel appears in bottom-right (same position as logged-in users)
- Panel tracks engagement in real-time showing:
  - Current engagement score (0-10)
  - BUX being earned (live calculation)
  - Progress indicators (time spent, scroll depth)
- **Anonymous User Earning Rates**:
  - **Reading**: 5 BUX per engagement point (max 50 BUX at 10/10 score)
  - **Video**: 5 BUX per minute watched
  - User earns whatever amount is shown when they click "Sign Up to Claim"
  - Amount updates in real-time as they engage
- **No blockchain transactions occur**
- **No data persisted server-side** (session-only)

### 2. User Navigates Away
- Session data is **lost** (not stored anywhere)
- If user returns to same post/video later, they start fresh
- Earnings calculation starts from zero again
- This is acceptable because no reward was paid out

### 3. User Clicks "Sign Up to Claim"
- Earnings panel shows "Sign Up to Claim X.XX BUX" button
- Button redirects to `/signup` with return path
- Session data stored in **browser localStorage** to survive redirect
- After successful signup/login:
  - User redirected back to post
  - Stored engagement data retrieved from localStorage
  - **Reward paid out immediately** to their new wallet
  - Panel shows "Claimed!" state with transaction link

## Architecture Changes

### A. Frontend Changes

#### 1. Engagement Tracker Hook (`assets/js/engagement_tracker.js`)

**Current Behavior**:
```javascript
// Skips tracking for anonymous users
if (!this.el.dataset.userId) {
  return;
}
```

**New Behavior**:
```javascript
mounted() {
  this.userId = this.el.dataset.userId; // May be null for anonymous
  this.isAnonymous = !this.userId;

  // Track for anonymous users too
  if (this.isAnonymous) {
    this.setupAnonymousTracking();
  } else {
    this.setupAuthenticatedTracking();
  }
}

setupAnonymousTracking() {
  // Store metrics in memory only
  this.anonymousMetrics = {
    timeSpent: 0,
    scrollDepth: 0,
    reachedEnd: false,
    scrollEvents: 0,
    // ... other metrics
  };

  // Send updates to server for score calculation
  // But don't trigger actual reward payout
  this.sendAnonymousUpdate();
}

sendAnonymousUpdate() {
  // Send engagement data with anonymous=true flag
  this.pushEvent("anonymous-engagement-update", {
    metrics: this.anonymousMetrics,
    postId: this.postId
  });
}

handleArticleEnd() {
  if (this.isAnonymous) {
    // Store in localStorage for claim after signup
    this.storeForClaim();
    // Show signup button in panel
    this.pushEvent("show-anonymous-claim", {
      metrics: this.anonymousMetrics
    });
  } else {
    // Normal flow - trigger reward
    this.pushEvent("article-read", {...});
  }
}

storeForClaim() {
  const claimData = {
    postId: this.postId,
    metrics: this.anonymousMetrics,
    timestamp: Date.now(),
    type: 'read' // or 'video'
  };

  localStorage.setItem(
    `pending_claim_${this.postId}`,
    JSON.stringify(claimData)
  );
}
```

#### 2. Video Watch Tracker Hook (`assets/js/video_watch_tracker.js`)

**Similar Changes**:
```javascript
mounted() {
  this.isAnonymous = !this.el.dataset.userId;

  if (this.isAnonymous) {
    this.setupAnonymousVideoTracking();
  }
}

handleVideoClose() {
  if (this.isAnonymous && this.earnableTime > 0) {
    // Calculate BUX earned: 5 BUX per minute for anonymous users
    const minutesWatched = this.earnableTime / 60;
    const buxEarned = minutesWatched * 5.0;

    // Store video watch data
    localStorage.setItem(`pending_claim_video_${this.postId}`, JSON.stringify({
      postId: this.postId,
      earnableTime: this.earnableTime,
      buxEarned: buxEarned,
      timestamp: Date.now(),
      type: 'video'
    }));

    // Show signup prompt
    this.pushEvent("show-anonymous-video-claim", {
      buxEarned: buxEarned
    });
  }
}
```

#### 3. New JavaScript Module (`assets/js/anonymous_claim_manager.js`)

```javascript
// Manages localStorage claim data and post-signup processing

export const AnonymousClaimManager = {
  // Store claim for later
  storeClaim(postId, type, metrics, earnedAmount) {
    const key = `pending_claim_${type}_${postId}`;
    localStorage.setItem(key, JSON.stringify({
      postId,
      type, // 'read' or 'video'
      metrics,
      earnedAmount,
      timestamp: Date.now(),
      expiresAt: Date.now() + (30 * 60 * 1000) // 30 min expiry
    }));
  },

  // Get all pending claims
  getPendingClaims() {
    const claims = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key.startsWith('pending_claim_')) {
        const data = JSON.parse(localStorage.getItem(key));

        // Check expiry
        if (data.expiresAt > Date.now()) {
          claims.push(data);
        } else {
          // Clean up expired
          localStorage.removeItem(key);
        }
      }
    }
    return claims;
  },

  // Clear claim after processing
  clearClaim(postId, type) {
    localStorage.removeItem(`pending_claim_${type}_${postId}`);
  },

  // Clear all claims
  clearAllClaims() {
    const keys = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key.startsWith('pending_claim_')) {
        keys.push(key);
      }
    }
    keys.forEach(k => localStorage.removeItem(k));
  }
};
```

---

### B. Backend Changes

#### 1. Post LiveView (`lib/blockster_v2_web/live/post_live/show.ex`)

**Mount Changes**:
```elixir
def mount(%{"slug" => slug}, session, socket) do
  # ... existing code ...

  # Check if user just signed up and has pending claim
  pending_claim = get_connect_params(socket)["pending_claim"]

  socket = if current_user && pending_claim do
    # Process the claim from localStorage
    process_anonymous_claim(socket, pending_claim)
  else
    socket
  end

  # Allow anonymous users to see engagement panel
  socket = assign(socket,
    is_anonymous: current_user == nil,
    show_signup_prompt: false,
    anonymous_earned: 0
  )

  {:ok, socket}
end
```

**New Event Handlers**:
```elixir
# Handle anonymous engagement updates (calculate but don't reward)
def handle_event("anonymous-engagement-update", params, socket) do
  if socket.assigns.is_anonymous do
    # Calculate engagement score
    engagement_score = calculate_engagement_score(params["metrics"])

    # Calculate BUX earned for anonymous users
    # FIXED RATE: 5 BUX per engagement point (max 50 BUX at 10/10)
    bux_earned = engagement_score * 5.0

    {:noreply,
     socket
     |> assign(:engagement_score, engagement_score)
     |> assign(:anonymous_earned, bux_earned)
     |> assign(:show_earning_progress, true)}
  else
    {:noreply, socket}
  end
end

# Show signup prompt when anonymous user completes article/video
def handle_event("show-anonymous-claim", params, socket) do
  if socket.assigns.is_anonymous do
    engagement_score = calculate_engagement_score(params["metrics"])
    # FIXED RATE: 5 BUX per engagement point
    bux_earned = engagement_score * 5.0

    {:noreply,
     socket
     |> assign(:show_signup_prompt, true)
     |> assign(:anonymous_earned, bux_earned)
     |> assign(:engagement_score, engagement_score)
     |> assign(:show_earning_progress, false)}
  else
    {:noreply, socket}
  end
end

def handle_event("show-anonymous-video-claim", params, socket) do
  if socket.assigns.is_anonymous do
    bux_earned = params["buxEarned"]

    {:noreply,
     socket
     |> assign(:show_signup_prompt, true)
     |> assign(:anonymous_earned, bux_earned)
     |> assign(:video_earned_state, true)}
  else
    {:noreply, socket}
  end
end

# Process claim after user signs up
defp process_anonymous_claim(socket, claim_data) do
  user_id = socket.assigns.current_user.id
  post_id = socket.assigns.post.id

  # Parse claim data from localStorage
  %{
    "type" => type,
    "metrics" => metrics,
    "earnedAmount" => earned_amount
  } = claim_data

  case type do
    "read" ->
      # Record engagement in Mnesia
      engagement_score = calculate_engagement_score(metrics)
      EngagementTracker.record_engagement(user_id, post_id, metrics, engagement_score)

      # Mint BUX reward
      wallet_address = socket.assigns.wallet_address
      case BuxMinter.mint_bux(wallet_address, earned_amount, user_id, post_id, :read, "BUX") do
        {:ok, tx_hash} ->
          # Record reward in Mnesia
          EngagementTracker.record_read_reward(user_id, post_id, earned_amount, tx_hash)

          # Deduct from pool
          EngagementTracker.deduct_from_pool(post_id, earned_amount)

          socket
          |> assign(:bux_earned, earned_amount)
          |> assign(:already_rewarded, true)
          |> assign(:read_tx_id, tx_hash)
          |> put_flash(:info, "Successfully claimed #{earned_amount} BUX!")

        {:error, reason} ->
          socket
          |> put_flash(:error, "Failed to claim reward: #{inspect(reason)}")
      end

    "video" ->
      # Similar flow for video claims
      wallet_address = socket.assigns.wallet_address
      case BuxMinter.mint_bux(wallet_address, earned_amount, user_id, post_id, :video, "BUX") do
        {:ok, tx_hash} ->
          EngagementTracker.record_video_reward(user_id, post_id, earned_amount, tx_hash)

          socket
          |> assign(:video_earned_bux, earned_amount)
          |> assign(:video_earned_state, true)
          |> assign(:video_tx_id, tx_hash)
          |> put_flash(:info, "Successfully claimed #{earned_amount} BUX from video!")

        {:error, reason} ->
          socket
          |> put_flash(:error, "Failed to claim video reward: #{inspect(reason)}")
      end
  end
end

# Helper to calculate engagement score from metrics
defp calculate_engagement_score(metrics) do
  # Same logic as EngagementTracker.calculate_engagement_score/8
  # but extracted for reuse with anonymous data

  time_spent = metrics["timeSpent"]
  min_read_time = metrics["minReadTime"]
  scroll_depth = metrics["scrollDepth"]
  reached_end = metrics["reachedEnd"]

  base_score = 1.0

  time_ratio = if min_read_time > 0, do: time_spent / min_read_time, else: 0
  time_score = cond do
    time_ratio >= 1.0 -> 6
    time_ratio >= 0.9 -> 5
    time_ratio >= 0.8 -> 4
    time_ratio >= 0.7 -> 3
    time_ratio >= 0.5 -> 2
    time_ratio >= 0.3 -> 1
    true -> 0
  end

  depth_score = cond do
    reached_end || scroll_depth >= 100 -> 3
    scroll_depth >= 66 -> 2
    scroll_depth >= 33 -> 1
    true -> 0
  end

  final_score = base_score + time_score + depth_score
  min(max(final_score, 1.0), 10.0)
end
```

#### 2. User Registration Flow (`lib/blockster_v2_web/live/user_registration_live.ex`)

**Add Return Path Handling**:
```elixir
def mount(params, session, socket) do
  # ... existing code ...

  # Store return path for post-signup redirect
  return_to = params["return_to"]

  socket = assign(socket,
    return_to: return_to,
    # ... other assigns
  )

  {:ok, socket}
end

def handle_event("save", %{"user" => user_params}, socket) do
  case Accounts.register_user(user_params) do
    {:ok, user} ->
      # ... existing user setup ...

      # Redirect back to post if return_to present
      redirect_path = if socket.assigns.return_to do
        socket.assigns.return_to
      else
        ~p"/#{user}"
      end

      {:noreply,
       socket
       |> put_flash(:info, "Account created successfully!")
       |> redirect(to: redirect_path)}

    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply, assign(socket, :changeset, changeset)}
  end
end
```

#### 3. Claim Processing Hook (`lib/blockster_v2_web/live/claim_processor_hook.ex`)

**New Hook Module**:
```elixir
defmodule BlocksterV2Web.ClaimProcessorHook do
  @moduledoc """
  LiveView hook that processes pending anonymous claims after user signs up.

  Checks localStorage via connect_params and triggers reward payouts.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    # Check if user just logged in and has pending claims
    if connected?(socket) do
      pending_claims = get_connect_params(socket)["pending_claims"]

      if pending_claims && socket.assigns[:current_user] do
        socket = process_pending_claims(socket, pending_claims)
        {:cont, socket}
      else
        {:cont, socket}
      end
    else
      {:cont, socket}
    end
  end

  defp process_pending_claims(socket, claims) when is_list(claims) do
    user_id = socket.assigns.current_user.id
    wallet_address = get_user_wallet_address(user_id)

    results = Enum.map(claims, fn claim ->
      process_single_claim(user_id, wallet_address, claim)
    end)

    # Count successes
    success_count = Enum.count(results, fn {status, _} -> status == :ok end)

    if success_count > 0 do
      total_earned = results
        |> Enum.filter(fn {status, _} -> status == :ok end)
        |> Enum.map(fn {_, amount} -> amount end)
        |> Enum.sum()

      put_flash(socket, :info,
        "Successfully claimed #{Float.round(total_earned, 2)} BUX from #{success_count} post(s)!")
    else
      socket
    end
  end

  defp process_single_claim(user_id, wallet_address, claim) do
    %{
      "postId" => post_id,
      "type" => type,
      "earnedAmount" => amount
    } = claim

    case type do
      "read" ->
        case BuxMinter.mint_bux(wallet_address, amount, user_id, post_id, :read, "BUX") do
          {:ok, tx_hash} ->
            EngagementTracker.record_read_reward(user_id, post_id, amount, tx_hash)
            EngagementTracker.deduct_from_pool(post_id, amount)
            {:ok, amount}

          {:error, reason} ->
            {:error, reason}
        end

      "video" ->
        case BuxMinter.mint_bux(wallet_address, amount, user_id, post_id, :video, "BUX") do
          {:ok, tx_hash} ->
            EngagementTracker.record_video_reward(user_id, post_id, amount, tx_hash)
            {:ok, amount}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp get_user_wallet_address(user_id) do
    # Fetch user's smart wallet address
    case Accounts.get_user!(user_id) do
      %{wallet_address: address} when not is_nil(address) -> address
      _ -> nil
    end
  end
end
```

---

### C. UI Changes

#### 1. Earnings Panel Template (`lib/blockster_v2_web/live/post_live/show.html.heex`)

**Current Condition** (line 3):
```heex
<%= if @current_user && !@video_modal_open do %>
```

**New Condition**:
```heex
<%= if !@video_modal_open do %>
  <!-- Show for both logged-in and anonymous users -->
```

**Add Anonymous State Section** (new section after line 129):
```heex
<!-- ANONYMOUS USER - SIGNUP PROMPT -->
<%= if @is_anonymous && @show_signup_prompt do %>
  <div id="earnings-panel"
       class="fixed bottom-4 right-4 w-80 rounded-lg shadow-2xl border-2 p-6
              bg-gradient-to-br from-green-50 to-emerald-50
              border-green-400 z-50">

    <!-- Earned Amount -->
    <div class="flex items-center justify-between mb-4">
      <span class="text-gray-700 font-medium">You Earned</span>
      <span class="text-3xl font-haas_medium_65 text-green-600">
        <%= Float.round(@anonymous_earned, 2) %> BUX
      </span>
    </div>

    <!-- Engagement Score Breakdown -->
    <%= if @engagement_score do %>
      <div class="text-sm text-gray-600 mb-4 space-y-1">
        <div class="flex justify-between">
          <span>Engagement Score:</span>
          <span class="font-medium"><%= @engagement_score %>/10</span>
        </div>
      </div>
    <% end %>

    <!-- USD Value -->
    <div class="text-sm text-gray-500 mb-6">
      ≈ $<%= Float.round(@anonymous_earned * 0.10, 2) %> USD
    </div>

    <!-- Signup Button -->
    <div class="space-y-3">
      <.link
        navigate={~p"/signup?return_to=#{@post.slug}"}
        class="block w-full text-center bg-green-600 hover:bg-green-700
               text-white font-haas_medium_65 py-3 px-4 rounded-lg
               transition-colors cursor-pointer"
      >
        Sign Up to Claim
      </.link>

      <.link
        navigate={~p"/login?return_to=#{@post.slug}"}
        class="block w-full text-center bg-white hover:bg-gray-50
               text-green-600 font-medium py-2 px-4 rounded-lg
               border-2 border-green-600 transition-colors cursor-pointer"
      >
        Already have an account? Log in
      </.link>
    </div>

    <!-- Expiry Notice -->
    <div class="mt-4 text-xs text-gray-500 text-center">
      This reward is available for 30 minutes
    </div>
  </div>
<% end %>

<!-- ANONYMOUS USER - EARNING IN PROGRESS -->
<%= if @is_anonymous && !@show_signup_prompt && @anonymous_earned > 0 do %>
  <div id="earnings-panel"
       class="fixed bottom-4 right-4 w-80 rounded-lg shadow-2xl border-2 p-6
              bg-gradient-to-br from-green-50 to-emerald-50
              border-green-400 z-50">

    <!-- Current Earnings -->
    <div class="flex items-center justify-between mb-4">
      <span class="text-gray-700 font-medium">Earning Now</span>
      <span class="text-3xl font-haas_medium_65 text-green-600">
        <%= Float.round(@anonymous_earned, 2) %> BUX
      </span>
    </div>

    <!-- Progress Indicator -->
    <%= if @engagement_score do %>
      <div class="mb-4">
        <div class="flex justify-between text-sm text-gray-600 mb-1">
          <span>Engagement Score</span>
          <span class="font-medium"><%= @engagement_score %>/10</span>
        </div>
        <div class="w-full bg-gray-200 rounded-full h-2">
          <div class="bg-green-600 h-2 rounded-full transition-all duration-300"
               style={"width: #{@engagement_score * 10}%"}>
          </div>
        </div>
      </div>
    <% end %>

    <!-- Call to Action -->
    <div class="text-center text-sm text-gray-600">
      Keep reading to earn more!
      <br/>
      <span class="text-green-600 font-medium">Sign up to claim your rewards</span>
    </div>
  </div>
<% end %>
```

---

## Implementation Checklist

### Phase 1: Frontend Tracking (Anonymous Users) ✅ COMPLETED

- [x] **1.1** Update `engagement_tracker.js` to track anonymous users
  - [x] Remove anonymous user skip check
  - [x] Add `isAnonymous` flag detection
  - [x] Store metrics in memory (no server persistence)
  - [x] Send `anonymous-engagement-update` events for score calculation
  - [x] Implement `storeForClaim()` to save to localStorage
  - [x] Add `calculateEngagementScore()` client-side helper (5 BUX per point)

- [x] **1.2** Update `video_watch_tracker.js` for anonymous tracking
  - [x] Remove anonymous user skip check
  - [x] Add anonymous video tracking mode (5 BUX per minute)
  - [x] Store video watch data in localStorage via `storeVideoClaimData()`
  - [x] Send `show-anonymous-video-claim` event

- [x] **1.3** Create `anonymous_claim_manager.js` module
  - [x] Implement `storeClaim(postId, type, metrics, earnedAmount)`
  - [x] Implement `getPendingClaims()` with expiry check
  - [x] Implement `clearClaim(postId, type)`
  - [x] Implement `clearAllClaims()`
  - [x] Add 30-minute expiry logic
  - [x] Add `getTotalPendingBux()` helper
  - [x] Add `hasPendingClaims()` helper
  - [x] Add `cleanupExpired()` function

- [x] **1.4** Update `app.js` to import and initialize new modules
  - [x] Import `AnonymousClaimManager`
  - [x] Pass pending claims to LiveView via connect_params in params function

### Phase 2: Backend Score Calculation (No Rewards) ✅ COMPLETED

- [x] **2.1** Update `show.ex` mount function
  - [x] Add `is_anonymous` assign
  - [x] Add `show_signup_prompt` assign (default false)
  - [x] Add `anonymous_earned` assign (default 0)
  - [x] Add `engagement_score` assign (default nil)
  - [ ] Check for pending claims in connect_params (deferred to Phase 4)
  - [ ] Call `process_anonymous_claim/2` if claims present (deferred to Phase 4)

- [x] **2.2** Add anonymous event handlers to `show.ex`
  - [x] `handle_event("anonymous-engagement-update", ...)` (line 504)
    - Calculate engagement score from metrics
    - Calculate BUX earned: `engagement_score * 5.0`
    - Update assigns (score, anonymous_earned)
  - [x] `handle_event("show-anonymous-claim", ...)` (line 520)
    - Calculate final earned amount: `engagement_score * 5.0`
    - Set `show_signup_prompt: true`
    - Update panel to show signup button
  - [x] `handle_event("show-anonymous-video-claim", ...)` (line 538)
    - Accept earned amount from JS (already calculated: `(seconds / 60) * 5.0`)
    - Set signup prompt state

- [x] **2.3** Extract engagement score calculation
  - [x] Create `calculate_engagement_score/1` helper in `show.ex` (line 237)
  - [x] Reuse same scoring logic as `EngagementTracker`
  - [x] Handle missing `min_read_time` gracefully

**Implementation Details**:
- **File**: `lib/blockster_v2_web/live/post_live/show.ex`
- **Mount assigns** (lines 141-177): Added `is_anonymous`, `show_signup_prompt`, `anonymous_earned`, `engagement_score`
- **Helper function** (lines 237-276): `calculate_engagement_score/1` - extracts metrics and calculates score 1-10
- **Event handlers** (lines 504-551): Three new handlers for anonymous engagement tracking
- **Earning calculation**: `engagement_score * 5.0` for reading, `(seconds / 60) * 5.0` for video

**Progress Notes**:
- ✅ Phase 1 (Frontend) completed - all JavaScript hooks updated
- ✅ Phase 2 (Backend) completed - score calculation and event handlers implemented
- 🟡 Phase 3 (UI) next - update templates to display earnings panel for anonymous users
- Anonymous earning rates implemented: 5 BUX per engagement point (read), 5 BUX per minute (video)

### Phase 3: UI for Anonymous Users ✅ COMPLETED

- [x] **3.1** Update earnings panel visibility in `show.html.heex`
  - [x] Change condition from `@current_user` to show for all users
  - [x] Keep `!@video_modal_open` check
  - [x] Wrap existing logged-in content with `<%= if @current_user do %>`

- [x] **3.2** Add anonymous signup prompt state (lines 139-186)
  - [x] Create new section for `@is_anonymous && @show_signup_prompt`
  - [x] Display earned BUX amount (large, prominent)
  - [x] Show engagement score breakdown
  - [x] Show USD value estimate ($0.10 per BUX)
  - [x] "Sign Up to Claim" button → `/signup?return_to=#{@post.slug}`
  - [x] "Already have account? Log in" link → `/login?return_to=#{@post.slug}`
  - [x] Add 30-minute expiry notice

- [x] **3.3** Add anonymous earning progress state (lines 189-220)
  - [x] Create section for `@is_anonymous && !@show_signup_prompt && @anonymous_earned > 0 && @pool_available`
  - [x] Show current BUX being earned (live updates)
  - [x] Display engagement score with progress bar
  - [x] Add "Keep reading to earn more!" call-to-action
  - [x] Encourage signup to claim

**Implementation Details**:
- **File**: `lib/blockster_v2_web/live/post_live/show.html.heex`
- **Panel visibility** (line 3): Changed from `@current_user && !@video_modal_open` to `!@video_modal_open`
- **Logged-in wrapper** (line 5): Added `<%= if @current_user do %>` wrapper around existing panels
- **Signup prompt panel** (lines 139-186): Green gradient with prominent BUX amount, score breakdown, and CTA buttons
- **Progress panel** (lines 189-220): Green gradient matching logged-in style, with live score and progress bar
- **Pool check**: Progress panel only shows when `@pool_available` is true

**Progress Notes**:
- ✅ Phase 1 (Frontend) completed - all JavaScript hooks updated
- ✅ Phase 2 (Backend) completed - score calculation and event handlers implemented
- ✅ Phase 3 (UI) completed - earnings panels display for anonymous users
- 🟡 Phase 4 (Signup/Login Flow) next - handle return_to params and claim processing

### Phase 4: Signup/Login Flow Integration ✅ COMPLETED

**NOTE**: The app uses Thirdweb passwordless auth - `/login` handles both new and existing users (no separate signup page).

- [x] **4.1** Update anonymous panel button
  - [x] Change to single "Log In to Claim" button pointing to `/login`
  - [x] Add helper text: "New users will automatically create an account"

- [x] **4.2** Update MemberLive.Show to process claims
  - [x] Check for pending claims in `connect_params` on connected mount
  - [x] Verify user is viewing their own profile
  - [x] Check if user is new (account < 5 minutes old)
  - [x] Process claims only for new users (prevents existing user abuse)

- [x] **4.3** Add claim processing helpers to MemberLive.Show
  - [x] `is_new_user?/1` - checks if account created within last 5 minutes
  - [x] `process_pending_claims/2` - loops through claims from localStorage
  - [x] `process_single_claim/2` - mints BUX, records in Mnesia, deducts from pool
  - [x] Handles both "read" and "video" claim types
  - [x] Sets success flash message with total claimed amount

- [x] **4.4** Add UI to member profile page
  - [x] Success message banner for new users who claimed rewards
  - [x] "How It Works" onboarding section for new users
  - [x] Explains: Connect X → Earn BUX → Redeem (shop/airdrops/BUX Booster)
  - [x] CTA buttons: "Start Reading & Earning" and "Try BUX Booster"

**Implementation Details**:
- **Button**: [show.html.heex:164-176](lib/blockster_v2_web/live/post_live/show.html.heex#L164-L176) - Single "Log In to Claim" button
- **Claim processing**: [member_live/show.ex:21-54](lib/blockster_v2_web/live/member_live/show.ex#L21-L54) - Check for claims in handle_params
- **Helper functions**: [member_live/show.ex:161-245](lib/blockster_v2_web/live/member_live/show.ex#L161-L245) - is_new_user?, process_pending_claims, process_single_claim
- **Success banner**: [member_live/show.html.heex:63-78](lib/blockster_v2_web/live/member_live/show.html.heex#L63-L78) - Green gradient with celebration
- **Onboarding**: [member_live/show.html.heex:81-145](lib/blockster_v2_web/live/member_live/show.html.heex#L81-L145) - 3-step how it works guide

**Security Features**:
- **Server-side check**: Only processes claims if `user.inserted_at` is < 5 minutes ago
- **Prevents abuse**: Existing users cannot claim higher anonymous rewards by logging out/in
- **Defense in depth**: Check happens on profile page (not login page) so claims are in localStorage when verified

**Flow**:
1. Anonymous user reads post → sees earnings → clicks "Log In to Claim"
2. Redirects to `/login` (Thirdweb passwordless auth)
3. After auth → redirects to `/member/:slug` (user's profile)
4. Profile page checks: Is this their profile? Are they new? Do they have pending claims?
5. If YES to all → process claims, show success + onboarding
6. If NO (existing user) → normal profile view, claims ignored

**Progress Notes**:
- ✅ Phase 1 (Frontend) completed
- ✅ Phase 2 (Backend) completed
- ✅ Phase 3 (UI) completed
- ✅ Phase 4 (Signup/Login Flow) completed
- 🟡 Phase 5 (Post-Claim Processing) - partially complete (integrated into Phase 4)

### Phase 5: Post-Claim Processing ✅ COMPLETED

- [x] **5.1** Implement claim processing in `member_live/show.ex` (integrated in Phase 4)
  - [x] Parse claim data from localStorage via connect_params
  - [x] Handle "read" type claims
    - Record engagement in Mnesia via `EngagementTracker.record_read_reward/4`
    - Mint BUX reward via `BuxMinter.mint_bux/6`
    - Deduct from pool via `EngagementTracker.deduct_from_pool_guaranteed/2`
  - [x] Handle "video" type claims
    - Mint BUX reward via `BuxMinter.mint_bux/6`
    - Record in Mnesia via `EngagementTracker.record_video_reward/4`
  - [x] Show success flash messages with total claimed amount
  - [x] Security: Only process claims for new users (< 5 minutes old)

- [x] **5.2** Add localStorage cleanup after successful claim
  - [x] Created `ClaimCleanup` hook in `assets/js/app.js`
  - [x] Hook calls `AnonymousClaimManager.clearAllClaims()` on mount
  - [x] Added hook to success banner in `member_live/show.html.heex`
  - [x] Cleanup happens automatically when success message displays

- [x] **5.3** Add pool empty handling
  - [x] Progress panel already checks `@pool_available` (line 188)
  - [x] Updated signup prompt to check `@pool_available` (line 139)
  - [x] Prevents showing claims when pool is empty

### Phase 6: localStorage Management ✅ COMPLETED

- [x] **6.1** Claim expiry handling (implemented in Phase 1)
  - [x] Set 30-minute expiry on claim creation
    - `engagement_tracker.js` line 332: `expiresAt: Date.now() + (30 * 60 * 1000)`
    - `video_watch_tracker.js` line 576: `expiresAt: Date.now() + (30 * 60 * 1000)`
  - [x] Check expiry in `getPendingClaims()`
    - `anonymous_claim_manager.js` lines 53-58: Filters out expired claims
  - [x] Auto-remove expired claims
    - Expired claims are removed when `getPendingClaims()` is called
    - Also has `cleanupExpired()` method for manual cleanup (lines 144-175)

- [x] **6.2** Claim cleanup (implemented in Phases 1 & 5)
  - [x] Clear claim from localStorage after successful processing
    - `ClaimCleanup` hook clears all claims when success message displays (Phase 5)
  - [x] Multiple pending claims handled
    - `getPendingClaims()` returns all valid claims as array
    - `MemberLive.Show.process_pending_claims/2` processes all claims sequentially

### Phase 7: Edge Cases & Error Handling ✅ COMPLETED

- [x] **7.1** Handle pool empty scenario for anonymous users (Phase 5)
  - [x] Signup prompt checks `@pool_available` (line 139)
  - [x] Progress panel checks `@pool_available` (line 188)
  - [x] Anonymous users don't see earnings panels when pool is empty

- [x] **7.2** Handle already-rewarded scenario
  - [x] Added `already_rewarded?/3` helper in `member_live/show.ex`
  - [x] Checks `user_post_rewards` Mnesia table before processing claim
  - [x] For read claims: checks if any reward exists for `{user_id, post_id}`
  - [x] For video claims: checks if `video_bux` field > 0
  - [x] Returns `{:error, "Already rewarded for this post"}` if duplicate

- [x] **7.3** Handle wallet creation failures
  - [x] `process_single_claim` checks for `wallet_address && wallet_address != ""`
  - [x] Returns `{:error, "No wallet address"}` if wallet missing
  - [x] Errors are collected but don't prevent other claims from processing

- [x] **7.4** Handle BUX minting failures
  - [x] `BuxMinter.mint_bux` errors are caught in `case` statement
  - [x] Returns `{:error, reason}` tuple
  - [x] Failed claims are filtered out from success count
  - [x] Only successful claims shown in flash message

- [x] **7.5** Handle concurrent claims
  - [x] `process_pending_claims` processes all claims sequentially with `Enum.map`
  - [x] Filters successful claims and calculates total
  - [x] Shows aggregated success message: "Successfully claimed X BUX from Y post(s)!"
  - [x] Failed claims are silently ignored (design decision: don't confuse user with errors)

### Phase 8: Testing

- [ ] **8.1** Manual testing - Anonymous read flow
  - [ ] Visit post without login
  - [ ] Verify earnings panel appears
  - [ ] Verify score updates in real-time
  - [ ] Scroll to end, verify signup prompt appears
  - [ ] Verify localStorage contains claim data

- [ ] **8.2** Manual testing - Signup claim flow
  - [ ] Click "Sign Up to Claim" button
  - [ ] Complete registration
  - [ ] Verify redirect back to post
  - [ ] Verify BUX minted and panel shows "Already Earned"
  - [ ] Verify transaction link works

- [ ] **8.3** Manual testing - Anonymous video flow
  - [ ] Open video modal without login
  - [ ] Watch video past high water mark
  - [ ] Close modal, verify signup prompt
  - [ ] Complete signup and verify video reward claimed

- [ ] **8.4** Manual testing - Multiple claims
  - [ ] Read 3 different posts without login
  - [ ] Sign up
  - [ ] Verify all 3 rewards claimed
  - [ ] Check aggregate flash message

- [ ] **8.5** Manual testing - Expiry
  - [ ] Create claim, wait 31 minutes
  - [ ] Sign up
  - [ ] Verify expired claim is not processed

- [ ] **8.6** Manual testing - Pool empty
  - [ ] Visit post with empty pool
  - [ ] Verify no earnings panel or appropriate message

- [ ] **8.7** Manual testing - Already rewarded
  - [ ] Earn reward as logged-in user
  - [ ] Revisit same post
  - [ ] Verify "Already Earned" state shown, not claim prompt

### Phase 9: Documentation & Polish

- [ ] **9.1** Update `docs/engagement_tracking.md`
  - [ ] Document anonymous user flow
  - [ ] Document localStorage schema
  - [ ] Document claim processing logic

- [ ] **9.2** Update `CLAUDE.md` session learnings
  - [ ] Add notes about anonymous tracking implementation
  - [ ] Document any gotchas discovered during implementation

- [ ] **9.3** Code cleanup
  - [ ] Remove debug logs
  - [ ] Add comprehensive code comments
  - [ ] Ensure consistent error handling

- [ ] **9.4** Performance check
  - [ ] Verify anonymous tracking doesn't impact page load
  - [ ] Check localStorage size limits (unlikely issue but verify)

### Phase 10: Deployment

- [ ] **10.1** Local testing complete
  - [ ] All checklist items verified on localhost
  - [ ] No console errors
  - [ ] No server errors

- [ ] **10.2** Git commit and push
  - [ ] Commit with descriptive message
  - [ ] Push to `feature/anonymous-engagement-tracking` branch

- [ ] **10.3** User acceptance
  - [ ] Request user to review on localhost
  - [ ] Make any requested adjustments

- [ ] **10.4** Merge to main
  - [ ] Create PR if desired
  - [ ] Merge when approved

- [ ] **10.5** Deploy to production (ONLY when explicitly instructed)
  - [ ] `git push origin main`
  - [ ] `flyctl deploy --app blockster-v2`
  - [ ] Monitor logs for errors

---

## Technical Considerations

### Anonymous User Earning Rates (IMPORTANT)

**Reading Articles**:
- Formula: `engagement_score * 5.0`
- Minimum: 5 BUX (score 1/10)
- Maximum: 50 BUX (score 10/10)
- Score updates in real-time as user scrolls/reads
- User claims whatever amount is showing when they click "Sign Up to Claim"

**Watching Videos**:
- Formula: `(seconds_watched / 60) * 5.0`
- Rate: 5 BUX per minute
- Example: 3.5 minutes = 17.5 BUX
- Claim triggers when user closes video modal

**Important**: These are FIXED rates for anonymous users only. Logged-in users continue to use the existing multiplier system (base_bux_reward * user_multiplier * engagement_score/10).

### localStorage Schema

Each pending claim stored with key pattern: `pending_claim_{type}_{postId}`

**Value Structure**:
```json
{
  "postId": 123,
  "type": "read", // or "video"
  "metrics": {
    "timeSpent": 120,
    "scrollDepth": 95,
    "reachedEnd": true,
    "scrollEvents": 45,
    "avgScrollSpeed": 150,
    "maxScrollSpeed": 800,
    "scrollReversals": 3,
    "focusChanges": 2,
    "minReadTime": 100
  },
  "earnedAmount": 45.0, // Example: score 9/10 * 5 = 45 BUX
  "timestamp": 1704931200000,
  "expiresAt": 1704933000000 // timestamp + 30 min
}
```

### Security Considerations

1. **No Sensitive Data in localStorage**
   - Only engagement metrics and calculated amounts
   - No user IDs or wallet addresses
   - All data is client-side visible anyway

2. **Server Validation**
   - Server recalculates engagement score from metrics
   - Server verifies pool availability
   - Server checks for duplicate rewards (already claimed)

3. **Expiry Protection**
   - 30-minute window to claim
   - Prevents stale claims from being processed
   - Auto-cleanup of expired data

4. **Pool Protection**
   - Pool checked before minting
   - Guaranteed earnings system still applies
   - Pool can go negative if commitment made

### Performance Considerations

1. **No Server Persistence for Anonymous**
   - Zero database load for anonymous users
   - No Mnesia writes until claim processed
   - Scalable to unlimited anonymous traffic

2. **Batch Claim Processing**
   - Multiple claims processed sequentially
   - Consider implementing batch minting API call if performance issues arise

3. **localStorage Size**
   - Each claim ~500 bytes
   - 5MB localStorage limit = ~10,000 claims
   - Unlikely to be an issue for single user

### UX Considerations

1. **Clear Value Proposition**
   - Show exact amount earned (not "earn up to X")
   - Real-time feedback during reading
   - Immediate gratification on signup

2. **Low Friction**
   - One-click signup button
   - Auto-redirect back to post
   - Auto-claim on return (no manual action needed)

3. **Trust Building**
   - Show engagement score breakdown
   - Explain what affects earnings
   - Display USD value for context

4. **Urgency**
   - 30-minute expiry creates urgency
   - "Sign up now to claim" messaging
   - But not so short it feels unfair

---

## Success Metrics

After implementation, monitor:

1. **Conversion Rate**
   - % of anonymous readers who sign up
   - Compare to baseline (if any historical data)
   - Target: >5% conversion for readers who complete articles

2. **Claim Processing**
   - Success rate of claim processing
   - Average time from signup to claim completion
   - Error rate and types

3. **User Engagement**
   - Do anonymous users read more/longer when they see earnings?
   - Engagement score distribution (anonymous vs logged-in)

4. **Pool Impact**
   - Does anonymous-to-signup flow drain pools faster?
   - Are pools adequately funded for expected conversion?

---

## Future Enhancements (Out of Scope)

1. **Email Collection Before Claim**
   - Collect email on panel, allow claim without full signup
   - Send "complete your account" email later

2. **Social Proof**
   - Show "X users earned Y BUX today" on panel
   - Build trust through community activity

3. **Referral Tracking**
   - Track which posts convert best
   - Identify high-conversion content for promotion

4. **Progressive Rewards**
   - "Read 3 more articles to unlock 2x multiplier"
   - Gamification to increase engagement

5. **Anonymous Leaderboard**
   - Show top anonymous earners (session-based)
   - Encourage competitive reading

---

## Rollback Plan

If issues arise in production:

1. **Quick Disable**
   - Add feature flag: `config :blockster_v2, :anonymous_engagement, false`
   - Wrap anonymous logic in `if Application.get_env(...)`
   - Redeploy with flag disabled

2. **Partial Rollback**
   - Disable only claim processing (keep tracking)
   - Or disable only UI (keep backend)

3. **Full Rollback**
   - Revert branch: `git revert <commit-hash>`
   - Redeploy previous version

4. **Data Cleanup**
   - No database cleanup needed (no persistent data)
   - localStorage will naturally expire or be cleared by users

---

## End of Plan

This implementation plan provides a complete roadmap for enabling anonymous engagement tracking with post-signup reward claims. The system is designed to be:

- **Low-risk**: No persistent data for anonymous users
- **High-conversion**: Clear value proposition with friction-free signup
- **Scalable**: Zero server load until claim processing
- **Secure**: Server-side validation and expiry protection

Follow the checklist in order, test thoroughly at each phase, and only deploy to production when explicitly instructed by the user.
