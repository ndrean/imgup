defmodule AppWeb.UserLiveInit do
  import Phoenix.LiveView
  import Phoenix.Component

  alias App.{Accounts, Gallery}
  require Logger

  @moduledoc """
  Following <https://hexdocs.pm/phoenix_live_view/security-model.html#mounting-considerations>
  """

  # defp path_in_socket(_p, url, socket) do
  #   {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(url).path)}
  # end

  def on_mount(:default, _p, %{"user_token" => user_token} = _session, socket) do
    Logger.info("On mount check #{inspect(user_token)}")

    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user_by_session_token(user_token)
      end)

    current_user = socket.assigns.current_user

    cond do
      current_user == nil ->
        Logger.warning("No user found or confirmed")

        {:halt,
         socket
         |> put_flash(:error, "You must confirm your account")
         |> redirect(to: "/")}

      current_user.confirmed_at == nil ->
        {:halt,
         socket
         |> put_flash(:error, "You must confirm your account")
         |> redirect(to: "/")}

      true ->
        socket =
          assign_new(socket, :uploaded_files, fn ->
            case Gallery.get_urls_by_user(current_user) do
              nil -> []
              list -> list
            end
          end)

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
end
