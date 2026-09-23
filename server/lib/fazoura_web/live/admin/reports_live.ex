defmodule FazouraWeb.Admin.ReportsLive do
  @moduledoc """
  Published quizzes somebody has objected to (ADMIN.md §3.3).

  The other end of `FazouraWeb.Admin.ReviewLive`: that one reads a quiz before it
  goes out, this one hears about the ones that got through — because a reader was
  wrong, or because the author edited it afterwards into something else.

  Reports are grouped by quiz, because a quiz is what an admin acts on. Both
  answers — taking it down, or deciding it is fine — clear every open report
  against it, so nothing sits in the queue twice.

  Below them, reports about players in rooms (PROTOCOL.md §3.5): a name or an
  answer, never an account. The answers are a ban from public rooms for a few
  days, ending the room if it is still running, or deciding it was fine.
  """

  use FazouraWeb, :live_view

  alias Fazoura.{Admin, Moderation, Rooms}
  alias Fazoura.Quizzes.Report
  alias Fazoura.Uploads

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page: :reports, open: nil) |> load()}
  end

  defp load(socket) do
    reported = Admin.reported_quizzes()

    players = Moderation.open_player_reports()

    socket
    |> assign(reported: reported, waiting: length(reported) + length(players))
    |> assign(players: players)
    # A quiz that has just been answered is no longer in the list, so the open
    # panel has to follow rather than keep showing a stale copy.
    |> then(fn socket -> assign(socket, open: still_open(socket.assigns.open, reported)) end)
  end

  defp still_open(nil, _reported), do: nil

  defp still_open(open, reported),
    do: Enum.find(reported, &(&1.quiz.id == open.quiz.id))

  @impl true
  def handle_event("open", %{"id" => id}, socket) do
    {:noreply, assign(socket, open: Enum.find(socket.assigns.reported, &(&1.quiz.id == id)))}
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, open: nil)}

  def handle_event("dismiss", %{"id" => id}, socket) do
    case Admin.dismiss_reports(id) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, "Kept the quiz. #{count} #{noun(count)} answered.")
         |> assign(open: nil)
         |> load()}

      {:error, _reason} ->
        {:noreply,
         socket |> put_flash(:error, "That quiz is already gone.") |> assign(open: nil) |> load()}
    end
  end

  def handle_event("take_down", %{"id" => id}, socket) do
    case Admin.delete_quiz(id) do
      {:ok, quiz} ->
        {:noreply,
         socket
         |> put_flash(:info, ~s("#{quiz.title}" was taken down.))
         |> assign(open: nil)
         |> load()}

      {:error, _reason} ->
        {:noreply,
         socket |> put_flash(:error, "That quiz is already gone.") |> assign(open: nil) |> load()}
    end
  end

  def handle_event("ban", %{"id" => id, "days" => days}, socket) do
    socket =
      case Moderation.ban(id, String.to_integer(days)) do
        {:ok, _ban} ->
          put_flash(socket, :info, "Banned from public rooms for #{days} days.")

        {:error, :no_address} ->
          put_flash(socket, :error, "No address was kept for that player; dismiss it instead.")

        {:error, _reason} ->
          put_flash(socket, :error, "That report is already answered.")
      end

    {:noreply, load(socket)}
  end

  def handle_event("end_room", %{"code" => code}, socket) do
    message =
      case Rooms.close(code) do
        :ok -> "Room #{code} has been ended."
        {:error, :room_not_found} -> "Room #{code} has already ended."
      end

    {:noreply, socket |> put_flash(:info, message) |> load()}
  end

  def handle_event("dismiss_player", %{"id" => id}, socket) do
    _ = Moderation.dismiss(id)
    {:noreply, socket |> put_flash(:info, "Report answered.") |> load()}
  end

  defp live?(code), do: Registry.lookup(Fazoura.Rooms.Registry, code) != []

  defp noun(1), do: "report"
  defp noun(_count), do: "reports"

  # How long the oldest report against a quiz has gone unanswered. Play expects
  # an answer within a day, so the number worth showing is the wait, not the
  # timestamp.
  defp waited(reported_at) do
    hours = DateTime.diff(DateTime.utc_now(), reported_at, :hour)

    cond do
      hours < 1 -> "just now"
      hours < 24 -> "#{hours}h ago"
      true -> "#{div(hours, 24)}d ago"
    end
  end

  defp overdue?(reported_at),
    do: DateTime.diff(DateTime.utc_now(), reported_at, :hour) >= 24

  defp reasons(reports) do
    reports
    |> Enum.map(& &1.reason)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_reason, count} -> -count end)
    |> Enum.map_join(" · ", fn
      {reason, 1} -> Report.describe(reason)
      {reason, count} -> "#{Report.describe(reason)} ×#{count}"
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h2>
      Reports
      <span :if={@waiting > 0} class="pill">{@waiting} waiting</span>
    </h2>

    <p class="muted">
      Quizzes that are public now and that somebody has asked to have removed. Answer
      each one within a day: either take the quiz down, or decide it is fine.
    </p>

    <div class="panel" style="margin-top:14px">
      <p :if={@reported == []} class="empty">Nothing reported.</p>
      <table :if={@reported != []}>
        <thead>
          <tr>
            <th>Quiz</th>
            <th>Reports</th>
            <th>Why</th>
            <th>Waiting</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={item <- @reported} id={"reported-#{item.quiz.id}"}>
            <td><span dir="auto">{item.quiz.title}</span></td>
            <td class="muted">{item.count}</td>
            <td class="muted">{reasons(item.reports)}</td>
            <td class={if overdue?(item.first_reported_at), do: "overdue", else: "muted"}>
              {waited(item.first_reported_at)}
            </td>
            <td>
              <button phx-click="open" phx-value-id={item.quiz.id}>Read</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <h3 style="margin-top:22px">Players</h3>
    <p class="muted">
      Names and answers somebody objected to. Players have no accounts: a ban keeps
      that connection out of public rooms for a while, and ending the room stops it now.
    </p>
    <div class="panel" style="margin-top:10px">
      <p :if={@players == []} class="empty">No players reported.</p>
      <table :if={@players != []}>
        <thead>
          <tr>
            <th>Room</th>
            <th>Name</th>
            <th>Answer</th>
            <th>Why</th>
            <th>Waiting</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={report <- @players} id={"player-report-#{report.id}"}>
            <td class="muted">{report.room_code}</td>
            <td><span dir="auto">{report.player_name}</span></td>
            <td class="muted"><span dir="auto">{report.answer || "—"}</span></td>
            <td class="muted">
              {Report.describe(report.reason)}
              <span :if={report.note} dir="auto">— {report.note}</span>
            </td>
            <td class={if overdue?(report.reported_at), do: "overdue", else: "muted"}>
              {waited(report.reported_at)}
            </td>
            <td>
              <div class="row">
                <button
                  :for={days <- Moderation.ban_days()}
                  :if={report.ip_hash}
                  phx-click="ban"
                  phx-value-id={report.id}
                  phx-value-days={days}
                  class="danger"
                >
                  Ban {days}d
                </button>
                <button
                  :if={live?(report.room_code)}
                  phx-click="end_room"
                  phx-value-code={report.room_code}
                  phx-confirm={"End room #{report.room_code} for everyone in it?"}
                >
                  End room
                </button>
                <button phx-click="dismiss_player" phx-value-id={report.id}>It's fine</button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div :if={@open} class="panel" style="margin-top:18px">
      <div class="row" style="justify-content:space-between">
        <h3 dir="auto">{@open.quiz.title}</h3>
        <button phx-click="close">Close</button>
      </div>

      <p class="muted">
        {@open.count} {noun(@open.count)}, the first {waited(@open.first_reported_at)}.
      </p>

      <ul>
        <li :for={report <- @open.reports} style="margin-bottom:6px">
          <strong>{Report.describe(report.reason)}</strong>
          <span :if={report.note} class="muted" dir="auto">— {report.note}</span>
        </li>
      </ul>

      <h4>What is in it</h4>
      <p class="muted" dir="auto">
        Tags: {Enum.map_join(@open.quiz.quiz_tags, ", ", & &1.tag)}
      </p>
      <ol>
        <li :for={question <- @open.quiz.questions} style="margin-bottom:12px">
          <div dir="auto">{question.prompt}</div>
          <div class="muted" dir="auto">{Enum.join(question.accepted_answers, " · ")}</div>
          <img
            :if={question.image_key}
            src={Uploads.path(question.image_key)}
            alt=""
            style="max-width:260px;max-height:200px;border-radius:8px;margin-top:6px"
          />
        </li>
      </ol>

      <div class="row" style="margin-top:12px">
        <button
          phx-click="take_down"
          phx-value-id={@open.quiz.id}
          phx-confirm={~s(Delete "#{@open.quiz.title}" for everyone? This cannot be undone.)}
          class="danger"
        >
          Take it down
        </button>
        <.link navigate={~p"/admin/quizzes/#{@open.quiz.id}/edit"} class="button">
          Edit it instead
        </.link>
        <button phx-click="dismiss" phx-value-id={@open.quiz.id}>Keep it</button>
      </div>
    </div>
    """
  end
end
