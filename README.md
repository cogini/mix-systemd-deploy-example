This is a working example Elixir app which shows how to deploy using
[mix_systemd](https://github.com/cogini/mix_systemd) and
[mix_deploy](https://github.com/cogini/mix_deploy).

`mix_systemd` generates a [systemd unit file](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
which supervises and manages your app according to standard conventions.

`mix_deploy` generates scripts which are called by systemd during startup and provides lifecycle hooks for deployment
systems like [AWS CodeDeploy](https://aws.amazon.com/codedeploy/).

This repo is built as a series of git commits, so you can see how it works step by step.

It starts with a default Phoenix project with PostgreSQL database.

# Changes

Following are the steps used to set up this repo. You can do the same to add
it to your own project.

It all began with a new Phoenix project:

```shell
mix phx.new mix_systemd_deploy
```

## Set up distillery

Add library:

```elixir
defp deps do
  [{:distillery, "~> 2.0"}]
end
```

Generate initial files in the `rel` dir:

```shell
mix release.init
```

## Set up mix_systemd and mix_deploy

Add library to deps:

```elixir
defp deps do
  [{:mix_deploy, "~> 0.1.0"}]
end
```

Initialize templates under the `rel/templates/systemd` directory:

```shell
MIX_ENV=prod mix systemd.init
```

Generate output files under `_build/#{mix_env}/systemd/lib/systemd/system`.

```shell
MIX_ENV=prod mix systemd.generate
```

Initialize templates under `rel/templates/deploy`:

```shell
MIX_ENV=prod mix deploy.init
```

Generate output files under your project's `bin` direcory:

```shell
MIX_ENV=prod mix deploy.generate
chmod +x bin/*
```

Check files under `rel/templates` and `bin` into source control.

## Configure system

Edit `config/prod.exs`

Uncomment this so Phoenix will run in a release:

```elixir
config :phoenix, :serve_endpoints, true
```

Modify `rel/vm.args` to increase network ports and set node name dynamically,
getting IP address from environment.

Modify `rel/config.exs` to specify runtime config in [TOML](https://github.com/bitwalker/toml-elixir) or
[Mix.Config](https://hexdocs.pm/distillery/Mix.Releases.Config.Providers.Elixir.html) format:

```elixir
set config_providers: [
  {Toml.Provider, [path: "/etc/mix-systemd-deploy/config.toml"},
  # {Mix.Releases.Config.Providers.Elixir, ["/etc/mix-systemd-deploy/config.exs"]},
]
```

Add library:

```elixir
def deps do
  [{:toml, "~> 0.5.2"}]
end
```

## Add support for running db migrations:

Modify `rel/config.exs`.

```elixir
# Custom commands
set commands: [
  migrate: "rel/commands/migrate.sh"
]
```

Add a task to run migrations `lib/mix_systemd_deploy/tasks/migrate.ex`:

```elixir
defmodule MixSystemdDeploy.Tasks.Migrate do
  @moduledoc false
  # CHANGEME
  @app :cloud_native
  @repo_module MixSystemdDeploy.Repo

  def migrate(_args) do
    # Configure
    Mix.Releases.Config.Providers.Elixir.init(["/etc/mix-systemd-deploy/config.toml"])
    # Mix.Releases.Config.Providers.Elixir.init(["/etc/mix-systemd-deplouy/config.exs"])

    repo_config = Application.get_env(@app, @repo_module)
    repo_config = Keyword.put(repo_config, :adapter, Ecto.Adapters.Postgres)
    Application.put_env(@app, @repo_module, repo_config)

    # Start requisite apps
    IO.puts "==> Starting applications.."
    for app <- [:crypto, :ssl, :postgrex, :ecto] do
      {:ok, res} = Application.ensure_all_started(app)
      IO.puts "==> Started #{app}: #{inspect res}"
    end

    # Start the repo
    IO.puts "==> Starting repo"
    {:ok, _pid} = apply(@repo_module, :start_link, [pool_size: 1, log: true, log_sql: true])

    # Run the migrations for the repo
    IO.puts "==> Running migrations"
    priv_dir = Application.app_dir(@app, "priv")
    migrations_dir = Path.join([priv_dir, "repo", "migrations"])

    opts = [all: true]
    # CHANGEME
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
```

Reference the same config provider as above.

Add `rel/commands/migrate.sh`:

Reference the task, above:

```shell
#!/usr/bin/env bash

release_ctl eval "MixSystemdDeploy.Tasks.migrate(:init.get_plain_arguments())"
```

## Generate runtime configuration

### Runtime users

Set runtime `app_user` to `app`. The deploy user defaults to the current user account.
You can also set `deploy_user` to something like `deploy`.

```elixir
config :mix_systemd,
  app_user: "app",
  app_group: "app"

config :mix_deploy,
  deploy_user: "deploy",
  deploy_group: "deploy",
  app_user: "app",
  app_group: "app"
```

Assume that the runtime config will be a TOML file in `/etc/mix-systemd-deploy/config.toml`.
On a simple deploy to a single system, you can just copy the file over.

In a cloud system, we would copy them over at runtime, so we enable the
`deploy-sync-config-s3` script and tell it which S3 bucket to read from with
the `CONFIG_S3_BUCKET` and `CONFIG_S3_PREFIX` environment vars.

```shell
apt install awscli
```

### Setting unique node name

If the app runs in a cluster, we need to set a unique node name.

In `rel/vm.args`, comment out

    -name <%= release_name %>@127.0.0.1

And uncomment:

    -name <%= release_name %>@${DEFAULT_IPV4}

We use `cloud-init` to get the runtime configuration. It gets information about the machine
and writes it to `/run/cloud-init/instance-data.json`. The `deploy-runtime-environment-wrap`.
script reads this file on startup and uses it to set the `DEFAULT_IPV4` environment var.
With the environment var `REPLACE_OS_VARS=true`, Distillery replaces the variable in `rel/vm.args`
with the value on startup.

The scripts `jq` to parse the `cloud-init` data, so install it:

```shell
apt install jq
```

In `config/prod.exs` for `mix_systemd` we set `runtime_environment_wrap: true`
and `env_vars: ["REPLACE_OS_VARS=true"]`, e.g.

```elixir
config :mix_systemd,
  app_user: "app",
  app_group: "app",
  runtime_environment_wrap: true,
  env_vars: [
    "REPLACE_OS_VARS=true",
    "CONFIG_S3_BUCKET=cogini-test",
    "CONFIG_S3_PREFIX=mix-systemd-deploy",
  ],
  exec_start_pre: [
    "deploy-sync-config-s3"
  ]

config :mix_deploy,
  deploy_user: "deploy",
  deploy_group: "deploy",
  app_user: "app",
  app_group: "app"
```

Add `bin/validate-service` script.

Add `appspec.yml`

```yaml
version: 0.0
os: linux
files:
  - source: bin
    destination: /srv/mix-systemd-deploy/bin
  - source: systemd
    destination: /lib/systemd/system
hooks:
  ApplicationStop:
    - location: bin/deploy-stop
      timeout: 300
  BeforeInstall:
    - location: bin/deploy-create-users
    - location: bin/deploy-clean-target
  AfterInstall:
    - location: bin/deploy-extract-release
    - location: bin/deploy-set-perms
    - location: bin/deploy-enable
  ApplicationStart:
    # - location: bin/deploy-migrate
    #     runas: app
    #     timeout: 300
    - location: bin/deploy-start
      timeout: 3600
  ValidateService:
    - location: bin/validate-service
      timeout: 3600
```

For a deploy to the local system:

```shell
sudo bin/deploy-create-users

sudo cp bin/* /srv/mix-systemd-deploy/bin
```

Add secrets:

`/etc/mix-systemd-deploy/config.toml`

See `config/config.toml.sample`

```shell
sudo mkdir /etc/mix-systemd-deploy
sudo chown app:app /etc/mix-systemd-deploy
sudo cp config/config.toml /etc/mix-systemd-deploy/
sudo chown app:app /etc/mix-systemd-deploy/config.toml
sudo chmod 640 /etc/mix-systemd-deploy/config.toml
```

`/etc/mix-systemd-deploy/erlang.cookie`

```shell
mix phx.gen.secret 32
```

The wrapper script `deploy-runtime-environment-file` generates
`/run/mix-systemd-deploy/runtime-environment`.

Install build deps, e.g. with [ASDF](https://asdf-vm.com/#/core-manage-asdf-vm).

```shell
mix deps.get
(cd assets && npm install && node node_modules/webpack/bin/webpack.js --mode development)
```

```shell
sudo mkdir /run/mix-systemd-deploy
sudo chown app:app /run/mix-systemd-deploy
sudo chmod 750 /run/mix-systemd-deploy
sudo bin/deploy-runtime-environment-file
```
