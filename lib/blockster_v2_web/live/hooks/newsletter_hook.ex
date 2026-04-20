defmodule BlocksterV2Web.NewsletterHook do
  @moduledoc """
  Attaches a `newsletter_subscribe` handle_event to every LiveView that mounts
  with this hook, so the footer's subscribe form works on any page.
  """

  import Phoenix.LiveView
  alias BlocksterV2.Newsletter

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :newsletter_subscribe, :handle_event, fn
       "newsletter_subscribe", %{"email" => email}, socket when is_binary(email) ->
         case Newsletter.subscribe(email, "footer") do
           {:ok, _sub} ->
             {:halt, put_flash(socket, :info, "Subscribed. Thanks — watch your inbox.")}

           {:error, %Ecto.Changeset{} = cs} ->
             {:halt, put_flash(socket, :error, format_error(cs))}
         end

       "newsletter_subscribe", _params, socket ->
         {:halt, put_flash(socket, :error, "Please enter an email.")}

       _event, _params, socket ->
         {:cont, socket}
     end)}
  end

  defp format_error(changeset) do
    case changeset.errors[:email] do
      {"is already subscribed", _} -> "You're already on the list."
      {"is invalid", _} -> "That email doesn't look right."
      {msg, _} -> "Email #{msg}"
      _ -> "Could not subscribe. Please try again."
    end
  end
end
