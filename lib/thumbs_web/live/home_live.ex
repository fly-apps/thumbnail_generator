defmodule ThumbsWeb.VideoUploadWriter do
  @behaviour Phoenix.LiveView.UploadWriter

  @impl true
  def init(_opts) do
    with {:ok, path} <- Plug.Upload.random_file("live_view_upload"),
         {:ok, file} <- File.open(path, [:binary, :write]) do
      {:ok, %{path: path, file: file}}
    end
  end

  @impl true
  def meta(state) do
    %{path: state.path}
  end

  @impl true
  def write_chunk(data, state) do
    case IO.binwrite(state.file, data) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def close(state, _reason) do
    case File.close(state.file) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule ThumbsWeb.HomeLive do
  use ThumbsWeb, :live_view

  def render(assigns) do
    ~H"""
    <.form for={%{}} phx-change="validate" phx-submit="save">
      <%= inspect(@uploads.video.errors) %>
      <.live_file_input upload={@uploads.video} />
      <div :for={entry <- @uploads.video.entries}>
        <%= entry.progress %>
      </div>
    </.form>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> allow_upload(:video,
       accept: ~w(.mp4 .mpeg .mov),
       max_file_size: 524_288_000,
       max_entries: 1,
       writer: &upload_writer/3,
       auto_upload: true
     )}
  end

  defp upload_writer(:video, entry, _socket) do
    {ThumbsWeb.VideoUploadWriter, entry: entry}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end
end
