defmodule FeatureFlags do
  # Feature flag module used to help in tests.
  #
  # Usage:
  #
  # iex> FeatureFlags.start_link(%{"foo" => true})
  # {:ok, #PID<0.182.0>}
  #
  # iex> FeatureFlags.on?("foo")
  # true
  #
  # iex> FeatureFlags.on?("bar")
  # false
  #
  # iex> FeatureFlags.set("bar", true)
  # :ok
  #
  # iex> FeatureFlags.on?("bar")
  # true

  use Agent

  def start_link(flags) when is_map(flags),
    do: Agent.start_link(fn -> flags end, name: __MODULE__)

  def on?(flag), do: Agent.get(__MODULE__, &Map.get(&1, flag, false))

  def set(flag, value), do: Agent.update(__MODULE__, &Map.put(&1, flag, value))
end
