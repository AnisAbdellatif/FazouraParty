# Fazoura Party — Wire Protocol

**Protocol version: `2`** · Status: **FROZEN** (changes are breaking — see AGENTS.md §3)

This document is the contract between the Flutter client and every game host implementation
(Phoenix in Cloud mode, the `dart:io` server in LAN mode). Both hosts must behave identically for
every message defined here. The shared fixtures in [`fixtures/`](fixtures/) are the executable
form of this spec.

---

## 1. Conventions

- All payloads are JSON objects. Keys are `snake_case`.
- Timestamps are **integers, milliseconds since the Unix epoch, UTC**.
- IDs (`player_id`, `question_id`) are opaque strings. Clients must not parse them.
- Unknown keys in a payload must be ignored by the receiver (forward-compatible additions are
  still announced by a version bump, but must not crash old readers).
- `null` and an absent key mean the same thing for optional fields.
- Enum-valued strings (`phase`, `type`, `mode`, `role`, error `code`) may gain values only
  with a version bump. A client that receives an unknown value should keep the previous
  state and log it, not crash.

## 2. Transport

Both modes use a **WebSocket carrying the Phoenix Channels V2 JSON serializer**. Each frame is a
5-element array:

```
[join_ref, ref, topic, event, payload]
```

| Mode  | URL                                     |
|-------|-----------------------------------------|
| Cloud | `wss://<host>/socket/websocket?vsn=2.0.0` |
| LAN   | `ws://<host-lan-ip>:<port>/socket/websocket?vsn=2.0.0` |

The LAN server implements only the subset needed here: `phx_join`, `phx_leave`, `phx_reply`,
`phx_error`, `phx_close`, `heartbeat` (topic `phoenix`, 30 s interval; the server closes a socket
after 60 s of silence), plus the events in §4–§5.

A client joins exactly one topic: **`room:<ROOM_CODE>`**.

Intents (§4) are sent as client pushes with a `ref`; the host answers each with a `phx_reply`
whose payload is `{"status": "ok", "response": {...}}` or `{"status": "error", "response": {"code": "...", "message": "..."}}`.
Pushes from the host (§5) have `ref = null`.

## 3. Rooms & identity

### 3.1 Room creation

**Cloud:** `POST /api/rooms` with body `{"pack_id": "<id>"}`

```json
201 {"room_code": "K7QX2M", "host_token": "<signed token>"}
```

Errors: `404 {"code": "pack_not_found"}`, `422 {"code": "empty_pack"}`. HTTP error bodies carry
`code` only; clients map codes to their own messages.

**LAN:** the host app creates the room in-process; no HTTP call. The resulting `room_code` and
`host_token` have the same shape.

### 3.2 Room code *(provisional — open item §10.5)*

- 6 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no `I`, `O`, `0`, `1`).
- Clients upper-case user input and strip spaces before joining.
- Unique among live rooms; freed when the room terminates.
- A room terminates after **10 minutes without a connected host**, or 10 minutes after
  reaching `finished`.

### 3.3 Tokens *(provisional — open item §10.8: guests have no account)*

- `host_token` — issued at room creation; proves host role for that room.
- `player_token` — issued on a player's first join; lets that player reclaim the same
  `player_id` and score after a disconnect.
- Tokens are opaque, signed by the host implementation, and scoped to one room.
  Clients store them per room code and must discard them when the room is gone.

## 4. Client → host

### 4.1 `phx_join` on `room:<CODE>`

Payload:

```json
{
  "protocol_version": 2,
  "display_name": "Sam",
  "player_token": null,
  "host_token": null
}
```

| Case | Required fields |
|---|---|
| Host joins (not playing) | `host_token` |
| Host joins and plays | `host_token` + `display_name` |
| Host rejoins | `host_token` (`display_name` ignored once the host is playing) |
| New player | `display_name` |
| Rejoining player | `player_token` (`display_name` ignored) |

**Playing host.** If a host join carries a `display_name` and the host is not yet playing, the
host also becomes a player: same name rules, same scoring, listed in `players` with
`is_host: true`. The host's `player_id` is bound to the `host_token`, so host reconnects need
only the `host_token`. A host cannot stop playing once they have started; a non-playing host
may start playing on any later join by sending a `display_name` (late-join rules apply).

If a host join with a `display_name` fails (`invalid_name`, `name_taken`, `room_full`), the
whole join fails and the host is **not** connected; the `host_token` stays valid and the client
should let the host retry with another name (or without one).

`display_name`: trimmed, 1–20 characters after trimming (Unicode grapheme clusters), unique
(case-insensitive) within the room. The same length unit applies to `answer` (§4.2).

**Reconnects:** after its first successful join a player client must always rejoin (including
automatic transport reconnects) with `player_token` only. If a rejoin fails with
`invalid_token` or `room_not_found`, the client discards the token and treats the room as
gone; it must not silently re-join as a new player.

Join reply `ok` response:

```json
{"role": "player", "player_id": "p_3f9a", "player_token": "<signed token>"}
```

