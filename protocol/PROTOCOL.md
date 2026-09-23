# Fazoura Party — Wire Protocol

**Protocol version: `9.4`** · Status: **FROZEN** (see AGENTS.md §3 and §1 below)

This document is the contract between the Flutter client and every game host implementation
(Phoenix in Cloud mode, the `dart:io` server in LAN mode). Both hosts must behave identically for
every message defined here. The shared fixtures in [`fixtures/`](fixtures/) are the executable
form of this spec.

---

## 1. Conventions

### 1.1 Versioning

The protocol is versioned `major.minor`, and **only the major is on the wire**:
`protocol_version` in a join and in every `RoomState` is the major, and the server reports
its minor alongside as `protocol_minor`.

| | Changes | Effect on a client |
|---|---|---|
| **major** | A message, field or value a client already relies on is changed or removed | Cutover. A host refuses a join whose major differs, with `unsupported_protocol_version` |
| **minor** | Anything a correct client of that major already copes with: a new host-side rule, a field it may ignore, a new optional payload key | None. Old and new clients both play |

A host accepts any client sharing its major, whatever the minor — a phone that has not taken
an update yet must not be thrown out of a party over a difference it does not need to know
about. Both host implementations must be on the same `major.minor`: the minor is what tells
you whether a LAN host built from an older tag behaves exactly like the cloud.

Ending a question as soon as everyone has answered (§6) is the example to reason from. A
client already has to handle the question ending at any moment, because `host_next` ends it —
so nothing a client does needed to change, and it was a minor.

A cloud-only HTTP route is a minor too, for the same reason: a client that has never heard
of it simply does not call it. `GET /api/rooms/:code` (§3.1) was 9.2 and
`POST /api/rooms/:code/report` is 9.3.

9.4 changed what `host_next` does to a running question: rather than scoring it on the spot,
the host pulls its `deadline` in to a short closing window (§6). A client already renders
whatever deadline the latest snapshot carries, so nothing had to change there either.

**This is semver's major and minor, and there is deliberately no patch.** The number
exists to answer one question — does this host behave exactly like that one? — and the
minor already answers it. A patch would mean "behaviour changed but nothing was added",
which a reader still has to compare before trusting two hosts to agree, so it would be a
third number carrying nothing the minor does not. A fix that brings an implementation in
line with the spec it already claimed to follow is a minor: from the outside, the host now
does something it did not do before, and that is exactly what a minor means here. A change
with no observable effect at all — a typo, a clearer sentence, renumbered sections — moves
neither number, because there is nothing for a reader to compare.

- All payloads are JSON objects. Keys are `snake_case`.
- Timestamps are **integers, milliseconds since the Unix epoch, UTC**.
- IDs (`player_id`, `question_id`) are opaque strings. Clients must not parse them.
- Unknown keys in a payload must be ignored by the receiver. Adding one is a minor bump
  precisely because an old reader is required to ignore it rather than crash.
- `null` and an absent key mean the same thing for optional fields.
- Enum-valued strings (`phase`, `type`, `mode`, `role`, error `code`) may gain values with a
  minor bump, because a client that receives an unknown value is required to keep the
  previous state and log it rather than crash. Changing or removing an existing value is a
  major.

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

**Cloud:** `POST /api/rooms` with an empty body to create the room before choosing anything.
The host then selects the quizzes to play in the lobby with `host_select_quiz` (§6.4).

For backwards compatibility the endpoint also accepts a **single** quiz body and snapshots it
immediately: `{"quiz_id": "<uuid or built-in slug>"}` for a stored (public) quiz (`pack_id` is
accepted as a legacy alias), or `{"quiz": <quiz document>}` for a private quiz kept on the
host's device, sent inline with base64 photos and never stored (QUIZ_FORMAT.md §4, §5.7). The
room snapshots that one quiz and starts with its `default_settings`. Selecting several is only
possible through `host_select_quiz`.

```json
201 {"room_code": "K7QX2M", "host_token": "<signed token>"}
```

