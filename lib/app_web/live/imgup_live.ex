defmodule AppWeb.ImgupLive do
  use AppWeb, :live_view
  on_mount AppWeb.UserLiveInit
  alias App.Gallery.Url
  alias App.Repo
  require Logger

  @msg_success_in_uploading "Success in uploading"
  @msg_sucess_deleting_object_from_bucket "Successfully deleted from the bucket"
  @msg_success_in_dowloading_file "Success, file saved locally"
  @msg_error_on_save "An error occured when saving"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(%{url: ""})
     |> allow_upload(:image_list,
       accept: ~w(image/*),
       max_entries: 10,
       chunk_size: 64_000,
       max_file_size: 5_000_000,
       external: &presign_upload/2
     )}
  end

  # Adding presign for each entry for S3 upload --------

  defp presign_upload(entry, socket) do
    uploads = socket.assigns.uploads
    client_name = clean_name(entry.client_name)
    key = Cid.cid("#{DateTime.utc_now() |> DateTime.to_iso8601()}_#{client_name}")

    {:ok, fields} =
      SimpleS3Upload.sign_form_upload(aws_config(), bucket(),
        key: key,
        content_type: entry.client_type,
        max_file_size: uploads[entry.upload_config].max_file_size,
        expires_in: :timer.hours(1)
      )

    meta =
      %{
        uploader: "S3",
        key: key,
        url: build_uri(),
        compressed_url: build_uri(),
        fields: fields,
        ext: Path.extname(client_name)
      }

    {:ok, meta, socket}
  end

  # Event handlers -------
  # for link_patch to display an image when clicked
  @impl true
  def handle_params(%{"url" => url}, _uri, socket) do
    {:noreply, assign(socket, %{url: url})}
  end

  def handle_params(_p, _uri, socket) do
    {:noreply, socket}
  end

  # device screen settings from a JS hook
  @impl true
  def handle_event("page-size", p, socket), do: {:noreply, assign(socket, screen: p)}

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove-selected", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image_list, ref)}
  end

  # trigger via submit button
  @impl true
  def handle_event("save", _params, socket) do
    current_user = socket.assigns.current_user

    uploaded_files =
      consume_uploaded_entries(socket, :image_list, fn %{uploader: _} = meta, entry ->
        # AWS does not accept extension ...?!! so we add one as we may need one further
        origin_url = meta.url <> "/" <> meta.key
        compressed_url = meta.compressed_url <> "/" <> meta.key

        {:ok,
         meta
         |> Map.put(:origin_url, origin_url)
         |> Map.put(:compressed_url, compressed_url)
         |> Map.put(:ext, meta.ext)
         |> Map.put(:uuid, entry.uuid)}
      end)

    case save_file_urls(uploaded_files, current_user) do
      {:error, msg} ->
        {:noreply,
         socket
         |> put_flash(:error, @msg_error_on_save <> inspect(msg))
         |> update(:uploaded_files, &(&1 ++ uploaded_files))}

      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, @msg_success_in_uploading)
         |> update(:uploaded_files, &(&1 ++ uploaded_files))}
    end
  end

  @impl true
  def handle_event("delete", %{"key" => key}, socket) do
    # case check_if_exists_in_bucket(bucket(), key) do
    # nil ->
    # {:noreply, App.send_flash!(socket, :error, "Object not found in the bucket")}

    # _ ->
    # runs deletion in a Task to ensure that S3 returns a response before the next check
    Task.async(fn -> ExAws.S3.delete_object(bucket(), key) |> ExAws.request() end)
    |> Task.await()

    # check that the object is deleted before sending to the LV the order to update
    # the database and LV state accordingly.
    case check_if_exists_in_bucket(bucket(), key) do
      nil ->
        send(self(), {:delete, key})
        {:noreply, socket}

      _ ->
        Logger.warning("Object not deleted")
        {:noreply, App.send_flash!(socket, :error, "Object not removed from the bucket")}
    end

    # end
  end

  @impl true
  def handle_event("delete", _p, socket) do
    {:noreply, put_flash(socket, :error, "Cannot find object as created by another mean")}
  end

  def check_if_exists_in_bucket(bucket, key) do
    ExAws.S3.list_objects(bucket)
    |> ExAws.request!()
    |> get_in([:body, :contents])
    |> dbg()
    |> Enum.find(&(&1.key == key))
  end

  # handle the flash messages sent from children live_components
  @impl true
  def handle_info({:child_flash, type, msg}, socket) do
    {:noreply, put_flash(socket, type, inspect(msg))}
  end

  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  # delete the ref "key" in the database
  def handle_info({:delete, key}, socket) do
    transaction =
      Repo.transaction(fn repo ->
        data = repo.get_by(Url, %{key: key})

        case data do
          nil ->
            {:error, :not_found_in_database}

          data ->
            repo.delete(data)
        end
      end)

    case transaction do
      {:ok, {:error, msg}} ->
        Logger.warning(inspect(msg))

        {:noreply,
         socket
         |> put_flash(:error, "Object deleted from the bucket but Database error")}

      {:ok, {:ok, _}} ->
        {:noreply,
         socket
         |> put_flash(:info, @msg_sucess_deleting_object_from_bucket)
         |> update(:uploaded_files, &Enum.filter(&1, fn file -> file.key != key end))}
    end
  end

  # success callback from live_component after local save
  @impl true
  def handle_info({:success, :download}, socket) do
    {:noreply,
     socket
     |> App.clear_flash!()
     |> App.send_flash!(:info, @msg_success_in_dowloading_file)}
  end

  # failure callback from live_component after local save
  @impl true
  def handle_info({:fail, {:error, msg}}, socket) do
    {:noreply,
     socket
     |> App.clear_flash!()
     |> App.send_flash!(:error, @msg_error_on_save <> inspect(msg))}
  end

  # View utilities -------

  @doc """
  Return a list of %App.Gallery.Url{} changeset struct based on the files received and the current_user.
  """
  def uploads_changesets(uploaded_files, user) do
    Enum.map(uploaded_files, &file_to_changeset(&1, user))
  end

  defp file_to_changeset(file, user) do
    %Url{}
    |> Url.changeset(%{
      key: file.key,
      origin_url: file.origin_url,
      compressed_url: file.compressed_url,
      user_id: user.id,
      ext: file.ext
    })
  end

  @doc """
  Checks if all changesets are valid. Returns true/false.
  """
  def validate_changesets?(list_changesets) do
    Enum.all?(list_changesets, & &1.valid?)
  end

  @doc """
  Receives the uploaded_files and the current_user.

  Produces an insertion of the association user/urls into the database.

  Returns a tuple `{:ok, _}` or `{:error, _}`
  """
  def save_file_urls(uploaded_files, current_user) do
    changesets =
      uploads_changesets(uploaded_files, current_user)

    case validate_changesets?(changesets) do
      true ->
        Ecto.Multi.new()
        |> Ecto.Multi.run(:build, fn repo, _change ->
          Enum.each(changesets, &repo.insert(&1))
          {:ok, :done}
        end)
        |> App.Repo.transaction()

      false ->
        errs = extract_errors(changesets)
        {:error, inspect(errs)}
    end
  end

  def extract_errors(changesets) do
    Enum.find(changesets, &(&1.valid? == false))
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> then(fn errors ->
      Map.keys(errors) |> Enum.map(&Map.get(errors, &1)) |> List.flatten()
    end)
  end

  def are_files_uploadable?(image_list) do
    error_list = Map.get(image_list, :errors)
    Enum.empty?(error_list) and length(image_list.entries) > 0
  end

  def error_to_string(:too_large), do: "Too large."
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type."

  # coveralls-ignore-start
  def error_to_string(:external_client_failure),
    do: "Couldn't upload files to S3. Open an issue on Github and contact the repo owner."

  # coveralls-ignore-stop

  def clean_name(name) do
    ext = Path.extname(name)
    rootname = name |> Path.rootname() |> String.replace(" ", "") |> String.replace(".", "")
    rootname <> ext
  end

  # utilities for config
  def aws_region, do: System.get_env("AWS_REGION")
  def aws_access_key_id, do: System.get_env("AWS_ACCESS_KEY_ID")
  def aws_secret_access_key, do: System.get_env("AWS_SECRET_ACCESS_KEY")
  def bucket, do: Application.get_env(:ex_aws, :original_bucket)
  def bucket_compressed, do: Application.get_env(:ex_aws, :compressed_bucket)

  def aws_config do
    %{
      region: aws_region(),
      access_key_id: aws_access_key_id(),
      secret_access_key: aws_secret_access_key()
    }
  end

  def build_uri(), do: "https://#{bucket()}.s3-#{aws_region()}.amazonaws.com"
end

# "meta" in the "save" handler
# %{
#   fields: %{
#     "acl" => "public-read",
#     "content-type" => "image/png",
#     "key" => "bafkreigzsr7usrayr6k7eta45ym4k5xrdoegiwlvqppuwhafmqx2tx6rcm",
#     "policy" => "ewogICJleHBpcmF0aW9uIjogIjIwMjMtMDktMDZUMTU6MjQ6NDAuOTEwMDgyWiIsCiAgImNvbmRpdGlvbnMiOiBbCiAgICB7ImJ1Y2tldCI6ICAiZHd5bC1pbWd1cCJ9LAogICAgWyJlcSIsICIka2V5IiwgImJhZmtyZWlnenNyN3VzcmF5cjZrN2V0YTQ1eW00azV4cmRvZWdpd2x2cXBwdXdoYWZtcXgydHg2cmNtIl0sCiAgICB7ImFjbCI6ICJwdWJsaWMtcmVhZCJ9LAogICAgWyJlcSIsICIkQ29udGVudC1UeXBlIiwgImltYWdlL3BuZyJdLAogICAgWyJjb250ZW50LWxlbmd0aC1yYW5nZSIsIDAsIDUwMDAwMDBdLAogICAgeyJ4LWFtei1zZXJ2ZXItc2lkZS1lbmNyeXB0aW9uIjogIkFFUzI1NiJ9LAogICAgeyJ4LWFtei1jcmVkZW50aWFsIjogIkFLSUE1VEg2RkxCWUkyQlo0TzVOLzIwMjMwOTA2L2V1LXdlc3QtMy9zMy9hd3M0X3JlcXVlc3QifSwKICAgIHsieC1hbXotYWxnb3JpdGhtIjogIkFXUzQtSE1BQy1TSEEyNTYifSwKICAgIHsieC1hbXotZGF0ZSI6ICIyMDIzMDkwNlQxNTI0NDBaIn0KICBdCn0K",
#     "x-amz-algorithm" => "AWS4-HMAC-SHA256",
#     "x-amz-credential" => "AKIA5TH6FLBYI2BZ4O5N/20230906/eu-west-3/s3/aws4_request",
#     "x-amz-date" => "20230906T152440Z",
#     "x-amz-server-side-encryption" => "AES256",
#     "x-amz-signature" => "4036f4e39dec486dbd09391f2f223d2047a27a27eb88935ef5ce6f4c71bdd4a2"
#   },
#   key: "bafkreigzsr7usrayr6k7eta45ym4k5xrdoegiwlvqppuwhafmqx2tx6rcm",
#   url: "https://dwyl-imgup.s3-eu-west-3.amazonaws.com",
#   compressed_url: "https://dwyl-imgup.s3-eu-west-3.amazonaws.com",
#   uploader: "S3",
#   ext: ".png"
# }
