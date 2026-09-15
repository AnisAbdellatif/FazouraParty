defmodule FazouraWeb.Router do
  use FazouraWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FazouraWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/api", FazouraWeb do
    pipe_through :api

    post "/rooms", RoomController, :create

    get "/quizzes", QuizController, :index
    post "/quizzes", QuizController, :create
    get "/quizzes/:id", QuizController, :show
    put "/quizzes/:id", QuizController, :update
    patch "/quizzes/:id", QuizController, :set_visibility
    delete "/quizzes/:id", QuizController, :delete

    post "/images", ImageController, :create
  end
end
