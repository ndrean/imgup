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

  def g_client_id(), do: System.get_env("GOOGLE_CLIENT_ID")
  def hostname(), do: AppWeb.Endpoint.url()

  def g_cb_url() do
    Path.join(
      hostname(),
      Application.get_application(__MODULE__) |> Application.get_env(:g_cb_uri)
    )
  end

  # def hostname() do
  #   :app
  #   |> Application.fetch_env!(AppWeb.Endpoint)
  #   |> Keyword.fetch!(:url)
  #   |> Enum.into(%{})
  #   |> then(fn map ->
  #     struct(URI.new!(""), map)
  #     |> URI.to_string()
  #   end)
  #   |> dbg()
  # end
end