Errors: `404 {"code": "quiz_not_found"}` (unknown quiz id), `422 {"code": "invalid_quiz"}`
(inline quiz fails validation), `413 image_too_large` / `415 unsupported_image` (inline
photos), `422 {"code": "empty_pack"}`. HTTP error bodies carry `code` and `message`; clients branch on
`code` only.

**LAN:** the host app creates the room in-process; no HTTP call. The resulting `room_code` and
`host_token` have the same shape.

#### `GET /api/rooms/:code` — is the room I remember still there?

A host's device keeps its `host_token` for as long as the token is valid (§3.3), and a room
can be gone long before that: 30 seconds after the last person leaves, or the moment the
host's connection drops with anybody else connected, which hands the role on and retires
the token. So a device that remembers hosting a room asks before offering to take it back.

The token travels in an **`x-host-token` header**, not the path, so it stays out of access
logs. Cloud only; a LAN host never stored a token to ask about.

```json
200 {"room_code": "K7QX2M", "phase": "question", "players": 4}
404 {"code": "room_not_found"}
```

`404` covers every no: there is no such room, the room has ended, the token was never
valid, or the role has since moved on. A caller without the room's *current* host token is
never told that a room exists, so this cannot be used to find live games by guessing codes.

A client must treat only a `404` as "forget this room". A request that failed to complete
means the answer is unknown, and a remembered room is worth more than a network blip.

#### `POST /api/rooms/:code/report` — this is not okay

A player only ever sees a quiz's questions and photos inside a game, so that is where
reporting one has to be possible. The room maps the question to the quiz it was
snapshotted from; **no quiz id is ever broadcast**, which is deliberate — one during a
game would let any player fetch the accepted answers (QUIZ_FORMAT.md §5.3a).

A token this room issued is required (§3.3), in `x-player-token` or `x-host-token`, so
this cannot be used to find live games by guessing codes. Cloud only, like the route
above: a LAN host is playing something that was never published.

The body, the answers and the reasons are QUIZ_FORMAT.md §5.9.

### 3.2 Room code *(provisional — open item §10.5)*

- 6 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no `I`, `O`, `0`, `1`).
- Clients upper-case user input and strip spaces before joining.
- Unique among live rooms; freed when the room terminates.
- A room terminates when it is **empty for 30 seconds** (§3.4), or 10 minutes after
  reaching `finished`.

### 3.3 Tokens *(provisional — open item §10.8: guests have no account)*

- `host_token` — issued at room creation; proves host role for that room. **Only the
  current one works:** every transfer or promotion (§3.4) issues a new token and the
  previous one is refused with `invalid_token`, so a former host cannot take the room back.
- `player_token` — issued on a player's first join; lets that player reclaim the same
  `player_id` and score after a disconnect. Unaffected by host changes.
- Tokens are opaque, signed by the host implementation, and scoped to one room.
  Clients store them per room code and must discard them when the room is gone.

### 3.4 The host role

Exactly one connection holds the host role, and the room keeps it filled while anyone is
still there:

- **Transfer.** The host may hand the role to any connected player with `host_transfer`
  (§4.2). The room issues that player a new `host_token`, delivered in their next `state`
  as `you.host_token` (§5.1) — it is sent only to the player who now holds it.
- **Promotion.** If the host's connection drops and does not return, a connected player is
  promoted at random and issued a new token the same way. A room therefore never sits
  hostless while players remain.
- **Handover is immediate.** A host who transfers deliberately loses the role at once. A
  host who merely disconnects is replaced only if someone else is connected.
- **Empty rooms end.** With nobody connected the room closes after **30 seconds**, with
  `room_closed: empty`. The delay is what lets a lone host survive a brief network drop,
  and gives a freshly created room time for its first join.

A host that is also playing keeps its `player_id`, score and submissions when it loses the
role; it simply becomes an ordinary player.

## 4. Client → host

### 4.1 `phx_join` on `room:<CODE>`

Payload:

