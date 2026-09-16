# Trivia Party App — Project Assessment

*Status: pre-implementation · Last revised: 15 Sep 2026*

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
- **Custom packs:** owner-editable, private by default.
- **Sharing:** a pack can be shared to a specific user (read-only copy or reference — flag as open item).
- **Community library:** curated + community-submitted packs across categories. Requires a submission → review → publish flow and a report button; without moderation this becomes a liability quickly.

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
- **Phoenix Presence** tracks connected players and handles disconnect/reconnect with almost no custom code.
- **Crash isolation:** one room's GenServer crashing does not affect other rooms. A supervisor restarts it; state is lost for that room (acceptable for a party game, but reconnecting clients must handle "room gone").
- **Room lifecycle:** RoomServer terminates after N minutes with no host presence, freeing the room code.

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
| Presence | Phoenix Presence | Solves join/leave/reconnect tracking. |
| Persistence | Postgres via Ecto | Only for durable content; rooms never touch the DB during play. |
| Images | Object storage needed | **Gap in the original plan.** Text+photo questions need upload, resize, and serving. Options: a local volume behind Caddy on the VPS (simple, fine for v1) or S3-compatible storage (MinIO/Backblaze) if packs are shared widely. |
| Auth | Phoenix-generated auth (`mix phx.gen.auth`) for pack creators; signed anonymous tokens for guests | Avoid building auth by hand. |

### 5.3 Hosting & Ops
- Single **Docker image** (multi-stage build → Elixir release), deployed on the existing VPS.
- **Caddy** terminates TLS and reverse-proxies `wss://` to the Phoenix container. Caddy handles WebSocket upgrade automatically.
- Postgres as a second container (`docker compose`) with a volume; nightly `pg_dump` to off-box storage.
- Single node is sufficient for v1; Phoenix PubSub works on one node without any extra setup. Multi-node clustering is a later concern.

---

## 6. Data Model

**Postgres (durable)**
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
| 4 | Reconnect/late-join edge cases (phone locks, Wi-Fi drops) | High | Medium | Presence + full state resync on rejoin; every broadcast is a complete `RoomState`, never a delta. |
| 5 | Timer desync between clients | Medium | Low | Broadcast a server deadline timestamp, not a countdown; clients render locally. |
| 6 | Community content moderation | Medium | High (reputational) | Submission review queue, report button, owner-only publish until reviewed. |
| 7 | Image storage/scaling not planned | Certain | Medium | Decide storage in §5.2 before building the pack editor. |
| 8 | LAN mixed-content blocks browser guests | Certain | Medium | Android-only guests for LAN in v1.1; host-served HTTP page later. |
| 9 | Solo maintainer, hand-managed VPS | — | Medium | Docker + compose, backups, health checks; keep the deploy to one command. |

---

## 8. Recommended Phasing

**Phase 0 — Contract (1–2 weeks)**
Define the `GameConnection` interface and the JSON message protocol (event names, payloads, `RoomState` shape). Write it down; treat changes as breaking.

**Phase 1 — Cloud MVP**
Phoenix backend (rooms, channels, presence, scoring, override), Postgres schema, Flutter host + player screens, text questions only, one built-in pack. Deploy to VPS. **This is a playable product.**

**Phase 2 — Content**
Accounts, pack editor, text+photo questions with image storage, pack sharing, community library with review flow.

**Phase 3 — LAN mode (v1.1)**
`LanGameConnection` + `dart:io` server on Android, Android-app guests only. Run the shared contract tests against it.

**Phase 4 — Polish**
Host-served web client for LAN browser guests, iOS enablement, performance work on the web bundle.

---

## 9. Engineering Standards

- **Flutter/Riverpod:** feature-first folder structure, `riverpod_generator` + `freezed` for immutable state, no `BuildContext`-dependent lookups, providers consume `GameConnection` only.
- **Elixir:** `mix format`, `credo`, `dialyzer` in CI; game logic in pure functions (`RoomState.apply(event)`) with the GenServer as a thin shell, so scoring is unit-testable without processes.
- **Tests:**
  - Pure scoring/wager/override logic — unit tests on both sides.
  - Protocol contract tests — same fixtures replayed against Phoenix and LAN implementations.
  - Phoenix Channel tests for join/submit/next/override flows.
  - Flutter widget tests with mocked providers; one integration test for a full two-player round.
- **CI/CD (GitHub Actions):** on PR → both suites (format, lint, test, dialyzer; analyze, test), the web bundle, the service-worker harness, and an image build that is not pushed. On `main` → the same, then push the image to ghcr.io tagged with the commit sha and deploy to the VPS over SSH (pull, migrate, `compose up --wait`), finishing with a smoke check against `/health`. See [.github/workflows/ci.yml](.github/workflows/ci.yml) and [deploy/README.md](deploy/README.md).

---

## 10. Open Items

1. Freeze the `GameConnection` interface and wire protocol (blocks everything).
2. Negative scores: allow or floor at zero?
3. Pack sharing semantics: copy vs. reference; can recipients re-share?
4. Image storage: local volume vs. S3-compatible; max size and resize policy.
5. Room code format and collision/expiry policy.
6. Community moderation workflow and who reviews.
7. Web renderer decision after first load-time profiling.
8. Whether guests need any account at all, or purely a signed session token.
