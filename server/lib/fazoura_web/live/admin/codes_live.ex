defmodule FazouraWeb.Admin.CodesLive do
  @moduledoc """
  Room size codes (ADMIN.md §3.7, PROTOCOL.md §6.5): make one for somebody who needs a
  bigger room, see how many rooms each has unlocked, and revoke one.

  A new code is shown once, on this page, right after it is made: only its hash is
  stored, so it cannot be shown again.
  """

  use FazouraWeb, :live_view

  alias Fazoura.RoomSizeCodes

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page: :codes, made: nil, form: blank()) |> load()}
  end

  defp load(socket), do: assign(socket, codes: RoomSizeCodes.list(), now: DateTime.utc_now())

  defp blank,
    do: to_form(%{"label" => "", "room_size" => "", "max_rooms" => "1", "expires_on" => ""})

  @impl true
  def handle_event("create", params, socket) do
    case RoomSizeCodes.create(attrs(params)) do
      {:ok, plain, code} ->
        {:noreply, socket |> assign(made: {plain, code}, form: blank()) |> load()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(params))
         |> put_flash(:error, describe(changeset))}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    :ok = RoomSizeCodes.revoke(id)

    {:noreply,
     socket |> put_flash(:info, "Revoked. Rooms it already unlocked keep their size.") |> load()}
  end

  def handle_event("dismiss", _params, socket), do: {:noreply, assign(socket, made: nil)}

  # A date means "until the end of that day", in UTC.
  defp attrs(params) do
    expires_at =
      case Date.from_iso8601(params["expires_on"] || "") do
        {:ok, date} -> DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
        {:error, _} -> nil
      end

    %{
      label: params["label"],
      room_size: params["room_size"],
      max_rooms: params["max_rooms"],
      expires_at: expires_at
    }
  end

  defp describe(changeset) do
    Enum.map_join(changeset.errors, "; ", fn {field, {message, opts}} ->
      "#{Phoenix.Naming.humanize(field)} " <>
        Enum.reduce(opts, message, fn {key, value}, text ->
          String.replace(text, "%{#{key}}", to_string(value))
        end)
    end)
  end

  defp status(code, now) do
    cond do
      code.revoked_at -> "revoked"
      code.rooms_used >= code.max_rooms -> "used up"
      code.expires_at && DateTime.compare(code.expires_at, now) != :gt -> "expired"
      true -> "active"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h2>Room size codes</h2>
    <p class="muted">
      A room holds {Fazoura.Game.max_players()} players. A code lets a host raise that, from the
      lobby, for as many rooms as you allow. Give it to whoever needs the bigger room.
    </p>

    <div :if={@made} id="new-code" class="card" style="margin:16px 0">
      <p>
        Code for <strong dir="auto">{elem(@made, 1).label}</strong>
        — {elem(@made, 1).room_size} players, {elem(@made, 1).max_rooms}
        {if elem(@made, 1).max_rooms == 1, do: "room", else: "rooms"}:
      </p>
      <p style="font-size:26px;letter-spacing:.12em;color:var(--ac)" id="new-code-value">
        {elem(@made, 0)}
      </p>
      <p class="muted">Copy it now. It is not stored, so it cannot be shown again.</p>
      <button phx-click="dismiss">Done</button>
    </div>

    <.form for={@form} id="create-code" phx-submit="create" class="panel pad" style="margin:16px 0 24px">
      <div class="fields" style="grid-template-columns:repeat(auto-fit, minmax(min(100%, 320px), 1fr))">
        <label>
          For <span class="muted">— who you are giving it to</span>
          <input
            type="text"
            name="label"
            value={@form[:label].value}
            placeholder="e.g. Sunny School, spring term"
            maxlength="80"
            autocomplete="off"
            dir="auto"
            required
          />
        </label>
        <label>
          Players
          <span class="muted">
            — {RoomSizeCodes.room_sizes().first} to {RoomSizeCodes.room_sizes().last}
          </span>
          <input
            type="number"
            name="room_size"
            value={@form[:room_size].value}
            min={RoomSizeCodes.room_sizes().first}
            max={RoomSizeCodes.room_sizes().last}
            required
          />
        </label>
        <label>
          Rooms <span class="muted">— how many it can unlock</span>
          <input type="number" name="max_rooms" value={@form[:max_rooms].value} min="1" max="10000" />
        </label>
        <label>
          Last day <span class="muted">— optional</span>
          <input type="date" name="expires_on" value={@form[:expires_on].value} />
        </label>
      </div>
      <div style="text-align:center">
        <button class="primary" type="submit">Make a code</button>
      </div>
    </.form>

    <div :if={@codes != []} style="overflow-x:auto">
    <table>
      <thead>
        <tr>
          <th>For</th>
          <th>Code</th>
          <th>Players</th>
          <th>Rooms</th>
          <th>Expires</th>
          <th>Status</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={code <- @codes} id={"code-#{code.id}"}>
          <td dir="auto">{code.label}</td>
          <td style="white-space:nowrap">…{code.hint}</td>
          <td>{code.room_size}</td>
          <td style="white-space:nowrap">{code.rooms_used} / {code.max_rooms}</td>
          <td>{if code.expires_at, do: Calendar.strftime(code.expires_at, "%Y-%m-%d"), else: "never"}</td>
          <td style="white-space:nowrap">{status(code, @now)}</td>
          <td>
            <button
              :if={is_nil(code.revoked_at)}
              phx-click="revoke"
              phx-value-id={code.id}
              data-confirm="Revoke this code? Rooms it already unlocked keep their size."
            >
              Revoke
            </button>
          </td>
        </tr>
      </tbody>
    </table>
    </div>
    <p :if={@codes == []} class="muted">No codes yet.</p>
    """
  end
end
