defmodule FazouraWeb.Router do
  use FazouraWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
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
    pipe_through :api

    post "/rooms", RoomController, :create

    get "/quizzes", QuizController, :index
    post "/quizzes", QuizController, :create
    get "/quizzes/:id", QuizController, :show
    put "/quizzes/:id", QuizController, :update
    delete "/quizzes/:id", QuizController, :delete

    get "/tags", QuizController, :tags

    post "/images", ImageController, :create
  end

  # Images are fetched with image Accept headers, so no JSON content negotiation.
  scope "/api", FazouraWeb do
    get "/room-images/:key", RoomImageController, :show
  end
end
