defmodule BlocksterV2.Repo.Migrations.DropUserProfilesAndAbTests do
  use Ecto.Migration

  def up do
    drop_if_exists table(:user_profiles)
    drop_if_exists table(:ab_test_assignments)
    drop_if_exists table(:ab_tests)
  end

  def down do
    # These tables are intentionally not recreated on rollback.
    # The user_profiles table has been replaced by Mnesia-based lookups.
    # AB testing infrastructure was unused dead code.
    :ok
  end
end