```json
{
  "protocol_version": 9,
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
| `submit` | player, or playing host | `{"answer": string}` | `question` (not paused) | Records the player's one submission for the current question |
| `host_next` | host | `{}` | any except `finished` | Advances the phase (§6). During `question`, closes the question rather than ending it outright |
| `host_pause` | host | `{}` | `question` (not paused) | Freezes the timer |
| `host_resume` | host | `{}` | `question` (paused) | Restarts the timer |
| `host_override` | host | `{"player_id": string, "correct": bool}` | `scoring`, `leaderboard` | Sets the verdict on that player's submission for the **current** question, including the host's own |
| `host_configure` | host | `{"question_count": int, "time_limit_ms": int, "difficulty_multiplier": bool, "difficulties": ["easy"\|"medium"\|"hard", ...]}` | `lobby` | Sets the game settings (§6.2). The difficulty list must be non-empty and selects the questions eligible for the round |
| `host_select_quiz` | host | `{"quizzes": [{"quiz_id": string} \| {"quiz": object}, ...]}` | `lobby` | Selects or replaces the quizzes played this round (§6.4); resets lobby settings to the first one's defaults |
| `host_rematch` | host | `{}` | `finished` | Starts a new game in the same room (§6.3) |
| `host_transfer` | host | `{"player_id": string}` | any | Hands the host role to a connected player (§3.4) |
| `host_close` | host | `{}` | any | Ends the room now: every client gets `room_closed: closed` |

Successful intents reply `{"status": "ok", "response": {}}` and — if state changed — trigger a
`state` push to every connected client.

`submit` rules:
- `answer`: trimmed, 1–100 characters.
- **One submission per player per question.** A second submit is rejected.
- Rejected after the deadline even if the phase transition has not happened yet.

Intent error codes: `invalid_phase`, `not_host`, `not_player`, `invalid_answer`,
`already_submitted`, `unknown_player`, `no_submission`, `paused`, `not_paused`,
`invalid_settings` (question count outside 1..`max_question_count`, time limit outside
`min_time_limit_ms`..`max_time_limit_ms`, or any field missing or of the wrong type),
`not_connected` (`host_transfer` naming a player who is not currently connected, or the
host itself), `invalid_payload` (unknown event, or a payload with missing/mistyped fields
not covered by a more specific code).

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
  "protocol_version": 9,
  "protocol_minor": 3,
  "room_code": "K7QX2M",
  "mode": "cloud",
  "phase": "question",
  "server_time": 1789502400000,

  "pack_titles": ["General Knowledge", "Film & TV"],
  "question_index": 2,
  "question_count": 10,
  "game_number": 1,
  "settings": {
    "question_count": 10,
    "time_limit_ms": 30000,
    "difficulty_multiplier": false,
    "difficulties": ["easy", "medium", "hard"],
    "max_question_count": 10,
    "min_time_limit_ms": 10000,
    "max_time_limit_ms": 120000
  },

  "question": {
    "id": "q_03",
    "type": "text",
    "prompt": "What is the capital of Australia?",
    "image_url": null,
    "time_limit_ms": 30000,
    "difficulty": "easy",
    "points": {"right": 10, "wrong": -10, "skipped": -10}
  },
  "deadline": 1789502430000,
  "paused_remaining_ms": null,
  "accepted_answers": null,

  "players": [
    {"id": "p_3f9a", "name": "Sam", "score": 12, "connected": true, "has_submitted": true, "is_host": false, "avatar_hue": 212}
  ],

  "you": {
    "role": "player",
    "player_id": "p_3f9a",
    "host_token": null,
    "submission": {"answer": "Canberra", "correct": null, "delta": null}
  },

  "submissions": null
}
```

