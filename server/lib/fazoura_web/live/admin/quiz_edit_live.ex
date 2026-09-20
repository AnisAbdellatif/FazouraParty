defmodule FazouraWeb.Admin.QuizEditLive do
  @moduledoc """
  Editing one quiz — its metadata and every question (ADMIN.md §3.3).

  The working copy is a plain list of question maps in the socket rather than a
  changeset, because most of what happens here is not validation: adding, removing and
  reordering questions, and replacing a photo. It is validated once, on save, by the same
  `Quiz.changeset/2` that guards the API — there is no second set of rules to keep in
  step.

  Each question carries a `cid` that lives only for this session and names its inputs.
  Positions would be simpler, but they shift when a question is removed or moved, and the
  browser would then keep the text of the question that used to be at that index.
  """

  use FazouraWeb, :live_view

  alias Fazoura.{Admin, Quizzes, Uploads}
  alias Fazoura.Quizzes.Question

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Admin.fetch_quiz(id) do
      {:ok, quiz} ->
        {:ok,
         socket
         |> assign(page: :quizzes, quiz: quiz, photo_for: nil, saved: false)
         |> assign(load(quiz))
         |> allow_upload(:photo,
           accept: ~w(.jpg .jpeg .png .webp),
           max_entries: 1,
           max_file_size: Uploads.max_bytes(),
           auto_upload: true,
           progress: &store_photo/3
         )}

      {:error, :quiz_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That quiz is gone.")
         |> push_navigate(to: ~p"/admin/quizzes")}
    end
  end

  # The stored quiz as the form's fields. Answers are one per line: they can contain
  # commas, so nothing else separates them safely.
  defp load(quiz) do
    %{
      meta: %{
        "title" => quiz.title,
        "description" => quiz.description || "",
        "language" => quiz.language || "en",
        "tags" => Enum.map_join(quiz.quiz_tags, ", ", & &1.tag),
        "seconds" => to_string(div(quiz.default_time_limit_ms, 1000)),
        "difficulty_multiplier" => to_string(quiz.default_difficulty_multiplier)
      },
      questions:
        quiz.questions
        |> Enum.with_index(1)
        |> Enum.map(fn {question, index} ->
          %{
            "cid" => "q#{index}",
            "prompt" => question.prompt,
            "accepted_answers" => Enum.join(question.accepted_answers, "\n"),
            "difficulty" => question.difficulty,
            "seconds" => seconds(question.time_limit_ms),
            "explanation" => question.explanation || "",
            "image_key" => question.image_key || "",
            "image_alt" => question.image_alt || ""
          }
        end),
      next_cid: length(quiz.questions) + 1
    }
  end

  ## Editing

  @impl true
  def handle_event("validate", %{"quiz" => params}, socket) do
    {:noreply, merge(socket, params)}
  end

  def handle_event("add_question", params, socket) do
    socket = merge(socket, params["quiz"])
    cid = "q#{socket.assigns.next_cid}"

    {:noreply,
     socket
     |> assign(next_cid: socket.assigns.next_cid + 1)
     |> assign(questions: socket.assigns.questions ++ [blank(cid)])}
  end

  def handle_event("remove_question", %{"cid" => cid} = params, socket) do
    socket = merge(socket, params["quiz"])
    questions = Enum.reject(socket.assigns.questions, &(&1["cid"] == cid))

    {:noreply,
     socket
     |> assign(questions: questions)
     |> assign(
       photo_for: if(socket.assigns.photo_for == cid, do: nil, else: socket.assigns.photo_for)
     )}
  end

  def handle_event("move_question", %{"cid" => cid, "by" => by} = params, socket) do
    socket = merge(socket, params["quiz"])
    {:noreply, assign(socket, questions: move(socket.assigns.questions, cid, by))}
  end

  # One upload slot serves every question, so the file input is rendered into whichever
  # one asked for it. Two inputs sharing an upload would share its ref, and the second
  # would quietly drive the first.
  def handle_event("choose_photo", %{"cid" => cid} = params, socket) do
    {:noreply, socket |> merge(params["quiz"]) |> assign(photo_for: cid)}
  end

  def handle_event("cancel_photo", params, socket) do
    {:noreply, socket |> merge(params["quiz"]) |> assign(photo_for: nil)}
  end

  def handle_event("remove_photo", %{"cid" => cid} = params, socket) do
    socket = merge(socket, params["quiz"])

    # The file itself is left where it is: `ImageSweeper` collects photos nothing
    # references once they are past its grace period.
    {:noreply,
     assign(socket,
       questions:
         update_question(socket.assigns.questions, cid, fn question ->
           %{question | "image_key" => "", "image_alt" => ""}
         end)
     )}
  end

  def handle_event("save", %{"quiz" => params}, socket) do
    socket = merge(socket, params)

    case Admin.update_quiz(socket.assigns.quiz.id, document(socket.assigns)) do
      {:ok, quiz} ->
        {:noreply,
         socket
         |> assign(quiz: quiz, saved: true)
         |> assign(load(quiz))
         |> put_flash(:info, ~s(Saved "#{quiz.title}" as version #{quiz.version}.))}

      {:error, :quiz_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "That quiz was deleted while you were editing it.")
         |> push_navigate(to: ~p"/admin/quizzes")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, Admin.error_messages(changeset))}
    end
  end

  defp store_photo(:photo, entry, socket) do
    if entry.done? do
      stored =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, path |> File.read!() |> Quizzes.store_own_image()}
        end)

      {:noreply, put_photo(socket, stored)}
    else
      {:noreply, socket}
    end
  end

  defp put_photo(socket, {:ok, image}) do
    socket
    |> assign(
      questions:
        update_question(socket.assigns.questions, socket.assigns.photo_for, fn question ->
          %{question | "image_key" => image.key}
        end)
    )
    |> assign(photo_for: nil)
  end

  defp put_photo(socket, {:error, :image_too_large}) do
    put_flash(socket, :error, "That photo is over #{div(Uploads.max_bytes(), 1024 * 1024)} MB.")
  end

  defp put_photo(socket, {:error, :unsupported_image}) do
    put_flash(socket, :error, "That file isn't a JPEG, PNG or WebP.")
  end

  ## The working copy

  # Everything the form holds, folded back in by `cid` rather than by position, and
  # ignoring any field the form did not send.
  defp merge(socket, nil), do: socket

  defp merge(socket, %{} = params) do
    sent = params["questions"] || %{}

    socket
    |> assign(
      meta: Map.merge(socket.assigns.meta, Map.take(params, Map.keys(socket.assigns.meta)))
    )
    |> assign(
      questions:
        Enum.map(socket.assigns.questions, fn question ->
          case sent[question["cid"]] do
            %{} = fields -> Map.merge(question, Map.take(fields, Map.keys(question)))
            _ -> question
          end
        end)
    )
  end

  defp blank(cid) do
    %{
      "cid" => cid,
      "prompt" => "",
      "accepted_answers" => "",
      "difficulty" => "easy",
      "seconds" => "",
      "explanation" => "",
      "image_key" => "",
      "image_alt" => ""
    }
  end

  # The hidden field carries an absent photo back from the browser as "", not as nil, so
  # nothing here may ask whether the key is merely truthy.
  defp photo?(question), do: question["image_key"] not in [nil, ""]

  defp update_question(questions, cid, fun) do
    Enum.map(questions, fn question ->
      if question["cid"] == cid, do: fun.(question), else: question
    end)
  end

  defp move(questions, cid, by) do
    case Enum.find_index(questions, &(&1["cid"] == cid)) do
      nil -> questions
      index -> shift(questions, index, index + String.to_integer(by))
    end
  end

  defp shift(questions, index, target) when target >= 0 do
    if target < length(questions) do
      question = Enum.at(questions, index)
      questions |> List.delete_at(index) |> List.insert_at(target, question)
    else
      questions
    end
  end

  defp shift(questions, _index, _target), do: questions

  # The working copy as the quiz document `Quiz.changeset/2` takes (QUIZ_FORMAT.md §2).
  defp document(assigns) do
    %{
      "title" => assigns.meta["title"],
      "description" => blank_to_nil(assigns.meta["description"]),
      "language" => assigns.meta["language"],
      "tags" => assigns.meta["tags"] |> String.split(",") |> Enum.map(&String.trim/1),
      "default_settings" => %{
        "time_limit_ms" => milliseconds(assigns.meta["seconds"]),
        "difficulty_multiplier" => assigns.meta["difficulty_multiplier"] == "true"
      },
      "questions" => Enum.map(assigns.questions, &question_document/1)
    }
  end

  defp question_document(question) do
    key = blank_to_nil(question["image_key"])

    %{
      # A question is a photo question exactly when it has a photo. Asking for the type
      # separately would only make it possible to get the two out of step.
      "type" => if(key, do: "text_photo", else: "text"),
      "prompt" => question["prompt"],
      "accepted_answers" =>
        question["accepted_answers"]
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "")),
      "difficulty" => question["difficulty"],
      "time_limit_ms" => milliseconds(question["seconds"]),
      "explanation" => blank_to_nil(question["explanation"]),
      "image" => key && %{"key" => key, "alt" => blank_to_nil(question["image_alt"])}
    }
  end

  # Both sides of the boundary: the protocol counts milliseconds (QUIZ_FORMAT.md §2.2),
  # the form asks for seconds, because nobody types 45000.
  defp seconds(nil), do: ""
  defp seconds(milliseconds), do: to_string(div(milliseconds, 1000))

  defp milliseconds(value) do
    case blank_to_nil(value) do
      nil -> nil
      trimmed -> to_string(String.to_integer(trimmed) * 1000)
    end
  rescue
    # Not a number at all. The changeset says so more usefully than a crash does.
    ArgumentError -> value
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <h2>
      <.link navigate={~p"/admin/quizzes"} class="muted">Quizzes</.link> / {@quiz.title}
    </h2>

    <form id="edit-quiz" phx-change="validate" phx-submit="save">
      <div class="panel pad">
        <div class="fields">
          <label>
            Title
            <input type="text" name="quiz[title]" value={@meta["title"]} autocomplete="off" />
          </label>
          <label>
            Language
            <input type="text" name="quiz[language]" value={@meta["language"]} autocomplete="off" />
          </label>
        </div>

        <label>
          Description
          <input
            type="text"
            name="quiz[description]"
            value={@meta["description"]}
            autocomplete="off"
          />
        </label>

        <label>
          Tags <span class="muted">— 1 to 10, comma separated</span>
          <input type="text" name="quiz[tags]" value={@meta["tags"]} autocomplete="off" />
        </label>

        <div class="fields">
          <label>
            Seconds per question <span class="muted">— 10 to 120</span>
            <input type="number" name="quiz[seconds]" value={@meta["seconds"]} min="10" max="120" />
          </label>
          <label class="check">
            <input type="hidden" name="quiz[difficulty_multiplier]" value="false" />
            <input
              type="checkbox"
              name="quiz[difficulty_multiplier]"
              value="true"
              checked={@meta["difficulty_multiplier"] == "true"}
            /> Difficulty bonus by default
          </label>
        </div>

        <p class="muted">
          {@quiz.source} · version {@quiz.version} · {length(@questions)} questions{if @quiz.slug,
            do: " · /#{@quiz.slug}"}
        </p>
      </div>

      <h2>Questions</h2>

      <div :for={{question, index} <- Enum.with_index(@questions, 1)} class="panel pad question">
        <div class="row between">
          <strong class="muted">{index}</strong>
          <div>
            <button type="button" phx-click="move_question" phx-value-cid={question["cid"]} phx-value-by="-1" disabled={index == 1}>
              Up
            </button>
            <button type="button" phx-click="move_question" phx-value-cid={question["cid"]} phx-value-by="1" disabled={index == length(@questions)}>
              Down
            </button>
            <button type="button" class="danger" phx-click="remove_question" phx-value-cid={question["cid"]}>
              Remove
            </button>
          </div>
        </div>

        <label>
          Prompt
          <input
            type="text"
            name={"quiz[questions][#{question["cid"]}][prompt]"}
            value={question["prompt"]}
            autocomplete="off"
          />
        </label>

        <div class="fields">
          <label>
            Accepted answers <span class="muted">— one per line, up to 10</span>
            <textarea
              name={"quiz[questions][#{question["cid"]}][accepted_answers]"}
              class="answers"
              spellcheck="false"
            >{question["accepted_answers"]}</textarea>
          </label>

          <div>
            <label>
              Difficulty
              <select name={"quiz[questions][#{question["cid"]}][difficulty]"}>
                <option
                  :for={difficulty <- Question.difficulties()}
                  value={difficulty}
                  selected={question["difficulty"] == difficulty}
                >
                  {difficulty}
                </option>
              </select>
            </label>
            <label>
              Seconds <span class="muted">— blank uses the quiz default</span>
              <input
                type="number"
                name={"quiz[questions][#{question["cid"]}][seconds]"}
                value={question["seconds"]}
                min="10"
                max="120"
              />
            </label>
          </div>
        </div>

        <label>
          Explanation <span class="muted">— optional, shown after scoring</span>
          <input
            type="text"
            name={"quiz[questions][#{question["cid"]}][explanation]"}
            value={question["explanation"]}
            autocomplete="off"
          />
        </label>

        <input
          type="hidden"
          name={"quiz[questions][#{question["cid"]}][image_key]"}
          value={question["image_key"]}
        />

        <div class="photo">
          <img :if={photo?(question)} src={Uploads.url(question["image_key"])} alt="" />

          <div class="photo-controls">
            <label :if={photo?(question)}>
              Alt text <span class="muted">— describes the photo, up to 140 characters</span>
              <input
                type="text"
                name={"quiz[questions][#{question["cid"]}][image_alt]"}
                value={question["image_alt"]}
                autocomplete="off"
              />
            </label>

            <div :if={@photo_for == question["cid"]}>
              <.live_file_input upload={@uploads.photo} />
              <button type="button" phx-click="cancel_photo">Cancel</button>
              <p :for={error <- upload_errors(@uploads.photo)} class="muted">{error(error)}</p>
              <p :for={entry <- @uploads.photo.entries} class="muted">
                <span :for={error <- upload_errors(@uploads.photo, entry)}>{error(error)}</span>
              </p>
            </div>

            <div :if={@photo_for != question["cid"]}>
              <button type="button" phx-click="choose_photo" phx-value-cid={question["cid"]}>
                {if photo?(question), do: "Replace photo", else: "Add photo"}
              </button>
              <button
                :if={photo?(question)}
                type="button"
                class="danger"
                phx-click="remove_photo"
                phx-value-cid={question["cid"]}
              >
                Remove photo
              </button>
            </div>
          </div>
        </div>
      </div>

      <p :if={@questions == []} class="empty panel">
        No questions yet — a quiz needs at least one.
      </p>

      <div class="row" style="margin-top:16px">
        <button type="button" phx-click="add_question">Add a question</button>
        <button class="primary" type="submit">Save</button>
        <.link navigate={~p"/admin/quizzes"} class="muted">Back without saving</.link>
      </div>
    </form>
    """
  end

  defp error(:too_large), do: "That photo is over #{div(Uploads.max_bytes(), 1024 * 1024)} MB."
  defp error(:not_accepted), do: "Photos must be JPEG, PNG or WebP."
  defp error(:too_many_files), do: "One photo at a time."
  defp error(reason), do: "That photo was refused: #{inspect(reason)}."
end
