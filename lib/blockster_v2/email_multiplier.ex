defmodule BlocksterV2.EmailMultiplier do
  @moduledoc """
  Calculates email verification multiplier for BUX earning rewards.

  | Status       | Multiplier |
  |-------------|-----------|
  | Not verified | 1.0x      |
  | Verified     | 2.0x      |
  """

  alias BlocksterV2.Accounts

  @verified_multiplier 2.0
  @unverified_multiplier 1.0

  @doc """
  Calculate email multiplier for a user.
  Returns 2.0 if email is verified, 1.0 otherwise.
  """
  def calculate(%{email_verified: true}), do: @verified_multiplier
  def calculate(%{email_verified: _}), do: @unverified_multiplier
  def calculate(_), do: @unverified_multiplier

  @doc """
  Calculate email multiplier by user ID (fetches user from DB).
  """
  def calculate_for_user(user_id) when is_integer(user_id) do
    case Accounts.get_user(user_id) do
      nil -> @unverified_multiplier
      user -> calculate(user)
    end
  rescue
    _ -> @unverified_multiplier
  end

  def calculate_for_user(_), do: @unverified_multiplier

  @doc """
  Get the multiplier for verified email.
  """
  def verified_multiplier, do: @verified_multiplier

  @doc """
  Get the multiplier for unverified email.
  """
  def unverified_multiplier, do: @unverified_multiplier
end
