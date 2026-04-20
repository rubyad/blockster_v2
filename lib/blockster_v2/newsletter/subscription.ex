defmodule BlocksterV2.Newsletter.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @email_regex ~r/^[^\s]+@[^\s]+\.[^\s]+$/

  schema "newsletter_subscriptions" do
    field :email, :string
    field :source, :string, default: "footer"
    field :subscribed_at, :utc_datetime
    field :unsubscribed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:email, :source, :subscribed_at, :unsubscribed_at])
    |> update_change(:email, fn
      email when is_binary(email) -> email |> String.trim() |> String.downcase()
      other -> other
    end)
    |> validate_required([:email, :source, :subscribed_at])
    |> validate_format(:email, @email_regex, message: "is invalid")
    |> validate_length(:email, max: 320)
    |> unique_constraint(:email, message: "is already subscribed")
  end
end
