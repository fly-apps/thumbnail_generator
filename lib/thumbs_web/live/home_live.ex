defmodule ThumbsWeb.HomeLive do
  use ThumbsWeb, :live_view

  def render(assigns) do
    ~H"""
    <.form for={%{}} phx-change="validate" phx-submit="save">
      <div class="space-y-4 relative">
        <h1 class="text-xl"><%= @message %></h1>
        <.live_file_input upload={@uploads.video} />
        <div :for={entry <- @uploads.video.entries}>
          <div class="w-full bg-gray-200 rounded-full h-2.5">
            <div class="bg-blue-600 h-2.5 rounded-full" style={"width: #{entry.progress}%"}></div>
          </div>
        </div>

        <div id="thumbs" phx-update="stream" class="grid grid-cols-3 gap-2">
          <img
            :for={{id, %{encoded: encoded}} <- @streams.thumbs}
            id={id}
            src={"data:image/png;base64," <> encoded}
            class="rounded-md"
          />
        </div>
      </div>
    </.form>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(message: "Select a file to generate thumbnails", count: 0)
     |> stream(:thumbs, [])
     |> allow_upload(:video,
       accept: ~w(.mp4 .mpeg .mov),
       max_file_size: 524_288_000,
       max_entries: 1,
       chunk_size: 1_048_576, # 1mb
       writer: fn _, entry, _socket ->
         fps = if entry.client_size < 20_971_520, do: 10, else: 60
         {ThumbsWeb.ThumbnailUploadWriter, caller: self(), fps: fps}
       end,
       auto_upload: true
     )}
  end

  def handle_info({_ref, :image, _count, encoded}, socket) do
    %{count: count} = socket.assigns

    {:noreply,
     socket
     |> assign(count: count + 1, message: "Generating thumbnails (#{count + 1})")
     |> stream_insert(:thumbs, %{id: count, encoded: encoded})}
  end

  def handle_info({_ref, :ok, total_count}, socket) do
    consume_uploaded_entries(socket, :video, fn meta, _entry -> {:ok, meta} end)
    {:noreply, assign(socket, message: "#{total_count} thumbnails generated!")}
  end

  def handle_event("validate", _params, socket) do
    {:noreply,
     socket
     |> stream(:thumbs, [], reset: true)
     |> assign(count: 0, message: "Generating thumbnails...")}
  end
end
