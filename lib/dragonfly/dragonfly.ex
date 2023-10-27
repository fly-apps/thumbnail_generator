defmodule Dragonfly do
  @moduledoc """
  TODO
  """
  require Logger

  alias Dragonfly.Runner

  @doc """
  Runs a task in an ephemeral Runner of the app.

  ## Examples

    def my_expensive_thing(arg) do
      Dragonfly.call(, fn ->
        # i'm now doing expensive work inside a new node
        # pubsub and repo access all just work
        Phoenix.PubSub.broadcast(MyApp.PubSub, "topic", result)

        # can return awaitable results back to caller
        result
      end)
  """
  def call(func) when is_function(func, 0) do
    call(func, [])
  end

  def call(func, opts) when is_function(func, 0) and is_list(opts) do
    {:ok, pid} = Runner.start_link(opts)
    :ok = Runner.remote_boot(pid)
    call(pid, func)
  end

  def call(pid, func) when is_pid(pid) and is_function(func, 0) do
    Runner.call(pid, func)
  end
end
