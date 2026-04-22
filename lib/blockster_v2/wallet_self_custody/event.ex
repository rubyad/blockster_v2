defmodule BlocksterV2.WalletSelfCustody.Event do
  @moduledoc """
  Audit-log entry for a self-custody action taken by a Web3Auth user via
  the /wallet panel.

  Recorded events:
    * `withdrawal_initiated`    — user clicked Sign & send (intent to transfer)
    * `withdrawal_confirmed`    — JS hook reported a signature back
    * `withdrawal_failed`       — signing errored or the tx didn't confirm
    * `key_exported`            — the reveal stage was entered (not the key itself)
    * `export_reauth_completed` — the re-auth gate was satisfied successfully

  `metadata` is free-form but MUST NEVER contain private key material.
  Safe keys: `amount`, `to`, `signature`, `format`, `error`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BlocksterV2.Accounts.User

  @event_types ~w(
    withdrawal_initiated
    withdrawal_confirmed
    withdrawal_failed
    key_exported
    export_reauth_completed
  )

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "wallet_self_custody_events" do
    belongs_to :user, User, type: :id
    field :event_type, :string
    field :metadata, :map, default: %{}
    field :ip_address, :string
    field :user_agent, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [:user_id, :event_type, :metadata, :ip_address, :user_agent])
    |> normalize_metadata_keys()
    |> validate_required([:user_id, :event_type])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_no_key_material()
  end

  # Stringify metadata keys so round-tripping through JSONB is a no-op.
  defp normalize_metadata_keys(changeset) do
    case get_change(changeset, :metadata) do
      metadata when is_map(metadata) ->
        stringified = Map.new(metadata, fn {k, v} -> {to_string(k), v} end)
        put_change(changeset, :metadata, stringified)

      _ ->
        changeset
    end
  end

  # Defense in depth — refuse any metadata key that smells like a private key.
  # Check after normalization so we only deal with string keys.
  defp validate_no_key_material(changeset) do
    case get_change(changeset, :metadata) do
      metadata when is_map(metadata) ->
        banned = ~w(private_key secret_key seed mnemonic secretKey privateKey)

        if Enum.any?(banned, &Map.has_key?(metadata, &1)) do
          add_error(changeset, :metadata, "must not contain private key material")
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  def event_types, do: @event_types
end