| Field | Type | Notes |
|---|---|---|
| `protocol_version` | int | The host's major — `9` (§1.1) |
| `protocol_minor` | int | Which revision of that major the host implements. A client may ignore it |
| `mode` | `"cloud"` \| `"lan"` | |
| `phase` | `"lobby"` \| `"question"` \| `"scoring"` \| `"leaderboard"` \| `"finished"` | §6 |
| `server_time` | timestamp | Host clock when the snapshot was built. Clients compute `offset = server_time - local_now` and render timers from `deadline - (local_now + offset)` |
| `pack_titles` | string[] | Titles of the selected quizzes, in the order the host chose them. Empty while none are selected (§6.4) |
| `question_count` | int | Questions in the current game; always equals `settings.question_count` |
| `game_number` | int | 1 for the first game in the room, +1 on every rematch. Question ids repeat across games, so clients key per-question UI state on (`game_number`, `question_index`) |
| `settings` | object | Always present. `question_count`, `time_limit_ms` (applied to every question, overriding the pack), `difficulty_multiplier` (bool — difficulty scoring on/off, §9), `difficulties` (selected question difficulties), `available_difficulties` (difficulty values present in the pack), plus the bounds `max_question_count` (number of questions matching the selected difficulties), `min_time_limit_ms`, `max_time_limit_ms` |
| `question_index` | int \| null | 0-based; `null` in `lobby` |
| `question` | object \| null | `null` in `lobby` and `finished` |
| `question.type` | `"text"` \| `"text_photo"` | `image_url` is non-null only for `text_photo` |
| `deadline` | timestamp \| null | Set only in `question` while not paused |
| `paused_remaining_ms` | int \| null | Set only in `question` while paused |
| `accepted_answers` | string[] \| null | §7 |
| `players` | array | Sorted by `score` desc, then `name` asc (case-insensitive). Includes the host only if playing |
| `players[].is_host` | bool | `true` for the playing host |
| `players[].avatar_hue` | int | 0–359. Picked at random by the host implementation when the player is added, kept as far as possible from hues already in the room; stable for the player's lifetime so every client shows the same colour |
| `question.difficulty` | `"easy"` \| `"medium"` \| `"hard"` | From the pack; `"easy"` when the pack doesn't say |
| `question.points` | object | What this question is worth: `{"right": int, "wrong": int, "skipped": int}` (§9). Clients display these; they never compute them |
| `you` | object | The recipient's own view: `role` (`"host"` \| `"player"`), `player_id`, `host_token`, `submission` |
| `you.player_id` | string \| null | `null` only for a host who is not playing |
| `you.host_token` | string \| null | Non-null **only** in the snapshot that follows a transfer or promotion, and only to the recipient who now holds the role (§3.4). The client replaces its stored token with it; every other client sees `null` |
| `you.submission` | object \| null | Recipient's own submission for the current question; `correct`/`delta` are `null` until `scoring`. From `scoring` on it is also present with `answer: null` for a player who was asked and did not answer, carrying the skip penalty as its `delta` |
| `submissions` | array \| null | §7 |

`submissions` entries (everyone, in `scoring`/`leaderboard` only):

```json
{"player_id": "p_3f9a", "answer": "canbera",
 "auto_correct": false, "override": true, "correct": true, "delta": 25}
```

There is one entry per player the question was **asked** of — everyone in the room when it
started, whether or not they answered — ordered like `players`. A player who joined
mid-question has no entry. All fields are always present and non-null except `override` and
`answer`.

- `answer` — `null` for a player who let the question go by; `delta` is then the skip
  penalty (§9) and `correct` is `false`.
- `auto_correct` — result of automatic matching (§8); `false` when there is no answer.
- `override` — `null` if the host has not overridden, else the host's verdict.
- `correct` — effective verdict: `override ?? auto_correct`.
- `delta` — what this question did to the player's score (§9).

### 5.2 `room_closed`

Payload `{"reason": "empty" | "closed" | "finished" | "shutdown"}`. Sent before the host
terminates the room; the client must then drop its tokens for that room. A client that reconnects
to a room that no longer exists gets `room_not_found` on join — it must handle that identically.

| Reason | Meaning |
|---|---|
| `empty` | Nobody was connected for 30 seconds (§3.4) |
| `closed` | The host ended the room with `host_close` |
| `finished` | 10 minutes passed after the game finished |
| `shutdown` | The host implementation is stopping (a deploy) |

`host_timeout` was removed in v5: a room whose host leaves now promotes someone rather than
waiting to die (§3.4).

## 6. Phase machine

```
lobby ──host_next──► question ──host_next / deadline / all answered──► scoring ──host_next──► leaderboard
                        ▲                                                         │
                        └───────────────host_next (more questions)────────────────┤
                                                                                  │
                                                  finished ◄──host_next (last)────┘
```

