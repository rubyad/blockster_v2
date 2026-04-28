defmodule BlocksterV2Web.AnnouncementBanner do
  @moduledoc """
  Returns the global lime announcement banner message. Call `pick/1` once in
  your LiveView `mount/3` and assign the result to `:announcement_banner`.
  """

  @doc """
  Returns the banner message map. The `user` arg is accepted for back-compat
  with callers that pass `current_user`; it is currently unused.
  """
  def pick(_user) do
    %{
      text: "Double your BUX!",
      short: "Double your BUX!",
      link: "/play",
      cta: "Play Now →",
      badge: false
    }
  end
end
