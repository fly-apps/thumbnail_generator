defmodule ThumbsWeb.ThumbnailUploadWriter do
  @behaviour Phoenix.LiveView.UploadWriter

  alias Thumbs.ThumbnailGenerator

  @impl true
  def init(opts) do
    generator = Dragonfly.call(Thumbs.FFMpegRunner, fn -> ThumbnailGenerator.open(opts) end)
    {:ok, %{gen: generator}}
  end

  @impl true
  def write_chunk(data, state) do
    ThumbnailGenerator.stream_chunk!(state.gen, data)
    {:ok, state}
  end

  @impl true
  def meta(state), do: %{gen: state.gen}

  @impl true
  def close(state, _reason) do
    ThumbnailGenerator.close(state.gen)
    {:ok, state}
  end
end
