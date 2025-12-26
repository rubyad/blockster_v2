# BUX Booster - Coin Flip Game

A provably fair coin flip gambling game where users can wager their tokens (BUX, hub tokens, or ROGUE) to multiply their holdings.

## Overview

BUX Booster offers two game modes with different risk/reward profiles:
- **Win One Mode**: Easier - player only needs to guess one flip correctly out of N flips
- **Win All Mode**: Harder - player must guess all N flips correctly for higher payouts

## File Locations

- **LiveView**: `lib/blockster_v2_web/live/bux_booster_live.ex`
- **JS Hook**: `assets/js/coin_flip.js`
- **CSS**: Inline styles in LiveView + `assets/css/app.css` (casino chip styles)
- **Route**: `/play` (defined in `router.ex`)

---

## Game Modes & Difficulty Levels

### Difficulty Options

```elixir
@difficulty_options [
  # Win One Mode (negative levels) - need only 1 correct flip
  %{level: -4, predictions: 5, multiplier: 1.03, label: "1.03x", mode: :win_one},
  %{level: -3, predictions: 4, multiplier: 1.06, label: "1.06x", mode: :win_one},
  %{level: -2, predictions: 3, multiplier: 1.14, label: "1.14x", mode: :win_one},
  %{level: -1, predictions: 2, multiplier: 1.33, label: "1.33x", mode: :win_one},

  # Win All Mode (positive levels) - must get all flips correct
  %{level: 1, predictions: 1, multiplier: 2, label: "2x", mode: :win_all},
  %{level: 2, predictions: 2, multiplier: 4, label: "4x", mode: :win_all},
  %{level: 3, predictions: 3, multiplier: 8, label: "8x", mode: :win_all},
  %{level: 4, predictions: 4, multiplier: 16, label: "16x", mode: :win_all},
  %{level: 5, predictions: 5, multiplier: 32, label: "32x", mode: :win_all}
]
```

### Fair Odds Calculation

**Win One Mode**: `multiplier = 1 / (1 - 0.5^n)` where n = number of flips
- 5 flips: 1 / (1 - 0.03125) = 1.03x
- 4 flips: 1 / (1 - 0.0625) = 1.06x
- 3 flips: 1 / (1 - 0.125) = 1.14x
- 2 flips: 1 / (1 - 0.25) = 1.33x

**Win All Mode**: `multiplier = 2^n` where n = number of flips
- 1 flip: 2x (50% win chance)
- 2 flips: 4x (25% win chance)
- 3 flips: 8x (12.5% win chance)
- 4 flips: 16x (6.25% win chance)
- 5 flips: 32x (3.125% win chance)

**Note**: These are true odds with zero house edge.

---

## Game States

The game uses a state machine with the following states:

| State | Description |
|-------|-------------|
| `:idle` | Initial state, player selects predictions and bet amount |
| `:flipping` | Coin flip animation playing (3 seconds per flip) |
| `:showing_result` | Showing flip result for 1 second |
| `:result` | Final result displayed with win/loss |

### State Transitions

```
:idle -> :flipping (on "start_game")
:flipping -> :showing_result (on "flip_complete" from JS hook)
:showing_result -> :flipping (next flip) OR :result (game over)
:result -> :idle (on "reset_game")
```

---

## Socket Assigns

| Assign | Type | Description |
|--------|------|-------------|
| `current_user` | User | Logged in user |
| `balances` | Map | Token balances from EngagementTracker |
| `tokens` | List | Available tokens (ROGUE first, then by balance) |
| `token_logos` | Map | Token name -> logo URL from HubLogoCache |
| `selected_token` | String | Currently selected token (default: "BUX") |
| `selected_difficulty` | Integer | Difficulty level (-4 to 5) |
| `bet_amount` | Integer | Wager amount |
| `current_bet` | Integer | Tracks doubling bet in win_all mode |
| `predictions` | List | User's predictions (`:heads` or `:tails`) |
| `results` | List | Actual flip results |
| `game_state` | Atom | Current state (`:idle`, `:flipping`, `:showing_result`, `:result`) |
| `current_flip` | Integer | Current flip number (1-indexed) |
| `flip_id` | Integer | Unique ID for JS hook remounting |
| `won` | Boolean | Whether player won |
| `payout` | Number | Amount won |
| `confetti_pieces` | List | Confetti animation data |
| `recent_games` | List | Last 10 games |
| `user_stats` | Map | Aggregated stats for selected token |

---

## Event Handlers

### User Input Events

| Event | Params | Description |
|-------|--------|-------------|
| `select_token` | `%{"token" => token}` | Switch selected token |
| `toggle_token_dropdown` | - | Show/hide token dropdown |
| `hide_token_dropdown` | - | Hide token dropdown |
| `select_difficulty` | `%{"level" => level}` | Change difficulty level |
| `toggle_prediction` | `%{"index" => i}` | Cycle prediction: nil -> heads -> tails -> heads |
| `update_bet_amount` | `%{"value" => val}` | Update bet from input |
| `set_max_bet` | - | Set bet to max balance |
| `halve_bet` | - | Divide bet by 2 |
| `double_bet` | - | Double bet (capped at balance) |
| `start_game` | - | Start the game |
| `flip_complete` | - | Called by JS when animation ends |
| `reset_game` | - | Reset to idle state |

### Internal Messages

| Message | Description |
|---------|-------------|
| `:flip_complete` | Sent after JS hook notifies flip animation complete |
| `:after_result_shown` | Sent 1 second after showing flip result |
| `:next_flip` | Proceed to next flip |
| `:show_final_result` | Display final win/loss result |

---

## Game Flow

### 1. Initialization (mount)

