defmodule AppWeb.ImgupNoClientStLive do
  use AppWeb, :live_view
  alias Vix.Vips.Operation
  require Logger

  @upload_dir Application.app_dir(:app, ["priv", "static", "image_uploads"])

  @impl true
  def mount(_, %{"user_token" => user_token}, socket) do
    File.mkdir_p(@upload_dir)

    socket =
      socket
      |> assign_new(:current_user, fn ->
        App.Accounts.get_user_by_session_token(user_token)
      end)
      |> assign(:uploaded_files_locally, [])
      |> allow_upload(:image_list,
        accept: ~w(image/*),
        max_entries: 10,
        chunk_size: 64_000,
        auto_upload: true,
        max_file_size: 5_000_000,
        progress: &handle_progress/3
      )
      |> stream_configure(:uploaded_files_to_S3, dom_id: &"uploaded-s3-#{&1.uuid}")
      |> stream(:uploaded_files_to_S3, [], at: -1, limit: 2)

    {:ok, socket}

    # Do not define presign_upload. This will create a local photo in /vars
  end

  def list_files do
    []
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
        dest_path = build_path(client_name)

        File.stream!(path, [], 64_000)
        |> Stream.into(File.stream!(dest_path))
        |> Stream.run()

        ext = Path.extname(client_name)
        pid = self()

        Task.start(fn ->
          compress_image(pid, client_name, entry.uuid, ext)
        end)

        # Adding properties to the entry.
        # image_url : to render link & img for preload

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

  @doc """
  Saves on server in "/image_uploads" the thumbnail file
  """
  def compress_image(pid, client_name, uuid, ".png") do
    dest_path = build_path(client_name)
    thumb_path = thumb_name(client_name) |> build_path()

    case Operation.thumbnail(dest_path, 100) do
      {:ok, img} ->
        Operation.pngsave(img, thumb_path, compression: 9)
        send(pid, {:compression_op, thumb_path, uuid})

      {:error, msg} ->
        send(pid, {:compressed_error, msg})
    end
  end

  def compress_image(pid, client_name, uuid, ext)
      when ext in [".jpg", ".jpeg"] do
    dest_path = build_path(client_name)
    thumb_path = thumb_name(client_name) |> build_path()

    case Operation.thumbnail(dest_path, 100) do
      {:ok, img} ->
        Operation.jpegsave(img, thumb_path, Q: 7)
        send(pid, {:compression_op, thumb_path, uuid})

      {:error, msg} ->
        send(pid, {:compressed_error, msg})
    end
  end

  def compress_image(pid, _, _, _, _) do
    send(pid, {:compressed_error, "format not handled"})
  end

  # callback from "thumbnailing" operation to update the socket
  @impl true
  def handle_info({:compressed_error, msg}, socket) do
    {:noreply, put_flash(socket, :error, inspect(msg))}
  end

  # update the socket once the compression is done with the thumbnail path
  @impl true
  def handle_info({:compression_op, path, uuid}, socket) do
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

  # callback from successfull upload to S3 to update the stream and the db
  @impl true
  def handle_info({:bucket_success, map}, socket) do
    alias App.Gallery.Url

    data =
      Map.new()
      |> Map.put(:origin_url, map.origin_url)
      |> Map.put(:compressed_url, map.compressed_url)
      |> Map.put(:uuid, map.uuid)

    new_file =
      %Phoenix.LiveView.UploadEntry{}
      |> Map.merge(data)

    # |> Map.put(:origin_url, map.origin_url)
    # |> Map.put(:compressed_url, map.compressed_url)
    # |> Map.put(:uuid, map.uuid)

    current_user = socket.assigns.current_user |> dbg()
    data = Map.put(data, :user_id, current_user.id)

    %Url{}
    |> Url.changeset(data)
    |> App.Repo.insert()
    |> dbg()

    {:noreply, stream_insert(socket, :uploaded_files_to_S3, new_file)}
  end

  # callback error upload to S3
  @impl true
  def handle_info({:upload_error}, socket) do
    {:noreply, put_flash(socket, :error, "Could not save in the bucket")}
  end

  # callback from successfull deletion from bucket
  @impl true
  def handle_info({:success_deletion_from_bucket, dom_id, uuid}, socket) do
    alias App.Repo
    alias App.Gallery.Url
    IO.puts("success_deletion_from_bucket")

    transaction =
      Repo.transaction(fn repo ->
        data = repo.get_by(Url, %{uuid: uuid})

        case data do
          nil ->
            {:error, :not_found_in_database}

          data ->
            repo.delete(data)
        end
      end)

    case transaction do
      {:ok, {:ok, _}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sucessfully deleted from bucket")
         |> stream_delete_by_dom_id(:uploaded_files_to_S3, dom_id)}

      {:ok, {:error, msg}} ->
        Logger.warning(inspect(msg))

        {:noreply,
         socket
         |> put_flash(:error, "Object deleted from the bucket but Database error")}
    end
  end

  # callback from deletion failure from bucket
  @impl true
  def handle_info({:failed_deletion_from_bucket}, socket) do
    IO.puts("failed_deletion_from_bucket")
    {:noreply, put_flash(socket, :error, "Not able to delete from bucket")}
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

  # triggered by the "upload" button
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

    # Create 1) original file object and 2) thumbnail/compressed file object to upload
    file =
      %{
        path: build_path(client_name),
        content_type: client_type
      }

    file_comp = %{
      path: compressed_path,
      content_type: client_type
    }

    # concurrently upload the 2 files to the bucket
    pid = self()
    Task.start(fn -> upload(pid, file, file_comp, uuid) end)
    # {:ok, origin_url} = App.Upload.upload(file)
    # {:ok, compressed_url} = App.Upload.upload(file_comp)

    # new_file =
    #   %Phoenix.LiveView.UploadEntry{}
    #   |> Map.put(:origin_url, origin_url.url)
    #   |> Map.put(:compressed_url, compressed_url.url)
    #   |> Map.put(:uuid, uuid)

    # updated_local_files =
    #   socket.assigns.uploaded_files_locally
    #   |> Enum.filter(&(&1.uuid != uuid))

    {
      :noreply,
      socket
      |> update(:uploaded_files_locally, fn list -> Enum.filter(list, &(&1.uuid != uuid)) end)
      #  |> stream_insert(:uploaded_files_to_S3, new_file)
    }
  end

  def handle_event(
        "delete-uploaded",
        %{"key" => dom_id, "origin" => origin, "thumb" => thumb, "uuid" => uuid},
        socket
      ) do
    bucket = bucket()
    keys_to_delete = [Path.basename(origin), Path.basename(thumb)]
    pid = self()

    keys_to_delete
    |> Task.async_stream(fn key ->
      ExAws.S3.delete_object(bucket, key)
      |> ExAws.request!()
    end)
    |> Stream.run()

    check_list =
      ExAws.S3.list_objects(bucket)
      |> ExAws.request!()
      |> Enum.filter(&Enum.member?(keys_to_delete, &1))

    case length(check_list) do
      0 ->
        send(pid, {:success_deletion_from_bucket, dom_id, uuid})

      _ ->
        send(pid, {:failed_deletion_from_bucket})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove-selected", %{"key" => uuid}, socket) do
    {:noreply,
     socket
     |> update(:uploaded_files_locally, &Enum.filter(&1, fn img -> img.uuid != uuid end))}
  end

  def upload(pid, file, file_comp, uuid) do
    requests =
      [file, file_comp]
      |> Task.async_stream(&App.Upload.upload(&1))
      |> Enum.map(&handle_async_result/1)
      |> Enum.reduce([], fn res, acc ->
        case res do
          {:ok, url} ->
            [url | acc]

          {:error, _msg} ->
            {:error, :upload_error}
        end
      end)

    case requests do
      {:error, _} ->
        send(pid, {:upload_error})

      [thumb_url, origin_url] ->
        send(
          pid,
          {:bucket_success, %{origin_url: origin_url, compressed_url: thumb_url, uuid: uuid}}
        )
    end

    File.rm!(file.path)
    File.rm!(file_comp.path)
  end

  # transform the map
  def handle_async_result({:ok, {:ok, %{url: url}}}), do: {:ok, url}
  def handle_async_result({:error, _msg}), do: {:error, :upload_error}

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

  # def build_dest(name),
  #   do: Application.app_dir(:app, ["priv", "static", "image_uploads", name])

  def build_path(name),
    do: Application.app_dir(:app, ["priv", "static", "image_uploads", name])

  def thumb_name(name), do: Path.rootname(name) <> "-th" <> Path.extname(name)
  # def comp_name(name), do: Path.rootname(name) <> "-comp" <> Path.extname(name)

  defp bucket do
    Application.get_env(:ex_aws, :original_bucket)
  end
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
