defmodule ConditionalChild.MixProject do
  use Mix.Project

  @source_url "https://github.com/TheRealReal/conditional_child"
  @version "0.1.0"

  def project do
    [
      app: :conditional_child,
      version: "0.1.0",
      name: "Conditional Child",
      description:
        "A wrapper for starting and stopping a child process in runtime, based on periodic checks",
      elixir: "~> 1.11",
      deps: deps(),
      docs: docs(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: extra_applications(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp extra_applications(:test), do: extra_applications(:default) ++ [:logger]
  defp extra_applications(_), do: []

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["TheRealReal"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/conditional_child",
      source_url: @source_url,
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md": [filename: "changelog", title: "Changelog"],
        "CODE_OF_CONDUCT.md": [filename: "code_of_conduct", title: "Code of Conduct"],
        LICENSE: [filename: "license", title: "License"],
        NOTICE: [filename: "notice", title: "Notice"]
      ]
    ]
  end
end