```elixir
def mount(_params, _session, socket) do
  # Redirect if not logged in
  # Load balances from EngagementTracker
  # Load token logos from HubLogoCache
  # Sort tokens: ROGUE first, then by balance descending
  # Initialize all assigns
end
```

### 2. Placing Bet (start_game)

```elixir
def handle_event("start_game", _params, socket) do
  # Validate all predictions made
  # Validate bet_amount > 0 and <= balance
  # Generate ALL results upfront (prevents manipulation)
  # Set game_state to :flipping, current_flip to 1
end
```

### 3. Flip Animation (CoinFlip JS Hook)

The JavaScript hook in `assets/js/coin_flip.js` handles animation timing:

```javascript
export const CoinFlip = {
  mounted() {
    this.currentFlipId = this.el.id;
    this.flipCompleted = false;
    this.startTimer();
  },

  updated() {
    // Remount if flip_id changed (new flip)
    if (this.el.id !== this.currentFlipId) {
      this.currentFlipId = this.el.id;
      this.flipCompleted = false;
      this.startTimer();
    }
  },

  startTimer() {
    // 3 second animation
    setTimeout(() => {
      if (!this.flipCompleted && this.el.id === this.currentFlipId) {
        this.flipCompleted = true;
        this.pushEvent('flip_complete', {});
      }
    }, 3000);
  }
};
```

### 4. Result Logic (after_result_shown)

```elixir
def handle_info(:after_result_shown, socket) do
  case mode do
    :win_one ->
      if correct do
        # Won immediately - show final result
        send(self(), :show_final_result)
      else
        if current_flip >= predictions_needed do
          # Lost all flips
          send(self(), :show_final_result)
        else
          # More flips to go
          send(self(), :next_flip)
        end
      end

    :win_all ->
      if not correct do
        # Lost immediately
        send(self(), :show_final_result)
      else
        if current_flip >= predictions_needed do
          # Won all flips
          send(self(), :show_final_result)
        else
          # Continue to next flip
          send(self(), :next_flip)
        end
      end
  end
end
```

### 5. Final Result (show_final_result)

```elixir
def handle_info(:show_final_result, socket) do
  # Determine win based on mode
  # Win One: any prediction matches result
  # Win All: all predictions match results

  if won do
    payout = bet_amount * multiplier
    save_game_result(socket, true, payout)
    confetti_pieces = generate_confetti_data(100)
    # Show win celebration
  else
    save_game_result(socket, false)
    # Show loss
  end
end
```

---

## Mnesia Persistence

### Tables

**bux_booster_games** - Individual game records
```
{:bux_booster_games, game_id, user_id, token_type, bet_amount, difficulty,
 multiplier, predictions, results, won, payout, timestamp}
```

**bux_booster_user_stats** - Aggregated user statistics per token
```
{:bux_booster_user_stats, {user_id, token_type}, user_id, token_type,
 total_games, total_wins, total_losses, total_wagered, total_won, total_lost,
 biggest_win, biggest_loss, current_streak, best_streak, worst_streak, updated_at}
```

### Stats Tracking

- **total_games**: Increment on each game
- **total_wins/losses**: Track win/loss count
- **total_wagered**: Sum of all bets
- **total_won/lost**: Sum of payouts and losses
- **biggest_win/loss**: Max single win/loss
- **current_streak**: Positive = winning streak, negative = losing streak
- **best/worst_streak**: Historical best/worst streaks

---

## UI Components

### Difficulty Tabs

9 tabs displayed horizontally at top of game card:
- Left 4 tabs: Win One mode (1.03x, 1.06x, 1.14x, 1.33x)
- Right 5 tabs: Win All mode (2x, 4x, 8x, 16x, 32x)

### Bet Controls

- Number input with ½ and 2× buttons inside
- Token dropdown (ROGUE first, then sorted by balance)
- MAX button to set max bet
- Balance display below

### Prediction Coins

Casino chip style buttons that cycle through:
1. Gray (unselected) - shows number
2. Orange/Gold heads chip with 🚀 emoji
3. Gray tails chip with 💩 emoji

### Coin Flip Animation

3D CSS flip animation lasting 3 seconds:
- `animate-flip-heads`: Ends at 1800deg (5 rotations, shows heads)
- `animate-flip-tails`: Ends at 1980deg (5 rotations + 180deg, shows tails)

```css
@keyframes flip-heads {
  0% { transform: rotateY(0deg); }
  100% { transform: rotateY(1800deg); }
}

@keyframes flip-tails {
  0% { transform: rotateY(0deg); }
  100% { transform: rotateY(1980deg); }
}
```

### Result Display

Top row shows prediction coins with:
- Result coins below each prediction
- Green ring (3px) if matched
- Red ring (3px) if didn't match
- "✓ Correct!" or "✗ Wrong!" text

### Win Celebration

- Scale-in animation with shake effect
- 🎉 emojis bouncing on each side of "YOU WON!" text
- Payout amount displayed
- Emoji confetti burst animation

---

## Confetti Animation

### Emoji Set

```elixir
@confetti_emojis ["❤️", "🧡", "💛", "💚", "💙", "💜", "🩷", "⭐", "🌟", "✨",
                  "⚡", "🌈", "🍀", "💎", "🎉", "🎊", "💫", "🔥", "💖", "💝"]
```

### Confetti Data Generation

```elixir
defp generate_confetti_data(count) do
  Enum.map(1..count, fn i ->
    %{
      id: i,
      x_start: 40 + :rand.uniform(20),      # 40-60% from left
      x_end: :rand.uniform(100),             # Random end position
      x_drift: :rand.uniform(60) - 30,       # -30 to +30 vw horizontal drift
      rotation: :rand.uniform(720) - 360,    # -360 to +360 deg rotation
      delay: rem(i * 23, 400),               # 0-400ms staggered delay
      duration: 4000 + :rand.uniform(2000),  # 4-6 second duration
      emoji: Enum.at(@confetti_emojis, rem(i + :rand.uniform(20), length(@confetti_emojis)))
    }
  end)
end
```