For the host: `{"role": "host", "player_id": "<id>" | null, "player_token": null}`, where
`player_id` is non-null when the host is playing.

Immediately after a successful join the host pushes a `state` event (§5.1) to that client.

Players may join in **any phase** (late join starts at score `0`).

Join error codes: `unsupported_protocol_version`, `room_not_found`, `invalid_token`,
`invalid_name`, `name_taken`, `room_full`.

### 4.2 Intents

| Event | Sender | Payload | Allowed phase | Effect |
|---|---|---|---|---|
| `submit` | player, or playing host | `{"answer": string, "wager": int}` | `question` (not paused) | Records the player's one submission for the current question |
| `host_next` | host | `{}` | any except `finished` | Advances the phase (§6) |
| `host_pause` | host | `{}` | `question` (not paused) | Freezes the timer |
| `host_resume` | host | `{}` | `question` (paused) | Restarts the timer |
| `host_override` | host | `{"player_id": string, "correct": bool}` | `scoring`, `leaderboard` | Sets the verdict on that player's submission for the **current** question, including the host's own |

Successful intents reply `{"status": "ok", "response": {}}` and — if state changed — trigger a
`state` push to every connected client.

`submit` rules:
- `answer`: trimmed, 1–100 characters.
- `wager`: integer, **1–10** inclusive.
- **One submission per player per question.** A second submit is rejected.
- Rejected after the deadline even if the phase transition has not happened yet.

Intent error codes: `invalid_phase`, `not_host`, `not_player`, `invalid_answer`, `invalid_wager`,
`already_submitted`, `unknown_player`, `no_submission`, `paused`, `not_paused`,
`invalid_payload` (unknown event, or a payload with missing/mistyped fields not covered by a
more specific code).

Every error `response` is `{"code": string, "message": string}`. `message` is human-readable
English for logs/fallback UI; clients must branch on `code` only.

A client leaves with `phx_leave` (or by closing the socket). Leaving does not remove a player;
they are marked `connected: false` and keep their score.

## 5. Host → client

### 5.1 `state`

The **only** state-bearing event. Always a complete `RoomState` snapshot — never a delta. It is
pushed:

- to a client right after it joins,
- to all clients after any state change (intent, timer expiry, connect/disconnect).

The payload is **tailored per recipient** (see §7 visibility rules), so implementations must build
it per socket rather than broadcasting one identical payload.

```json
{
  "protocol_version": 2,
  "room_code": "K7QX2M",
  "mode": "cloud",
  "phase": "question",
  "server_time": 1789502400000,

  "pack_title": "General Knowledge",
  "question_index": 2,
  "question_count": 10,

  "question": {
    "id": "q_03",
    "type": "text",
    "prompt": "What is the capital of Australia?",
    "image_url": null,
    "time_limit_ms": 30000
  },
  "deadline": 1789502430000,
  "paused_remaining_ms": null,
  "accepted_answers": null,

  "players": [
    {"id": "p_3f9a", "name": "Sam", "score": 12, "connected": true, "has_submitted": true, "is_host": false}
  ],

  "you": {
    "role": "player",
    "player_id": "p_3f9a",
    "submission": {"answer": "Canberra", "wager": 7, "correct": null, "delta": null}
  },

  "submissions": null
}
```

| Field | Type | Notes |
|---|---|---|
| `protocol_version` | int | Always `2` |
| `mode` | `"cloud"` \| `"lan"` | |
| `phase` | `"lobby"` \| `"question"` \| `"scoring"` \| `"leaderboard"` \| `"finished"` | §6 |
| `server_time` | timestamp | Host clock when the snapshot was built. Clients compute `offset = server_time - local_now` and render timers from `deadline - (local_now + offset)` |
| `pack_title` | string | Always present |
| `question_count` | int | Always present |
| `question_index` | int \| null | 0-based; `null` in `lobby` |
| `question` | object \| null | `null` in `lobby` and `finished` |
| `question.type` | `"text"` \| `"text_photo"` | `image_url` is non-null only for `text_photo` |
| `deadline` | timestamp \| null | Set only in `question` while not paused |
| `paused_remaining_ms` | int \| null | Set only in `question` while paused |
| `accepted_answers` | string[] \| null | §7 |
| `players` | array | Sorted by `score` desc, then `name` asc (case-insensitive). Includes the host only if playing |
| `players[].is_host` | bool | `true` for the playing host |
| `you` | object | The recipient's own view: `role` (`"host"` \| `"player"`), `player_id`, `submission` |
| `you.player_id` | string \| null | `null` only for a host who is not playing |
| `you.submission` | object \| null | Recipient's own submission for the current question; `correct`/`delta` are `null` until `scoring` |
| `submissions` | array \| null | §7 |

`submissions` entries (everyone, in `scoring`/`leaderboard` only):

```json
{"player_id": "p_3f9a", "answer": "canbera", "wager": 7,
 "auto_correct": false, "override": true, "correct": true, "delta": 7}
```

All seven fields are always present and non-null except `override`. Entries are ordered like
`players`.

