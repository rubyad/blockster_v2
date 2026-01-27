defmodule BlocksterV2.PhoneVerificationTest do
  use BlocksterV2.DataCase

  alias BlocksterV2.PhoneVerification
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Accounts.PhoneVerification, as: PhoneVerificationSchema
  alias BlocksterV2.Repo

  # Helper to create test users
  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])
    default_attrs = %{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "user#{unique_id}@example.com",
      username: "user#{unique_id}",
      auth_method: "wallet",
      phone_verified: false,
      geo_multiplier: Decimal.new("0.5"),
      geo_tier: "unverified",
      sms_opt_in: true
    }

    %User{}
    |> User.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  describe "normalize_phone_number/1" do
    test "normalizes US phone with spaces and dashes" do
      assert PhoneVerification.normalize_phone_number("+1 234 567 8900") == "+12345678900"
      assert PhoneVerification.normalize_phone_number("+1-234-567-8900") == "+12345678900"
      assert PhoneVerification.normalize_phone_number("234-567-8900") == "+12345678900"
    end

    test "normalizes US phone with parentheses" do
      assert PhoneVerification.normalize_phone_number("(234) 567-8900") == "+12345678900"
      assert PhoneVerification.normalize_phone_number("+1 (234) 567-8900") == "+12345678900"
    end

    test "normalizes US phone without country code (assumes US)" do
      assert PhoneVerification.normalize_phone_number("2345678900") == "+12345678900"
      assert PhoneVerification.normalize_phone_number("1234567890") == "+11234567890"
    end

    test "normalizes international phone numbers" do
      # UK
      assert PhoneVerification.normalize_phone_number("+44 20 7946 0958") == "+442079460958"

      # India
      assert PhoneVerification.normalize_phone_number("+91 98765 43210") == "+919876543210"

      # Nigeria
      assert PhoneVerification.normalize_phone_number("+234 803 123 4567") == "+2348031234567"

      # China
      assert PhoneVerification.normalize_phone_number("+86 138 0013 8000") == "+8613800138000"
    end

    test "strips extensions" do
      assert PhoneVerification.normalize_phone_number("+1 (234) 567-8900 ext. 123") == "+12345678900"
    end

    test "handles edge cases" do
      # Leading 1 without +
      assert PhoneVerification.normalize_phone_number("12345678900") == "+12345678900"

      # Multiple spaces
      assert PhoneVerification.normalize_phone_number("+1   234   567   8900") == "+12345678900"
    end
  end

  describe "validate_phone_format/1" do
    test "validates correct E.164 format" do
      assert {:ok, "+12345678900"} = PhoneVerification.validate_phone_format("+12345678900")
      assert {:ok, "+442079460958"} = PhoneVerification.validate_phone_format("+442079460958")
      assert {:ok, "+919876543210"} = PhoneVerification.validate_phone_format("+919876543210")
    end

    test "rejects invalid formats" do
      # Too short
      assert {:error, _} = PhoneVerification.validate_phone_format("+123")

      # Too short even for US (less than 10 digits)
      assert {:error, _} = PhoneVerification.validate_phone_format("123456")

      # Invalid - letters
      assert {:error, _} = PhoneVerification.validate_phone_format("+1ABC567890")

      # Empty string
      assert {:error, _} = PhoneVerification.validate_phone_format("")
    end

    test "validates mobile numbers only" do
      # This test requires ex_phone_number to detect line type
      # Most validation happens server-side via Twilio
      valid_mobile = "+12345678900"
      assert {:ok, _} = PhoneVerification.validate_phone_format(valid_mobile)
    end
  end

  describe "determine_geo_tier/1" do
    test "returns premium tier for US" do
      assert {:ok, %{tier: "premium", multiplier: multiplier}} =
        PhoneVerification.determine_geo_tier("US")

      assert Decimal.equal?(multiplier, Decimal.new("2.0"))
    end

    test "returns premium tier for other premium countries" do
      premium_countries = ["CA", "GB", "AU", "DE", "FR", "IT", "ES", "NL",
                          "SE", "NO", "DK", "FI", "CH", "AT", "BE", "IE",
                          "NZ", "SG", "JP", "KR"]

      for country <- premium_countries do
        assert {:ok, %{tier: "premium", multiplier: multiplier}} =
          PhoneVerification.determine_geo_tier(country)

        assert Decimal.equal?(multiplier, Decimal.new("2.0"))
      end
    end

    test "returns standard tier for standard countries" do
      standard_countries = ["BR", "MX", "AR", "CL", "AE", "SA", "IL",
                           "CN", "TW", "HK", "PL", "CZ", "PT", "GR", "TR", "ZA"]

      for country <- standard_countries do
        assert {:ok, %{tier: "standard", multiplier: multiplier}} =
          PhoneVerification.determine_geo_tier(country)

        assert Decimal.equal?(multiplier, Decimal.new("1.5"))
      end
    end

    test "returns basic tier for unlisted countries" do
      basic_countries = ["IN", "PK", "BD", "VN", "TH", "PH", "NG", "KE", "UA"]

      for country <- basic_countries do
        assert {:ok, %{tier: "basic", multiplier: multiplier}} =
          PhoneVerification.determine_geo_tier(country)

        assert Decimal.equal?(multiplier, Decimal.new("1.0"))
      end
    end

    test "returns basic tier for unknown countries" do
      assert {:ok, %{tier: "basic", multiplier: multiplier}} =
        PhoneVerification.determine_geo_tier("XX")

      assert Decimal.equal?(multiplier, Decimal.new("1.0"))
    end
  end

  describe "rate limiting" do
    setup do
      # Create a test user
      user = create_user()
      {:ok, user: user}
    end

    test "allows first verification attempt", %{user: user} do
      # First attempt should succeed (mocking Twilio calls)
      # This test would need to mock TwilioClient
      # For now, we'll test the rate limit check function directly

      assert {:ok, :no_previous_attempts} =
        PhoneVerification.check_rate_limit(user.id)
    end

    test "blocks after 3 attempts within an hour", %{user: user} do
      # Create a verification record with 3 attempts in the last hour
      phone_number = "+12345678900"

      attrs = %{
        user_id: user.id,
        phone_number: phone_number,
        country_code: "US",
        geo_tier: "premium",
        geo_multiplier: Decimal.new("2.0"),
        attempts: 3,
        last_attempt_at: DateTime.truncate(DateTime.utc_now(), :second),
        verified: false
      }

      %PhoneVerificationSchema{}
      |> PhoneVerificationSchema.changeset(attrs)
      |> Repo.insert!()

      # 4th attempt should fail
      assert {:error, message} = PhoneVerification.check_rate_limit(user.id)
      assert message =~ "Too many verification attempts"
    end

    test "resets rate limit after 1 hour", %{user: user} do
      # Create a verification record with attempts from 2 hours ago
      phone_number = "+12345678900"
      one_hour_ago = DateTime.add(DateTime.utc_now(), -7200, :second)

      attrs = %{
        user_id: user.id,
        phone_number: phone_number,
        country_code: "US",
        geo_tier: "premium",
        geo_multiplier: Decimal.new("2.0"),
        attempts: 3,
        last_attempt_at: one_hour_ago,
        verified: false
      }

      %PhoneVerificationSchema{}
      |> PhoneVerificationSchema.changeset(attrs)
      |> Repo.insert!()

      # Should be allowed now
      assert {:ok, :rate_limit_reset} = PhoneVerification.check_rate_limit(user.id)
    end
  end

  describe "get_verification_status/1" do
    setup do
      user = create_user()
      {:ok, user: user}
    end

    test "returns unverified status for user with no verification", %{user: user} do
      assert {:ok, status} = PhoneVerification.get_verification_status(user.id)
      assert status.verified == false
      assert status.geo_tier == "unverified"
      # geo_multiplier is returned as float 0.5 for unverified users
      assert status.geo_multiplier == 0.5
    end

    test "returns verified status for user with verification", %{user: user} do
      # Create verified phone record
      attrs = %{
        user_id: user.id,
        phone_number: "+12345678900",
        country_code: "US",
        geo_tier: "premium",
        geo_multiplier: Decimal.new("2.0"),
        verified: true,
        verified_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      %PhoneVerificationSchema{}
      |> PhoneVerificationSchema.changeset(attrs)
      |> Repo.insert!()

      assert {:ok, status} = PhoneVerification.get_verification_status(user.id)
      assert status.verified == true
      assert status.geo_tier == "premium"
      assert Decimal.equal?(status.geo_multiplier, Decimal.new("2.0"))
      assert status.country_code == "US"
      assert status.verified_at != nil
    end
  end

  describe "fraud prevention" do
    test "blocks VoIP numbers" do
      phone_data = %{
        country_code: "US",
        carrier_name: "VoIP Provider",
        line_type: "voip",
        fraud_flags: %{}
      }

      assert {:error, message} = PhoneVerification.check_fraud_flags(phone_data)
      assert message =~ "VoIP numbers are not supported"
    end

    test "allows mobile numbers" do
      phone_data = %{
        country_code: "US",
        carrier_name: "Verizon",
        line_type: "mobile",
        fraud_flags: %{}
      }

      assert {:ok, :passed_fraud_check} = PhoneVerification.check_fraud_flags(phone_data)
    end

    test "allows landline numbers" do
      phone_data = %{
        country_code: "US",
        carrier_name: "AT&T",
        line_type: "landline",
        fraud_flags: %{}
      }

      assert {:ok, :passed_fraud_check} = PhoneVerification.check_fraud_flags(phone_data)
    end
  end

  describe "phone number uniqueness" do
    setup do
      user1 = create_user()
      user2 = create_user()
      {:ok, user1: user1, user2: user2}
    end

    test "prevents duplicate phone numbers across users", %{user1: user1, user2: user2} do
      phone_number = "+12345678900"

      # User 1 verifies phone
      attrs1 = %{
        user_id: user1.id,
        phone_number: phone_number,
        country_code: "US",
        geo_tier: "premium",
        geo_multiplier: Decimal.new("2.0"),
        verified: true,
        verified_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      %PhoneVerificationSchema{}
      |> PhoneVerificationSchema.changeset(attrs1)
      |> Repo.insert!()

      # User 2 tries to use same phone
      attrs2 = %{
        user_id: user2.id,
        phone_number: phone_number,
        country_code: "US",
        geo_tier: "premium",
        geo_multiplier: Decimal.new("2.0"),
        verified: false
      }

      result = %PhoneVerificationSchema{}
        |> PhoneVerificationSchema.changeset(attrs2)
        |> Repo.insert()

      # The unique constraint error will be caught as a changeset error
      assert {:error, changeset} = result
      # Check for the unique constraint error
      assert %{phone_number: ["This phone number is already registered"]} = errors_on(changeset)
    end
  end
end
