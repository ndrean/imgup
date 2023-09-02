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
            <.icon name="hero-arrow-down-tray" />
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
    # {:ok, assign(socket, :form_dwld, to_form(%{"name" => ""}))}
  end

  @impl true
  def handle_event("change", %{"input" => input, "key" => _key, "ext" => _ext}, socket) do
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

  @impl true
  def handle_event("download", %{"name" => ""}, socket) do
    {:noreply, socket}
  end

  # extension if reset as the original file.
  # !! flash messages are only rendered by parent Livevewi -> `send_flash!`
  @impl true
  def handle_event(
        "download",
        %{"input" => %{"name" => name}, "key" => key, "ext" => ext},
        socket
      ) do
    bucket = bucket()
    dest = build_dest(name, ext)

    changeset = Input.create_changeset(%{"name" => name})

    request =
      case changeset.valid? do
        true ->
          ExAws.S3.download_file(bucket, key, dest)
          |> ExAws.request()

        false ->
          :error
      end

    case request do
      {:ok, :done} ->
        {:noreply,
         socket
         |> App.clear_flash!()
         |> App.send_flash!(:info, "Success, file saved locally")
         |> reset_form()}

      :error ->
        {:noreply, socket}

      {:error, msg} ->
        Logger.warning(inspect(msg))

        {:noreply,
         socket
         |> App.clear_flash!()
         |> App.send_flash!(:error, "An error occured when saving: #{inspect(msg)}")
         |> reset_form()}
    end
  end

  def check_if_exists_in_bucket(bucket, key) do
    ExAws.S3.list_objects(bucket)
    |> ExAws.request!()
    |> get_in([:body, :contents])
    |> Enum.find(&(&1.key == key))
  end

  defp reset_form(socket) do
    assign(socket, :form_dwld, to_form(Input.create_changeset(%{})))
  end

  defp build_dest(name, extension) do
    Path.join([:code.priv_dir(:app), "static", "image_uploads", "#{name}.#{extension}"])
  end

  defp bucket do
    Application.get_env(:ex_aws, :original_bucket)
  end
end
