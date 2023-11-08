defmodule Thumbs.ThumbnailGenerator do
  use GenServer
  @png_begin <<137, 80, 78, 71, 13, 10, 26, 10>>

  require Logger

  alias Thumbs.ThumbnailGenerator

  defstruct ref: nil, exec_pid: nil, caller: nil, pid: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def stream_chunk!(%ThumbnailGenerator{} = gen, chunk) do
    each_part(chunk, 60_000, fn part -> :ok = exec_send(gen, part) end)
  end

  def close(%ThumbnailGenerator{} = gen) do
    ref = Process.monitor(gen.pid)
    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> :ok
    after
      0 -> GenServer.call(gen.pid, :close)
    end
  end

  def open(opts \\ []) do
    Keyword.validate!(opts, [:timeout, :caller, :fps])
    timeout = Keyword.get(opts, :timeout, 5_000)
    caller = Keyword.get(opts, :caller, self())
    parent_ref = make_ref()
    parent = self()

    spec = %{
      id: parent_ref,
      start: {__MODULE__, :start_link, [{caller, parent_ref, parent, opts}]},
      restart: :temporary
    }

    {:ok, pid} = DynamicSupervisor.start_child(Thumbs.DynamicSup, spec)

    receive do
      {^parent_ref, %ThumbnailGenerator{} = gen} ->
        %ThumbnailGenerator{gen | pid: pid}
    after
      timeout -> exit(:timeout)
    end
  end

  @impl true
  def init({caller, parent_ref, parent, opts}) do
    count = Keyword.get(opts, :fps, 60)

    case exec("ffmpeg -i pipe:0 -vf \"fps=1/#{count}\" -f image2pipe -c:v png -") do
      {:ok, exec_pid, ref} ->
        gen = %ThumbnailGenerator{ref: ref, exec_pid: exec_pid, pid: self(), caller: caller}
        send(parent, {parent_ref, gen})
        Process.monitor(caller)
        {:ok, %{gen: gen, count: 0, current: nil}}

      other ->
        exit(other)
    end
  end

  @impl true
  def handle_call(:close, _from, state) do
    %ThumbnailGenerator{ref: ref} = state.gen
    :exec.send(ref, :eof)
    {:reply, :ok, state}
  end

  def handle_call({:exec_send, data}, _from, state) do
    %ThumbnailGenerator{ref: ref} = state.gen
    :exec.send(ref, data)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:stderr, _ref, _msg}, state) do
    {:noreply, state}
  end

  def handle_info({:stdout, ref, bin}, state) do
    %ThumbnailGenerator{ref: ^ref, caller: caller} = state.gen

    case bin do
      <<@png_begin, _rest::binary>> ->
        Logger.info("image #{state.count + 1} received")

        if state.current do
          send(caller, {ref, :image, state.count, encode_current(state)})
        end

        {:noreply, %{state | count: state.count + 1, current: [bin]}}

      _ ->
        {:noreply, %{state | current: [bin | state.current]}}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    %{gen: %ThumbnailGenerator{ref: gen_ref, caller: caller}} = state

    cond do
      pid === caller ->
        Logger.info("Caller #{inspect(pid)} went away: #{inspect(reason)}")
        {:stop, {:shutdown, reason}, state}

      ref === gen_ref ->
        if state.count == 0 do
          Logger.info("Finished without generating any thumbnails: #{inspect(reason)}")
          send(caller, {ref, :exit, reason})
        else
          Logger.info("Finished generating #{state.count} thumbnail(s)")
          send(caller, {ref, :image, state.count, encode_current(state)})
          send(caller, {ref, :ok, state.count})
        end

        {:stop, :normal, state}
    end
  end

  defp encode_current(state) do
    state.current |> Enum.reverse() |> IO.iodata_to_binary() |> Base.encode64()
  end

  defp exec(cmd) do
    :exec.run(cmd, [:stdin, :stdout, :stderr, :monitor])
  end

  defp each_part(binary, max_size, func) when is_binary(binary) and is_integer(max_size) do
    case binary do
      <<>> ->
        :ok

      part when byte_size(part) <= max_size ->
        func.(part)

      <<part::binary-size(max_size), rest::binary>> ->
        func.(part)
        each_part(rest, max_size, func)
    end
  end

  defp exec_send(%ThumbnailGenerator{pid: pid, ref: ref}, data) do
    if node(pid) === node() do
      :exec.send(ref, data)
    else
      GenServer.call(pid, {:exec_send, data})
    end
  end
end
