defmodule FazouraWeb.Router do
  use FazouraWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Writes cost the server memory, disk or database rows and need no account, so they
  # are metered per IP. Reads are cheap and bounded already (`Quizzes.list/1` clamps
  # its own limit), so they stay unmetered — with one exception below.
  pipeline :create_room do
    plug FazouraWeb.Plugs.RateLimit, bucket: :rooms, limit: 20, window_ms: 60_000
  end

  pipeline :room_status do
    plug FazouraWeb.Plugs.RateLimit, bucket: :room_status, limit: 60, window_ms: 60_000
  end

  pipeline :upload do
    plug FazouraWeb.Plugs.RateLimit, bucket: :images, limit: 60, window_ms: 60_000
  end

  pipeline :publish do
    plug FazouraWeb.Plugs.RateLimit, bucket: :quizzes, limit: 30, window_ms: 60_000
  end

  # The one expensive read: building a `.fazoura` archive holds the whole quiz and
  # every one of its photos in memory at once, so a handful of concurrent callers is
  # worth far more than a handful of listings. Metered well below the other reads.
  pipeline :archive do
    plug FazouraWeb.Plugs.RateLimit, bucket: :archives, limit: 10, window_ms: 60_000
  end

  # Public pages (the privacy policy). No session: nothing on them needs one.
  pipeline :page do
    plug :accepts, ["html"]
    plug :put_secure_browser_headers
  end

  # The admin dashboard is the only HTML this server renders.
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

  scope "/", FazouraWeb do
    pipe_through :page

    get "/privacy", PageController, :privacy
  end

  scope "/admin", FazouraWeb.Admin do
    pipe_through :admin

    get "/quizzes/:id/archive", QuizController, :archive
    get "/submissions/:id/photo", SubmissionController, :photo

    live_session :admin, on_mount: {FazouraWeb.Admin.Auth, :ensure_admin} do
      live "/", StatsLive
      live "/review", ReviewLive
      live "/quizzes", QuizzesLive
      live "/quizzes/:id/edit", QuizEditLive
      live "/tags", TagsLive
    end
  end

  scope "/api", FazouraWeb do
    pipe_through [:api, :create_room]

    post "/rooms", RoomController, :create
  end

  # Metered although it is a read: an unknown code costs a registry miss, but a
  # real one reaches the room's own process, and that process is running a live
  # game. Generous enough that the app's one call per launch never notices.
  scope "/api", FazouraWeb do
    pipe_through [:api, :room_status]

    get "/rooms/:code", RoomController, :show
  end

  scope "/api", FazouraWeb do
    pipe_through [:api, :publish]

    post "/quizzes", QuizController, :create
    put "/quizzes/:id", QuizController, :update
    delete "/quizzes/:id", QuizController, :delete
    delete "/submissions/:id", QuizController, :withdraw
  end

  scope "/api", FazouraWeb do
    pipe_through [:api, :upload]

    post "/images", ImageController, :create
  end

  scope "/api", FazouraWeb do
    pipe_through :api

    get "/quizzes", QuizController, :index
    get "/submissions", QuizController, :submissions
    get "/quizzes/:id/download", QuizController, :download
    get "/quizzes/:id", QuizController, :show
    get "/tags", QuizController, :tags
  end

  scope "/api", FazouraWeb do
    pipe_through [:api, :archive]

    get "/quizzes/:id/archive", QuizController, :archive
  end

  # Images are fetched with image Accept headers, so no JSON content negotiation.
  scope "/api", FazouraWeb do
    get "/room-images/:key", RoomImageController, :show
  end
end
