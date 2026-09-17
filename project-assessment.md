# Trivia Party App — Project Assessment

*Status: Cloud mode shipped (Phases 0–2); LAN mode is the next milestone · Last revised: 18 Sep 2026*

> **How to read this document.** It was written before implementation as a plan, and is kept
> because the reasoning behind the shape of the project is still worth having. Several of its
> guesses were overtaken by decisions taken during the build — most visibly **accounts, which
> do not exist**: a quiz is private on the device or published anonymously with a per-device
> key (AGENTS.md §5). Where a section has been superseded it says so inline.
>
> For what is actually true today, the binding sources are
> [AGENTS.md](AGENTS.md) (rules), [protocol/PROTOCOL.md](protocol/PROTOCOL.md) (the frozen
> contract, v4) and the [README](README.md) (status). §11 below records what is built.

## 1. Summary

A real-time, host-driven trivia party game in the style of Sporcle Party, targeting **Android and Web** at launch. A host runs the room, players join from their own devices, answer each question with a confidence wager, and a live leaderboard tracks the party.

Two hosting modes are planned: **Cloud** (our backend owns the game) and **LAN** (an Android device hosts locally, no internet). Cloud mode is the primary path and covers almost all real-world use; LAN mode is a differentiator with a real but bounded cost.

**Decided stack:** Flutter + Riverpod on the client, Elixir/Phoenix on the backend, Postgres via Ecto, deployed as a Docker container on a personal VPS behind Caddy.

**Overall verdict:** the scope is coherent and the stack fits the problem well. The main risks are (a) building two transport implementations in v1, (b) Flutter Web load time for browser guests, and (c) underestimating the "boring" parts — answer matching, reconnects, image storage, content moderation. Recommendation: ship **Cloud-only MVP first**, keep the LAN seam in the architecture from day one, and implement LAN hosting as a v1.1 milestone.

---

## 2. Goals & Non-Goals

**Goals (v1)**
- Host creates a room, dozens of players join by code/link.
- Host controls pacing and can override correctness of any submission.
- Confidence wager scoring (1–10 points per question), validated server-side.
- Live leaderboard.
- Text and text+photo questions.
- Custom packs, pack sharing between users, and a community pack library.

**Non-goals (v1)**
- iOS support (scaffolded only; no testing or store presence).
- Browser-hosted LAN rooms (impossible with WebSockets; WebRTC path rejected for v1 — see §4).
- Game state surviving a server restart.
- Real-money, ads, or monetization features.

---

## 3. Feature Specification

### 3.1 Rooms
| Aspect | Decision |
|---|---|
| Creation | Host picks **Cloud** or **LAN** mode and a pack |
| Join | Short room code (e.g. `ABC123`); web guests can also use a link |
| Capacity | Dozens of players per room; Phoenix handles this trivially, LAN host is the practical limit |
| Identity | Guests are anonymous (display name only); accounts needed only to create/share packs |

### 3.2 Host controls
- Advance to next question, pause/resume timer.
- See all submissions per question.
- Toggle any submission correct ↔ incorrect (typos, spelling variants, ambiguous phrasing). Score deltas re-apply immediately and the leaderboard re-broadcasts.

### 3.3 Gameplay
- **Wager:** player sets 1–10 before/with their answer. Correct → +wager, incorrect → −wager. Scores may go negative (decide: floor at 0 or allow negatives — flag as open item).
- **Answer matching:** automatic first pass (case/whitespace/diacritic normalization + accepted-answer list), host override as the second pass. No fuzzy/Levenshtein matching in v1 — it creates arguments faster than it settles them; the host override covers the same ground.
- **Leaderboard:** updated after each question is scored, pushed to all clients.
- **Question types:** `text`, `text_photo`.

### 3.4 Content

> **Superseded.** This section assumed accounts. There are none, so "owner" became *this
> device* and "sharing to a user" became *publish to everyone*. What shipped:
>
> - **Custom quizzes:** written on the device, stored in its local database, private by
>   default. Hosting a private quiz sends it inline with `POST /api/rooms`; the server never
>   stores it (AGENTS.md §5, QUIZ_FORMAT.md §5.7).
> - **Publishing:** a quiz is private *or* public, switchable at any time. A per-device
>   publisher key (`x-owner-key`) is the only thing that lets a device update or unpublish
>   what it published; other devices get `404`, never `403`.
> - **No per-user sharing.** Without accounts there is no one to share *to*; publishing is the
>   sharing mechanism. Open item §10.3 is answered by being removed.
> - **Free-text tags, not fixed categories** (QUIZ_FORMAT.md §2.3): 1–10 per quiz, which
>   browsing filters and searches on.
> - **Moderation is admin-only and after the fact** — see §10.6, still open.

