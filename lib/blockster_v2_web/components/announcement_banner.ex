defmodule BlocksterV2Web.AnnouncementBanner do
  @moduledoc """
  Picks a random announcement banner message for the global lime bar in
  `site_header/1`. Call `pick/1` once in your LiveView `mount/3` and assign
  the result to `:announcement_banner`.

  Messages are context-aware: some only show for logged-in users, some only
  when profile items are incomplete, etc.
  """

  @doc """
  Returns a map `%{text: str, short: str, link: str|nil, cta: str|nil, badge: bool}`
  chosen from all messages the user is eligible to see.

  Uses a deterministic seed based on user_id + current second so:
    * Both LiveView mounts (static + connected) within the same second
      get the same message — no visible flicker.
    * Navigating to a new page (always >= 1 second later) picks a
      different message — the user sees variety.

  `user` is the current_user struct (or nil for anonymous visitors).
  """
  def pick(user) do
    messages = build_eligible_messages(user)
    seed = :erlang.phash2({user && user.id, System.monotonic_time(:second)})
    Enum.at(messages, rem(seed, length(messages)))
  end

  # ── Message pool ──────────────────────────────────────────────────────────

  defp build_eligible_messages(user) do
    always() ++
      conditional_x(user) ++
      conditional_referral(user) ++
      conditional_profile(user)
  end

  # Messages shown to everyone (logged in or not)
  defp always do
    [
      # Hype / Brand
      %{text: "Welcome to the read-to-earn revolution. Powered by Solana.",
        short: "Read-to-earn. Powered by Solana.",
        link: nil, cta: nil, badge: false},
      %{text: "Web3's daily content hub. Read. Watch. Share. Earn.",
        short: "Read. Watch. Share. Earn.",
        link: nil, cta: nil, badge: false},

      # Airdrop
      %{text: "Why Earn BUX? Redeem BUX to enter sponsored airdrops.",
        short: "BUX = airdrop entries.",
        link: nil, cta: "Coming Soon", badge: true},
      %{text: "Airdrops are coming. Stack BUX now so you're ready.",
        short: "Stack BUX for airdrops.",
        link: nil, cta: "Coming Soon", badge: true},

      # Coin Flip / Play
      %{text: "Flip a coin. Win SOL or BUX. Provably fair, on-chain.",
        short: "Flip a coin. Win SOL or BUX.",
        link: "/play", cta: "Play Now →", badge: false},
      %{text: "Feeling lucky? Double your BUX in one flip.",
        short: "Double your BUX in one flip.",
        link: "/play", cta: "Play Now →", badge: false},
      %{text: "Win up to 32x your bet. On-chain. Provably fair.",
        short: "Win up to 32x. On-chain.",
        link: "/play", cta: "Play Now →", badge: false},

      # Liquidity Pool
      %{text: "Earn yield on your SOL. Deposit to the Blockster pool.",
        short: "Earn yield on SOL.",
        link: "/pool", cta: "Deposit →", badge: false},
      %{text: "Be the house. Earn from every coin flip.",
        short: "Be the house. Earn from flips.",
        link: "/pool", cta: "View Pool →", badge: false},

      # Reading / Engagement
      %{text: "You earn BUX just by reading this. Seriously.",
        short: "Earn BUX by reading.",
        link: "/", cta: "Read →", badge: false},
      %{text: "Every article you read earns you BUX. Start stacking.",
        short: "Read articles. Earn BUX.",
        link: "/", cta: "Read →", badge: false}
    ]
  end

  # X / Social — only if logged in AND X not yet connected
  defp conditional_x(nil), do: []
  defp conditional_x(user) do
    if is_nil(user.locked_x_user_id) do
      [%{text: "Share articles on X and earn BUX for every retweet.",
         short: "Share on X. Earn BUX.",
         link: "/auth/x", cta: "Connect X →", badge: false}]
    else
      []
    end
  end

  # Referral banners disabled 2026-04-27 — referral feature parked until
  # post-launch. Function preserved as a no-op so the rotation array shape
  # in `pick/1` stays unchanged; re-populate the entries when the feature
  # ships.
  defp conditional_referral(_user), do: []

  # Profile / Multiplier — only if profile is incomplete
  defp conditional_profile(nil), do: []
  defp conditional_profile(user) do
    incomplete =
      !user.phone_verified ||
        !user.email_verified ||
        is_nil(user.locked_x_user_id)

    if incomplete do
      [
        %{text: "Your multiplier is low. Verify phone + email for up to 20x more BUX.",
          short: "Boost your multiplier up to 20x.",
          link: "/onboarding", cta: "Boost →", badge: false},
        %{text: "Hold SOL. Verify phone. Connect X. Earn up to 20x more BUX.",
          short: "Earn up to 20x more BUX.",
          link: "/onboarding", cta: "My Profile →", badge: false}
      ]
    else
      []
    end
  end
end
