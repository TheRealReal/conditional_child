defmodule ConditionalChildTest do
  use ExUnit.Case

  defmodule DummyAgent do
    use Agent

    def start_link(init_value) do
      Agent.start_link(fn -> init_value end, name: __MODULE__)
    end
  end

  describe "child_spec/1" do
    test "clones id from child spec of child" do
      child_spec = ConditionalChild.child_spec(child: DummyAgent, start_if: fn -> true end)
      assert child_spec.id == DummyAgent

      child_spec =
        ConditionalChild.child_spec(
          child: Supervisor.child_spec(DummyAgent, id: :custom_id),
          start_if: fn -> true end
        )

      assert child_spec.id == :custom_id
    end
  end

  describe "Child start/stop" do
    test "starts child synchronously when result of start_if is true on init" do
      FeatureFlags.start_link(%{"foo" => true})

      assert {:ok, _pid} =
               ConditionalChild.start_link(
                 child: DummyAgent,
                 start_if: fn -> FeatureFlags.on?("foo") end,
                 interval: 10
               )

      assert is_pid(Process.whereis(DummyAgent))
    end

    test "does not start child when result of start_if is false on init" do
      FeatureFlags.start_link(%{"foo" => false})

      assert {:ok, _pid} =
               ConditionalChild.start_link(
                 child: DummyAgent,
                 start_if: fn -> FeatureFlags.on?("foo") end,
                 interval: 10
               )

      assert is_nil(Process.whereis(DummyAgent))
      sleep()
      assert is_nil(Process.whereis(DummyAgent))
    end

    test "starts and stops child in runtime based on result of start_if" do
      FeatureFlags.start_link(%{"foo" => true})

      assert {:ok, _pid} =
               ConditionalChild.start_link(
                 child: DummyAgent,
                 start_if: fn -> FeatureFlags.on?("foo") end,
                 interval: 10
               )

      assert is_pid(Process.whereis(DummyAgent))

      FeatureFlags.set("foo", false)
      sleep()
      assert is_nil(Process.whereis(DummyAgent))
      sleep()
      assert is_nil(Process.whereis(DummyAgent))

      FeatureFlags.set("foo", true)
      sleep()
      assert is_pid(Process.whereis(DummyAgent))
    end
  end

  describe "Child init failure when ConditionalChild is starting" do
    defmodule FailOnInit do
      use Agent

      def start_link(_) do
        Agent.start_link(fn -> raise "boom" end, name: __MODULE__)
      end
    end

    @tag capture_log: true
    test "stops when child initialization fails" do
      assert {:error, reason} =
               ConditionalChild.start_link(
                 child: FailOnInit,
                 start_if: fn -> true end,
                 interval: 10
               )

      assert {%RuntimeError{message: "boom"}, _stack_trace} = reason
    end
  end

  describe "Child init failure when ConditionalChild is started" do
    defmodule FailAfterConditionalChildStarted do
      use Agent

      def start_link(_) do
        Agent.start_link(
          fn ->
            if FeatureFlags.on?("fail_init") do
              raise "boom"
            else
              %{}
            end
          end,
          name: __MODULE__
        )
      end
    end

    @tag capture_log: true
    test "exits when initialization fails after ConditionalChild is started" do
      Process.flag(:trap_exit, true)

      FeatureFlags.start_link(%{"foo" => true, "fail_init" => false})

      assert {:ok, conditional_child_pid} =
               ConditionalChild.start_link(
                 child: FailAfterConditionalChildStarted,
                 start_if: fn -> FeatureFlags.on?("foo") end,
                 interval: 10
               )

      assert is_pid(Process.whereis(FailAfterConditionalChildStarted))

      FeatureFlags.set("foo", false)
      sleep()
      assert is_nil(Process.whereis(FailAfterConditionalChildStarted))

      FeatureFlags.set("fail_init", true)
      FeatureFlags.set("foo", true)

      assert_receive {:EXIT, ^conditional_child_pid,
                      {%RuntimeError{message: "boom"}, _stack_trace}}
    end
  end

  describe "Child stop failure" do
    defmodule FailOnStop do
      use GenServer

      def start_link(args) do
        GenServer.start_link(__MODULE__, args, name: __MODULE__)
      end

      @impl true
      def init(args) do
        {:ok, args}
      end

      @impl true
      def terminate(_reason, _state) do
        raise "boom"
      end
    end

    @tag capture_log: true
    test "exits when child fails to stop" do
      Process.flag(:trap_exit, true)

      FeatureFlags.start_link(%{"foo" => true})

      {:ok, _} = Task.Supervisor.start_link(name: TaskSupervisor)

      assert {:ok, conditional_child_pid} =
               ConditionalChild.start_link(
                 child: FailOnStop,
                 start_if: fn -> FeatureFlags.on?("foo") end,
                 interval: 10
               )

      child_pid = Process.whereis(FailOnStop)
      assert is_pid(child_pid)

      Task.Supervisor.async_nolink(TaskSupervisor, fn ->
        :proc_lib.stop(child_pid)
      end)

      assert_receive {:EXIT, ^conditional_child_pid,
                      {%RuntimeError{message: "boom"}, _stack_trace}}
    end
  end

  describe "Child process abnormal exit" do
    defmodule ChildProcessAbnormalExit do
      use GenServer

      def start_link(args) do
        GenServer.start_link(__MODULE__, args, name: __MODULE__)
      end

      @impl true
      def init(args) do
        :timer.send_interval(10, :work)
        {:ok, args}
      end

      @impl true
      def handle_info(:work, state) do
        if FeatureFlags.on?("exit") do
          {:stop, "exit reason", state}
        else
          {:noreply, state}
        end
      end
    end

    @tag capture_log: true
    test "exits with same reason when child exits abnormally" do
      Process.flag(:trap_exit, true)

      FeatureFlags.start_link(%{"exit" => false})

      assert {:ok, conditional_child_pid} =
               ConditionalChild.start_link(
                 child: ChildProcessAbnormalExit,
                 start_if: fn -> true end,
                 interval: 10
               )

      assert is_pid(Process.whereis(ChildProcessAbnormalExit))

      FeatureFlags.set("exit", true)
      sleep()

      assert_receive {:EXIT, ^conditional_child_pid, "exit reason"}
    end
  end

  describe "Child process normal exit" do
    defmodule ChildProcessNormalExit do
      use GenServer

      def start_link(args) do
        GenServer.start_link(__MODULE__, args, name: __MODULE__)
      end

      @impl true
      def init(args) do
        :timer.send_interval(10, :work)
        {:ok, args}
      end

      @impl true
      def handle_info(:work, state) do
        if FeatureFlags.on?("exit") do
          {:stop, :normal, state}
        else
          {:noreply, state}
        end
      end
    end

    test "does not restart child when child exits normally" do
      FeatureFlags.start_link(%{"exit" => false})

      assert {:ok, _pid} =
               ConditionalChild.start_link(
                 child: ChildProcessNormalExit,
                 start_if: fn -> true end,
                 interval: 10
               )

      assert is_pid(Process.whereis(ChildProcessNormalExit))

      FeatureFlags.set("exit", true)
      sleep()

      assert is_nil(Process.whereis(ChildProcessNormalExit))
      sleep()
      assert is_nil(Process.whereis(ChildProcessNormalExit))
    end

    test "does not crash when attempting to stop child that already exited normally" do
      FeatureFlags.start_link(%{"foo" => true, "exit" => false})

      assert {:ok, _pid} =
               ConditionalChild.start_link(
                 child: ChildProcessNormalExit,
                 start_if: fn -> FeatureFlags.on?("foo") end,
                 interval: 10
               )

      assert is_pid(Process.whereis(ChildProcessNormalExit))

      FeatureFlags.set("exit", true)
      sleep()

      assert is_nil(Process.whereis(ChildProcessNormalExit))
      sleep()

      FeatureFlags.set("foo", false)
      sleep()

      assert is_nil(Process.whereis(ChildProcessNormalExit))
    end

    test "restarts child that exited normally when condition is toggled twice" do
      FeatureFlags.start_link(%{"foo" => true, "exit" => false})

      assert {:ok, _pid} =
               ConditionalChild.start_link(
                 child: ChildProcessNormalExit,
                 start_if: fn -> FeatureFlags.on?("foo") end,
                 interval: 10
               )

      assert is_pid(Process.whereis(ChildProcessNormalExit))

      FeatureFlags.set("exit", true)
      sleep()

      assert is_nil(Process.whereis(ChildProcessNormalExit))
      sleep()

      FeatureFlags.set("foo", false)
      FeatureFlags.set("exit", false)
      sleep()

      FeatureFlags.set("foo", true)
      sleep()

      assert is_pid(Process.whereis(ChildProcessNormalExit))
    end
  end

  describe "ConditionalChild stop with :normal reason" do
    defmodule ConditionalChildNormalStop do
      use GenServer

      def start_link(args) do
        GenServer.start_link(__MODULE__, args, name: __MODULE__)
      end

      @impl true
      def init(%{test_pid: test_pid}) do
        {:ok, %{test_pid: test_pid}}
      end

      @impl true
      def terminate(reason, %{test_pid: test_pid}) do
        send(test_pid, {:child_received_stop_message, reason})
        reason
      end
    end

    test "sends stop message to child with reason :normal" do
      assert {:ok, pid} =
               ConditionalChild.start_link(
                 child: {ConditionalChildNormalStop, %{test_pid: self()}},
                 start_if: fn -> true end,
                 interval: 10
               )

      assert is_pid(Process.whereis(ConditionalChildNormalStop))

      :proc_lib.stop(pid)

      sleep()
      assert_receive {:child_received_stop_message, :normal}
      assert is_nil(Process.whereis(ConditionalChildNormalStop))
    end
  end

  describe "ConditionalChild stop with :shutdown reason" do
    defmodule ConditionalChildShutdownStop do
      use GenServer

      def start_link(args) do
        GenServer.start_link(__MODULE__, args, name: __MODULE__)
      end

      @impl true
      def init(%{test_pid: test_pid}) do
        {:ok, %{test_pid: test_pid}}
      end

      @impl true
      def terminate(reason, %{test_pid: test_pid}) do
        send(test_pid, {:child_received_stop_message, reason})
        reason
      end
    end

    test "sends stop message to child with reason :shutdown" do
      Process.flag(:trap_exit, true)

      assert {:ok, pid} =
               ConditionalChild.start_link(
                 child: {ConditionalChildShutdownStop, %{test_pid: self()}},
                 start_if: fn -> true end,
                 interval: 10
               )

      assert is_pid(Process.whereis(ConditionalChildShutdownStop))

      :proc_lib.stop(pid, :shutdown, :infinity)

      sleep()
      assert is_nil(Process.whereis(ConditionalChildShutdownStop))
      assert_receive {:child_received_stop_message, :shutdown}
      assert_receive {:EXIT, ^pid, :shutdown}
    end
  end

  describe "End-to-end test" do
    defmodule EndToEnd do
      use Agent

      def start_link(opts) do
        Agent.start_link(fn -> %{} end, opts)
      end
    end

    @tag capture_log: true
    test "end-to-end test with supervisor" do
      FeatureFlags.start_link(%{"foo" => true, "bar" => false})

      children = [
        {ConditionalChild,
         child: Supervisor.child_spec({EndToEnd, name: :foo}, id: :foo),
         start_if: fn -> FeatureFlags.on?("foo") end,
         interval: 10},
        {ConditionalChild,
         child: Supervisor.child_spec({EndToEnd, name: :bar}, id: :bar),
         start_if: fn -> FeatureFlags.on?("bar") end,
         interval: 10}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

      sleep()
      assert is_pid(Process.whereis(:foo))
      assert is_nil(Process.whereis(:bar))

      FeatureFlags.set("bar", true)
      sleep()
      assert is_pid(Process.whereis(:foo))
      assert is_pid(Process.whereis(:bar))

      FeatureFlags.set("foo", false)
      sleep()
      assert is_nil(Process.whereis(:foo))
      assert is_pid(Process.whereis(:bar))

      FeatureFlags.set("bar", false)
      sleep()
      assert is_nil(Process.whereis(:foo))
      assert is_nil(Process.whereis(:bar))

      FeatureFlags.set("bar", true)
      sleep()
      assert is_nil(Process.whereis(:foo))
      assert is_pid(Process.whereis(:bar))

      Process.whereis(:bar) |> Process.exit(:kill)
      sleep()
      assert is_pid(Process.whereis(:bar)), "Expected process to have been restarted"
    end
  end

  defp sleep(time \\ 100), do: :timer.sleep(time)
end