### Confetti CSS Animation

```css
@keyframes confetti-burst {
  0% {
    opacity: 1;
    transform: translateY(0) translateX(0) rotate(0deg) scale(0.5);
  }
  15% {
    /* Peak of burst - spread out during upward motion */
    opacity: 1;
    transform: translateY(-50vh) translateX(var(--x-drift))
               rotate(calc(var(--rotation) * 0.4)) scale(1.2);
  }
  100% {
    /* Fall straight down - stay solid */
    opacity: 1;
    transform: translateY(60vh) translateX(var(--x-drift))
               rotate(var(--rotation)) scale(0.8);
  }
}
```

Key characteristics:
- Bursts upward 50vh while spreading horizontally
- Stays solid (opacity: 1) throughout
- Falls slowly like snowflakes
- Full screen coverage via fixed positioning

---

## Token Integration

### Balance Loading

Balances are loaded from `EngagementTracker` Mnesia tables on mount:

```elixir
balances = EngagementTracker.get_user_token_balances(current_user.id)
```

### Token Logos

Token logos come from `HubLogoCache` ETS table:

```elixir
token_logos = HubLogoCache.get_all_logos()
# Returns: %{"BUX" => "https://...", "moonBUX" => "https://...", ...}
```

Default tokens always included:
- BUX: Blockster icon
- ROGUE: Rogue chain logo

### Token Sorting

Tokens are sorted with ROGUE always first, then by user's balance descending:

```elixir
other_tokens =
  token_logos
  |> Map.keys()
  |> Enum.reject(fn token -> token == "ROGUE" end)
  |> Enum.sort_by(fn token -> Map.get(balances, token, 0) end, :desc)

tokens = ["ROGUE" | other_tokens]
```

---

## Future Implementation: On-Chain Integration

### TODO: Token Transfer

Currently game results only update Mnesia balances. Future implementation will:

1. **Lock tokens on bet placement**
   - Transfer bet amount to game escrow contract
   - Or use approve/allowance pattern

2. **Settle on-chain after result**
   - Winner receives payout from escrow
   - Or house wallet sends winnings

3. **Transaction confirmation**
   - Wait for blockchain confirmation
   - Show pending state during transaction

### TODO: Provably Fair Mechanics

Current implementation uses `Enum.random([:heads, :tails])` which is not verifiable.

Future provably fair implementation:

1. **Commit-Reveal Pattern**
   - Server generates secret seed
   - Hash of seed sent to client BEFORE bet
   - After bet, reveal seed
   - Client can verify result = hash(seed + bet_id)

2. **VRF (Verifiable Random Function)**
   - Use Chainlink VRF or similar
   - On-chain randomness that's verifiable
   - Request randomness -> wait for callback -> resolve game

3. **Client Seed Contribution**
   - Allow player to provide their own seed
   - Final result = hash(server_seed + client_seed + nonce)
   - Neither party can predict outcome alone

### Recommended Approach: Commit-Reveal with Client Seed

We use a commit-reveal pattern where both server and client contribute to the final randomness. This ensures neither party can predict or manipulate the outcome.

---

### Overview

The provably fair system uses cryptographic commitments to ensure:
1. **Server can't cheat**: Server commits to seed BEFORE seeing player's bet
2. **Player can verify**: All inputs are revealed after game for verification
3. **Combined randomness**: Both server seed + client seed determine outcome

### Cryptographic Flow

```
BEFORE BET (server commits first):
┌─────────────────────────────────────────────────────────────┐
│ 1. Server generates: server_seed = secure_random_hex(32)    │
│ 2. Server computes:  commitment = SHA256(server_seed)       │
│ 3. Server sends:     commitment to client (shown in UI)     │
│    ⚠️ Server is now LOCKED IN - cannot change server_seed   │
└─────────────────────────────────────────────────────────────┘

PLAYER PLACES BET (after seeing commitment):
┌─────────────────────────────────────────────────────────────┐
│ 4. Player chooses:   predictions, bet_amount, token, etc.   │
│ 5. Client seed derived from PLAYER CHOICES ONLY:            │
│    client_seed = SHA256(user_id:bet_amount:token:           │
│                         difficulty:predictions)              │
│ 6. Server stores:    game record with all data              │
└─────────────────────────────────────────────────────────────┘

RESULT CALCULATION:
┌─────────────────────────────────────────────────────────────┐
│ 7. Combined seed = SHA256(server_seed:client_seed:nonce)    │
│ 8. For each flip i:                                         │
│    result[i] = combined_seed[i] < 128 ? :heads : :tails     │
│ 9. Server reveals: server_seed (player can now verify)      │
└─────────────────────────────────────────────────────────────┘

VERIFICATION (anytime after game):
┌─────────────────────────────────────────────────────────────┐
│ 10. Player verifies: SHA256(server_seed) == commitment      │
│ 11. Player recomputes: client_seed from their bet choices   │
│ 12. Player recomputes: results from combined seeds          │
│ 13. If matches: game was provably fair ✓                    │
└─────────────────────────────────────────────────────────────┘

WHY THIS IS SECURE:
- Server commits BEFORE seeing player's predictions
- Client seed uses ONLY player-controlled values (no timestamp)
- Nonce ensures unique results even for identical bets
- Neither party can predict or manipulate the outcome alone
```

### Why Deterministic Client Seed?

Using a deterministic client seed derived from bet details is **superior** to random generation:

