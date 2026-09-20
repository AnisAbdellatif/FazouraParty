defmodule FazouraWeb.Admin.TagsLive do
  @moduledoc "The suggested tags the apps offer as quick picks (QUIZ_FORMAT.md §2.3)."

  use FazouraWeb, :live_view

  alias Fazoura.Quizzes
  alias Fazoura.Quizzes.Tag
  alias Fazoura.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page: :tags) |> load()}
  end

  defp load(socket) do
    assign(socket,
      tags: Settings.suggested_tags(),
      in_use: Map.new(Quizzes.popular_tags(100), &{&1.tag, &1.count})
    )
  end

  @impl true
  def handle_event("add", %{"tag" => tag}, socket) do
    save(socket, socket.assigns.tags ++ [tag])
  end

  def handle_event("remove", %{"tag" => tag}, socket) do
    save(socket, Enum.reject(socket.assigns.tags, &(&1 == tag)))
  end

  def handle_event("move", %{"tag" => tag, "by" => by}, socket) when by in ["-1", "1"] do
    tags = socket.assigns.tags

    case Enum.find_index(tags, &(&1 == tag)) do
      nil ->
        {:noreply, socket}

      from ->
        to = from + String.to_integer(by)

        if to in 0..(length(tags) - 1)//1 do
          save(socket, tags |> List.delete_at(from) |> List.insert_at(to, tag))
        else
          {:noreply, socket}
        end
    end
  end

  def handle_event("move", _params, socket), do: {:noreply, socket}

  def handle_event("reset", _params, socket), do: save(socket, [])

  defp save(socket, tags) do
    case Settings.put_suggested_tags(tags) do
      {:ok, _saved} ->
        {:noreply, load(socket)}

      {:error, :too_many_tags} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "At most #{Settings.max_suggested_tags()} suggested tags."
         )}

      {:error, :tag_too_long} ->
        {:noreply,
         put_flash(socket, :error, "Tags can be at most #{Tag.max_length()} characters.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h2>Suggested tags</h2>
    <p class="muted">
      Quick picks in the quiz editor and filter chips when browsing. People can still type
      any tag they like; changes here reach the apps the next time they ask for tags.
    </p>

    <form id="add-tag" phx-submit="add" class="row" style="margin:16px 0">
      <input
        type="text"
        name="tag"
        value=""
        placeholder="Add a tag, e.g. pub quiz"
        maxlength={Tag.max_length()}
        autocomplete="off"
        dir="auto"
        />
      <button class="primary" type="submit">Add</button>
    </form>

    <div class="tags">
      <span :for={{tag, index} <- Enum.with_index(@tags)} class="tagchip">
        <span dir="auto">{tag}</span>
        <span class="muted">{Map.get(@in_use, tag, 0)}</span>
        <button phx-click="move" phx-value-tag={tag} phx-value-by="-1" disabled={index == 0}>
          ↑
        </button>
        <button
          phx-click="move"
          phx-value-tag={tag}
          phx-value-by="1"
          disabled={index == length(@tags) - 1}
        >
          ↓
        </button>
        <button phx-click="remove" phx-value-tag={tag} title={"Remove #{tag}"}>×</button>
      </span>
    </div>

    <p class="muted" style="margin-top:18px">
      The number next to a tag is how many public quizzes use it.
    </p>

    <button
      style="margin-top:8px"
      phx-click="reset"
      data-confirm="Restore the built-in list of suggested tags?"
    >
      Reset to defaults
    </button>
    """
  end
end
