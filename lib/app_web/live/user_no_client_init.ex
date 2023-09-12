defmodule AppWeb.UserNoClientInit do
  import Phoenix.LiveView
  import Phoenix.Component

  alias App.Accounts
  require Logger

  @upload_dir Application.app_dir(:app, ["priv", "static", "image_uploads"])

  @moduledoc """
  Following <https://hexdocs.pm/phoenix_live_view/security-model.html#mounting-considerations>
  """

  # defp path_in_socket(_p, url, socket) do
  #   {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(url).path)}
  # end

  def on_mount(:default, _p, %{"user_token" => user_token} = _session, socket) do
    Logger.info("On mount check #{inspect(user_token)}")
    File.mkdir_p(@upload_dir)

    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user_by_session_token(user_token)
      end)

    current_user = socket.assigns.current_user

    cond do
      current_user == nil ->
        Logger.warning("No user found")

        {:halt,
         socket
         |> put_flash(:error, "You must confirm your account")
         |> redirect(to: "/")}

      # is_not_confirmed_current_user(current_user) ->
      #   Logger.warning("User not confirmed")

      #   {:halt,
      #    socket
      #    |> put_flash(:error, "You must confirm your account")
      #    |> redirect(to: "/")}

      true ->
        socket =
          assign(socket, :uploaded_files_to_S3, [])

        {:cont, socket}
    end
  end

  def on_mount(:default, _p, _session, socket) do
    Logger.warning("No user")

    {:halt,
     socket
     |> put_flash(:error, "You must be logged in")
     |> redirect(to: "/")}
  end

  # defp is_not_confirmed_current_user(user), do: user.confirmed_at == nil
end
