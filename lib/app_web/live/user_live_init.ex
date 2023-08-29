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
      is_current_user_nil(current_user) ->
        Logger.warning("No user found")

        {:halt,
         socket
         |> put_flash(:error, "You must confirm your account")
         |> redirect(to: "/")}

      is_not_confirmed_current_user(current_user) ->
        Logger.warning("User not confirmed")

        {:halt,
         socket
         |> put_flash(:error, "You must confirm your account")
         |> redirect(to: "/")}

      true ->
        socket =
          assign_new(socket, :uploaded_files, fn ->
            get_uploads(current_user)
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

  defp is_current_user_nil(user), do: user == nil
  defp is_not_confirmed_current_user(user), do: user.confirmed_at == nil

  defp get_uploads(user) do
    case Gallery.get_urls_by_user(user) do
      nil -> []
      list -> list
    end
  end
end
