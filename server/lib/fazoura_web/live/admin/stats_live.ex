defmodule FazouraWeb.Admin.StatsLive do
  @moduledoc "Key indicators: what's live right now, and what the library holds."

  use FazouraWeb, :live_view

  alias Fazoura.Admin

  @refresh_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)
    {:ok, socket |> assign(page: :stats) |> load()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  defp load(socket), do: assign(socket, stats: Admin.stats())

  @impl true
  def render(assigns) do
    ~H"""
    <h2>Live now</h2>
    <section class="cards">
      <.stat label="Live games" value={@stats.live_rooms} hint={phases(@stats.by_phase)} />
      <.stat
        label="Live players"
        value={@stats.live_connections}
        hint={"#{@stats.live_players} seated in a game"}
      />
      <.stat
        label="Games hosted"
        value={@stats.rooms_created}
        hint="rooms created since the server started"
      />
    </section>

    <h2>Rooms</h2>
    <div class="panel">
      <p :if={@stats.rooms == []} class="empty">No games running right now.</p>
      <table :if={@stats.rooms != []}>
        <thead>
          <tr>
            <th>Room</th>
            <th>Quiz</th>
            <th>Phase</th>
            <th>Question</th>
            <th>Players</th>
            <th>Connections</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={room <- @stats.rooms}>
            <td><span class="pill live">{room.code}</span></td>
            <td>
              {room.quiz_title}
              <span :if={room.game_number > 1} class="muted">· game {room.game_number}</span>
            </td>
            <td>{room.phase}</td>
            <td>
              <span :if={room.question_number}>{room.question_number} / {room.question_count}</span>
              <span :if={is_nil(room.question_number)} class="muted">—</span>
            </td>
            <td>{room.players}</td>
            <td>{room.connections}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <h2>Library</h2>
    <section class="cards">
      <.stat
        label="Public quizzes"
        value={@stats.library.quizzes}
        hint={"#{@stats.library.presets} presets · #{@stats.library.community} community"}
      />
      <.stat
        label="Questions"
        value={@stats.library.questions}
        hint={"#{@stats.library.photo_questions} with a photo"}
      />
      <.stat
        label="Tags in use"
        value={@stats.library.tags}
        hint={"#{@stats.library.images} uploaded images"}
      />
    </section>

    <h2>Most used tags</h2>
    <div class="panel">
      <p :if={@stats.top_tags == []} class="empty">No tags yet.</p>
      <table :if={@stats.top_tags != []}>
        <tbody>
          <tr :for={tag <- @stats.top_tags}>
            <td>{tag.tag}</td>
            <td class="muted">{tag.count} {if tag.count == 1, do: "quiz", else: "quizzes"}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <h2>Newest quizzes</h2>
    <div class="panel">
      <p :if={@stats.recent == []} class="empty">Nothing published yet.</p>
      <table :if={@stats.recent != []}>
        <tbody>
          <tr :for={quiz <- @stats.recent}>
            <td>
              {quiz.title}
              <span :if={quiz.source == "builtin"} class="pill preset">preset</span>
            </td>
            <td class="muted">{quiz.question_count} questions</td>
            <td class="muted">{Enum.map_join(quiz.quiz_tags, ", ", & &1.tag)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :hint, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <div class="card">
      <div class="label">{@label}</div>
      <div class="value">{@value}</div>
      <div :if={@hint} class="hint">{@hint}</div>
    </div>
    """
  end

  defp phases(by_phase) when map_size(by_phase) == 0, do: "nothing running"

  defp phases(by_phase) do
    Enum.map_join(by_phase, " · ", fn {phase, count} -> "#{count} #{phase}" end)
  end
end