1. **Fully Verifiable**: Anyone can independently recreate the client seed from the bet parameters
2. **No Trust in Client RNG**: Eliminates questions about whether client's "random" seed was manipulated
3. **Transparent**: The seed generation formula is public and reproducible
4. **No Hidden State**: All inputs to the game result are visible and derivable
5. **No Server-Controlled Values**: Only player choices influence the client seed

The client seed formula:
```
client_seed = SHA256(user_id + ":" + bet_amount + ":" + token + ":" +
                     difficulty + ":" + predictions_string)
```

**Why no timestamp?** The timestamp is controlled by the server, which could introduce doubt.
Since the commit-reveal pattern already ensures the server commits *before* seeing player choices,
and the nonce ensures each game is unique, the timestamp adds no security value.

Example:
```
Inputs:
  user_id = 42
  bet_amount = 100
  token = "BUX"
  difficulty = 2
  predictions = [:heads, :tails]

String: "42:100:BUX:2:heads,tails"
client_seed = SHA256("42:100:BUX:2:heads,tails")
            = "a3b8c9d2e4f5..." (64 hex chars)
```

**Why is this secure without timestamp?**
- The `nonce` (game counter) ensures each game produces different results
- The server commits to `server_seed` BEFORE seeing player's predictions
- Combined seed = `SHA256(server_seed:client_seed:nonce)` - all three change per game

### Data Model Changes

#### New Fields in bux_booster_games Mnesia Table

```elixir
# Current schema:
{:bux_booster_games, game_id, user_id, token_type, bet_amount, difficulty,
 multiplier, predictions, results, won, payout, timestamp}

# New schema with provably fair fields:
{:bux_booster_games, game_id, user_id, token_type, bet_amount, difficulty,
 multiplier, predictions, results, won, payout, timestamp,
 server_seed,       # Hex string, revealed after game
 server_seed_hash,  # SHA256 hash, shown before bet (commitment)
 nonce}             # Integer, game counter for this user

# Note: client_seed is NOT stored - it's derived from existing fields:
# SHA256(user_id:bet_amount:token_type:difficulty:predictions)
# All these values are already in the game record!
```

#### New Socket Assigns

```elixir
# Add to mount/3:
|> assign(server_seed: nil)           # Current game's server seed
|> assign(server_seed_hash: nil)      # Commitment shown to player
|> assign(nonce: 0)                   # Game counter
|> assign(show_fairness_modal: false) # Modal visibility
|> assign(fairness_game: nil)         # Game data for modal

# Note: client_seed is computed on-demand from bet details, not stored
```

### Implementation Steps

#### Step 1: Seed Generation Module

Create `lib/blockster_v2/provably_fair.ex`:

```elixir
defmodule BlocksterV2.ProvablyFair do
  @moduledoc """
  Provably fair random number generation using commit-reveal pattern.

  The client seed is derived DETERMINISTICALLY from bet details, making
  verification fully transparent - anyone can recompute all seeds.
  """

  @doc """
  Generate a new server seed (32 bytes hex = 64 characters).
  """
  def generate_server_seed do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  @doc """
  Generate commitment (SHA256 hash of server seed).
  """
  def generate_commitment(server_seed) do
    :crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower)
  end

  @doc """
  Verify a commitment matches a server seed.
  """
  def verify_commitment(server_seed, commitment) do
    generate_commitment(server_seed) == String.downcase(commitment)
  end

  @doc """
  Generate client seed DETERMINISTICALLY from bet details.

  This is the key improvement over random client seeds:
  - Fully verifiable by anyone
  - No trust required in client's RNG
  - All inputs are visible in the game record
  - No server-controlled values (like timestamp)

  Formula: SHA256(user_id:bet_amount:token:difficulty:predictions)
  """
  def generate_client_seed(user_id, bet_amount, token, difficulty, predictions) do
    predictions_str = predictions
      |> Enum.map(&Atom.to_string/1)
      |> Enum.join(",")

    input = "#{user_id}:#{bet_amount}:#{token}:#{difficulty}:#{predictions_str}"
    :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)
  end

  @doc """
  Generate combined seed from server_seed + client_seed + nonce.
  """
  def generate_combined_seed(server_seed, client_seed, nonce) do
    input = "#{server_seed}:#{client_seed}:#{nonce}"
    :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)
  end

  @doc """
  Generate flip results from combined seed.
  Each byte of the hash determines one flip (< 128 = heads, >= 128 = tails).
  """
  def generate_results(combined_seed, num_flips) do
    combined_seed
    |> Base.decode16!(case: :lower)
    |> :binary.bin_to_list()
    |> Enum.take(num_flips)
    |> Enum.map(fn byte ->
      if byte < 128, do: :heads, else: :tails
    end)
  end

  @doc """
  Get the raw bytes from combined seed (for verification display).
  """
  def get_result_bytes(combined_seed, num_flips) do
    combined_seed
    |> Base.decode16!(case: :lower)
    |> :binary.bin_to_list()
    |> Enum.take(num_flips)
  end

  @doc """
  Full verification: given all bet details, verify the results are correct.
  Returns {:ok, results, client_seed, combined_seed} if valid, {:error, reason} if not.

  This allows complete third-party verification with only the game record data.
  No timestamp needed - all inputs are player-controlled values from the game record.
  """
  def verify_game(server_seed, server_seed_hash, user_id, bet_amount, token,
                  difficulty, predictions, nonce) do
    # Step 1: Verify server commitment
    if not verify_commitment(server_seed, server_seed_hash) do
      {:error, :invalid_commitment}
    else
      # Step 2: Derive client seed from bet details (all from game record)
      client_seed = generate_client_seed(user_id, bet_amount, token, difficulty, predictions)

      # Step 3: Generate combined seed and results
      combined_seed = generate_combined_seed(server_seed, client_seed, nonce)
      results = generate_results(combined_seed, length(predictions))

      {:ok, results, client_seed, combined_seed}
    end
  end
end
```

