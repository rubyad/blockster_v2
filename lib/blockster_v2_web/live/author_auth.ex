defmodule BlocksterV2Web.AuthorAuth do
  @moduledoc """
  LiveView on_mount hook to ensure only authors can create/edit posts.
  Admins have full access to all posts.
  """
  import Phoenix.LiveView
  import Phoenix.Component
  alias BlocksterV2.Blog

  def on_mount(:require_author, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt, socket |> put_flash(:error, "You must be logged in to access this page") |> redirect(to: "/")}

      %{is_author: true} ->
        {:cont, socket}

      %{is_admin: true} ->
        {:cont, socket}

      _user ->
        {:halt, socket |> put_flash(:error, "You must be an approved author to create posts") |> redirect(to: "/")}
    end
  end

  def on_mount(:check_post_ownership, %{"slug" => slug}, _session, socket) do
    post = Blog.get_post_by_slug!(slug)
    current_user = socket.assigns[:current_user]

    cond do
      # Not logged in
      is_nil(current_user) ->
        {:halt, socket |> put_flash(:error, "You must be logged in to edit posts") |> redirect(to: "/")}

      # Admin can edit all posts
      current_user.is_admin ->
        {:cont, assign(socket, :post, post)}

      # Author can only edit their own posts (check both author_id and author_name for backwards compatibility)
      current_user.is_author && (post.author_id == current_user.id || post.author_name == current_user.username) ->
        {:cont, assign(socket, :post, post)}

      # Not authorized
      true ->
        {:halt, socket |> put_flash(:error, "You can only edit your own posts") |> redirect(to: "/")}
    end
  rescue
    Ecto.NoResultsError ->
      {:halt, socket |> put_flash(:error, "Post not found") |> redirect(to: "/")}
  end
end
