defmodule ConditionalChild do
  @moduledoc """
  A wrapper for starting and stopping a child process in runtime, based on periodic checks.

  A common use case is to start and stop processes when feature flags are toggled,
  but any condition can be used.

  ## Example

  Suppose you have a static `Demo.Worker` child in your application supervision tree:

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

  To make it conditional, just wrap it in a `ConditionalChild` process, passing
  `start_if` and `child` options, like in the diff below:

      -      Demo.Worker
      +      {ConditionalChild, child: Demo.Worker, start_if: fn -> your_condition() end}

  Becoming:

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

  During initialization, `ConditionalChild` will execute `start_if` and only start the child process
  if it evaluates to `true`.

  After that, it will execute `start_if` every second, and start/stop the process based on the
  result.

  If every second is too much, the check interval can by changed via the `interval` option, e.g.:

      {
        ConditionalChild,
        child: Demo.Worker,
        start_if: fn -> your_condition() end,
        interval: :timer.seconds(5)
      }

  `ConditionalChild` is linked to the managed child process, meaning that if the child process exits,
  it will exit together with the same reason and be restarted by the parent supervisor.

  Any [`child_spec`-compatible](https://hexdocs.pm/elixir/1.14.3/Supervisor.html#module-child_spec-1-function)
  value can be passed as the `child` option.
  """

  use GenServer

  @typep state :: %{
           start_if: (() -> boolean),
           interval: pos_integer,
           child_spec: parsed_child_spec,
           started: boolean,
           pid: pid | nil
         }

  @typep parsed_child_spec :: %{
           id: atom,
           start: {module, function_name :: atom, args :: list}
         }

  def child_spec(opts) do
    {child, _} = Keyword.pop!(opts, :child)
    child_child_spec = Supervisor.child_spec(child, [])

    %{
      id: child_child_spec.id,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    {child, opts} = Keyword.pop!(opts, :child)
    {start_if, opts} = Keyword.pop!(opts, :start_if)
    {interval, _opts} = Keyword.pop(opts, :interval, 1000)

    state = %{
      start_if: start_if,
      interval: interval,
      child_spec: Supervisor.child_spec(child, []),
      started: false,
      pid: nil
    }

    Process.send_after(self(), :check, interval)

    if start_if.() do
      case start_child(state) do
        {:ok, pid} -> {:ok, Map.merge(state, %{started: true, pid: pid})}
        {:error, reason} -> {:stop, reason}
      end
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_info(:check, state) do
    %{start_if: start_if, started: started, interval: interval} = state

    result =
      case start: start_if.(), started: started do
        start: true, started: true ->
          {:noreply, state}

        start: false, started: false ->
          {:noreply, state}

        start: true, started: false ->
          case start_child(state) do
            {:ok, pid} -> {:noreply, Map.merge(state, %{started: true, pid: pid})}
            {:error, reason} -> {:stop, reason, state}
          end

        start: false, started: true ->
          stop_child!(state)
          {:noreply, Map.merge(state, %{started: false, pid: nil})}
      end

    Process.send_after(self(), :check, interval)

    result
  end

  @spec start_child(state) :: {:ok, pid} | {:error, reason :: any}
  defp start_child(state) do
    %{start: {module, function_name, args}} = state.child_spec
    apply(module, function_name, args)
  end

  @spec stop_child!(state) :: :ok
  defp stop_child!(state) do
    if Process.alive?(state.pid) do
      :proc_lib.stop(state.pid)
    end
  end

  @impl true
  def terminate(reason, state) do
    if state.pid && Process.alive?(state.pid) do
      :proc_lib.stop(state.pid, reason, :infinity)
    end

    reason
  end
end