#### Step 2: Update LiveView Mount

```elixir
def mount(_params, _session, socket) do
  # ... existing code ...

  # Generate initial server seed and commitment
  server_seed = ProvablyFair.generate_server_seed()
  server_seed_hash = ProvablyFair.generate_commitment(server_seed)

  # Load user's game nonce (next game number)
  nonce = get_user_nonce(current_user.id)

  socket =
    socket
    |> assign(server_seed: server_seed)
    |> assign(server_seed_hash: server_seed_hash)
    |> assign(client_seed: nil)
    |> assign(nonce: nonce)
    |> assign(show_fairness_modal: false)
    |> assign(fairness_game: nil)
    # ... rest of assigns ...

  {:ok, socket}
end
```

#### Step 3: Update Start Game Handler

```elixir
def handle_event("start_game", _params, socket) do
  # ... existing validation ...

  # Generate client seed DETERMINISTICALLY from player's bet choices
  # No timestamp - only player-controlled values
  client_seed = ProvablyFair.generate_client_seed(
    socket.assigns.current_user.id,
    socket.assigns.bet_amount,
    socket.assigns.selected_token,
    socket.assigns.selected_difficulty,
    socket.assigns.predictions
  )

  # Generate results using provably fair method
  combined_seed = ProvablyFair.generate_combined_seed(
    socket.assigns.server_seed,
    client_seed,
    socket.assigns.nonce
  )
  results = ProvablyFair.generate_results(combined_seed, predictions_needed)

  socket =
    socket
    |> assign(results: results)
    |> assign(game_state: :flipping)
    # ... rest ...

  {:noreply, socket}
end
```

#### Step 4: Update Save Game Result

```elixir
defp save_game_result(socket, won, payout \\ 0) do
  # ... existing code ...

  game_record = {
    :bux_booster_games,
    game_id,
    user_id,
    token_type,
    bet_amount,
    difficulty,
    multiplier,
    predictions,
    results,
    won,
    payout,
    now,
    # Provably fair fields:
    socket.assigns.server_seed,
    socket.assigns.server_seed_hash,
    socket.assigns.nonce
  }

  :mnesia.dirty_write(game_record)

  # Increment nonce for next game
  update_user_nonce(user_id)

  # ... rest ...
end

# client_seed can be recomputed anytime from existing game record fields:
# ProvablyFair.generate_client_seed(user_id, bet_amount, token_type, difficulty, predictions)
# No timestamp needed - all inputs are already stored!
```

#### Step 5: Generate New Seed After Game

```elixir
def handle_event("reset_game", _params, socket) do
  # Generate fresh server seed for next game
  server_seed = ProvablyFair.generate_server_seed()
  server_seed_hash = ProvablyFair.generate_commitment(server_seed)
  new_nonce = socket.assigns.nonce + 1

  {:noreply,
   socket
   |> assign(server_seed: server_seed)
   |> assign(server_seed_hash: server_seed_hash)
   |> assign(nonce: new_nonce)
   |> assign(game_state: :idle)
   # ... rest ...
  }
end
```

### UI Changes

#### Step 6: Show Commitment Before Bet

Add to idle state UI, below the bet controls:

```heex
<!-- Provably Fair Info -->
<div class="bg-gray-50 rounded-lg p-3 mb-4 border border-gray-200">
  <div class="flex items-center justify-between">
    <div class="flex items-center gap-2">
      <svg class="w-4 h-4 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
      </svg>
      <span class="text-sm text-gray-600">Provably Fair</span>
    </div>
    <button
      type="button"
      phx-click="show_fairness_info"
      class="text-xs text-purple-600 hover:underline cursor-pointer"
    >
      How it works
    </button>
  </div>
  <div class="mt-2">
    <p class="text-xs text-gray-500">Server Seed Hash (commitment):</p>
    <code class="text-xs text-gray-700 font-mono break-all bg-white px-2 py-1 rounded block mt-1">
      <%= String.slice(@server_seed_hash, 0, 16) %>...<%= String.slice(@server_seed_hash, -8, 8) %>
    </code>
  </div>
  <p class="text-xs text-gray-400 mt-2">
    Game #<%= @nonce + 1 %> • Your seed will be added when you place bet
  </p>
</div>
```

#### Step 7: Client Seed Explanation (No Input Needed)

Since the client seed is derived deterministically from bet details, **no client input is required**.
The UI simply explains how the seed is generated:

```heex
<!-- Client Seed Info (optional, for transparency) -->
<details class="mb-4">
  <summary class="text-xs text-gray-500 cursor-pointer hover:text-gray-700">
    How is my seed generated?
  </summary>
  <div class="mt-2 text-xs text-gray-600 bg-gray-50 p-2 rounded">
    <p class="mb-1">Your client seed is derived from your bet choices:</p>
    <code class="block text-xs bg-white p-1 rounded font-mono">
      SHA256(user_id + bet_amount + token + difficulty + predictions)
    </code>
    <p class="mt-2 text-gray-500">
      Only YOUR choices influence the client seed - no server-controlled values.
      Anyone can verify by recomputing from the game record.
    </p>
  </div>
</details>
```

The `start_game` button is simple - server derives client seed from bet choices:

```heex
<button
  type="button"
  phx-click="start_game"
  class="..."
>
  Place Bet
</button>
```

#### Step 8: Verify Fairness Link in Result

Add to result state, after win/loss display:

