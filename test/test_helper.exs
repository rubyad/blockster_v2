# Set up Mox for mocking
Mox.defmock(TwilioClientMock, for: BlocksterV2.TwilioClientBehaviour)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(BlocksterV2.Repo, :manual)
