# Seeds synthetic followers so each hub on /hubs reads with healthy social
# proof — between 300 and ~1,800 followers, scaled by current popularity.
#
# Idempotent and stable: each hub's target is deterministic from its id, and
# only the missing delta is inserted. Real follower rows are preserved and
# count toward the target. The rows live in `hub_followers` and persist
# across deploys / app boots — nothing resets them.
#
# Dev:
#   mix run priv/repo/seeds_hub_followers.exs
#
# Dry run (preview, no writes):
#   mix run -e 'BlocksterV2.HubFollowers.Seeder.run(dry_run: true)'
#
# Production:
#   flyctl ssh console --app blockster-v2 \
#     -C "/app/bin/blockster_v2 eval 'BlocksterV2.HubFollowers.Seeder.run()'"

BlocksterV2.HubFollowers.Seeder.run()