```heex
<%= if @game_state == :result do %>
  <!-- ... existing win/loss display ... -->

  <!-- Verify Fairness Link -->
  <button
    type="button"
    phx-click="show_fairness_modal"
    class="mt-4 text-sm text-purple-600 hover:underline cursor-pointer flex items-center justify-center gap-1"
  >
    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
    </svg>
    Verify Fairness
  </button>
<% end %>
```

#### Step 9: Fairness Verification Modal

```heex
<%= if @show_fairness_modal do %>
  <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
       phx-click="close_fairness_modal">
    <div class="bg-white rounded-2xl max-w-lg w-full max-h-[90vh] overflow-y-auto shadow-xl"
         phx-click-away="close_fairness_modal">
      <!-- Header -->
      <div class="flex items-center justify-between p-4 border-b">
        <div class="flex items-center gap-2">
          <svg class="w-5 h-5 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                  d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
          </svg>
          <h2 class="text-lg font-bold">Provably Fair Verification</h2>
        </div>
        <button phx-click="close_fairness_modal" class="text-gray-400 hover:text-gray-600 cursor-pointer">
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <!-- Content -->
      <div class="p-4 space-y-4">
        <!-- Bet Details (used to derive client seed) -->
        <div class="bg-blue-50 rounded-lg p-3 border border-blue-200">
          <p class="text-sm font-medium text-blue-800 mb-2">📋 Your Bet Choices</p>
          <p class="text-xs text-blue-600 mb-2">These player-controlled values derive your client seed:</p>
          <div class="grid grid-cols-2 gap-2 text-sm">
            <div class="text-blue-600">User ID:</div>
            <div class="font-mono text-xs"><%= @fairness_game.user_id %></div>
            <div class="text-blue-600">Bet Amount:</div>
            <div><%= @fairness_game.bet_amount %></div>
            <div class="text-blue-600">Token:</div>
            <div><%= @fairness_game.token %></div>
            <div class="text-blue-600">Difficulty:</div>
            <div><%= @fairness_game.difficulty %></div>
            <div class="text-blue-600">Predictions:</div>
            <div><%= @fairness_game.predictions_str %></div>
          </div>
          <p class="text-xs text-blue-500 mt-2 italic">
            No server-controlled values (like timestamp) are used
          </p>
        </div>

        <!-- Nonce (separate, explains uniqueness) -->
        <div class="bg-gray-50 rounded-lg p-3">
          <div class="flex justify-between items-center">
            <span class="text-sm text-gray-600">Game Nonce:</span>
            <span class="font-mono text-sm"><%= @fairness_game.nonce %></span>
          </div>
          <p class="text-xs text-gray-500 mt-1">
            Ensures unique results even for identical bets
          </p>
        </div>

        <!-- Seeds -->
        <div class="space-y-3">
          <div>
            <label class="text-sm font-medium text-gray-700">Server Seed</label>
            <div class="mt-1 flex items-center gap-2">
              <code class="flex-1 text-xs font-mono bg-gray-100 px-2 py-2 rounded break-all">
                <%= @fairness_game.server_seed %>
              </code>
              <button
                phx-click={JS.dispatch("phx:copy", to: "#server-seed-copy")}
                class="text-gray-400 hover:text-gray-600 cursor-pointer"
              >
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                        d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                </svg>
              </button>
            </div>
          </div>

          <div>
            <label class="text-sm font-medium text-gray-700">Server Seed Hash (Commitment)</label>
            <div class="mt-1">
              <code class="text-xs font-mono bg-gray-100 px-2 py-2 rounded break-all block">
                <%= @fairness_game.server_seed_hash %>
              </code>
            </div>
            <p class="text-xs text-gray-500 mt-1">
              This was shown to you BEFORE you placed your bet
            </p>
          </div>

          <div>
            <label class="text-sm font-medium text-gray-700">Client Seed (Derived from Bet Details)</label>
            <div class="mt-1">
              <code class="text-xs font-mono bg-gray-100 px-2 py-2 rounded break-all block">
                <%= @fairness_game.client_seed %>
              </code>
            </div>
            <p class="text-xs text-gray-500 mt-1">
              = SHA256("<%= @fairness_game.client_seed_input %>")
            </p>
          </div>

          <div>
            <label class="text-sm font-medium text-gray-700">Combined Seed</label>
            <div class="mt-1">
              <code class="text-xs font-mono bg-gray-100 px-2 py-2 rounded break-all block">
                <%= @fairness_game.combined_seed %>
              </code>
            </div>
            <p class="text-xs text-gray-500 mt-1">
              SHA256(server_seed + ":" + client_seed + ":" + nonce)
            </p>
          </div>
        </div>

        <!-- Verification Steps -->
        <div class="bg-green-50 rounded-lg p-3 border border-green-200">
          <p class="text-sm font-medium text-green-800 mb-2">✓ Verification Steps</p>
          <ol class="text-sm text-green-700 space-y-1 list-decimal list-inside">
            <li>SHA256(server_seed) = commitment ✓</li>
            <li>client_seed = SHA256(bet_details) ✓</li>
            <li>combined_seed = SHA256(server_seed:client_seed:nonce) ✓</li>
            <li>Results derived from combined seed bytes ✓</li>
          </ol>
        </div>

        <!-- Flip Results Breakdown -->
        <div>
          <p class="text-sm font-medium text-gray-700 mb-2">Flip Results</p>
          <div class="space-y-2">
            <%= for {result, i} <- Enum.with_index(@fairness_game.results) do %>
              <div class="flex items-center gap-3 text-sm bg-gray-50 rounded p-2">
                <span class="text-gray-500">Flip <%= i + 1 %>:</span>
                <code class="font-mono text-xs">
                  byte[<%= i %>] = <%= Enum.at(@fairness_game.bytes, i) %>
                </code>
                <span class="text-gray-400">→</span>
                <span class={if result == :heads, do: "text-amber-600", else: "text-gray-600"}>
                  <%= if result == :heads, do: "🚀 Heads", else: "💩 Tails" %>
                </span>
                <span class="text-xs text-gray-400">
                  (<%= Enum.at(@fairness_game.bytes, i) %> <%= if result == :heads, do: "< 128", else: ">= 128" %>)
                </span>
              </div>
            <% end %>
          </div>
        </div>

        <!-- External Verification -->
        <div class="border-t pt-4">
          <p class="text-sm font-medium text-gray-700 mb-2">Verify Externally</p>
          <p class="text-xs text-gray-500 mb-2">
            You can verify this result using any SHA256 tool:
          </p>
          <div class="bg-gray-900 text-green-400 rounded p-3 text-xs font-mono overflow-x-auto">
            <p># 1. Verify server commitment</p>
            <p>echo -n "<%= @fairness_game.server_seed %>" | sha256sum</p>
            <p class="text-gray-500"># Should equal: <%= @fairness_game.server_seed_hash %></p>

            <p class="mt-2"># 2. Derive client seed from bet details</p>
            <p>echo -n "<%= @fairness_game.client_seed_input %>" | sha256sum</p>
            <p class="text-gray-500"># Should equal: <%= @fairness_game.client_seed %></p>

            <p class="mt-2"># 3. Generate combined seed</p>
            <p>echo -n "<%= @fairness_game.server_seed %>:<%= @fairness_game.client_seed %>:<%= @fairness_game.nonce %>" | sha256sum</p>
            <p class="text-gray-500"># Should equal: <%= @fairness_game.combined_seed %></p>
          </div>
        </div>
      </div>

      <!-- Footer -->
      <div class="p-4 border-t bg-gray-50 rounded-b-2xl">
        <button
          phx-click="close_fairness_modal"
          class="w-full py-2 bg-black text-white rounded-lg hover:bg-gray-800 cursor-pointer"
        >
          Close
        </button>
      </div>
    </div>
  </div>
<% end %>
```