---

## 4. Architecture

### 4.1 Cloud mode (default, all platforms)

```
Flutter client (Android / Web)
        │  Phoenix Channel  (topic: room:ABC123)
        ▼
Phoenix endpoint ──► RoomServer (GenServer, one per active room)
                          │  ephemeral: question index, timer, players, scores, submissions
                          ▼
                     Postgres (Ecto): users, packs, questions, shares
```

- **Server is authoritative.** Clients only send intents (`join`, `submit`, `next_question`, `override`); the RoomServer validates and broadcasts resulting state. The wager mechanic makes this non-negotiable — a client-trusted implementation is trivially cheatable.
- ~~**Phoenix Presence** tracks connected players.~~ **Not used.** The `RoomServer` monitors each
  joined channel process and derives `connected` from that. State views are per-recipient, and
  the LAN host has to mirror the behaviour exactly; Presence earns its keep across nodes, which
  a single-node party game does not have (AGENTS.md §5).
- **Crash isolation:** one room's GenServer crashing does not affect other rooms. It is
  `restart: :temporary`, so it is *not* restarted — an empty room is worse than none, and
  clients get `room_not_found` and show "the party ended".
- **Room lifecycle:** the room closes 10 minutes after the host disconnects, and 10 minutes
  after it finishes, freeing the room code.

### 4.2 LAN mode (Android host only)

- Android app starts a local WebSocket server via `dart:io`; guests (Android app or browser) connect to `ws://<host-LAN-IP>:<port>`.
- **Why Android-only:** browsers are network clients only — a web page cannot open a listening socket. This is a platform constraint, not a design preference.
- **Same protocol, same game logic:** the LAN server implements the identical message contract as the Phoenix Channel, so gameplay UI and Riverpod providers are mode-agnostic.
- **Mixed-content caveat:** an HTTPS-served web client cannot open a plain `ws://` connection to a LAN IP. Options, in order of preference:
  1. LAN-mode guests use an **Android app** (no browser involved) — simplest, ship this first.
  2. The Android host **serves the web client itself** over plain HTTP on the LAN (`http://<host-ip>:<port>`), so origin and socket are both insecure and no mixed-content rule triggers. Requires bundling the Flutter Web build into the Android app (size cost) and a QR code/join link for discovery.
  3. Self-signed certificates — rejected; the UX of installing certs on guest phones is a non-starter.

### 4.3 The connection seam (key design decision)

```dart
abstract class GameConnection {
  Stream<RoomState> get state;
  Future<void> join(String roomCode, String displayName);
  Future<void> submit(String answer, int wager);
  Future<void> hostNext();
  Future<void> hostOverride(String playerId, bool correct);
  Future<void> leave();
}
```

Two implementations: `PhoenixGameConnection` and `LanGameConnection`. Riverpod providers depend on the abstraction only. **This interface — and the wire protocol behind it — must be specified and frozen before either implementation starts.** It is the single most important artifact to produce next.

---

## 5. Tech Stack

### 5.1 Client — Flutter
| Aspect | Decision | Assessment |
|---|---|---|
| Platforms | Android + Web; iOS scaffolded | Sound. Keep iOS builds compiling in CI so it stays "nearly free". |
| State | Riverpod (code-gen, `AsyncNotifier`/`StreamProvider`) | Good fit for stream-driven state; testable without a socket. |
| Web renderer | CanvasKit / WASM | **Risk.** Browser guests joining via link are the most latency-sensitive users and hit a multi-MB first load. Profile early; keep the guest screens minimal; consider the HTML renderer or a separate lightweight join page if load time exceeds ~3 s on mobile data. |
| Phoenix client | `phoenix_socket` (pub.dev) or hand-rolled channel client | Evaluate `phoenix_socket` first; write our own only if reconnect/heartbeat behaviour is inadequate. |
| LAN server | `dart:io` `HttpServer` + `WebSocketTransformer` | Straightforward; must be conditionally imported so the Web build compiles. |

### 5.2 Backend — Elixir / Phoenix
| Aspect | Decision | Assessment |
|---|---|---|
| Realtime | Phoenix Channels, one topic per room | Exactly the intended use of Channels; minimal custom plumbing. |
| Room state | GenServer per room under a `DynamicSupervisor`, looked up via `Registry` | Standard pattern; crash isolation for free. |
| Presence | ~~Phoenix Presence~~ → process monitoring | **Changed.** See §4.1. |
| Persistence | Postgres in production, **SQLite in dev/test** | Only for durable content; rooms never touch the DB during play. SQLite locally means no database to install; queries must stay portable. |
| Images | **Resolved:** local volume (`UPLOADS_DIR`) | Client downscales to 1280 px and re-encodes as JPEG before upload; the server type- and size-checks, and `ImageSweeper` collects photos no question references past a 24 h grace. The volume must be mounted, or a deploy loses every published photo. |
| Auth | ~~`mix phx.gen.auth`~~ → **none** | **Changed.** No accounts at all: signed per-room `player_token`/`host_token` for play, a hashed per-device `x-owner-key` for quiz ownership. The only credentials are `ADMIN_USERNAME`/`ADMIN_PASSWORD` for `/admin`. |

