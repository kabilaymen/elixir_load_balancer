defmodule LoadBalancer.Application do
  use Application
  require Logger

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: LoadBalancer.ServerRegistry},

      LoadBalancer.LoadBalancer,

      Supervisor.child_spec({LoadBalancer.Server, 1}, id: :server_1),
      Supervisor.child_spec({LoadBalancer.Server, 2}, id: :server_2),
      Supervisor.child_spec({LoadBalancer.Server, 3}, id: :server_3)
    ]

    opts = [strategy: :one_for_one, name: LoadBalancer.Supervisor]
    Logger.info("Starting LoadBalancer application")
    Supervisor.start_link(children, opts)
  end
end