#### Step 10: Modal Event Handlers

```elixir
def handle_event("show_fairness_modal", _params, socket) do
  # Build the bet details string (same format used for hashing)
  # Only player-controlled values - no timestamp
  predictions_str = socket.assigns.predictions
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(",")

  client_seed_input = "#{socket.assigns.current_user.id}:#{socket.assigns.bet_amount}:" <>
    "#{socket.assigns.selected_token}:#{socket.assigns.selected_difficulty}:" <>
    "#{predictions_str}"

  # Derive client seed from bet details
  client_seed = ProvablyFair.generate_client_seed(
    socket.assigns.current_user.id,
    socket.assigns.bet_amount,
    socket.assigns.selected_token,
    socket.assigns.selected_difficulty,
    socket.assigns.predictions
  )

  # Build fairness game data for current game
  combined_seed = ProvablyFair.generate_combined_seed(
    socket.assigns.server_seed,
    client_seed,
    socket.assigns.nonce
  )

  bytes = ProvablyFair.get_result_bytes(combined_seed, length(socket.assigns.results))

  fairness_game = %{
    game_id: "#{socket.assigns.current_user.id}_#{socket.assigns.nonce}",
    # Bet details (player-controlled only)
    user_id: socket.assigns.current_user.id,
    bet_amount: socket.assigns.bet_amount,
    token: socket.assigns.selected_token,
    difficulty: socket.assigns.selected_difficulty,
    predictions_str: predictions_str,
    nonce: socket.assigns.nonce,
    # Seeds
    server_seed: socket.assigns.server_seed,
    server_seed_hash: socket.assigns.server_seed_hash,
    client_seed_input: client_seed_input,  # The string that gets hashed
    client_seed: client_seed,
    combined_seed: combined_seed,
    # Results
    results: socket.assigns.results,
    bytes: bytes,
    won: socket.assigns.won
  }

  {:noreply,
   socket
   |> assign(show_fairness_modal: true)
   |> assign(fairness_game: fairness_game)}
end

def handle_event("close_fairness_modal", _params, socket) do
  {:noreply, assign(socket, show_fairness_modal: false)}
end

def handle_event("show_fairness_info", _params, socket) do
  # Could show an info modal explaining how provably fair works
  {:noreply, socket}
end
```

### Historical Game Verification

#### Step 11: View Past Game Fairness

Add link in Recent Games section:

```heex
<%= for game <- @recent_games do %>
  <div class="flex justify-between items-center p-1.5 rounded ...">
    <!-- existing game display -->
    <button
      phx-click="show_past_game_fairness"
      phx-value-game_id={game.game_id}
      class="text-purple-600 hover:text-purple-800 cursor-pointer"
      title="Verify fairness"
    >
      <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M9 12l2 2 4-4m5.618-4.016A11.955..." />
      </svg>
    </button>
  </div>
<% end %>
```

Handler:

