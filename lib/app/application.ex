defmodule App.Application do
  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    Logger.info("Vix version: " <> Vix.Vips.version())

    children = [
      AppWeb.Telemetry,
      App.Repo,
      {Task.Supervisor, name: App.TaskSup},
      {Task, fn -> shutdown_when_inactive(:timer.minutes(5)) end},
      {Phoenix.PubSub, name: App.PubSub},
      AppWeb.Endpoint
      # Start a worker by calling: App.Worker.start_link(arg)
      # {App.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: App.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # https://fly.io/phoenix-files/shut-down-idle-phoenix-app/
  defp shutdown_when_inactive(every_ms) do
    Process.sleep(every_ms)

    if :ranch.procs(AppWeb.Endpoint.HTTP, :connections) == [] do
      System.stop(0)
    else
      shutdown_when_inactive(every_ms)
    end
  end
end
