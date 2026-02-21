defmodule BlocksterV2.Workers.ABTestCheckWorker do
  @moduledoc """
  Periodically checks A/B tests for statistical significance.
  Scheduled via Oban cron every 6 hours.
  When a test reaches significance, promotes the winner.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias BlocksterV2.Notifications.ABTestEngine

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_id" => test_id}}) do
    # Check a specific test
    check_test(test_id)
  end

  def perform(%Oban.Job{args: _args}) do
    # Batch: check all running tests
    tests = ABTestEngine.list_tests(status: "running")

    Enum.each(tests, fn test ->
      check_test(test.id)
    end)

    :ok
  end

  @doc "Enqueue a check for a specific test."
  def enqueue(test_id) do
    %{test_id: test_id}
    |> __MODULE__.new(unique: [period: 300, keys: [:test_id]])
    |> Oban.insert()
  end

  defp check_test(test_id) do
    test = BlocksterV2.Repo.get(BlocksterV2.Notifications.ABTest, test_id)

    if test && test.status == "running" do
      case ABTestEngine.check_significance(test) do
        {:significant, winner, p_value} ->
          Logger.info(
            "A/B test '#{test.name}' (#{test.id}) reached significance: " <>
              "winner=#{winner}, p=#{Float.round(p_value, 4)}"
          )

          ABTestEngine.promote_winner(test, winner)

        {:not_yet, _winner, p_value} ->
          Logger.debug(
            "A/B test '#{test.name}' (#{test.id}) not yet significant: p=#{Float.round(p_value, 4)}"
          )

          :ok

        {:insufficient_data, _, _} ->
          Logger.debug("A/B test '#{test.name}' (#{test.id}) has insufficient data")
          :ok
      end
    else
      :ok
    end
  end
end
