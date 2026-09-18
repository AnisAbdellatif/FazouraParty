defmodule FazouraWeb.Router do
  use FazouraWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Writes cost the server memory, disk or database rows and need no account, so they
  # are metered per IP. Reads are cheap and bounded already (`Quizzes.list/1` clamps
  # its own limit), so they stay unmetered.
  pipeline :create_room do
    plug FazouraWeb.Plugs.RateLimit, bucket: :rooms, limit: 20, window_ms: 60_000
  end

  pipeline :upload do
    plug FazouraWeb.Plugs.RateLimit, bucket: :images, limit: 60, window_ms: 60_000
  end

  pipeline :publish do
    plug FazouraWeb.Plugs.RateLimit, bucket: :quizzes, limit: 30, window_ms: 60_000
  end

  # The admin dashboard is the only HTML this server serves.
  pipeline :admin do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FazouraWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug FazouraWeb.Plugs.AdminAuth
  end

  scope "/", FazouraWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/admin", FazouraWeb.Admin do
    pipe_through :admin

    live_session :admin, on_mount: {FazouraWeb.Admin.Auth, :ensure_admin} do
      live "/", StatsLive
      live "/quizzes", QuizzesLive
      live "/tags", TagsLive
    end
  end

  scope "/api", FazouraWeb do
    pipe_through [:api, :create_room]

    post "/rooms", RoomController, :create
  end

  scope "/api", FazouraWeb do
    pipe_through [:api, :publish]

    post "/quizzes", QuizController, :create
    put "/quizzes/:id", QuizController, :update
    delete "/quizzes/:id", QuizController, :delete
  end

  scope "/api", FazouraWeb do
    pipe_through [:api, :upload]

    post "/images", ImageController, :create
  end

  scope "/api", FazouraWeb do
    pipe_through :api

    get "/quizzes", QuizController, :index
    get "/quizzes/:id/download", QuizController, :download
    get "/quizzes/:id", QuizController, :show
    get "/tags", QuizController, :tags
  end

  # Images are fetched with image Accept headers, so no JSON content negotiation.
  scope "/api", FazouraWeb do
    get "/room-images/:key", RoomImageController, :show
  end
end
