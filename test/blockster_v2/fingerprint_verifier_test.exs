defmodule BlocksterV2.FingerprintVerifierTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.FingerprintVerifier

  describe "verify_event/2 — precondition checks" do
    test "returns {:ok, :skipped} when API key not configured" do
      original = Application.get_env(:blockster_v2, :fingerprintjs_server_api_key)
      Application.put_env(:blockster_v2, :fingerprintjs_server_api_key, nil)

      assert {:ok, :skipped} = FingerprintVerifier.verify_event("req_123", "visitor_abc")

      Application.put_env(:blockster_v2, :fingerprintjs_server_api_key, original)
    end

    test "returns {:ok, :skipped} when API key is empty string" do
      original = Application.get_env(:blockster_v2, :fingerprintjs_server_api_key)
      Application.put_env(:blockster_v2, :fingerprintjs_server_api_key, "")

      assert {:ok, :skipped} = FingerprintVerifier.verify_event("req_123", "visitor_abc")

      Application.put_env(:blockster_v2, :fingerprintjs_server_api_key, original)
    end

    test "returns {:error, :missing_request_id} when request_id is nil" do
      original = Application.get_env(:blockster_v2, :fingerprintjs_server_api_key)
      Application.put_env(:blockster_v2, :fingerprintjs_server_api_key, "test_key")

      assert {:error, :missing_request_id} = FingerprintVerifier.verify_event(nil, "visitor_abc")

      Application.put_env(:blockster_v2, :fingerprintjs_server_api_key, original)
    end

    test "returns {:error, :missing_request_id} when request_id is empty" do
      original = Application.get_env(:blockster_v2, :fingerprintjs_server_api_key)
      Application.put_env(:blockster_v2, :fingerprintjs_server_api_key, "test_key")

      assert {:error, :missing_request_id} = FingerprintVerifier.verify_event("", "visitor_abc")

      Application.put_env(:blockster_v2, :fingerprintjs_server_api_key, original)
    end

    test "returns {:error, :missing_visitor_id} when visitor_id is nil" do
      original = Application.get_env(:blockster_v2, :fingerprintjs_server_api_key)
      Application.put_env(:blockster_v2, :fingerprintjs_server_api_key, "test_key")

      assert {:error, :missing_visitor_id} = FingerprintVerifier.verify_event("req_123", nil)

      Application.put_env(:blockster_v2, :fingerprintjs_server_api_key, original)
    end
  end
end
