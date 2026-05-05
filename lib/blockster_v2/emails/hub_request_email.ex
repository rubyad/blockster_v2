defmodule BlocksterV2.Emails.HubRequestEmail do
  @moduledoc """
  Sends a notification email to the Blockster team when a project submits
  a hub request via `/hubs/request`.
  """

  import Swoosh.Email

  @to_email "lidia@blockster.com"
  @from_email "info@blockster.com"

  def admin_notification(attrs) do
    new()
    |> to(@to_email)
    |> from({"Blockster Hubs", @from_email})
    |> reply_to(attrs["contact_email"])
    |> subject("New Hub Request: #{attrs["project_name"]}")
    |> html_body(html_body(attrs))
    |> text_body(text_body(attrs))
  end

  defp html_body(attrs) do
    """
    <h2>New Hub Request</h2>
    <table style="border-collapse: collapse; font-family: -apple-system, sans-serif;">
      <tr><td><strong>Project:</strong></td><td>#{e(attrs["project_name"])}</td></tr>
      <tr><td><strong>Website:</strong></td><td><a href="#{e(attrs["website_url"])}">#{e(attrs["website_url"])}</a></td></tr>
      <tr><td><strong>Contact:</strong></td><td>#{e(attrs["contact_name"])}</td></tr>
      <tr><td><strong>Email:</strong></td><td><a href="mailto:#{e(attrs["contact_email"])}">#{e(attrs["contact_email"])}</a></td></tr>
      <tr><td><strong>X:</strong></td><td>#{e(attrs["x_handle"])}</td></tr>
      <tr><td><strong>Telegram:</strong></td><td>#{e(attrs["telegram_handle"])}</td></tr>
      <tr><td><strong>Category:</strong></td><td>#{e(attrs["category"])}</td></tr>
      <tr><td><strong>Community:</strong></td><td>#{e(attrs["community_size"] || "—")}</td></tr>
      <tr><td><strong>Merch:</strong></td><td>#{e(attrs["merch_interest"] || "—")}</td></tr>
      <tr><td><strong>Events:</strong></td><td>#{e(attrs["events_interest"] || "—")}</td></tr>
    </table>
    <h3>Description</h3>
    <p style="white-space: pre-wrap;">#{e(attrs["description"])}</p>
    """
  end

  defp text_body(attrs) do
    """
    New Hub Request

    Project:    #{attrs["project_name"]}
    Website:    #{attrs["website_url"]}
    Contact:    #{attrs["contact_name"]} <#{attrs["contact_email"]}>
    X:          #{attrs["x_handle"]}
    Telegram:   #{attrs["telegram_handle"]}
    Category:   #{attrs["category"]}
    Community:  #{attrs["community_size"] || "—"}
    Merch:      #{attrs["merch_interest"] || "—"}
    Events:     #{attrs["events_interest"] || "—"}

    Description:
    #{attrs["description"]}
    """
  end

  defp e(nil), do: ""
  defp e(s) when is_binary(s), do: Phoenix.HTML.html_escape(s) |> Phoenix.HTML.safe_to_string()
end
