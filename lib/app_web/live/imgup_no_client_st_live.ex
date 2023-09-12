defmodule AppWeb.ImgupNoClientStLive do
  use AppWeb, :live_view
  alias App.Gallery.Url
  alias App.Repo

  alias Vix.Vips.Image
  alias Vix.Vips.Operation

  on_mount AppWeb.UserNoClientInit
  require Logger

  # @upload_dir Application.app_dir(:app, ["priv", "static", "image_uploads"])
  @thumb_size 200

  @delete_bucket_and_db "Sucessfully deleted from bucket and database"
  @error_delete_object_in_bucket "Failed to delete from bucket"
  @error_saving_in_bucket "Could not save in the bucket"
  @error_in_db_but_deleted_from_bucket "Object deleted in bucket but not found in database"
  @inserted_in_bucket_but_db_failed "Object save in bucket but failed in db"
  @timeout_bucket "Upload to bucket, timeout"

  @impl true
  def mount(_, _, socket) do
    current_user = socket.assigns.current_user

    init_assigns = %{
      limit: 4,
      page: 0,
      offset: 3,
      uploaded_files_locally: []
    }

    socket =
      socket
      |> assign_new(:current_user, fn -> current_user end)
      |> assign(init_assigns)
      |> allow_upload(:image_list,
        accept: ~w(image/*),
        max_entries: 10,
        chunk_size: 128_000,
        auto_upload: true,
        max_file_size: 5_000_000,
        progress: &handle_progress/3
      )
      |> stream_configure(:uploaded_files_to_S3, dom_id: &"uploaded-s3-#{&1.uuid}")
      |> paginate(0)
      |> push_event("screen", %{})

    {:ok, socket}

    # Do not define presign_upload. This will create a local photo in /vars
  end

  def paginate(socket, page) do
    %{limit: limit, offset: offset, current_user: current_user} = socket.assigns
    files = App.Gallery.get_limited_urls_by_user(current_user, limit, page * offset)
    stream(socket, :uploaded_files_to_S3, files, at: -1)
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

        # ext = Path.extname(client_name)
        pid = self()
        screen = socket.assigns.screen

        Task.start(fn ->
          compress_image(pid, client_name, entry.uuid, screen)
        end)

        # Adding properties to the entry.
        # image_url : to render link & img for preload

        # updated_map = %{
        #   image_url: set_image_url(client_name),
        #   compressed_url: nil,
        #   client_name: client_name,
        #   compressed_path: nil,
        #   errors: []
        # }
        updated_map = %{
          image_url: nil,
          compressed_url: nil,
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
  def compress_image(pid, client_name, uuid, screen) do
    # %{"screenHeight" => h, "screenWidth" => w} = screen

    dest_path = build_path(client_name)

    # "/Users/nevendrean/code/elixir/imgup/_build/dev/lib/app/priv/static/image_uploads/Screenshot2023-08-04at210431.png"

    thumb_name = thumb_name(client_name)

    # "Screenshot2023-08-04at210431-th.webp"

    thumb_path = thumb_name(client_name) |> build_path()

    # "/Users/nevendrean/code/elixir/imgup/_build/dev/lib/app/priv/static/image_uploads/Screenshot2023-08-04at210431-th.webp"

    rename_to_webp = (client_name |> Path.rootname()) <> ".webp"
    # "Screenshot2023-08-04at210431.webp"

    resized_name = build_path("resized-" <> rename_to_webp)

    # "/Users/nevendrean/code/elixir/imgup/_build/dev/lib/app/priv/static/image_uploads/resized-Screenshot2023-08-04at210431.webp"

    with {:ok, img_origin} <- Image.new_from_file(dest_path),
         scale <- get_scale(img_origin, screen),
         {:ok, img_resized} <- Operation.resize(img_origin, scale),
         :ok <- Operation.webpsave(img_resized, resized_name),
         {:ok, img_thumb} <- Operation.thumbnail(dest_path, @thumb_size),
         :ok <- Operation.webpsave(img_thumb, thumb_path) do
      send(pid, {:compression_op, thumb_name, resized_name, uuid})
    else
      {:error, msg} ->
        Logger.warning(msg)
        send(pid, {:compressed_error, msg})
    end
  end

  def get_scale(img, screen) do
    %{"screenHeight" => h, "screenWidth" => w} = screen
    h_origin = Image.height(img)
    w_origin = Image.width(img)
    hscale = if h < h_origin, do: h / h_origin, else: 1
    wscale = if w < w_origin, do: w / w_origin, else: 1
    min(hscale, wscale)
  end

  # callback from "thumbnailing" operation to update the socket
  @impl true
  def handle_info({:compressed_error, msg}, socket) do
    {:noreply, put_flash(socket, :error, inspect(msg))}
  end

  # update the socket once the compression is done with the thumbnail path
  @impl true
  def handle_info({:compression_op, thumb_name, resized_name, uuid}, socket) do
    local_images = socket.assigns.uploaded_files_locally
    resized_url = resized_name |> Path.basename() |> set_image_url()

    img = find_image(local_images, uuid)

    img =
      Map.merge(img, %{
        compressed_path: build_path(thumb_name),
        compressed_url: set_image_url(thumb_name),
        image_url: resized_url,
        resized_name: resized_name,
        client_type: "image/webp"
      })

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
    data =
      Map.new()
      |> Map.put(:origin_url, map.origin_url)
      |> Map.put(:compressed_url, map.compressed_url)
      |> Map.put(:uuid, map.uuid)

    new_file =
      %Phoenix.LiveView.UploadEntry{}
      |> Map.merge(data)

    current_user = socket.assigns.current_user
    data = Map.put(data, :user_id, current_user.id)

    %Url{}
    |> Url.changeset(data)
    |> Repo.insert()
    |> case do
      {:ok, _} ->
        {:noreply, stream_insert(socket, :uploaded_files_to_S3, new_file)}

      {:error, _msg} ->
        {:noreply, put_flash(socket, :error, @inserted_in_bucket_but_db_failed)}
    end
  end

  # callback error upload to S3
  @impl true
  def handle_info({:upload_error}, socket) do
    {:noreply, put_flash(socket, :error, @error_saving_in_bucket)}
  end

  # callback from successfull deletion from bucket
  @impl true
  def handle_info({:success_deletion_from_bucket, dom_id, uuid}, socket) do
    alias App.Gallery.Url
    alias App.Repo

    Repo.transaction(fn repo ->
      data = repo.get_by(Url, %{uuid: uuid})

      case data do
        nil ->
          {:error, :not_found_in_database}

        data ->
          repo.delete(data)
      end
    end)
    |> case do
      {:ok, {:ok, _}} ->
        {:noreply,
         socket
         |> put_flash(:info, @delete_bucket_and_db)
         |> stream_delete_by_dom_id(:uploaded_files_to_S3, dom_id)}

      {:ok, {:error, msg}} ->
        Logger.warning("transaction delete failed " <> inspect(msg))

        {:noreply,
         socket
         |> put_flash(:error, @error_in_db_but_deleted_from_bucket)}
    end
  end

  # callback from deletion failure from bucket
  @impl true
  def handle_info({:failed_deletion_from_bucket}, socket) do
    Logger.warning("failed_deletion_from_bucket")
    {:noreply, put_flash(socket, :error, @error_delete_object_in_bucket)}
  end

  @impl true
  def handle_info({:rm_error, msg}, socket) do
    {:noreply, put_flash(socket, :error, msg)}
  end

  @impl true
  def handle_event("load-more", _, socket) do
    {:noreply,
     socket
     |> update(:page, &(&1 + 1))
     |> paginate(socket.assigns.page + 1)}
  end

  # response to the JS hook to capture page size
  @impl true
  def handle_event("page-size", p, socket) do
    # %{"screenHeight" => h, "screenWidth" => w} = p
    Logger.info(p)
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
      # client_name: client_name,
      resized_name: resized_name,
      client_type: client_type,
      compressed_path: compressed_path,
      uuid: uuid,
      client_name: client_name
    } =
      find_image(socket.assigns.uploaded_files_locally, uuid)

    # Create 1) original file object and 2) thumbnail/compressed file object to upload
    file =
      %{
        path: resized_name,
        content_type: "image/webp"
      }

    file_comp =
      %{
        path: compressed_path,
        content_type: client_type
      }

    # concurrently upload the 2 files to the bucket
    pid = self()
    Task.start(fn -> upload(pid, client_name, file, file_comp, uuid) end)

    {:noreply,
     socket
     |> update(:uploaded_files_locally, fn list -> Enum.filter(list, &(&1.uuid != uuid)) end)}
  end

  def handle_event(
        "delete-uploaded",
        %{"key" => dom_id, "origin" => origin, "thumb" => thumb, "uuid" => uuid},
        socket
      ) do
    pid = self()
    keys_to_delete = [Path.basename(origin), Path.basename(thumb)]

    keys_to_delete
    |> Task.async_stream(fn key ->
      ExAws.S3.delete_object(bucket(), key)
      |> ExAws.request!()
    end)
    |> Stream.run()

    # verify that objects are removed
    Task.start(fn ->
      check_list =
        ExAws.S3.list_objects(bucket())
        |> ExAws.request!()
        |> Enum.filter(&Enum.member?(keys_to_delete, &1))

      case length(check_list) do
        0 ->
          send(pid, {:success_deletion_from_bucket, dom_id, uuid})

        _ ->
          send(pid, {:failed_deletion_from_bucket})
      end
    end)

    {:noreply, socket}
  end

  # rm files from server when unselected
  @impl true
  def handle_event("remove-selected", %{"key" => uuid}, socket) do
    %{
      compressed_path: comp_path,
      client_name: client_name,
      resized_name: resized_name
    } =
      socket.assigns.uploaded_files_locally
      |> Enum.find(&(&1.uuid == uuid))

    pid = self()

    [comp_path, resized_name, build_path(client_name)]
    |> Task.async_stream(&remove_safely(pid, &1))
    |> Stream.run()

    {:noreply,
     socket
     |> update(:uploaded_files_locally, &Enum.filter(&1, fn img -> img.uuid != uuid end))}
  end

  def remove_safely(pid, file) do
    case File.rm(file) do
      :ok ->
        :ok

      {:error, msg} ->
        send(pid, {:rm_error, msg})
    end
  end

  # In Task.async_stream, use "on_timeout: :kill_task" to intercept the timeout error
  def upload(pid, client_name, file, file_comp, uuid) do
    [file, file_comp]
    |> Task.async_stream(&App.Upload.upload/1, on_timeout: :kill_task)
    |> Enum.map(&handle_async_result/1)
    |> Enum.reduce([], fn res, acc ->
      case res do
        {:ok, url} ->
          [url | acc]

        {:error, msg} ->
          [{:error, msg} | acc]
      end
    end)
    |> handle_result(pid, uuid)

    pid = self()
    # cleanup the server
    [file.path, file_comp.path, build_path(client_name)]
    |> Task.async_stream(&remove_safely(pid, &1))
    |> Stream.run()
  end

  def handle_result([{:error, _}, {:error, _}], pid, _uuid) do
    send(pid, {:upload_error})
  end

  # remove the thumbnail from the bucket
  def handle_result([url, {:error, msg}], pid, _uuid) do
    Logger.warning("Upload error: " <> inspect(msg))

    Task.start(fn ->
      ExAws.S3.delete_object(bucket(), Path.basename(url))
      |> ExAws.request!()
    end)

    send(pid, {:upload_error})
  end

  # remove the thumbnail from the bucket
  def handle_result([{:error, msg}, url], pid, uuid) do
    handle_result([url, {:error, msg}], pid, uuid)
  end

  def handle_result([thumb_url, origin_url], pid, uuid) do
    send(
      pid,
      {:bucket_success, %{origin_url: origin_url, compressed_url: thumb_url, uuid: uuid}}
    )
  end

  # transform the map
  def handle_async_result({:ok, {:ok, %{url: url}}}), do: {:ok, url}
  def handle_async_result({:ok, {:error, :upload_fail}}), do: {:error, :bucket_error}
  def handle_async_result({:ok, {:error, :failure_read}}), do: {:error, :failure_read}
  def handle_async_result({:error, _msg}), do: {:error, :upload_error}
  def handle_async_result({:exit, :timeout}), do: {:error, @timeout_bucket}

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

  def build_path(name),
    do: Application.app_dir(:app, ["priv", "static", "image_uploads", name])

  # def thumb_name(name), do: Path.rootname(name) <> "-th" <> Path.extname(name)
  def thumb_name(name), do: Path.rootname(name) <> "-th" <> ".webp"

  defp bucket do
    Application.get_env(:ex_aws, :original_bucket)
  end
end

# entry -
# %Phoenix.LiveView.UploadEntry{
#   progress: 100,
#   preflighted?: true,
#   upload_config: :image_list,
#   upload_ref: "phx-F4NSgF6BAJ2Dng8C",
#   ref: "0",
#   uuid: "808e6ae7-c6fe-4f8e-acdb-812497b4fe0f",
#   valid?: true,
#   done?: true,
#   cancelled?: false,
#   client_name: "Screenshot 2023-06-06 at 17.52.01.png",
#   client_relative_path: "",
#   client_size: 99767,
#   client_type: "image/png",
#   client_last_modified: 1686066727004
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
