defmodule Thumbs.Repo do
  use Ecto.Repo,
    otp_app: :thumbs,
    adapter: Ecto.Adapters.Postgres
end
