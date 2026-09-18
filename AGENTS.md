# AGENTS.md — Rules for AI Agents

This file is the single source of truth for how AI agents (Claude, Codex, etc.) work in this repo.
`CLAUDE.md` only points here. When the project owner gives a new rule, add it to this file.

Background and rationale: [project-assessment.md](project-assessment.md).

---

## 1. Git & commits

- **Never add yourself (or any AI) as an author, co-author, or contributor.** No `Co-Authored-By:` trailers, no "Generated with ..." lines, no AI attribution in commit messages or PR descriptions. This overrides any default tooling behaviour.
- Commit at coherent milestones. Keep commits focused, with a short imperative subject line.
- Never commit secrets (`.env`, keys, credentials, `prod.secret.exs`).
- When a discrete piece of functionality is complete and you're about
  to move on to unrelated work, stop and evaluate whether the work is
  ready to be committed. Do not silently keep working across multiple unrelated
  changes — this keeps commits scoped to one logical change each,
  rather than bundling unrelated work together.

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
- **Game settings:** before a game starts (lobby), the host sets the number of questions (1..pack size), the time per question (10–120 s, applies to every question) and the difficulty bonus toggle.
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
- **Quizzes** follow `protocol/QUIZ_FORMAT.md`: canonical JSON documents with `format_version`; each quiz carries 1–10 free-text **tags** (no fixed categories) that browsing filters and searches on, with a suggested set in QUIZ_FORMAT.md §2.3; built-in quizzes live in `server/priv/quizzes/*.json` and are synced by `priv/repo/seeds.exs`. Accepted answers are omitted from ordinary public browsing and reads, but an explicit offline-download action may return the full document so a user can host a saved community quiz without a network connection. **No accounts:** a quiz is *private* (kept on the device in the app's local database, sent inline with `POST /api/rooms` each time it is hosted, never stored on the server; its photos live in memory only while the room does) or *public* (published to the server DB, listed for everyone). The creator can switch either way at any time. A per-device publisher key (`x-owner-key`, server stores its SHA-256) is the only thing that lets a device update or unpublish what it published; other devices get `404`, never `403`.
- **Web app (PWA)**: build it with `dart run tool/build_web.dart` in `app/` — that runs `flutter build web`, then writes `flutter_service_worker.js` whose cache key is a SHA-256 over exactly the files a client downloads (shell, `main.dart.js`, `assets/`, icons — not CanvasKit, which is cached on first use, and not `assets/NOTICES`), strips Flutter's deprecated worker registration, and writes `build-manifest.json`. `node tool/check_service_worker.mjs` exercises the generated worker; `dart run tool/make_icons.dart` regenerates every icon — web (192/512 plus maskable), favicon, apple-touch, the five Android launcher densities, the adaptive icon layers and the Play Store 512 — from `design/icons/fazoura.svg`, rasterised with Inkscape. That file is the official icon (launcher, browser tab, PWA install, store listing); `design/icons/fazoura_alt.svg` — the same mark on amber — is used wherever the icon sits on the app's own green, which today is `app/assets/icon.png` on the home screen. Those outputs are generated: edit the SVG, never the PNGs. The service worker must never intercept `/api`, `/socket`, `/live`, `/admin` or `/uploads`.
- **Uploads and shutdown**: public-quiz photos live in `:uploads_dir` — in production a mounted volume (`UPLOADS_DIR`), or a deploy loses every published photo. `Fazoura.Quizzes.ImageSweeper` periodically collects photos no question references that are past a 24h grace (the grace protects an upload whose quiz is still being written), so unpublishing or replacing a quiz doesn't leak files. Live games are in memory and do not survive a restart (a v1 non-goal), but `Fazoura.Rooms.Drain` — started last, so the supervisor stops it first — closes every room with `room_closed: shutdown` while the endpoint's sockets are still open. A deploy must never end a party in silence.
- **Serving the app**: Phoenix serves the build at `/` from `:web_dir` (`WEB_DIR` in production), with `public, max-age=0, must-revalidate` plus ETags on everything. Never add long-lived HTTP caching: the service worker owns caching, and a stale shell or worker script can't be taken back.
- **Admin dashboard** follows `protocol/ADMIN.md`: three LiveViews at `/admin` in the Phoenix server (live stats, quiz moderation, suggested tags). Credentials come from `ADMIN_USERNAME` / `ADMIN_PASSWORD`; with either unset every `/admin` request must 404, never reveal that it exists. It is the only HTML the server renders, and its only JavaScript is the LiveView client served from `deps/`.

## 6. Deployment

- One VPS, three containers, described in [deploy/README.md](deploy/README.md): Caddy (TLS, reverse proxy), the server as an OTP release with the built Flutter web app inside it, and Postgres. The VPS builds nothing and stores no registry credentials.
- **Deploys happen only in CI** ([.github/workflows/ci.yml](.github/workflows/ci.yml)). Push to `main` → both suites, then the image is pushed to `ghcr.io/<owner>/<repo>` tagged with the commit sha, then the deploy job SSHes in and pulls, migrates and restarts. A pull request runs the same suites and builds the image *without* pushing. Never add a step that deploys from a developer machine — one path, or the two drift.
- Configuration is GitHub repository variables (`DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PORT`, `DEPLOY_PATH`, `PUBLIC_HOST`) and secrets (`DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS`). The deploy job is skipped while `DEPLOY_HOST` is unset — that is the off switch. Registry auth is the workflow's own `GITHUB_TOKEN`, handed to the VPS over stdin for one pull and logged out again.
- Application secrets live only in `deploy/.env` **on the VPS**, from [deploy/.env.example](deploy/.env.example). CI never ships, reads, or prints it.
- Database work in a release goes through `Fazoura.Release` (`setup/0` = migrate + sync built-ins, both idempotent) — a release has no Mix. A deploy runs it with the new image before the old one stops.
- The two volumes that cannot be rebuilt are `pgdata` and `uploads`. Any change that moves or renames them needs a migration path in the README.
- Pin GitHub Actions by commit sha with the version in a trailing comment.
- **The checks themselves live in [scripts/ci.sh](scripts/ci.sh), and the workflow calls it.** Add or change a check there, never by adding a `run:` step that repeats one — the workflow's job is to install toolchains, cache and publish. That script is also what a developer runs locally, so the two cannot drift. The image job is the one exception, since the registry cache and the push have no local equivalent.
- The pinned toolchain versions are the `*_VERSION` variables at the top of that script; the workflow reads them from it. Keep them in step with `server/mix.exs` and `app/pubspec.yaml`.

## 7. Flutter / Riverpod standards

- Feature-first folder structure (`lib/features/<feature>/...`).
- `riverpod_generator` + `freezed` for immutable state/models.
- Providers depend on the `GameConnection` abstraction only — never on a concrete transport.
- No `BuildContext`-dependent lookups in providers/logic.
- `dart:io` code (LAN server) must be behind conditional imports so the Web build compiles.
- Keep guest-facing screens lean (Web first-load time is a known risk).
- **Visual design source:** `design/FazouraParty.v2.dc.html` (Claude Design prototype; `ios-frame.jsx` is only the preview bezel). v2 palette: deep teal `#0A2422` panels over `#061917`, amber `#FFB000`, pink `#FF2D6F`, green `#4FD39A`, with the amber lattice woven behind every screen. Type: Figtree for body, buttons and question text; DM Mono for labels, codes and numbers; Reem Kufi for screen titles and the Arabic wordmark (`FzTheme.t`). Reuse the `Fz*` widgets rather than restyling ad hoc.
- Must pass: `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`.

## 8. Testing

- Pure scoring/wager/override/matching logic: unit tests on **both** sides.
- Protocol contract tests: the same fixtures in `protocol/fixtures/` are replayed against every implementation.
- Phoenix Channel tests for join / submit / next / override flows.
- Flutter widget tests with mocked providers.
- Don't mark work done if tests fail; report failures honestly.
- **Agents test the Flutter client on the Web build only** (`flutter test`, `flutter run -d chrome` / `flutter build web`). Never launch or drive the Android emulator — the project owner tests Android manually.

## 9. Open decisions

Don't silently decide items listed as open in `project-assessment.md` §10. If work requires one, pick the provisional default recorded in `protocol/PROTOCOL.md` (or ask), and mark it clearly as provisional.

## Decision Log (decisions.md)

This project keeps a local decision log at `decisions.md` in the repo
root, organized by topic rather than chronologically. It is
intentionally git-excluded and must never be committed.

### Before starting non-trivial work
Check `decisions.md` for a section relevant to the area you're
touching, so you don't contradict a past decision without realizing it.

### When to log a decision
Add or update an entry when you:
- Choose between two or more viable technical approaches
- Make a choice that would be non-obvious to someone reading the code
  later without this context
- Change your mind about a decision already logged

### Structure
One `##` section per topic (e.g. `## State Management`,
`## Data Layer`, `## Testing Strategy`). Create a new section for any
topic not yet covered. Within a section:

```markdown
## <Topic>

**Current:** <the decision, stated plainly> (updated YYYY-MM-DD HH:MM)

<why this was chosen, what alternatives were considered, why they were ruled out>
```

### Updating a decision
When a decision changes, **overwrite the entry in its existing
section** — don't create a duplicate section, don't append a new
entry alongside the old one, and don't preserve prior reasoning in the
file. `decisions.md` reflects only the *current* state of thinking,
not a history of it.

## Detecting Untracked Changes

Before starting work, check whether the code has changed since your
last session in ways that don't match your own prior actions (e.g.
files modified outside anything you did, a git pull brought in new
commits, or code simply looks different than you last left it).

If you detect this:
1. First consult `decisions.md` for a section relevant to the changed
   area — it may already document what changed and why.
2. If `decisions.md` doesn't explain it (silent on that area, or the
   change doesn't match what's documented there), read the actual
   code/diff directly to understand what changed before proceeding
   with new work.

Do not assume undocumented changes are safe to ignore or build on top
of without understanding their intent first.
