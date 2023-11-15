defmodule Thumbs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    flame_parent = FLAME.Parent.get()

    children =
      [
        ThumbsWeb.Telemetry,
        Thumbs.Repo,
        !flame_parent &&
          {DNSCluster, query: Application.get_env(:thumbs, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Thumbs.PubSub},
        # Start the Finch HTTP client for sending emails
        !flame_parent && {Finch, name: Thumbs.Finch},
        # Start a worker by calling: Thumbs.Worker.start_link(arg)
        # {Thumbs.Worker, arg},
        # Start to serve requests, typically the last entry
        {Task.Supervisor, name: Thumbs.TaskSup},
        {DynamicSupervisor, name: Thumbs.DynamicSup},
        {FLAME.Pool,
         name: Thumbs.FFMpegRunner,
         min: 0,
         max: 10,
         max_concurrency: 5,
         idle_shutdown_after: 10_000},
        !flame_parent && ThumbsWeb.Endpoint
      ]
      |> Enum.filter(& &1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Thumbs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  require Logger

  defp idle? do
    Supervisor.which_children(Thumbs.DynamicSup) == []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ThumbsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
