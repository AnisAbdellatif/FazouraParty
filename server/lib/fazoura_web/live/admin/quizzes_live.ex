defmodule FazouraWeb.Admin.QuizzesLive do
  @moduledoc "Moderation: add presets, promote community quizzes, remove anything."

  use FazouraWeb, :live_view

  alias Fazoura.Admin
  alias Fazoura.Quizzes.Archive

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page: :quizzes, q: "", json: "", adding: false)
     |> allow_upload(:package,
       accept: ~w(.fazoura),
       max_entries: 1,
       max_file_size: Archive.max_bytes(),
       # One button: choosing the file is the whole gesture. Nothing is gained by
       # making someone confirm a file they just picked from a dialog.
       auto_upload: true,
       progress: &import_package/3
     )
     |> load()}
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
    socket = assign(socket, adding: true)

    case Admin.create_preset(json) do
      {:ok, quiz} ->
        {:noreply,
         socket
         |> assign(json: "")
         |> put_flash(:info, ~s(Added preset "#{quiz.title}".))
         |> push_navigate(to: ~p"/admin/quizzes/#{quiz.id}/edit")}

      {:error, :invalid_json} ->
        {:noreply, socket |> assign(json: json) |> put_flash(:error, "That isn't valid JSON.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(json: json)
         |> put_flash(:error, "The quiz is invalid: #{Admin.error_messages(changeset)}")}
    end
  end

  # A file the client itself refused — too large, wrong extension — never reaches
  # `import_package/3`, and a refused entry would sit in the way of the next one. Say
  # what was wrong and drop it, so the button is ready again.
  def handle_event("validate_package", _params, socket) do
    {:noreply,
     Enum.reduce(socket.assigns.uploads.package.entries, socket, fn entry, socket ->
       case upload_errors(socket.assigns.uploads.package, entry) do
         [] ->
           socket

         [reason | _rest] ->
           socket
           |> put_flash(:error, upload_error(reason))
           |> cancel_upload(:package, entry.ref)
       end
     end)}
  end

  defp import_package(:package, entry, socket) do
    if entry.done? do
      imported =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, path |> File.read!() |> Admin.create_preset_from_package()}
        end)

      {:noreply, added(socket, imported)}
    else
      {:noreply, socket}
    end
  end

  defp added(socket, {:ok, quiz}) do
    socket
    |> put_flash(:info, ~s(Added preset "#{quiz.title}" — #{described(quiz)}.))
    |> push_navigate(to: ~p"/admin/quizzes/#{quiz.id}/edit")
  end

  defp added(socket, {:error, reason}) do
    socket |> assign(adding: true) |> put_flash(:error, package_error(reason))
  end

  defp described(quiz) do
    photos = if quiz.has_photos, do: " with photos", else: ""
    "#{quiz.question_count} questions#{photos}, hostable as /#{quiz.slug}"
  end

  defp package_error(%Ecto.Changeset{} = changeset),
    do: "The quiz in that package is invalid: #{Admin.error_messages(changeset)}"

  defp package_error(:archive_too_large),
    do: "That package is over the #{div(Archive.max_bytes(), 1024 * 1024)} MB limit."

  defp package_error(:invalid_archive), do: "That file isn't a readable .fazoura package."

  defp package_error(:manifest_missing), do: "That package has no manifest.json."

  defp package_error(:manifest_invalid),
    do: "That package's manifest.json doesn't hold a quiz document under \"quiz\"."

  defp package_error({:not_in_the_package, path}),
    do: "The manifest asks for the photo #{path}, which the package doesn't carry."

  defp package_error({:image_too_large, path}), do: "The photo #{path} is over 2 MB."

  defp package_error({:unsupported_image, path}),
    do: "The photo #{path} isn't a JPEG, PNG or WebP."

  defp package_error({reason, path}), do: "The photo #{path} was refused: #{inspect(reason)}."

  # The LiveView client's own refusals, before a byte reaches us.
  defp upload_error(:too_large),
    do: "That file is over the #{div(Archive.max_bytes(), 1024 * 1024)} MB limit."

  defp upload_error(:not_accepted), do: "Only .fazoura packages can be uploaded here."
  defp upload_error(:too_many_files), do: "One package at a time."
  defp upload_error(reason), do: "That file was refused: #{inspect(reason)}."

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
        dir="auto"
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
              <span dir="auto">{quiz.title}</span>
              <span :if={quiz.source == "builtin"} class="pill preset">preset</span>
              <div :if={quiz.description} class="muted" dir="auto">{quiz.description}</div>
              <div :if={quiz.slug} class="muted">/{quiz.slug}</div>
            </td>
            <td class="muted" dir="auto">{Enum.map_join(quiz.quiz_tags, ", ", & &1.tag)}</td>
            <td class="muted">
              {quiz.question_count}
              <span :if={quiz.has_photos}>· photos</span>
            </td>
            <td>
              <.link navigate={~p"/admin/quizzes/#{quiz.id}/edit"} class="button">Edit</.link>
              <a href={~p"/admin/quizzes/#{quiz.id}/archive"} class="button" download>
                Download
              </a>
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

    <%!-- Held open once an add has been tried, so a rejected one can be fixed and
    re-submitted without hunting for the form again. --%>
    <details open={@adding}>
      <summary>Add a preset</summary>

      <%!-- The file input is the button: a label triggers the one it wraps, so the
      dialog opens on the click and the upload starts on the choice. There is nothing
      left to confirm. --%>
      <form id="add-package" phx-change="validate_package">
        <label class="button primary">
          <.live_file_input upload={@uploads.package} class="hidden" /> Upload a package
        </label>
        <p :for={entry <- @uploads.package.entries} class="muted">
          Reading {entry.client_name}… {entry.progress}%
        </p>
        <p :for={error <- upload_errors(@uploads.package)} class="muted">
          {upload_error(error)}
        </p>
        <p class="muted">
          A <code>.fazoura</code> package (QUIZ_FORMAT.md §5.3b): one ZIP holding the quiz
          and its photos, as <code>GET /api/quizzes/:id/archive</code> sends it and
          <code>tools/fazoura-cli/fazoura quiz pack</code> builds it from a folder. The photos become
          ordinary uploads, so nothing has to be uploaded first.
        </p>
      </form>

      <form id="add-preset" phx-submit="add_preset" style="margin-top:24px">
        <textarea name="json" placeholder={placeholder()} spellcheck="false" dir="auto">{@json}</textarea>
        <p class="muted">
          Or paste the quiz on its own: the same JSON as <code>priv/quizzes/*.json</code>
          and the apps (QUIZ_FORMAT.md §2), with photos by key. Either way the quiz is
          public, hostable by everyone and shown first when browsing.
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
