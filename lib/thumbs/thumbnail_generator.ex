defmodule Thumbs.ThumbnailGenerator do
  @png_begin <<137, 80, 78, 71, 13, 10, 26, 10>>

  require Logger

  alias Thumbs.ThumbnailGenerator

  defstruct ref: nil, exec_pid: nil, caller: nil, pid: nil

  def open(opts \\ []) do
    Keyword.validate!(opts, [:timeout, :caller, :fps])
    count = Keyword.get(opts, :fps, 60)
    timeout = Keyword.get(opts, :timeout, 5_000)
    caller = Keyword.get(opts, :caller, self())
    parent_ref = make_ref()
    parent = self()

    Task.Supervisor.start_child(Thumbs.TaskSup, fn ->
      case exec("ffmpeg -i pipe:0 -vf \"fps=1/#{count}\" -f image2pipe -c:v png -") do
        {:ok, pid, ref} ->
          gen = %ThumbnailGenerator{ref: ref, exec_pid: pid, pid: self(), caller: caller}
          send(parent, {parent_ref, gen})
          receive_images(gen, %{count: 0, current: nil})

        other ->
          exit(other)
      end
    end)

    receive do
      {^parent_ref, %ThumbnailGenerator{} = gen} -> gen
    after
      timeout -> exit(:timeout)
    end
  end

  def send_chunk(%ThumbnailGenerator{exec_pid: pid}, chunk) do
    :exec.send(pid, chunk)
  end

  def close(%ThumbnailGenerator{exec_pid: pid}) do
    :exec.send(pid, :eof)
  end

  defp receive_images(%ThumbnailGenerator{ref: ref, caller: caller} = gen, state) do
    receive do
      {:stderr, ^ref, _} ->
        receive_images(gen, state)

      {:stdout, ^ref, bin} ->
        case bin do
          <<@png_begin, _rest::binary>> ->
            Logger.debug("image #{state.count + 1} received")

            if state.current do
              send(caller, {ref, :image, state.count, encode_current(state)})
            end

            receive_images(gen, %{state | count: state.count + 1, current: [bin]})

          _ ->
            receive_images(gen, %{state | current: [bin | state.current]})
        end

      {:DOWN, ^ref, :process, _pid, reason} ->
        if state.count == 0 do
          Logger.debug("Finished without generating any thumbnails: #{inspect(reason)}")
          send(caller, {ref, :exit, reason})
        else
          Logger.debug("Finished generating #{state.count} thumbnail(s)")
          send(caller, {ref, :image, state.count, encode_current(state)})
          send(caller, {ref, :ok, state.count})
        end
    end
  end

  defp encode_current(state) do
    state.current |> Enum.reverse() |> IO.iodata_to_binary() |> Base.encode64()
  end

  defp exec(cmd) do
    :exec.run(cmd, [:stdin, :stdout, :stderr, :monitor])
  end
end
