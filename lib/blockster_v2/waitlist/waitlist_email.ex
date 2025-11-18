defmodule BlocksterV2.Waitlist.WaitlistEmail do
  use Ecto.Schema
  import Ecto.Changeset

  schema "waitlist_emails" do
    field :email, :string
    field :verification_token, :string
    field :verified_at, :utc_datetime
    field :token_sent_at, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(waitlist_email, attrs) do
    waitlist_email
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> update_change(:email, &String.downcase/1)
    |> unique_constraint(:email)
  end

  @doc false
  def token_changeset(waitlist_email, attrs) do
    waitlist_email
    |> cast(attrs, [:verification_token, :token_sent_at])
    |> validate_required([:verification_token, :token_sent_at])
  end

  @doc false
  def verification_changeset(waitlist_email, attrs) do
    waitlist_email
    |> cast(attrs, [:verified_at])
    |> validate_required([:verified_at])
  end
end
