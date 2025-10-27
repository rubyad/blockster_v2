defmodule BlocksterV2.Repo do
  use Ecto.Repo,
    otp_app: :blockster_v2,
    adapter: Ecto.Adapters.Postgres
end
