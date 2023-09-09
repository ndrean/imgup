defmodule AppWeb.ImgupNoClientLive do
  use AppWeb, :live_view
  alias Vix.Vips.Operation
  require Logger

  @upload_dir Application.app_dir(:app, ["priv", "static", "image_uploads"])

  @impl true
  def mount(_params, _session, socket) do
    File.mkdir_p(@upload_dir)

    socket =
      socket
      |> assign(:uploaded_files_locally, [])
      |> assign(:uploaded_files_to_S3, [])
      |> allow_upload(:image_list,
        accept: ~w(image/*),
        max_entries: 10,
        chunk_size: 64_000,
        auto_upload: true,
        max_file_size: 5_000_000,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  # With `auto_upload: true`, we can consume files here
  def handle_progress(:image_list, entry, socket) when entry.done? == false do
    # loop while receiving chunks
    {:noreply, socket}
  end

  def handle_progress(:image_list, entry, socket) when entry.done? do
    uploaded_file =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        client_name = clean_name(entry.client_name)
        # Copying the file from temporary system folder to static folder
        dest_file = build_dest(client_name)

        File.stream!(path, [], 64_000)
        |> Stream.into(File.stream!(dest_file))
        |> Stream.run()

        ext = Path.extname(client_name)
        compressed_name = comp_name(client_name)
        comp_dest = build_dest(compressed_name)
        pid = self()

        Task.start(fn -> compress_image(pid, dest_file, comp_dest, entry.uuid, ext) end)

        # Adding properties to the entry.

        updated_map = %{
          image_url: set_image_url(client_name),
          client_name: client_name,
          compressed_path: nil,
          errors: []
        }

        {:ok, Map.merge(entry, updated_map)}
      end)

    {:noreply, update(socket, :uploaded_files_locally, &(&1 ++ [uploaded_file]))}
  end

  def compress_image(pid, dest_file, comp_dest, uuid, ".png") do
    case Operation.thumbnail(dest_file, 100) do
      # case Image.new_from_file(dest) do
      {:ok, img} ->
        Operation.pngsave(img, comp_dest, compression: 9)
        send(pid, {:compressed, comp_dest, uuid})

      {:error, msg} ->
        send(pid, {:compressed_error, msg})
    end
  end

  def compress_image(pid, dest_file, comp_dest, uuid, ext) when ext in [".jpg", ".jpeg"] do
    # case Image.new_from_file(dest) do
    case Operation.thumbnail(dest_file, 100) do
      {:ok, img} ->
        Operation.jpegsave(img, comp_dest, Q: 7)
        send(pid, {:compressed, comp_dest, uuid})

      {:error, msg} ->
        send(pid, {:compressed_error, msg})
    end
  end

  def compress_image(pid, _, _, _, _) do
    send(pid, {:compressed_error, "format not handled"})
  end

  @impl true
  def handle_info({:compressed_error, msg}, socket) do
    {:noreply, put_flash(socket, :error, inspect(msg))}
  end

  # update the socket once the compression is done
  @impl true
  def handle_info({:compressed, path, uuid}, socket) do
    local_images = socket.assigns.uploaded_files_locally
    img = find_image(local_images, uuid)
    img = Map.put(img, :compressed_path, path)

    {:noreply,
     socket
     |> update(
       :uploaded_files_locally,
       &find_and_replace(&1, uuid, img)
     )}
  end

  # payload is:
  # %{
  #   source: :compressed or :original,
  #   url: "https://s3.eu-west-3.amazonaws.com/....jpg",
  #   uuid: "32e6056e-52d8-4f88-8c7c-321388ec88d6"
  # }

  # success callback from "upload" for compressed file: merge with "original" file data
  @impl true
  def handle_info({:bucket_success, %{source: :original} = payload}, socket) do
    IO.puts("original")
    %{url: url, uuid: uuid} = payload
    # clean temporary list display
    local_images = socket.assigns.uploaded_files_locally
    img = find_image(local_images, uuid)

    updated_local_array =
      if img,
        do: List.delete(local_images, img),
        else: local_images

    # update remote uploaded list
    body = %{origin_url: url, compressed_url: nil, uuid: uuid}
    remote_images = socket.assigns.uploaded_files_to_S3

    updated_list =
      case Enum.find_index(remote_images, &(&1.uuid == uuid)) do
        nil -> [body | remote_images]
        id -> List.update_at(remote_images, id, &Map.merge(&1, %{origin_url: url}))
      end

    socket =
      socket
      |> assign(:uploaded_files_to_S3, updated_list)
      |> assign(:uploaded_files_locally, updated_local_array)

    {:noreply, socket}
  end

  # success callback from "upload" for compressed file: merge with "original" file data
  @impl true
  def handle_info({:bucket_success, %{source: :compressed} = payload}, socket) do
    IO.puts("compressed")
    %{url: url, uuid: uuid} = payload
    # clean temporary list display
    local_images = socket.assigns.uploaded_files_locally
    img = find_image(local_images, uuid)

    updated_local_array =
      if img,
        do: List.delete(socket.assigns.uploaded_files_locally, img),
        else: local_images

    # update remote uploaded list
    body = %{origin_url: nil, compressed_url: url, uuid: uuid}

    remote_images =
      socket.assigns.uploaded_files_to_S3

    updated_list =
      case Enum.find_index(remote_images, &(&1.uuid == uuid)) do
        nil -> [body | remote_images]
        id -> List.update_at(remote_images, id, &Map.merge(&1, %{compressed_url: url}))
      end

    socket =
      assign(socket, %{
        uploaded_files_to_S3: updated_list,
        uploaded_files_locally: updated_local_array
      })

    {:noreply, socket}
  end

  # error callback from the "upload"
  @impl true
  def handle_info({:bucket_error, reason, uuid}, socket) do
    Logger.debug(inspect(reason))
    # Update the failed local file element to show an error message
    local_images = socket.assigns.uploaded_files_locally
    file_element = find_image(local_images, uuid)
    index = Enum.find_index(local_images, &(&1 == file_element))
    updated_file_element = Map.put(file_element, :errors, ["#{reason}"])

    updated_local_array =
      List.replace_at(local_images, index, updated_file_element)

    {:noreply, assign(socket, :uploaded_files_locally, updated_local_array)}
    {:noreply, put_flash(socket, :error, "error from bucket")}
  end

  # response to the JS hook to capture page size
  @impl true
  def handle_event("page-size", p, socket) do
    {:noreply, assign(socket, :screen, p)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  # trigger by the "upload" button
  @impl true
  def handle_event("upload_to_s3", %{"uuid" => uuid}, socket) do
    # Get file element from the local files array
    %{
      client_name: client_name,
      client_type: client_type,
      compressed_path: compressed_path,
      uuid: uuid
    } =
      find_image(socket.assigns.uploaded_files_locally, uuid)

    # Create original file object and compressed file object to upload
    file =
      %{
        path: build_dest(client_name),
        content_type: client_type
      }

    file_comp = %{
      path: compressed_path,
      content_type: client_type
    }

    # run HTTP call concurrently
    pid = self()
    Task.start(fn -> upload(pid, file, uuid, :original) end)
    Task.start(fn -> upload(pid, file_comp, uuid, :compressed) end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove-selected", %{"key" => uuid}, socket) do
    {:noreply,
     socket
     |> update(:uploaded_files_locally, &Enum.filter(&1, fn img -> img.uuid != uuid end))}
  end

  def upload(pid, file, uuid, atom) do
    case App.Upload.upload(file) do
      {:ok, body} ->
        File.rm!(file.path)
        send(pid, {:bucket_success, Map.merge(body, %{uuid: uuid, source: atom})})

      {:error, msg} ->
        send(pid, {:bucket_error, msg, uuid})
    end
  end

  # utilities
  def find_and_replace(images, uuid, img) do
    Enum.map(images, fn image -> if image.uuid == uuid, do: img, else: image end)
  end

  def find_image(images, img_uuid) do
    Enum.find(images, fn %{uuid: uuid} ->
      uuid == img_uuid
    end)
  end

  def set_image_url(name) do
    AppWeb.Endpoint.url() <>
      AppWeb.Endpoint.static_path("/image_uploads/#{name}")
  end

  def url_path(name) do
    AppWeb.Endpoint.static_path("/image_uploads/#{name}")
  end

  def clean_name(name) do
    ext = Path.extname(name)
    rootname = name |> Path.rootname() |> String.replace(" ", "") |> String.replace(".", "")
    rootname <> ext
  end

  def build_dest(name),
    do: Application.app_dir(:app, ["priv", "static", "image_uploads", name])

  def thumb_name(name), do: Path.rootname(name) <> "-th" <> Path.extname(name)
  def comp_name(name), do: Path.rootname(name) <> "-comp" <> Path.extname(name)
end

# entry -
# %Phoenix.LiveView.UploadEntry{
#   progress: 100,
#   preflighted?: true,
#   upload_config: :image_list,
#   upload_ref: "phx-F4Ieh9a692sakgnC",
#   ref: "0",
#   uuid: "eed07cd0-e686-4ba7-b405-02f1304478c7",
#   valid?: true,
#   done?: true,
#   cancelled?: false,
#   client_name: "Screenshot 2023-09-04 at 14.56.47.png",
#   client_relative_path: "",
#   client_size: 594354,
#   client_type: "image/png",
#   client_last_modified: 1693832212932
# }

# file_element
# %{
#   progress: 100,
#   __struct__: Phoenix.LiveView.UploadEntry,
#   errors: [],
#   valid?: true,
#   ref: "0",
#   client_size: 2504782,
#   client_name: "action.jpg",
#   client_type: "image/jpeg",
#   uuid: "38809d8d-e080-4f14-a137-13e50cd23c56",
#   compressed_path: "/Users/nevendrean/code/elixir/imgup/_build/dev/lib/app/priv/static/image_uploads/action-comp.jpg",
#   done?: true,
#   image_url: "http://localhost:4000/image_uploads/action.jpg",
#   compressed_name: "action-comp.jpg",
#   upload_ref: "phx-F4JGIKN9v6ORWQXC",
#   preflighted?: true,
#   upload_config: :image_list,
#   cancelled?: false,
#   client_last_modified: 1693731232407,
#   client_relative_path: ""
# }
