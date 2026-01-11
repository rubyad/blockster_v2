# Ensure the application is started for Endpoint tests
{:ok, _} = Application.ensure_all_started(:high_rollers)

# Start Mox for contract mocking
Application.ensure_all_started(:mox)

ExUnit.start()
