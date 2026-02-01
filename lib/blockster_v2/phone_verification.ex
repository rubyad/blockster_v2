defmodule BlocksterV2.PhoneVerification do
  @moduledoc """
  Context for phone verification and geo-based multipliers.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.{User, PhoneVerification}
  alias BlocksterV2.{UnifiedMultiplier, Referrals}

  # Allow injecting mock client in tests
  @twilio_client Application.compile_env(:blockster_v2, :twilio_client, BlocksterV2.TwilioClient)

  # Rate limiting: max 3 attempts per hour
  @max_attempts_per_hour 3
  @verification_timeout_minutes 10

  @doc """
  Initiates phone verification by sending SMS code.
  Returns {:ok, verification} or {:error, reason}.
  """
  def send_verification_code(user_id, phone_number, sms_opt_in \\ true) do
    # Normalize to E.164
    normalized = normalize_phone_number(phone_number)

    with {:ok, _} <- validate_phone_format(normalized),
         {:ok, _} <- check_phone_not_registered(user_id, normalized),
         {:ok, _} <- check_rate_limit(user_id),
         {:ok, phone_data} <- @twilio_client.lookup_phone_number(normalized),
         {:ok, geo_data} <- determine_geo_tier(phone_data.country_code),
         {:ok, _} <- check_fraud_flags(phone_data),
         {:ok, verification_sid} <- @twilio_client.send_verification_code(normalized) do

      # Create or update phone verification record
      case get_by_user(user_id) do
        nil ->
          # First attempt
          attrs = %{
            user_id: user_id,
            phone_number: normalized,
            country_code: phone_data.country_code,
            carrier_name: phone_data.carrier_name,
            line_type: phone_data.line_type,
            geo_tier: geo_data.tier,
            geo_multiplier: geo_data.multiplier,
            verification_sid: verification_sid,
            attempts: 1,
            last_attempt_at: DateTime.utc_now(),
            fraud_flags: phone_data.fraud_flags,
            sms_opt_in: sms_opt_in
          }

          %PhoneVerification{}
          |> PhoneVerification.changeset(attrs)
          |> Repo.insert()

        existing ->
          # Subsequent attempt - increment counter
          attrs = %{
            user_id: user_id,
            phone_number: normalized,
            country_code: phone_data.country_code,
            carrier_name: phone_data.carrier_name,
            line_type: phone_data.line_type,
            geo_tier: geo_data.tier,
            geo_multiplier: geo_data.multiplier,
            verification_sid: verification_sid,
            attempts: existing.attempts + 1,
            last_attempt_at: DateTime.utc_now(),
            fraud_flags: phone_data.fraud_flags,
            sms_opt_in: sms_opt_in
          }

          existing
          |> PhoneVerification.changeset(attrs)
          |> Repo.update()
      end
    end
  end

  @doc """
  Verifies the code entered by user.
  Returns {:ok, verification} or {:error, reason}.
  """
  def verify_code(user_id, code) do
    with {:ok, verification} <- get_pending_verification(user_id),
         {:ok, _} <- @twilio_client.check_verification_code(verification.phone_number, code) do

      # Mark as verified
      verification
      |> PhoneVerification.changeset(%{
        verified: true,
        verified_at: DateTime.utc_now()
      })
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          # Update user record with multiplier and SMS opt-in
          update_user_multiplier(user_id, updated.geo_multiplier, updated.geo_tier, updated.sms_opt_in)

          # Award referral reward to referrer (if user was referred)
          Referrals.process_phone_verification_reward(user_id)

          {:ok, updated}

        error -> error
      end
    end
  end

  @doc """
  Get geo tier and multiplier for a country code.
  """
  def determine_geo_tier(country_code) do
    tier_map = %{
      # Premium Tier (2.0x)
      "US" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "CA" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "GB" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "AU" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "DE" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "FR" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "IT" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "ES" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "NL" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "SE" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "NO" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "DK" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "FI" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "CH" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "AT" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "BE" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "IE" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "NZ" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "SG" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "JP" => %{tier: "premium", multiplier: Decimal.new("2.0")},
      "KR" => %{tier: "premium", multiplier: Decimal.new("2.0")},

      # Standard Tier (1.5x)
      "BR" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "MX" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "AR" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "CL" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "AE" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "SA" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "IL" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "CN" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "TW" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "HK" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "PL" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "CZ" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "PT" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "GR" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "TR" => %{tier: "standard", multiplier: Decimal.new("1.5")},
      "ZA" => %{tier: "standard", multiplier: Decimal.new("1.5")},

      # Basic Tier (1.0x) - Default for all others
    }

    case Map.get(tier_map, country_code) do
      nil -> {:ok, %{tier: "basic", multiplier: Decimal.new("1.0")}}
      data -> {:ok, data}
    end
  end

  # Private functions (some exposed for testing)

  @doc false
  def normalize_phone_number(phone) do
    # Parse with ex_phone_number library - country code is required
    case ExPhoneNumber.parse(phone, nil) do
      {:ok, phone_number} ->
        # Format to E.164 (+1234567890)
        ExPhoneNumber.format(phone_number, :e164)

      {:error, _reason} ->
        # No fallback - return as-is for validation to catch
        phone
        |> String.replace(~r/[^\d+]/, "")
        |> ensure_plus_prefix()
    end
  end

  defp ensure_plus_prefix(phone) do
    if String.starts_with?(phone, "+") do
      phone
    else
      # Add + prefix but don't assume any country code
      "+" <> phone
    end
  end

  @doc false
  def validate_phone_format(phone) do
    # Parse and validate using ex_phone_number - country code is required
    case ExPhoneNumber.parse(phone, nil) do
      {:ok, phone_number} ->
        if ExPhoneNumber.is_valid_number?(phone_number) do
          # Format to E.164 and return
          normalized = ExPhoneNumber.format(phone_number, :e164)
          {:ok, normalized}
        else
          {:error, "Invalid phone number. Please check the number and country code."}
        end

      {:error, "Invalid country calling code"} ->
        {:error, "Country code required. Please start with + followed by your country code (e.g., +1 for US/CA, +44 for UK, +91 for India)"}

      {:error, "The string supplied did not seem to be a phone number"} ->
        {:error, "Invalid format. Include your country code: +1 234-567-8900, +44 20 1234 5678, etc."}

      {:error, reason} ->
        {:error, "Invalid phone number: #{reason}"}
    end
  end

  @doc false
  def check_rate_limit(user_id) do
    case get_by_user(user_id) do
      nil ->
        {:ok, :no_previous_attempts}

      verification ->
        if verification.last_attempt_at do
          time_since_last = DateTime.diff(DateTime.utc_now(), verification.last_attempt_at, :second)

          cond do
            time_since_last < 3600 && verification.attempts >= @max_attempts_per_hour ->
              {:error, "Too many verification attempts. Please try again in #{60 - div(time_since_last, 60)} minutes."}

            time_since_last >= 3600 ->
              {:ok, :rate_limit_reset}

            true ->
              {:ok, :within_limit}
          end
        else
          {:ok, :no_previous_attempts}
        end
    end
  end

  @doc false
  def check_fraud_flags(phone_data) do
    # Block VoIP numbers (common for fraud)
    if phone_data.line_type == "voip" do
      {:error, "VoIP numbers are not supported. Please use a mobile phone number."}
    else
      {:ok, :passed_fraud_check}
    end
  end

  @doc false
  def check_phone_not_registered(user_id, phone_number) do
    # Check if this phone number is already registered to a different user
    case Repo.get_by(PhoneVerification, phone_number: phone_number) do
      nil ->
        {:ok, :phone_available}

      %PhoneVerification{user_id: ^user_id} ->
        # Same user trying their own number again - that's fine
        {:ok, :phone_available}

      %PhoneVerification{} ->
        {:error, "This phone number is already registered to another account."}
    end
  end

  defp get_pending_verification(user_id) do
    case get_by_user(user_id) do
      nil ->
        {:error, "No verification in progress"}

      verification ->
        if verification.verified do
          {:error, "Phone number already verified"}
        else
          # Check if verification expired (10 minutes)
          if verification.last_attempt_at do
            age = DateTime.diff(DateTime.utc_now(), verification.last_attempt_at, :minute)

            if age > @verification_timeout_minutes do
              {:error, "Verification code expired. Please request a new code."}
            else
              {:ok, verification}
            end
          else
            {:error, "No verification code sent"}
          end
        end
    end
  end

  defp update_user_multiplier(user_id, multiplier, tier, sms_opt_in) do
    Repo.get!(User, user_id)
    |> Ecto.Changeset.change(%{
      phone_verified: true,
      geo_multiplier: multiplier,
      geo_tier: tier,
      sms_opt_in: sms_opt_in
    })
    |> Repo.update!()

    # Update unified_multipliers table (V2 system) when phone verification completes
    UnifiedMultiplier.update_phone_multiplier(user_id)
  end

  defp get_by_user(user_id) do
    Repo.get_by(PhoneVerification, user_id: user_id)
  end

  @doc """
  Get verification status for a user.
  """
  def get_verification_status(user_id) do
    case get_by_user(user_id) do
      nil -> {:ok, %{verified: false, geo_tier: "unverified", geo_multiplier: 0.5}}
      verification ->
        {:ok, %{
          verified: verification.verified,
          geo_tier: verification.geo_tier,
          geo_multiplier: verification.geo_multiplier,
          country_code: verification.country_code,
          verified_at: verification.verified_at
        }}
    end
  end
end
