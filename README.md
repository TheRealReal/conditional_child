![Tests](https://github.com/TheRealReal/conditional_child/actions/workflows/ci.yml/badge.svg)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)

# Conditional Child

A wrapper for starting and stopping a child process in runtime, based on periodic checks.

A common use case is to start and stop processes when feature flags are toggled, but any condition can be used.

## Installation

Add `conditional_child` to your list of dependencies:

```elixir
def deps do
  [{:conditional_child, "~> 0.1"}]
end
```

## How to use

Suppose you have a static `Demo.Worker` child in your application supervision tree:

```elixir
defmodule Demo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Demo.Worker
    ]

    opts = [strategy: :one_for_one, name: Demo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

To make it conditional, just wrap your child definition into a `ConditionalChild` process, passing `start_if` and `child` options, like in the diff below:

```diff
-      Demo.Worker
+      {ConditionalChild, child: Demo.Worker, start_if: fn -> your_condition() end}
```

Becoming:

```elixir
defmodule Demo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {ConditionalChild, child: Demo.Worker, start_if: fn -> your_condition() end}
    ]

    opts = [strategy: :one_for_one, name: Demo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

During initialization, `ConditionalChild` will execute `start_if` and only start the child process if it evaluates to `true`.

After that, it will execute `start_if` every second, and start/stop the process based on the result. The check interval can be changed if desired.

For more details, see [`ConditionalChild`](https://hexdocs.pm/conditional_child/0.1.1/ConditionalChild.html).

## Code of Conduct

This project  Contributor Covenant version 2.1. Check [CODE_OF_CONDUCT.md](/CODE_OF_CONDUCT.md) file for more information.

## License

`conditional_child` source code is released under Apache License 2.0.

Check [NOTICE](/NOTICE) and [LICENSE](/LICENSE) files for more information.
