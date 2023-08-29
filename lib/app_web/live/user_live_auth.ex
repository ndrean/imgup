defmodule AppWeb.UserLiveAuth do
  import Phoenix.LiveView
  import Phoenix.Component
  require Logger

  @moduledoc """
  Following <https://hexdocs.pm/phoenix_live_view/security-model.html#mounting-considerations>
  """

  # defp path_in_socket(_p, url, socket) do
  #   {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(url).path)}
  # end

  def on_mount(:default, _p, %{"user_token" => user_token} = _session, socket) do
    Logger.info("On mount check")

    case App.Accounts.get_user_by_session_token(user_token) do
      nil ->
        Logger.warning("not found on mount")
        {:halt, redirect(socket, to: "/")}

      user ->
        {:cont, assign_new(socket, :current_user, fn -> user end)}
    end
  end

  def on_mount(:default, _p, _session, socket) do
    Logger.warning("not Logged in")
    {:halt, push_redirect(socket, to: "/")}
  end
end
