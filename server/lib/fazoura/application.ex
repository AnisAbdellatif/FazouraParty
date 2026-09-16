defmodule Fazoura.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Fazoura.Quizzes.ImageSweeper

  @impl true
  def start(_type, _args) do
    Fazoura.Metrics.setup()

    children =
      [
        FazouraWeb.Telemetry,
        # Phase 1 runs without a database; see `:start_repo` in config.exs.
        if(Application.get_env(:fazoura, :start_repo, true), do: Fazoura.Repo),
        {DNSCluster, query: Application.get_env(:fazoura, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Fazoura.PubSub},
        {Registry, keys: :unique, name: Fazoura.Rooms.Registry},
        Fazoura.Rooms.Images,
        {DynamicSupervisor, name: Fazoura.Rooms.Supervisor, strategy: :one_for_one},
        if(Application.get_env(:fazoura, :start_repo, true),
          do: ImageSweeper.child_spec_if_enabled()
        ),
        FazouraWeb.Endpoint,
        # Last, so it is the first to stop: it tells live rooms to close while the
        # endpoint's sockets are still open.
        Fazoura.Rooms.Drain
      ]
      |> Enum.reject(&is_nil/1)

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Fazoura.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FazouraWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
