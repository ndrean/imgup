# defmodule AppWeb.ImgupNoClientLive do
#   use AppWeb, :live_view
#   alias App.ChunkWriter
#   on_mount AppWeb.UserNoClientInit
#   require Logger

#   @upload_dir Application.app_dir(:app, ["priv", "static", "image_uploads"])
#   @default_opt %{q: 80, r: 0.5, th: 80}

#   @impl true
#   def mount(_params, _session, socket) do
#     File.mkdir(@upload_dir)

#     {:ok,
#      socket
#      |> assign(:uploaded_files_locally, [])
#      |> assign(:uploaded_files_to_S3, socket.assigns.uploaded_files_to_S3)
#      |> allow_upload(:image_list,
#        accept: ~w(image/*),
#        max_entries: 6,
#        chunk_size: 64_000,
#        auto_upload: true,
#        max_file_size: 5_000_000,
#        progress: &handle_progress/3,
#        writer: fn _, _, _ -> {ChunkWriter, []} end
#        # Do not define presign_upload. This will create a local photo in /vars
#      )}
#   end

#   # With `auto_upload: true`, we can consume files here
#   # loop until chunk is finished
#   defp handle_progress(:image_list, entry, socket) when entry.done? == false,
#     do: {:noreply, socket}

#   defp handle_progress(:image_list, entry, socket) do
#     uploaded_file =
#       consume_uploaded_entry(socket, entry, fn %{file: file_data, total_size: total_size} ->
#         checked_sum = check_sum(entry.client_size, total_size)

#         entry = Map.update!(entry, :client_name, &clean_name(&1))
#         pid = self()

#         checked_sum &&
#           Task.start(fn ->
#             transform_image(pid, file_data, entry, %{q: 70, th: 110})
#           end)

#         IO.puts("before Task Image________")

#         {:ok,
#          entry
#          |> Map.put(:thumbnail, nil)
#          |> Map.put(:image_url, nil)
#          |> Map.put(:url_path, nil)
#          |> Map.put(:thumb_name, nil)
#          |> Map.put(:errors, [])
#          |> Map.update(:errors, [], fn list ->
#            if checked_sum, do: list, else: list ++ ["file truncated"]
#          end)}
#       end)

#     case length(uploaded_file.errors) do
#       0 ->
#         {:noreply, update(socket, :uploaded_files_locally, &(&1 ++ [uploaded_file]))}

#       _ ->
#         Logger.warning(inspect(uploaded_file.errors))

#         {:noreply,
#          socket
#          |> put_flash(:error, inspect(uploaded_file.errors))
#          |> update(:uploaded_files_locally, &(&1 ++ [uploaded_file]))}
#     end
#   end

#   def transform_image(pid, file_data, entry, opts \\ @default_opt) do
#     {_q, _r, th} = get_transform_opts(opts)
#     file_name = entry.client_name |> build_dest()
#     thumb_name = build_thumb_name(entry.client_name) |> build_dest() |> dbg()

#     with {:ok, img1} <- Image.open(file_data, []),
#          {:ok, img2} <- Image.thumbnail(img1, th),
#          {:ok, _thumb_file_img} <- Image.write(img2, thumb_name),
#          {:ok, _file_img} <- Image.write(img1, file_name) do
#       {:ok, content} = File.read(thumb_name)
#       send(pid, {:update, entry.client_name, entry.uuid, content, thumb_name})
#     else
#       {:error, msg} ->
#         Logger.warning(inspect(msg))
#         send(pid, {:error, :file_not_transformed})
#     end
#   end

#   # Event handlers -------

#   @impl true
#   def handle_event("validate", _params, socket) do
#     {:noreply, socket}
#   end

#   @impl true
#   def handle_event("upload_to_s3", params, socket) do
#     IO.puts("upload")

#     # Get file element from the local files array
#     file_element =
#       Enum.find(socket.assigns.uploaded_files_locally, fn %{uuid: uuid} ->
#         uuid == Map.get(params, "uuid")
#       end)
#       |> dbg()

#     filename = file_element.client_name
#     ext = filename |> Path.extname()

#     # Create file object to upload
#     file =
#       %{
#         path: build_dest(filename),
#         content_type: file_element.client_type,
#         filename: filename
#       }
#       |> dbg()

#     # Upload file
#     case App.Upload.upload(file) do
#       {:ok, body} ->
#         # We add the `uuid` to the object to display on the view template.
#         body = Map.put(body, :uuid, file_element.uuid)

#         # Delete the file locally
#         File.rm!(file.path)

#         pid = self()

#         {:ok, %{thumbnail: file_data}} = save_aws_links_with_thumb(pid, body)

#         thumb_path = build_image_url("tmp-#{file_element.uuid}#{ext}") |> dbg()
#         thumb_file_path = build_dest("tmp-#{file_element.uuid}#{ext}") |> dbg()
#         Image.open!(file_data, []) |> Image.write(thumb_file_path) |> dbg()

#         body = Map.put(body, :thumb_file, thumb_path)
#         File.rm!(thumb_file_path)
#         File.rm!(file_element.thumb_name)
#         # Update the socket accordingly
#         updated_local_array = List.delete(socket.assigns.uploaded_files_locally, file_element)

#         socket = update(socket, :uploaded_files_to_S3, &(&1 ++ [body]))
#         socket = assign(socket, :uploaded_files_locally, updated_local_array)

