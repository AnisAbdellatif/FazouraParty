defmodule FazouraWeb.RoomReportTest do
  @moduledoc """
  Reporting from inside a game (QUIZ_FORMAT.md §5.9).

  The room is where content is actually seen — browsing a quiz shows a title,
  a description and tags, and nothing a player would object to. This is the
  path from "I am looking at this question" to a row in the review queue,
  without a quiz id ever being broadcast.
  """

  use FazouraWeb.ConnCase, async: false

  import Phoenix.ChannelTest

  alias Fazoura.{QuizFixtures, Quizzes}
  alias Fazoura.Quizzes.Reports
  alias Fazoura.Rooms

  @endpoint FazouraWeb.Endpoint
  @reporter "reporter-key-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  # A room playing a published quiz, with one player in it.
  defp public_room(_context) do
    quiz = QuizFixtures.published!(%{"title" => "Public Night"})
    {:ok, code, host_token} = Rooms.create(Quizzes.to_pack(quiz))
    {:ok, %{player_token: player_token}, _socket} = join_room(code, %{"display_name" => "Sam"})

    %{quiz: quiz, code: code, host_token: host_token, player_token: player_token}
  end

  defp as_player(conn, token),
    do:
      conn |> put_req_header("x-player-token", token) |> put_req_header("x-owner-key", @reporter)

  describe "a player reporting what they are looking at" do
    setup :public_room

    test "records it against the quiz the question came from", %{
      conn: conn,
      code: code,
      quiz: quiz,
      player_token: token
    } do
      assert conn
             |> as_player(token)
             |> post(~p"/api/rooms/#{code}/report", %{
               "reason" => "sexual",
               "note" => "The photo on this one."
             })
             |> response(204)

      assert [queued] = Reports.open()
      assert queued.quiz.id == quiz.id
      assert hd(queued.reports).note == "The photo on this one."
    end

    test "a named question is looked up in the room's own pack", %{
      conn: conn,
      code: code,
      quiz: quiz,
      player_token: token
    } do
      pack = Quizzes.to_pack(quiz)
      last = List.last(pack.questions)

      assert conn
             |> as_player(token)
             |> post(~p"/api/rooms/#{code}/report", %{
               "reason" => "hate",
               "question_id" => last.id
             })
             |> response(204)

      assert [queued] = Reports.open()
      assert queued.quiz.id == quiz.id
    end

    test "a question from another room is not in this one", %{
      conn: conn,
      code: code,
      player_token: token
    } do
      assert %{"code" => "question_not_found"} =
               conn
               |> as_player(token)
               |> post(~p"/api/rooms/#{code}/report", %{
                 "reason" => "spam",
                 "question_id" => "not-a-question-here"
               })
               |> json_response(404)
    end

    test "the host may report too", %{conn: conn, code: code, host_token: host_token} do
      assert conn
             |> put_req_header("x-host-token", host_token)
             |> put_req_header("x-owner-key", @reporter)
             |> post(~p"/api/rooms/#{code}/report", %{"reason" => "illegal"})
             |> response(204)

      assert Reports.open_count() == 1
    end
  end

  describe "the quiz id stays on the server" do
    setup :public_room

    test "no snapshot a player receives carries it", %{code: code, quiz: quiz} do
      # The reason this endpoint exists at all. Putting the id in `state` would
      # be the easy way to let a client report, and would also hand every player
      # `GET /api/quizzes/:id/download` — which returns the accepted answers.
      {:ok, _reply, _socket} = join_room(code, %{"display_name" => "Ada"})
      assert_push "state", snapshot

      encoded = Jason.encode!(snapshot)
      refute encoded =~ quiz.id

      # The title is broadcast, and always was: it is what the lobby shows.
      assert encoded =~ quiz.title
    end
  end

  describe "being in the room is the price of reporting from it" do
    setup :public_room

    test "a made-up token is told nothing, not refused", %{conn: conn, code: code} do
      assert %{"code" => "room_not_found"} =
               conn
               |> as_player("forged")
               |> post(~p"/api/rooms/#{code}/report", %{"reason" => "spam"})
               |> json_response(404)

      assert Reports.open() == []
    end

    test "and neither is somebody with no token at all", %{conn: conn, code: code} do
      assert %{"code" => "room_not_found"} =
               conn
               |> put_req_header("x-owner-key", @reporter)
               |> post(~p"/api/rooms/#{code}/report", %{"reason" => "spam"})
               |> json_response(404)
    end

    test "a real room answers a guesser exactly as a made-up one does", %{
      conn: conn,
      code: code
    } do
      # The point of the token: without it this endpoint would say which
      # six-character codes are live games, which `GET /api/rooms/:code` goes
      # out of its way not to (PROTOCOL.md §3.1).
      real =
        conn
        |> as_player("forged")
        |> post(~p"/api/rooms/#{code}/report", %{"reason" => "spam"})
        |> json_response(404)

      invented =
        conn
        |> as_player("forged")
        |> post(~p"/api/rooms/ZZZZZZ/report", %{"reason" => "spam"})
        |> json_response(404)

      assert real == invented
    end

    test "a token for one room does not work in another", %{conn: conn, player_token: token} do
      other = QuizFixtures.published!(%{"title" => "Somewhere Else"})
      {:ok, other_code, _host} = Rooms.create(Quizzes.to_pack(other))

      assert %{"code" => "room_not_found"} =
               conn
               |> as_player(token)
               |> post(~p"/api/rooms/#{other_code}/report", %{"reason" => "spam"})
               |> json_response(404)
    end
  end

  describe "a private quiz" do
    test "has nothing published to take down", %{conn: conn} do
      # Hosted inline and never stored, so there is no row anybody could act on
      # — and saying so is more honest than accepting a report into a void.
      {:ok, pack, _keys, _bytes} =
        Quizzes.inline_pack(QuizFixtures.quiz_params(%{"title" => "Just For Us"}))

      {:ok, code, _host_token} = Rooms.create(pack)
      {:ok, %{player_token: token}, _socket} = join_room(code, %{"display_name" => "Sam"})

      assert %{"code" => "quiz_not_public"} =
               conn
               |> as_player(token)
               |> post(~p"/api/rooms/#{code}/report", %{"reason" => "sexual"})
               |> json_response(422)

      assert Reports.open() == []
    end
  end

  describe "the reason still has to be one of ours" do
    setup :public_room

    test "a made-up one is refused", %{conn: conn, code: code, player_token: token} do
      assert %{"code" => "invalid_report"} =
               conn
               |> as_player(token)
               |> post(~p"/api/rooms/#{code}/report", %{"reason" => "boring"})
               |> json_response(422)
    end
  end
end
