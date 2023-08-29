defmodule AppWeb.UserLoginLive do
  use AppWeb, :live_view

  def render(assigns) do
    ~H"""
    <section id="login" class="flex justify-center items-center h-screen">
      <div class="mx-auto max-w-sm">
        <div>
          <.header class="text-center">
            Sign in to account
            <:subtitle>
              Don't have an account?
              <.link navigate={~p"/users/register"} class="font-semibold text-brand hover:underline">
                Sign up
              </.link>
              for an account now.
            </:subtitle>
          </.header>

          <.simple_form for={@form} id="login_form" action={~p"/users/log_in"} phx-update="ignore">
            <.input field={@form[:email]} type="email" label="Email" required />
            <.input field={@form[:password]} type="password" label="Password" required />

            <:actions>
              <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
              <.link href={~p"/users/reset_password"} class="text-sm font-semibold">
                Forgot your password?
              </.link>
            </:actions>
            <:actions>
              <.button phx-disable-with="Signing in..." class="w-full">
                Sign in <span aria-hidden="true">→</span>
              </.button>
            </:actions>
          </.simple_form>
        </div>
        <br />
        <p class="text-center">
          or use
          <bold>One-Tap</bold>
        </p>
        <br />
        <div>
          <script src="https://accounts.google.com/gsi/client" async defer>
          </script>
          <div class="border-solid">
            <div
              phx-update="ignore"
              id="g_id_onload"
              data-auto_prompt="true"
              data-client_id={App.g_client_id()}
              data-context="signin"
              data-ux_mode="popup"
              data-login_uri={App.g_cb_url()}
              data-nonce={@g_src_nonce}
            >
            </div>

            <div
              id="g-button"
              phx-update="ignore"
              class="g_id_signin"
              data-type="standard"
              data-shape="pill"
              data-theme="filled_blue"
              data-text="signin_with"
              data-size="large"
              data-logo_alignment="left"
              data-width="300"
            >
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def mount(_params, session, socket) do
    email = live_flash(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, g_src_nonce: session["g_nonce"]),
     temporary_assigns: [form: form]}
  end
end
