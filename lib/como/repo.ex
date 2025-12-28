defmodule Como.Repo do
  use Ecto.Repo,
    otp_app: :como,
    adapter: Ecto.Adapters.Postgres
end
