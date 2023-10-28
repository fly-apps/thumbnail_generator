defmodule Thumbs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    dragonfly_parent = Dragonfly.Backend.ParentMonitor.remote_parent_pid()

    children = [
      ThumbsWeb.Telemetry,
      Thumbs.Repo,
      {DNSCluster, query: Application.get_env(:thumbs, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Thumbs.PubSub},
      # Start the Finch HTTP client for sending emails
      !dragonfly_parent && {Finch, name: Thumbs.Finch},
      # Start a worker by calling: Thumbs.Worker.start_link(arg)
      # {Thumbs.Worker, arg},
      # Start to serve requests, typically the last entry
      {Task.Supervisor, name: Thumbs.TaskSup},
      {DynamicSupervisor, name: Thumbs.DynamicSup},
      {Task.Supervisor, name: Dragonfly.TaskSupervisor},
      Dragonfly.FlyBackend,
      !dragonfly_parent && ThumbsWeb.Endpoint
    ] |> Enum.filter(&(&1))

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Thumbs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ThumbsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
