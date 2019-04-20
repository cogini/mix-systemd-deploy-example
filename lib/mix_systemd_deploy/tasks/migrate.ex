defmodule MixSystemdDeploy.Tasks.Migrate do
  @moduledoc "Mix task to run Ecto database migrations"

  # CHANGEME: Name of app as used by Application.get_env
  @app :mix_systemd_deploy
  # CHANGEME: Name of app repo module
  @repo_module MixSystemdDeploy.Repo

  def run(_args) do
    # CHANGEME: Runtime configuration method/file
    Mix.Releases.Config.Providers.Elixir.init(["/etc/mix-systemd-deploy/config.toml"])
    # Mix.Releases.Config.Providers.Elixir.init(["/etc/mix-systemd-deplouy/config.exs"])

    repo_config = Application.get_env(@app, @repo_module)
    repo_config = Keyword.put(repo_config, :adapter, Ecto.Adapters.Postgres)
    Application.put_env(@app, @repo_module, repo_config)

    # Start requisite apps
    IO.puts "==> Starting applications.."
    for app <- [:crypto, :ssl, :postgrex, :ecto, :ecto_sql] do
      {:ok, res} = Application.ensure_all_started(app)
      IO.puts "==> Started #{app}: #{inspect res}"
    end

    # Start repo
    IO.puts "==> Starting repo"
    {:ok, _pid} = apply(@repo_module, :start_link, [[pool_size: 1, log: :info, log_sql: true]])

    # Run migrations for the repo
    IO.puts "==> Running migrations"
    priv_dir = Application.app_dir(@app, "priv")
    migrations_dir = Path.join([priv_dir, "repo", "migrations"])

    opts = [all: true]
    # CHANGEME: Name of repo module
    pool = MixSystemdDeploy.Repo.config[:pool]
    if function_exported?(pool, :unboxed_run, 2) do
      pool.unboxed_run(@repo_module, fn -> Ecto.Migrator.run(@repo_module, migrations_dir, :up, opts) end)
    else
      Ecto.Migrator.run(@repo_module, migrations_dir, :up, opts)
    end

    # Shut down
    :init.stop()
  end
end
