# AGENTS.md — Rules for AI Agents

This file is the single source of truth for how AI agents (Claude, Codex, etc.) work in this repo.
`CLAUDE.md` only points here. When the project owner gives a new rule, add it to this file.

Background and rationale: [project-assessment.md](project-assessment.md).

---

## 1. Git & commits

- **Never add yourself (or any AI) as an author, co-author, or contributor.** No `Co-Authored-By:` trailers, no "Generated with ..." lines, no AI attribution in commit messages or PR descriptions. This overrides any default tooling behaviour.
- Commit at coherent milestones. Keep commits focused, with a short imperative subject line.
- Never commit secrets (`.env`, keys, credentials, `prod.secret.exs`).

## 2. Project shape

- Monorepo layout:
  - `protocol/` — wire protocol spec + shared JSON fixtures (the contract).
  - `server/` — Elixir/Phoenix backend.
  - `app/` — Flutter client (Android + Web; iOS scaffolded only).
- **Stack is decided:** Flutter + Riverpod (client), Elixir/Phoenix + Postgres/Ecto (backend), Docker on a VPS behind Caddy. Do not introduce alternative frameworks without explicit approval.
- **Scope:** Cloud mode first (Phase 1). LAN mode is v1.1 — keep the seam, don't build it early. iOS, monetization, and game-state persistence across restarts are non-goals for v1.

## 3. The protocol contract (most important rule)

- `protocol/PROTOCOL.md` and the `GameConnection` interface are **frozen contracts**. Any change is a breaking change: bump the protocol version, update the spec, the fixtures, and *both* sides in the same change.
- Never add a transport-specific message or payload. Cloud (Phoenix) and LAN implementations must speak the identical contract.
- Every state broadcast is a **complete `RoomState` snapshot, never a delta**.
- Timers are broadcast as an absolute **server deadline timestamp**, never a countdown.

## 4. Server authority & game rules

- **The server is authoritative.** Clients send intents only (`join`, `submit`, `next_question`, `override`, ...). All validation — wager range, phase, host permissions, one submission per question — happens server-side. Never trust client-computed scores or correctness.
- Wager is an integer 1–10. Correct → `+wager`, incorrect → `−wager`.
- **Game settings:** before a game starts (lobby), the host sets the number of questions (1..min(pack size, 20)), the time per question (10–120 s, applies to every question) and the difficulty bonus toggle.
- **Difficulty bonus:** pack questions have a difficulty (easy/medium/hard). With the toggle on, points are wager × 1 / 2 / 3; off (default), wager × 1.
- **Avatar colours** are random, assigned by the server per player (spread apart within a room), so every device shows the same colour for the same player. Clients must not derive colours locally.
- **Rematch:** after a game finishes, the host can start a new game in the same room — same players and settings, scores reset, continuing through the pack. No new room is created.
- Answer matching v1: normalize (trim, collapse whitespace, case-fold, strip diacritics) then exact match against `accepted_answers`. **No fuzzy/Levenshtein matching.** Host override is the second pass.
- Host overrides re-apply score deltas immediately and trigger a full `RoomState` re-broadcast.
- Pack questions are **snapshotted at room start**; rooms never read or write the DB during play.
- **The host may also play** (joins with a display name). Because of that, nobody — host included — sees accepted answers or other players' submissions before the question ends (deadline or host ends it). From scoring on, the host sees the correct answers and can override any submission, including their own.

## 5. Elixir / Phoenix standards

- Game logic lives in **pure functions** (e.g. `Game.apply(state, event)`); the per-room `GenServer` is a thin shell. Scoring must be unit-testable without processes.
- One `RoomServer` GenServer per room, under a `DynamicSupervisor`, looked up via `Registry`.
- One Channel topic per room (`room:<CODE>`). The Channel is a transport adapter only — no game logic.
- Connection tracking: the `RoomServer` monitors each joined channel process and derives `connected` from that. (Chosen over Phoenix Presence because state views are per-recipient and the LAN host must mirror the behaviour exactly; revisit Presence only if rooms go multi-node.)
- Time is injected (`now` function option), never read directly inside game logic, so timer behaviour is testable.
- Use `mix phx.gen.auth` for accounts; signed tokens for anonymous guests. Don't hand-roll auth.
- Must pass: `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`, `mix test` (`mix precommit` runs most of these).
- **Database:** Ecto with **SQLite locally (dev/test)** and **Postgres in production** (`config :fazoura, :repo_adapter`). Migrations and queries must be portable across both: no Postgres-only SQL or types, string enums validated in changesets, no defaults on array columns. DB tests use `async: false` (SQLite sandbox).
- **Quizzes** follow `protocol/QUIZ_FORMAT.md`: canonical JSON documents with `format_version`; built-in quizzes live in `server/priv/quizzes/*.json` and are synced by `priv/repo/seeds.exs`. Accepted answers are only ever returned to the publishing device. **No accounts:** a quiz is *private* (kept on the device in the app's local database, sent inline with `POST /api/rooms` each time it is hosted, never stored on the server; its photos live in memory only while the room does) or *public* (published to the server DB, listed for everyone). The creator can switch either way at any time. A per-device publisher key (`x-owner-key`, server stores its SHA-256) is the only thing that lets a device update or unpublish what it published; other devices get `404`, never `403`.

## 6. Flutter / Riverpod standards

- Feature-first folder structure (`lib/features/<feature>/...`).
- `riverpod_generator` + `freezed` for immutable state/models.
- Providers depend on the `GameConnection` abstraction only — never on a concrete transport.
- No `BuildContext`-dependent lookups in providers/logic.
- `dart:io` code (LAN server) must be behind conditional imports so the Web build compiles.
- Keep guest-facing screens lean (Web first-load time is a known risk).
- **Visual design source:** `design/FazouraParty.dc.html` (Claude Design prototype; `ios-frame.jsx` is only the preview bezel). Follow its look — palette, Figtree + DM Mono type, spacing, components — but not its game mechanics: gameplay (typed answers, 1–10 wager, 6-char codes, host overrides) comes from `protocol/PROTOCOL.md`. Screens in the design without backend support (pack picker, profile) may exist as clearly-marked mocks.
- Must pass: `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`.

## 7. Testing

- Pure scoring/wager/override/matching logic: unit tests on **both** sides.
- Protocol contract tests: the same fixtures in `protocol/fixtures/` are replayed against every implementation.
- Phoenix Channel tests for join / submit / next / override flows.
- Flutter widget tests with mocked providers.
- Don't mark work done if tests fail; report failures honestly.
- **Agents test the Flutter client on the Web build only** (`flutter test`, `flutter run -d chrome` / `flutter build web`). Never launch or drive the Android emulator — the project owner tests Android manually.

## 8. Open decisions

Don't silently decide items listed as open in `project-assessment.md` §10. If work requires one, pick the provisional default recorded in `protocol/PROTOCOL.md` (or ask), and mark it clearly as provisional.
