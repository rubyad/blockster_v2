defmodule BlocksterV2.PhoneVerificationIntegrationTest do
  use BlocksterV2.DataCase

  alias BlocksterV2.PhoneVerification
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Repo

  import Mox

  # Setup mox for TwilioClient
  setup :verify_on_exit!

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

  describe "Full verification flow - US phone" do
    setup do
      user = create_user()
      phone = "+12345678900"
      {:ok, user: user, phone: phone}
    end

    test "successfully verifies US phone and assigns premium tier", %{user: user, phone: phone} do
      # Mock Twilio lookup to return US mobile phone
      expect(TwilioClientMock, :lookup_phone_number, fn ^phone ->
        {:ok, %{
          country_code: "US",
          carrier_name: "Verizon",
          line_type: "mobile",
          fraud_flags: %{}
        }}
      end)

      # Mock Twilio verification code send
      expect(TwilioClientMock, :send_verification_code, fn ^phone ->
        {:ok, "VA123456789"}
      end)

      # Send verification code
      assert {:ok, verification} = PhoneVerification.send_verification_code(user.id, phone)
      assert verification.country_code == "US"
      assert verification.geo_tier == "premium"
      assert Decimal.equal?(verification.geo_multiplier, Decimal.new("2.0"))
      assert verification.phone_number == phone
      assert verification.verified == false

      # Mock Twilio code verification
      expect(TwilioClientMock, :check_verification_code, fn "VA123456789", "123456" ->
        {:ok, :verified}
      end)

      # Verify code
      assert {:ok, verified} = PhoneVerification.verify_code(user.id, "123456")
      assert verified.verified == true
      assert verified.verified_at != nil

      # Check user record was updated
      user = Repo.get!(User, user.id)
      assert user.phone_verified == true
      assert Decimal.equal?(user.geo_multiplier, Decimal.new("2.0"))
      assert user.geo_tier == "premium"
    end
  end

  describe "Full verification flow - UK/International phone" do
    setup do
      user = create_user()
      phone = "+442079460958"
      {:ok, user: user, phone: phone}
    end

    test "successfully verifies UK phone and assigns premium tier", %{user: user, phone: phone} do
      # Mock Twilio lookup to return UK mobile phone
      expect(TwilioClientMock, :lookup_phone_number, fn ^phone ->
        {:ok, %{
          country_code: "GB",
          carrier_name: "Vodafone",
          line_type: "mobile",
          fraud_flags: %{}
        }}
      end)

      # Mock Twilio verification code send
      expect(TwilioClientMock, :send_verification_code, fn ^phone ->
        {:ok, "VA987654321"}
      end)

      # Send verification code
      assert {:ok, verification} = PhoneVerification.send_verification_code(user.id, phone)
      assert verification.country_code == "GB"
      assert verification.geo_tier == "premium"
      assert Decimal.equal?(verification.geo_multiplier, Decimal.new("2.0"))

      # Mock Twilio code verification
      expect(TwilioClientMock, :check_verification_code, fn "VA987654321", "654321" ->
        {:ok, :verified}
      end)

      # Verify code
      assert {:ok, verified} = PhoneVerification.verify_code(user.id, "654321")
      assert verified.verified == true

      # Check user record
      user = Repo.get!(User, user.id)
      assert user.phone_verified == true
      assert Decimal.equal?(user.geo_multiplier, Decimal.new("2.0"))
      assert user.geo_tier == "premium"
    end
  end

  describe "Full verification flow - India phone (basic tier)" do
    setup do
      user = create_user()
      phone = "+919876543210"
      {:ok, user: user, phone: phone}
    end

    test "successfully verifies India phone and assigns basic tier", %{user: user, phone: phone} do
      # Mock Twilio lookup to return India mobile phone
      expect(TwilioClientMock, :lookup_phone_number, fn ^phone ->
        {:ok, %{
          country_code: "IN",
          carrier_name: "Airtel",
          line_type: "mobile",
          fraud_flags: %{}
        }}
      end)

      # Mock Twilio verification code send
      expect(TwilioClientMock, :send_verification_code, fn ^phone ->
        {:ok, "VA111222333"}
      end)

      # Send verification code
      assert {:ok, verification} = PhoneVerification.send_verification_code(user.id, phone)
      assert verification.country_code == "IN"
      assert verification.geo_tier == "basic"
      assert Decimal.equal?(verification.geo_multiplier, Decimal.new("1.0"))

      # Mock Twilio code verification
      expect(TwilioClientMock, :check_verification_code, fn "VA111222333", "999888" ->
        {:ok, :verified}
      end)

      # Verify code
      assert {:ok, verified} = PhoneVerification.verify_code(user.id, "999888")
      assert verified.verified == true

      # Check user record
      user = Repo.get!(User, user.id)
      assert user.phone_verified == true
      assert Decimal.equal?(user.geo_multiplier, Decimal.new("1.0"))
      assert user.geo_tier == "basic"
    end
  end

  describe "Duplicate phone number" do
    setup do
      user1 = create_user()
      user2 = create_user()
      phone = "+12345678900"
      {:ok, user1: user1, user2: user2, phone: phone}
    end

    test "prevents two users from using same phone number", %{user1: user1, user2: user2, phone: phone} do
      # User 1 successfully verifies
      expect(TwilioClientMock, :lookup_phone_number, fn ^phone ->
        {:ok, %{
          country_code: "US",
          carrier_name: "Verizon",
          line_type: "mobile",
          fraud_flags: %{}
        }}
      end)

      expect(TwilioClientMock, :send_verification_code, fn ^phone ->
        {:ok, "VA123456789"}
      end)

      assert {:ok, _} = PhoneVerification.send_verification_code(user1.id, phone)

      expect(TwilioClientMock, :check_verification_code, fn "VA123456789", "123456" ->
        {:ok, :verified}
      end)

      assert {:ok, _} = PhoneVerification.verify_code(user1.id, "123456")

      # User 2 tries to use same phone - should fail at database level
      # Mock Twilio calls since they will be attempted before database constraint check
      expect(TwilioClientMock, :lookup_phone_number, fn ^phone ->
        {:ok, %{
          country_code: "US",
          carrier_name: "Verizon",
          line_type: "mobile",
          fraud_flags: %{}
        }}
      end)

      expect(TwilioClientMock, :send_verification_code, fn ^phone ->
        {:ok, "VA999888777"}
      end)

      # This should fail at database level due to unique constraint
      assert {:error, changeset} = PhoneVerification.send_verification_code(user2.id, phone)
      assert %{phone_number: ["This phone number is already registered"]} = errors_on(changeset)
    end
  end

  describe "Invalid phone numbers" do
    setup do
      user = create_user()
      {:ok, user: user}
    end

    test "rejects invalid phone format", %{user: user} do
      invalid_phones = [
        "123456",           # Too short
        "+1ABC567890",      # Contains letters
        "",                 # Empty
        "+123"              # Too short with country code
      ]

      for invalid_phone <- invalid_phones do
        assert {:error, _message} = PhoneVerification.send_verification_code(user.id, invalid_phone)
      end
    end

    test "rejects VoIP numbers", %{user: user} do
      phone = "+12345678900"

      # Mock Twilio lookup to return VoIP
      expect(TwilioClientMock, :lookup_phone_number, fn ^phone ->
        {:ok, %{
          country_code: "US",
          carrier_name: "Google Voice",
          line_type: "voip",
          fraud_flags: %{}
        }}
      end)

      assert {:error, message} = PhoneVerification.send_verification_code(user.id, phone)
      assert message =~ "VoIP numbers are not supported"
    end
  end

  describe "Expired verification code" do
    setup do
      user = create_user()
      phone = "+12345678900"
      {:ok, user: user, phone: phone}
    end

    test "rejects code after 10 minutes", %{user: user, phone: phone} do
      # Mock Twilio lookup
      expect(TwilioClientMock, :lookup_phone_number, fn ^phone ->
        {:ok, %{
          country_code: "US",
          carrier_name: "Verizon",
          line_type: "mobile",
          fraud_flags: %{}
        }}
      end)

      # Mock Twilio verification code send
      expect(TwilioClientMock, :send_verification_code, fn ^phone ->
        {:ok, "VA123456789"}
      end)

      # Send verification code
      assert {:ok, verification} = PhoneVerification.send_verification_code(user.id, phone)

      # Update the timestamp to 11 minutes ago
      eleven_minutes_ago = DateTime.add(DateTime.utc_now(), -660, :second)

      verification
      |> BlocksterV2.Accounts.PhoneVerification.changeset(%{
        last_attempt_at: eleven_minutes_ago
      })
      |> Repo.update!()

      # Try to verify - should fail due to expiration
      assert {:error, message} = PhoneVerification.verify_code(user.id, "123456")
      assert message =~ "Verification code expired"
    end
  end

  describe "Rate limiting (3 attempts per hour)" do
    setup do
      user = create_user()
      phone = "+12345678900"
      {:ok, user: user, phone: phone}
    end

    test "blocks after 3 verification attempts within 1 hour", %{user: user, phone: phone} do
      # Mock Twilio for first 3 attempts
      expect(TwilioClientMock, :lookup_phone_number, 3, fn ^phone ->
        {:ok, %{
          country_code: "US",
          carrier_name: "Verizon",
          line_type: "mobile",
          fraud_flags: %{}
        }}
      end)

      expect(TwilioClientMock, :send_verification_code, 3, fn ^phone ->
        {:ok, "VA#{:rand.uniform(999999999)}"}
      end)

      # Make 3 attempts
      for _i <- 1..3 do
        assert {:ok, _} = PhoneVerification.send_verification_code(user.id, phone)
      end

      # 4th attempt should be blocked by rate limiter BEFORE calling Twilio
      # Don't set up any expectations - this should not call Twilio
      assert {:error, message} = PhoneVerification.send_verification_code(user.id, phone)
      assert message =~ "Too many verification attempts"
    end

    test "allows new attempt after 1 hour", %{user: user, phone: phone} do
      # Make 3 attempts
      for _i <- 1..3 do
        expect(TwilioClientMock, :lookup_phone_number, fn ^phone ->
          {:ok, %{
            country_code: "US",
            carrier_name: "Verizon",
            line_type: "mobile",
            fraud_flags: %{}
          }}
        end)

        expect(TwilioClientMock, :send_verification_code, fn ^phone ->
          {:ok, "VA#{:rand.uniform(999999999)}"}
        end)

        assert {:ok, _} = PhoneVerification.send_verification_code(user.id, phone)
      end

      # Update timestamp to 61 minutes ago (just over 1 hour)
      verification = Repo.get_by(BlocksterV2.Accounts.PhoneVerification, user_id: user.id)
      sixty_one_minutes_ago = DateTime.add(DateTime.utc_now(), -3660, :second)

      verification
      |> BlocksterV2.Accounts.PhoneVerification.changeset(%{
        last_attempt_at: sixty_one_minutes_ago
      })
      |> Repo.update!()

      # 4th attempt should now succeed (rate limit reset)
      expect(TwilioClientMock, :lookup_phone_number, fn ^phone ->
        {:ok, %{
          country_code: "US",
          carrier_name: "Verizon",
          line_type: "mobile",
          fraud_flags: %{}
        }}
      end)

      expect(TwilioClientMock, :send_verification_code, fn ^phone ->
        {:ok, "VA999888777"}
      end)

      assert {:ok, _} = PhoneVerification.send_verification_code(user.id, phone)
    end
  end

  describe "Wrong verification code" do
    setup do
      user = create_user()
      phone = "+12345678900"
      {:ok, user: user, phone: phone}
    end

    test "rejects incorrect code", %{user: user, phone: phone} do
      # Mock Twilio lookup and send
      expect(TwilioClientMock, :lookup_phone_number, fn ^phone ->
        {:ok, %{
          country_code: "US",
          carrier_name: "Verizon",
          line_type: "mobile",
          fraud_flags: %{}
        }}
      end)

      expect(TwilioClientMock, :send_verification_code, fn ^phone ->
        {:ok, "VA123456789"}
      end)

      assert {:ok, _} = PhoneVerification.send_verification_code(user.id, phone)

      # Mock Twilio rejecting wrong code
      expect(TwilioClientMock, :check_verification_code, fn "VA123456789", "000000" ->
        {:error, "Verification failed: incorrect"}
      end)

      # Try with wrong code
      assert {:error, message} = PhoneVerification.verify_code(user.id, "000000")
      assert message =~ "Verification failed"
    end
  end
end
