defmodule AppWeb.ImgupNoClientLive do
  use AppWeb, :live_view
  require Logger

  @upload_dir Application.app_dir(:app, ["priv", "static", "image_uploads"])

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:pid, self())
     |> assign(:uploaded_files_locally, [])
     |> assign(:uploaded_files_to_S3, [])
     |> allow_upload(:image_list,
       accept: ~w(image/*),
       max_entries: 6,
       chunk_size: 64_000,
       auto_upload: true,
       max_file_size: 5_000_000,
       progress: &handle_progress/3,
       writer: fn _, _, _ -> {MyWriter, []} end
       # Do not define presign_upload. This will create a local photo in /vars
     )}
  end

  # With `auto_upload: true`, we can consume files here
  defp handle_progress(:image_list, entry, socket) when entry.done? == false do
    # loop until chunk is finished
    {:noreply, socket}
  end

  defp handle_progress(:image_list, entry, socket) do
    uploaded_file =
      consume_uploaded_entry(socket, entry, fn %{file: file, total_size: total_size} ->
        check_size = size_check(entry.client_size, total_size)
        pid = socket.assigns.pid
        Task.start(fn -> transform_image(check_size, pid, file, entry, 80) end)

        {:ok,
         entry
         |> Map.put(
           :image_url,
           AppWeb.Endpoint.url() <>
             AppWeb.Endpoint.static_path("/image_uploads/#{entry.client_name}")
         )
         |> Map.put(
           :url_path,
           AppWeb.Endpoint.static_path("/image_uploads/#{entry.client_name}")
         )
         |> Map.put(:errors, [])
         |> Map.update(:errors, [], fn list ->
           if check_size, do: list, else: list ++ ["file truncated"]
         end)}
      end)

    case length(uploaded_file.errors) do
      0 ->
        uploaded_file |> dbg()
        {:noreply, update(socket, :uploaded_files_locally, &(&1 ++ [uploaded_file]))}

      _ ->
        Logger.warning(inspect(uploaded_file.errors))
        {:noreply, put_flash(socket, :error, inspect(uploaded_file.errors))}
    end
  end

  # Event handlers -------

  @impl true
  def handle_event("validate", _params, socket) do
    IO.puts("valid")
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_to_s3", params, socket) do
    IO.puts("upload")
    # Get file element from the local files array
    file_element =
      Enum.find(socket.assigns.uploaded_files_locally, fn %{uuid: uuid} ->
        uuid == Map.get(params, "uuid")
      end)

    # Create file object to upload
    file = %{
      path: @upload_dir <> "/" <> Map.get(file_element, :client_name),
      content_type: file_element.client_type,
      filename: file_element.client_name
    }

    # Upload file
    case App.Upload.upload(file) do
      # If the upload succeeds...
      {:ok, body} ->
        # We add the `uuid` to the object to display on the view template.
        body = Map.put(body, :uuid, file_element.uuid)

        # Delete the file locally
        File.rm!(file.path)

        # Update the socket accordingly
        updated_local_array = List.delete(socket.assigns.uploaded_files_locally, file_element)

        socket = update(socket, :uploaded_files_to_S3, &(&1 ++ [body]))
        socket = assign(socket, :uploaded_files_locally, updated_local_array)

        {:noreply, socket}

      # If the upload fails...
      {:error, reason} ->
        # Update the failed local file element to show an error message
        index = Enum.find_index(socket.assigns.uploaded_files_locally, &(&1 == file_element))
        updated_file_element = Map.put(file_element, :errors, ["#{reason}"])

        updated_local_array =
          List.replace_at(socket.assigns.uploaded_files_locally, index, updated_file_element)

        {:noreply, assign(socket, :uploaded_files_locally, updated_local_array)}
    end
  end

  def transform_image(false, _, _, _, _) do
    :error
  end

  def transform_image(true, pid, file, entry, q) do
    alias Vix.Vips.Image
    alias Vix.Vips.Operation

    file_name = entry.client_name
    dest_name = build_dest(file_name)
    ext = App.get_entry_extension(entry)

    case Image.new_from_buffer(file) do
      {:error, msg} ->
        {:error, msg}

      {:ok, img} ->
        try do
          w = Image.width(img)
          # IO.puts("Width: #{Image.width(img)}")
          # IO.puts("Height: #{Image.height(img)}")
          :ok = Image.write_to_file(img, "#{dest_name}[Q=#{q}]") |> dbg()

          rename = "small-#{to_string(w)}.#{ext}" |> dbg()

          :ok =
            Operation.resize!(img, 0.1) |> Image.write_to_file(rename) |> dbg()

          :ok =
            Operation.thumbnail!(rename, 80)
            |> Image.write_to_file("thumb-#{to_string(w)}.#{ext}")
            |> dbg()
        rescue
          e ->
            Logger.warning(inspect(e.message))
            send(pid, {:error, :file_not_transformed})
        end
    end
  end

  @impl true
  def handle_info({:error, :file_not_transformed}, socket) do
    {:noreply, put_flash(socket, :error, "Picture not transformed")}
  end

  @spec size_check(any, any) :: boolean
  def size_check(entry_size, chunked_size), do: entry_size == chunked_size

  defp build_dest(name) do
    Path.join([:code.priv_dir(:app), "static", "image_uploads", "#{name}"])
  end
end
