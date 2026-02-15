defmodule BlocksterV2.ContentAutomation.TimeHelper do
  @moduledoc "EST/UTC conversion for scheduler UI. Handles DST automatically via America/New_York."

  @timezone "America/New_York"

  @doc "Convert a naive datetime (from EST input) to UTC for storage."
  def est_to_utc(%NaiveDateTime{} = naive) do
    naive
    |> DateTime.from_naive!(@timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  @doc "Convert a UTC datetime to EST for display."
  def utc_to_est(%DateTime{} = utc) do
    DateTime.shift_zone!(utc, @timezone)
  end

  @doc "Format a UTC datetime as EST string for datetime-local input (YYYY-MM-DDTHH:MM)."
  def format_for_input(%DateTime{} = utc) do
    est = utc_to_est(utc)
    Calendar.strftime(est, "%Y-%m-%dT%H:%M")
  end

  def format_for_input(nil), do: nil

  @doc "Format a UTC datetime as human-readable EST string."
  def format_display(%DateTime{} = utc) do
    est = utc_to_est(utc)
    suffix = if est.zone_abbr == "EDT", do: "EDT", else: "EST"
    Calendar.strftime(est, "%b %d, %Y at %I:%M %p") <> " " <> suffix
  end

  def format_display(nil), do: nil
end
