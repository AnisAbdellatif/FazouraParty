defmodule FazouraWeb.Admin.ReportsLive do
  @moduledoc """
  Published quizzes somebody has objected to (ADMIN.md §3.3).

  The other end of `FazouraWeb.Admin.ReviewLive`: that one reads a quiz before it
  goes out, this one hears about the ones that got through — because a reader was
  wrong, or because the author edited it afterwards into something else.

  Reports are grouped by quiz, because a quiz is what an admin acts on. Both
  answers — taking it down, or deciding it is fine — clear every open report
  against it, so nothing sits in the queue twice.
  """

  use FazouraWeb, :live_view

  alias Fazoura.Admin
  alias Fazoura.Quizzes.Report
  alias Fazoura.Uploads

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page: :reports, open: nil) |> load()}
  end

  defp load(socket) do
    reported = Admin.reported_quizzes()

    socket
    |> assign(reported: reported, waiting: length(reported))
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
