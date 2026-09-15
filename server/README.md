# Fazoura Party — server

Elixir/Phoenix game host for Cloud mode. Implements [`../protocol/PROTOCOL.md`](../protocol/PROTOCOL.md).

## Run (Phase 1, no database)

```bash
mix setup        # deps.get
mix phx.server   # http://localhost:4000
```

- `GET  /health`
- `POST /api/rooms {"pack_id": "general-knowledge"}` → `{room_code, host_token}`
- WebSocket: `ws://localhost:4000/socket/websocket?vsn=2.0.0`, topic `room:<CODE>`

Built-in packs live in `priv/packs/<id>.json`.

## Checks

```bash
mix format --check-formatted
mix credo --strict
mix dialyzer
mix test
```

`mix test` replays the shared scenarios in `../protocol/fixtures/scenarios/` against the channel.

## Layout

| Path | Role |
|---|---|
| `lib/fazoura/game.ex` | Pure game logic: intents, phases, scoring, per-recipient views |
| `lib/fazoura/game/answer.ex` | Answer normalization/matching |
| `lib/fazoura/rooms.ex`, `rooms/room_server.ex` | One GenServer per room (clock, connections, timers) |
| `lib/fazoura_web/channels/room_channel.ex` | Wire adapter: events ↔ intents |
| `lib/fazoura_web/controllers/room_controller.ex` | Room creation |
