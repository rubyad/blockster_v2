defmodule BlocksterV2.BuxMinterStub do
  @moduledoc """
  Test stub for `BlocksterV2.BuxMinter` used by `BlocksterV2.Migration.LegacyMerge`
  and any other code that wants to fake out settler minting.

  Behaviour is controlled per-test via the Process dictionary so multiple
  async-style tests don't step on each other (the stub only ever runs in tests
  that have explicitly opted in by setting Application env).

  Usage:

      # Default: every mint succeeds with a fake signature
      BuxMinterStub.set_response({:ok, %{"signature" => "fake_sig"}})

      # Force failures (e.g. to test rollback paths)
      BuxMinterStub.set_response({:error, :settler_unreachable})

      # Inspect what was called
      BuxMinterStub.calls()
  """

  @key :bux_minter_stub_state

  def set_response(response) do
    state = state()
    Process.put(@key, %{state | response: response})
    :ok
  end

  def calls do
    state().calls |> Enum.reverse()
  end

  def reset do
    Process.put(@key, default_state())
    :ok
  end

  # ============================================================================
  # BuxMinter API surface used by LegacyMerge
  # ============================================================================

  def mint_bux(wallet_address, amount, user_id, post_id, reward_type) do
    state = state()

    call = %{
      wallet_address: wallet_address,
      amount: amount,
      user_id: user_id,
      post_id: post_id,
      reward_type: reward_type
    }

    Process.put(@key, %{state | calls: [call | state.calls]})

    state.response
  end

  # ============================================================================
  # Internal
  # ============================================================================

  defp state do
    case Process.get(@key) do
      nil ->
        s = default_state()
        Process.put(@key, s)
        s

      s ->
        s
    end
  end

  defp default_state do
    %{
      response: {:ok, %{"signature" => "stub_signature"}},
      calls: []
    }
  end
end