| Transition | Side effects |
|---|---|
| `lobby → question` | `question_index = 0`, `deadline = now + settings.time_limit_ms` |
| `question → scoring` | Timer stops. Every submission is auto-matched and its `delta` applied to the player's score. Players without a submission get no delta |
| `question → scoring` (all answered) | Same. Triggered the moment nobody is left to wait for — see below |
| `scoring → leaderboard` | None (overrides still allowed) |
| `leaderboard → question` | `question_index += 1`, new deadline, previous submissions discarded from state |
| `leaderboard → finished` | When question `settings.question_count` was just scored |
| `finished → lobby` | `host_rematch` (§6.3) |
| pause / resume | `paused_remaining_ms = deadline - now`, `deadline = null` / `deadline = now + paused_remaining_ms`, `paused_remaining_ms = null` |

`host_next` while `question` is active ends the question early, but not on the spot: the
question is **closed**. `deadline` becomes `now + 3000` (the **closing window**), or stays
where it is if that is sooner, and a paused question resumes into it. Submissions are accepted
until the new deadline as before, and the question still ends the moment nobody is left to
wait for. The window exists because a client sends a typed-but-unlocked answer on its own
shortly before the deadline — ending a question outright would throw away every answer still
being typed. `host_next` on a question already closing changes nothing, so a second tap cannot
cut the window short. If everyone asked has already answered or is gone past the grace below,
there is nobody to wait for and the question is scored at once.

Starting a room with a pack of zero questions is rejected at creation.

**A question also ends as soon as there is nobody left to wait for**: every player it was
asked of has either submitted or been disconnected for longer than a **5 s grace**. The grace
is what keeps a locked screen or a walk past a thick wall from costing someone their question —
a dropped socket is not an answer. At least one submission is required, so a room everybody
has wandered away from runs its clock down rather than racing through the pack unattended. A
paused question never ends this way.

The host's own clock is unchanged: `deadline` is still the absolute time the question would
end on its own, and a client must not assume it will get there.

### 6.1 Overrides

`host_override` sets `override` on the current question's submission. The player's score is
recomputed as: `score -= old_delta; score += new_delta`. Setting an override equal to
`auto_correct` is allowed and stored. Overriding a player who did not submit returns `no_submission`.

### 6.2 Game settings

- The maximum number of questions per game is the size of the selected pool: `max_question_count`
  = the number of questions across every selected quiz that match `settings.difficulties` (§6.4).
- Defaults when the room is created: `question_count` = `max_question_count`,
  `difficulty_multiplier` = `false`, `time_limit_ms` = the
  first question's limit clamped to 10 000–120 000 ms.
- `host_configure` is accepted only in `lobby` (before the first question, or after a
  rematch). Settings persist across rematches until changed.
- Every question uses `settings.time_limit_ms`; per-question pack limits are ignored.

### 6.3 Rematch

`host_rematch` in `finished` returns the room to `lobby` without creating a new room:

- every player's `score` = 0; players, connection state, host and tokens are kept;
- `game_number += 1`, `question_index = null`, submissions cleared;
- the selection is cleared: the room returns to an empty lobby and the host chooses what to
  play next with `host_select_quiz` (§6.4);
- the room's finished-expiry (§3.2) is cancelled.

### 6.4 Selected quizzes

A round is played from a **pool**: one or more quizzes the host chose, merged into a single
shuffled list of questions. `host_select_quiz` (§4.2) carries the whole selection each time and
replaces whatever was selected before; there is no "add one more" intent. Each entry is either a
stored quiz (`quiz_id`) or a full inline document (`quiz`), and one selection may mix the two —
a host can play a published quiz alongside one that never leaves their device.

- **1 to 10 quizzes.** More is `invalid_quiz`, as is an empty list or a malformed entry. An
  unknown `quiz_id` is `quiz_not_found`. A selection whose questions come to zero is `empty_pack`.