### 5.3 Hosting & Ops
- Single **Docker image** (multi-stage build → Elixir release), deployed on the existing VPS.
- **Caddy** terminates TLS and reverse-proxies `wss://` to the Phoenix container. Caddy handles WebSocket upgrade automatically.
- Postgres as a second container (`docker compose`) with a volume; nightly `pg_dump` to off-box storage.
- Single node is sufficient for v1; Phoenix PubSub works on one node without any extra setup. Multi-node clustering is a later concern.

---

## 6. Data Model

**Postgres (durable)**

> **Superseded.** No `users` and no `pack_shares`: there are no accounts, so ownership is a
> hashed per-device key on the quiz itself. The real schema is five tables
> (`server/priv/repo/migrations/`), and SQLite stands in for Postgres in dev and test:
>
> ```
> quizzes         id, slug, format_version, title, description, language, source,
>                 visibility (private|public), owner_key_hash, default_time_limit_ms,
>                 default_difficulty_multiplier, question_count, has_photos, timestamps
> quiz_questions  id, quiz_id, position, type (text|text_photo), prompt,
>                 accepted_answers, difficulty (easy|medium|hard), image_key, timestamps
> quiz_tags       id, quiz_id, position, tag
> images          id, key, byte_size, content_type, ...  (uploaded question photos)
> app_settings    key, value                             (suggested tags, admin state)
> ```

*Original plan, for reference:*
```
users        id, email, password_hash, display_name, inserted_at
packs        id, owner_id, title, category, visibility (private|shared|community),
             status (draft|published|flagged), question_count, inserted_at
questions    id, pack_id, position, type (text|text_photo), prompt,
             accepted_answers (text[]), image_key (nullable)
pack_shares  pack_id, shared_with_user_id, inserted_at
```

**In-memory per RoomServer (ephemeral)**
```
room_code, host_id, mode, pack_snapshot (questions copied at room start)
phase            (lobby | question | scoring | leaderboard | finished)
question_index, timer_deadline
players          %{player_id => %{name, score, connected?}}
submissions      %{player_id => %{answer, wager, auto_correct?, override}}
```

*Snapshotting the pack at room start* means an owner editing a pack mid-game can't corrupt a running room.

---

## 7. Risk Assessment

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | Two transport implementations doubles surface area and drifts | High | High | Freeze the protocol first; shared contract tests run against both implementations; ship Cloud-only MVP. |
| 2 | Flutter Web first-load too slow for link-joining guests | Medium | High | Profile in week 1; lean guest screens; renderer fallback plan. |
| 3 | Answer-matching disputes ruin the party mood | Medium | Medium | Normalized exact match + host override; no fuzzy match in v1. |
| 4 | Reconnect/late-join edge cases (phone locks, Wi-Fi drops) | High | Medium | Process monitoring (not Presence, see §4.1) + full state resync on rejoin; every broadcast is a complete `RoomState`, never a delta. |
| 5 | Timer desync between clients | Medium | Low | Broadcast a server deadline timestamp, not a countdown; clients render locally. |
| 6 | Community content moderation | Medium | High (reputational) | Submission review queue, report button, owner-only publish until reviewed. |
| 7 | ~~Image storage/scaling not planned~~ **Resolved** | Certain | Medium | Local `UPLOADS_DIR` volume, client-side downscale, server type/size checks, `ImageSweeper` for orphans. |
| 8 | LAN mixed-content blocks browser guests | Certain | Medium | Android-only guests for LAN in v1.1; host-served HTTP page later. |
| 9 | Solo maintainer, hand-managed VPS | — | Medium | Docker + compose, backups, health checks; keep the deploy to one command. |

---

## 8. Recommended Phasing

**Phase 0 — Contract · done**
`GameConnection` and the wire protocol are written down and frozen at **v4**
([PROTOCOL.md](protocol/PROTOCOL.md)). Changes are breaking and bump the version.

**Phase 1 — Cloud MVP · done**
Rooms, channels, scoring, wagers, host override, pause/resume, rematch, difficulty bonus,
server-assigned avatar hues; Flutter host and player screens; built-in quiz; deployed from CI.

