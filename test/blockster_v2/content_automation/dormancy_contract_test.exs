defmodule BlocksterV2.ContentAutomation.DormancyContractTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Dormancy contract (2026-06-05): the content automation pipeline spends
  Anthropic credits ONLY when an admin explicitly triggers generation
  (Populate Stories / Market Analysis / Request Article / Events roundup).
  No timer anywhere in the pipeline may reach Claude.

  These are source-level assertions on purpose — the regression they guard
  against (someone re-adding a scheduled generation path) is a code-shape
  change, and a silent one: it works, looks harmless, and burns API credits
  around the clock. If you trip one of these tests intentionally, you are
  re-introducing scheduled Claude spend — get explicit sign-off first.
  """

  @topic_engine_src File.read!("lib/blockster_v2/content_automation/topic_engine.ex")
  @content_queue_src File.read!("lib/blockster_v2/content_automation/content_queue.ex")
  @feed_poller_src File.read!("lib/blockster_v2/content_automation/feed_poller.ex")

  test "TopicEngine has no automatic analysis timer" do
    refute @topic_engine_src =~ ~r/send_after\(self\(\),\s*:analyze/,
           "TopicEngine must not schedule :analyze — generation is admin-triggered only"

    refute @topic_engine_src =~ "schedule_analysis",
           "TopicEngine must not define a schedule_analysis helper"
  end

  test "ContentQueue's loop reaches no generation module" do
    for generation_module <- ~w(ContentGenerator MarketContentScheduler EventRoundup) do
      # Match code usage (alias lines / Module.fun calls), not moduledoc prose.
      refute @content_queue_src =~ ~r/(alias .*\b#{generation_module}\b|#{generation_module}\.\w)/,
             "ContentQueue must not alias or call #{generation_module} — its 10-min loop " <>
               "must stay Claude-free (it publishes admin-approved entries only)"
    end
  end

  test "FeedPoller stays Claude-free" do
    refute @feed_poller_src =~ "ClaudeClient",
           "FeedPoller polls RSS/X only — it must never call Claude"
  end

  test "no AI Manager review crontab — autonomous reviews are manual-only" do
    config_src = File.read!("config/config.exs")

    refute config_src =~ ~r/\{"[^"]+",\s*BlocksterV2\.Workers\.AIManagerReviewWorker/,
           "AIManagerReviewWorker must not be in the Oban crontab — each scheduled " <>
             "run is a Claude Opus call. Trigger reviews manually via Oban.insert/1."
  end
end
