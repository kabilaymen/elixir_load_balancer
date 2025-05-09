defmodule LoadBalancer.MixProject do
  use Mix.Project

  def project do
    [
      app: :load_balancer,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {LoadBalancer.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.2"}
    ]
  end
end
