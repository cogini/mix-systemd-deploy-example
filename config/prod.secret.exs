use Mix.Config

# In this file, we keep production configuration that
# you'll likely want to automate and keep away from
# your version control system.
#
# You should document the content of this
# file or create a script for recreating it, since it's
# kept out of version control and might be hard to recover
# or recreate for your teammates (or yourself later on).
config :mix_systemd_deploy, MixSystemdDeployWeb.Endpoint,
  secret_key_base: "cRvewFEA0uZCS6kgiB0Ut2YbBxBcXvE/870i37YqHvVqrvaL+Pm1Qst2T4JIu5W/"

# Configure your database
config :mix_systemd_deploy, MixSystemdDeploy.Repo,
  username: "postgres",
  password: "postgres",
  database: "mix_systemd_deploy_prod",
  pool_size: 15
