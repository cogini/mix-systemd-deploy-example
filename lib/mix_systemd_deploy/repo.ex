defmodule MixSystemdDeploy.Repo do
  use Ecto.Repo,
    otp_app: :mix_systemd_deploy,
    adapter: Ecto.Adapters.Postgres
end
