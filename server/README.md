# Fazoura Party — server

Elixir/Phoenix game host. Implements [`../protocol/PROTOCOL.md`](../protocol/PROTOCOL.md),
serves the quiz library, the admin dashboard, and — when `WEB_DIR` is set — the built
Flutter web app itself, so the whole game lives on one origin.

## Run

```bash
mix setup        # deps.get, create the database, migrate, seed the built-in quizzes
mix phx.server   # http://localhost:4000
```

SQLite in dev and test, Postgres in production (`config :fazoura, :repo_adapter`), so
there is nothing to install locally. Migrations and queries must stay portable across
both — no Postgres-only SQL or types.

## Surface

| | |
|---|---|
| `GET /health` | liveness, used by the container healthcheck |
| `POST /api/rooms` | `{"quiz_id": "..."}` or `{"quiz": {…}}` for a private quiz sent inline → `{room_code, host_token}` |
| `GET/POST/PUT/DELETE /api/quizzes[/:id]` | the public library; writes need the publisher's `x-owner-key` |
| `GET /api/tags`, `POST /api/images` | tag suggestions, photo upload |
| `ws://…/socket/websocket?vsn=2.0.0` | topic `room:<CODE>` — the game itself |
| `/admin` | LiveView dashboard: live stats, quiz moderation, suggested tags |

`/admin` returns **404** unless both `ADMIN_USERNAME` and `ADMIN_PASSWORD` are set; it
never advertises that it exists. Built-in quizzes live in `priv/quizzes/*.json` and are
upserted by `mix run priv/repo/seeds.exs` (and by every deploy).

## Checks

```bash
mix precommit    # compile --warnings-as-errors, format, credo --strict, test
mix dialyzer
```

`mix test` replays the shared scenarios in [`../protocol/fixtures/`](../protocol/fixtures/)
against the channel, so the server and the client are held to the same contract.

## Layout

| Path | Role |
|---|---|
| `lib/fazoura/game.ex` | Pure game logic: intents, phases, scoring, per-recipient views. No processes. |
| `lib/fazoura/game/answer.ex` | Answer normalization and matching |
| `lib/fazoura/rooms.ex`, `rooms/room_server.ex` | One GenServer per room: clock, connections, timers |
| `lib/fazoura/rooms/images.ex` | Private-quiz photos, in memory for exactly as long as the room |
| `lib/fazoura/rooms/drain.ex` | Closes live rooms out loud when the server is shutting down |
| `lib/fazoura/quizzes.ex` | The library: publishing, tags, inline quizzes, orphaned-photo collection |
| `lib/fazoura/admin.ex`, `lib/fazoura_web/live/admin/` | The dashboard |
| `lib/fazoura/release.ex` | Migrations and seeding for a built release, where Mix does not exist |
| `lib/fazoura_web/channels/room_channel.ex` | Wire adapter: events ↔ intents. No game logic. |

## Configuration

Everything production reads comes from the environment ([`config/runtime.exs`](config/runtime.exs)):
`SECRET_KEY_BASE`, `DATABASE_URL`, `PHX_HOST`, `PORT`, `WEB_DIR`, `UPLOADS_DIR`,
`ADMIN_USERNAME`, `ADMIN_PASSWORD`, `CORS_ORIGINS`. See [`../deploy/`](../deploy/).
