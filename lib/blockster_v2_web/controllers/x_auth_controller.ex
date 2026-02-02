defmodule BlocksterV2Web.XAuthController do
  use BlocksterV2Web, :controller

  require Logger

  alias BlocksterV2.Social
  alias BlocksterV2.Social.{XApiClient, XScoreCalculator}

  @doc """
  Initiates the X OAuth flow by redirecting to X's authorization page.
  """
  def authorize(conn, params) do
    user = conn.assigns[:current_user]

    if is_nil(user) do
      conn
      |> put_flash(:error, "You must be logged in to connect your X account")
      |> redirect(to: ~p"/login")
    else
      redirect_path = normalize_redirect_path(params["redirect"])

      # Generate PKCE code_verifier
      code_verifier = generate_code_verifier()

      case Social.create_oauth_state(user.id, code_verifier, redirect_path) do
        {:ok, state} ->
          code_challenge = generate_code_challenge(code_verifier)
          auth_url = XApiClient.authorize_url(state, code_challenge)

          redirect(conn, external: auth_url)

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Failed to initiate X connection. Please try again.")
          |> redirect(to: redirect_path)
      end
    end
  end

  @doc """
  Handles the OAuth callback from X.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    case Social.get_valid_oauth_state(state) do
      nil ->
        Logger.warning("X OAuth callback with invalid or expired state")

        conn
        |> put_flash(:error, "OAuth session expired. Please try again.")
        |> redirect(to: ~p"/")

      oauth_state ->
        handle_token_exchange(conn, oauth_state, code)
    end
  end

  def callback(conn, %{"error" => error, "error_description" => description}) do
    Logger.warning("X OAuth callback error: #{error} - #{description}")

    conn
    |> put_flash(:error, "X authorization was denied: #{description}")
    |> redirect(to: ~p"/")
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Invalid OAuth callback")
    |> redirect(to: ~p"/")
  end

  @doc """
  Disconnects the user's X account.
  """
  def disconnect(conn, _params) do
    user = conn.assigns[:current_user]

    if is_nil(user) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Not authenticated"})
    else
      # Redirect to member page settings tab after disconnect
      slug = user.slug || user.smart_wallet_address
      redirect_path = "/member/#{slug}?tab=settings"

      case Social.disconnect_x_account(user.id) do
        :ok ->
          conn
          |> put_flash(:info, "X account disconnected successfully")
          |> redirect(to: redirect_path)

        {:ok, _} ->
          conn
          |> put_flash(:info, "X account disconnected successfully")
          |> redirect(to: redirect_path)

        {:error, _} ->
          conn
          |> put_flash(:error, "Failed to disconnect X account")
          |> redirect(to: redirect_path)
      end
    end
  end

  # Private functions

  defp handle_token_exchange(conn, oauth_state, code) do
    redirect_path = normalize_redirect_path(oauth_state.redirect_path)

    case XApiClient.exchange_code(code, oauth_state.code_verifier) do
      {:ok, token_data} ->
        # Clean up the OAuth state
        Social.consume_oauth_state(oauth_state)

        # Get user info from X
        case XApiClient.get_me(token_data.access_token) do
          {:ok, x_user} ->
            save_x_connection(conn, oauth_state, token_data, x_user, redirect_path)

          {:error, reason} ->
            Logger.error("Failed to get X user info: #{reason}")

            conn
            |> put_flash(:error, "Failed to get your X profile information")
            |> redirect(to: redirect_path)
        end

      {:error, reason} ->
        Logger.error("X OAuth token exchange failed: #{reason}")
        Social.consume_oauth_state(oauth_state)

        conn
        |> put_flash(:error, "Failed to connect X account: #{reason}")
        |> redirect(to: redirect_path)
    end
  end

  defp save_x_connection(conn, oauth_state, token_data, x_user, redirect_path) do
    user_id = oauth_state.user_id

    expires_at =
      if token_data.expires_in do
        DateTime.utc_now()
        |> DateTime.add(token_data.expires_in, :second)
        |> DateTime.truncate(:second)
      end

    attrs = %{
      x_user_id: x_user["id"],
      x_username: x_user["username"],
      x_name: x_user["name"],
      x_profile_image_url: x_user["profile_image_url"],
      access_token: token_data.access_token,
      refresh_token: token_data.refresh_token,
      token_expires_at: expires_at,
      scopes: token_data.scope,
      connected_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    case Social.upsert_x_connection(user_id, attrs) do
      {:ok, connection} ->
        # Calculate X score asynchronously if needed (first connect or 7+ days old)
        # This runs in the background so it doesn't slow down the redirect
        maybe_calculate_x_score_async(connection, token_data.access_token)

        conn
        |> put_flash(:info, "X account @#{x_user["username"]} connected successfully!")
        |> redirect(to: redirect_path)

      {:error, :x_account_locked} ->
        Logger.warning("User #{user_id} attempted to connect X account @#{x_user["username"]} but is locked to a different account")

        conn
        |> put_flash(:error, "Your account is locked to a different X account. You can only connect the X account you originally linked.")
        |> redirect(to: redirect_path)

      {:error, {:x_account_already_linked, existing_email}} ->
        Logger.warning("User #{user_id} attempted to connect X account @#{x_user["username"]} but it's already linked to another Blockster account (#{existing_email})")

        message = if existing_email do
          "This X account (@#{x_user["username"]}) is already connected to another Blockster account (#{existing_email}). Please log in with that account instead, or use a different X account."
        else
          "This X account (@#{x_user["username"]}) is already connected to another Blockster account. Each X account can only be linked to one Blockster account."
        end

        conn
        |> put_flash(:error, message)
        |> redirect(to: redirect_path)

      {:error, changeset} ->
        Logger.error("Failed to save X connection: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to save X connection")
        |> redirect(to: redirect_path)
    end
  end

  # Calculates X score asynchronously if score_calculated_at is nil or > 7 days old
  defp maybe_calculate_x_score_async(connection, access_token) do
    if XScoreCalculator.needs_score_calculation?(connection) do
      Task.start(fn ->
        case XScoreCalculator.calculate_and_save_score(connection, access_token) do
          {:ok, _updated} ->
            Logger.info("[XAuthController] X score calculated for user #{connection.user_id}")

          {:error, reason} ->
            Logger.error("[XAuthController] Failed to calculate X score: #{inspect(reason)}")
        end
      end)
    end
  end

  # Normalizes the redirect path to ensure it starts with /
  # Default to home page since /profile no longer exists
  defp normalize_redirect_path(nil), do: "/"
  defp normalize_redirect_path(""), do: "/"
  defp normalize_redirect_path("/profile"), do: "/"
  defp normalize_redirect_path("/" <> _ = path), do: path
  defp normalize_redirect_path(path), do: "/" <> path

  # PKCE code_verifier generation (43-128 characters, URL-safe base64)
  defp generate_code_verifier do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  # PKCE code_challenge generation (SHA256 hash of verifier, URL-safe base64)
  defp generate_code_challenge(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end
end
