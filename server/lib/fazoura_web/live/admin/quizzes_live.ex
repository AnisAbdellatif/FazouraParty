defmodule FazouraWeb.Admin.QuizzesLive do
  @moduledoc "Moderation: add presets, promote community quizzes, remove anything."

  use FazouraWeb, :live_view

  alias Fazoura.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page: :quizzes, q: "", json: "") |> load()}
  end

  defp load(socket), do: assign(socket, quizzes: Admin.list_quizzes(q: socket.assigns.q))

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(q: q) |> load()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Admin.delete_quiz(id) do
      {:ok, quiz} ->
        {:noreply, socket |> put_flash(:info, ~s(Deleted "#{quiz.title}".)) |> load()}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "That quiz is already gone.") |> load()}
    end
  end

  def handle_event("toggle_preset", %{"id" => id, "preset" => preset}, socket) do
    preset? = preset == "true"

    case Admin.set_preset(id, preset?) do
      {:ok, quiz} ->
        message =
          if preset?,
            do: ~s("#{quiz.title}" is now a preset, hostable as /#{quiz.slug}.),
            else: ~s("#{quiz.title}" is a community quiz again.)

        {:noreply, socket |> put_flash(:info, message) |> load()}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Couldn't change that quiz.") |> load()}
    end
  end

  def handle_event("add_preset", %{"json" => json}, socket) do
    case Admin.create_preset(json) do
      {:ok, quiz} ->
        {:noreply,
         socket
         |> assign(json: "")
         |> put_flash(:info, ~s(Added preset "#{quiz.title}".))
         |> load()}

      {:error, :invalid_json} ->
        {:noreply, socket |> assign(json: json) |> put_flash(:error, "That isn't valid JSON.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(json: json)
         |> put_flash(:error, "The quiz is invalid: #{errors(changeset)}")}
    end
  end

  # "title can't be blank · questions must be a list of 1 to 1024 questions"
  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join(" · ", fn {field, messages} ->
      "#{field} #{messages |> List.flatten() |> Enum.join(", ")}"
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h2>Quizzes</h2>
    <form id="quiz-search" phx-change="search" phx-submit="search" class="row">
      <input
        type="text"
        name="q"
        value={@q}
        placeholder="Search by title or tag"
        phx-debounce="250"
        autocomplete="off"
      />
    </form>

    <div class="panel" style="margin-top:14px">
      <p :if={@quizzes == []} class="empty">No quizzes match.</p>
      <table :if={@quizzes != []}>
        <thead>
          <tr>
            <th>Quiz</th>
            <th>Tags</th>
            <th>Questions</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={quiz <- @quizzes} id={"quiz-#{quiz.id}"}>
            <td>
              {quiz.title}
              <span :if={quiz.source == "builtin"} class="pill preset">preset</span>
              <div :if={quiz.description} class="muted">{quiz.description}</div>
              <div :if={quiz.slug} class="muted">/{quiz.slug}</div>
            </td>
            <td class="muted">{Enum.map_join(quiz.quiz_tags, ", ", & &1.tag)}</td>
            <td class="muted">
              {quiz.question_count}
              <span :if={quiz.has_photos}>· photos</span>
            </td>
            <td>
              <button
                phx-click="toggle_preset"
                phx-value-id={quiz.id}
                phx-value-preset={to_string(quiz.source != "builtin")}
              >
                {if quiz.source == "builtin", do: "Unset preset", else: "Make preset"}
              </button>
              <button
                class="danger"
                phx-click="delete"
                phx-value-id={quiz.id}
                phx-confirm={~s(Delete "#{quiz.title}" for everyone? This can't be undone.)}
              >
                Delete
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <details>
      <summary>Add a preset from a quiz document</summary>
      <form id="add-preset" phx-submit="add_preset">
        <textarea name="json" placeholder={placeholder()} spellcheck="false">{@json}</textarea>
        <p class="muted">
          The same JSON as <code>priv/quizzes/*.json</code> and the apps (QUIZ_FORMAT.md §2).
          Presets are public, hostable by everyone and shown first when browsing.
        </p>
        <button class="primary" type="submit">Add preset</button>
      </form>
    </details>
    """
  end

  defp placeholder do
    ~s({"format_version": 1, "title": "Pub Night", "tags": ["general"], "questions": [ ... ]})
  end
end
