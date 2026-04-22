defmodule BlocksterV2.WalletSelfCustody do
  @moduledoc """
  Audit log for user-initiated self-custody actions on /wallet.

  Used by WalletLive.Index and the Web3AuthWithdraw / Web3AuthExport JS
  hooks (which round-trip events through the LiveView) to record every
  withdrawal and key-export for incident response.

  Never stores private key material — `log_event/2` validates metadata.
  """

  import Ecto.Query

  alias BlocksterV2.Repo
  alias BlocksterV2.WalletSelfCustody.Event

  @doc """
  Record a self-custody event.

  ## Examples

      iex> WalletSelfCustody.log_event(user.id, :withdrawal_initiated,
      ...>   metadata: %{amount: "0.5", to: "ABCD..."},
      ...>   ip: "127.0.0.1")
      {:ok, %Event{}}
  """
  def log_event(user_id, event_type, opts \\ []) when is_atom(event_type) or is_binary(event_type) do
    attrs = %{
      user_id: user_id,
      event_type: to_string(event_type),
      metadata: Keyword.get(opts, :metadata, %{}),
      ip_address: Keyword.get(opts, :ip),
      user_agent: Keyword.get(opts, :user_agent)
    }

    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Return the `limit` most recent events for a user, newest first.
  """
  def list_recent_for_user(user_id, limit \\ 10) do
    Event
    |> where(user_id: ^user_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Count events of a given type for a user over the last `minutes` minutes.
  Used for rate-limiting export attempts.
  """
  def count_recent_for_user(user_id, event_type, minutes \\ 60) do
    cutoff = DateTime.utc_now() |> DateTime.add(-minutes * 60, :second)

    Event
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.event_type == ^to_string(event_type))
    |> where([e], e.inserted_at >= ^cutoff)
    |> Repo.aggregate(:count, :id)
  end
end
