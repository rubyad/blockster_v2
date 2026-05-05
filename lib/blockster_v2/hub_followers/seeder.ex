defmodule BlocksterV2.HubFollowers.Seeder do
  @moduledoc """
  Seeds each hub's display follower count to a stable number between
  `@min_followers` and `@max_followers`, scaled by current popularity
  (post count). Writes the synthetic count to `hubs.follower_count_offset`
  rather than fabricating user rows in `hub_followers`.

  ## Display math

  `hub_follower_count(hub) = real_follower_count(hub) + follower_count_offset`

  Real follows still count and push the displayed number above the seeded
  baseline naturally. The offset only ever fills the gap up to `target`
  (clamped at zero — never reduces the real count).

  ## Stability

  - Targets are deterministic per `hub.id` (same input → same output every run).
  - The offset is persisted on `hubs`. Nothing in the codebase resets it on
    boot, deploy, or background work.
  - Idempotent: re-running re-derives the same target and writes the same
    offset (or a smaller one if real follows have caught up).

  ## Usage

      # Dev
      mix run priv/repo/seeds_hub_followers.exs

      # Dry run (no writes)
      mix run -e 'BlocksterV2.HubFollowers.Seeder.run(dry_run: true)'

      # Production
      flyctl ssh console --app blockster-v2 \\
        -C "/app/bin/blockster_v2 eval 'BlocksterV2.HubFollowers.Seeder.run()'"
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Blog.Hub

  @min_followers 300
  @max_followers 1800
  @jitter_pct 0.12

  def run(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    hubs = load_hubs_ranked_by_popularity()

    if hubs == [] do
      IO.puts("No active hubs found — nothing to seed.")
      :ok
    else
      results =
        hubs
        |> compute_targets()
        |> Enum.map(fn {hub, target} -> seed_hub(hub, target, dry_run?) end)

      print_summary(results, dry_run?)
      :ok
    end
  end

  defp load_hubs_ranked_by_popularity do
    from(h in Hub,
      where: h.is_active == true,
      left_join: p in assoc(h, :posts),
      left_join: f in "hub_followers",
      on: f.hub_id == h.id,
      group_by: h.id,
      select: %{
        id: h.id,
        name: h.name,
        post_count: count(p.id, :distinct),
        real_follower_count: count(f.user_id, :distinct)
      },
      order_by: [desc: count(p.id, :distinct), desc: h.id]
    )
    |> Repo.all()
  end

  defp compute_targets(hubs) do
    total = length(hubs)

    Enum.map(Enum.with_index(hubs), fn {hub, rank} ->
      base =
        if total <= 1 do
          @max_followers
        else
          @max_followers - rank / (total - 1) * (@max_followers - @min_followers)
        end

      jitter_seed = :erlang.phash2({hub.id, :jitter}, 1_000_000_000)
      :rand.seed(:exsss, {jitter_seed, jitter_seed + 1, jitter_seed + 2})
      jitter = (:rand.uniform() * 2 - 1) * @jitter_pct

      target =
        (base * (1 + jitter))
        |> round()
        |> max(@min_followers)
        |> min(@max_followers)

      {hub, target}
    end)
  end

  defp seed_hub(hub, target, dry_run?) do
    real_count = hub.real_follower_count
    offset = max(0, target - real_count)

    unless dry_run? do
      Repo.update_all(
        from(h in Hub, where: h.id == ^hub.id),
        set: [follower_count_offset: offset, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )
    end

    {hub, target, real_count, offset}
  end

  defp print_summary(results, dry_run?) do
    prefix = if dry_run?, do: "[DRY RUN] ", else: ""

    IO.puts("\n#{prefix}Hub follower seeding (offset model)")
    IO.puts(String.duplicate("─", 76))

    IO.puts(
      String.pad_trailing("Hub", 36) <>
        String.pad_leading("Real", 9) <>
        String.pad_leading("Offset", 9) <>
        String.pad_leading("Display", 11) <>
        String.pad_leading("Target", 9)
    )

    IO.puts(String.duplicate("─", 76))

    Enum.each(results, fn {hub, target, real, offset} ->
      IO.puts(
        (hub.name |> String.slice(0, 35) |> String.pad_trailing(36)) <>
          String.pad_leading("#{real}", 9) <>
          String.pad_leading("#{offset}", 9) <>
          String.pad_leading("#{real + offset}", 11) <>
          String.pad_leading("#{target}", 9)
      )
    end)

    IO.puts(String.duplicate("─", 76))
    total_display = Enum.reduce(results, 0, fn {_, _, real, offset}, acc -> acc + real + offset end)
    verb = if dry_run?, do: "would display", else: "displaying"
    IO.puts("Total #{verb}: #{total_display} synthetic + real followers across all hubs")
  end
end