- **Questions are drawn from the whole pool.** They are shuffled together once per round, so a
  round of 10 questions over three quizzes takes 10 at random from all of them rather than a
  fixed share of each. Selecting the same quiz twice is pointless but harmless: it is one pool,
  and duplicates simply make those questions likelier.
- **Lobby settings come from the first quiz selected** — its `default_settings` — because a pool
  has no defaults of its own. `question_count` resets to the pool size.
- **Question ids are made unique within the pool.** Two quizzes may each call a question `q1`;
  ids are opaque (§1), so hosts are free to rewrite them, and must, because clients use them to
  tell one question from the next.
- `pack_titles` (§5.1) lists the selected titles in order, so clients can name the round.

## 7. Visibility rules

Nothing that could be used to cheat reaches anyone before the question ends — **the host
included**, since the host may be playing. Visibility depends only on phase, not role:

| Field | `lobby` / `question` | `scoring` / `leaderboard` | `finished` |
|---|---|---|---|
| `accepted_answers` | `null` | revealed | `null` |
| `submissions` | `null` | revealed (all players, host's included) | `null` |
| `players[].has_submitted` | yes | yes | `false` |
| `you.submission` | own only | own, with `correct`/`delta` | `null` |

The question ends when its deadline passes, including the closing window after the host sends
`host_next` (§6); from `scoring` on,
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

There is no wager. A question is worth a fixed number of points set by its difficulty, and
a wrong answer costs **more** on an easy question than on a hard one.

| `settings.difficulty_multiplier` | difficulty | right | wrong | no answer |
|---|---|---|---|---|
| `true` | easy | **+10** | **−15** | **−10** |
| `true` | medium | **+25** | **−10** | **−10** |
| `true` | hard | **+50** | **−5** | **−10** |
| `false` | any | **+10** | **−10** | **−10** |

- You are expected to know the easy ones, so guessing at one is expensive; a hard one is
  cheap to attempt. Saying nothing costs 10 whatever the difficulty, so silence is never
  the cheapest way out of a hard question — and on easy questions it beats a wrong guess.
- The values are fixed per question when the player submits (settings can't change
  mid-game), and host overrides recompute with the same numbers.
- The skip penalty applies to every player who was in the room when the question started
  and did not answer, connected or not. A player who **joined mid-question** is not
  charged: they never saw it.
- Not-answering cannot be overridden (`no_submission`, §7).
- `question.points` carries all three numbers to the client, which never computes them.
- Scores **may go negative** *(provisional — open item §10.2)*.
- Cases: [`fixtures/scoring.json`](fixtures/scoring.json).

## 10. Client abstraction

Clients depend only on `GameConnection` ([`game_connection.dart`](game_connection.dart)). The
Cloud and LAN implementations differ only in the socket URL and how the room is created.
At the start of each round, the selected quizzes are merged into one pool and shuffled once;
all players then see that same shuffled order for the round (§6.4).

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
    {"actor": "sam",   "push": "submit", "payload": {...}, "expect": {"status": "error", "response": {"code": "invalid_answer"}}},
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
| Game settings & rematch (added in v3) | Host sets question count (1..pack) and per-question time (10–120 s) in the lobby; host-triggered rematch keeps the room and players, resets scores, continues through the pack |
| Avatars, pack-sized rounds, difficulty bonus (added in v4) | Server-assigned random avatar hues; up to the selected pack size per game; optional difficulty multiplier easy ×1 / medium ×2 / hard ×3, off by default |
| Host role (added in v5) | Transferable to a connected player, and passed on automatically if the host drops; each change issues a fresh `host_token` and invalidates the old one; a room with nobody in it ends after 30 s rather than lingering for the old 10-minute host timeout |

| Several quizzes per round (added in v8) | The host selects 1–10 quizzes and the round draws its questions at random from all of them merged into one pool; `pack_title` became `pack_titles` |

| Wagers removed (added in v9) | No wager: a question scores by difficulty (easy +10 / −15, medium +25 / −10, hard +50 / −5), letting one go by costs 10, and `settings.difficulty_multiplier` now switches difficulty scoring on and off rather than a multiplier |

Changing any of these is a protocol version bump.
