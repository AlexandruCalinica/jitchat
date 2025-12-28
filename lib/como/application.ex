defmodule Como.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ComoWeb.Telemetry,
      Como.Repo,
      {DNSCluster, query: Application.get_env(:como, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Como.PubSub},
      # Start a worker by calling: Como.Worker.start_link(arg)
      # {Como.Worker, arg},
      # Start to serve requests, typically the last entry
      ComoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Como.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ComoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
