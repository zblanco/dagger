defmodule Dagger.MixProject do
  use Mix.Project

  def project do
    [
      app: :dagger,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:uuid, "~> 1.1"},
      {:libgraph, github: "bitwalker/libgraph", branch: "main"}
      # {:norm, "~> 0.10.2"},
      # {:expreso, "~> 0.1.1"}
    ]
  end
end
