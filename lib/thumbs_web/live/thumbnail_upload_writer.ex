defmodule ThumbsWeb.ThumbnailUploadWriter do
  @behaviour Phoenix.LiveView.UploadWriter

  alias Thumbs.ThumbnailGenerator

  @impl true
  def init(opts) do
    generator = Dragonfly.call(fn -> ThumbnailGenerator.open(opts) end, log: :debug)
    {:ok, %{gen: generator}}
  end

  @impl true
  def write_chunk(data, state) do
    Node.spawn(node(state.gen.pid), fn ->
      ThumbnailGenerator.send_chunk(state.gen, data)
    end)
    {:ok, state}
  end

  @impl true
  def meta(state), do: %{gen: state.gen}

  @impl true
  def close(state, _reason) do
    Process.unlink(state.gen.pid)
    Node.spawn(node(state.gen.pid), fn ->
      ThumbnailGenerator.close(state.gen)
    end)
    {:ok, state}
  end
end
