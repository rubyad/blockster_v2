defmodule BlocksterV2.Notifications.TriggerEngine do
  @moduledoc """
  Real-time notification triggers that fire based on user events and profile state.
  Called by UserEvents.track/3 after recording each event.
  Each trigger returns {:fire, notification_type, data} or :skip.
  """

  import Ecto.Query
  alias BlocksterV2.{Repo, Notifications}
  alias BlocksterV2.Notifications.Notification

  require Logger

  @bux_milestones [1_000, 5_000, 10_000, 25_000, 50_000, 100_000]

  @doc """
  Evaluate all triggers for a user event. Fires notifications for any matching triggers.
  Returns list of fired notification types (for testing/logging).
  """
  def evaluate_triggers(user_id, event_type, metadata \\ %{}) do
    triggers = [
      &bux_milestone_trigger/3
    ]

    fired =
      Enum.reduce(triggers, [], fn trigger, acc ->
        case trigger.({user_id, event_type, metadata}, %{}, %{}) do
          {:fire, notif_type, data} ->
            fire_notification(user_id, notif_type, data)
            [notif_type | acc]

          :skip ->
            acc
        end
      end)

    Enum.reverse(fired)
  end

  # ============ Triggers ============

  @doc false
  def bux_milestone_trigger({user_id, _event_type, metadata}, _context, _opts) do
    new_balance = get_metadata_decimal(metadata, "new_balance")

    if new_balance do
      milestone = Enum.find(@bux_milestones, fn m ->
        Decimal.compare(new_balance, Decimal.new(m)) != :lt &&
          Decimal.compare(Decimal.sub(new_balance, Decimal.new(m)), Decimal.new(500)) == :lt
      end)

      if milestone && !milestone_already_celebrated?(user_id, milestone) do
        {:fire, "bux_milestone", %{
          milestone: milestone,
          balance: Decimal.to_string(new_balance)
        }}
      else
        :skip
      end
    else
      :skip
    end
  end

  # ============ Notification Firing ============

  defp fire_notification(user_id, type, data) do
    attrs = %{
      type: type,
      category: "rewards",
      title: notification_title(type, data),
      body: notification_body(type, data),
      metadata: data
    }

    case Notifications.create_notification(user_id, attrs) do
      {:ok, _notification} ->
        Logger.info("TriggerEngine fired #{type} for user #{user_id}")
        :ok

      {:error, reason} ->
        Logger.warning("TriggerEngine failed to fire #{type} for user #{user_id}: #{inspect(reason)}")
        :error
    end
  end

  defp notification_title("bux_milestone", %{milestone: m}),
    do: "You hit #{format_number(m)} BUX!"
  defp notification_title(type, _data), do: "Notification: #{type}"

  defp notification_body("bux_milestone", %{milestone: m, balance: bal}),
    do: "Your BUX balance just hit #{format_number(m)}! Current balance: #{bal}"
  defp notification_body(_, _), do: ""

  # ============ Private Helpers ============

  defp milestone_already_celebrated?(user_id, milestone) do
    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type == "bux_milestone",
      where: fragment("?->>'milestone' = ?", n.metadata, ^to_string(milestone))
    )
    |> Repo.exists?()
  end

  defp get_metadata_decimal(metadata, key) do
    val = metadata[key] || metadata[String.to_atom(key)]

    case val do
      nil -> nil
      %Decimal{} = d -> d
      v when is_number(v) -> Decimal.new(v)
      v when is_binary(v) ->
        case Decimal.parse(v) do
          {d, _} -> d
          :error -> nil
        end
      _ -> nil
    end
  end

  defp format_number(n) when n >= 1_000 do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.reverse/1)
    |> String.reverse()
    |> String.replace(~r/^,/, "")
  end
  defp format_number(n), do: Integer.to_string(n)
end
