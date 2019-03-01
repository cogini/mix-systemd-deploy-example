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
```

Check in files under `rel/templates` and `bin` to source control.


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
    pool = CloudNative.Repo.config[:pool]
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


## Generate environment 
/etc/mix-systemd-deploy/config.toml
/etc/mix-systemd-deploy/erlang.cookie
EnvironmentFile=-/etc/mix-systemd-deploy/environment
EnvironmentFile=-/run/mix-systemd-deploy/runtime-environment





## Set up ASDF

Add the `.tool-versions` file to specify versions of Elixir and Erlang.


## Add Ansible

Add the Ansible tasks to set up the servers and deploy code, in the `ansible`
directory. Configure the vars in the inventory.

This repository contains local copies of roles from Ansible Galaxy in
`roles.galaxy`. To install them, run:

```shell
ansible-galaxy install --roles-path roles.galaxy -r install_roles.yml
```

## Add mix tasks for local deploy

Add `lib/mix/tasks/deploy.ex`

## Add Conform for configuration

Add [Conform](https://github.com/bitwalker/conform) to `deps` in `mix.exs`:

```elixir
 {:conform, "~> 2.2"}
```

Generate schema to the `config/deploy_template.schema.exs` file.

```elixir
MIX_ENV=prod mix conform.new
```

Generate a sample `deploy_template.prod.conf` file:

```elixir
MIX_ENV=prod mix conform.configure
```

Integrate with Distillery, by adding `plugin Conform.ReleasePlugin`
to `rel/config.exs`:

```elixir
release :deploy_template do
  set version: current_version(:deploy_template)
  set applications: [
    :runtime_tools
  ]
  plugin Conform.ReleasePlugin
end
```

## Add shutdown_flag library

This supports restarting the app after deploying a release [without needing
sudo permissions](https://www.cogini.com/blog/deploying-elixir-apps-without-sudo/).

Add [shutdown_flag](https://github.com/cogini/shutdown_flag) to `mix.exs`:

    {:shutdown_flag, github: "cogini/shutdown_flag"},

Add to `config/prod.exs`:

```elixir
config :shutdown_flag,
  flag_file: "/var/tmp/deploy/deploy-template/shutdown.flag",
  check_delay: 10_000
```

# TL;DR

Once you have configured Ansible, set up the servers:

```shell
ansible-playbook -u root -v -l web-servers playbooks/setup-web.yml -D
ansible-playbook -u root -v -l web-servers playbooks/deploy-app.yml --skip-tags deploy -D
ansible-playbook -u root -v -l web-servers playbooks/config-web.yml -D
ansible-playbook -u root -v -l build-servers playbooks/setup-build.yml -D
ansible-playbook -u root -v -l build-servers playbooks/setup-db.yml -D
ansible-playbook -u root -v -l build-servers playbooks/config-build.yml -D
```

Build and deploy the code:

```shell
# Check out latest code and build release on server
ssh -A deploy@build-server build/deploy-template/scripts/build-release.sh

# Deploy release
ssh -A deploy@build-server build/deploy-template/scripts/deploy-local.sh
```

# MixSystemdDeploy

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Install Node.js dependencies with `cd assets && npm install`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: http://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Mailing list: http://groups.google.com/group/phoenix-talk
  * Source: https://github.com/phoenixframework/phoenix


Other options:

Implement [Mix.Config config file](https://hexdocs.pm/distillery/Mix.Releases.Config.Providers.Elixir.html):

```elixir
set config_providers: [
    # Config file in standard systemd `configuration_directory`
    # {Mix.Releases.Config.Providers.Elixir, ["/etc/mix-systemd-deploy/config.exs"]}

    # Config file under release directory
    # {Mix.Releases.Config.Providers.Elixir, ["${RELEASE_ROOT_DIR}/etc/config.exs"]}
]
```

```elixir
# We source control our service file, overlay it into the release tarball
# and it is expected that this path will be symlinked to the appropriate systemd service
# directory on the target
set overlays: [
  {:mkdir, "etc"},
  {:copy, "rel/etc/config.exs", "etc/config.exs"},
  {:template, "rel/etc/environment", "etc/environment"}
]
```
