defmodule Livewriter.MixProject do
  use Mix.Project

  def project do
    [
      app: :livewriter,
      version: "0.1.0",
      elixir: "~> 1.17",
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
      {:livebook, "~> 0.13"},
      {:ex_doc, "~> 0.34"}
    ]
  end
end
