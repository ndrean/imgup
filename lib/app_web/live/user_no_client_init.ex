defmodule AppWeb.UserNoClientInit do
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
        # _thumbs = get_thumbs(current_user)

        # res =
        #   if length(thumbs) > 0,
        #     do:
        #       Enum.each(thumbs, fn elt ->
        #         with {:ok, thumb} <- Map.fetch(elt, :thumbnail),
        #              {:ok, img} <- Image.open!(thumb, []),
        #              {:ok, _f} <- Image.write(img, Path.basename(elt)) do
        #           :ok
        #         else
        #           :error ->
        #             :error

        #           {:error, msg} ->
        #             inspect(msg)
        #             :error
        #         end
        #       end)
        #       |> dbg()

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

  defp is_current_user_nil(user), do: user == nil
  defp is_not_confirmed_current_user(user), do: user.confirmed_at == nil

  # defp get_thumbs(user) do
  #   case Gallery.get_thumbs_by_user(user) do
  #     nil -> []
  #     list -> list
  #   end
  # end
end
