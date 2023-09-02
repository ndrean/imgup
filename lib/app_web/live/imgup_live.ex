defmodule AppWeb.ImgupLive do
  use AppWeb, :live_view
  on_mount AppWeb.UserLiveInit
  alias App.Gallery.Url
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    default_assigns = %{url: ""}

    {:ok,
     socket
     |> assign(default_assigns)
     |> allow_upload(:image_list,
       accept: ~w(image/*),
       max_entries: 6,
       chunk_size: 64_000,
       max_file_size: 5_000_000,
       external: &presign_upload/2
     )}
  end

  # Adding presign for each entry for S3 upload --------

  defp presign_upload(entry, socket) do
    uploads = socket.assigns.uploads
    bucket_original = bucket_original()
    bucket_compressed = bucket_compressed()
    key = Cid.cid("#{DateTime.utc_now() |> DateTime.to_iso8601()}_#{entry.client_name}")

    aws_config = aws_config()

    {:ok, fields} =
      SimpleS3Upload.sign_form_upload(aws_config, bucket_original,
        key: key,
        content_type: entry.client_type,
        max_file_size: uploads[entry.upload_config].max_file_size,
        expires_in: :timer.hours(1)
      )

    meta =
      %{
        uploader: "S3",
        key: key,
        url: "https://#{bucket_original}.s3-#{aws_config.region}.amazonaws.com",
        compressed_url: "https://#{bucket_compressed}.s3-#{aws_config.region}.amazonaws.com",
        fields: fields,
        ext: get_entry_extension(entry)
      }

    {:ok, meta, socket}
  end

  # Event handlers -------
  @impl true
  def handle_params(%{"url" => url}, _uri, socket) do
    {:noreply, assign(socket, :url, url)}
  end

  @impl true
  def handle_params(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove-selected", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image_list, ref)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    current_user = socket.assigns.current_user

    uploaded_files =
      consume_uploaded_entries(socket, :image_list, fn %{uploader: _} = meta, _entry ->
        public_url = meta.url <> "/#{meta.key}"
        compressed_url = meta.compressed_url <> "/#{meta.key}"

        meta = Map.put(meta, :public_url, public_url)
        meta = Map.put(meta, :compressed_url, compressed_url)

        {:ok, meta}
      end)

    case save_file_urls(uploaded_files, current_user) do
      {:error, msg} ->
        {:noreply,
         socket
         |> put_flash(:error, "Something went wrong: #{inspect(msg)}")
         |> update(:uploaded_files, &(&1 ++ uploaded_files))}

      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Success in uploading")
         |> update(:uploaded_files, &(&1 ++ uploaded_files))}
    end
  end

  # handle the flash messages sent from children live_components
  @impl true
  def handle_info({:child_flash, type, msg}, socket) do
    {:noreply, put_flash(socket, type, inspect(msg))}
  end

  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  def handle_info({:delete, key}, socket) do
    res =
      App.Repo.transaction(fn repo ->
        data = repo.get_by(App.Gallery.Url, %{key: key})

        case data do
          nil ->
            {:error, :not_found_in_database}

          data ->
            repo.delete(data)
        end
      end)

    case res do
      {:ok, {:error, msg}} ->
        Logger.warning(inspect(msg))

        {:noreply,
         socket
         |> put_flash(:error, "Object deleted from the bucket but Database error")}

      {:ok, {:ok, _}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Successfully deleted from the bucket")
         |> update(:uploaded_files, &Enum.filter(&1, fn file -> file.key != key end))}
    end
  end

  # View utilities -------

  @doc """
  Return a list of %App.Gallery.Url{} changeset struct based on the files received and the current_user.
  """
  def uploads_changesets(uploaded_files, user) do
    Enum.map(uploaded_files, &file_to_changeset(&1, user))
  end

  defp file_to_changeset(file, user) do
    Url.changeset(%{
      key: file.key,
      public_url: file.public_url,
      compressed_url: file.compressed_url,
      ext: file.ext,
      user_id: user.id
    })
  end

  @doc """
  Accumulate the `changeset.valid?` by adding the boolean result to get a boolean result.
  """
  def validate_changesets?(list_changesets) do
    Enum.all?(list_changesets, & &1.valid?)
  end

  @doc """
  Receives the uploaded_files and the current_user.

  Produces an insertion of the association user/urls into the database.

  Returns a tuple `{:ok, _}` or `{}:error, _}`
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
      Map.keys(errors) |> Enum.map(&Map.get(errors, &1))
    end)
  end

  def get_entry_extension(entry) do
    entry.client_name |> String.split(".") |> List.last()
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
  def aws_region, do: System.get_env("AWS_REGION")
  def aws_access_key_id, do: System.get_env("AWS_ACCESS_KEY_ID")
  def aws_secret_access_key, do: System.get_env("AWS_SECRET_ACCESS_KEY")
  def bucket_original, do: Application.get_env(:ex_aws, :original_bucket)
  def bucket_compressed, do: Application.get_env(:ex_aws, :compressed_bucket)

  def aws_config do
    %{
      region: aws_region(),
      access_key_id: aws_access_key_id(),
      secret_access_key: aws_secret_access_key()
    }
  end
end
