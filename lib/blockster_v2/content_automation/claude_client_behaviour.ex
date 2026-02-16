defmodule BlocksterV2.ContentAutomation.ClaudeClientBehaviour do
  @moduledoc "Behaviour for ClaudeClient, enabling Mox mocking in tests."

  @callback call_with_tools(String.t(), list(), keyword()) :: {:ok, map()} | {:error, term()}
end
