defmodule AppWeb.OneTapController do
  use AppWeb, :controller
  alias App.{Accounts, Accounts.User}
  alias AppWeb.UserAuth
  require Logger

  def check_csrf(conn, _opts) do
    %{cookies: %{"g_csrf_token" => g_csrf_cookies}} = Plug.Conn.fetch_cookies(conn)
    g_csrf_params = Map.get(conn.params, "g_csrf_token")

    if g_csrf_cookies !== g_csrf_params do
      conn
      |> fetch_flash()
      |> fetch_session()
      |> put_flash(:error, "CSRF token mismatch")
      |> redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

  plug :check_csrf

  def handle(conn, %{"credential" => jwt}) do
    g_nonce = fetch_session(conn) |> get_session(:g_nonce)

    with {:ok, %{email: email} = _profile} <-
           ElixirGoogleCerts.verified_identity(%{
             g_nonce: g_nonce,
             jwt: jwt
           }),
         user = %User{} <- Accounts.get_user_by_email(email) do
      conn
      |> fetch_session()
      |> fetch_flash()
      |> put_flash(:info, "Welcome back!")
      |> put_session(:origin, "google_one_tap")
      |> UserAuth.log_in_user(user)
    else
      nil ->
        conn
        |> fetch_session()
        |> fetch_flash()
        |> put_flash(
          :info,
          "If we find your account, you will be logged in"
        )
        |> redirect(to: ~p"/")

      {:error, errors} ->
        conn
        |> fetch_session()
        |> fetch_flash()
        |> put_flash(:error, inspect(errors))
        |> redirect(to: ~p"/")
    end
  end

  def handle(conn, msg) do
    Logger.warning("OneTap error: #{inspect(msg)}")
    redirect(conn, to: ~p"/")
  end
end