**Phase 2 — Content · done, minus moderation**
Quiz editor, text+photo questions with image storage, the public library with tags and search,
and an admin dashboard. Diverged from the plan: **no accounts**, so no per-user sharing — see
§3.4. The review queue and report button were *not* built (§10.6).

**Phase 3 — LAN mode (v1.1) · next**
`LanGameConnection` + `dart:io` server on Android, Android-app guests only. The seam exists and
the protocol is shaped for it; nothing of the LAN side is written yet. The shared fixtures must
be replayed against it, as they now are against both the server and the client.

**Phase 4 — Polish**
Host-served web client for LAN browser guests, iOS (not scaffolded — there is no `app/ios/`),
performance work on the web bundle.

---

## 9. Engineering Standards

- **Flutter/Riverpod:** feature-first folder structure, `riverpod_generator` + `freezed` for immutable state, no `BuildContext`-dependent lookups, providers consume `GameConnection` only.
- **Elixir:** `mix format`, `credo`, `dialyzer` in CI; game logic in pure functions (`RoomState.apply(event)`) with the GenServer as a thin shell, so scoring is unit-testable without processes.
- **Tests:**
  - Pure scoring/wager/override logic — unit tests on both sides.
  - Protocol contract tests — the same `protocol/fixtures/` replayed against every
    implementation: the Phoenix channel scenario-by-scenario, the Flutter client against the
    wire shape it decodes and encodes, and the LAN host when it exists.
  - Phoenix Channel tests for join/submit/next/override flows.
  - Flutter widget tests with mocked providers; one integration test for a full two-player round.
- **CI/CD (GitHub Actions):** on PR → both suites (format, lint, test, dialyzer; analyze, test), the web bundle, the service-worker harness, and an image build that is not pushed. On `main` → the same, then push the image to ghcr.io tagged with the commit sha and deploy to the VPS over SSH (pull, migrate, `compose up --wait`), finishing with a smoke check against `/health`. See [.github/workflows/ci.yml](.github/workflows/ci.yml) and [deploy/README.md](deploy/README.md).

---

## 10. Open Items

Decisions confirmed during the build are logged in [PROTOCOL.md §12](protocol/PROTOCOL.md).

| # | Item | Status |
|---|---|---|
| 1 | Freeze the `GameConnection` interface and wire protocol | **Closed** — frozen at v4 |
| 2 | Negative scores: allow or floor at zero? | **Closed** — negatives allowed |
| 3 | Pack sharing semantics | **Dropped** — no accounts, so nothing to share *to*; publishing replaced it (§3.4) |
| 4 | Image storage and resize policy | **Closed** — local `UPLOADS_DIR` volume; client downscales to 1280 px JPEG (§5.2) |
| 5 | Room code format and collision/expiry policy | **Closed** — PROTOCOL.md §3.2 |
| 6 | Community moderation workflow and who reviews | **Open** — the one content risk still unaddressed. Today anything published is public immediately; the admin dashboard can only take it down afterwards. No review queue, and no way for a player to report a quiz. |
| 7 | Web renderer decision after load-time profiling | **Open** — never profiled. Risk #2 stands unmeasured. |
| 8 | Whether guests need any account at all | **Closed** — none; signed per-room `player_token` |

### Also outstanding

- **LAN mode is unimplemented** (Phase 3). `LanGameConnection` is named in the interface docs
  but does not exist; only `PhoenixGameConnection` does.
- **No join-by-link or QR.** §3.1 assumed web guests could follow a link; joining is
  code-entry only, which is the slowest path for exactly the guests who matter most.
- **iOS is not scaffolded.** §5.1 assumed an `app/ios/` kept compiling in CI; there is no
  such directory and no iOS job.

---

## 11. What exists today

Cloud mode works end to end and is deployed from CI.

| Area | State |
|---|---|
| Protocol v4 | All 7 intents and both server events implemented on **both** sides |
| Gameplay | Wagers, scoring, negatives, difficulty bonus, host override, pause/resume, rematch, avatar hues |
| Rooms | GenServer per room, monitored connections, host-timeout and finished expiry, drain-on-shutdown |
| Quizzes | Local editor, private inline hosting, publish/unpublish via `x-owner-key`, tags, search, photos |
| Admin | Three LiveViews at `/admin`; 404s unless both credentials are set |
| Deploy | Image built and pushed by CI, VPS restarted over SSH; `pgdata` and `uploads` are the volumes that matter |
| Tests | 134 server, 100 client; shared fixtures replayed against both |

Not built: LAN mode, accounts, moderation review/reporting, join links, iOS, and games that
survive a restart (a deliberate v1 non-goal).
