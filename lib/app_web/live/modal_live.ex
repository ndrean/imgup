defmodule AppWeb.Input do
  @moduledoc """
  Embedded schema to validate the input of the modal form
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias AppWeb.Input

  embedded_schema do
    field :name, :string
  end

  def create_changeset(attrs \\ %{}) do
    %Input{}
    |> cast(attrs, [:name])
    |> validate_length(:name, min: 3)
    |> validate_required([:name])
  end
end

defmodule AppWeb.ModalForm do
  @moduledoc """
  LiveComponent rendered in the modal.
  It displays the "compressed link" and a form to assign a name to file the user wants to download from S3.
  """
  use AppWeb, :live_component
  alias AppWeb.Input
  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.link href={@file.compressed_url} target="_blank">
        <.icon name="hero-link" /> View the compressed file
      </.link>

      <.button phx-click="delete" phx-value-key={@file.key} phx-target={@myself}>
        <.icon name="hero-trash"/>
      </.button>
      <.simple_form
        id={"dwld-#{@file.key}"}
        for={@form_dwld}
        phx-submit={JS.push("download") |> hide_modal("modal-#{@file.key}")}
        phx-target={@myself}
        phx-value-key={@file.key}
        phx-value-ext={@file.ext}
        phx-change="change"
      >
        <.input
          type="text"
          field={@form_dwld[:name]}
          id={"input-name-#{@file.key}"}
          label="Give this picture a name if you want to save it locally:"
        >
        </.input>
        <:actions>
          <.button type="submit">
            <.icon name="hero-cloud-arrow-down" />
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    init_input = %{"name" => ""}
    {:ok, assign(socket, :form_dwld, to_form(Input.create_changeset(init_input)))}
  end

  @impl true
  def handle_event("change", %{"input" => input, "key" => _key}, socket) do
    IO.puts("change-------")
    changeset = Input.create_changeset(input)

    case changeset.valid? do
      true ->
        {:noreply,
         socket
         |> App.clear_flash!()
         |> assign(:form_dwld, to_form(Input.create_changeset(input)))}

      false ->
        err_msg =
          Ecto.Changeset.traverse_errors(changeset, & &1)
          |> Map.get(:name)
          |> hd()

        {:noreply,
         socket
         |> App.send_flash!(:error, err_msg)
         |> assign(:form_dwld, to_form(Input.create_changeset(input)))}
    end
  end

  @impl true
  def handle_event("delete", %{"key" => key}, socket) do
    bucket = bucket()

    case check_if_exists_in_bucket(bucket, key) do
      nil ->
        {:noreply, App.send_flash!(socket, :error, "Object not found in the bucket")}

      _ ->
        # runs deletion in a Task to ensure that S3 returns a response before the next check
        Task.async(fn -> ExAws.S3.delete_object(bucket, key) |> ExAws.request() end)
        |> Task.await()

        # check that the object is deleted before sending to the LV the order to update
        # the database and LV state accordingly.
        case check_if_exists_in_bucket(bucket, key) do
          nil ->
            send(self(), {:delete, key})
            {:noreply, socket}

          _ ->
            Logger.warning("Object not deleted")
            {:noreply, App.send_flash!(socket, :error, "Object not removed from the bucket")}
        end
    end
  end

  # Task.await receives the S3 delete response: a 204 no content. We don't know if the object is deleted so we check after.
  # {:ok,
  #  %{
  #    body: "",
  #    headers: [
  #      {"x-amz-id-2",
  #       "TnK3TiuJVAiVxg06DwH9Eh02SFHVj+URLy35+S5LhapUcO4buc07k+8CeYNyxoIhrTQTbHGcE8I="},
  #      {"x-amz-request-id", "SJEMQQ3EG7R6XYGB"},
  #      {"Date", "Sat, 02 Sep 2023 23:42:11 GMT"},
  #      {"Server", "AmazonS3"}
  #    ],
  #    status_code: 204
  #  }}

  @impl true
  def handle_event("download", %{"name" => ""}, socket) do
    {:noreply, socket}
  end

  # Download in a Task from S3 into a file with a given name from the form.
  # Using "send_flash!" to send a flash to the parent LV.
  @impl true
  def handle_event(
        "download",
        %{"input" => %{"name" => name}, "key" => key, "ext" => ext},
        socket
      ) do
    name = name <> ext
    bucket = bucket()
    dest = build_dest(name)
    pid = self()

    changeset = Input.create_changeset(%{"name" => name})

    request =
      case changeset.valid? do
        true ->
          Task.start(fn ->
            save_local(pid, bucket, key, dest)
          end)

        false ->
          :error
      end

    case request do
      :error ->
        {:noreply,
         socket
         |> App.clear_flash!()
         |> App.send_flash!(:error, "Invalid file name")}

      {:ok, _} ->
        {:noreply, reset_form(socket)}
    end
  end

  # Task: stream from S3 to local file. Send msg to the LV
  def save_local(pid, bucket, key, dest) do
    ExAws.S3.download_file(bucket, key, :memory)
    |> ExAws.stream!()
    |> Stream.into(File.stream!(dest))
    |> Stream.run()

    send(pid, {:success, :download})
  rescue
    e in ExAws.Error ->
      send(pid, {:fail, {:error, inspect(e.message)}})

    _ ->
      send(pid, {:fail, {:error, :stream_error}})
  end

  @doc """
  If the key doesn't exist, it returns `nil`, otherwise an object of the form:
    %{
      owner: %{
        id: "54a149a5522afd4a6424f8f77e41c25521ad980403aba904f7cc286e3a5187f9",
        display_name: ""
      },
      size: "890601",
      key: "bafkreibydopavab5llmih2moggi2hj3unqgn3h5astezo6vsfnciiwyanu",
      last_modified: "2023-09-02T23:46:32.000Z",
      storage_class: "STANDARD",
      e_tag: "\"845b6f8b2343842e9bf055e27407bafa\""
    }
  """

  def check_if_exists_in_bucket(bucket, key) do
    ExAws.S3.list_objects(bucket)
    |> ExAws.request!()
    |> get_in([:body, :contents])
    |> Enum.find(&(&1.key == key))
  end

  defp reset_form(socket) do
    assign(socket, :form_dwld, to_form(Input.create_changeset(%{})))
  end

  defp build_dest(name) do
    Path.join([:code.priv_dir(:app), "static", "image_uploads", "#{name}"])
  end

  defp bucket do
    Application.get_env(:ex_aws, :original_bucket)
  end
end
