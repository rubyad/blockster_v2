defmodule BlocksterV2Web.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use BlocksterV2Web, :html

  embed_templates "error_html/*"

  # Fallback for error pages without a custom template (e.g. 500)
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
