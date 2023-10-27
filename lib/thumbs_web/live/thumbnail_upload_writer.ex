defmodule ThumbsWeb.ThumbnailUploadWriter do
  @behaviour Phoenix.LiveView.UploadWriter

  alias Thumbs.ThumbnailGenerator

  @impl true
  def init(opts) do
    generator = ThumbnailGenerator.open(opts)
    {:ok, %{gen: generator}}
  end

  @impl true
  def meta(state), do: %{gen: state.gen}

  @impl true
  def write_chunk(data, state) do
    ThumbnailGenerator.send_chunk(state.gen, data)
    {:ok, state}
  end

  @impl true
  def close(state, _reason) do
    Process.unlink(state.gen.pid)
    ThumbnailGenerator.close(state.gen)
    {:ok, state}
  end
end