```elixir
def handle_event("show_past_game_fairness", %{"game_id" => game_id}, socket) do
  case load_game_for_fairness(game_id) do
    nil ->
      {:noreply, socket}

    game ->
      # Derive client seed from stored bet details (no timestamp needed)
      predictions_str = game.predictions
        |> Enum.map(&Atom.to_string/1)
        |> Enum.join(",")

      client_seed_input = "#{game.user_id}:#{game.bet_amount}:" <>
        "#{game.token}:#{game.difficulty}:#{predictions_str}"

      client_seed = ProvablyFair.generate_client_seed(
        game.user_id,
        game.bet_amount,
        game.token,
        game.difficulty,
        game.predictions
      )

      combined_seed = ProvablyFair.generate_combined_seed(
        game.server_seed,
        client_seed,
        game.nonce
      )

      bytes = ProvablyFair.get_result_bytes(combined_seed, length(game.results))

      fairness_game = %{
        game_id: game.game_id,
        # Bet details (player-controlled only)
        user_id: game.user_id,
        bet_amount: game.bet_amount,
        token: game.token,
        difficulty: game.difficulty,
        predictions_str: predictions_str,
        nonce: game.nonce,
        # Seeds
        server_seed: game.server_seed,
        server_seed_hash: game.server_seed_hash,
        client_seed_input: client_seed_input,
        client_seed: client_seed,
        combined_seed: combined_seed,
        # Results
        results: game.results,
        bytes: bytes,
        won: game.won
      }

      {:noreply,
       socket
       |> assign(show_fairness_modal: true)
       |> assign(fairness_game: fairness_game)}
  end
end

defp load_game_for_fairness(game_id) do
  case :mnesia.dirty_read({:bux_booster_games, game_id}) do
    [] -> nil
    [record] ->
      %{
        game_id: elem(record, 1),
        user_id: elem(record, 2),
        token: elem(record, 3),
        bet_amount: elem(record, 4),
        difficulty: elem(record, 5),
        predictions: elem(record, 7),
        results: elem(record, 8),
        won: elem(record, 9),
        server_seed: elem(record, 12),
        server_seed_hash: elem(record, 13),
        nonce: elem(record, 14)  # No timestamp field needed
      }
  end
end
```

---

## Summary of Changes Required

### Files to Create
- `lib/blockster_v2/provably_fair.ex` - Core cryptographic functions with deterministic client seed generation

### Files to Modify
- `lib/blockster_v2_web/live/bux_booster_live.ex` - Main LiveView
- `lib/blockster_v2/mnesia_initializer.ex` - Update table schema

### New UI Elements
1. Commitment display (before bet)
2. Client seed derivation explanation (informational, no input needed)
3. "Verify Fairness" button (after result)
4. Fairness verification modal with full bet details
5. Verify icon in recent games list

### Key Design Decision: Deterministic Client Seed (No Timestamp)

Instead of using a random client seed, the client seed is **derived deterministically** from bet details:

```
client_seed = SHA256(user_id:bet_amount:token:difficulty:predictions)
```

**Why no timestamp?** Timestamps are server-controlled and could introduce doubt.
The nonce already ensures unique results for identical bets.

**Benefits**:
- **Fully transparent**: All inputs are visible in the game record
- **No trust required**: Anyone can verify by recomputing the client seed
- **No server-controlled values**: Only player choices affect the client seed
- **Simpler implementation**: No client-side code needed
- **Auditable**: Third parties can independently verify any game

### Migration Steps
1. Add new fields to Mnesia table definition (`server_seed`, `server_seed_hash`, `nonce`)
2. Handle nil values for old games without provably fair data
3. Generate server seed on mount
4. Derive client seed from player's bet choices (not stored - computed on demand)
5. Update save_game_result with new fields
6. Implement verification modal

---

## Statistics Display

### User Stats Card

Shows for selected token:
- Total Games played
- Win Rate (percentage)
- Net Profit/Loss (green if positive, red if negative)
- Biggest Win amount

### Recent Games Card

Last 10 games showing:
- Token logo and name
- Multiplier level
- Win/loss indicator with amount
- Color coded (green background for win, red for loss)

---

## CSS Classes

### Casino Chip Styles (in app.css)

```css
.bg-coin-heads {
  background-color: #f59e0b; /* Amber */
}

.casino-chip-heads {
  background: conic-gradient(
    #f59e0b 0deg 30deg,
    #ffffff 30deg 60deg,
    /* ... repeating pattern for 12 wedges */
  );
  border: 3px solid #d97706;
}

.casino-chip-tails {
  background: conic-gradient(
    #374151 0deg 30deg,
    #ffffff 30deg 60deg,
    /* ... repeating pattern for 12 wedges */
  );
  border: 3px solid #1f2937;
}
```

### Animation Classes (inline in LiveView)

- `.perspective-1000` - 3D perspective for coin flip
- `.backface-hidden` - Hide back face during flip
- `.rotate-y-180` - Rotate 180deg on Y axis
- `.animate-flip-heads` / `.animate-flip-tails` - Flip animations
- `.confetti-emoji` - Positioned confetti pieces
- `.win-celebration` - Scale-in animation
- `.win-shake` - Shake animation
- `.animate-fade-in` - Button fade in

---

## Security Considerations

### Current Implementation

1. **Results generated server-side** - Client cannot influence outcome
2. **Results generated before first flip** - Prevents mid-game manipulation
3. **Balance validation on bet** - Cannot bet more than balance
4. **User authentication required** - Must be logged in

### Vulnerabilities to Address

1. **Not provably fair** - Server could theoretically manipulate results
2. **No on-chain settlement** - Relies on Mnesia balance updates only
3. **No rate limiting** - Could potentially spam games
4. **No maximum bet limit** - Could bet entire balance

### Recommended Security Additions

1. Implement provably fair commit-reveal
2. Add rate limiting (X games per minute)
3. Add maximum bet limits
4. Add session validation
5. Log all games for audit
6. Implement on-chain settlement for large bets

---

## Performance Considerations

### Optimizations in Place

1. **ETS for token logos** - No DB queries for logos
2. **Mnesia for game data** - Fast reads/writes
3. **Lazy loading stats** - Only load on mount/reset
4. **Efficient confetti** - CSS animations, no JS updates

### Potential Improvements

1. Cache user stats in ETS
2. Batch Mnesia writes
3. Reduce confetti count on mobile
4. Lazy load recent games list
