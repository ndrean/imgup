defmodule AppWeb.ImgupNoClientLive do
  use AppWeb, :live_view
  alias App.ChunkWriter
  require Logger

  @upload_dir Application.app_dir(:app, ["priv", "static", "image_uploads"])
  @default_opt %{q: 80, r: 0.5, th: 80}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:uploaded_files_locally, [])
     |> assign(:uploaded_files_to_S3, [])
     |> allow_upload(:image_list,
       accept: ~w(image/*),
       max_entries: 6,
       chunk_size: 64_000,
       auto_upload: true,
       max_file_size: 5_000_000,
       progress: &handle_progress/3,
       writer: fn _, _, _ -> {ChunkWriter, []} end
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
        checked_sum = check_sum(entry.client_size, total_size)
        ext = App.get_entry_extension(entry)
        entry = Map.update!(entry, :client_name, fn name -> clean_name(name, ext) end)
        pid = self()

        checked_sum &&
          Task.start(fn -> transform_image(pid, file, entry, %{q: 70}) end)

        Logger.info("first render before Task Image________")

        {:ok,
         entry
         |> Map.put(:thumbnail, nil)
         |> Map.put(:image_url, nil)
         |> Map.put(:url_path, nil)
         |> Map.put(:errors, [])
         |> Map.update(:errors, [], fn list ->
           if checked_sum, do: list, else: list ++ ["file truncated"]
         end)}

        # {:ok,
        #  entry
        #  |> Map.put(:image_url, build_image_url(entry.client_name))
        #  |> Map.put(:thumbnail, build_image_url(entry.client_name))
        #  |> Map.put(:url_path, build_url_path(entry.client_name))
        #  |> Map.put(:errors, [])
        #  |> Map.update(:errors, [], fn list ->
        #    if checked_sum, do: list, else: list ++ ["file truncated"]
        #  end)}
      end)

    case length(uploaded_file.errors) do
      0 ->
        {:noreply, update(socket, :uploaded_files_locally, &(&1 ++ [uploaded_file]))}

      _ ->
        Logger.warning(inspect(uploaded_file.errors))

        {:noreply,
         socket
         |> put_flash(:error, inspect(uploaded_file.errors))
         |> update(:uploaded_files_locally, &(&1 ++ [uploaded_file]))}
    end
  end

  # Event handlers -------

  @impl true
  def handle_event("validate", _params, socket) do
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

  def transform_image(pid, file, entry, opts \\ @default_opt) do
    alias Vix.Vips.Image
    alias Vix.Vips.Operation

    {q, r, th} = get_transform_opts(opts)

    case Image.new_from_buffer(file) do
      {:error, msg} ->
        {:error, msg}

      {:ok, img} ->
        try do
          # w = Image.width(img) |> to_string()
          filename = entry.client_name
          dest_name = build_dest(filename)
          :ok = Image.write_to_file(img, "#{dest_name}[Q=#{q}]")

          resized_name = "small-#{filename}" |> build_dest()

          :ok =
            Operation.resize!(img, r) |> Image.write_to_file(resized_name)

          thumb_name = "thumb-#{filename}" |> build_dest()

          :ok =
            Operation.thumbnail!(dest_name, th)
            |> Image.write_to_file(thumb_name)

          send(pid, {:update, filename, "thumb-#{filename}", entry.uuid})
        rescue
          e ->
            Logger.warning(inspect(e.message))
            send(pid, {:error, :file_not_transformed})
        end
    end
  end

  # callback from the `transform_image` Task in case of error
  @impl true
  def handle_info({:error, :file_not_transformed}, socket),
    do: {:noreply, put_flash(socket, :error, "Picture not transformed")}

  @impl true
  def handle_info({:update, filename, thumb_name, uuid}, socket) do
    new_url_path =
      build_url_path(thumb_name)

    new_thumbnail =
      build_image_url(thumb_name)

    new_image_url = build_image_url(filename)

    Logger.info("Render Update after Image___________")

    {:noreply,
     socket
     |> update(
       :uploaded_files_locally,
       &update_file_at_uuid(&1, uuid, new_image_url, new_thumbnail, new_url_path)
     )}
  end

  @doc """
  Takes the option map that defaults to `@default_opt`.

  Defines the compression quality `q`, the resizing factor `r`, the thumbnail size `th`
  """
  def get_transform_opts(opts),
    do:
      {Map.get(opts, :q, @default_opt.q), Map.get(opts, :r, @default_opt.r),
       Map.get(opts, :th, @default_opt.th)}

  def check_sum(entry_size, chunked_size), do: entry_size == chunked_size

  defp build_dest(name),
    do: Path.join([:code.priv_dir(:app), "static", "image_uploads", "#{name}"])

  def clean_name(name, ext) do
    n = name |> String.replace(" ", "") |> String.replace(".", "")
    n <> "." <> ext
  end

  def update_file_at_uuid(files, uuid, new_image_url, new_thumbnail, new_url_path),
    do:
      Enum.map(files, fn el ->
        if el.uuid == uuid,
          do: %{el | thumbnail: new_thumbnail, image_url: new_image_url, url_path: new_url_path},
          else: el
      end)

  def build_url_path(name), do: AppWeb.Endpoint.static_path("/#{name}")

  def build_image_url(name),
    do:
      AppWeb.Endpoint.url() <>
        AppWeb.Endpoint.static_path("/image_uploads/#{name}")
end
