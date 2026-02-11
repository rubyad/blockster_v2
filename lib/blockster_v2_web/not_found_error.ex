defmodule BlocksterV2Web.NotFoundError do
  @moduledoc """
  Custom exception that renders as a 404 page.
  """
  defexception message: "Not Found", plug_status: 404
end

defimpl Plug.Exception, for: BlocksterV2Web.NotFoundError do
  def status(_exception), do: 404
  def actions(_exception), do: []
end
