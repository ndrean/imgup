defmodule Upload do
  defstruct [:uuid, :compressed_url, :origin_url]
end

defmodule AppWeb.ImgupNoClientStLive do
  use AppWeb, :live_view
  alias Vix.Vips.Operation
  require Logger

  @upload_dir Application.app_dir(:app, ["priv", "static", "image_uploads"])

  @impl true
  def render(assigns) do
    ~H"""
    <div
    id="lv_no_client"
    class="px-4 py-10 sm:px-6 sm:py-28 lg:px-8 xl:px-28 xl:py-32"
    phx-hook="ScreenSize"
    >
    <div class="flex flex-col justify-around md:flex-row">
    <AppWeb.UploadForm.render uploads={@uploads}/>
    <%!-- <div class="flex flex-col flex-1 md:mr-4">
      <!-- Drag and drop -->
      <div class="space-y-12">
        <div class="border-gray-900/10 pb-12">
          <h2 class="text-base font-semibold leading-7 text-gray-900">
            Image Upload <b>(without file upload from client-side code)</b>
          </h2>
          <p class="mt-1 text-sm leading-6 text-gray-400">
            The files uploaded in this page are not routed from the client. Meaning all file uploads are made in the LiveView code.
          </p>
          <p class="mt-1 text-sm leading-6 text-gray-600">
            Drag your images and they'll be uploaded to the cloud! ☁️
          </p>
          <p class="mt-1 text-sm leading-6 text-gray-600">
            You may add up to <%= @uploads.image_list.max_entries %> exhibits at a time.
          </p>
          <!-- File upload section -->
          <form
            class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8"
            phx-change="validate"
            phx-submit="save"
            id="upload-form"
          >
            <div class="col-span-full">
              <div
                class="mt-2 flex justify-center rounded-lg border border-dashed border-gray-900/25 px-6 py-10"
                phx-drop-target={@uploads.image_list.ref}
              >
                <div class="text-center">
                  <svg
                    class="mx-auto h-12 w-12 text-gray-300"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                    aria-hidden="true"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M1.5 6a2.25 2.25 0 012.25-2.25h16.5A2.25 2.25 0 0122.5 6v12a2.25 2.25 0 01-2.25 2.25H3.75A2.25 2.25 0 011.5 18V6zM3 16.06V18c0 .414.336.75.75.75h16.5A.75.75 0 0021 18v-1.94l-2.69-2.689a1.5 1.5 0 00-2.12 0l-.88.879.97.97a.75.75 0 11-1.06 1.06l-5.16-5.159a1.5 1.5 0 00-2.12 0L3 16.061zm10.125-7.81a1.125 1.125 0 112.25 0 1.125 1.125 0 01-2.25 0z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  <div class="mt-4 flex text-sm leading-6 text-gray-600">
                    <label
                      for="file-upload"
                      class="relative cursor-pointer rounded-md bg-white font-semibold text-indigo-600 focus-within:outline-none focus-within:ring-2 focus-within:ring-indigo-600 focus-within:ring-offset-2 hover:text-indigo-500"
                    >
                      <div>
                        <label class="cursor-pointer">
                          <.live_file_input upload={@uploads.image_list} class="hidden" /> Upload
                        </label>
                      </div>
                    </label>
                    <p class="pl-1">or drag and drop</p>
                  </div>
                  <p class="text-xs leading-5 text-gray-600">PNG, JPG, GIF up to 10MB</p>
                </div>
              </div>
            </div>
          </form>
        </div>
      </div>
    </div> --%>

    <div class="flex flex-col flex-1 mt-10 md:mt-0 md:ml-4">
      <AppWeb.NoClientPreloading.display uploaded_files_locally={@uploaded_files_locally} />
      <div class="flex flex-col flex-1 mt-10">
        <h2 class="text-base font-semibold leading-7 text-gray-900">Uploaded files to S3</h2>
        <p class="mt-1 text-sm leading-6 text-gray-600">
          Here is the list of uploaded files in S3. 🪣
        </p>

        <%!-- <p class={"
          #{if length(@streams.uploaded_files_to_S3) == 0 do "block" else "hidden" end}
          text-xs leading-7 text-gray-400 text-center my-10"}>
          No files uploaded.
        </p> --%>

        <ul
          phx-update="stream"
          id="uploaded_files_S3"
          role="list"
          class="divide-y divide-gray-100"
        >
          <!-- Entry information -->
          <li
            :for={{dom_id, file} <- @streams.uploaded_files_to_S3}
            id={dom_id}
            class="uploaded-s3-item relative flex justify-between gap-x-6 py-5"
          >

            <div :if={Map.has_key?(file, :compressed_url) && Map.has_key?(file, :origin_url)} class="flex gap-x-4">
              <div class="min-w-0 flex-auto">
                <p>
                  <a
                    class="text-sm leading-6 break-all underline text-indigo-600"
                    href={file.origin_url}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    <img
                      class="block max-w-12 max-h-12 w-auto h-auto flex-none bg-gray-50"
                      src={file.compressed_url}
                      onerror="imgError(this);"
                    />
                  </a>
                </p>
                </div>
              </div>
            <div class="flex items-center justify-end gap-x-6">
            <.button type="button" phx-click="delete-uploaded" phx-value-key={dom_id} phx-value-origin={file.origin_url} phx-value-thumb={file.compressed_url}>
              <.icon name="hero-trash"/>
            </.button>
            </div>
          </li>
        </ul>
      </div>
    </div>
    </div>
    </div>

    """
  end

  @impl true
  def mount(_params, _session, socket) do
    File.mkdir_p(@upload_dir)

    socket =
      socket
      |> assign(:uploaded_files_locally, [])
      # |> assign(:uploaded_files_to_S3, [])
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

  # callback from successfull upload to S3 to update the stream
  @impl true
  def handle_info({:bucket_success, map}, socket) do
    new_file =
      %Phoenix.LiveView.UploadEntry{}
      |> Map.put(:origin_url, map.origin_url)
      |> Map.put(:compressed_url, map.compressed_url)
      |> Map.put(:uuid, map.uuid)

    {:noreply, stream_insert(socket, :uploaded_files_to_S3, new_file)}
  end

  # callback error upload to S3
  @impl true
  def handle_info({:upload_error}, socket) do
    {:noreply, put_flash(socket, :error, "Could not save in the bucket")}
  end

  # callback from successfull deletion from bucket
  @impl true
  def handle_info({:success_deletion_from_bucket, dom_id}, socket) do
    IO.puts("success_deletion_from_bucket")

    {:noreply,
     socket
     |> put_flash(:info, "Sucessfully deleted from bucket")
     |> stream_delete_by_dom_id(:uploaded_files_to_S3, dom_id)}
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
        path: build_dest(client_name),
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
        %{"key" => dom_id, "origin" => origin, "thumb" => thumb},
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
        send(pid, {:success_deletion_from_bucket, dom_id})

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

  def build_dest(name),
    do: Application.app_dir(:app, ["priv", "static", "image_uploads", name])

  def thumb_name(name), do: Path.rootname(name) <> "-th" <> Path.extname(name)
  def comp_name(name), do: Path.rootname(name) <> "-comp" <> Path.extname(name)

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