#         {:noreply, socket}

#       # If the upload fails...
#       {:error, reason} ->
#         # Update the failed local file element to show an error message
#         index = Enum.find_index(socket.assigns.uploaded_files_locally, &(&1 == file_element))
#         updated_file_element = Map.put(file_element, :errors, ["#{reason}"])

#         updated_local_array =
#           List.replace_at(socket.assigns.uploaded_files_locally, index, updated_file_element)

#         {:noreply, assign(socket, :uploaded_files_locally, updated_local_array)}
#     end
#   end

#   @impl true
#   # get screen size
#   def handle_event("page-size", p, socket) do
#     {:noreply, assign(socket, screen: p)}
#   end

#   # callback from the `transform_image` Task in case of error
#   @impl true
#   def handle_info({:error, :file_not_transformed}, socket),
#     do: {:noreply, put_flash(socket, :error, "Picture not transformed")}

#   # udpate state in this callback from "transform_image".
#   @impl true
#   def handle_info({:update, filename, uuid, file_data, thumb_name}, socket) do
#     # save thum file in DB
#     pid = self()
#     current_user = socket.assigns.current_user
#     Task.start(fn -> pre_save_thumb(pid, current_user, uuid, file_data) end)

#     # udpate the state
#     new_url_path =
#       build_url_path(filename)

#     new_thumbnail =
#       filename |> build_thumb_name() |> build_image_url()

#     new_image_url = build_image_url(filename)

#     IO.puts("Render Update after Image___________")

#     {:noreply,
#      socket
#      |> update(
#        :uploaded_files_locally,
#        &update_file_at_uuid(&1, uuid, new_image_url, new_thumbnail, new_url_path, thumb_name)
#      )}
#   end

#   # error when saving thumbnail
#   @impl true
#   def handle_info({:thumb_error, msg}, socket), do: {:noreply, put_flash(socket, :error, hd(msg))}

#   @impl true
#   def handle_info({:thumb_update_error, msg}, socket) do
#     {:noreply, put_flash(socket, :error, inspect(msg))}
#   end

#   # body = %{url: "..", compressed_url: "..", uuid: "..."}
#   def save_aws_links_with_thumb(pid, body) do
#     alias App.Gallery.Thumb
#     alias App.Repo

#     # !!!! first draft. the error handling should be largely improved, no "with"!!.
#     with thumb <- Repo.get_by(Thumb, uuid: body.uuid),
#          changeset <-
#            Thumb.changeset(thumb, %{
#              public_url: body.url,
#              # key: key,
#              compressed_url: body.compressed_url
#            }) do
#       Repo.update(changeset)
#     else
#       msg ->
#         inspect(msg)
#         send(pid, {:thumb_update_error, msg})
#         :error
#     end
#   end

#   def pre_save_thumb(pid, current_user, uuid, file_data) do
#     alias App.Gallery.Thumb
#     alias App.Repo

#     # key = body.url |> Path.basename() |> Path.rootname()

#     changeset =
#       Thumb.changeset(%Thumb{}, %{
#         user_id: current_user.id,
#         uuid: uuid,
#         # thumbnail: :erlang.term_to_binary(file_data)
#         thumbnail: file_data
#       })

#     case changeset.valid? do
#       true ->
#         Repo.insert!(changeset)
#         :ok

#       false ->
#         errs = extract_errors(changeset)
#         Logger.warning(inspect(errs))
#         send(pid, {:thumb_error, errs})
#         :error
#     end
#   end

#   def extract_errors(changeset) do
#     changeset
#     |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
#     |> then(fn errors ->
#       Map.keys(errors) |> Enum.map(&Map.get(errors, &1)) |> List.flatten()
#     end)
#   end

#   @doc """
#   Takes the option map that defaults to `@default_opt`.

#   Defines the compression quality `q`, the resizing factor `r`, the thumbnail size `th`
#   """
#   def get_transform_opts(opts),
#     do:
#       {Map.get(opts, :q, @default_opt.q), Map.get(opts, :r, @default_opt.r),
#        Map.get(opts, :th, @default_opt.th)}

#   def check_sum(entry_size, chunked_size), do: entry_size == chunked_size

#   def update_file_at_uuid(files, uuid, new_image_url, new_thumbnail, new_url_path, thumb_name),
#     do:
#       Enum.map(files, fn el ->
#         if el.uuid == uuid,
#           do: %{
#             el
#             | thumbnail: new_thumbnail,
#               image_url: new_image_url,
#               url_path: new_url_path,
#               thumb_name: thumb_name
#           },
#           else: el
#       end)

#   def build_dest(name),
#     do: Application.app_dir(:app, ["priv", "static", "image_uploads", name])

#   # equiv: Path.join([:code.priv_dir(:app), "static", "image_uploads", "#{name}"])

#   def clean_name(name) do
#     ext = Path.extname(name)
#     rootname = name |> Path.rootname() |> String.replace(" ", "") |> String.replace(".", "")
#     rootname <> ext
#   end

#   def build_thumb_name(name), do: Path.rootname(name) <> "-th" <> Path.extname(name)

#   def build_url_path(name), do: AppWeb.Endpoint.static_path("/#{name}")

#   def build_image_url(name),
#     do:
#       AppWeb.Endpoint.url() <>
#         AppWeb.Endpoint.static_path("/image_uploads/#{name}")
# end
