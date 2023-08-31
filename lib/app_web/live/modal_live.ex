defmodule AppWeb.ModalForm do
  @moduledoc """
  LiveComponent rendered in the modal.
  It displays the "compressed link" and a form to assign a name to file the user wants to download from S3.
  """
  use AppWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.link href={@file.compressed_url} target="_blank">
        <.icon name="hero-link" /> Link to the compressed file:
        <p><%= @file.compressed_url %></p>
      </.link>

      <.simple_form
        id={"dwld-#{@file.key}"}
        for={@form_dwld}
        phx-submit={JS.push("download") |> hide_modal("modal-#{@file.key}")}
        phx-target={@myself}
        phx-value-key={@file.key}
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
    {:ok, assign(socket, :form_dwld, to_form(%{"name" => ""}))}
  end

  @impl true
  def handle_event("change", %{"name" => name}, socket) do
    {:noreply, assign(socket, :form_dwld, to_form(%{"name" => name}))}
  end

  @impl true
  def handle_event("download", %{"name" => ""}, socket) do
    {:noreply, socket}
  end

  # setting the name for the file that is going to be saved. !! extension is set as ".png".
  @impl true
  def handle_event("download", %{"name" => name, "key" => key}, socket) do
    bucket = Application.get_env(:ex_aws, :original_bucket)

    new_file = get_binary_from_s3_bucket(bucket, key)
    :ok = save_named_file_to_private_dir(name: name, data: new_file, extension: "png")
    {:noreply, reset_form(socket)}
  end

  defp reset_form(socket) do
    assign(socket, :form_dwld, to_form(%{}))
  end

  defp get_binary_from_s3_bucket(bucket, key) do
    ExAws.S3.get_object(bucket, key)
    |> ExAws.request!()
    |> Map.get(:body)
  end

  defp save_named_file_to_private_dir(name: name, data: data, extension: extension) do
    name =
      Path.join([:code.priv_dir(:app), "static", "image_uploads", "#{name}.#{extension}"])

    # name =
    #   Application.app_dir(:app, "priv/static/image_uploads") <> "/" <> name <> "." <> extension

    File.write(name, data)
  end
end
