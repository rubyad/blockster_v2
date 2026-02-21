defmodule BlocksterV2.Workers.RogueAirdropWorker do
  @moduledoc """
  Weekly automated ROGUE giveaway to top conversion candidates.
  Scheduled Fridays at 3 PM UTC (before weekend gaming).
  Identifies top candidates by ROGUE readiness score and sends airdrops.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias BlocksterV2.{Repo, Notifications}
  alias BlocksterV2.Notifications.RogueOfferEngine

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "amount" => amount}}) do
    # Single user airdrop (enqueued by batch job)
    send_airdrop_to_user(user_id, amount)
  end

  def perform(%Oban.Job{args: _args}) do
    # Batch: find top candidates and enqueue individual jobs
    candidates = RogueOfferEngine.get_rogue_offer_candidates(25)

    Logger.info("RogueAirdropWorker: found #{length(candidates)} candidates")

    Enum.each(candidates, fn {profile, score} ->
      amount = RogueOfferEngine.calculate_airdrop_amount(profile, score)

      %{user_id: profile.user_id, amount: amount, score: score}
      |> __MODULE__.new()
      |> Oban.insert()
    end)

    :ok
  end

  defp send_airdrop_to_user(user_id, amount) do
    user = Repo.get(BlocksterV2.Accounts.User, user_id)

    if user do
      profile = BlocksterV2.UserEvents.get_profile(user_id)
      reason = RogueOfferEngine.airdrop_reason(profile)

      # Create in-app notification
      Notifications.create_notification(user_id, %{
        type: "special_offer",
        category: "offers",
        title: "Free ROGUE airdrop!",
        body: "#{reason} You received #{amount} ROGUE — play now!",
        action_url: "/play",
        action_label: "Play Your Free ROGUE",
        metadata: %{
          offer_type: "rogue_airdrop",
          amount: amount,
          reason: reason
        }
      })

      # Mark that we sent an offer
      RogueOfferEngine.mark_rogue_offer_sent(user_id)

      Logger.info("RogueAirdropWorker: sent #{amount} ROGUE airdrop to user #{user_id}")
      :ok
    else
      Logger.warning("RogueAirdropWorker: user #{user_id} not found")
      :ok
    end
  end
end
