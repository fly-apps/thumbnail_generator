defmodule Thumbs.ThumbnailGenerator do
  @png_begin <<137, 80, 78, 71, 13, 10, 26, 10>>

  require Logger

  alias Thumbs.ThumbnailGenerator

  defstruct ref: nil, exec_pid: nil, caller: nil, pid: nil

  def open(count, timeout \\ 5000) when is_integer(count) do
    caller_ref = make_ref()
    caller = self()

    {:ok, _pid} =
      Task.start_link(fn ->
        result =
          :exec.run("ffmpeg -i pipe:0 -vf \"fps=1/#{count}\" -f image2pipe -c:v png -", [
            :stdin,
            :stdout,
            :stderr,
            :monitor
          ])

        case result do
          {:ok, pid, ref} ->
            gen = %ThumbnailGenerator{ref: ref, exec_pid: pid, pid: self(), caller: caller}
            send(caller, {caller_ref, gen})
            receive_images(gen, %{count: 0, current: nil})

          other ->
            exit(other)
        end
      end)

    receive do
      {^caller_ref, %ThumbnailGenerator{} = gen} -> gen
    after
      timeout -> exit(:timeout)
    end
  end

  def send_chunk(%ThumbnailGenerator{ref: ref}, chunk) do
    :exec.send(ref, chunk)
  end

  def close(%ThumbnailGenerator{ref: ref}) do
    :exec.send(ref, :eof)
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
              encoded =
                state.current |> Enum.reverse() |> IO.iodata_to_binary() |> Base.encode64()

              send(caller, {ref, :image, state.count, encoded})
            end

            receive_images(gen, %{state | count: state.count + 1, current: [bin]})

          _ ->
            receive_images(gen, %{state | current: [bin | state.current]})
        end

      {:DOWN, ^ref, :process, _, reason} ->
        if state.count == 0 do
          Logger.debug("Finished without generating any thumbnails: #{inspect(reason)}")
          send(caller, {ref, :exit, reason})
        else
          Logger.debug("Finished generated #{state.count - 1} thumbnail(s)")
          send(caller, {ref, :ok, state.count - 1})
        end
    end
  end
end
