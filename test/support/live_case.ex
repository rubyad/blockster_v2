defmodule BlocksterV2Web.LiveCase do
  @moduledoc """
  This module defines the test case to be used by
  LiveView tests.

  It provides conveniences for testing LiveViews and
  includes database sandbox setup.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint BlocksterV2Web.Endpoint

      use BlocksterV2Web, :verified_routes

      # Import conveniences for testing with LiveViews
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import BlocksterV2Web.LiveCase
    end
  end

  setup tags do
    BlocksterV2.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Helper to create a logged-in user and conn for LiveView tests.
  """
  def log_in_user(conn, user) do
    # Create a session for the user
    {:ok, session} = BlocksterV2.Accounts.create_session(user.id)

    # Set the session token in the conn
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, session.token)
  end
end
