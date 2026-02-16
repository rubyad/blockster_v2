# Set up Mox for mocking
Mox.defmock(TwilioClientMock, for: BlocksterV2.TwilioClientBehaviour)
Mox.defmock(BlocksterV2.ContentAutomation.ClaudeClientMock, for: BlocksterV2.ContentAutomation.ClaudeClientBehaviour)
Mox.defmock(BlocksterV2.Social.XApiClientMock, for: BlocksterV2.Social.XApiClientBehaviour)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(BlocksterV2.Repo, :manual)
