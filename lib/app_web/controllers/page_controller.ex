defmodule AppWeb.PageController do
  use AppWeb, :controller

  @env_required ~w/AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_S3_BUCKET_ORIGINAL/

  def home(conn, _params) do
    init =
      if Envar.is_set_all?(@env_required) do
        "All Set!"
      else
        "cannot be run until all required environment variables are set"
      end

    g_nonce = App.gen_secret()
    # for SignIn
    g_state = App.gen_secret()

    # The home page is often custom made,
    # so skip the default app layout.
    conn
    |> fetch_session()
    |> put_session(:g_state, g_state)
    |> put_session(:g_nonce, g_nonce)
    # |> assign(:g_client_id, System.get_env("GOOGLE_CLIENT_ID"))
    |> assign(:g_src_nonce, g_nonce)
    |> assign(:g_client_id, App.g_client_id())
    |> render(:home, layout: false, env: check_env(@env_required), init: init)
  end

  defp check_env(keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      src =
        "https://raw.githubusercontent.com/dwyl/auth/main/assets/static/images/#{Envar.is_set?(key)}.png"

      Map.put(acc, key, src)
    end)
  end
end
