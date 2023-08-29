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
    Logger.info("On mount check")

    case Accounts.get_user_by_session_token(user_token) do
      nil ->
        Logger.warning("not found on mount")
        {:halt, redirect(socket, to: "/")}

      user ->
        socket =
          socket
          |> assign_new(:current_user, fn -> user end)
          |> assign_new(:uploaded_files, fn ->
            case Gallery.get_urls_by_user(user) |> dbg() do
              nil -> []
              list -> list
            end
          end)

        {:cont, socket}
    end
  end

  def on_mount(:default, _p, _session, socket) do
    Logger.warning("not Logged in")
    {:halt, push_redirect(socket, to: "/")}
  end
end