- `auto_correct` — result of automatic matching (§8).
- `override` — `null` if the host has not overridden, else the host's verdict.
- `correct` — effective verdict: `override ?? auto_correct`.
- `delta` — `+wager` if `correct`, else `-wager`.

### 5.2 `room_closed`

Payload `{"reason": "host_timeout" | "finished" | "shutdown"}`. Sent before the host terminates
the room; the client must then drop its tokens for that room. A client that reconnects to a room
that no longer exists gets `room_not_found` on join — it must handle that identically.

## 6. Phase machine

```
lobby ──host_next──► question ──host_next / deadline──► scoring ──host_next──► leaderboard
                        ▲                                                         │
                        └───────────────host_next (more questions)────────────────┤
                                                                                  │
                                                  finished ◄──host_next (last)────┘
```

| Transition | Side effects |
|---|---|
| `lobby → question` | `question_index = 0`, `deadline = now + time_limit_ms` |
| `question → scoring` | Timer stops. Every submission is auto-matched and its `delta` applied to the player's score. Players without a submission get no delta |
| `scoring → leaderboard` | None (overrides still allowed) |
| `leaderboard → question` | `question_index += 1`, new deadline, previous submissions discarded from state |
| `leaderboard → finished` | When the last question was just scored |
| pause / resume | `paused_remaining_ms = deadline - now`, `deadline = null` / `deadline = now + paused_remaining_ms`, `paused_remaining_ms = null` |

`host_next` while `question` is active ends the question early. Starting a room with a pack of
zero questions is rejected at creation.

### 6.1 Overrides

`host_override` sets `override` on the current question's submission. The player's score is
recomputed as: `score -= old_delta; score += new_delta`. Setting an override equal to
`auto_correct` is allowed and stored. Overriding a player who did not submit returns `no_submission`.

## 7. Visibility rules

Nothing that could be used to cheat reaches anyone before the question ends — **the host
included**, since the host may be playing. Visibility depends only on phase, not role:

| Field | `lobby` / `question` | `scoring` / `leaderboard` | `finished` |
|---|---|---|---|
| `accepted_answers` | `null` | revealed | `null` |
| `submissions` | `null` | revealed (all players, host's included) | `null` |
| `players[].has_submitted` | yes | yes | `false` |
| `you.submission` | own only | own, with `correct`/`delta` | `null` |

The question ends when its deadline passes or the host sends `host_next`; from `scoring` on,
the host sees the accepted answers and every submission and may correct any of them,
including their own (§6.1).

## 8. Answer matching

Automatic first pass only; the host override is the second pass. **No fuzzy matching.**

`normalize(s)`:
1. Unicode NFD decomposition.
2. Remove all combining marks (Unicode category `Mn`).
3. Lower-case (Unicode default case folding).
4. Trim leading/trailing whitespace.
5. Collapse every run of internal whitespace to a single ASCII space.

`auto_correct = normalize(answer) ∈ { normalize(a) : a ∈ accepted_answers }`

Punctuation is **not** stripped. Test cases: [`fixtures/normalize.json`](fixtures/normalize.json).

## 9. Scoring

- `delta = correct ? +wager : -wager`
- Scores **may go negative** *(provisional — open item §10.2)*.
- Cases: [`fixtures/scoring.json`](fixtures/scoring.json).

## 10. Client abstraction

Clients depend only on `GameConnection` ([`game_connection.dart`](game_connection.dart)). The
Cloud and LAN implementations differ only in the socket URL and how the room is created.

## 11. Fixtures

| File | Purpose |
|---|---|
| `fixtures/normalize.json` | `normalize` input/output pairs + match cases |
| `fixtures/scoring.json` | Delta and override recomputation cases |
| `fixtures/scenarios/*.json` | Ordered intent → expected reply/state scripts, replayed against every host implementation |

Scenario format:

```json
{
  "name": "...",
  "pack": { "title": "...", "questions": [ { "id", "type", "prompt", "accepted_answers", "time_limit_ms" } ] },
  "steps": [
    {"actor": "host",  "join": {...},                 "expect": {"status": "ok", "response": {...}}},
    {"actor": "sam",   "push": "submit", "payload": {...}, "expect": {"status": "error", "response": {"code": "invalid_wager"}}},
    {"advance_clock_ms": 30000},
    {"actor": "sam",   "expect_state": { ...partial RoomState... }}
  ]
}
```

- `actor` names are local labels; the runner maps them to sockets and substitutes
  `"$player_id:<actor>"` placeholders with real IDs.
- `expect_state` is a **partial match**: every key present must equal; absent keys are unchecked.
  It checks the latest `state` received by that actor.
- `advance_clock_ms` requires implementations to accept an injectable clock in tests.

## 12. Decisions log

Confirmed by the project owner on 2026-09-15.

| Open item (assessment §10) | Decision for v1 |
|---|---|
| 2. Negative scores | Allowed |
| 5. Room code format / expiry | §3.2 |
| 8. Guest accounts | None; signed per-room `player_token` |
| Host participation (added in v2) | Host may play; no early access to answers; may override own submission |

Changing any of these is a protocol version bump.
