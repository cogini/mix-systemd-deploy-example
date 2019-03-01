# Import all plugins from `rel/plugins`
# They can then be used by adding `plugin MyPlugin` to
# either an environment, or release definition, where
# `MyPlugin` is the name of the plugin module.
~w(rel plugins *.exs)
|> Path.join()
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

use Mix.Releases.Config,
    # This sets the default release built by `mix release`
    default_release: :default,
    # This sets the default environment used by `mix release`
    default_environment: Mix.env()

# For a full list of config options for both releases
# and environments, visit https://hexdocs.pm/distillery/config/distillery.html


# You may define one or more environments in this file,
# an environment's settings will override those of a release
# when building in that environment, this combination of release
# and environment configuration is called a profile

environment :dev do
  # If you are running Phoenix, you should make sure that
  # server: true is set and the code reloader is disabled,
  # even in dev mode.
  # It is recommended that you build with MIX_ENV=prod and pass
  # the --env flag to Distillery explicitly if you want to use
  # dev mode.
  set dev_mode: true
  set include_erts: false
  set cookie: :"[Lmuh;KoV0vjYg`_[9[88fupQ`xt;k1S>ECrLN>aLKax;OVh;7<DX|rq4A9$<**e"
end

environment :prod do
  set include_erts: true
  set include_src: false
  set cookie: :"S}ek9N1H[eclz=Klj@uf&2~R_D$WFnsY*9o^cPv/XBUnX8jzP&A~mZCRi2/P:56."
  set vm_args: "rel/vm.args"

  # Custom commands
  set commands: [
    migrate: "rel/commands/migrate.sh"
  ]

  # Runtime config
  set config_providers: [
    {Toml.Provider, [path: "/etc/mix-systemd-deploy/config.toml"]},
    # {Mix.Releases.Config.Providers.Elixir, ["/etc/mix-systemd-deploy/config.exs"]},
  ]
end

# You may define one or more releases in this file.
# If you have not set a default release, or selected one
# when running `mix release`, the first release in the file
# will be used by default

release :mix_systemd_deploy do
  set version: current_version(:mix_systemd_deploy)
  set applications: [
    :runtime_tools
  ]
end
