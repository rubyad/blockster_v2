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
  randomly chosen from all messages the user is eligible to see.

  `user` is the current_user struct (or nil for anonymous visitors).
  """
  def pick(user) do
    messages = build_eligible_messages(user)
    Enum.random(messages)
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

  # Referral — only for logged-in users
  defp conditional_referral(nil), do: []
  defp conditional_referral(_user) do
    [
      %{text: "Invite friends. Earn 500 BUX per signup + 0.2% of their bets forever.",
        short: "Invite friends. Earn BUX.",
        link: nil, cta: "Share Link →", badge: false},
      %{text: "Your referral link earns you BUX every time a friend plays.",
        short: "Refer friends. Earn BUX.",
        link: nil, cta: "Copy Link →", badge: false}
    ]
  end

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
