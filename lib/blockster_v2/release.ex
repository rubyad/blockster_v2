defmodule BlocksterV2.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix installed.
  """
  @app :blockster_v2

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &run_seeds_for/1)
    end
  end

  defp run_seeds_for(repo) do
    # Run the seed script if it exists
    seed_script = Path.join([priv_dir(@app), "repo", "seeds.exs"])

    if File.exists?(seed_script) do
      IO.puts("Running seed script...")
      Code.eval_file(seed_script)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp priv_dir(app), do: "#{:code.priv_dir(app)}"
end
