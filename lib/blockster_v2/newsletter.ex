defmodule BlocksterV2.Newsletter do
  @moduledoc """
  In-house newsletter subscription list. Stored in Postgres; no external provider.
  """

  alias BlocksterV2.Repo
  alias BlocksterV2.Newsletter.Subscription

  @doc """
  Subscribes an email to the newsletter. Returns `{:ok, subscription}` or
  `{:error, changeset}`. Resubscribes a previously-unsubscribed email in place.
  """
  def subscribe(email, source \\ "footer") when is_binary(email) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    normalized = email |> String.trim() |> String.downcase()

    case Repo.get_by(Subscription, email: normalized) do
      nil ->
        %Subscription{}
        |> Subscription.changeset(%{
          email: normalized,
          source: source,
          subscribed_at: now
        })
        |> Repo.insert()

      %Subscription{unsubscribed_at: nil} = existing ->
        {:ok, existing}

      %Subscription{} = existing ->
        existing
        |> Subscription.changeset(%{
          unsubscribed_at: nil,
          subscribed_at: now,
          source: source
        })
        |> Repo.update()
    end
  end
end
