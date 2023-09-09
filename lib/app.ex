defmodule App do
  @moduledoc """
  App keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def gen_secret do
    Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  def g_client_id, do: System.get_env("GOOGLE_CLIENT_ID")
  def hostname, do: AppWeb.Endpoint.url()

  @doc """
  Defines the Google callback endpoint. It must correspond to the settings in the Google Dev console.
  """
  def g_cb_url do
    Path.join(
      hostname(),
      Application.get_application(__MODULE__) |> Application.get_env(:g_cb_uri)
    )
  end

  @doc """
  Sends a message to the parent LiveView to render a flash message.
  You must implement a `handle_info({:child_flash, type, msg}, socket)`in the parent LiveView
  """
  def send_flash!(socket, type, message) do
    send(self(), {:child_flash, type, message})
    socket
  end

  def clear_flash!(socket) do
    send(self(), :clear_flash)
    socket
  end

  @doc """
  Get the extension from MIME type
  """
  def get_entry_extension(entry) do
    # entry.client_type |> MIME.extensions() |> hd()
    entry.client_name |> Path.extname()
  end
end
