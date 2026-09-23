defmodule FazouraWeb.Admin.ReviewLive do
  @moduledoc """
  The queue between somebody writing a quiz and it being public (ADMIN.md §3.2).

  A submission is still a `.fazoura` package here — nothing about it is a quiz,
  and its photos are not on disk — so this screen reads the package to show what
  is in it. That read is the only place unreviewed content is inflated, and
  `Archive.read/1` caps and checks it first.

  Approving is what turns it into a quiz; until then there is nothing anybody
  can find, host or be served.
  """

  use FazouraWeb, :live_view

  alias Fazoura.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page: :review, open: nil, contents: nil, note: "") |> load()}
  end

  defp load(socket) do
    assign(socket,
      submissions: Admin.pending_submissions(),
      waiting: Admin.pending_submission_count()
    )
  end

  @impl true
  def handle_event("open", %{"id" => id}, socket) do
    # Reading the package is the expensive part, so it happens when somebody
    # actually looks at one rather than for every row in the list.
    with {:ok, submission} <- Admin.fetch_submission(id),
         {:ok, contents} <- Admin.submission_contents(submission) do
      {:noreply, assign(socket, open: submission, contents: contents, note: "")}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "That package could not be read: #{inspect(reason)}.")
         |> assign(open: nil, contents: nil)
         |> load()}
    end
  end

  def handle_event("close", _params, socket),
    do: {:noreply, assign(socket, open: nil, contents: nil, note: "")}

  def handle_event("note", %{"note" => note}, socket),
    do: {:noreply, assign(socket, note: note)}

  def handle_event("approve", %{"id" => id}, socket) do
    case Admin.approve_submission(id) do
      {:ok, quiz} ->
        {:noreply,
         socket
         |> put_flash(:info, ~s("#{quiz.title}" is public.))
         |> assign(open: nil, contents: nil, note: "")
         |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, refusal(reason)) |> load()}
    end
  end

  def handle_event("reject", %{"submission" => id} = params, socket) do
    note = params |> Map.get("note", "") |> String.trim()

    case Admin.reject_submission(id, if(note == "", do: nil, else: note)) do
      {:ok, submission} ->
        {:noreply,
         socket
         |> put_flash(:info, ~s("#{submission.title}" was turned down.))
         |> assign(open: nil, contents: nil, note: "")
         |> load()}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "That submission is already gone.") |> load()}
    end
  end

  # A package that reads but does not make a valid quiz is a refusal worth
  # seeing, not a crash: it is the one thing an admin cannot fix from here.
  defp refusal(%Ecto.Changeset{} = changeset),
    do: "That quiz is not valid: #{Admin.error_messages(changeset)}."

  defp refusal(:not_found), do: "That submission is already gone."
  defp refusal(reason), do: "That package could not be published: #{inspect(reason)}."

  defp answers(%{"accepted_answers" => list}) when is_list(list), do: Enum.join(list, " · ")
  defp answers(_question), do: ""

  defp photo_path(%{"image" => %{"path" => path}}) when is_binary(path), do: path
  defp photo_path(_question), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <h2>
      Review
      <span :if={@waiting > 0} class="pill">{@waiting} waiting</span>
    </h2>

    <p class="muted">
      Nothing here is public yet. A submission is the package a device sent — no quiz,
      no photos on the server — until it is approved.
    </p>

    <div class="panel" style="margin-top:14px">
      <p :if={@submissions == []} class="empty">Nothing waiting.</p>
      <table :if={@submissions != []}>
        <thead>
          <tr>
            <th>Quiz</th>
            <th>Questions</th>
            <th>Submitted</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={submission <- @submissions} id={"submission-#{submission.id}"}>
            <td><span dir="auto">{submission.title}</span></td>
            <td class="muted">
              {submission.question_count}
              <span :if={submission.has_photos}>· photos</span>
            </td>
            <td class="muted">{Calendar.strftime(submission.submitted_at, "%Y-%m-%d %H:%M")}</td>
            <td>
              <button phx-click="open" phx-value-id={submission.id}>Read</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div :if={@open} class="panel" style="margin-top:18px">
      <div class="row" style="justify-content:space-between">
        <h3 dir="auto">{@open.title}</h3>
        <button phx-click="close">Close</button>
      </div>

      <p :if={@contents.document["description"]} class="muted" dir="auto">
        {@contents.document["description"]}
      </p>
      <p class="muted" dir="auto">
        Tags: {Enum.join(@contents.document["tags"] || [], ", ")}
      </p>

      <ol>
        <li :for={question <- @contents.document["questions"] || []} style="margin-bottom:12px">
          <div dir="auto">{question["prompt"]}</div>
          <div class="muted" dir="auto">{answers(question)}</div>
          <img
            :if={photo_path(question)}
            src={~p"/admin/submissions/#{@open.id}/photo?#{[path: photo_path(question)]}"}
            alt=""
            style="max-width:260px;max-height:200px;border-radius:8px;margin-top:6px"
          />
        </li>
      </ol>

      <form
        id={"reject-#{@open.id}"}
        phx-change="note"
        phx-submit="reject"
        class="row"
        style="margin-top:12px"
      >
        <input type="hidden" name="submission" value={@open.id} />
        <input
          type="text"
          name="note"
          value={@note}
          dir="auto"
          placeholder="Why it was turned down — the author's device shows this"
          autocomplete="off"
          style="flex:1"
        />
        <button type="submit" class="danger">Turn down</button>
      </form>

      <button
        phx-click="approve"
        phx-value-id={@open.id}
        phx-confirm={~s(Publish "#{@open.title}" for everyone?)}
        style="margin-top:10px"
      >
        Approve and publish
      </button>
    </div>
    """
  end
end
