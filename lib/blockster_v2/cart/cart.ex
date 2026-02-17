defmodule BlocksterV2.Cart.Cart do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "carts" do
    # Users have integer primary keys (default Ecto :id), not binary_id
    belongs_to :user, BlocksterV2.Accounts.User, type: :id
    has_many :cart_items, BlocksterV2.Cart.CartItem, on_delete: :delete_all
    timestamps(type: :utc_datetime)
  end

  def changeset(cart, attrs) do
    cart
    |> cast(attrs, [:user_id])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
