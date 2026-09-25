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

  pipeline :publish do
    plug FazouraWeb.Plugs.RateLimit, bucket: :quizzes, limit: 30, window_ms: 60_000
  end

  # Reporting is metered tightly. It writes a row on behalf of anybody at all, and
  # a person who has seen something they want gone reports it once — a caller
  # sending more than a handful a minute is not that person.
  pipeline :report do
    plug FazouraWeb.Plugs.RateLimit, bucket: :reports, limit: 10, window_ms: 60_000
  end

  # The one expensive read: building a `.fazoura` archive holds the whole quiz and
  # every one of its photos in memory at once, so a handful of concurrent callers is
  # worth far more than a handful of listings. Metered well below the other reads.
  #
  # Its own `accepts`, not `:api`'s: the answer is a ZIP, and the app asks for one with
  # `accept: application/zip`. Behind `:api` that was a 406 every time, and "Save
  # offline" quietly fell back to fetching the JSON and each photo on its own.
  pipeline :archive do
    plug :accepts, ["zip", "json"]
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
    get "/rules", PageController, :rules
  end

  scope "/admin", FazouraWeb.Admin do
    pipe_through :admin

    get "/quizzes/:id/archive", QuizController, :archive
    get "/submissions/:id/photo", SubmissionController, :photo

    live_session :admin, on_mount: {FazouraWeb.Admin.Auth, :ensure_admin} do
      live "/", StatsLive
      live "/review", ReviewLive
      live "/reports", ReportsLive
      live "/quizzes", QuizzesLive
      live "/quizzes/:id/edit", QuizEditLive
      live "/tags", TagsLive
      live "/codes", CodesLive
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

    get "/rooms", RoomController, :index
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
    pipe_through [:api, :report]

    post "/quizzes/:id/report", QuizController, :report
    post "/rooms/:code/report", RoomController, :report
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
    pipe_through :archive

    get "/quizzes/:id/archive", QuizController, :archive
  end

  # Images are fetched with image Accept headers, so no JSON content negotiation.
  scope "/api", FazouraWeb do
    get "/room-images/:key", RoomImageController, :show
  end
end
